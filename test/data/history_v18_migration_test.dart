import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:true_grit_vital/data/record_store.dart';

void main() {
  late Directory dir;
  late String path;
  RecordStore? store;
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

  Future<RecordStore> upgrade() async =>
      store = await RecordStore.open(path: path, key: key, isNew: false);
  Map<String, String> savedRows(Database db) => {
    for (final table
        in db
            .select(
              "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'",
            )
            .map((r) => r['name'] as String))
      table: jsonEncode(
        db
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
      ),
  };
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('vital-schema18-');
    path = '${dir.path}/db';
    final db = raw();
    db.execute(
      File('test/data/fixtures/record_store_v17.sql').readAsStringSync(),
    );
    db.close();
  });
  tearDown(() async {
    await store?.close();
    store = null;
    await dir.delete(recursive: true);
  });
  test(
    'all frozen older schemas retain records through the schema18 chain',
    () async {
      for (final version in [
        1,
        3,
        4,
        5,
        6,
        7,
        8,
        9,
        10,
        11,
        12,
        13,
        14,
        15,
        16,
      ]) {
        path = '${dir.path}/v$version';
        final before = raw();
        before.execute(
          File('test/data/fixtures/record_store_v$version.sql')
              .readAsStringSync(),
        );
        final records = before
            .select('SELECT COUNT(*) AS count FROM administration')
            .single['count'];
        before.close();
        final upgraded = await upgrade();
        await upgraded.close();
        store = null;
        final checked = raw();
        expect(
          checked
              .select('SELECT COUNT(*) AS count FROM administration')
              .single['count'],
          records,
          reason: 'schema $version retains voided and active records',
        );
        expect(
          checked.select('PRAGMA user_version').single.values.single,
          21,
          reason: 'schema $version',
        );
        expect(
          checked.select('PRAGMA integrity_check').single.values.single,
          'ok',
          reason: 'schema $version',
        );
        expect(
          checked.select('PRAGMA foreign_key_check'),
          isEmpty,
          reason: 'schema $version',
        );
        checked.close();
      }
    },
  );
  test('populated encrypted17 upgrades without changing captured records or audits', () async {
    final beforeDb = raw();
    final before = savedRows(beforeDb);
    final expected = beforeDb
        .select(
          "SELECT d.id,e.occurs_at FROM daily_action d JOIN daily_expectation e ON e.id=d.bucket AND e.person=d.person WHERE d.kind='skip' AND d.undone=0 ORDER BY e.occurs_at DESC,d.id",
        )
        .map((r) => r['id'])
        .toList();
    beforeDb.close();
    final upgraded = await upgrade();
    final page = await upgraded.timeline(
      TimelineQuery(
        filter: TimelineFilter(status: TimelineStatus.skipped),
        displayZone: 'Pacific/Auckland',
      ),
    );
    expect(
      page.entries.map((e) => (e as SkippedTimelineEntry).action.id),
      orderedEquals(expected),
    );
    expect(page.schemaVersion, 21);
    final skips = page.entries.cast<SkippedTimelineEntry>().toList();
    expect(
      skips.singleWhere((e) => e.action.id == 'v17-reskip').savedDate,
      CivilDate(2026, 10, 25),
    );
    expect(skips.every((e) => e.planZone == 'Europe/London'), isTrue);
    await upgraded.close();
    store = null;
    final db = raw();
    expect(db.select('PRAGMA user_version').single.values.single, 21);
    final after = savedRows(db);
    for (final entry in before.entries) {
      expect(after[entry.key], entry.value, reason: entry.key);
    }
    expect(db.select('PRAGMA integrity_check').single.values.single, 'ok');
    expect(db.select('PRAGMA foreign_key_check'), isEmpty);
    expect(
      db.select(
        'SELECT d.id FROM daily_action d JOIN daily_expectation e ON e.id=d.bucket AND e.person=d.person WHERE d.occurs_at IS NULL OR d.occurs_at!=e.occurs_at',
      ),
      isEmpty,
    );
    expect(
      db.select("SELECT id FROM daily_action WHERE undone=1").single['id'],
      'v17-action-0',
    );
    db.close();
    await upgrade();
  });
  test(
    'missing captured occurrence fails atomically and can retry after repair',
    () async {
      final db = raw();
      final old = db
          .select(
            "SELECT bucket,occurs_at FROM daily_action d JOIN daily_expectation e ON e.id=d.bucket WHERE d.id='v17-reskip'",
          )
          .single;
      db.execute('UPDATE daily_expectation SET occurs_at=NULL WHERE id=?', [
        old['bucket'],
      ]);
      final before = savedRows(db);
      db.close();
      await expectLater(
        upgrade(),
        throwsA(
          predicate(
            (e) => e.toString().contains('history_occurrence_migration_review'),
          ),
        ),
      );
      final failed = raw();
      expect(failed.select('PRAGMA user_version').single.values.single, 17);
      expect(savedRows(failed), before);
      expect(
        failed
            .select('PRAGMA table_info(daily_action)')
            .any((r) => r['name'] == 'occurs_at'),
        isFalse,
      );
      failed.execute('UPDATE daily_expectation SET occurs_at=? WHERE id=?', [
        old['occurs_at'],
        old['bucket'],
      ]);
      failed.close();
      await upgrade();
    },
  );
  test(
    'late index collision rolls back column backfill and guards before retry',
    () async {
      final db = raw();
      db.execute('CREATE TABLE history_skip_global_time(marker TEXT)');
      db.execute("INSERT INTO history_skip_global_time VALUES ('preserve')");
      final before = savedRows(db);
      db.close();
      await expectLater(upgrade(), throwsA(anything));
      final failed = raw();
      expect(failed.select('PRAGMA user_version').single.values.single, 17);
      expect(savedRows(failed), before);
      expect(
        failed
            .select('PRAGMA table_info(daily_action)')
            .any((r) => r['name'] == 'occurs_at'),
        isFalse,
      );
      expect(
        failed.select(
          "SELECT name FROM sqlite_master WHERE name='history_skip_person_time' OR name='history_action_occurrence_insert'",
        ),
        isEmpty,
      );
      failed.execute('DROP TABLE history_skip_global_time');
      failed.close();
      await upgrade();
    },
  );
  test('new take skip undo and reskip retain captured occurrence and enforce guards', () async {
    final upgraded = await upgrade();
    final day = CivilDate(2026, 10, 25);
    Future<DailyRow> row() async => (await upgraded.dailyRows(
      from: day,
      toExclusive: day.addDays(1),
      observedZone: 'Europe/London',
    )).rows.singleWhere((r) => r.expectation.identity.planId == 'v17-plan-0');
    final skip = await upgraded.actDaily(
      commandId: 'new-skip',
      row: await row(),
      kind: DailyActionKind.skip,
    );
    await upgraded.undoDaily(
      commandId: 'new-undo',
      row: await row(),
      action: skip,
    );
    await upgraded.actDaily(
      commandId: 'new-take',
      row: await row(),
      kind: DailyActionKind.taken,
      actualAt: DateTime.utc(2026, 10, 25, 12),
    );
    await upgraded.close();
    store = null;
    final db = raw();
    final copied = db.select(
      "SELECT d.*,e.occurs_at AS saved FROM daily_action d JOIN daily_expectation e ON e.id=d.bucket WHERE d.id IN ('new-skip','new-take')",
    );
    expect(copied, hasLength(2));
    for (final r in copied) {
      expect(r['occurs_at'], r['saved']);
    }
    final source = copied.first;
    expect(
      () => db.execute('UPDATE daily_action SET occurs_at=NULL WHERE id=?', [
        source['id'],
      ]),
      throwsA(isA<SqliteException>()),
    );
    expect(
      () => db.execute(
        'UPDATE daily_action SET occurs_at=occurs_at+1 WHERE id=?',
        [source['id']],
      ),
      throwsA(isA<SqliteException>()),
    );
    expect(
      () => db.execute(
        'UPDATE daily_expectation SET occurs_at=occurs_at+1 WHERE id=?',
        [source['bucket']],
      ),
      throwsA(isA<SqliteException>()),
    );
    expect(
      () => db.execute(
        "INSERT INTO daily_action(id,bucket,person,kind,record,revision,undone,sequence,recorded_at) VALUES ('bad',?,'me','skip',NULL,1,0,9999,0)",
        [source['bucket']],
      ),
      throwsA(isA<SqliteException>()),
    );
    expect(db.select('PRAGMA foreign_key_check'), isEmpty);
    db.close();
  });
  test('new repeated-clock choices copy the exact saved instance', () async {
    final upgraded = await upgrade();
    final day = CivilDate(2026, 10, 25);
    for (var instance = 0; instance < 2; instance++) {
      final item = await upgraded.createItem(
        commandId: 'fold-item-$instance',
        name: 'Synthetic fold source',
        form: 'tablet',
        unit: 'count',
        type: 'medicine',
      );
      await upgraded.saveDailyPlan(
        commandId: 'fold-plan-$instance',
        plan: DailyPlanVersion(
          personId: meId,
          planId: 'fold-plan-$instance',
          itemId: item.id,
          versionId: 'fold-version-$instance',
          start: day,
          timing: DailySlots([
            DailySlot(
              id: 'fold',
              time: WallTime(1, 30),
              reminderEnabled: false,
              amount: PlannedAmount(
                quantity: ExactQuantity.parse('1'),
                enteredText: '1',
                unit: 'count',
              ),
            ),
          ]),
          zoneBasis: FixedHome('Europe/London'),
        ),
        expectedPersonRevision: 1,
        expectedGeneration: upgraded.generation,
      );
      Future<DailyRow> row() async => (await upgraded.dailyRows(
        from: day,
        toExclusive: day.addDays(1),
        observedZone: 'Europe/London',
      )).rows.singleWhere((r) => r.expectation.itemId == item.id);
      await upgraded.chooseDailyClock(
        commandId: 'fold-choice-$instance',
        row: await row(),
        decision: ChooseClockInstance(instance),
      );
      final captured = await row();
      expect(
        captured.expectation.instant,
        DateTime.utc(2026, 10, 25, instance, 30),
      );
      await upgraded.actDaily(
        commandId: 'fold-skip-$instance',
        row: captured,
        kind: DailyActionKind.skip,
      );
    }
    final page = await upgraded.timeline(
      TimelineQuery(
        filter: TimelineFilter(status: TimelineStatus.skipped),
        displayZone: 'UTC',
      ),
    );
    for (var instance = 0; instance < 2; instance++) {
      final entry = page.entries.cast<SkippedTimelineEntry>().singleWhere(
        (e) => e.action.id == 'fold-skip-$instance',
      );
      expect(entry.occurredAt, DateTime.utc(2026, 10, 25, instance, 30));
      expect(entry.dateOnly, isFalse);
      expect(entry.planZone, 'Europe/London');
    }
  });
  test(
    '5000 equal-instant skips page through the real upgraded encrypted reader',
    () async {
      final db = raw();
      final source = db
          .select(
            "SELECT e.* FROM daily_expectation e JOIN daily_action d ON d.bucket=e.id WHERE d.id='v17-reskip'",
          )
          .single;
      final snapshot =
          jsonDecode(source['snapshot'] as String) as Map<String, dynamic>;
      snapshot['count'] = 5001;
      db.execute(
        'UPDATE daily_expectation SET snapshot=?,revision=5003 WHERE id=?',
        [jsonEncode(snapshot), source['id']],
      );
      db.execute('BEGIN');
      final insert = db.prepare(
        "INSERT INTO daily_action VALUES (?,?,'me','skip',NULL,1,0,?,0)",
      );
      try {
        for (var i = 0; i < 5000; i++) {
          insert.execute([
            'tie-${(4999 - i).toString().padLeft(4, '0')}',
            source['id'],
            i + 4,
          ]);
        }
        db.execute('COMMIT');
      } finally {
        insert.close();
      }
      final oracle = db
          .select(
            "SELECT d.id FROM daily_action d JOIN daily_expectation e ON e.id=d.bucket WHERE d.kind='skip' AND d.undone=0 ORDER BY e.occurs_at DESC,d.id",
          )
          .map((r) => r['id'])
          .toList();
      db.close();
      final upgraded = await upgrade();
      for (final scope in [FeedScope.person(meId), FeedScope.everyone()]) {
        var query = TimelineQuery(
          filter: TimelineFilter(scope: scope, status: TimelineStatus.skipped),
          displayZone: 'Europe/London',
          limit: 50,
        );
        final seen = <String>[];
        while (true) {
          final page = await upgraded.timeline(query);
          seen.addAll(
            page.entries.map((e) => (e as SkippedTimelineEntry).action.id),
          );
          if (!page.hasMore) break;
          query = query.withCursor(page.next!);
        }
        expect(seen, orderedEquals(oracle));
        expect(seen.toSet(), hasLength(oracle.length));
      }
    },
  );
}
