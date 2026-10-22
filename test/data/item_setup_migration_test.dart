import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:true_grit_vital/data/record_store.dart';

void main() {
  test(
    'version 22 retains authored detail, setup and draft during upgrade to 23',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'vital-setup-v22-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final path = '${directory.path}/records.db';
      final key = List.generate(32, (i) => i + 7);
      final hex = key.map((v) => v.toRadixString(16).padLeft(2, '0')).join();
      Database raw() {
        final db = sqlite3.open(path);
        db.execute("PRAGMA cipher='chacha20'");
        db.execute("PRAGMA key=\"x'$hex'\"");
        return db;
      }

      final seeded = raw();
      seeded.execute(
        File('test/data/fixtures/record_store_v19.sql').readAsStringSync(),
      );
      seeded.execute('PRAGMA foreign_keys=OFF');
      for (final sql in supportingSchemaV20) {
        seeded.execute(sql);
      }
      seeded.execute('ALTER TABLE ordinary_draft RENAME TO ordinary_draft_v20');
      seeded.execute(supportingVoidDraftSchemaV21);
      seeded.execute(
        'INSERT INTO ordinary_draft SELECT * FROM ordinary_draft_v20',
      );
      seeded.execute('DROP TABLE ordinary_draft_v20');
      for (final sql in itemDetailSchemaV22) {
        seeded.execute(sql);
      }
      seeded.execute('ALTER TABLE ordinary_draft RENAME TO ordinary_draft_v21');
      seeded.execute(itemDetailDraftSchemaV22);
      seeded.execute(
        'INSERT INTO ordinary_draft SELECT * FROM ordinary_draft_v21',
      );
      seeded.execute('DROP TABLE ordinary_draft_v21');
      seeded.execute(
        "CREATE INDEX ordinary_draft_supporting_void ON ordinary_draft(person,target) WHERE kind='supportingVoid'",
      );
      final itemId =
          seeded.select('SELECT id FROM item WHERE person=? LIMIT 1', [
                meId,
              ]).single['id']
              as String;
      final generation =
          seeded.select('SELECT generation FROM dataset').single['generation']
              as String;
      seeded.execute('INSERT INTO item_detail VALUES (?,?,?,?,?,?)', [
        itemId,
        meId,
        'Authored 0.125 mg instruction',
        'Private exact note',
        2,
        100,
      ]);
      seeded.execute('INSERT INTO item_setup VALUES (?,?,?,?,?,?,?,?,?)', [
        itemId,
        meId,
        generation,
        1,
        0,
        0,
        100,
        100,
        null,
      ]);
      final draft = OrdinaryDraft(
        id: 'details-v22',
        generation: generation,
        operationId: 'details-operation-v22',
        kind: DraftKind.itemDetails,
        personId: meId,
        personRevision: 1,
        targetId: itemId,
        targetRevision: 2,
        fields: const {
          'instructions': 'Unfinished text',
          'notes': 'Unfinished private note',
        },
      );
      seeded.execute('INSERT INTO ordinary_draft VALUES (?,?,?,?,?,?,?,?,?)', [
        draft.id,
        generation,
        draft.operationId,
        draft.kind.name,
        meId,
        1,
        itemId,
        2,
        draft.encode(),
      ]);
      final beforeCount = seeded
          .select('SELECT COUNT(*) AS n FROM revision')
          .single['n'];
      seeded.execute('PRAGMA user_version=22');
      seeded.close();

      final store = await RecordStore.open(path: path, key: key, isNew: false);
      addTearDown(store.close);
      final detail = (await store.itemDetail(itemId))!;
      expect(detail.instructions, 'Authored 0.125 mg instruction');
      expect(detail.notes, 'Private exact note');
      expect(detail.revision, 2);
      expect((await store.itemSetup(itemId))!.scheduleSkipped, isTrue);
      expect((await store.draftById(draft.id))!.fields, draft.fields);
      final check = raw();
      addTearDown(check.close);
      expect(check.select('PRAGMA user_version').single.values.single, currentRecordSchemaVersion);
      expect(
        check.select('SELECT COUNT(*) AS n FROM revision').single['n'],
        beforeCount,
      );
      expect(
        check
            .select(
              "SELECT COUNT(*) AS n FROM revision WHERE notes IS NULL AND context_tags='[]'",
            )
            .single['n'],
        beforeCount,
      );
      expect(check.select('PRAGMA foreign_key_check'), isEmpty);
      expect(check.select('PRAGMA integrity_check').single.values.single, 'ok');
    },
  );
}
