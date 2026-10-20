import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:true_grit_vital/backup/backup_service.dart';
import 'package:true_grit_vital/data/record_store.dart';
import 'package:true_grit_vital/domain/backup/backup.dart';
import 'package:true_grit_vital/domain/restore/restore.dart';
import 'package:true_grit_vital/restore/restore_activation.dart';

import 'fixtures/restore_fixture.dart';

void main() {
  late Directory directory;
  late String livePath;
  late RecordStore live;
  late BackupService service;
  const password = 'synthetic correct horse';

  setUp(() async {
    directory = await createRestoreDataDirectory();
    livePath = '${directory.path}/data/records.sqlite';
    writeFixtureDatabase(livePath);
    live = await openFixtureStore(livePath);
    service = BackupService(
      recordStore: live,
      stagingDirectory: Directory('${directory.path}/data/backup-staging'),
      destination: const UnsupportedBackupDestination(),
      clock: () => DateTime.utc(2026, 10, 20, 12),
    );
  });

  tearDown(() async {
    try {
      await live.close();
    } catch (_) {
      // Already closed by activation.
    }
    await directory.delete(recursive: true);
  });

  test(
    'validated archive previews and replaces with a fresh generation',
    () async {
      final creation = await service.createBackup(
        password: password,
        token: BackupCancellationToken(),
      );
      expect(creation.byteCount, greaterThan(512));
      expect(creation.inventory.peopleCount, 1);
      expect(creation.archive.existsSync(), isTrue);

      await expectLater(
        service.validateArchive(
          archive: creation.archive,
          password: 'wrong password value',
          token: BackupCancellationToken(),
        ),
        throwsA(
          isA<BackupFailure>().having(
            (error) => error.code,
            'code',
            'backup_wrong_password',
          ),
        ),
      );
      expect((await live.records()), hasLength(3));

      final corruptCopy = File('${directory.path}/corrupt.vitalbackup');
      await creation.archive.copy(corruptCopy.path);
      final bytes = await corruptCopy.readAsBytes();
      bytes[bytes.length - 10] ^= 0xff;
      await corruptCopy.writeAsBytes(bytes, flush: true);
      await expectLater(
        service.validateArchive(
          archive: corruptCopy,
          password: password,
          token: BackupCancellationToken(),
        ),
        throwsA(isA<BackupFailure>()),
      );
      expect((await live.records()), hasLength(3));

      final cancelled = BackupCancellationToken()..cancel();
      await expectLater(
        service.validateArchive(
          archive: creation.archive,
          password: password,
          token: cancelled,
        ),
        throwsA(
          isA<BackupFailure>().having(
            (error) => error.code,
            'code',
            'backup_cancelled',
          ),
        ),
      );
      expect((await live.records()), hasLength(3));

      final beforeRecords = await live.records();
      final beforeGeneration = live.generation;
      final staged = await service.validateArchive(
        archive: creation.archive,
        password: password,
        token: BackupCancellationToken(),
      );
      final archive = RestoreArchive(
        databasePath: staged.databasePath,
        header: staged.header,
        inventory: staged.inventory,
        archiveBytes: staged.archiveBytes,
        rekey: staged.rekey,
        discard: staged.discard,
      );
      final preview = restorePreviewFor(
        archive: archive,
        fileName: creation.fileName,
        currentSchemaVersion: 21,
      );
      expect(preview.fileName, creation.fileName);
      expect(preview.people, hasLength(1));
      expect(preview.coverage, hasLength(1));
      expect(preview.multiplePeople, isFalse);
      expect(preview.recordCount, 3);
      expect(preview.earliestRecord, isNotNull);
      expect(preview.latestRecord, isNotNull);
      expect(preview.upgradesSchema, isFalse);

      final prepared = await live.prepareRestoredDatabase(
        stagedPath: staged.databasePath,
        rekeyTo: staged.rekey,
      );
      expect(prepared.previousGeneration, beforeGeneration);
      expect(prepared.generation, isNot(beforeGeneration));
      expect(prepared.previousNamespace, isNotNull);

      final activation = RestoreActivation(databasePath: live.databasePath);
      final result = await activation.activate(
        preparedPath: prepared.path,
        previousGeneration: prepared.previousGeneration,
        newGeneration: prepared.generation,
        previousNamespace: prepared.previousNamespace ?? '',
        reminderNamespace: prepared.reminderNamespace,
        key: restoreTestKey,
        closeLive: live.close,
      );
      expect(result.newGeneration, prepared.generation);
      expect(result.reminderNamespace, prepared.reminderNamespace);

      final reopened = await RecordStore.open(
        path: livePath,
        key: restoreTestKey,
        isNew: false,
      );
      try {
        expect(reopened.generation, prepared.generation);
        expect(await reopened.drafts(), isEmpty);
        expect(
          (await reopened.records()).map(
            (record) => '${record.id}:${record.revision}',
          ),
          beforeRecords.map((record) => '${record.id}:${record.revision}'),
        );
      } finally {
        await reopened.close();
      }
      final restoreDirectory = Directory('${directory.path}/data/restore');
      expect(await restoreDirectory.exists(), isFalse);
    },
  );
}
