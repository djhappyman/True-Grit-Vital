import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:sqlite3/sqlite3.dart' show SqliteException;

import '../data/record_store.dart';
import '../domain/backup/backup.dart';
import 'backup_worker.dart';

/// Injectable boundary used by the backup controller and available to T07.
abstract interface class BackupOperations {
  bool get destinationSupported;

  Future<BackupCreation> createBackup({
    required String password,
    required BackupCancellationToken token,
    void Function(BackupProgress)? onProgress,
  });

  Future<BackupSaveStatus> save(BackupCreation creation);

  Future<void> discard(BackupCreation creation);

  Future<StagedBackup> validateArchive({
    required File archive,
    required String password,
    required BackupCancellationToken token,
    void Function(BackupProgress)? onProgress,
  });

  Future<void> cleanupAbandoned();
}

final class BackupCreation {
  const BackupCreation({
    required this.archive,
    required this.fileName,
    required this.byteCount,
    required this.sha256,
    required this.createdAt,
    required this.inventory,
    required this.summary,
  });

  final File archive;
  final String fileName;
  final int byteCount;
  final String sha256;
  final DateTime createdAt;
  final BackupInventory inventory;
  final BackupSnapshotSummary summary;
}

/// A decrypted, validated snapshot that is never activated here. T07 owns
/// replacement, fresh generation and rollback.
final class StagedBackup {
  StagedBackup._({
    required this.databasePath,
    required this.generation,
    required this.schemaVersion,
    required this.inventory,
    required this.header,
    required this.archiveBytes,
    required List<int> key,
    this._onDiscard,
  }) : _key = List<int>.of(key);

  final String databasePath, generation;
  final int schemaVersion, archiveBytes;
  final BackupInventory inventory;
  final BackupHeader header;
  final void Function()? _onDiscard;
  List<int> _key;

  /// Re-keys the staged copy for the installation that will activate it.
  /// The archive's original dataset key is never exposed to callers.
  Future<void> rekey(List<int> newKey) async {
    await rekeyBackupSnapshot(
      path: databasePath,
      currentKey: _key,
      newKey: newKey,
    );
    _key = List<int>.of(newKey);
  }

  Future<void> discard() async {
    await _deleteDatabaseFiles(databasePath);
    _onDiscard?.call();
  }
}

final class BackupService implements BackupOperations {
  BackupService({
    required this.recordStore,
    required this.stagingDirectory,
    BackupDestinationGateway? destination,
    DateTime Function()? clock,
  }) : destination = destination ?? defaultBackupDestination(),
       clock = clock ?? (() => DateTime.now().toUtc());

  final RecordStore recordStore;
  final Directory stagingDirectory;
  final BackupDestinationGateway destination;
  final DateTime Function() clock;
  static final Set<String> _activePaths = {};

  /// Process-wide guard: only one protected capture may pin/reclaim versions,
  /// and startup cleanup must not clear pins for an active capture.
  static bool _captureActive = false;

  static const _archivePrefix = 'backup-';
  static const _snapshotPrefix = 'snapshot-';
  static const _archiveSuffix = '.vitalbackup';

  @override
  bool get destinationSupported => destination.supported;

