import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:true_grit_vital/data/record_store.dart';

void main() {
  late Directory directory;
  final key = List.generate(32, (i) => i + 9);

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('vital-context-v21-');
  });

  tearDown(() async => directory.delete(recursive: true));

  test(
    'version 21 upgrades directly to 23 with empty context columns',
    () async {
      final path = '${directory.path}/records.db';
      final db = sqlite3.open(path);
      final hex = key.map((v) => v.toRadixString(16).padLeft(2, '0')).join();
      db.execute("PRAGMA cipher='chacha20'");
      db.execute("PRAGMA key=\"x'$hex'\"");
      db.execute('PRAGMA foreign_keys=ON');
      db.execute(
        File('test/data/fixtures/record_store_v19.sql').readAsStringSync(),
      );
      // Build the version 21 shape with the same steps the store applies, so
      // this test exercises the direct 21 to 23 upgrade rather than a chain
      // from an older fixture.
      db.execute('PRAGMA foreign_keys=OFF');
      for (final sql in supportingSchemaV20) {
        db.execute(sql);
      }
      db.execute('PRAGMA user_version=20');
      db.execute('ALTER TABLE ordinary_draft RENAME TO ordinary_draft_v20');
      db.execute(supportingVoidDraftSchemaV21);
      db.execute('INSERT INTO ordinary_draft SELECT * FROM ordinary_draft_v20');
      db.execute('DROP TABLE ordinary_draft_v20');
      db.execute('PRAGMA user_version=21');
      db.execute('PRAGMA foreign_keys=ON');
      final before = db
          .select('SELECT COUNT(*) AS n FROM revision')
          .single['n'];
      final skipBefore = db
          .select('SELECT COUNT(*) AS n FROM daily_action')
          .single['n'];
      db.close();

      final store = await RecordStore.open(path: path, key: key, isNew: false);
      addTearDown(store.close);
      final raw = sqlite3.open(path);
      addTearDown(raw.close);
      raw.execute("PRAGMA cipher='chacha20'");
      raw.execute("PRAGMA key=\"x'$hex'\"");
      expect(raw.select('PRAGMA user_version').single.values.single, currentRecordSchemaVersion);
      final revisionColumns = raw
          .select('PRAGMA table_info(revision)')
          .map((row) => row['name'])
          .toSet();
      expect(revisionColumns, containsAll(['notes', 'context_tags']));
      expect(
        raw.select('PRAGMA table_info(daily_action)').map((row) => row['name']),
        contains('reason'),
      );
      expect(
        raw.select('SELECT COUNT(*) AS n FROM revision').single['n'],
        before,
      );
      expect(
        raw.select('SELECT COUNT(*) AS n FROM daily_action').single['n'],
        skipBefore,
      );
      expect(
        raw
            .select(
              'SELECT COUNT(*) AS n FROM revision WHERE context_tags=\'[]\'',
            )
            .single['n'],
        before,
      );
      expect(
        raw
            .select(
              'SELECT COUNT(*) AS n FROM daily_action WHERE reason IS NULL',
            )
            .single['n'],
        skipBefore,
      );
      expect(raw.select('PRAGMA foreign_key_check'), isEmpty);

      final records = await store.records();
      expect(records.first.notes, isNull);
      expect(records.first.contextTags, isEmpty);
      final item = await store.createItem(
        commandId: 'new-item',
        name: 'Synthetic migrated item',
        form: 'tablet',
        unit: 'mg',
        type: 'medicine',
      );
      final written = await store.record(
        commandId: 'new-record',
        itemId: item.id,
        amount: '1',
        actualAt: DateTime.utc(2026, 10, 20),
        context: const DoseContext(
          notes: 'Saved after upgrade.',
          contextTags: ['Morning'],
        ),
      );
      expect(written.notes, 'Saved after upgrade.');
      expect(written.contextTags, ['Morning']);
    },
  );
}
