import 'dart:io';

import '../backup/backup_service.dart';
import '../data/record_store.dart';
import '../domain/backup/backup.dart';
import '../domain/restore/restore.dart';
import 'restore_activation.dart';
import 'restore_intake.dart';

/// Adapts the admitted T04 backup reader to the restore boundary without
/// duplicating archive parsing, cryptography or KDF work.
final class BackupRestoreGateway implements RestoreGateway {
  BackupRestoreGateway({
    required this.store,
    required this.intake,
    required this.activation,
    required this.invalidateReminders,
    required this.onRefresh,
    required this.stagingDirectory,
    this.beforeActivate,
    this.onOutcome,
  });

  final RecordStore store;
  final RestoreArchiveIntake intake;
  final RestoreActivation activation;
  final Future<bool> Function({
    required String previousNamespace,
    required String reminderNamespace,
  })
  invalidateReminders;
  final Future<void> Function() onRefresh;
  final Directory stagingDirectory;
  final Future<void> Function()? beforeActivate;
  final void Function(RestoreActivationOutcome)? onOutcome;

  @override
  bool get supported => true;

  @override
  int get currentSchemaVersion => schemaVersionCurrent;

  @override
  Future<RestorePick?> chooseArchive() => intake.choose();

  @override
  Future<void> discardPick(RestorePick pick) => intake.discard(pick);

  @override
  Future<RestoreArchive> validateArchive({
    required RestorePick pick,
    required String password,
    required BackupCancellationToken token,
    void Function(RestoreProgress progress)? onProgress,
  }) async {
    final reader = BackupService(
      recordStore: store,
      stagingDirectory: stagingDirectory,
      destination: const UnsupportedBackupDestination(),
    );
    final staged = await reader.validateArchive(
      archive: pick.file,
      password: password,
      token: token,
      onProgress: (progress) => onProgress?.call(
        RestoreProgress(
          stage: RestoreProgressStage.checking,
          fraction: progress.fraction,
        ),
      ),
    );
    if (!staged.inventory.singleUserCompatible) {
      await staged.discard();
      throw const RestoreFailure(RestoreCodes.multiplePeople);
    }
    // The authenticated reader has its own staged snapshot; the intake copy is
    // no longer needed and is removed as soon as validation succeeds.
    await intake.discard(pick);
    return RestoreArchive(
      databasePath: staged.databasePath,
      header: staged.header,
      inventory: staged.inventory,
      archiveBytes: staged.archiveBytes,
      rekey: staged.rekey,
      discard: staged.discard,
    );
  }

  @override
  Future<void> discardArchive(RestoreArchive archive) => archive.discard();

  @override
  Future<RestorePreparedDatabase> prepare(
    RestoreArchive archive, {
    BackupCancellationToken? token,
  }) async {
    return await store.prepareRestoredDatabase(
      stagedPath: archive.databasePath,
      rekeyTo: archive.rekey,
      token: token,
    );
  }

  @override
  Future<RestoreActivationOutcome> activate({
    required RestoreArchive archive,
    required RestorePreparedDatabase prepared,
    void Function(RestoreProgress progress)? onProgress,
  }) async {
    var closed = false;
    try {
      await beforeActivate?.call();
      final result = await store.withRestoreKey(
        (key) => activation.activate(
          preparedPath: prepared.path,
          previousGeneration: prepared.previousGeneration,
          newGeneration: prepared.generation,
          previousNamespace: prepared.previousNamespace ?? '',
          reminderNamespace: prepared.reminderNamespace,
          key: key,
          closeLive: () async {
            store.suspendWrites(true);
            try {
              await store.close();
            } finally {
              closed = true;
            }
          },
          onProgress: (fraction) => onProgress?.call(
            RestoreProgress(
              stage: RestoreProgressStage.replacing,
              fraction: fraction,
            ),
          ),
        ),
      );
      var remindersInvalidated = true;
      final previous = result.previousNamespace;
      if (previous != null) {
        try {
          remindersInvalidated = await invalidateReminders(
            previousNamespace: previous,
            reminderNamespace: result.reminderNamespace,
          );
        } catch (_) {
          remindersInvalidated = false;
        }
      }
      final outcome = RestoreActivationOutcome(
        result: result,
        remindersInvalidated: remindersInvalidated,
      );
      try {
        await archive.discard();
      } catch (_) {}
      onOutcome?.call(outcome);
      return outcome;
    } finally {
      if (closed) await onRefresh();
    }
  }

  @override
  Future<void> refresh() => onRefresh();
}
