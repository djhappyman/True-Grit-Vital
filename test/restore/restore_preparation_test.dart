import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:true_grit_vital/data/record_store.dart';
import 'package:true_grit_vital/domain/restore/restore.dart';

import 'fixtures/restore_fixture.dart';

void main() {
  late Directory directory;
  late String livePath;
  late RecordStore live;

  setUp(() async {
    directory = await createRestoreDataDirectory();
    livePath = '${directory.path}/data/records.sqlite';
    writeFixtureDatabase(livePath);
    live = await openFixtureStore(livePath);
  });

  tearDown(() async {
    try {
      await live.close();
    } catch (_) {
      // Already closed by the test.
    }
    await directory.delete(recursive: true);
  });

  Database raw(String path) {
    final db = sqlite3.open(path);
    db.execute("PRAGMA cipher='chacha20'");
    db.execute('PRAGMA key="x\'${hexKey(restoreTestKey)}\'"');
    return db;
  }

  test('an old archive cannot disable the installation app lock', () async {
    await live.writeSetting('app_lock', 'true');
    await live.close();
    final archivePath = '${directory.path}/older.sqlite';
    await File(livePath).copy(archivePath);
    final older = await openFixtureStore(archivePath);
    older.suspendWrites(false);
    await older.writeSetting('app_lock', 'false');
    await older.close();
    live = await openFixtureStore(livePath);
    live.suspendWrites(false);
    await live.prepareRestoredDatabase(
      stagedPath: archivePath,
      rekeyTo: (_) async {},
    );
    final prepared = await openFixtureStore(archivePath);
    try {
      expect(await prepared.readSetting('app_lock'), 'true');
    } finally {
      await prepared.close();
    }
  });

  test(
    'migrates, re-keys and clears device-local state while preserving history',
    () async {
      final beforeGeneration = live.generation;
      final beforeNamespace = await live.restoreObjectNamespace();
      final beforeRecords = await live.records();
      final beforeHistory = <String, List<String>>{
        for (final record in beforeRecords)
          record.id: [
            for (final revision in await live.history(record.id))
              '${revision.revision}:${revision.enteredAmount}:'
                  '${revision.isVoided}',
          ],
      };
      expect(beforeRecords, hasLength(3));
      expect(beforeNamespace, isNotNull);

      // A portable archive from another installation has a different dataset
      // key. Re-key that copy first, then prove restore re-keys it back to the
      // installation key without exposing either key.
      final archivePath = '${directory.path}/source.sqlite';
      await live.close();
      await File(livePath).copy(archivePath);
      final archiveKey = List<int>.generate(32, (index) => 200 - index);
      await rekeyBackupSnapshot(
        path: archivePath,
        currentKey: restoreTestKey,
        newKey: archiveKey,
      );
      live = await openFixtureStore(livePath);
      final prepared = await live.prepareRestoredDatabase(
        stagedPath: archivePath,
        rekeyTo: (installationKey) => rekeyBackupSnapshot(
          path: archivePath,
          currentKey: archiveKey,
          newKey: installationKey,
        ),
      );

      expect(prepared.previousGeneration, beforeGeneration);
      expect(prepared.generation, isNot(beforeGeneration));
      expect(prepared.previousNamespace, beforeNamespace);
      expect(prepared.reminderNamespace, isNot(beforeNamespace));
      expect(prepared.schemaVersion, greaterThanOrEqualTo(21));
      expect(prepared.peopleCount, 1);
      expect(prepared.recordCount, 3);
      expect(prepared.itemCount, 4);
      expect(prepared.supportingCount, 3);

      final restored = await openFixtureStore(archivePath);
      try {
        expect(restored.generation, prepared.generation);
        expect((await restored.profiles()), hasLength(1));
        expect((await restored.drafts()), isEmpty);
        final panel = await restored.supportingRecord(meId, 'v19-panel-exact');
        expect(panel, isNotNull);
        expect(
          (panel!.snapshot as LabPanelSnapshot).title,
          'Synthetic exact panel',
        );
        final afterRecords = await restored.records();
        expect(
          afterRecords.map((r) => '${r.id}:${r.revision}:${r.enteredAmount}'),
          beforeRecords.map((r) => '${r.id}:${r.revision}:${r.enteredAmount}'),
        );
        for (final record in afterRecords) {
          expect([
            for (final revision in await restored.history(record.id))
              '${revision.revision}:${revision.enteredAmount}:'
                  '${revision.isVoided}',
          ], beforeHistory[record.id]);
        }
        await expectLater(
          restored.createItem(
            commandId: 'v16-item',
            name: 'Stale replay',
            form: 'Tablet',
            unit: 'count',
            type: 'Medicine',
          ),
          throwsA(
            isA<CommandConflict>().having(
              (error) => error.code,
              'code',
              'deleted_context',
            ),
          ),
        );
      } finally {
        await restored.close();
      }

      final db = raw(archivePath);
      try {
        expect(
          db.select('SELECT count(*) c FROM ordinary_draft').single['c'],
          0,
        );
        expect(
          db.select('SELECT count(*) c FROM operation').single['c'],
          greaterThan(0),
        );
        expect(
          db
              .select(
                "SELECT count(*) c FROM operation WHERE result<>'{\"invalidated\":true}'",
              )
              .single['c'],
          0,
        );
        for (final table in [
          'reminder_request',
          'reminder_pending',
          'event_pending',
          'event_end_request',
          'attachment_job',
          'attachment_pin',
        ]) {
          expect(
            db.select('SELECT count(*) c FROM "$table"').single['c'],
            0,
            reason: table,
          );
        }
        final meta = db.select('SELECT * FROM reminder_meta').single;
        expect(meta['namespace'], prepared.reminderNamespace);
        expect(meta['sequence'], 0);
        expect(meta['fingerprint'], '');
        expect(
          db.select('SELECT value FROM setting WHERE key=?', [
            'v16-capture',
          ]).single['value'],
          'preserve',
        );
        expect(
          db.select('SELECT count(*) c FROM attachment_record').single['c'],
          1,
        );
        expect(
          db.select('SELECT id,state FROM attachment_record').single['id'],
          'fixture-ready-attachment',
        );
        expect(
          db.select('SELECT count(*) c FROM attachment_chunk WHERE version=?', [
            'fixture-ready-version',
          ]).single['c'],
          1,
        );
        expect(
          db.select('SELECT count(*) c FROM attachment_chunk').single['c'],
          1,
        );
        expect(db.select('PRAGMA user_version').single.values.single, 21);
      } finally {
        db.close();
      }
    },
  );

  test('rejects quantity text that disagrees with its stored scale', () async {
    final archivePath = '${directory.path}/bad-quantity.sqlite';
    final generation = live.generation;
    await live.close();
    await File(livePath).copy(archivePath);
    live = await openFixtureStore(livePath);
    final db = raw(archivePath);
    try {
      final row = db
          .select('SELECT record,revision FROM revision LIMIT 1')
          .single;
      db.execute(
        'UPDATE revision SET entered=? WHERE record=? AND revision=?',
        ['999', row['record'], row['revision']],
      );
    } finally {
      db.close();
    }
    await expectLater(
      live.prepareRestoredDatabase(
        stagedPath: archivePath,
        rekeyTo: (_) async {},
      ),
      throwsA(
        isA<RestoreFailure>().having(
          (e) => e.code,
          'code',
          RestoreCodes.corrupt,
        ),
      ),
    );
    expect(live.generation, generation);
    expect(await live.records(), isNotEmpty);
  });

  test('rejects a staged snapshot with broken ownership or links', () async {
    final before = live.generation;
    final archivePath = '${directory.path}/damaged.sqlite';
    await live.close();
    await File(livePath).copy(archivePath);
    live = await openFixtureStore(livePath);
    final db = raw(archivePath);
    try {
      const other = 'missing-person';
      db.execute('PRAGMA foreign_keys=OFF');
      db.execute("UPDATE attachment_record SET person=? WHERE id=?", [
        other,
        'fixture-ready-attachment',
      ]);
    } finally {
      db.close();
    }
    await expectLater(
      live.prepareRestoredDatabase(
        stagedPath: archivePath,
        rekeyTo: (_) async {},
      ),
      throwsA(
        isA<RestoreFailure>().having(
          (error) => error.code,
          'code',
          RestoreCodes.corrupt,
        ),
      ),
    );
    expect(live.generation, before);
  });
}
