import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:true_grit_vital/data/record_store.dart';

void main() {
  late Directory directory;
  late RecordStore store;
  late SubstanceItem item;
  final key = List.generate(32, (i) => i + 11);
  final date = CivilDate(2026, 10, 20);

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('vital-event-summary-');
    store = await RecordStore.open(
      path: '${directory.path}/db',
      key: key,
      isNew: true,
    );
    item = await store.createItem(
      commandId: 'item',
      name: 'Synthetic event item',
      form: 'tablet',
      unit: 'mg',
      type: 'medicine',
    );
  });
  tearDown(() async {
    await store.close();
    await directory.delete(recursive: true);
  });

  EventRecord event({
    String notes = '',
    int revision = 1,
    String zone = 'UTC',
    List<EventMembership>? members,
  }) => EventRecord(
    id: 'event',
    personId: meId,
    name: 'Synthetic event',
    eventType: 'cycle',
    zoneId: zone,
    revision: revision,
    plannedStart: EventDate.day(date),
    plannedEnd: EventDate.day(date),
    notes: notes,
    memberships:
        members ??
        [
          EventMembership(
            id: 'member',
            itemId: item.id,
            personId: meId,
            effectiveFrom: DateTime.utc(2026, 10, 1),
            revision: 1,
          ),
        ],
  );
  Future<EventRecord> save(
    EventRecord value,
    String command, {
    int? expected,
  }) async {
    final input = SaveEventCommand(
      commandId: command,
      generation: store.generation,
      expectedRevision: expected,
      event: value,
    );
    return store.saveEvent(
      input,
      membershipReview: await store.previewEventMembership(input),
    );
  }

  Future<UseRecord> record(String id, DateTime at) =>
      store.record(commandId: id, itemId: item.id, amount: '1', actualAt: at);

  test(
    'whole-event counts span pages, revisions and current void state',
    () async {
      await save(event(), 'save');
      for (var i = 0; i < 111; i++) {
        await record('record-$i', DateTime.utc(2026, 10, 20, 8, i));
      }
      expect(await store.eventActuals(['event'], limit: 51), hasLength(51));
      expect((await store.eventUseSummary('event'))!.recorded, 111);
      final saved = (await store.records(limit: 1)).single;
      final corrected = await store.correct(
        commandId: 'correct',
        recordId: saved.id,
        expectedRevision: saved.revision,
        amount: '2',
        actualAt: saved.actualAt,
      );
      expect((await store.eventUseSummary('event'))!.recorded, 111);
      await store.voidRecord(
        commandId: 'void',
        recordId: corrected.id,
        expectedRevision: corrected.revision,
      );
      expect((await store.eventUseSummary('event'))!.recorded, 110);
    },
  );

  test(
    'event and membership intervals use inclusive dates and exclusive instants',
    () async {
      final members = [
        EventMembership(
          id: 'm1',
          itemId: item.id,
          personId: meId,
          effectiveFrom: DateTime.utc(2026, 10, 20, 8),
          effectiveUntil: DateTime.utc(2026, 10, 20, 10),
          revision: 1,
        ),
        EventMembership(
          id: 'm2',
          itemId: item.id,
          personId: meId,
          effectiveFrom: DateTime.utc(2026, 10, 20, 10),
          revision: 1,
        ),
      ];
      await save(event(members: members), 'save');
      for (final (id, at) in [
        ('before', DateTime.utc(2026, 10, 20, 7, 59)),
        ('start', DateTime.utc(2026, 10, 20, 8)),
        ('join', DateTime.utc(2026, 10, 20, 10)),
        ('last', DateTime.utc(2026, 10, 20, 23, 59)),
        ('end', DateTime.utc(2026, 10, 21)),
      ]) {
        await record(id, at);
      }
      final summary = (await store.eventUseSummary('event'))!;
      expect(summary.recorded, 3);
      expect(summary.substances, 1);
      expect(
        (await store.eventActuals(['event'])),
        hasLength(summary.recorded!),
      );
    },
  );

  test('skip actions and undo never become doses or stock movements', () async {
    await save(event(), 'save');
    await store.saveDailyPlan(
      commandId: 'plan',
      expectedGeneration: store.generation,
      expectedPersonRevision: 1,
      plan: DailyPlanVersion(
        personId: meId,
        planId: 'plan',
        itemId: item.id,
        versionId: 'v1',
        start: date,
        timing: DailyCount(
          2,
          PlannedAmount(quantity: ExactQuantity.parse('1'), unit: 'mg'),
        ),
        zoneBasis: const FollowingLocal(),
        calendar: const EveryDay(),
      ),
    );
    Future<DailyRow> row() async => (await store.dailyRows(
      from: date,
      toExclusive: date.addDays(1),
      observedZone: 'UTC',
    )).rows.single;
    final skip = await store.actDaily(
      commandId: 'skip',
      row: await row(),
      kind: DailyActionKind.skip,
      skipReason: 'Authored reason',
    );
    expect((await store.eventUseSummary('event'))!.skipped, 1);
    expect((await store.eventUseSummary('event'))!.recorded, 0);
    await store.undoDaily(commandId: 'undo', row: await row(), action: skip);
    expect((await store.eventUseSummary('event'))!.skipped, 0);
    expect(await store.records(), isEmpty);
    expect(await store.stockContainers(personId: meId), isEmpty);
  });

  test(
    'event day boundaries retain the full daylight-saving transition day',
    () async {
      final dstDate = CivilDate(2026, 10, 25);
      await save(
        event(zone: 'Europe/London').copyWith(
          plannedStart: EventDate.day(dstDate),
          plannedEnd: EventDate.day(dstDate),
        ),
        'save',
      );
      await record('before-dst-day', DateTime.utc(2026, 10, 24, 22, 59));
      await record('start-dst-day', DateTime.utc(2026, 10, 24, 23));
      await record('last-dst-day', DateTime.utc(2026, 10, 25, 23, 59));
      await record('after-dst-day', DateTime.utc(2026, 10, 26));
      expect((await store.eventUseSummary('event'))!.recorded, 2);
      expect(await store.eventActuals(['event']), hasLength(2));
    },
  );

  test('unresolved stored event dates stay unknown and lock blocks reads', () async {
    await save(event(), 'save');
    final path = store.databasePath;
    await store.close();
    final db = sqlite3.open(path);
    db.execute("PRAGMA cipher='chacha20'");
    db.execute(
      'PRAGMA key="x\'${key.map((v) => v.toRadixString(16).padLeft(2, '0')).join()}\'"',
    );
    db.execute('UPDATE event_record SET snapshot=? WHERE id=?', [
      jsonEncode(event(zone: 'Unknown/Zone').toJson()),
      'event',
    ]);
    db.execute('UPDATE event_history_bounds SET resolved=0 WHERE event=?', [
      'event',
    ]);
    db.close();
    store = await RecordStore.open(path: path, key: key, isNew: false);
    final summary = (await store.eventUseSummary('event'))!;
    expect(summary.boundsNeedReview, isTrue);
    expect(summary.recorded, isNull);
    expect(summary.skipped, isNull);
    store.suspendWrites(true);
    await expectLater(
      store.eventUseSummary('event'),
      throwsA(
        isA<CommandConflict>().having((e) => e.code, 'code', 'app_locked'),
      ),
    );
  });

  test(
    'notes retain exact text, old defaults, audit and explicit clearing',
    () async {
      final old = event().toJson();
      expect(
        old.containsKey('notes'),
        isFalse,
        reason: 'legacy command payload shape remains stable',
      );
      expect(EventRecord.fromJson(old).notes, isEmpty);
      const text = 'Private original wording: 0.125 mg.\nSecond line.';
      await save(event(notes: text), 'save');
      await store.saveEvent(
        SaveEventCommand(
          commandId: 'save',
          generation: store.generation,
          expectedRevision: null,
          event: event(notes: text),
        ),
      );
      expect((await store.eventHistory('event')), hasLength(1));
      await save(event(revision: 2), 'clear', expected: 1);
      expect((await store.eventHistory('event')).map((e) => e.notes), [
        text,
        '',
      ]);
      await expectLater(
        save(event(notes: 'Stale', revision: 2), 'stale', expected: 1),
        throwsA(isA<CommandConflict>()),
      );
      await store.close();
      store = await RecordStore.open(
        path: '${directory.path}/db',
        key: key,
        isNew: false,
      );
      expect((await store.eventById('event'))!.notes, isEmpty);
      expect((await store.eventHistory('event')).first.notes, text);
    },
  );

  test('event report notes require deliberate inclusion', () async {
    const secret = 'Private event note';
    await save(event(notes: secret), 'save');
    for (final include in [false, true]) {
      final capture = await store.captureTemplateReport(
        selection: ReportSelection(
          template: ReportTemplateId.r03EventReview,
          personId: meId,
          eventId: 'event',
          fromDate: date,
          beforeDate: date.addDays(1),
          displayZone: 'UTC',
          includeNotes: include,
        ),
        now: () => DateTime.utc(2026, 10, 22),
      );
      final data = capture.snapshot.templateData! as ReportEventData;
      expect(data.notes, include ? secret : '');
      expect(
        data.structuredText(capture.snapshot, use24Hour: true).contains(secret),
        include,
      );
    }
  });
}
