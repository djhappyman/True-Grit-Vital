import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:true_grit_vital/data/record_store.dart';

void main() {
  late Directory dir;
  late String path;
  final key = List.generate(32, (i) => i + 1);
  Database raw() {
    final db = sqlite3.open(path);
    db.execute("PRAGMA cipher='chacha20'");
    db.execute(
      'PRAGMA key="x\'${key.map((v) => v.toRadixString(16).padLeft(2, '0')).join()}\'"',
    );
    db.execute('PRAGMA foreign_keys=ON');
    return db;
  }

  Map<String, String> rows(Database db) => {
    for (final row in db.select(
      "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name",
    ))
      row['name'] as String: jsonEncode(
        db
            .select(
              row['name'] == 'attachment_link'
                  ? 'SELECT attachment,person,item,record FROM attachment_link ORDER BY rowid'
                  : 'SELECT * FROM "${row['name']}" ORDER BY rowid',
            )
            .map(
              (r) => r.values
                  .map((v) => v is List<int> ? base64Encode(v) : v)
                  .toList(),
            )
            .toList(),
      ),
  };
  Future<void> upgrade() async {
    final store = await RecordStore.open(path: path, key: key, isNew: false);
    await store.close();
  }

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('vital-supporting-migration-');
    path = '${dir.path}/db';
    final db = raw();
    db.execute(
      File('test/data/fixtures/record_store_v18.sql').readAsStringSync(),
    );
    db.close();
  });
  tearDown(() async => dir.delete(recursive: true));
  test('populated18 retains every old row, protected bytes, jobs, pins, drafts and skip ordering', () async {
    final before = raw();
    final expected = rows(before);
    final indexes = before
        .select(
          "SELECT name,sql FROM sqlite_master WHERE type='index' AND name LIKE 'history_skip_%'",
        )
        .map((r) => r.values.toList())
        .toList();
    expect(
      before.select('SELECT COUNT(*) AS n FROM attachment_pin').single['n'],
      greaterThan(0),
    );
    expect(
      before.select('SELECT COUNT(*) AS n FROM attachment_chunk').single['n'],
      greaterThan(0),
    );
    before.close();
    await upgrade();
    final after = raw();
    final actual = rows(after);
    for (final entry in expected.entries) {
      expect(actual[entry.key], entry.value, reason: entry.key);
    }
    expect(after.select('PRAGMA user_version').single.values.single, 19);
    expect(after.select('PRAGMA integrity_check').single.values.single, 'ok');
    expect(after.select('PRAGMA foreign_key_check'), isEmpty);
    expect(
      after
          .select(
            "SELECT name,sql FROM sqlite_master WHERE type='index' AND name LIKE 'history_skip_%'",
          )
          .map((r) => r.values.toList())
          .toList(),
      indexes,
    );
    expect(
      after.select(
        "SELECT name FROM sqlite_master WHERE name LIKE 'supporting_%v18'",
      ),
      isEmpty,
    );
    after.close();
  });
  for (final collision in [
    'supporting_record',
    'supporting_manifest_v18',
    'attachment_target',
  ]) {
    test(
      '$collision collision rolls back whole migration and permits retry',
      () async {
        final db = raw();
        if (collision == 'attachment_target') {
          // This existing index is recreated near the end. A same-named table
          // survives its parent drop and forces a late transactional failure.
          db.execute('DROP INDEX attachment_target');
        }
        db.execute('CREATE TABLE "$collision"(recovery TEXT)');
        db.execute('INSERT INTO "$collision" VALUES (?)', ['preserve']);
        final expected = rows(db);
        db.close();
        await expectLater(upgrade(), throwsA(anything));
        final failed = raw();
        expect(failed.select('PRAGMA user_version').single.values.single, 18);
        expect(rows(failed), expected);
        expect(failed.select('PRAGMA foreign_key_check'), isEmpty);
        failed.execute('DROP TABLE "$collision"');
        failed.close();
        await upgrade();
      },
    );
  }
  test(
    'unexpected manifest child rejects before DDL without losing recovery data',
    () async {
      final db = raw();
      db.execute(
        'CREATE TABLE future_child(id TEXT REFERENCES attachment_record(id))',
      );
      final expected = rows(db);
      db.close();
      await expectLater(
        upgrade(),
        throwsA(
          predicate(
            (e) =>
                e.toString().contains('supporting_attachment_migration_review'),
          ),
        ),
      );
      final failed = raw();
      expect(rows(failed), expected);
      expect(failed.select('PRAGMA user_version').single.values.single, 18);
      failed.close();
    },
  );
}
