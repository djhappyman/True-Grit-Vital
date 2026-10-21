import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:true_grit_vital/domain/scheduling/iana_clock.dart';
import 'package:true_grit_vital/data/record_store.dart';

void main() {
  late Directory dir;
  late RecordStore store;
  late SubstanceItem item;
  late String path;
  final key = List.generate(32, (i) => i + 1);
  final now = DateTime.utc(2026, 10, 19, 12);
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('vital-events-');
    path = '${dir.path}/events.db';
    store = await RecordStore.open(path: path, key: key, isNew: true);
    item = await store.createItem(
      commandId: 'item',
      name: 'Synthetic event item',
      form: 'tablet',
      unit: 'count',
      type: 'medicine',
    );
  });
  tearDown(() async {
    await store.close();
    await dir.delete(recursive: true);
  });
  EventMembership membership({
    DateTime? from,
    DateTime? until,
    int revision = 1,
  }) => EventMembership(
    id: 'membership',
    itemId: item.id,
    personId: meId,
    effectiveFrom: from ?? DateTime.utc(2026, 10, 10),
    effectiveUntil: until,
    revision: revision,
  );
  EventRecord event({
    String id = 'event',
    int revision = 1,
    List<EventMembership>? members,
    EventDate? end,
  }) => EventRecord(
    id: id,
    personId: meId,
    name: 'Synthetic course',
    eventType: 'course',
    zoneId: 'Europe/London',
    revision: revision,
    plannedStart: EventDate.day(CivilDate(2026, 10, 1)),
    plannedEnd: end ?? EventDate.day(CivilDate(2026, 10, 25)),
    memberships: members ?? [membership()],
  );
  SaveEventCommand command(
    EventRecord e, {
    String id = 'event-save',
    int? expected,
  }) => SaveEventCommand(
    commandId: id,
    generation: store.generation,
    expectedRevision: expected,
    event: e,
  );
  Future<UseRecord> actual(String id, int day) => store.record(
    commandId: id,
    itemId: item.id,
    amount: '1',
    actualAt: DateTime.utc(2026, 10, day, 12),
  );
  Future<EventRecord> save(
    EventRecord e, {
    String id = 'event-save',
    int? expected,
  }) async {
    final c = command(e, id: id, expected: expected);
    final review = await store.previewEventMembership(c);
    return store.saveEvent(c, membershipReview: review);
  }

  test('membership removal closes interval and retains old actuals, audit and snapshots', () async {
    final before = await actual('before', 9),
        included = await actual('included', 15),
        later = await actual('later', 22);
    await save(event());
    expect((await store.eventActuals(['event'])).map((r) => r.id), [
      later.id,
      included.id,
    ]);
    await save(
      event(
        revision: 2,
        members: [membership(until: DateTime.utc(2026, 10, 20), revision: 2)],
      ),
      id: 'remove',
      expected: 1,
    );
    expect((await store.eventActuals(['event'])).map((r) => r.id), [
      included.id,
    ]);
    expect((await store.eventHistory('event')).length, 2);
    expect((await store.records()).length, 3);
    expect((await store.history(before.id)).length, 1);
    await expectLater(
      store.saveEvent(
        command(event(revision: 3, members: []), id: 'erase', expected: 2),
      ),
      throwsA(isA<CommandConflict>()),
    );
  });
  test('backdated inclusion requires explicit preview and corrected actual invalidates it', () async {
    final record = await actual('actual', 9);
    await save(event());
    final c = command(
      event(
        revision: 2,
        members: [membership(from: DateTime.utc(2026, 10, 8), revision: 2)],
      ),
      id: 'backdate',
      expected: 1,
    );
    final review = await store.previewEventMembership(c);
    expect(review.entering.single.id, record.id);
    await expectLater(store.saveEvent(c), throwsA(isA<CommandConflict>()));
    await store.correct(
      commandId: 'correct',
      recordId: record.id,
      expectedRevision: 1,
      amount: '1',
      actualAt: DateTime.utc(2026, 10, 11),
    );
    await expectLater(
      store.saveEvent(c, membershipReview: review),
      throwsA(isA<CommandConflict>()),
    );
    expect((await store.eventActuals(['event'])).single.id, record.id);
    expect((await store.records()).length, 1);
    expect((await store.history(record.id)).length, 2);
  });
  test('overlap selection deduplicates administration identity and retains type snapshot', () async {
    final record = await actual('actual', 15);
    await save(event());
    await save(event(id: 'other'), id: 'other-save');
    expect(
      (await store.eventActuals(['event', 'other', 'event'])).single.id,
      record.id,
    );
    await store.renameItemType(
      commandId: 'rename-type',
      typeId: item.typeId!,
      expectedRevision: 1,
      name: 'Renamed current type',
    );
    expect((await store.itemById(item.id))!.type, 'Renamed current type');
    expect(
      (await store.eventActuals(['event', 'other'])).single.type,
      'medicine',
    );
    expect((await store.records()).length, 1);
  });
  test('saved inclusive London DST final day includes its 25th hour', () async {
    final r = await store.record(
      commandId: 'last-hour',
      itemId: item.id,
      amount: '1',
      actualAt: DateTime.utc(2026, 10, 25, 23, 30),
    );
    await store.record(
      commandId: 'next-midnight',
      itemId: item.id,
      amount: '1',
      actualAt: DateTime.utc(2026, 10, 26),
    );
    await save(event());
    expect((await store.eventActuals(['event'])).single.id, r.id);
    expect(
      (await store.eventById('event'))!.endReviewAt(IanaClock()),
      DateTime.utc(2026, 10, 26),
    );
  });
  test(
    'use period unknown precision and first-ever remain separate and encrypted',
    () async {
      final p = RecordedUsePeriod(
        id: 'period',
        personId: meId,
        itemId: item.id,
        revision: 1,
        start: EventDate.unknown(),
        firstEver: true,
      );
      final c = SaveUsePeriodCommand(
        commandId: 'period-save',
        generation: store.generation,
        expectedRevision: null,
        period: p,
      );
      await store.saveUsePeriod(c);
      await store.saveUsePeriod(c);
      expect(
        (await store.usePeriods(
          personId: meId,
          itemId: item.id,
        )).single.start.precision,
        EventDatePrecision.unknown,
      );
      expect(await store.records(), isEmpty);
      expect(await store.dailyPlans(), isEmpty);
      await store.close();
      expect(
        String.fromCharCodes(await File(path).readAsBytes())
            .contains('Synthetic event item'),
        isFalse,
      );
      store = await RecordStore.open(path: path, key: key, isNew: false);
      expect((await store.usePeriodHistory('period')).length, 1);
    },
  );
  test(
    'event and use-period commands rollback and replay atomically',
    () async {
      final c = command(event());
      await expectLater(
        store.saveEvent(c, failBeforeCommit: true),
        throwsStateError,
      );
      expect(await store.events(), isEmpty);
      await store.saveEvent(c);
      await store.saveEvent(c);
      expect((await store.eventHistory('event')).length, 1);
      await expectLater(
        store.saveEvent(
          command(event().copyWith(name: 'Changed'), id: 'event-save'),
        ),
        throwsA(isA<CommandConflict>()),
      );
    },
  );
  test('event end uses reserved8, prepared acknowledgement, dismissal invalidates pending without doses', () async {
    for (var i = 0; i < 10; i++) {
      await save(
        event(
          id: 'event-$i',
          end: EventDate.exact(now.add(Duration(minutes: i + 1))),
        ),
        id: 'save-$i',
      );
    }
    var projection = await store.prepareReminders(
      now: now,
      observedZone: 'Europe/London',
      clockSample: null,
      adapterFingerprint: 'test',
    );
    expect(projection.desired, isEmpty);
    expect(projection.eventEnds.length, 8);
    expect(projection.complete, isFalse);
    expect(
      projection.exclusions.where((e) => e.reason == 'capacity').length,
      2,
    );
    final r = projection.eventEnds.first;
    expect(
      await store.acknowledgeReminder(
        generation: store.generation,
        requestToken: r.requestToken,
        intentRevision: r.eventRevision,
        sequence: projection.sequence,
        receipt: ReminderReceipt.accepted,
        adapterFingerprint: 'test',
      ),
      isTrue,
    );
    expect(
      await store.captureEventEndAction(
        envelopeId: 'dose-attempt',
        namespace: r.namespace,
        requestToken: r.requestToken,
        actionToken: r.takenToken,
        action: ReminderActionKind.taken,
      ),
      isFalse,
    );
    expect(
      await store.captureEventEndAction(
        envelopeId: 'open',
        namespace: r.namespace,
        requestToken: r.requestToken,
        actionToken: r.requestToken,
        action: ReminderActionKind.open,
      ),
      isTrue,
    );
    expect((await store.pendingEventEndReviews()).single.eventId, r.eventId);
    final review = await store.eventEndReview(r.eventId);
    await store.dismissEventEndReview(commandId: 'dismiss', review: review);
    expect(await store.pendingEventEndReviews(), isEmpty);
    expect(
      await store.captureEventEndAction(
        envelopeId: 'stale',
        namespace: r.namespace,
        requestToken: r.requestToken,
        actionToken: r.requestToken,
        action: ReminderActionKind.open,
      ),
      isFalse,
    );
    projection = await store.prepareReminders(
      now: now,
      observedZone: 'Europe/London',
      clockSample: null,
      adapterFingerprint: 'test',
    );
    expect(projection.obsoleteTokens, contains(r.requestToken));
    expect(await store.records(), isEmpty);
    expect(await store.dailyPlans(), isEmpty);
  });
  test('profile deletion removes event ownership graph and invalidates operation replay', () async {
    await save(event());
    await store.deleteProfile(
      commandId: 'delete',
      personId: meId,
      expectedRevision: 1,
    );
    expect(await store.events(), isEmpty);
    await expectLater(
      store.saveEvent(command(event())),
      throwsA(isA<CommandConflict>()),
    );
  });
  test('populated v14 migration retains combined identity, audit, site and replay', () async {
    final migratedPath = '${dir.path}/v14.db';
    var raw = sqlite3.open(migratedPath);
    raw.execute("PRAGMA cipher='chacha20'");
    final keySql =
        'PRAGMA key="x\'${key.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}\'"';
    raw.execute(keySql);
    raw.execute(
      File('test/data/fixtures/record_store_v14.sql').readAsStringSync(),
    );
    final before = raw
        .select('SELECT * FROM combined_member')
        .map((r) => Map<String, Object?>.from(r))
        .toList();
    final audit = raw
        .select('SELECT * FROM combined_audit')
        .map((r) => Map<String, Object?>.from(r))
        .toList();
    final operations = raw
        .select('SELECT * FROM operation ORDER BY id')
        .map((r) => Map<String, Object?>.from(r))
        .toList();
    raw.close();
    final migrated = await RecordStore.open(
      path: migratedPath,
      key: key,
      isNew: false,
    );
    expect((await migrated.records()).length, 2);
    expect(
      (await migrated.siteHistory(personId: meId)).single,
      'V14 synthetic site',
    );
    expect(await migrated.readSetting('v14-capture'), 'preserve');
    expect(await migrated.events(), isEmpty);
    await migrated.close();
    raw = sqlite3.open(migratedPath);
    raw.execute("PRAGMA cipher='chacha20'");
    raw.execute(keySql);
    expect(raw.select('PRAGMA user_version').single.values.single, 23);
    expect(
      raw
          .select('SELECT * FROM combined_member')
          .map((r) => Map<String, Object?>.from(r))
          .toList(),
      before,
    );
    expect(
      raw
          .select('SELECT * FROM combined_audit')
          .map((r) => Map<String, Object?>.from(r))
          .toList(),
      audit,
    );
    expect(
      raw
          .select('SELECT * FROM operation ORDER BY id')
          .map((r) => Map<String, Object?>.from(r))
          .toList(),
      operations,
    );
    expect(raw.select('PRAGMA foreign_key_check'), isEmpty);
    raw.close();
  });
  test('early and late migration failures retain recoverable populated v14', () async {
    for (final collision in [
      'event_record',
      'event_pending',
      'ordinary_draft_v14',
    ]) {
      final p = '${dir.path}/collision-$collision.db';
      var raw = sqlite3.open(p);
      raw.execute("PRAGMA cipher='chacha20'");
      final keySql =
          'PRAGMA key="x\'${key.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}\'"';
      raw.execute(keySql);
      raw.execute(
        File('test/data/fixtures/record_store_v14.sql').readAsStringSync(),
      );
      raw.execute('CREATE TABLE $collision(recovery TEXT)');
      raw.close();
      await expectLater(
        RecordStore.open(path: p, key: key, isNew: false),
        throwsA(anything),
      );
      raw = sqlite3.open(p);
      raw.execute("PRAGMA cipher='chacha20'");
      raw.execute(keySql);
      expect(raw.select('PRAGMA user_version').single.values.single, 14);
      expect(raw.select('SELECT * FROM administration').length, 2);
      expect(raw.select('SELECT * FROM combined_audit').length, 1);
      expect(
        raw.select("SELECT name FROM sqlite_master WHERE name='use_period'"),
        isEmpty,
      );
      expect(raw.select('PRAGMA foreign_key_check'), isEmpty);
      raw.close();
    }
  });
  test('end review persists partial decisions and explicit stop uses existing phase command', () async {
    final p = DailyPlanVersion(
      personId: meId,
      planId: 'plan',
      itemId: item.id,
      versionId: 'version',
      start: CivilDate(2026, 10, 19),
      zoneBasis: FixedHome('Europe/London'),
      timing: DailySlots([
        DailySlot(
          id: 'slot',
          time: WallTime(16, 0),
          amount: PlannedAmount(
            quantity: ExactQuantity.parse('1'),
            enteredText: '1',
            unit: 'count',
          ),
          reminderEnabled: true,
        ),
      ]),
    );
    final saved = await store.saveDailyPlan(
      commandId: 'plan-save',
      plan: p,
      expectedPersonRevision: 1,
      expectedGeneration: store.generation,
    );
    await save(event());
    final review = await store.eventEndReview('event');
    await store.applyEventItemDecision(
      commandId: 'continue',
      review: review,
      itemId: item.id,
      continuePlan: true,
    );
    expect((await store.dailyPlans()).single.revision, saved.revision);
    expect(
      (await store.eventEndReview('event')).items.single.decision,
      'continuePlan',
    );
    final continuedReview = await store.eventEndReview('event');
    final stop = await store.previewPhasePlan(
      plan: saved,
      proposed: PhasePlan(
        phases: [p],
        end: PlanEnd(zoneId: 'Europe/London', exclusiveInstant: now),
      ),
      now: now,
      observedZone: 'Europe/London',
    );
    await expectLater(
      store.applyEventItemDecision(
        commandId: 'stop-fail',
        review: continuedReview,
        itemId: item.id,
        continuePlan: false,
        stopReview: stop,
        failBeforeCommit: true,
      ),
      throwsA(anything),
    );
    expect((await store.dailyPlans()).single.revision, 1);
    await store.applyEventItemDecision(
      commandId: 'stop',
      review: continuedReview,
      itemId: item.id,
      continuePlan: false,
      stopReview: stop,
    );
    expect((await store.dailyPlans()).single.revision, 2);
    expect(
      (await store.eventEndReview('event')).items.single.decision,
      'stopPlan',
    );
    await store.applyEventItemDecision(
      commandId: 'stop',
      review: continuedReview,
      itemId: item.id,
      continuePlan: false,
      stopReview: stop,
    );
    expect((await store.dailyPlans()).single.revision, 2);
    expect(
      (await store.nextDailyPlans(
        now: now,
        observedZone: 'Europe/London',
      )).rows.single.result.next,
      isNull,
    );
    expect(await store.records(), isEmpty);
  });
  test(
    'cross-adult event membership and stale owner/generation are rejected',
    () async {
      final other = await store.createProfile(
        commandId: 'adult',
        name: 'Other adult',
        adultConfirmed: true,
      );
      final otherItem = await store.createItem(
        commandId: 'other-item',
        personId: other.id,
        expectedPersonRevision: other.revision,
        name: 'Other item',
        form: 'tablet',
        unit: 'count',
        type: 'medicine',
      );
      final wrong = event(
        members: [
          EventMembership(
            id: 'foreign',
            itemId: otherItem.id,
            personId: meId,
            effectiveFrom: now,
            revision: 1,
          ),
        ],
      );
      await expectLater(
        store.saveEvent(command(wrong)),
        throwsA(isA<CommandConflict>()),
      );
      await expectLater(
        store.saveEvent(
          SaveEventCommand(
            commandId: 'old-owner',
            generation: store.generation,
            expectedRevision: null,
            expectedPersonRevision: 2,
            event: event(),
          ),
        ),
        throwsA(isA<CommandConflict>()),
      );
      await save(event());
      await expectLater(
        store.saveEvent(
          SaveEventCommand(
            commandId: 'event-save',
            generation: 'old-generation',
            expectedRevision: null,
            event: event(),
          ),
        ),
        throwsA(isA<CommandConflict>()),
      );
    },
  );

  test('independent connections accept one event revision and reject competing stale edit', () async {
    await save(event());
    final second = await RecordStore.open(path: path, key: key, isNew: false);
    Future<Object> settled(Future<EventRecord> future) async {
      try {
        return await future;
      } catch (e) {
        return e;
      }
    }

    try {
      final results = await Future.wait([
        settled(
          store.saveEvent(
            command(
              event(revision: 2).copyWith(name: 'First edit'),
              id: 'first-edit',
              expected: 1,
            ),
          ),
        ),
        settled(
          second.saveEvent(
            command(
              event(revision: 2).copyWith(name: 'Second edit'),
              id: 'second-edit',
              expected: 1,
            ),
          ),
        ),
      ]);
      expect(results.whereType<EventRecord>().length, 1);
      expect(results.whereType<CommandConflict>().length, 1);
      expect((await store.eventHistory('event')).length, 2);
    } finally {
      await second.close();
    }
  });
  test('event audit rejects mutation and event context preserves existing physical stock effect', () async {
    final source = await store.createStockContainer(
      commandId: 'container',
      personId: meId,
      expectedPersonRevision: 1,
      expectedGeneration: store.generation,
      itemId: item.id,
      label: 'Synthetic stock',
      unit: 'count',
      strength: LabelledStrength(ingredientId: item.id, label: 'Count'),
      opening: ExactAmount(BigInt.from(10)),
    );
    await store.record(
      commandId: 'physical-actual',
      itemId: item.id,
      amount: '1',
      actualAt: now,
      stockUse: StockUseInput(
        expectedGeneration: store.generation,
        entered: EnteredStockAmount('1', 'count'),
        containerId: source.id,
        expectedContainerRevision: source.revision,
      ),
    );
    final prior = await store.stockMovements(
      personId: meId,
      containerId: source.id,
    );
    await save(event());
    await store.dismissEventEndReview(
      commandId: 'dismiss-stock',
      review: await store.eventEndReview('event'),
    );
    expect(
      (await store.stockMovements(
        personId: meId,
        containerId: source.id,
      )).length,
      prior.length,
    );
    expect(
      (await store.stockContainerById(
        personId: meId,
        containerId: source.id,
      ))!.balance.value,
      ExactAmount(BigInt.from(9)),
    );
    await store.close();
    final raw = sqlite3.open(path);
    raw.execute("PRAGMA cipher='chacha20'");
    raw.execute(
      'PRAGMA key="x\'${key.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}\'"',
    );
    expect(
      () => raw.execute(
        "UPDATE event_audit SET snapshot='{}' WHERE event='event'",
      ),
      throwsA(isA<SqliteException>()),
    );
    raw.close();
    store = await RecordStore.open(path: path, key: key, isNew: false);
    expect((await store.eventHistory('event')).length, 2);
  });
  test(
    'unknown zone and folded midnight reject explicit boundary review',
    () async {
      await expectLater(
        store.saveEvent(command(event().copyWith(zoneId: 'Europe/Lundon'))),
        throwsA(
          isA<CommandConflict>().having(
            (e) => e.code,
            'code',
            'event_zone_review',
          ),
        ),
      );
      await expectLater(
        store.saveEvent(
          command(
            event().copyWith(
              zoneId: 'America/Havana',
              plannedStart: EventDate.day(CivilDate(2026, 11, 1)),
              plannedEnd: EventDate.day(CivilDate(2026, 11, 2)),
            ),
          ),
        ),
        throwsA(
          isA<CommandConflict>().having(
            (e) => e.code,
            'code',
            'event_boundary_review',
          ),
        ),
      );
    },
  );
  test('actual and completed due events use actionable review without expired native requests', () async {
    final past = event(id: 'past').copyWith(
      actualEnd: EventDate.exact(DateTime.utc(2020)),
      clearPlannedStart: true,
    );
    await save(past, id: 'past-save');
    final completed = await save(
      event(id: 'completed').copyWith(completed: true, clearPlannedEnd: true),
      id: 'completed-save',
    );
    expect(completed.completedAt, isNotNull);
    var p = await store.prepareReminders(
      now: DateTime.now().toUtc().add(const Duration(seconds: 1)),
      observedZone: 'Europe/London',
      clockSample: null,
      adapterFingerprint: 'test',
    );
    expect(p.eventEnds, isEmpty);
    expect(p.eventEndAttention.length, 2);
    expect(
      p.eventEndAttention.every((r) => r.reason == 'event_end_due'),
      isTrue,
    );
    final tokens = p.eventEndAttention.map((r) => r.requestToken).toSet();
    p = await store.prepareReminders(
      now: DateTime.now().toUtc().add(const Duration(minutes: 5)),
      observedZone: 'Europe/London',
      clockSample: null,
      adapterFingerprint: 'test',
    );
    expect(p.eventEndAttention.map((r) => r.requestToken).toSet(), tokens);
    expect(
      (await store.eventById('completed'))!.completedAt,
      completed.completedAt,
    );
  });
  test('dismissal follows one end occurrence and edited future ends invalidate native work', () async {
    await save(event(end: EventDate.day(CivilDate(2026, 10, 24))));
    final p = await store.prepareReminders(
      now: now,
      observedZone: 'Europe/London',
      clockSample: null,
      adapterFingerprint: 'test',
    );
    final oldToken = p.eventEnds.single.requestToken;
    final dismissed = await store.dismissEventEndReview(
      commandId: 'dismiss-new',
      review: await store.eventEndReview('event'),
    );
    final renamed = await save(
      dismissed.copyWith(revision: 3, name: 'Renamed'),
      id: 'renamed',
      expected: 2,
    );
    expect(renamed.endReviewDismissed, isTrue);
    final extended = await save(
      renamed.copyWith(
        revision: 4,
        plannedEnd: EventDate.day(CivilDate(2026, 10, 25)),
      ),
      id: 'extend',
      expected: 3,
    );
    expect(extended.endReviewDismissed, isFalse);
    final next = await store.prepareReminders(
      now: now,
      observedZone: 'Europe/London',
      clockSample: null,
      adapterFingerprint: 'test',
    );
    expect(next.obsoleteTokens, contains(oldToken));
    expect(next.eventEnds.single.requestToken, isNot(oldToken));
  });
  test('one unresolvable stored event does not abort healthy reminder preparation', () async {
    await save(event(id: 'bad'), id: 'bad-save');
    await save(event(id: 'good'), id: 'good-save');
    await store.close();
    final raw = sqlite3.open(path);
    raw.execute("PRAGMA cipher='chacha20'");
    raw.execute(
      'PRAGMA key="x\'${key.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}\'"',
    );
    raw.execute(
      "UPDATE event_record SET snapshot=json_set(snapshot,'\$.zoneId','Europe/Lundon') WHERE id='bad'",
    );
    raw.close();
    store = await RecordStore.open(path: path, key: key, isNew: false);
    final p = await store.prepareReminders(
      now: now,
      observedZone: 'Europe/London',
      clockSample: null,
      adapterFingerprint: 'test',
    );
    expect(p.complete, isFalse);
    expect(p.eventEnds.single.eventId, 'good');
    expect(
      p.exclusions.any(
        (e) => e.scope == 'event:bad' && e.reason == 'event_zone_review',
      ),
      isTrue,
    );
  });
  test('consumed pending and acknowledged obsolete requests prune without reopening native actions', () async {
    await save(event());
    var projection = await store.prepareReminders(
      now: now,
      observedZone: 'Europe/London',
      clockSample: null,
      adapterFingerprint: 'test',
    );
    final r = projection.eventEnds.single;
    expect(
      await store.captureEventEndAction(
        envelopeId: 'open-to-consume',
        namespace: r.namespace,
        requestToken: r.requestToken,
        actionToken: r.requestToken,
        action: ReminderActionKind.open,
      ),
      isTrue,
    );
    await store.consumePendingEventEndReview('open-to-consume');
    await store.prepareReminders(
      now: now,
      observedZone: 'Europe/London',
      clockSample: null,
      adapterFingerprint: 'test',
    );
    expect(
      await store.captureEventEndAction(
        envelopeId: 'replayed-open',
        namespace: r.namespace,
        requestToken: r.requestToken,
        actionToken: r.requestToken,
        action: ReminderActionKind.open,
      ),
      isFalse,
    );
    await store.dismissEventEndReview(
      commandId: 'final-dismiss',
      review: await store.eventEndReview('event'),
    );
    projection = await store.prepareReminders(
      now: now,
      observedZone: 'Europe/London',
      clockSample: null,
      adapterFingerprint: 'test',
    );
    expect(
      await store.acknowledgeObsoleteReminder(
        generation: store.generation,
        requestToken: r.requestToken,
        sequence: projection.sequence,
        receipt: ReminderReceipt.cancelled,
        adapterFingerprint: 'test',
      ),
      isTrue,
    );
    await store.prepareReminders(
      now: now,
      observedZone: 'Europe/London',
      clockSample: null,
      adapterFingerprint: 'test',
    );
    expect(
      await store.captureEventEndAction(
        envelopeId: 'late-native',
        namespace: r.namespace,
        requestToken: r.requestToken,
        actionToken: r.requestToken,
        action: ReminderActionKind.open,
      ),
      isFalse,
    );
    await store.close();
    final raw = sqlite3.open(path);
    raw.execute("PRAGMA cipher='chacha20'");
    raw.execute(
      'PRAGMA key="x\'${key.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}\'"',
    );
    expect(raw.select('SELECT * FROM event_pending'), isEmpty);
    expect(raw.select('SELECT * FROM event_end_request'), isEmpty);
    raw.close();
    store = await RecordStore.open(path: path, key: key, isNew: false);
  });
}
