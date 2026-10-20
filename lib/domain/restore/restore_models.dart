import 'dart:io';

import '../backup/backup.dart';

/// Technical restore failure codes. Presentation maps them to reviewed copy.
final class RestoreFailure implements Exception {
  const RestoreFailure(this.code);
  final String code;
  @override
  String toString() => 'RestoreFailure($code)';
}

/// Stable codes shared by the gateway, controller and presentation.
abstract final class RestoreCodes {
  static const locked = 'restore_locked';
  static const multiplePeople = 'restore_multiple_people';
  static const unavailable = 'restore_unavailable';
  static const chooseArchive = 'restore_choose_archive';
  static const passwordRequired = 'restore_password_required';
  static const passwordLong = 'restore_password_long';
  static const wrongPassword = 'restore_wrong_password';
  static const corrupt = 'restore_corrupt';
  static const unsupportedVersion = 'restore_unsupported_version';
  static const tooLarge = 'restore_too_large';
  static const confirmationRequired = 'restore_confirmation_required';
  static const busy = 'restore_busy';
  static const recoveryRequired = 'restore_recovery_required';
  static const storage = 'restore_storage';
  static const archiveChanged = 'restore_archive_changed';
  static const failed = 'restore_failed';
  static const cancelled = 'restore_cancelled';
}

abstract final class RestoreLimits {
  /// Bound for one intake archive. The authenticated reader enforces the same
  /// archive ceiling again before it writes a staged snapshot.
  static const int maxArchiveBytes = BackupLimits.maxArchiveBytes;
  static const int maxPasswordBytes = BackupLimits.maxPasswordBytes;
  static const int maxPeoplePreview = 200;
  static const int maxJournalBytes = 8192;
  static const String intakeFile = 'incoming.vitalbackup';
  static const String restoreDirectory = 'restore';
  static const String stagedFile = 'staged.sqlite';
  static const String rollbackFile = 'previous.sqlite';
  static const String journalFile = 'journal.json';
  static const String journalTemporary = 'journal.tmp';
}

/// The user's chosen archive, copied into protected app storage under an
/// opaque name. The original picker source is never used again.
final class RestorePick {
  const RestorePick({
    required this.name,
    required this.file,
    required this.byteCount,
  });
  final String name;
  final File file;
  final int byteCount;
}

/// A decrypted and integrity-checked backup archive. It is still encrypted
/// with the archive key and never activated by the archive reader.
final class RestoreArchive {
  const RestoreArchive({
    required this.databasePath,
    required this.header,
    required this.inventory,
    required this.archiveBytes,
    required this.rekey,
    required this.discard,
  });
  final String databasePath;
  final BackupHeader header;
  final BackupInventory inventory;
  final int archiveBytes;

  /// Re-keys the staged snapshot to this installation's dataset key. The key
  /// is supplied only by the record store that owns the live connection.
  final Future<void> Function(List<int> newKey) rekey;
  final Future<void> Function() discard;
}

enum RestoreProgressStage { checking, preparing, replacing }

final class RestoreProgress {
  const RestoreProgress({required this.stage, this.fraction});
  final RestoreProgressStage stage;
  final double? fraction;
}

/// Bounded, user-reviewable coverage of the staged archive.
final class RestorePreview {
  const RestorePreview({
    required this.fileName,
    required this.createdAt,
    required this.schemaVersion,
    required this.archiveBytes,
    required this.people,
    required this.coverage,
    required this.peopleCount,
    required this.recordCount,
    required this.itemCount,
    required this.supportingCount,
    required this.attachmentCount,
    required this.attachmentBytes,
    required this.upgradesSchema,
    this.earliestRecord,
    this.latestRecord,
  });

  final String fileName;
  final DateTime createdAt;
  final int schemaVersion;
  final int archiveBytes;
  final List<BackupPerson> people;
  final List<BackupPersonCoverage> coverage;
  final int peopleCount;
  final int recordCount;
  final int itemCount;
  final int supportingCount;
  final int attachmentCount;
  final int attachmentBytes;
  final bool upgradesSchema;
  final DateTime? earliestRecord;
  final DateTime? latestRecord;

  bool get multiplePeople => peopleCount > 1;
  bool get peopleTruncated => peopleCount > people.length;
}

