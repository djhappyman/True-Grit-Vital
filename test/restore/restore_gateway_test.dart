import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:true_grit_vital/backup/backup_service.dart';
import 'package:true_grit_vital/data/record_store.dart';
import 'package:true_grit_vital/domain/backup/backup.dart';
import 'package:true_grit_vital/restore/backup_restore_source.dart';
import 'package:true_grit_vital/restore/restore_activation.dart';
import 'package:true_grit_vital/restore/restore_archive_picker.dart';
import 'package:true_grit_vital/restore/restore_intake.dart';

import 'fixtures/restore_fixture.dart';

final class _Picker implements RestoreArchivePicker {
  _Picker(this.file);
  final File file;

  @override
  bool get supported => true;

  @override
  Future<RestorePickedFile?> pick() async => RestorePickedFile(
    name: 'synthetic-backup.vitalbackup',
    byteCount: file.lengthSync(),
    openRead: file.openRead,
  );
}

void main() {
  test(
    'gateway wires the admitted reader, activation and reminder epoch',
    () async {
      final directory = await createRestoreDataDirectory();
      final livePath = '${directory.path}/data/records.sqlite';
      writeFixtureDatabase(livePath);
      final live = await openFixtureStore(livePath);
      final creation =
          await BackupService(
            recordStore: live,
            stagingDirectory: Directory(
              '${directory.path}/data/backup-staging',
            ),
            destination: const UnsupportedBackupDestination(),
          ).createBackup(
            password: 'synthetic correct horse',
            token: BackupCancellationToken(),
          );
      final previousNamespace = await live.restoreObjectNamespace();
      var refreshes = 0;
      String? retiredOld, retiredNew;
      final gateway = BackupRestoreGateway(
        store: live,
        intake: RestoreArchiveIntake(
          picker: _Picker(creation.archive),
          directory: Directory('${directory.path}/data/restore'),
        ),
        activation: RestoreActivation(databasePath: live.databasePath),
        stagingDirectory: Directory('${directory.path}/data/backup-staging'),
        invalidateReminders:
            ({
              required String previousNamespace,
              required String reminderNamespace,
            }) async {
              retiredOld = previousNamespace;
              retiredNew = reminderNamespace;
              return true;
            },
        onRefresh: () async => refreshes++,
      );
      final pick = (await gateway.chooseArchive())!;
      final archive = await gateway.validateArchive(
        pick: pick,
        password: 'synthetic correct horse',
        token: BackupCancellationToken(),
      );
      expect(archive.inventory.coverage, isNotEmpty);
      final prepared = await gateway.prepare(archive);
      final outcome = await gateway.activate(
        archive: archive,
        prepared: prepared,
      );
      expect(outcome.remindersInvalidated, isTrue);
      expect(refreshes, 1);
      expect(retiredOld, previousNamespace);
      expect(retiredNew, prepared.reminderNamespace);

      final reopened = await RecordStore.open(
        path: livePath,
        key: restoreTestKey,
        isNew: false,
      );
      try {
        expect(reopened.generation, prepared.generation);
        expect(await reopened.drafts(), isEmpty);
      } finally {
        await reopened.close();
      }
      await directory.delete(recursive: true);
    },
  );
}
