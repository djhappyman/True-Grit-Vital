// Frozen synthetic v19 capture for the schema21 recovery migration checks.
// Run before the schema21 edits: starts from the frozen v18 fixture, upgrades
// through the real store, adds one supporting panel, one correction and a
// supporting draft, then dumps every row and entity.
// Pass test/data/fixtures/record_store_v19_recovery.sql as the only argument;
// never overwrite Agent A's independent record_store_v19.sql fixture.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:sqlite3/sqlite3.dart';
import 'package:true_grit_vital/data/record_store.dart';

Future<void> main(List<String> args) async {
  final dir = await Directory.systemTemp.createTemp('vital-v19-capture-');
  final key = List.generate(32, (i) => i + 1);
  final hex = key.map((v) => v.toRadixString(16).padLeft(2, '0')).join();
  Database open(String path) {
    final db = sqlite3.open(path);
    db.execute("PRAGMA cipher='chacha20'");
    db.execute("PRAGMA key=\"x'$hex'\"");
    db.execute('PRAGMA foreign_keys=ON');
    return db;
  }

  RecordStore? store;
  try {
    final path = '${dir.path}/db';
    final initial = open(path);
    initial.execute(
      File('test/data/fixtures/record_store_v18.sql').readAsStringSync(),
    );
    initial.close();
    store = await RecordStore.open(path: path, key: key, isNew: false);
    final panel = LabPanelSnapshot(
      id: SupportingRecordId(id: 'v19-panel', personId: meId),
      title: 'Synthetic v19 report',
      collectionDate: SupportingDate.day(CivilDate(2026, 10, 19)),
      reportDate: SupportingDate.partial(
        originalText: 'October 2026',
        year: 2026,
        month: 10,
      ),
      provenance: SupportingProvenance(
        mode: SupportingProvenanceMode.manualTranscription,
        laboratoryId: 'v19-lab',
        laboratoryName: 'Synthetic laboratory',
        methodId: 'v19-method',
        specimenId: 'v19-specimen',
      ),
      results: [
        LabResultSnapshot(
          id: 'v19-result',
          metricId: 'v19-metric',
          markerName: 'Synthetic marker',
          value: SupportingValue.numeric('1.50'),
          unit: 'mg/L',
        ),
      ],
    );
    await store.saveLabPanel(
      SaveLabPanelCommand(
        commandId: 'v19-save',
        generation: store.generation,
        expectedPersonRevision: 1,
        panel: panel,
      ),
    );
    await store.voidSupportingRecord(
      VoidSupportingRecordCommand(
        commandId: 'v19-void',
        generation: store.generation,
        personId: meId,
        id: panel.id.id,
        expectedPersonRevision: 1,
        expectedRevision: 1,
        isVoided: true,
      ),
    );
    await store.saveDraft(
      OrdinaryDraft(
        id: 'v19-supporting-draft',
        generation: store.generation,
        operationId: 'v19-supporting-operation',
        kind: DraftKind.labPanel,
        personId: meId,
        personRevision: 1,
        targetId: panel.id.id,
        targetRevision: 2,
        fields: {'payload': '{"synthetic":true}', 'frozen': 'true'},
      ),
    );
    await store.close();
    store = null;
    final db = open(path);
    try {
      if (db.select('PRAGMA user_version').single.values.single != 19) {
        throw StateError('capture_requires_schema19_source');
      }
      final out = StringBuffer(
        '-- Frozen populated schema19, synthetic data captured before the v21 recovery rebuild.\nPRAGMA foreign_keys=OFF;\n',
      );
      final entities = db.select(
        "SELECT type,name,sql FROM sqlite_master WHERE sql IS NOT NULL AND name NOT LIKE 'sqlite_%' ORDER BY CASE type WHEN 'table' THEN 0 WHEN 'index' THEN 1 ELSE 2 END,name",
      );
      String literal(Object? value) => value == null
          ? 'NULL'
          : value is Uint8List
          ? "X'${value.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}'"
          : value is num
          ? '$value'
          : "'${(value as String).replaceAll("'", "''")}'";
      for (final table in entities.where((r) => r['type'] == 'table')) {
        out.writeln('${table['sql']};');
        final name = table['name'] as String;
        for (final row in db.select('SELECT * FROM "$name"')) {
          out.writeln(
            'INSERT INTO "$name" VALUES (${row.values.map(literal).join(',')});',
          );
        }
      }
      for (final entity in entities.where((r) => r['type'] != 'table')) {
        out.writeln('${entity['sql']};');
      }
      out.writeln('PRAGMA user_version=19;\nPRAGMA foreign_keys=ON;');
      File(args.single).writeAsStringSync(out.toString());
      stdout.writeln('captured schema19 ${jsonEncode(rows(db))}');
    } finally {
      db.close();
    }
  } finally {
    await store?.close();
    await dir.delete(recursive: true);
  }
}

Map<String, int> rows(Database db) => {
  for (final row in db.select(
    "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'",
  ))
    row['name'] as String:
        db.select('SELECT COUNT(*) AS n FROM "${row['name']}"').single['n']
            as int,
};
