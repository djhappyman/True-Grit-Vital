// Encrypted schema18 migration process-loss boundaries using the real SQL step.
import 'dart:convert';
import 'dart:io';

import 'package:sqlite3/sqlite3.dart';
import 'package:true_grit_vital/data/record_store.dart';

Future<void> main(List<String> args) async {
  final directory = args[0], mode = args[1];
  final path = '$directory/migration.db';
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

  String snapshots(Database db) => jsonEncode({
    for (final table
        in db
            .select(
              "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name",
            )
            .map((r) => r['name'] as String))
      table: db
          .select(
            table == 'attachment_link'
                ? 'SELECT attachment,person,item,record FROM attachment_link'
                : table == 'daily_action'
                ? 'SELECT id,bucket,person,kind,record,revision,undone,sequence,recorded_at FROM daily_action'
                : 'SELECT * FROM "$table"',
          )
          .map(
            (r) => r.values
                .map((v) => v is List<int> ? base64Encode(v) : v)
                .toList(),
          )
          .toList(),
  });
  if (mode == 'init') {
    final db = raw();
    db.execute(
      File('test/data/fixtures/record_store_v17.sql').readAsStringSync(),
    );
    File('$directory/before.json').writeAsStringSync(snapshots(db));
    db.close();
  } else if (mode.startsWith('before-')) {
    final db = raw();
    db.execute('BEGIN');
    final statements = int.parse(mode.substring('before-'.length));
    for (final sql in historySchemaV18.take(statements)) {
      db.execute(sql);
    }
    if (statements == historySchemaV18.length) {
      db.execute('PRAGMA user_version=18');
    }
    // Deliberate process loss: do not close or commit this connection.
    exit(91);
  } else {
    if (mode == 'verify-old-retry') {
      final db = raw();
      if (db.select('PRAGMA user_version').single.values.single != 17 ||
          db
              .select('PRAGMA table_info(daily_action)')
              .any((r) => r['name'] == 'occurs_at')) {
        throw StateError('migration_not_rolled_back');
      }
      if (snapshots(db) != File('$directory/before.json').readAsStringSync()) {
        throw StateError('migration_rows_changed');
      }
      db.close();
    }
    final store = await RecordStore.open(path: path, key: key, isNew: false);
    if (mode == 'after') exit(92);
    final page = await store.timeline(
      TimelineQuery(filter: TimelineFilter(), displayZone: 'Europe/London'),
    );
    if (page.schemaVersion != 21 || page.entries.length != 4) {
      throw StateError('migration_reader');
    }
    await store.close();
    final db = raw();
    final original = jsonDecode(
      File('$directory/before.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final current = jsonDecode(snapshots(db)) as Map<String, dynamic>;
    if (original.entries.any(
          (e) => jsonEncode(current[e.key]) != jsonEncode(e.value),
        ) ||
        db.select('PRAGMA foreign_key_check').isNotEmpty ||
        db.select('PRAGMA integrity_check').single.values.single != 'ok') {
      throw StateError('migration_integrity');
    }
    if (db
        .select(
          'SELECT d.id FROM daily_action d JOIN daily_expectation e ON e.id=d.bucket AND e.person=d.person WHERE d.occurs_at IS NULL OR d.occurs_at!=e.occurs_at',
        )
        .isNotEmpty) {
      throw StateError('migration_projection');
    }
    db.close();
  }
  stdout.writeln('PASS history schema18 $mode');
}
