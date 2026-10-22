import 'dart:io';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:true_grit_vital/data/record_store.dart';

void main() {
  late Directory dir;
  late RecordStore store;
  late String path;
  late SubstanceItem item;
  final key = List.generate(32, (i) => i + 1);
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('vital-history-');
    path = '${dir.path}/db';
    store = await RecordStore.open(path: path, key: key, isNew: true);
    item = await store.createItem(
      commandId: 'item',
      name: 'Recorded medicine',
      form: 'tablet',
      unit: 'mg',
      type: 'medicine',
    );
  });
  tearDown(() async {
    await store.close();
    await dir.delete(recursive: true);
  });
  TimelineQuery query({
    TimelineFilter? filter,
    int limit = 25,
    TimelineCursor? cursor,
    String zone = 'Europe/London',
  }) => TimelineQuery(
    filter: filter ?? TimelineFilter(),
    displayZone: zone,
    limit: limit,
    cursor: cursor,
  );
  Future<UseRecord> record(
    String id,
    DateTime at, {
    SubstanceItem? source,
    String person = meId,
  }) => store.record(
    commandId: id,
    itemId: (source ?? item).id,
    amount: '1.000',
    actualAt: at,
    personId: person,
  );
  Future<CombinedUseResult> combined(
    String id,
    DateTime at, {
    SubstanceItem? other,
  }) => store.recordCombined(
    CombinedUseCommand(
      commandId: id,
      expectedGeneration: store.generation,
      personId: meId,
      expectedPersonRevision: 1,
      actualAt: at,
      components: [
        for (final it in [item, other ?? item])
          CombinedUseComponent(
            itemId: it.id,
            expectedItemRevision: 1,
            enteredAmount: '1.000',
          ),
      ],
    ),
  );
  Future<DailyAction> skip(CivilDate day, {DailyTiming? timing}) async {
    await store.saveDailyPlan(
      commandId: 'plan',
      plan: DailyPlanVersion(
        personId: meId,
        planId: 'plan',
        itemId: item.id,
        versionId: 'v1',
        start: day,
        timing:
            timing ??
            DailyCount(
              1,
              PlannedAmount(
                quantity: ExactQuantity.parse('1'),
                enteredText: '1',
                unit: 'mg',
              ),
            ),
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
    return store.actDaily(
      commandId: 'skip',
      row: rows.rows.single,
      kind: DailyActionKind.skip,
    );
  }

  Database raw() {
    final db = sqlite3.open(path);
    db.execute("PRAGMA cipher='chacha20'");
    db.execute(
      'PRAGMA key="x\'${key.map((v) => v.toRadixString(16).padLeft(2, '0')).join()}\'"',
    );
    db.execute('PRAGMA foreign_keys=ON');
    return db;
  }

  test(
    'keyset equal instants pages all parent kinds without duplication',
    () async {
      final at = DateTime.utc(2026, 10, 19);
      await record('single1', at);
      await record('single2', at);
      await combined('group', at);
      await skip(CivilDate(2026, 10, 19));
      final seen = <TimelineEntry>[];
      var q = query(limit: 1);
      while (true) {
        final page = await store.timeline(q);
        seen.addAll(page.entries);
        if (!page.hasMore) break;
        q = q.withCursor(page.next!);
      }
      expect(seen.length, 4);
      expect(seen.map((e) => e.id.sortKey).toSet().length, 4);
      expect(seen.whereType<CombinedTimelineEntry>().single.records.length, 2);
      expect(seen.whereType<SkippedTimelineEntry>().single.dateOnly, isTrue);
      expect(await store.recordCount(), 4);
    },
  );
  test(
    'combined component predicates are conjunctive and preserve full group',
    () async {
      final other = await store.createItem(
        commandId: 'other',
        name: 'Recorded supplement',
        form: 'liquid',
        unit: 'ml',
        type: 'supplement',
      );
      final group = await combined(
        'group',
        DateTime.utc(2026, 10, 19),
        other: other,
      );
      final page = await store.timeline(
        query(
          filter: TimelineFilter(
            itemId: item.id,
            typeIds: ['medicine'],
            actualUnit: 'mg',
          ),
        ),
      );
      final entry = page.entries.single as CombinedTimelineEntry;
      expect(entry.records.length, 2);
      expect(entry.matchedRecordIds, [group.records.first.id]);
      expect(
        (await store.timeline(
          query(
            filter: TimelineFilter(itemId: item.id, typeIds: ['supplement']),
          ),
        )).entries,
        isEmpty,
      );
    },
  );
  test(
    'scope keeps archived history inspectable only in fixed owner feed',
    () async {
      await record('mine', DateTime.utc(2026, 10, 19));
      final adult = await store.createProfile(
        commandId: 'adult',
        name: 'Another adult',
        adultConfirmed: true,
      );
      final other = await store.createItem(
        commandId: 'other',
        personId: adult.id,
        name: 'Other',
        form: 'tablet',
        unit: 'mg',
        type: 'medicine',
      );
      await record(
        'theirs',
        DateTime.utc(2026, 10, 20),
        source: other,
        person: adult.id,
      );
      await store.archiveProfile(
        commandId: 'archive',
        personId: adult.id,
        expectedRevision: 1,
      );
      expect((await store.timeline(query())).entries.single.personId, meId);
      expect(
        (await store.timeline(
          query(filter: TimelineFilter(scope: FeedScope.person(adult.id))),
        )).entries.single.personId,
        adult.id,
      );
    },
  );
  test('combined timestamp correction updates parent once, replays and rolls back atomically', () async {
    final group = await combined('group', DateTime.utc(2026, 10, 19));
    final command = CombinedCorrectionCommand(
      commandId: 'move',
      actionId: group.actionId,
      personId: meId,
      expectedPersonRevision: 1,
      expectedGeneration: store.generation,
      actualAt: DateTime.utc(2026, 10, 20),
      components: [
        for (final r in group.records)
          CombinedCorrectionComponent(
            recordId: r.id,
            expectedRevision: 1,
            physicalCorrection: null,
          ),
      ],
    );
    await expectLater(
      store.correctCombined(command, failBeforeCommit: true),
      throwsA(isA<StateError>()),
    );
    expect(
      (await store.timeline(query())).entries.single.occurredAt,
      DateTime.utc(2026, 10, 19),
    );
    await store.correctCombined(command);
    await store.correctCombined(command);
    expect(
      (await store.timeline(query())).entries.single.occurredAt,
      DateTime.utc(2026, 10, 20),
    );
    expect(await store.recordCount(), 2);
    expect((await store.history(group.records.first.id)).length, 2);
    final page = await store.calendar(
      query(),
      dates: [CivilDate(2026, 10, 19), CivilDate(2026, 10, 20)],
    );
    expect(page.cells.map((c) => c.recorded), [0, 1]);
    await store.close();
    final db = raw();
    expect(
      db.select('SELECT actual FROM combined_action').single['actual'],
      DateTime.utc(2026, 10, 20).microsecondsSinceEpoch,
    );
    db.close();
    store = await RecordStore.open(path: path, key: key, isNew: false);
  });
  test(
    'skips retain date-only plan context and undo audit without actuals',
    () async {
      final action = await skip(CivilDate(2026, 10, 25));
      final page = await store.timeline(query(zone: 'America/New_York'));
      final entry = page.entries.single as SkippedTimelineEntry;
      expect(entry.savedDate, CivilDate(2026, 10, 25));
      expect(entry.planZone, 'Europe/London');
      expect(entry.context.itemName, 'Recorded medicine');
      final calendar = await store.calendar(
        query(zone: 'America/New_York'),
        dates: [CivilDate(2026, 10, 24), CivilDate(2026, 10, 25)],
      );
      expect(calendar.cells.map((c) => c.skipped), [0, 1]);
      final rows = await store.dailyRows(
        from: CivilDate(2026, 10, 25),
        toExclusive: CivilDate(2026, 10, 26),
        observedZone: 'Europe/London',
      );
      await store.undoDaily(
        commandId: 'undo',
        row: rows.rows.single,
        action: action,
      );
      expect((await store.timeline(query())).entries, isEmpty);
      expect(
        (await store.dailyActionSource(
          action.id,
          personId: meId,
        ))!.action.isUndone,
        isTrue,
      );
      expect((await store.dailyActionAudit(action.id)).length, 1);
      expect(await store.recordCount(), 0);
    },
  );
  test(
    'DST repeated skip remains date-only; calendar exact status counts',
    () async {
      await skip(
        CivilDate(2026, 10, 25),
        timing: DailySlots([
          DailySlot(
            id: 'slot',
            reminderEnabled: false,
            time: WallTime(1, 30),
            amount: PlannedAmount(
              quantity: ExactQuantity.parse('1'),
              enteredText: '1',
              unit: 'mg',
            ),
          ),
        ]),
      );
      final entry =
          (await store.timeline(query())).entries.single
              as SkippedTimelineEntry;
      expect(entry.timeNeedsReview, isTrue);
      expect(entry.dateOnly, isTrue);
      final r = await record('actual', DateTime.utc(2026, 10, 25, 1, 45));
      await store.voidRecord(
        commandId: 'void',
        recordId: r.id,
        expectedRevision: 1,
      );
      final cell = (await store.calendar(
        query(),
        dates: [CivilDate(2026, 10, 25)],
      )).cells.single;
      expect(cell.skipped, 1);
      expect(cell.voided, 1);
      expect(cell.recorded, 0);
    },
  );
  test(
    'recorded type remains after item reclassification and correction',
    () async {
      final r = await record('actual', DateTime.utc(2026, 10, 19));
      // The historical predicate reads revision.type, independently of live item.type.
      await store.close();
      final db = raw();
      db.execute("UPDATE item SET type='supplement' WHERE id=?", [item.id]);
      db.close();
      store = await RecordStore.open(path: path, key: key, isNew: false);
      await store.correct(
        commandId: 'correct',
        recordId: r.id,
        expectedRevision: 1,
        amount: '2',
        actualAt: r.actualAt,
      );
      expect(
        (await store.timeline(
          query(filter: TimelineFilter(typeIds: ['medicine'])),
        )).entries.length,
        1,
      );
      expect(
        (await store.timeline(
          query(filter: TimelineFilter(typeIds: ['supplement'])),
        )).entries,
        isEmpty,
      );
      expect((await store.historyTypeOptions()).options.map((e) => e.id), [
        'medicine',
      ]);
    },
  );
  test('overlapping event memberships deduplicate actuals and explicitly match planned skips', () async {
    await record('actual', DateTime.utc(2026, 10, 25, 23, 30));
    await skip(CivilDate(2026, 10, 25));
    for (final id in ['event1', 'event2']) {
      final e = EventRecord(
        id: id,
        personId: meId,
        name: id,
        eventType: 'course',
        zoneId: 'Europe/London',
        revision: 1,
        plannedEnd: EventDate.day(CivilDate(2026, 10, 25)),
        memberships: [
          EventMembership(
            id: '$id-member',
            itemId: item.id,
            personId: meId,
            effectiveFrom: DateTime.utc(2026, 10, 1),
            revision: 1,
          ),
        ],
      );
      final command = SaveEventCommand(
        commandId: id,
        generation: store.generation,
        expectedRevision: null,
        event: e,
      );
      await store.saveEvent(
        command,
        membershipReview: await store.previewEventMembership(command),
      );
    }
    final page = await store.timeline(
      query(filter: TimelineFilter(eventIds: ['event1', 'event2'])),
    );
    expect(page.entries.length, 2);
    expect(page.entries.whereType<SkippedTimelineEntry>().length, 1);
    expect((await store.historyEventOptions(limit: 1)).hasMore, isTrue);
  });
  test('cursor rejects other query and stale dataset; page watch refreshes correction', () async {
    final r = await record('first', DateTime.utc(2026, 10, 19));
    await record('second', DateTime.utc(2026, 10, 18));
    final first = await store.timeline(query(limit: 1));
    expect(
      () => query(
        filter: TimelineFilter(itemId: item.id),
        cursor: first.next,
      ),
      throwsA(isA<TimelineCursorException>()),
    );
    final bad = TimelineCursor.at(
      occurredAt: r.actualAt,
      sortKey: 'r:${r.id}',
      query: query(),
      schemaVersion: 19,
      datasetGeneration: 'other',
    );
    await expectLater(
      store.timeline(query(cursor: bad)),
      throwsA(isA<TimelineCursorException>()),
    );
    final stream = store.watchTimeline(query()).take(2).toList();
    await Future<void>.delayed(const Duration(milliseconds: 30));
    await store.correct(
      commandId: 'correct',
      recordId: r.id,
      expectedRevision: 1,
      amount: null,
      actualAt: DateTime.utc(2026, 10, 17),
    );
    final pages = await stream;
    expect(pages.last.entries.last.occurredAt, DateTime.utc(2026, 10, 17));
  });
  test('populated16 migration repairs stale parent while preserving protected bytes and audits', () async {
    await store.close();
    File(path).deleteSync();
    final db = raw();
    db.execute(
      File('test/data/fixtures/record_store_v16.sql').readAsStringSync(),
    );
    final queries = {
      for (final t in [
        'attachment_record',
        'attachment_chunk',
        'attachment_pin',
        'attachment_job',
        'event_audit',
        'combined_audit',
        'revision',
        'operation',
      ])
        t: t == 'revision'
            ? 'SELECT record,person,revision,name,form,unit,type,amount,entered,actual,entered_at,voided FROM revision'
            : 'SELECT * FROM $t',
    };
    final before = {
      for (final e in queries.entries)
        e.key: jsonEncode(
          db
              .select(e.value)
              .map(
                (r) => r.values
                    .map((v) => v is List<int> ? base64Encode(v) : v)
                    .toList(),
              )
              .toList(),
        ),
    };
    expect(
      db.select('SELECT actual FROM combined_action').single['actual'],
      isNot(
        db.select('SELECT actual FROM administration LIMIT 1').single['actual'],
      ),
    );
    db.close();
    store = await RecordStore.open(path: path, key: key, isNew: false);
    expect(
      (await store.timeline(query())).entries.single.occurredAt,
      DateTime.utc(2026, 10, 16, 13),
    );
    await store.close();
    final upgraded = raw();
    expect(upgraded.select('PRAGMA user_version').single.values.single, currentRecordSchemaVersion);
    for (final t in before.keys) {
      expect(
        jsonEncode(
          upgraded
              .select(queries[t]!)
              .map(
                (r) => r.values
                    .map((v) => v is List<int> ? base64Encode(v) : v)
                    .toList(),
              )
              .toList(),
        ),
        before[t],
        reason: t,
      );
    }
    expect(upgraded.select('PRAGMA foreign_key_check'), isEmpty);
    upgraded.close();
    store = await RecordStore.open(path: path, key: key, isNew: false);
  });
  test('inconsistent16 group migration rolls back schema and leaves immutable evidence', () async {
    await store.close();
    File(path).deleteSync();
    final db = raw();
    db.execute(
      File('test/data/fixtures/record_store_v16.sql').readAsStringSync(),
    );
    db.execute(
      'UPDATE administration SET actual=actual+1 WHERE id=(SELECT record FROM combined_member ORDER BY position LIMIT 1)',
    );
    db.close();
    await expectLater(
      RecordStore.open(path: path, key: key, isNew: false),
      throwsA(
        predicate((e) => e.toString().contains('combined_migration_review')),
      ),
    );
    final failed = raw();
    expect(failed.select('PRAGMA user_version').single.values.single, 16);
    expect(
      failed.select(
        "SELECT name FROM sqlite_master WHERE name='event_history_bounds'",
      ),
      isEmpty,
    );
    failed.close();
    store = await RecordStore.open(
      path: '${dir.path}/replacement',
      key: key,
      isNew: true,
    );
  });
  test('legacy16 skip snapshots backfill in saved zone with explicit unknown classification', () async {
    await skip(CivilDate(2026, 10, 25));
    await store.close();
    final source = raw();
    final tables = [
      'item',
      'daily_plan',
      'daily_version',
      'daily_version_audit',
    ];
    final copied = {
      for (final t in tables)
        t: source
            .select('SELECT * FROM $t')
            .map((r) => Map<String, Object?>.from(r))
            .toList(),
    };
    final expectation = source
        .select(
          'SELECT id,plan,person,date,snapshot,revision FROM daily_expectation',
        )
        .single
        .values
        .toList();
    final action = source
        .select(
          'SELECT id,bucket,person,kind,record,revision,undone,sequence,recorded_at FROM daily_action',
        )
        .single
        .values
        .toList();
    source.close();
    File(path).deleteSync();
    final db = raw();
    db.execute(
      File('test/data/fixtures/record_store_v16.sql').readAsStringSync(),
    );
    for (final t in tables) {
      for (final row in copied[t]!) {
        if (t == 'item') {
          // The populated fixture already owns this named type under a
          // different ID from the freshly created source dataset.
          row['type_id'] = db.select(
            'SELECT id FROM personal_item_type WHERE person=? AND name=?',
            [row['person'], row['type']],
          ).single['id'];
        }
        db.execute(
          'INSERT INTO $t (${row.keys.join(',')}) '
          'VALUES (${List.filled(row.length, '?').join(',')})',
          row.values.toList(),
        );
      }
    }
    db.execute(
      'INSERT INTO daily_expectation VALUES (?,?,?,?,?,?)',
      expectation,
    );
    db.execute(
      'INSERT INTO daily_action VALUES (${List.filled(action.length, '?').join(',')})',
      action,
    );
    db.close();
    store = await RecordStore.open(path: path, key: key, isNew: false);
    final entry =
        (await store.timeline(
              query(filter: TimelineFilter(status: TimelineStatus.skipped)),
            )).entries.single
            as SkippedTimelineEntry;
    expect(entry.savedDate, CivilDate(2026, 10, 25));
    expect(entry.planZone, 'Europe/London');
    final sourceAction = await store.dailyActionSource(
      entry.action.id,
      personId: meId,
    );
    expect(sourceAction!.recordedType, 'legacy_unknown');
    expect(sourceAction.context.itemName, isNull);
    expect(
      (await store.timeline(
        query(
          filter: TimelineFilter(
            typeIds: ['medicine'],
            status: TimelineStatus.skipped,
          ),
        ),
      )).entries,
      isEmpty,
    );
    expect(
      (await store.timeline(
        query(
          filter: TimelineFilter(
            typeIds: ['legacy_unknown'],
            status: TimelineStatus.skipped,
          ),
        ),
      )).entries.length,
      1,
    );
  });
  test(
    'early middle and late schema collisions rollback every17 change',
    () async {
      await store.close();
      final fixture = File('test/data/fixtures/record_store_v16.sql')
          .readAsStringSync();
      for (final collision in [
        'CREATE INDEX history_recorded_type ON item(type)',
        'CREATE INDEX history_combined_time ON item(name)',
        'CREATE TABLE event_history_bounds(id TEXT)',
      ]) {
        if (File(path).existsSync()) File(path).deleteSync();
        final db = raw();
        db.execute(fixture);
        db.execute(collision);
        final old = db
            .select('SELECT actual FROM combined_action')
            .single['actual'];
        db.close();
        await expectLater(
          RecordStore.open(path: path, key: key, isNew: false),
          throwsA(anything),
        );
        final failed = raw();
        expect(failed.select('PRAGMA user_version').single.values.single, 16);
        expect(failed.select('PRAGMA table_info(daily_expectation)').length, 6);
        expect(
          failed.select('SELECT actual FROM combined_action').single['actual'],
          old,
        );
        failed.close();
      }
      store = await RecordStore.open(
        path: '${dir.path}/replacement',
        key: key,
        isNew: true,
      );
    },
  );
  test('bounded revision inspection retains old site and quantities', () async {
    final r = await record('actual', DateTime.utc(2026, 10, 19));
    await store.correct(
      commandId: 'correct',
      recordId: r.id,
      expectedRevision: 1,
      amount: '2.000',
      actualAt: DateTime.utc(2026, 10, 20),
    );
    final page = await store.recordRevisionPage(
      recordId: r.id,
      personId: meId,
      limit: 1,
    );
    expect(page.single.revision, 2);
    expect(page.single.enteredAmount, '2.000');
    final older = await store.recordRevisionPage(
      recordId: r.id,
      personId: meId,
      beforeRevision: page.single.revision,
      limit: 1,
    );
    expect(older.single.revision, 1);
    expect(older.single.enteredAmount, '1.000');
    expect(
      await store.recordRevisionPage(recordId: r.id, personId: 'another'),
      isEmpty,
    );
  });
  test('calendar and option query bounds are explicit', () async {
    await expectLater(
      store.calendar(
        query(),
        dates: List.generate(43, (i) => CivilDate(2026, 1, 1).addDays(i)),
      ),
      throwsA(isA<TimelineQueryException>()),
    );
    await expectLater(
      store.historyTypeOptions(limit: 51),
      throwsA(isA<TimelineQueryException>()),
    );
  });
}
