import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:true_grit_vital/data/record_store.dart';

void main() {
  late Directory directory;
  late RecordStore store;
  final day = CivilDate(2026, 10, 23);
  final at = DateTime.utc(2026, 10, 23, 7);
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('vital-follow-up-');
    store = await RecordStore.open(
      path: '${directory.path}/test.db',
      key: List.generate(32, (i) => i + 1),
      isNew: true,
    );
  });
  tearDown(() async {
    await store.close();
    await directory.delete(recursive: true);
  });
  Future<void> setup({PlanTimingPolicy? policy, bool enabled = true}) async {
    final item = await store.createItem(
      commandId: 'item',
      name: 'Synthetic medicine',
      form: 'tablet',
      unit: 'count',
      type: 'Medicine',
    );
    await store.saveDailyPlan(
      commandId: 'plan',
      expectedPersonRevision: 1,
      expectedGeneration: store.generation,
      plan: DailyPlanVersion(
        personId: meId,
        planId: 'plan',
        itemId: item.id,
        versionId: 'v1',
        start: day,
        endExclusive: day.addDays(1),
        zoneBasis: FixedHome('UTC'),
        timingPolicy: policy,
        timing: DailySlots([
          DailySlot(
            id: 'am',
            time: WallTime(8, 0),
            reminderEnabled: true,
            amount: PlannedAmount(
              quantity: ExactQuantity.parse('1'),
              unit: 'count',
            ),
          ),
        ]),
      ),
    );
    await store.setPlanReminders(
      commandId: 'enabled',
      planId: 'plan',
      personId: meId,
      expectedPlanRevision: 1,
      expectedPersonRevision: 1,
      enabled: enabled,
    );
  }

  Future<ReminderProjection> prepare([DateTime? now]) => store.prepareReminders(
    now: now ?? at,
    observedZone: 'UTC',
    clockSample: ReminderClockSample(
      utcMilliseconds: (now ?? at).millisecondsSinceEpoch,
      elapsedMilliseconds: 1000000,
      bootId: 'boot',
    ),
    adapterFingerprint: 'test',
  );
  Future<DailyRow> row() async => (await store.dailyRows(
    from: day,
    toExclusive: day.addDays(1),
    observedZone: 'UTC',
  )).rows.single;

  test('default and timing labels alone do not add a follow-up', () async {
    await setup(policy: PlanTimingPolicy(allowanceMinutes: 15));
    expect((await prepare()).desired.map((r) => r.kind), [
      ReminderKind.ordinary,
    ]);
  });
  test(
    'one extra request is prepared ahead and keeps its exact token on repair',
    () async {
      await setup(policy: PlanTimingPolicy(followUpMinutes: 30));
      final first = await prepare();
      expect(first.desired.map((r) => r.kind).toSet(), {
        ReminderKind.ordinary,
        ReminderKind.followUp,
      });
      final follow = first.desired.singleWhere(
        (r) => r.kind == ReminderKind.followUp,
      );
      expect(follow.projectedUtc, DateTime.utc(2026, 10, 23, 8, 30));
      final next = await prepare();
      expect(
        next.desired
            .singleWhere((r) => r.kind == ReminderKind.followUp)
            .requestToken,
        follow.requestToken,
      );
      expect(await store.records(), isEmpty);
    },
  );
  for (final kind in [DailyActionKind.taken, DailyActionKind.skip]) {
    test('$kind cancels both requests without creating another use', () async {
      await setup(policy: PlanTimingPolicy(followUpMinutes: 30));
      await prepare();
      await store.actDaily(
        commandId: 'act',
        row: await row(),
        kind: kind,
        actualAt: kind == DailyActionKind.taken
            ? DateTime.utc(2026, 10, 23, 8)
            : null,
        reminderObservedZone: 'UTC',
      );
      expect((await prepare()).desired, isEmpty);
      expect(
        await store.records(),
        hasLength(kind == DailyActionKind.taken ? 1 : 0),
      );
    });
  }
  test('explicit snooze replaces the original and follow-up', () async {
    await setup(policy: PlanTimingPolicy(followUpMinutes: 30));
    await prepare();
    final target = await store.reminderTarget(await row(), observedZone: 'UTC');
    await store.snoozeReminder(
      SnoozeCommand(
        commandId: 'snooze',
        target: target,
        delayMinutes: 10,
        observedZone: 'UTC',
        sample: ReminderClockSample(
          utcMilliseconds: at.millisecondsSinceEpoch,
          elapsedMilliseconds: 1000000,
          bootId: 'boot',
        ),
      ),
      currentObservedZone: 'UTC',
    );
    expect((await prepare()).desired.map((r) => r.kind), [ReminderKind.snooze]);
  });
  test('disabling reminders cancels the prepared follow-up', () async {
    await setup(policy: PlanTimingPolicy(followUpMinutes: 30));
    await prepare();
    await store.setPlanReminders(
      commandId: 'disabled',
      planId: 'plan',
      personId: meId,
      expectedPlanRevision: 1,
      expectedPersonRevision: 1,
      enabled: false,
    );
    expect((await prepare()).desired, isEmpty);
  });
  test(
    'a fresh repair after planned time prepares only the future nudge',
    () async {
      await setup(policy: PlanTimingPolicy(followUpMinutes: 30));
      expect(
        (await prepare(DateTime.utc(2026, 10, 23, 8, 15))).desired
            .map((r) => r.kind),
        [ReminderKind.followUp],
      );
      expect(
        (await prepare(DateTime.utc(2026, 10, 23, 8, 31))).desired,
        isEmpty,
      );
    },
  );
  test('a confirmed follow-up cannot re-arm after it is consumed', () async {
    await setup(policy: PlanTimingPolicy(followUpMinutes: 30));
    final projection = await prepare();
    final follow = projection.desired.singleWhere(
      (r) => r.kind == ReminderKind.followUp,
    );
    expect(
      await store.acknowledgeReminder(
        generation: store.generation,
        requestToken: follow.requestToken,
        intentRevision: follow.intentRevision,
        sequence: projection.sequence,
        receipt: ReminderReceipt.consumed,
        adapterFingerprint: 'test',
      ),
      isTrue,
    );
    expect(
      (await prepare()).desired.where((r) => r.kind == ReminderKind.followUp),
      isEmpty,
    );
  });
  for (final receipt in [
    ReminderReceipt.consumed,
    ReminderReceipt.postUncertain,
  ]) {
    test(
      '$receipt survives disabling, cancellation acknowledgement and re-enabling',
      () async {
        await setup(policy: PlanTimingPolicy(followUpMinutes: 30));
        final initial = await prepare();
        final follow = initial.desired.singleWhere(
          (r) => r.kind == ReminderKind.followUp,
        );
        expect(
          await store.acknowledgeReminder(
            generation: store.generation,
            requestToken: follow.requestToken,
            intentRevision: follow.intentRevision,
            sequence: initial.sequence,
            receipt: receipt,
            adapterFingerprint: 'test',
          ),
          isTrue,
        );
        await store.setPlanReminders(
          commandId: 'off',
          planId: 'plan',
          personId: meId,
          expectedPlanRevision: 1,
          expectedPersonRevision: 1,
          enabled: false,
        );
        final cancelled = await prepare();
        expect(cancelled.obsoleteTokens, contains(follow.requestToken));
        expect(
          await store.acknowledgeObsoleteReminder(
            generation: store.generation,
            requestToken: follow.requestToken,
            sequence: cancelled.sequence,
            receipt: ReminderReceipt.cancelled,
            adapterFingerprint: 'test',
          ),
          isTrue,
        );
        await store.setPlanReminders(
          commandId: 'on',
          planId: 'plan',
          personId: meId,
          expectedPlanRevision: 1,
          expectedPersonRevision: 1,
          enabled: true,
        );
        expect(
          (await prepare()).desired.where(
            (r) => r.kind == ReminderKind.followUp,
          ),
          isEmpty,
        );
      },
    );
  }
  test('a late native posted receipt during cancellation prevents another follow-up', () async {
    await setup(policy: PlanTimingPolicy(followUpMinutes: 30));
    final initial = await prepare();
    final follow = initial.desired.singleWhere(
      (r) => r.kind == ReminderKind.followUp,
    );
    await store.setPlanReminders(
      commandId: 'off',
      planId: 'plan',
      personId: meId,
      expectedPlanRevision: 1,
      expectedPersonRevision: 1,
      enabled: false,
    );
    final cancelled = await prepare();
    expect(
      await store.acknowledgeObsoleteReminder(
        generation: store.generation,
        requestToken: follow.requestToken,
        sequence: cancelled.sequence,
        receipt: ReminderReceipt.postUncertain,
        adapterFingerprint: 'test',
      ),
      isTrue,
    );
    await store.setPlanReminders(
      commandId: 'on',
      planId: 'plan',
      personId: meId,
      expectedPlanRevision: 1,
      expectedPersonRevision: 1,
      enabled: true,
    );
    expect(
      (await prepare()).desired.where((r) => r.kind == ReminderKind.followUp),
      isEmpty,
    );
  });
  test('historical timing uses the captured version after editing and encrypted restart', () async {
    await setup(policy: PlanTimingPolicy(allowanceMinutes: 15));
    final original = await row();
    await store.actDaily(
      commandId: 'taken',
      row: original,
      kind: DailyActionKind.taken,
      actualAt: DateTime.utc(2026, 10, 23, 8, 10),
      reminderObservedZone: 'UTC',
    );
    final previous = (await store.dailyPlans(
      itemId: original.expectation.itemId,
    )).single;
    await store.saveDailyPlan(
      commandId: 'new-policy',
      expectedPersonRevision: 1,
      expectedGeneration: store.generation,
      expectedPlanRevision: previous.revision,
      plan: DailyPlanVersion(
        personId: meId,
        planId: 'plan',
        itemId: previous.plan.itemId,
        versionId: 'v2',
        start: day.addDays(1),
        zoneBasis: previous.plan.zoneBasis,
        timing: previous.plan.timing,
        timingPolicy: PlanTimingPolicy(allowanceMinutes: 0),
      ),
    );
    await store.close();
    store = await RecordStore.open(
      path: '${directory.path}/test.db',
      key: List.generate(32, (i) => i + 1),
      isNew: false,
    );
    final page = await store.timeline(
      TimelineQuery(filter: TimelineFilter(), displayZone: 'UTC'),
    );
    final entry = page.entries.whereType<RecordTimelineEntry>().single;
    final captured = entry.planContext!.expectation;
    expect(captured.timingPolicy!.allowanceMinutes, 15);
    expect(
      doseTimingLabel(
        policy: captured.timingPolicy,
        planned: captured.instant,
        actual: entry.record.actualAt,
      ),
      DoseTimingLabel.withinWindow,
    );
    expect(
      (await store.dailyPlans(itemId: original.expectation.itemId))
          .single
          .plan
          .timingPolicy!
          .allowanceMinutes,
      0,
    );
  });
}
