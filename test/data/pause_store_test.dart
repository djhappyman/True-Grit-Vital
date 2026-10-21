import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:true_grit_vital/data/record_store.dart';

void main() {
  late Directory dir;
  late RecordStore store;
  late SubstanceItem item;
  final key = List.generate(32, (i) => i + 1);
  final date = CivilDate(2026, 10, 19);
  final now = DateTime.utc(2026, 10, 19, 7);
  PlannedAmount amount() => PlannedAmount(
    quantity: ExactQuantity.parse('1'),
    enteredText: '1',
    unit: 'mg',
  );
  DailyPlanVersion plan({
    String version = 'v1',
    List<PlanPause> pauses = const [],
    OnOffPattern? onOff,
    bool interval = false,
    String segment = 's1',
    DateTime? anchor,
  }) => DailyPlanVersion(
    personId: meId,
    planId: 'p',
    itemId: item.id,
    versionId: version,
    start: date,
    zoneBasis: FixedHome('Europe/London'),
    pauses: pauses,
    onOff: onOff,
    timing: interval
        ? ElapsedInterval(
            segmentId: segment,
            duration: ExactElapsed.parseHours('6'),
            mode: IntervalMode.fixedPlanned,
            plannedAnchor: anchor ?? now,
            amount: amount(),
          )
        : DailySlots([
            DailySlot(
              id: 'slot',
              time: WallTime(8, 0),
              amount: amount(),
              reminderEnabled: true,
            ),
          ]),
  );
  Future<SavedDailyPlan> save({bool interval = false}) => store.saveDailyPlan(
    commandId: 'initial',
    plan: plan(interval: interval),
    expectedPersonRevision: 1,
    expectedGeneration: store.generation,
    intervalClockSample: ReminderClockSample(
      bootId: 'boot',
      utcMilliseconds: now.millisecondsSinceEpoch,
      elapsedMilliseconds: 12345,
    ),
  );
  Future<PauseChangeReview> preview(
    SavedDailyPlan old,
    DailyPlanVersion next, {
    DateTime? restartAt,
  }) => store.previewPauseChange(
    plan: old,
    proposed: next,
    now: now,
    observedZone: 'Europe/London',
    restartAt: restartAt,
  );
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('vital-pause-');
    store = await RecordStore.open(
      path: '${dir.path}/records.db',
      key: key,
      isNew: true,
    );
    item = await store.createItem(
      commandId: 'item',
      name: 'Synthetic pause',
      form: 'tablet',
      unit: 'mg',
      type: 'medicine',
    );
  });
  tearDown(() async {
    await store.close();
    await dir.delete(recursive: true);
  });
  test('preview cancellation has no writes; commit replays original and rejects stale race', () async {
    final old = await save();
    final next = plan(
      version: 'v2',
      pauses: [PlanPause(start: now)],
    );
    final review = await preview(old, next);
    expect(await store.pauseHistory(planId: 'p', personId: meId), isEmpty);
    expect((await store.dailyPlans()).single.revision, 1);
    final result = await store.savePauseChange(
      commandId: 'pause',
      review: review,
    );
    expect(result.revision, 2);
    expect(
      (await store.savePauseChange(
        commandId: 'pause',
        review: review,
      )).alreadyCommitted,
      isTrue,
    );
    await expectLater(
      store.savePauseChange(commandId: 'race', review: review),
      throwsA(isA<CommandConflict>()),
    );
    expect(await store.pauseHistory(planId: 'p', personId: meId), hasLength(1));
    expect(
      (await store.dailyRows(
        from: date,
        toExclusive: date.addDays(1),
        observedZone: 'Europe/London',
      )).rows,
      isEmpty,
    );
    expect(await store.records(), isEmpty);
  });
  test('independent connections serialize competing pause commands', () async {
    final old = await save();
    final review = await preview(
      old,
      plan(
        version: 'v2',
        pauses: [PlanPause(start: now)],
      ),
    );
    final other = await RecordStore.open(
      path: '${dir.path}/records.db',
      key: key,
      isNew: false,
    );
    try {
      final outcomes = await Future.wait([
        store
            .savePauseChange(commandId: 'race-a', review: review)
            .then<Object>((v) => v, onError: (Object e) => e),
        other
            .savePauseChange(commandId: 'race-b', review: review)
            .then<Object>((v) => v, onError: (Object e) => e),
      ]);
      expect(outcomes.whereType<SavedDailyPlan>(), hasLength(1));
      expect(outcomes.whereType<CommandConflict>(), hasLength(1));
      expect(
        await store.pauseHistory(planId: 'p', personId: meId),
        hasLength(1),
      );
    } finally {
      await other.close();
    }
  });
  test('native ordinary and Snooze targets cancel atomically and late acknowledgements cannot restore', () async {
    final old = await save();
    await store.setPlanReminders(
      commandId: 'enable',
      planId: 'p',
      personId: meId,
      expectedPlanRevision: 1,
      expectedPersonRevision: 1,
      enabled: true,
    );
    final clock = ReminderClockSample(
      bootId: 'boot',
      utcMilliseconds: now.millisecondsSinceEpoch,
      elapsedMilliseconds: 1000,
    );
    final prepared = await store.prepareReminders(
      now: now.subtract(const Duration(hours: 1)),
      observedZone: 'Europe/London',
      clockSample: clock,
      adapterFingerprint: 'test',
    );
    expect(prepared.desired, isNotEmpty);
    final row = (await store.dailyRows(
      from: date,
      toExclusive: date.addDays(1),
      observedZone: 'Europe/London',
    )).rows.single;
    final target = await store.reminderTarget(
      row,
      observedZone: 'Europe/London',
    );
    final deferred = await store.snoozeReminder(
      SnoozeCommand(
        commandId: 'snooze',
        target: target,
        delayMinutes: 15,
        sample: clock,
        observedZone: 'Europe/London',
      ),
      currentObservedZone: 'Europe/London',
    );
    await store.savePauseChange(
      commandId: 'pause',
      review: await preview(
        old,
        plan(
          version: 'v2',
          pauses: [PlanPause(start: now)],
        ),
      ),
    );
    await expectLater(
      store.snoozeReminder(
        SnoozeCommand(
          commandId: 'old-snooze',
          target: target,
          delayMinutes: 15,
          sample: clock,
          observedZone: 'Europe/London',
        ),
        currentObservedZone: 'Europe/London',
      ),
      throwsA(isA<CommandConflict>()),
    );
    expect(
      await store.acknowledgeReminder(
        generation: store.generation,
        requestToken: deferred.desired.requestToken,
        intentRevision: deferred.desired.intentRevision,
        sequence: prepared.sequence,
        receipt: ReminderReceipt.accepted,
        adapterFingerprint: 'test',
      ),
      false,
    );
    final after = await store.prepareReminders(
      now: now,
      observedZone: 'Europe/London',
      clockSample: clock,
      adapterFingerprint: 'test',
    );
    expect(after.desired, isEmpty);
    expect(after.obsoleteTokens, contains(deferred.desired.requestToken));
    expect(await store.records(), isEmpty);
  });
  test('partial untimed pause and restart retain one date bucket and original progress', () async {
    final base = plan();
    DailyPlanVersion count(
      String version,
      List<PlanPause> pauses, {
      OnOffPattern? block,
    }) => DailyPlanVersion(
      personId: base.personId,
      planId: base.planId,
      itemId: base.itemId,
      versionId: version,
      start: base.start,
      zoneBasis: base.zoneBasis,
      timing: DailyCount(2, amount()),
      pauses: pauses,
      onOff: block,
    );
    final original = await store.saveDailyPlan(
      commandId: 'initial-count',
      plan: count('v1', []),
      expectedPersonRevision: 1,
      expectedGeneration: store.generation,
    );
    final first = (await store.dailyRows(
      from: date,
      toExclusive: date.addDays(1),
      observedZone: 'Europe/London',
    )).rows.single;
    expect(first.expectation.instant, isNull);
    await store.actDaily(
      commandId: 'take-count',
      row: first,
      kind: DailyActionKind.taken,
      actualAt: now,
    );
    final pauses = [
      PlanPause(start: now, resume: now.add(const Duration(hours: 1))),
    ];
    final reviewed = await preview(original, count('v2', pauses));
    expect(reviewed.afterDate, date);
    expect(reviewed.after?.instant, isNull);
    final paused = await store.savePauseChange(
      commandId: 'count-pause',
      review: reviewed,
    );
    final restart = count(
      'v3',
      pauses,
      block: OnOffPattern(anchor: date, onDays: 3, offDays: 2),
    );
    await store.savePauseChange(
      commandId: 'count-restart',
      review: await preview(
        paused,
        restart,
        restartAt: now.add(const Duration(hours: 1)),
      ),
    );
    final after = (await store.dailyRows(
      from: date,
      toExclusive: date.addDays(1),
      observedZone: 'Europe/London',
    )).rows.single;
    expect(after.expectation.identity, first.expectation.identity);
    expect(after.takenCount, 1);
    expect(after.plannedCount, 2);
    expect(after.expectation.instant, isNull);
    expect((await store.capturedDailyRows()).rows, hasLength(1));
    expect(await store.records(), hasLength(1));
  });
  test(
    'actual inside a pause cannot resolve a later eligible planned slot',
    () async {
      final old = await save();
      final pauseStart = now.subtract(const Duration(minutes: 30));
      final pauseEnd = now.subtract(const Duration(minutes: 15));
      await store.savePauseChange(
        commandId: 'pause',
        review: await preview(
          old,
          plan(
            version: 'v2',
            pauses: [PlanPause(start: pauseStart, resume: pauseEnd)],
          ),
        ),
      );
      final row = (await store.dailyRows(
        from: date,
        toExclusive: date.addDays(1),
        observedZone: 'Europe/London',
      )).rows.single;
      await expectLater(
        store.actDaily(
          commandId: 'inside',
          row: row,
          kind: DailyActionKind.taken,
          actualAt: pauseStart.add(const Duration(minutes: 1)),
        ),
        throwsA(isA<CommandConflict>()),
      );
      expect(await store.records(), isEmpty);
      await store.record(
        commandId: 'standalone',
        itemId: item.id,
        amount: '1',
        actualAt: pauseStart.add(const Duration(minutes: 1)),
      );
      expect(await store.records(), hasLength(1));
      expect((await store.capturedDailyRows()).rows, isEmpty);
    },
  );
  test('exact same-day elapsed restart retains earlier uncaptured segment and replay', () async {
    final base = plan(interval: true, anchor: DateTime.utc(2026, 10, 19));
    final old = await store.saveDailyPlan(
      commandId: 'fixed',
      plan: base,
      expectedPersonRevision: 1,
      expectedGeneration: store.generation,
    );
    final boundary = DateTime.utc(2026, 10, 19, 10);
    final next = plan(
      interval: true,
      version: 'v2',
      segment: 's2',
      anchor: DateTime.utc(2026, 10, 19, 11),
      pauses: [
        PlanPause(start: DateTime.utc(2026, 10, 19, 6), resume: boundary),
      ],
    );
    final review = await preview(old, next, restartAt: boundary);
    expect((await store.dailyPlanVersions('p', personId: meId)), hasLength(1));
    await store.savePauseChange(commandId: 'restart-exact', review: review);
    final rows = (await store.dailyRows(
      from: date,
      toExclusive: date.addDays(1),
      observedZone: 'Europe/London',
    )).rows;
    expect(rows.map((r) => r.expectation.instant).toList(), [
      DateTime.utc(2026, 10, 19),
      DateTime.utc(2026, 10, 19, 11),
      DateTime.utc(2026, 10, 19, 17),
    ]);
    expect(rows.first.expectation.identity.intervalSegmentId, 's1');
    expect(rows.last.expectation.identity.intervalSegmentId, 's2');
    final versions = await store.dailyPlanVersions('p', personId: meId);
    expect(versions, hasLength(2));
    expect(versions.first.plan.effectiveUntil, boundary);
    expect(versions.last.plan.effectiveFrom, boundary);
    expect(
      (await store.savePauseChange(
        commandId: 'restart-exact',
        review: review,
      )).alreadyCommitted,
      true,
    );
    expect(await store.records(), isEmpty);
  });
  test(
    'calendar restart retains past uncaptured parity and exact intra-day slots',
    () async {
      DailyPlanVersion selected(
        String version,
        CivilDate anchor, {
        List<PlanPause> pauses = const [],
      }) => DailyPlanVersion(
        personId: meId,
        planId: 'p',
        itemId: item.id,
        versionId: version,
        start: date,
        zoneBasis: FixedHome('Europe/London'),
        calendar: EveryNDays(anchor: anchor, interval: 2),
        pauses: pauses,
        timing: DailySlots([
          DailySlot(
            id: 'am',
            time: WallTime(8, 0),
            amount: amount(),
            reminderEnabled: true,
          ),
          DailySlot(
            id: 'pm',
            time: WallTime(20, 0),
            amount: amount(),
            reminderEnabled: true,
          ),
        ]),
      );
      final old = await store.saveDailyPlan(
        commandId: 'calendar',
        plan: selected('v1', date),
        expectedPersonRevision: 1,
        expectedGeneration: store.generation,
      );
      final boundary = DateTime.utc(2026, 10, 20, 10);
      final next = selected(
        'v2',
        date.addDays(1),
        pauses: [
          PlanPause(start: DateTime.utc(2026, 10, 19, 10), resume: boundary),
        ],
      );
      final review = await preview(old, next, restartAt: boundary);
      await store.savePauseChange(
        commandId: 'restart-calendar',
        review: review,
      );
      final rows = (await store.dailyRows(
        from: date,
        toExclusive: date.addDays(3),
        observedZone: 'Europe/London',
      )).rows;
      expect(rows.map((r) => r.expectation.instant).toList(), [
        DateTime.utc(2026, 10, 19, 7),
        DateTime.utc(2026, 10, 20, 19),
      ]);
      expect(rows.first.expectation.versionId, 'v1');
      expect(rows.last.expectation.versionId, 'v2');
      expect((await store.dailyPlans()).single.plan.versionId, 'v2');
    },
  );
  test('ordinary amount edit after exact restart preserves closed sibling and native projection', () async {
    final base = plan(interval: true, anchor: DateTime.utc(2026, 10, 19));
    final old = await store.saveDailyPlan(
      commandId: 'fixed',
      plan: base,
      expectedPersonRevision: 1,
      expectedGeneration: store.generation,
    );
    final boundary = DateTime.utc(2026, 10, 19, 10);
    final next = plan(
      interval: true,
      version: 'v2',
      segment: 's2',
      anchor: DateTime.utc(2026, 10, 19, 11),
      pauses: [
        PlanPause(start: DateTime.utc(2026, 10, 19, 6), resume: boundary),
      ],
    );
    final resumed = await store.savePauseChange(
      commandId: 'restart',
      review: await preview(old, next, restartAt: boundary),
    );
    final t = resumed.plan.timing as ElapsedInterval;
    final edited = DailyPlanVersion(
      personId: meId,
      planId: 'p',
      itemId: item.id,
      versionId: 'v3',
      start: resumed.plan.start,
      endExclusive: resumed.plan.endExclusive,
      zoneBasis: resumed.plan.zoneBasis,
      calendar: resumed.plan.calendar,
      pauses: resumed.plan.pauses,
      onOff: resumed.plan.onOff,
      effectiveFrom: resumed.plan.effectiveFrom,
      effectiveUntil: resumed.plan.effectiveUntil,
      timing: ElapsedInterval(
        segmentId: t.segmentId,
        duration: t.duration,
        mode: t.mode,
        plannedAnchor: t.plannedAnchor,
        amount: PlannedAmount(
          quantity: ExactQuantity.parse('2'),
          enteredText: '2',
          unit: 'mg',
        ),
      ),
    );
    await store.saveDailyPlan(
      commandId: 'ordinary-amount-edit',
      plan: edited,
      expectedPersonRevision: 1,
      expectedGeneration: store.generation,
      expectedPlanRevision: resumed.revision,
      intervalClockSample: ReminderClockSample(
        bootId: 'boot',
        utcMilliseconds: now.millisecondsSinceEpoch,
        elapsedMilliseconds: 1000,
      ),
    );
    final afterEdit = (await store.dailyRows(
      from: date,
      toExclusive: date.addDays(1),
      observedZone: 'Europe/London',
    )).rows;
    expect(afterEdit.map((r) => r.expectation.instant), [
      DateTime.utc(2026, 10, 19),
      DateTime.utc(2026, 10, 19, 11),
      DateTime.utc(2026, 10, 19, 17),
    ]);
    expect(afterEdit.first.expectation.amount.enteredText, '1');
    expect(afterEdit.last.expectation.amount.enteredText, '2');
    expect(
      (await store.dailyPlanVersions(
        'p',
        personId: meId,
      )).first.plan.effectiveUntil,
      boundary,
    );
    await store.setPlanReminders(
      commandId: 'enable-after-edit',
      planId: 'p',
      personId: meId,
      expectedPersonRevision: 1,
      expectedPlanRevision: 3,
      enabled: true,
    );
    final native = await store.prepareReminders(
      now: DateTime.utc(2026, 10, 19, 10, 30),
      observedZone: 'Europe/London',
      clockSample: ReminderClockSample(
        bootId: 'boot',
        utcMilliseconds: DateTime.utc(
          2026,
          10,
          19,
          10,
          30,
        ).millisecondsSinceEpoch,
        elapsedMilliseconds: 12601000,
      ),
      adapterFingerprint: 'test',
    );
    expect(native.desired, isNotEmpty);
    expect(
      native.desired.every(
        (r) => r.target.row.expectation.identity.intervalSegmentId == 's2',
      ),
      true,
    );
  });
  test('pause atomic rollback retains old plan and no history', () async {
    final old = await save();
    final review = await preview(
      old,
      plan(
        version: 'v2',
        pauses: [PlanPause(start: now)],
      ),
    );
    await expectLater(
      store.savePauseChange(
        commandId: 'rollback',
        review: review,
        failBeforeCommit: true,
      ),
      throwsA(anything),
    );
    expect((await store.dailyPlans()).single.revision, 1);
    expect(await store.pauseHistory(planId: 'p', personId: meId), isEmpty);
  });
  test(
    'captured history persists and old action cannot restore suppressed slot',
    () async {
      final old = await save();
      final row = (await store.dailyRows(
        from: date,
        toExclusive: date.addDays(1),
        observedZone: 'Europe/London',
      )).rows.single;
      await store.actDaily(
        commandId: 'skip',
        row: row,
        kind: DailyActionKind.skip,
      );
      final review = await preview(
        old,
        plan(
          version: 'v2',
          pauses: [PlanPause(start: now)],
        ),
      );
      await store.savePauseChange(commandId: 'pause', review: review);
      expect((await store.capturedDailyRows()).rows, hasLength(1));
      await expectLater(
        store.actDaily(
          commandId: 'old',
          row: row,
          kind: DailyActionKind.taken,
          actualAt: now,
        ),
        throwsA(isA<CommandConflict>()),
      );
      expect(
        (await store.actDaily(
          commandId: 'skip',
          row: row,
          kind: DailyActionKind.skip,
        )).alreadyCommitted,
        isTrue,
      );
      expect(await store.records(), isEmpty);
    },
  );
  test('preserve retains native clock through encrypted reopen; restart has distinct segment', () async {
    final old = await save(interval: true);
    final next = plan(
      interval: true,
      version: 'v2',
      pauses: [
        PlanPause(start: now, resume: now.add(const Duration(days: 10))),
      ],
      onOff: OnOffPattern(anchor: date, onDays: 3, offDays: 2),
    );
    final result = await store.savePauseChange(
      commandId: 'pause',
      review: await preview(old, next),
    );
    await store.close();
    store = await RecordStore.open(
      path: '${dir.path}/records.db',
      key: key,
      isNew: false,
    );
    final p = (await store.dailyPlans()).single;
    expect(p.plan.pauses.single.resume, now.add(const Duration(days: 10)));
    expect(p.plan.onOff!.offDays, 2);
    final restart = plan(
      interval: true,
      version: 'v3',
      segment: 's2',
      anchor: now.add(const Duration(days: 11)),
      pauses: next.pauses,
      onOff: next.onOff,
    );
    await store.savePauseChange(
      commandId: 'restart',
      review: await preview(
        result,
        restart,
        restartAt: now.add(const Duration(days: 11)),
      ),
      intervalClockSample: ReminderClockSample(
        bootId: 'new-boot',
        utcMilliseconds: now.millisecondsSinceEpoch,
        elapsedMilliseconds: 999,
      ),
    );
    expect(await store.records(), isEmpty);
    expect(await store.pauseHistory(planId: 'p', personId: meId), hasLength(2));
    await store.close();
    final raw = sqlite3.open('${dir.path}/records.db');
    raw.execute("PRAGMA cipher='chacha20'");
    raw.execute(
      'PRAGMA key="x\'${key.map((x) => x.toRadixString(16).padLeft(2, '0')).join()}\'"',
    );
    expect(
      raw
          .select('SELECT boot,elapsed FROM interval_clock ORDER BY segment')
          .map((r) => [r['boot'], r['elapsed']])
          .toList(),
      [
        ['boot', 12345],
        ['new-boot', 999],
      ],
    );
    raw.close();
    store = await RecordStore.open(
      path: '${dir.path}/records.db',
      key: key,
      isNew: false,
    );
  });
  test('schema11 populated migration preserves clock qualification recovery products and drafts', () async {
    await store.close();
    await File('${dir.path}/records.db').delete();
    final raw = sqlite3.open('${dir.path}/records.db');
    raw.execute("PRAGMA cipher='chacha20'");
    raw.execute(
      'PRAGMA key="x\'${key.map((x) => x.toRadixString(16).padLeft(2, '0')).join()}\'"',
    );
    raw.execute(
      File('test/data/fixtures/record_store_v11.sql').readAsStringSync(),
    );
    raw.close();
    store = await RecordStore.open(
      path: '${dir.path}/records.db',
      key: key,
      isNew: false,
    );
    expect(
      await store.intervalSources(planId: 'calendar-plan', personId: 'other'),
      hasLength(1),
    );
    expect(await store.drafts(), isNotEmpty);
    expect(
      (await store.recordById('product-fixture', personId: 'other'))!.product,
      isNotNull,
    );
    await store.close();
    final check = sqlite3.open('${dir.path}/records.db');
    check.execute("PRAGMA cipher='chacha20'");
    check.execute(
      'PRAGMA key="x\'${key.map((x) => x.toRadixString(16).padLeft(2, '0')).join()}\'"',
    );
    expect(check.select('PRAGMA user_version').single.values.single, 22);
    expect(
      check.select('SELECT * FROM interval_clock').single['elapsed'],
      12345,
    );
    expect(
      check.select('SELECT * FROM interval_recovery').single['cutoff'],
      '2026-10-19',
    );
    check.close();
    store = await RecordStore.open(
      path: '${dir.path}/records.db',
      key: key,
      isNew: false,
    );
  });
  test('failed schema11 migration rolls back version and source recovery', () async {
    final path = '${dir.path}/failed.db';
    final raw = sqlite3.open(path);
    raw.execute("PRAGMA cipher='chacha20'");
    raw.execute(
      'PRAGMA key="x\'${key.map((x) => x.toRadixString(16).padLeft(2, '0')).join()}\'"',
    );
    raw.execute(
      File('test/data/fixtures/record_store_v11.sql').readAsStringSync(),
    );
    raw.execute('CREATE TABLE pause_change(recovery TEXT)');
    raw.close();
    await expectLater(
      RecordStore.open(path: path, key: key, isNew: false),
      throwsA(anything),
    );
    final check = sqlite3.open(path);
    check.execute("PRAGMA cipher='chacha20'");
    check.execute(
      'PRAGMA key="x\'${key.map((x) => x.toRadixString(16).padLeft(2, '0')).join()}\'"',
    );
    expect(check.select('PRAGMA user_version').single.values.single, 11);
    expect(check.select('SELECT * FROM interval_clock'), hasLength(1));
    expect(check.select('SELECT * FROM ordinary_draft'), isNotEmpty);
    check.close();
  });
}