RestorePreview restorePreviewFor({
  required RestoreArchive archive,
  required String fileName,
  required int currentSchemaVersion,
}) {
  final inventory = archive.inventory;
  return RestorePreview(
    fileName: fileName,
    createdAt: archive.header.createdAt,
    schemaVersion: archive.header.schemaVersion,
    archiveBytes: archive.archiveBytes,
    people: inventory.people
        .take(RestoreLimits.maxPeoplePreview)
        .toList(growable: false),
    coverage: inventory.coverage
        .take(RestoreLimits.maxPeoplePreview)
        .toList(growable: false),
    peopleCount: inventory.peopleCount,
    recordCount: inventory.recordCount,
    itemCount: inventory.itemCount,
    supportingCount: inventory.supportingCount,
    attachmentCount: inventory.attachmentCount,
    attachmentBytes: inventory.attachmentBytes,
    upgradesSchema: archive.header.schemaVersion < currentSchemaVersion,
    earliestRecord: inventory.earliestRecord,
    latestRecord: inventory.latestRecord,
  );
}

/// One fully prepared replacement database. It is re-keyed to the live
/// installation key, migrated by the real open path, scrubbed of device-local
/// actions and stamped with a fresh local generation.
final class RestorePreparedDatabase {
  const RestorePreparedDatabase({
    required this.path,
    required this.previousGeneration,
    required this.generation,
    required this.previousNamespace,
    required this.reminderNamespace,
    required this.schemaVersion,
    required this.peopleCount,
    required this.recordCount,
    required this.itemCount,
    required this.supportingCount,
    required this.attachmentCount,
  });

  final String path;
  final String previousGeneration;
  final String generation;
  final String? previousNamespace;
  final String reminderNamespace;
  final int schemaVersion;
  final int peopleCount;
  final int recordCount;
  final int itemCount;
  final int supportingCount;
  final int attachmentCount;
}

final class RestoreActivationResult {
  const RestoreActivationResult({
    required this.previousGeneration,
    required this.newGeneration,
    required this.previousNamespace,
    required this.reminderNamespace,
  });
  final String previousGeneration;
  final String newGeneration;
  final String? previousNamespace;
  final String reminderNamespace;
}

final class RestoreActivationOutcome {
  const RestoreActivationOutcome({
    required this.result,
    required this.remindersInvalidated,
  });
  final RestoreActivationResult result;

  /// False when the native epoch could not be retired. Records are still
  /// replaced; the next foreground reconcile reports the reminder repair.
  final bool remindersInvalidated;
}

enum RestoreRecoveryOutcome { none, cleaned, completed, rolledBack }

/// Result of the startup recovery pass. [generation] is the generation now
/// open, or the generation left in place when the pass preserved evidence.
final class RestoreRecovery {
  const RestoreRecovery({required this.outcome, this.generation, this.reason});
  final RestoreRecoveryOutcome outcome;
  final String? generation;
  final String? reason;
}

/// Injectable boundary. The isolated implementation wraps the admitted backup
/// reader; tests supply a synthetic archive without a second crypto engine.
abstract interface class RestoreGateway {
  bool get supported;
  int get currentSchemaVersion;

  Future<RestorePick?> chooseArchive();
  Future<void> discardPick(RestorePick pick);

  Future<RestoreArchive> validateArchive({
    required RestorePick pick,
    required String password,
    required BackupCancellationToken token,
    void Function(RestoreProgress progress)? onProgress,
  });

  Future<void> discardArchive(RestoreArchive archive);

  /// Prepares the staged snapshot while [token] is still live. Cancellation is
  /// cooperative and bounded to preparation: it must never interrupt a
  /// confirmed activation or journal swap. A cancelled call leaves the live
  /// store untouched and discards its staged connection.
  Future<RestorePreparedDatabase> prepare(
    RestoreArchive archive, {
    BackupCancellationToken? token,
  });

  Future<RestoreActivationOutcome> activate({
    required RestoreArchive archive,
    required RestorePreparedDatabase prepared,
    void Function(RestoreProgress progress)? onProgress,
  });

  /// Rebuilds the live store provider after activation or rollback.
  Future<void> refresh();
}

String restoreErrorCode(Object error) => switch (error) {
  RestoreFailure(:final code) => code,
  BackupFailure(:final code) => switch (code) {
    'backup_wrong_password' => RestoreCodes.wrongPassword,
    'backup_unsupported_version' => RestoreCodes.unsupportedVersion,
    'backup_too_large' => RestoreCodes.tooLarge,
    'backup_cancelled' => RestoreCodes.cancelled,
    'backup_corrupt' ||
    'backup_invalid_dataset' ||
    'backup_attachment_mismatch' ||
    'backup_snapshot_changed' ||
    'backup_key' => RestoreCodes.corrupt,
    _ => RestoreCodes.failed,
  },
  _ => RestoreCodes.failed,
};

bool isRestoreCancellation(Object error) =>
    restoreErrorCode(error) == RestoreCodes.cancelled;
