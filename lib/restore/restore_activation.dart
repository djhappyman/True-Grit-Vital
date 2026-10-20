import 'dart:convert';
import 'dart:io';

import '../data/record_store.dart';
import '../domain/backup/backup.dart';
import '../domain/restore/restore.dart';

/// File-level replacement with a recoverable previous dataset.
///
/// Invariants:
/// - the staged snapshot is verified with the installation key before the live
///   file is touched;
/// - the previous live file is copied and verified before the journal is
///   written;
/// - the live file is replaced by one atomic rename, so it never disappears;
/// - the journal is advanced before and after replacement, and startup
///   recovery completes or rolls back from the file that actually opens.
final class RestoreActivation {
  RestoreActivation({
    required this.databasePath,
    DateTime Function()? clock,
    this.checkpoint,
  }) : _clock = clock ?? (() => DateTime.now().toUtc());

  final String databasePath;
  final DateTime Function() _clock;

  /// Test-only process checkpoint. Throwing or exiting here simulates process
  /// death; production callers leave it null.
  final Future<void> Function(RestoreJournalPhase phase)? checkpoint;

  String get restoreDirectory =>
      '${File(databasePath).parent.path}/${RestoreLimits.restoreDirectory}';

  File get _staged => File('$restoreDirectory/${RestoreLimits.stagedFile}');
  File get _rollback => File('$restoreDirectory/${RestoreLimits.rollbackFile}');
  File get _intake => File('$restoreDirectory/${RestoreLimits.intakeFile}');
  File get _journal => File('$restoreDirectory/${RestoreLimits.journalFile}');

  Future<RestoreRecovery> recoverInterrupted({required List<int> key}) async {
    final directory = Directory(restoreDirectory);
    if (!await directory.exists()) {
      return const RestoreRecovery(outcome: RestoreRecoveryOutcome.none);
    }
    if (await FileSystemEntity.type(directory.path, followLinks: false) !=
        FileSystemEntityType.directory) {
      throw const RestoreFailure(RestoreCodes.recoveryRequired);
    }
    final journal = await _readJournal();
    if (journal != null && journal.databaseFile != _baseName(databasePath)) {
      throw const RestoreFailure(RestoreCodes.recoveryRequired);
    }
    final liveGeneration = await _generation(databasePath, key);
    final liveOpened = liveGeneration != null;
    final rollbackGeneration = await _generation(_rollback.path, key);
    final stagedExists = await _staged.exists();
    final rollbackExists = await _rollback.exists();
    final previousGeneration =
        journal?.previousGeneration ?? rollbackGeneration ?? '';
    final newGeneration = journal?.newGeneration ?? '';
    final decision = decideRestoreRecovery(
      journalPresent: journal != null,
      phase: journal?.phase,
      liveOpened: liveOpened,
      liveGeneration: liveGeneration,
      rollbackExists: rollbackExists,
      rollbackOpened: rollbackGeneration != null,
      rollbackGeneration: rollbackGeneration,
      stagedExists: stagedExists,
      newGeneration: newGeneration,
      previousGeneration: previousGeneration,
    );
    switch (decision.action) {
      case RestoreRecoveryAction.none:
        return const RestoreRecovery(outcome: RestoreRecoveryOutcome.none);
      case RestoreRecoveryAction.cleanupStaging:
        await _deleteKnownFiles();
        return RestoreRecovery(
          outcome: RestoreRecoveryOutcome.cleaned,
          generation: liveGeneration,
          reason: decision.reason,
        );
      case RestoreRecoveryAction.completeReplacement:
        await _deleteKnownFiles();
        return RestoreRecovery(
          outcome: RestoreRecoveryOutcome.completed,
          generation: liveGeneration,
          reason: decision.reason,
        );
      case RestoreRecoveryAction.rollBack:
        await _replaceFile(_rollback, File(databasePath));
        final restored = await _generation(databasePath, key);
        if (restored != previousGeneration) {
          throw const RestoreFailure(RestoreCodes.recoveryRequired);
        }
        await _deleteKnownFiles();
        return RestoreRecovery(
          outcome: RestoreRecoveryOutcome.rolledBack,
          generation: restored,
          reason: decision.reason,
        );
      case RestoreRecoveryAction.preserve:
        throw const RestoreFailure(RestoreCodes.recoveryRequired);
    }
  }