  @override
  Future<BackupCreation> createBackup({
    required String password,
    required BackupCancellationToken token,
    void Function(BackupProgress)? onProgress,
  }) async {
    if (_captureActive) throw const BackupFailure('backup_busy');
    BackupLimits.checkPassword(password);
    token.throwIfCancelled();
    _captureActive = true;
    final session = newCommandId();
    String? snapshotPath;
    String? archivePath;
    try {
      await stagingDirectory.create(recursive: true);
      onProgress?.call(const BackupProgress(stage: BackupStage.snapshot));
      final snapshot = await recordStore.createBackupSnapshot(
        directory: stagingDirectory,
        sessionId: session,
      );
      snapshotPath = snapshot.path;
      _activePaths.add(snapshot.path);
      token.throwIfCancelled();

      onProgress?.call(const BackupProgress(stage: BackupStage.inspect));
      final inventory = await recordStore.inspectOwnSnapshot(snapshot);
      token.throwIfCancelled();

      final createdAt = clock().toUtc();
      final header = BackupHeader(
        createdAt: createdAt,
        schemaVersion: snapshot.schemaVersion,
        generation: snapshot.generation,
        kdf: BackupKdfParameters.fresh(),
        cipher: BackupCipherParameters.fresh(),
        snapshot: inventory.summaryFor(snapshot.byteCount, snapshot.sha256),
      );
      archivePath =
          '${stagingDirectory.path}/'
          '$_archivePrefix${_stamp(createdAt)}-${session.substring(0, 8)}'
          '$_archiveSuffix';
      if (await File(archivePath).exists()) {
        throw const BackupFailure('backup_staging');
      }
      _activePaths.add(archivePath);
      onProgress?.call(
        BackupProgress(
          stage: BackupStage.encrypt,
          totalBytes: header.snapshot.bytes,
        ),
      );
      await recordStore.writeBackupArchive(
        snapshot: snapshot,
        outputPath: archivePath,
        password: password,
        header: header,
        token: token,
        onProgress: onProgress,
      );
      await _deleteQuietly(File(snapshot.path));
      _activePaths.remove(snapshot.path);
      snapshotPath = null;
      token.throwIfCancelled();

      onProgress?.call(
        BackupProgress(
          stage: BackupStage.verify,
          totalBytes: header.snapshot.bytes,
        ),
      );
      final staged = await _decryptAndInspect(
        archive: File(archivePath),
        password: password,
        token: token,
        onProgress: onProgress,
      );
      try {
        _compare(header, staged);
      } finally {
        await staged.discard();
      }
      token.throwIfCancelled();

      final archive = File(archivePath);
      final bytes = await archive.length();
      final digest = await sha256.bind(archive.openRead()).first;
      onProgress?.call(
        BackupProgress(
          stage: BackupStage.verify,
          completedBytes: header.snapshot.bytes,
          totalBytes: header.snapshot.bytes,
        ),
      );
      return BackupCreation(
        archive: archive,
        fileName: archive.uri.pathSegments.last,
        byteCount: bytes,
        sha256: digest.toString(),
        createdAt: createdAt,
        inventory: inventory,
        summary: header.snapshot,
      );
    } catch (error) {
      if (archivePath != null) {
        await _deleteQuietly(File(archivePath));
        _activePaths.remove(archivePath);
      }
      if (snapshotPath != null) {
        await _deleteQuietly(File(snapshotPath));
        _activePaths.remove(snapshotPath);
      }
      if (error is SqliteException && error.resultCode == 13) {
        throw const BackupFailure('backup_no_space');
      }
      if (error is FileSystemException && error.osError?.errorCode == 28) {
        throw const BackupFailure('backup_no_space');
      }
      rethrow;
    } finally {
      try {
        await recordStore.releaseBackupPins(session);
      } catch (_) {
        // Expiring backup pins are reclaimed by the next maintenance pass.
      }
      _captureActive = false;
    }
  }

  @override
  Future<BackupSaveStatus> save(BackupCreation creation) async {
    final result = await destination.save(
      BackupArtifact(
        file: creation.archive,
        name: creation.fileName,
        byteCount: creation.byteCount,
        sha256: creation.sha256,
        createdAt: creation.createdAt,
      ),
    );
    if (result == BackupSaveStatus.saved) {
      await _deleteQuietly(creation.archive);
      _activePaths.remove(creation.archive.path);
    }
    return result;
  }

  @override
  Future<void> discard(BackupCreation creation) async {
    if (await creation.archive.exists()) await creation.archive.delete();
    _activePaths.remove(creation.archive.path);
  }

  @override
  Future<StagedBackup> validateArchive({
    required File archive,
    required String password,
    required BackupCancellationToken token,
    void Function(BackupProgress)? onProgress,
  }) => _decryptAndInspect(
    archive: archive,
    password: password,
    token: token,
    onProgress: onProgress,
  );

