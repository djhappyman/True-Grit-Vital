// Synthetic encrypted interruption checks; the runner owns the dataset.
import 'dart:convert';
import 'dart:io';

import 'package:sqlite3/sqlite3.dart';
import 'package:true_grit_vital/data/record_store.dart';

Future<void> main(List<String> args) async {
  final directory = args[0], mode = args[1], path = '$directory/db';
  final key = List.generate(32, (i) => i + 1);
  Database raw() {
    final db = sqlite3.open(path);
    db.execute("PRAGMA cipher='chacha20'");
    db.execute(
      'PRAGMA key="x\'${key.map((v) => v.toRadixString(16).padLeft(2, '0')).join()}\'"',
    );
    db.execute('PRAGMA foreign_keys=ON');
    db.execute('PRAGMA synchronous=FULL');
    return db;
  }

  String rows(Database db) => jsonEncode({
    for (final t in db.select(
      "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name",
    ))
      t['name'] as String: db
          .select(
            t['name'] == 'attachment_link'
                ? 'SELECT attachment,person,item,record FROM attachment_link ORDER BY rowid'
                : 'SELECT * FROM "${t['name']}" ORDER BY rowid',
          )
          .map(
            (r) => r.values
                .map((v) => v is List<int> ? base64Encode(v) : v)
                .toList(),
          )
          .toList(),
  });
  if (mode == 'migration-init') {
    final db = raw();
    db.execute(
      File('test/data/fixtures/record_store_v18.sql').readAsStringSync(),
    );
    File('$directory/before.json').writeAsStringSync(rows(db));
    db.close();
  } else if (mode == 'migration-init19') {
    final db = raw();
    db.execute(
      File('test/data/fixtures/record_store_v19.sql').readAsStringSync(),
    );
    File('$directory/before.json').writeAsStringSync(rows(db));
    db.close();
  } else if (mode.startsWith('migration-before20-')) {
    final db = raw();
    db.execute('BEGIN');
    final count = int.parse(mode.substring('migration-before20-'.length));
    for (final sql in supportingSchemaV20.take(count)) {
      db.execute(sql);
    }
    exit(91);
  } else if (mode == 'migration-retry20') {
    final db = raw();
    if (db.select('PRAGMA user_version').single.values.single != 19 ||
        rows(db) != File('$directory/before.json').readAsStringSync()) {
      throw StateError('migration_not_atomic');
    }
    db.close();
  } else if (mode.startsWith('migration-before-')) {
    final db = raw();
    db.execute('BEGIN');
    final count = int.parse(mode.substring('migration-before-'.length));
    for (final sql in supportingSchemaV19.take(count)) {
      db.execute(sql);
    }
    if (count >= supportingSchemaV19.length) {
      db.execute('PRAGMA user_version=19');
    }
    exit(91);
  } else if (mode.startsWith('migration-')) {
    if (mode == 'migration-retry') {
      final db = raw();
      if (db.select('PRAGMA user_version').single.values.single != 18 ||
          rows(db) != File('$directory/before.json').readAsStringSync()) {
        throw StateError('migration_not_atomic');
      }
      db.close();
    }
    final store = await RecordStore.open(path: path, key: key, isNew: false);
    if (mode == 'migration-after') exit(92);
    await store.close();
    final db = raw();
    final before = jsonDecode(
      File('$directory/before.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final after = jsonDecode(rows(db)) as Map<String, dynamic>;
    if (before.entries.any(
          (e) => jsonEncode(e.value) != jsonEncode(after[e.key]),
        ) ||
        db.select('PRAGMA user_version').single.values.single != 21 ||
        db.select('PRAGMA foreign_key_check').isNotEmpty) {
      throw StateError('migration_integrity');
    }
    db.close();
  } else {
    final store = await RecordStore.open(
      path: path,
      key: key,
      isNew: mode == 'init',
    );
    final input = File('$directory/command.json');
    if (mode == 'init') {
      final panel = LabPanelSnapshot(
        id: SupportingRecordId(id: 'panel', personId: meId),
        title: 'Synthetic private report',
        collectionDate: SupportingDate.unknown(originalText: 'Source unknown'),
        reportDate: SupportingDate.day(CivilDate(2026, 10, 19)),
        provenance: SupportingProvenance(
          mode: SupportingProvenanceMode.manualTranscription,
        ),
        results: [
          LabResultSnapshot(
            id: 'result',
            metricId: 'metric',
            markerName: 'Source marker',
            value: SupportingValue.numeric('-0.25'),
            unit: 'source unit',
          ),
        ],
      );
      input.writeAsStringSync(
        jsonEncode(
          SaveLabPanelCommand(
            commandId: 'save',
            generation: store.generation,
            expectedPersonRevision: 1,
            panel: panel,
          ).toJson(),
        ),
      );
    } else {
      final command = SaveLabPanelCommand.fromJson(
        jsonDecode(input.readAsStringSync()) as Map<String, dynamic>,
      );
      if (mode == 'verify-old') {
        if (await store.supportingRecord(meId, 'panel') != null ||
            (await store.supportingMetrics(
              personId: meId,
              kind: SupportingMetricKind.lab,
            )).isNotEmpty) {
          throw StateError('partial_supporting_save');
        }
      } else {
        final saved = await store.saveLabPanel(
          command,
          beforeCommit: mode == 'before'
              ? () async {
                  exit(91);
                }
              : null,
        );
        if (mode == 'after') exit(92);
        if (saved.revision != 1 ||
            (await store.supportingRevisions(meId, 'panel')).length != 1 ||
            (await store.supportingMetrics(
                  personId: meId,
                  kind: SupportingMetricKind.lab,
                )).length !=
                1 ||
            saved.snapshot.results.single.value.exactAmount !=
                ExactAmount(BigInt.from(-1), BigInt.from(4))) {
          throw StateError('supporting_replay');
        }
      }
    }
    await store.close();
  }
  stdout.writeln('PASS supporting $mode');
}