  Future<RestoreActivationResult> activate({
    required String preparedPath,
    required String previousGeneration,
    required String newGeneration,
    required String previousNamespace,
    required String reminderNamespace,
    required List<int> key,
    required Future<void> Function() closeLive,
    void Function(double fraction)? onProgress,
  }) async {
    if (!_generationPattern.hasMatch(previousGeneration) ||
        !_generationPattern.hasMatch(newGeneration) ||
        !_generationPattern.hasMatch(reminderNamespace) ||
        (previousNamespace.isNotEmpty &&
            !_generationPattern.hasMatch(previousNamespace))) {
      throw const RestoreFailure(RestoreCodes.failed);
    }
    await _ensureRestoreDirectory();
    if (await _journal.exists()) {
      throw const RestoreFailure(RestoreCodes.recoveryRequired);
    }
    final prepared = File(preparedPath);
    if (!await prepared.exists()) {
      throw const RestoreFailure(RestoreCodes.storage);
    }
    final preparedBytes = await prepared.length();
    if (preparedBytes < 512) {
      throw const RestoreFailure(RestoreCodes.corrupt);
    }
    if (preparedBytes > BackupLimits.maxSnapshotBytes) {
      throw const RestoreFailure(RestoreCodes.tooLarge);
    }

    var journalWritten = false;
    var replaced = false;
    try {
      onProgress?.call(0.2);
      await _moveIntoPlace(prepared, _staged);
      if (await _generation(_staged.path, key) != newGeneration) {
        throw const RestoreFailure(RestoreCodes.corrupt);
      }
      onProgress?.call(0.4);
      await closeLive();
      final live = File(databasePath);
      if (!await live.exists()) {
        throw const RestoreFailure(RestoreCodes.storage);
      }
      final liveBytes = await live.length();
      if (liveBytes < 512 || liveBytes > BackupLimits.maxSnapshotBytes) {
        throw const RestoreFailure(RestoreCodes.tooLarge);
      }
      onProgress?.call(0.55);
      await _copyDurably(live, _rollback);
      if (await _generation(_rollback.path, key) != previousGeneration) {
        throw const RestoreFailure(RestoreCodes.storage);
      }
      final journal = RestoreJournal(
        phase: RestoreJournalPhase.ready,
        previousGeneration: previousGeneration,
        newGeneration: newGeneration,
        previousNamespace: previousNamespace.isEmpty ? null : previousNamespace,
        reminderNamespace: reminderNamespace,
        stagedFile: RestoreLimits.stagedFile,
        rollbackFile: RestoreLimits.rollbackFile,
        databaseFile: _baseName(databasePath),
        startedAt: _clock(),
      );
      await _writeJournal(journal);
      journalWritten = true;
      onProgress?.call(0.7);
      await checkpoint?.call(RestoreJournalPhase.ready);
      await _replaceFile(_staged, live);
      replaced = true;
      await _writeJournal(journal.advance(RestoreJournalPhase.replaced));
      onProgress?.call(0.85);
      await checkpoint?.call(RestoreJournalPhase.replaced);
      if (await _generation(databasePath, key) != newGeneration) {
        // The shared failure path performs and verifies one rollback.
        throw const RestoreFailure(RestoreCodes.corrupt);
      }
      await _writeJournal(journal.advance(RestoreJournalPhase.committed));
      await checkpoint?.call(RestoreJournalPhase.committed);
      await _deleteKnownFiles();
      onProgress?.call(1);
      return RestoreActivationResult(
        previousGeneration: previousGeneration,
        newGeneration: newGeneration,
        previousNamespace: journal.previousNamespace,
        reminderNamespace: reminderNamespace,
      );
    } catch (_) {
      if (replaced) {
        try {
          await _rollbackToPrevious(key, previousGeneration);
          await _deleteKnownFiles();
        } catch (_) {
          // Leave the verified rollback copy and journal for startup recovery;
          // never claim that current records were kept.
          throw const RestoreFailure(RestoreCodes.recoveryRequired);
        }
      } else if (journalWritten) {
        final live = await _generation(databasePath, key);
        if (live == previousGeneration) {
          await _deleteKnownFiles();
        }
      } else {
        await _deleteQuietly(_staged);
        await _deleteQuietly(_rollback);
      }
      rethrow;
    }
  }

  Future<void> _rollbackToPrevious(
    List<int> key,
    String previousGeneration,
  ) async {
    if (!await _rollback.exists()) {
      throw const RestoreFailure(RestoreCodes.recoveryRequired);
    }
    await _replaceFile(_rollback, File(databasePath));
    if (await _generation(databasePath, key) != previousGeneration) {
      throw const RestoreFailure(RestoreCodes.recoveryRequired);
    }
  }

  Future<String?> _generation(String path, List<int> key) async {
    final file = File(path);
    if (!await file.exists() || await file.length() < 512) return null;
    try {
      final store = await RecordStore.open(path: path, key: key, isNew: false);
      try {
        return store.generation;
      } finally {
        await store.close();
      }
    } catch (_) {
      return null;
    }
  }

