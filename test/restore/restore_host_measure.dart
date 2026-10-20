// Host performance probe for the synthetic restore flow. Not a release budget:
// it records one Linux host measurement for the affected commands.
import 'dart:convert';
import 'dart:io';

import 'package:true_grit_vital/backup/backup_service.dart';
import 'package:true_grit_vital/data/record_store.dart';
import 'package:true_grit_vital/domain/backup/backup.dart';
import 'package:true_grit_vital/restore/restore_activation.dart';

import 'fixtures/restore_fixture.dart';

Future<void> main() async {
  final directory = await createRestoreDataDirectory();
  final livePath = '${directory.path}/data/records.sqlite';
  try {
    writeFixtureDatabase(livePath);
    final live = await openFixtureStore(livePath);
    final service = BackupService(
      recordStore: live,
      stagingDirectory: Directory('${directory.path}/data/backup-staging'),
      destination: const UnsupportedBackupDestination(),
    );
    final create = Stopwatch()..start();
    final creation = await service.createBackup(
      password: 'synthetic correct horse',
      token: BackupCancellationToken(),
    );
    create.stop();
    final validate = Stopwatch()..start();
    final staged = await service.validateArchive(
      archive: creation.archive,
      password: 'synthetic correct horse',
      token: BackupCancellationToken(),
    );
    validate.stop();
    final prepare = Stopwatch()..start();
    final prepared = await live.prepareRestoredDatabase(
      stagedPath: staged.databasePath,
      rekeyTo: staged.rekey,
    );
    prepare.stop();
    final activate = Stopwatch()..start();
    await RestoreActivation(databasePath: live.databasePath).activate(
      preparedPath: prepared.path,
      previousGeneration: prepared.previousGeneration,
      newGeneration: prepared.generation,
      previousNamespace: prepared.previousNamespace ?? '',
      reminderNamespace: prepared.reminderNamespace,
      key: restoreTestKey,
      closeLive: live.close,
    );
    activate.stop();
    final reopen = Stopwatch()..start();
    final restored = await RecordStore.open(
      path: livePath,
      key: restoreTestKey,
      isNew: false,
    );
    await restored.close();
    reopen.stop();
    stdout.writeln(
      jsonEncode({
        'host': Platform.operatingSystem,
        'fixture':
            'synthetic schema19 -> 21, 2 people, 3 records, 1 attachment',
        'archiveBytes': creation.byteCount,
        'snapshotBytes': staged.header.snapshot.bytes,
        'backupCreateMs': create.elapsedMilliseconds,
        'validateMs': validate.elapsedMilliseconds,
        'prepareMs': prepare.elapsedMilliseconds,
        'activateMs': activate.elapsedMilliseconds,
        'reopenMs': reopen.elapsedMilliseconds,
      }),
    );
  } finally {
    await directory.delete(recursive: true);
  }
}
