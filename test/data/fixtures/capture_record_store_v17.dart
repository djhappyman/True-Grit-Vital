// Frozen synthetic v17 capture. Run only against the schema-17 source revision.
// Starts from the unchanged populated v16 fixture, then uses real v17 commands.
import 'dart:io';
import 'dart:typed_data';

import 'package:sqlite3/sqlite3.dart';
import 'package:true_grit_vital/data/record_store.dart';

Future<void> main(List<String> args) async {
  final dir = await Directory.systemTemp.createTemp('vital-v17-capture-');
  final key = List.generate(32, (i) => i + 1);
  final hex = key.map((v) => v.toRadixString(16).padLeft(2, '0')).join();
  Database open(String path) {
    final db = sqlite3.open(path);
    db.execute("PRAGMA cipher='chacha20'");
    db.execute("PRAGMA key=\"x'$hex'\"");
    return db;
  }

  RecordStore? store;
  try {
    final path = '${dir.path}/db';
    final initial = open(path);
    initial.execute(
      File('test/data/fixtures/record_store_v16.sql').readAsStringSync(),
    );
    initial.close();
    store = await RecordStore.open(path: path, key: key, isNew: false);
    for (var i = 0; i < 3; i++) {
      final item = await store.createItem(
        commandId: 'v17-item-$i',
        name: 'Synthetic v17 source $i',
        form: 'tablet',
        unit: 'count',
        type: 'medicine',
      );
      final amount = PlannedAmount(
        quantity: ExactQuantity.parse('1'),
        enteredText: '1',
        unit: 'count',
      );
      final day = CivilDate(2026, 10, 25);
      await store.saveDailyPlan(
        commandId: 'v17-plan-$i',
        plan: DailyPlanVersion(
          personId: meId,
          planId: 'v17-plan-$i',
          itemId: item.id,
          versionId: 'v17-version-$i',
          start: day,
          timing: i == 0
              ? DailyCount(2, amount)
              : DailySlots([
                  DailySlot(
                    id: 'repeat',
                    time: WallTime(1, 30),
                    reminderEnabled: false,
                    amount: amount,
                  ),
                ]),
          zoneBasis: FixedHome('Europe/London'),
        ),
        expectedPersonRevision: 1,
        expectedGeneration: store.generation,
      );
      final rows = await store.dailyRows(
        from: day,
        toExclusive: day.addDays(1),
        observedZone: 'Europe/London',
      );
      final row = rows.rows.singleWhere((r) => r.expectation.itemId == item.id);
      final action = await store.actDaily(
        commandId: 'v17-action-$i',
        row: row,
        kind: i == 2 ? DailyActionKind.taken : DailyActionKind.skip,
        actualAt: i == 2 ? DateTime.utc(2026, 10, 25, 2, 15) : null,
      );
      if (i == 0) {
        await store.undoDaily(
          commandId: 'v17-undo',
          row: (await store.dailyRows(
            from: day,
            toExclusive: day.addDays(1),
            observedZone: 'Europe/London',
          )).rows.singleWhere((r) => r.expectation.itemId == item.id),
          action: action,
        );
        final refreshed = await store.dailyRows(
          from: day,
          toExclusive: day.addDays(1),
          observedZone: 'Europe/London',
        );
        await store.actDaily(
          commandId: 'v17-reskip',
          row: refreshed.rows.singleWhere(
            (r) => r.expectation.itemId == item.id,
          ),
          kind: DailyActionKind.skip,
        );
      }
    }
    await store.close();
    store = null;
    final db = open(path);
    try {
      if (db.select('PRAGMA user_version').single.values.single != 17) {
        throw StateError('capture_requires_schema17_source');
      }
      final out = StringBuffer(
        '-- Frozen populated schema17. Synthetic data only; derived from unchanged v16 plus real v17 commands.\nPRAGMA foreign_keys=OFF;\n',
      );
      final entities = db.select(
        "SELECT type,name,sql FROM sqlite_master WHERE sql IS NOT NULL AND name NOT LIKE 'sqlite_%' ORDER BY CASE type WHEN 'table' THEN 0 WHEN 'index' THEN 1 ELSE 2 END,name",
      );
      String literal(Object? v) => v == null
          ? 'NULL'
          : v is Uint8List
          ? "X'${v.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}'"
          : v is num
          ? '$v'
          : "'${(v as String).replaceAll("'", "''")}'";
      for (final t in entities.where((r) => r['type'] == 'table')) {
        out.writeln('${t['sql']};');
        final name = t['name'] as String;
        for (final row in db.select('SELECT * FROM "$name"')) {
          out.writeln(
            'INSERT INTO "$name" VALUES (${row.values.map(literal).join(',')});',
          );
        }
      }
      for (final e in entities.where((r) => r['type'] != 'table')) {
        out.writeln('${e['sql']};');
      }
      out.writeln('PRAGMA user_version=17;\nPRAGMA foreign_keys=ON;');
      File(args.single).writeAsStringSync(out.toString());
    } finally {
      db.close();
    }
  } finally {
    await store?.close();
    await dir.delete(recursive: true);
  }
}