  Future<StagedBackup> _decryptAndInspect({
    required File archive,
    required String password,
    required BackupCancellationToken token,
    void Function(BackupProgress)? onProgress,
  }) async {
    await stagingDirectory.create(recursive: true);
    final session = newCommandId();
    final stagedPath = '${stagingDirectory.path}/$_snapshotPrefix$session.db';
    token.throwIfCancelled();
    _activePaths.add(stagedPath);
    try {
      final result = await const BackupWorker().decrypt(
        archive: archive,
        output: File(stagedPath),
        password: password,
        token: token,
        onProgress: onProgress,
      );
      token.throwIfCancelled();
      if (result.header.schemaVersion > schemaVersionCurrent) {
        throw const BackupFailure('backup_unsupported_version');
      }
      final BackupInventory inventory;
      try {
        inventory = await inspectBackupSnapshot(
          path: stagedPath,
          key: result.datasetKey,
        );
      } on BackupFailure {
        rethrow;
      } catch (_) {
        // The authenticated snapshot cannot be opened as a valid Vital
        // database. Database-engine error wrappers are not a public API.
        throw const BackupFailure('backup_corrupt');
      }
      if (inventory.generation != result.header.generation ||
          result.header.snapshot.bytes != result.snapshotBytes ||
          result.header.snapshot.sha256 != result.snapshotSha256) {
        throw const BackupFailure('backup_invalid_dataset');
      }
      return StagedBackup._(
        databasePath: stagedPath,
        generation: inventory.generation,
        schemaVersion: result.header.schemaVersion,
        inventory: inventory,
        header: result.header,
        archiveBytes: result.archiveBytes,
        key: result.datasetKey,
        onDiscard: () => _activePaths.remove(stagedPath),
      );
    } on StateError catch (error) {
      await _deleteDatabaseFiles(stagedPath);
      _activePaths.remove(stagedPath);
      if (error.message == 'unsupported_schema') {
        throw const BackupFailure('backup_unsupported_version');
      }
      if (const {
        'corrupt_dataset',
        'invalid_dataset',
        'invalid_dataset_identity',
        'plaintext_dataset',
        'truncated_dataset',
        'uninitialised_dataset',
      }.contains(error.message)) {
        throw const BackupFailure('backup_corrupt');
      }
      rethrow;
    } on SqliteException {
      await _deleteDatabaseFiles(stagedPath);
      _activePaths.remove(stagedPath);
      throw const BackupFailure('backup_corrupt');
    } catch (_) {
      await _deleteDatabaseFiles(stagedPath);
      _activePaths.remove(stagedPath);
      rethrow;
    }
  }

  void _compare(BackupHeader header, StagedBackup staged) {
    final snapshot = header.snapshot;
    final inventory = staged.inventory;
    if (staged.generation != header.generation ||
        staged.schemaVersion > schemaVersionCurrent ||
        inventory.attachmentCount != snapshot.attachmentCount ||
        inventory.attachmentBytes != snapshot.attachmentBytes ||
        inventory.attachmentSha256 != snapshot.attachmentSha256) {
      throw const BackupFailure('backup_attachment_mismatch');
    }
  }

  @override
  Future<void> cleanupAbandoned({
    Duration olderThan = const Duration(hours: 1),
  }) async {
    if (_captureActive) return;
    // Claim maintenance before the first await. A capture must not begin
    // between scanning staging and clearing abandoned pins.
    _captureActive = true;
    try {
      if (!await stagingDirectory.exists()) return;
      final cutoff = clock().toUtc().subtract(olderThan);
      await for (final entry in stagingDirectory.list(followLinks: false)) {
        if (entry is! File) continue;
        if (_activePaths.contains(entry.path)) continue;
        final name = entry.uri.pathSegments.last;
        final known =
            (name.startsWith(_archivePrefix) &&
                name.endsWith(_archiveSuffix)) ||
            (name.startsWith(_snapshotPrefix) && name.endsWith('.db')) ||
            name.endsWith('.db-wal') ||
            name.endsWith('.db-shm') ||
            name.endsWith('.db-journal');
        if (!known) continue;
        try {
          final stat = await entry.stat();
          if (stat.modified.toUtc().isAfter(cutoff)) continue;
          await entry.delete();
        } catch (_) {
          // A later maintenance pass retries known staging names.
        }
      }
      await recordStore.clearBackupPins();
    } finally {
      _captureActive = false;
    }
  }

  static String _stamp(DateTime value) {
    final utc = value.toUtc();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${utc.year}${two(utc.month)}${two(utc.day)}-'
        '${two(utc.hour)}${two(utc.minute)}${two(utc.second)}';
  }
}

/// The schema version this build can open after a validated restore.
const schemaVersionCurrent = 21;

Future<void> _deleteQuietly(File file) async {
  try {
    if (await file.exists()) await file.delete();
  } catch (_) {
    // Known staging names are retried by startup cleanup.
  }
}

Future<void> _deleteDatabaseFiles(String path) async {
  await _deleteQuietly(File(path));
  await _deleteQuietly(File('$path-wal'));
  await _deleteQuietly(File('$path-shm'));
  await _deleteQuietly(File('$path-journal'));
}
