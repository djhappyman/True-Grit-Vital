import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:true_grit_vital/data/record_store.dart';

void main() {
  test('schema 23 upgrades with empty pack facts and migrated history', () async {
    final directory = await Directory.systemTemp.createTemp('vital-stock-v23-');
    addTearDown(() => directory.delete(recursive: true));
    final path = '${directory.path}/records.db';
    final key = List.generate(32, (i) => i + 11);
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
    seeded.execute('ALTER TABLE revision ADD COLUMN notes TEXT');
    seeded.execute(
      "ALTER TABLE revision ADD COLUMN context_tags TEXT NOT NULL DEFAULT '[]'",
    );
    seeded.execute('ALTER TABLE daily_action ADD COLUMN reason TEXT');
    seeded.execute('PRAGMA foreign_keys=ON');
    seeded.execute(
      "INSERT OR IGNORE INTO person(id,name,adult_confirmed) VALUES ('me','Me',1)",
    );
    seeded.execute(
      "INSERT INTO item(id,person,name,form,unit,type) VALUES ('item-v23','me','Legacy vial','liquid','ml','medicine')",
    );
    seeded.execute(
      "INSERT INTO stock_container(id,person,item,label,unit,strength,revision,sequence,measurement_sequence,balance_status,numerator,denominator,refill,notice_eligible,notice_active) VALUES ('container-v23','me','item-v23','Legacy bottle','ml','{\"ingredient\":\"item-v23\",\"label\":\"5 mg/ml\",\"pair\":[\"5\",\"1\"]}',2,0,0,'known','4','1',0,0,1)",
    );
    seeded.execute(
      "INSERT INTO stock_movement(id,person,container,sequence,kind,numerator,denominator,strength,operation,generation,recorded_at) VALUES ('movement-v23','me','container-v23',1,'restock','4','1','{\"ingredient\":\"item-v23\",\"label\":\"5 mg/ml\",\"pair\":[\"5\",\"1\"]}','op-v23',(SELECT generation FROM dataset),1)",
    );
    seeded.execute('PRAGMA user_version=23');
    expect(seeded.select("SELECT id FROM person WHERE id='me'").length, 1);
    final fkRows = seeded.select('PRAGMA foreign_key_check');
    expect(fkRows.length, 0, reason: '$fkRows');
    expect(seeded.select('SELECT generation FROM dataset').length, 1);
    seeded.close();

    final store = await RecordStore.open(path: path, key: key, isNew: false);
    addTearDown(store.close);
    final check = raw();
    addTearDown(check.close);
    expect(
      check.select('PRAGMA user_version').single.values.single,
      currentRecordSchemaVersion,
    );
    final columns = check
        .select('PRAGMA table_info(stock_container)')
        .map((row) => row['name'])
        .toSet();
    expect(
      columns,
      containsAll(['lot', 'expiry_date', 'capacity_n', 'capacity_d']),
    );
    final container = (await store.stockContainerById(
      personId: meId,
      containerId: 'container-v23',
    ))!;
    expect(container.lot, isNull);
    expect(container.expiryDate, isNull);
    expect(container.capacity, isNull);
    expect(container.balance.value, ExactAmount(BigInt.from(4)));
    expect(container.strength.label, '5 mg/ml');
    final history = await store.stockMetadataHistory(
      personId: meId,
      containerId: 'container-v23',
    );
    expect(history, hasLength(1));
    expect(history.single.source, 'migrated');
    expect(history.single.revision, 2);
    expect(check.select('PRAGMA foreign_key_check'), isEmpty);
    expect(check.select('PRAGMA integrity_check').single.values.single, 'ok');

    final updated = await store.updateStockMetadata(
      commandId: 'details-after-upgrade',
      personId: meId,
      expectedPersonRevision: 1,
      expectedGeneration: store.generation,
      containerId: container.id,
      expectedContainerRevision: container.revision,
      lot: 'NEW-LOT',
      expiryDate: CivilDate(2027, 1, 2),
      capacity: ExactAmount(BigInt.from(4)),
    );
    expect(updated.revision, container.revision + 1);
    expect(updated.lot, 'NEW-LOT');
    expect(updated.expiryDate, CivilDate(2027, 1, 2));
  });
}