  Future<RestoreJournal?> _readJournal() async {
    if (!await _journal.exists()) return null;
    if (await _journal.length() > RestoreLimits.maxJournalBytes) {
      throw const RestoreFailure(RestoreCodes.recoveryRequired);
    }
    try {
      final decoded = jsonDecode(await _journal.readAsString());
      if (decoded is! Map) {
        throw const RestoreFailure(RestoreCodes.recoveryRequired);
      }
      return RestoreJournal.fromJson(Map<String, Object?>.from(decoded));
    } on RestoreFailure {
      rethrow;
    } catch (_) {
      throw const RestoreFailure(RestoreCodes.recoveryRequired);
    }
  }

  Future<void> _writeJournal(RestoreJournal journal) async {
    final text = RestoreJournal.encode(journal);
    if (text.length > RestoreLimits.maxJournalBytes) {
      throw const RestoreFailure(RestoreCodes.storage);
    }
    final temporary = File(
      '$restoreDirectory/${RestoreLimits.journalTemporary}',
    );
    try {
      await temporary.writeAsString(text, flush: true);
    } on FileSystemException {
      throw const RestoreFailure(RestoreCodes.storage);
    }
    await _replaceFile(temporary, _journal);
    await _syncDirectory(restoreDirectory);
  }

  Future<void> _ensureRestoreDirectory() async {
    final directory = Directory(restoreDirectory);
    try {
      await directory.create(recursive: true);
    } on FileSystemException {
      throw const RestoreFailure(RestoreCodes.storage);
    }
    final type = await FileSystemEntity.type(
      directory.path,
      followLinks: false,
    );
    if (type != FileSystemEntityType.directory) {
      throw const RestoreFailure(RestoreCodes.recoveryRequired);
    }
    await _runQuietly('/usr/bin/chmod', ['0700', '--', directory.path]);
  }

  Future<void> _moveIntoPlace(File source, File target) async {
    if (source.path == target.path) return;
    try {
      await source.rename(target.path);
    } on FileSystemException {
      // A different filesystem cannot rename atomically; copy then verify.
      await _copyDurably(source, target);
      await _deleteQuietly(source);
    }
    if (await target.length() < 512) {
      throw const RestoreFailure(RestoreCodes.storage);
    }
  }

  Future<void> _copyDurably(File source, File target) async {
    if (await target.exists()) await target.delete();
    final sink = await target.open(mode: FileMode.writeOnly);
    try {
      await for (final chunk in source.openRead()) {
        await sink.writeFrom(chunk);
      }
      await sink.flush();
      await sink.close();
    } catch (_) {
      try {
        await sink.close();
      } catch (_) {
        // The partial target is removed below.
      }
      await _deleteQuietly(target);
      throw const RestoreFailure(RestoreCodes.storage);
    }
    if (await target.length() != await source.length()) {
      await _deleteQuietly(target);
      throw const RestoreFailure(RestoreCodes.storage);
    }
    await _runQuietly('/usr/bin/chmod', ['0600', '--', target.path]);
  }

  Future<void> _replaceFile(File source, File target) async {
    if (!await source.exists()) {
      throw const RestoreFailure(RestoreCodes.storage);
    }
    try {
      await source.rename(target.path);
    } on FileSystemException {
      // Linux and Android support atomic replacement by rename. If it fails,
      // preserve the existing target and the journalled rollback evidence.
      throw const RestoreFailure(RestoreCodes.storage);
    }
    await _syncDirectory(target.parent.path);
  }

  Future<void> _deleteKnownFiles() async {
    await _deleteQuietly(_staged);
    await _deleteQuietly(_rollback);
    await _deleteQuietly(_intake);
    await _deleteQuietly(_journal);
    await _deleteQuietly(
      File('$restoreDirectory/${RestoreLimits.journalTemporary}'),
    );
    // Remove the directory when empty so ordinary launches skip the recovery
    // probe entirely.
    try {
      final directory = Directory(restoreDirectory);
      if (await directory.exists() && await directory.list().isEmpty) {
        await directory.delete();
      }
    } on FileSystemException {
      // An empty private directory is harmless and retried later.
    }
  }

  Future<void> _syncDirectory(String path) async {
    await _runQuietly('/usr/bin/sync', ['--', path]);
  }

  Future<void> _runQuietly(String executable, List<String> arguments) async {
    try {
      await Process.run(
        executable,
        arguments,
        runInShell: false,
      ).timeout(const Duration(seconds: 2));
    } catch (_) {
      // Directory fsync and mode hardening are best effort on non-Linux hosts.
    }
  }
}

final RegExp _generationPattern = RegExp(r'^[A-Za-z0-9_-]{16,128}$');

String _baseName(String path) => path.split(Platform.pathSeparator).last;

Future<void> _deleteQuietly(File file) async {
  try {
    if (await file.exists()) await file.delete();
  } on FileSystemException {
    // Retried by the next recovery pass for known names.
  }
}
