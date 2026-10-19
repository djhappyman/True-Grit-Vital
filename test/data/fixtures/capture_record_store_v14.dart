// Synthetic v14 capture using the frozen pre-event package configuration.
import 'dart:io';

import 'package:true_grit_vital/data/record_store.dart';
import 'package:sqlite3/sqlite3.dart';

Future<void> main(List<String> args) async {
  final dir = await Directory.systemTemp.createTemp('vital-v14-capture-');
  final path = '${dir.path}/fixture.db';
  final key = List.generate(32, (i) => i + 1);
  final store = await RecordStore.open(path: path, key: key, isNew: true);
  final item = await store.createItem(
    commandId: 'v14-item',
    name: 'V14 synthetic source',
    form: 'tablet',
    unit: 'count',
    type: 'medicine',
  );
  final command = CombinedUseCommand(
    commandId: 'v14-combined',
    expectedGeneration: store.generation,
    personId: meId,
    expectedPersonRevision: 1,
    actualAt: DateTime.utc(2026, 10, 15, 12),
    components: [
      for (var i = 0; i < 2; i++)
        CombinedUseComponent(
          itemId: item.id,
          expectedItemRevision: 1,
          enteredAmount: '1',
          siteLabel: i == 0 ? 'V14 synthetic site' : null,
        ),
    ],
  );
  await store.recordCombined(command);
  await store.writeSetting('v14-capture', 'preserve');
  await store.close();
  final db = sqlite3.open(path);
  db.execute("PRAGMA cipher='chacha20'");
  db.execute(
    'PRAGMA key="x\'${key.map((v) => v.toRadixString(16).padLeft(2, '0')).join()}\'"',
  );
  if (db.select('PRAGMA user_version').single.values.single != 14) {
    throw StateError('capture_requires_frozen_v14_package');
  }
  final out = StringBuffer(
    '-- Frozen populated schema14, generated from pre-event runtime. Synthetic data only.\nPRAGMA foreign_keys=OFF;\n',
  );
  final entities = db.select(
    "SELECT type,name,sql FROM sqlite_master WHERE sql IS NOT NULL AND name NOT LIKE 'sqlite_%' ORDER BY CASE type WHEN 'table' THEN 0 WHEN 'index' THEN 1 ELSE 2 END,name",
  );
  for (final t in entities.where((r) => r['type'] == 'table')) {
    out.writeln('${t['sql']};');
    final name = t['name'] as String;
    final rows = db.select('SELECT * FROM "${name.replaceAll('"', '""')}"');
    String literal(Object? v) => v == null
        ? 'NULL'
        : v is num
        ? '$v'
        : "'${(v as String).replaceAll("'", "''")}'";
    for (final row in rows) {
      out.writeln(
        'INSERT INTO "$name" VALUES (${row.values.map(literal).join(',')});',
      );
    }
  }
  for (final e in entities.where((r) => r['type'] != 'table')) {
    out.writeln('${e['sql']};');
  }
  out.writeln('PRAGMA user_version=14;\nPRAGMA foreign_keys=ON;');
  File(args.single).writeAsStringSync(out.toString());
  db.close();
  await dir.delete(recursive: true);
  stdout.writeln('PASS captured populated schema14 ${args.single}');
}
