// Frozen synthetic v19 capture, run before schema20 query-projection edits.
// Starts from the unchanged v18 fixture, upgrades through the real schema19
// migration, then saves supporting records with exact, day-only and unknown
// dates so the schema20 migration is exercised against populated parent rows.
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

    SupportingProvenance provenance({
      String laboratoryId = 'v19-lab',
      String laboratoryName = 'Synthetic laboratory',
    }) => SupportingProvenance(
      mode: SupportingProvenanceMode.manualTranscription,
      laboratoryId: laboratoryId,
      laboratoryName: laboratoryName,
      methodId: 'v19-method',
      methodText: 'Synthetic method',
      specimenId: 'v19-serum',
      specimenText: 'Serum',
    );

    LabResultSnapshot result(
      String id,
      String metric,
      String value, {
      String? unit = 'mg/L',
    }) => LabResultSnapshot(
      id: id,
      metricId: metric,
      markerName: 'Synthetic marker $metric',
      value: SupportingValue.numeric(value),
      unit: unit,
      referenceRange: SourceReferenceRange(originalText: 'Source range'),
    );

    await store.saveLabPanel(
      SaveLabPanelCommand(
        commandId: 'v19-panel-exact',
        generation: store.generation,
        expectedPersonRevision: 1,
        panel: LabPanelSnapshot(
          id: SupportingRecordId(id: 'v19-panel-exact', personId: meId),
          title: 'Synthetic exact panel',
          collectionDate: SupportingDate.exact(
            DateTime.utc(2026, 10, 1, 23),
            zoneId: 'UTC',
            utcOffsetMinutes: 0,
          ),
          reportDate: SupportingDate.exact(
            DateTime.utc(2026, 10, 4, 9),
            zoneId: 'Europe/London',
            utcOffsetMinutes: 60,
          ),
          provenance: provenance(),
          results: [
            result('exact-a', 'v19-metric-a', '1.5'),
            result('exact-b', 'v19-metric-b', '<0.1'),
          ],
        ),
      ),
    );
    await store.saveLabPanel(
      SaveLabPanelCommand(
        commandId: 'v19-panel-day',
        generation: store.generation,
        expectedPersonRevision: 1,
        panel: LabPanelSnapshot(
          id: SupportingRecordId(id: 'v19-panel-day', personId: meId),
          title: 'Synthetic day panel',
          collectionDate: SupportingDate.day(
            CivilDate(2026, 10, 2),
            zoneId: 'Asia/Tokyo',
          ),
          reportDate: SupportingDate.unknown(),
          provenance: provenance(
            laboratoryId: 'v19-lab-two',
            laboratoryName: 'Synthetic second laboratory',
          ),
          results: [result('day-a', 'v19-metric-a', '2.25')],
        ),
      ),
    );
    await store.saveObservation(
      SaveObservationCommand(
        commandId: 'v19-observation-unknown',
        generation: store.generation,
        expectedPersonRevision: 1,
        observation: ObservationSnapshot(
          id: SupportingRecordId(id: 'v19-observation-unknown', personId: meId),
          title: 'Synthetic unknown observation',
          measuredDate: SupportingDate.unknown(originalText: 'Date not given'),
          provenance: SupportingProvenance(
            mode: SupportingProvenanceMode.manualObservation,
          ),
          components: [
            LabResultSnapshot(
              id: 'unknown-a',
              metricId: 'v19-observation-a',
              markerName: 'Synthetic observation',
              value: SupportingValue.numeric('0'),
              unit: null,
            ),
          ],
        ),
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
        '-- Frozen populated schema19, synthetic data. Captured before schema20 query projections.\nPRAGMA foreign_keys=OFF;\n',
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
    } finally {
      db.close();
    }
  } finally {
    await store?.close();
    await dir.delete(recursive: true);
  }
}
