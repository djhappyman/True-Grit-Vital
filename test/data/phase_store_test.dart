import 'dart:io';

import 'package:true_grit_vital/domain/scheduling/iana_clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:true_grit_vital/data/record_store.dart';
import 'package:true_grit_vital/data/daily_codec.dart';

void main() {
  late Directory dir;
  late RecordStore store;
  late SubstanceItem item;
  final key = List.generate(32, (i) => i + 1);
  final date = CivilDate(2026, 10, 19), tomorrow = CivilDate(2026, 10, 20);
  final now = DateTime.utc(2026, 10, 19, 6);
  PlannedAmount amount(String text) => PlannedAmount(
    quantity: ExactQuantity.parse(text),
    enteredText: text,
    unit: 'mg',
  );
  DailyPlanVersion plan({
    String version = 'v1',
    CivilDate? start,
    CivilDate? end,
    DailyTiming? timing,
  }) => DailyPlanVersion(
    personId: meId,
    planId: 'p',
    itemId: item.id,
    versionId: version,
    start: start ?? date,
    endExclusive: end,
    zoneBasis: FixedHome('Europe/London'),
    timing:
        timing ??
        DailySlots([
          DailySlot(
            id: 'slot',
            time: WallTime(8, 0),
            amount: amount('1'),
            reminderEnabled: true,
          ),
        ]),
  );
  Future<SavedDailyPlan> save() => store.saveDailyPlan(
    commandId: 'initial',
    plan: plan(),
    expectedPersonRevision: 1,
    expectedGeneration: store.generation,
  );
  Future<PhaseChangeReview> preview(SavedDailyPlan old, PhasePlan candidate) =>
      store.previewPhasePlan(
        plan: old,
        proposed: candidate,
        now: now,
        observedZone: 'Europe/London',
      );
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('vital-phase-');
    store = await RecordStore.open(
      path: '${dir.path}/records.db',
      key: key,
      isNew: true,
    );
    item = await store.createItem(
      commandId: 'item',
      name: 'Synthetic phases',
      form: 'tablet',
      unit: 'mg',
      type: 'medicine',
    );
  });
  tearDown(() async {
    await store.close();
    await dir.delete(recursive: true);
  });
  test('phases close a prefix without changing uncaptured past, replay and stale review', () async {
    final old = await save();
    final candidate = PhasePlan(
      phases: [
        plan(end: tomorrow),
        plan(
          version: 'v2',
          start: tomorrow,
          timing: DailyCount(2, amount('2')),
        ),
      ],
      end: PlanEnd.onDate(
        lastDate: tomorrow,
        zoneId: 'Europe/London',
        clock: IanaClock(),
      ),
    );
    final review = await preview(old, candidate);
    expect((await store.dailyPlanVersions('p', personId: meId)), hasLength(1));
    final saved = await store.savePhasePlan(
      commandId: 'phases',
      review: review,
    );
    expect(saved.revision, 2);
    expect(
      (await store.savePhasePlan(
        commandId: 'phases',
        review: review,
      )).alreadyCommitted,
      true,
    );
    await expectLater(
      store.savePhasePlan(commandId: 'race', review: review),
      throwsA(isA<CommandConflict>()),
    );
    final rows = await store.dailyRows(
      from: date,
      toExclusive: tomorrow.addDays(2),
      observedZone: 'America/New_York',
    );
    expect(rows.complete, true);
    expect(rows.rows, hasLength(2));
    expect(rows.rows.first.expectation.amount.enteredText, '1');
    expect(rows.rows.last.expectation.amount.enteredText, '2');
    expect(await store.records(), isEmpty);
    await store.close();
    store = await RecordStore.open(
      path: '${dir.path}/records.db',
      key: key,
      isNew: false,
    );
    expect(
      (await store.phasePlan(planId: 'p', personId: meId))!.end!.zoneId,
      'Europe/London',
    );
  });
  test('moved original keeps quantity, independently collides and writes no stock or actual', () async {
    final old = await save();
    final identity = DailyIdentity(
      personId: meId,
      planId: 'p',
      originalDate: date,
      slotId: 'slot',
    );
    final sibling = DailyIdentity(
      personId: meId,
      planId: 'p',
      originalDate: tomorrow,
      slotId: 'slot',
    );
    PhasePlan candidate(bool reviewed) => PhasePlan(
      phases: [plan()],
      overrides: [
        OccurrenceOverride(
          identity: identity,
          versionId: 'v1',
          targetInstant: DateTime.utc(2026, 10, 20, 7),
          targetZoneId: 'Europe/London',
          reviewedCollisions: reviewed ? [sibling] : [],
        ),
      ],
    );
    await expectLater(preview(old, candidate(false)), throwsArgumentError);
    final review = await preview(old, candidate(true));
    await store.savePhasePlan(commandId: 'move', review: review);
    expect(
      (await store.dailyRows(
        from: date,
        toExclusive: tomorrow,
        observedZone: 'Europe/London',
      )).rows,
      isEmpty,
    );
    final target = (await store.dailyRows(
      from: tomorrow,
      toExclusive: tomorrow.addDays(1),
      observedZone: 'Europe/London',
    )).rows;
    expect(target, hasLength(2));
    final moved = target.singleWhere((r) => r.expectation.identity == identity);
    expect(moved.expectation.originalAmount!.enteredText, '1');
    expect(moved.expectation.originalInstant, DateTime.utc(2026, 10, 19, 7));
    expect(await store.records(), isEmpty);
    await store.actDaily(
      commandId: 'take',
      row: moved,
      kind: DailyActionKind.taken,
      actualAt: DateTime.utc(2026, 10, 20, 7, 5),
    );
    expect(
      (await store.capturedDailyRows()).rows.single.expectation.identity,
      identity,
    );
  });
  test(
    'window endpoints and mixed timed count persist without inferred actual',
    () async {
      final window = plan(
        timing: DailyWindows(
          windows: [
            DailyWindow(
              id: 'night',
              start: WallTime(23, 0),
              end: WallTime(1, 0),
              amount: amount('1'),
            ),
          ],
        ),
      );
      final old = await store.saveDailyPlan(
        commandId: 'window',
        plan: window,
        expectedPersonRevision: 1,
        expectedGeneration: store.generation,
      );
      final review = await preview(old, PhasePlan(phases: [window]));
      await store.savePhasePlan(commandId: 'finite-window', review: review);
      final row = (await store.dailyRows(
        from: date,
        toExclusive: tomorrow,
        observedZone: 'Europe/London',
      )).rows.single;
      expect(row.expectation.instant, isNull);
      expect(row.expectation.windowStart, DateTime.utc(2026, 10, 19, 22));
      expect(row.expectation.windowEnd, DateTime.utc(2026, 10, 20));
      final encoded = encodeDailyExpectation(row.expectation);
      expect(
        encodeDailyExpectation(
          decodeDailyExpectation(Map<String, dynamic>.from(encoded)),
        ),
        encoded,
      );
      await store.actDaily(
        commandId: 'window-taken',
        row: row,
        kind: DailyActionKind.taken,
        actualAt: DateTime.utc(2026, 10, 19, 22, 30),
      );
      expect(
        (await store.records()).single.actualAt,
        DateTime.utc(2026, 10, 19, 22, 30),
      );
      final mixed = plan(
        version: 'v2',
        start: tomorrow,
        timing: MixedDailyCount(
          count: 3,
          amount: amount('1'),
          slots: [
            DailySlot(
              id: 'known',
              time: WallTime(8, 0),
              reminderEnabled: false,
              amount: amount('2'),
            ),
          ],
        ),
      );
      expect(
        decodeDailyPlan(Map<String, dynamic>.from(encodeDailyPlan(mixed)))
            .timing,
        isA<MixedDailyCount>(),
      );
      await store.saveDailyPlan(
        commandId: 'mixed',
        plan: mixed,
        expectedPersonRevision: 1,
        expectedGeneration: store.generation,
        expectedPlanRevision: 2,
      );
      final mixedRows = (await store.dailyRows(
        from: tomorrow,
        toExclusive: tomorrow.addDays(1),
        observedZone: 'Europe/London',
      )).rows;
      expect(mixedRows, hasLength(2));
      expect(mixedRows.fold<int>(0, (sum, row) => sum + row.plannedCount), 3);
      final timed = mixedRows.singleWhere((r) => r.expectation.instant != null);
      await store.actDaily(
        commandId: 'mixed-taken',
        row: timed,
        kind: DailyActionKind.taken,
        actualAt: DateTime.utc(2026, 10, 20, 7),
      );
      expect((await store.records()).first.enteredAmount, '2');
    },
  );
  test(
    'failed phase transaction is empty and exact command can retry',
    () async {
      final old = await save();
      final review = await preview(
        old,
        PhasePlan(
          phases: [plan()],
          end: PlanEnd(
            zoneId: 'Europe/London',
            exclusiveInstant: DateTime.utc(2026, 10, 20),
          ),
        ),
      );
      await expectLater(
        store.savePhasePlan(
          commandId: 'rollback',
          review: review,
          failBeforeCommit: true,
        ),
        throwsA(anything),
      );
      expect(await store.phasePlan(planId: 'p', personId: meId), isNull);
      expect((await store.dailyPlans()).single.revision, 1);
      expect(
        (await store.savePhasePlan(
          commandId: 'rollback',
          review: review,
        )).revision,
        2,
      );
    },
  );
  test('populated encrypted v12 migration and failure rollback preserve sources drafts and pause audit', () async {
    Future<void> seed(String path, {bool collide = false}) async {
      final raw = sqlite3.open(path);
      raw.execute("PRAGMA cipher='chacha20'");
      raw.execute(
        'PRAGMA key="x\'${key.map((x) => x.toRadixString(16).padLeft(2, '0')).join()}\'"',
      );
      raw.execute(
        File('test/data/fixtures/record_store_v12.sql').readAsStringSync(),
      );
      if (collide) raw.execute('CREATE TABLE phase_plan(recovery TEXT)');
      raw.close();
    }

    final migrated = '${dir.path}/v12.db';
    await seed(migrated);
    final next = await RecordStore.open(path: migrated, key: key, isNew: false);
    expect(
      await next.pauseHistory(planId: 'calendar-plan', personId: 'other'),
      hasLength(1),
    );
    expect(
      await next.intervalSources(planId: 'calendar-plan', personId: 'other'),
      hasLength(1),
    );
    expect(await next.drafts(), isNotEmpty);
    final versions = await next.dailyPlanVersions(
      'calendar-plan',
      personId: 'other',
    );
    expect(versions, hasLength(2));
    expect(
      versions.first.plan.effectiveUntil,
      DateTime.fromMicrosecondsSinceEpoch(1792411200000000, isUtc: true),
    );
    expect(
      versions.last.plan.effectiveFrom,
      versions.first.plan.effectiveUntil,
    );
    expect(versions.first.plan.pauses, hasLength(1));
    await next.close();
    final failed = '${dir.path}/failed.db';
    await seed(failed, collide: true);
    await expectLater(
      RecordStore.open(path: failed, key: key, isNew: false),
      throwsA(anything),
    );
    final raw = sqlite3.open(failed);
    raw.execute("PRAGMA cipher='chacha20'");
    raw.execute(
      'PRAGMA key="x\'${key.map((x) => x.toRadixString(16).padLeft(2, '0')).join()}\'"',
    );
    expect(raw.select('PRAGMA user_version').single.values.single, 12);
    expect(raw.select('SELECT * FROM pause_change'), hasLength(1));
    expect(raw.select('SELECT * FROM interval_clock'), hasLength(1));
    raw.close();
  });
  test('far moved-in date is indexed, suppresses original, preserves native identity and invalidates delayed ack', () async {
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
      elapsedMilliseconds: 12345,
    );
    final initial = await store.prepareReminders(
      now: now,
      observedZone: 'Europe/London',
      clockSample: clock,
      adapterFingerprint: 'test',
    );
    final targetDate = CivilDate(2026, 11, 3);
    final identity = DailyIdentity(
      personId: meId,
      planId: 'p',
      originalDate: date,
      slotId: 'slot',
    );
    final candidate = PhasePlan(
      phases: [plan()],
      overrides: [
        OccurrenceOverride(
          identity: identity,
          versionId: 'v1',
          targetInstant: DateTime.utc(2026, 11, 3, 10),
          targetZoneId: 'Europe/London',
        ),
      ],
    );
    final review = await preview(old, candidate);
    await store.savePhasePlan(commandId: 'far-move', review: review);
    final moved = (await store.dailyRows(
      from: targetDate,
      toExclusive: targetDate.addDays(1),
      observedZone: 'Europe/London',
    )).rows.singleWhere((r) => r.expectation.identity == identity);
    expect(moved.expectation.instant, DateTime.utc(2026, 11, 3, 10));
    expect(
      (await store.dailyRows(
        from: date,
        toExclusive: date.addDays(1),
        observedZone: 'Europe/London',
      )).rows,
      isEmpty,
    );
    expect(
      await store.acknowledgeReminder(
        generation: store.generation,
        requestToken: initial.desired.first.requestToken,
        intentRevision: initial.desired.first.intentRevision,
        sequence: initial.sequence,
        receipt: ReminderReceipt.accepted,
        adapterFingerprint: 'test',
      ),
      false,
    );
    final native = await store.prepareReminders(
      now: DateTime.utc(2026, 11, 3),
      observedZone: 'Europe/London',
      clockSample: ReminderClockSample(
        bootId: 'boot',
        utcMilliseconds: DateTime.utc(2026, 11, 3).millisecondsSinceEpoch,
        elapsedMilliseconds: 12345 + 15 * 86400000,
      ),
      adapterFingerprint: 'test',
    );
    expect(
      native.desired.any((r) => r.target.row.expectation.identity == identity),
      true,
    );
  });

  test('whole window moves preserve endpoints and captured actual cannot be retargeted', () async {
    final window = plan(
      timing: DailyWindows(
        windows: [
          DailyWindow(
            id: 'night',
            start: WallTime(23, 0),
            end: WallTime(1, 0),
            amount: amount('1'),
            reminderAnchor: WallTime(23, 30),
            reminderEnabled: true,
          ),
        ],
      ),
    );
    final old = await store.saveDailyPlan(
      commandId: 'window',
      plan: window,
      expectedPersonRevision: 1,
      expectedGeneration: store.generation,
    );
    final identity = DailyIdentity(
      personId: meId,
      planId: 'p',
      originalDate: date,
      slotId: 'night',
    );
    final candidate = PhasePlan(
      phases: [window],
      overrides: [
        OccurrenceOverride(
          identity: identity,
          versionId: 'v1',
          windowTarget: WindowOverrideTarget(
            start: DateTime.utc(2026, 10, 21, 2),
            end: DateTime.utc(2026, 10, 21, 4),
            zoneId: 'Europe/London',
            reminderAnchor: DateTime.utc(2026, 10, 21, 3),
          ),
        ),
      ],
    );
    await store.savePhasePlan(
      commandId: 'move-window',
      review: await preview(old, candidate),
    );
    final row = (await store.dailyRows(
      from: CivilDate(2026, 10, 21),
      toExclusive: CivilDate(2026, 10, 22),
      observedZone: 'Europe/London',
    )).rows.singleWhere((r) => r.expectation.identity == identity);
    expect(row.expectation.windowStart, DateTime.utc(2026, 10, 21, 2));
    expect(row.expectation.windowEnd, DateTime.utc(2026, 10, 21, 4));
    expect(row.expectation.originalWindowStart, DateTime.utc(2026, 10, 19, 22));
    expect(row.expectation.amount.enteredText, '1');
    await store.actDaily(
      commandId: 'window-actual',
      row: row,
      kind: DailyActionKind.taken,
      actualAt: DateTime.utc(2026, 10, 21, 3, 15),
    );
    final current = (await store.dailyPlans()).single;
    await expectLater(
      preview(current, PhasePlan(phases: [window])),
      throwsA(isA<CommandConflict>()),
    );
    expect(
      (await store.records()).single.actualAt,
      DateTime.utc(2026, 10, 21, 3, 15),
    );
    expect(
      (await store.capturedDailyRows())
          .rows
          .single
          .expectation
          .originalWindowEnd,
      DateTime.utc(2026, 10, 20),
    );
  });

  test('pause replacement preserves archived override origin and resuming restores eligibility', () async {
    final old = await save();
    final identity = DailyIdentity(
      personId: meId,
      planId: 'p',
      originalDate: date,
      slotId: 'slot',
    );
    final candidate = PhasePlan(
      phases: [plan()],
      overrides: [
        OccurrenceOverride(
          identity: identity,
          versionId: 'v1',
          targetInstant: DateTime.utc(2026, 10, 20, 10),
          targetZoneId: 'Europe/London',
        ),
      ],
    );
    final moved = await store.savePhasePlan(
      commandId: 'move',
      review: await preview(old, candidate),
    );
    DailyPlanVersion paused(String version, DateTime? resume) =>
        DailyPlanVersion(
          personId: meId,
          planId: 'p',
          itemId: item.id,
          versionId: version,
          start: date,
          zoneBasis: FixedHome('Europe/London'),
          timing: plan().timing,
          pauses: [
            PlanPause(start: DateTime.utc(2026, 10, 20, 9), resume: resume),
          ],
        );
    final pausedReview = await store.previewPauseChange(
      plan: moved,
      proposed: paused('v2', null),
      now: now,
      observedZone: 'Europe/London',
    );
    final changed = await store.savePauseChange(
      commandId: 'pause',
      review: pausedReview,
    );
    final aggregate = (await store.phasePlan(planId: 'p', personId: meId))!;
    expect(aggregate.originPhases.single.versionId, 'v1');
    expect(aggregate.overrides.single.versionId, 'v1');
    final suppressed = (await store.dailyRows(
      from: tomorrow,
      toExclusive: tomorrow.addDays(1),
      observedZone: 'Europe/London',
    )).rows;
    expect(suppressed.any((r) => r.expectation.identity == identity), false);
    final resumedReview = await store.previewPauseChange(
      plan: changed,
      proposed: paused('v3', DateTime.utc(2026, 10, 20, 9, 30)),
      now: now,
      observedZone: 'Europe/London',
    );
    await store.savePauseChange(commandId: 'resume', review: resumedReview);
    final restored = (await store.dailyRows(
      from: tomorrow,
      toExclusive: tomorrow.addDays(1),
      observedZone: 'Europe/London',
    )).rows.singleWhere((r) => r.expectation.identity == identity);
    expect(restored.expectation.versionId, 'v1');
    expect(restored.expectation.amount.enteredText, '1');
    expect(restored.expectation.instant, DateTime.utc(2026, 10, 20, 10));
  });

  test('partial finite count retains count but rejects planned use after exact cutoff', () async {
    final count = plan(timing: DailyCount(3, amount('1')));
    final old = await store.saveDailyPlan(
      commandId: 'count',
      plan: count,
      expectedPersonRevision: 1,
      expectedGeneration: store.generation,
    );
    await store.savePhasePlan(
      commandId: 'count-end',
      review: await preview(
        old,
        PhasePlan(
          phases: [count],
          end: PlanEnd(
            zoneId: 'Europe/London',
            exclusiveInstant: DateTime.utc(2026, 10, 19, 12),
          ),
        ),
      ),
    );
    final rows = await store.dailyRows(
      from: date,
      toExclusive: tomorrow,
      observedZone: 'Europe/London',
    );
    final row = rows.rows.single;
    expect(row.plannedCount, 3);
    await expectLater(
      store.actDaily(
        commandId: 'late-count',
        row: row,
        kind: DailyActionKind.taken,
        actualAt: DateTime.utc(2026, 10, 19, 13),
      ),
      throwsA(isA<CommandConflict>()),
    );
    expect(await store.records(), isEmpty);
    await store.record(
      commandId: 'truthful',
      itemId: item.id,
      amount: '1',
      actualAt: DateTime.utc(2026, 10, 19, 13),
    );
    expect(await store.records(), hasLength(1));
    expect((await store.capturedDailyRows()).rows, isEmpty);
  });
  test(
    'finite window end conflict is rejected before saving without an override',
    () async {
      final window = plan(
        timing: DailyWindows(
          windows: [
            DailyWindow(
              id: 'night',
              start: WallTime(23, 0),
              end: WallTime(1, 0),
              amount: amount('1'),
            ),
          ],
        ),
      );
      final old = await store.saveDailyPlan(
        commandId: 'window-bound',
        plan: window,
        expectedPersonRevision: 1,
        expectedGeneration: store.generation,
      );
      await expectLater(
        preview(
          old,
          PhasePlan(
            phases: [window],
            end: PlanEnd(
              zoneId: 'Europe/London',
              exclusiveInstant: DateTime.utc(2026, 10, 19, 23),
            ),
          ),
        ),
        throwsArgumentError,
      );
      expect(await store.phaseHistory(planId: 'p', personId: meId), isEmpty);
    },
  );
  test(
    'two independent connections race one phase revision atomically',
    () async {
      final old = await save();
      final review = await preview(
        old,
        PhasePlan(
          phases: [plan()],
          end: PlanEnd(
            zoneId: 'Europe/London',
            exclusiveInstant: DateTime.utc(2026, 10, 21),
          ),
        ),
      );
      final other = await RecordStore.open(
        path: '${dir.path}/records.db',
        key: key,
        isNew: false,
      );
      try {
        Future<Object> attempt(RecordStore target, String id) async {
          try {
            return await target.savePhasePlan(commandId: id, review: review);
          } catch (error) {
            return error;
          }
        }

        final results = await Future.wait([
          attempt(store, 'race-a'),
          attempt(other, 'race-b'),
        ]);
        expect(results.whereType<SavedDailyPlan>(), hasLength(1));
        expect(results.whereType<CommandConflict>(), hasLength(1));
        expect(
          await store.phaseHistory(planId: 'p', personId: meId),
          hasLength(1),
        );
        expect(await store.records(), isEmpty);
      } finally {
        await other.close();
      }
    },
  );
  test(
    'window end fold choice persists independently across midnight',
    () async {
      final window = plan(
        timing: DailyWindows(
          windows: [
            DailyWindow(
              id: 'night',
              start: WallTime(23, 0),
              end: WallTime(1, 30),
              amount: amount('1'),
            ),
          ],
        ),
      );
      await store.saveDailyPlan(
        commandId: 'window-fold',
        plan: window,
        expectedPersonRevision: 1,
        expectedGeneration: store.generation,
      );
      final day = CivilDate(2026, 10, 24);
      final before = (await store.dailyRows(
        from: day,
        toExclusive: day.addDays(1),
        observedZone: 'Europe/London',
      )).rows.single;
      final endpoint = before.expectation.windowEndpoints.singleWhere(
        (e) => e.identity.slotId == 'night:end',
      );
      expect(endpoint.resolution, DailyResolution.repeatedClock);
      await expectLater(
        store.chooseWindowClock(
          commandId: 'invalid-fold',
          row: before,
          endpoint: endpoint,
          decision: const ChooseClockInstance(99),
        ),
        throwsArgumentError,
      );
      await store.chooseWindowClock(
        commandId: 'end-fold',
        row: before,
        endpoint: endpoint,
        decision: const ChooseClockInstance(1),
      );
      final after = (await store.dailyRows(
        from: day,
        toExclusive: day.addDays(1),
        observedZone: 'Europe/London',
      )).rows.single;
      expect(after.expectation.windowEnd, DateTime.utc(2026, 10, 25, 1, 30));
      expect(after.expectation.instant, isNull);
      await store.close();
      store = await RecordStore.open(
        path: '${dir.path}/records.db',
        key: key,
        isNew: false,
      );
      expect(
        (await store.dailyRows(
          from: day,
          toExclusive: day.addDays(1),
          observedZone: 'Europe/London',
        )).rows.single.expectation.windowEnd,
        DateTime.utc(2026, 10, 25, 1, 30),
      );
    },
  );
  test('multi-opportunity count override rejects atomically and preserves full bucket progress', () async {
    final count = plan(timing: DailyCount(3, amount('1')));
    final old = await store.saveDailyPlan(
      commandId: 'count',
      plan: count,
      expectedPersonRevision: 1,
      expectedGeneration: store.generation,
    );
    final candidate = PhasePlan(
      phases: [count],
      overrides: [
        OccurrenceOverride(
          identity: DailyIdentity(
            personId: meId,
            planId: 'p',
            originalDate: date,
          ),
          versionId: 'v1',
          amount: amount('2'),
        ),
      ],
    );
    await expectLater(preview(old, candidate), throwsArgumentError);
    final review = PhaseChangeReview(
      plan: old,
      proposed: candidate,
      personRevision: 1,
      generation: store.generation,
      sourceGuard: '[]',
      now: now,
      observedZone: 'Europe/London',
    );
    await expectLater(
      store.savePhasePlan(commandId: 'invalid-count', review: review),
      throwsA(isA<CommandConflict>()),
    );
    expect(await store.phaseHistory(planId: 'p', personId: meId), isEmpty);
    expect(await store.phasePlan(planId: 'p', personId: meId), isNull);
    expect((await store.dailyPlans()).single.revision, 1);
    expect(await store.records(), isEmpty);
    final row = (await store.dailyRows(
      from: date,
      toExclusive: tomorrow,
      observedZone: 'Europe/London',
    )).rows.single;
    await store.actDaily(
      commandId: 'one-count',
      row: row,
      kind: DailyActionKind.taken,
      actualAt: now,
    );
    final after = (await store.dailyRows(
      from: date,
      toExclusive: tomorrow,
      observedZone: 'Europe/London',
    )).rows.single;
    expect(after.plannedCount, 3);
    expect(after.takenCount, 1);
    expect(after.expectation.amount.enteredText, '1');
  });
  test('single untimed opportunity accepts amount-only exception without inventing time', () async {
    final count = plan(timing: DailyCount(1, amount('1')));
    final old = await store.saveDailyPlan(
      commandId: 'one-count',
      plan: count,
      expectedPersonRevision: 1,
      expectedGeneration: store.generation,
    );
    final candidate = PhasePlan(
      phases: [count],
      overrides: [
        OccurrenceOverride(
          identity: DailyIdentity(
            personId: meId,
            planId: 'p',
            originalDate: date,
          ),
          versionId: 'v1',
          amount: amount('2'),
        ),
      ],
    );
    await store.savePhasePlan(
      commandId: 'one-amount',
      review: await preview(old, candidate),
    );
    final row = (await store.dailyRows(
      from: date,
      toExclusive: tomorrow,
      observedZone: 'Europe/London',
    )).rows.single;
    expect(row.plannedCount, 1);
    expect(row.expectation.instant, isNull);
    expect(row.expectation.originalAmount!.enteredText, '1');
    expect(row.expectation.amount.enteredText, '2');
    await store.actDaily(
      commandId: 'one-actual',
      row: row,
      kind: DailyActionKind.taken,
      actualAt: now,
    );
    expect((await store.records()).single.enteredAmount, '2');
  });
  test(
    'phase preview preserves missing actual anchor issue instead of no-next',
    () async {
      final interval = plan(
        timing: ElapsedInterval(
          segmentId: 'actual-segment',
          duration: ExactElapsed.parseHours('6'),
          mode: IntervalMode.qualifyingActual,
          amount: amount('1'),
        ),
      );
      final old = await store.saveDailyPlan(
        commandId: 'actual-plan',
        plan: interval,
        expectedPersonRevision: 1,
        expectedGeneration: store.generation,
      );
      final review = await preview(
        old,
        PhasePlan(
          phases: [interval],
          end: PlanEnd(
            zoneId: 'Europe/London',
            exclusiveInstant: DateTime.utc(2026, 10, 21),
          ),
        ),
      );
      expect(review.before, isNull);
      expect(review.after, isNull);
      expect(review.beforeIssue, DailyCalculationIssue.intervalNoAnchor);
      expect(review.afterIssue, DailyCalculationIssue.intervalNoAnchor);
      expect(await store.phaseHistory(planId: 'p', personId: meId), isEmpty);
      expect((await store.dailyPlans()).single.revision, 1);
      expect(await store.records(), isEmpty);
    },
  );
}
