import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:true_grit_vital/data/record_store.dart';

void main() {
  late Directory dir;
  late RecordStore store;
  late String path;
  late SubstanceItem item;
  final key = List.generate(32, (i) => i + 1);
  final now = DateTime.utc(2026, 10, 19, 10);
  final date = CivilDate(2026, 10, 19);
  PlannedAmount amount() => PlannedAmount(
    quantity: ExactQuantity.parse('1.000'),
    enteredText: '1.000',
    unit: 'mg',
  );
  DailyPlanVersion plan({
    IntervalMode mode = IntervalMode.qualifyingActual,
    bool reminders = true,
  }) => DailyPlanVersion(
    personId: meId,
    planId: 'interval',
    itemId: item.id,
    versionId: 'iv1',
    start: date,
    zoneBasis: FixedHome('Europe/London'),
    timing: ElapsedInterval(
      segmentId: 'segment',
      duration: ExactElapsed.parseHours('6'),
      mode: mode,
      amount: amount(),
      plannedAnchor: mode == IntervalMode.fixedPlanned
          ? DateTime.utc(2026, 10, 19)
          : null,
      reminderEnabled: reminders,
    ),
  );
  Future<SavedDailyPlan> save({
    IntervalMode mode = IntervalMode.qualifyingActual,
  }) => store.saveDailyPlan(
    commandId: 'plan',
    plan: plan(mode: mode),
    expectedPersonRevision: 1,
    expectedGeneration: store.generation,
    intervalClockSample: ReminderClockSample(
      bootId: 'boot',
      utcMilliseconds: now.millisecondsSinceEpoch,
      elapsedMilliseconds: 1000,
    ),
  );
  Future<UseRecord> actual(String id, int hour) => store.record(
    commandId: id,
    itemId: item.id,
    amount: '1.000',
    actualAt: DateTime.utc(2026, 10, 19, hour),
  );
  Future<IntervalChangeReview> preview(
    SavedDailyPlan p,
    UseRecord a, {
    DateTime? time,
    bool? qualifies,
    bool voided = false,
  }) => store.previewIntervalChange(
    plan: p,
    recordId: a.id,
    expectedRecordRevision: a.revision,
    actualAt: time,
    qualifies: qualifies,
    voided: voided,
    now: now,
    observedZone: 'Europe/London',
    intervalClockSample: ReminderClockSample(
      bootId: 'boot',
      utcMilliseconds: now.millisecondsSinceEpoch,
      elapsedMilliseconds: 1000,
    ),
  );
  Future<void> qualify(
    SavedDailyPlan p,
    UseRecord a, {
    String command = 'qualify',
  }) async => store.qualifyInterval(
    commandId: command,
    review: await preview(p, a, qualifies: true),
  );
  Future<DailyRows> rows() => store.dailyRows(
    from: date,
    toExclusive: date.addDays(1),
    observedZone: 'Europe/London',
  );
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('vital-interval-');
    path = '${dir.path}/records.db';
    store = await RecordStore.open(path: path, key: key, isNew: true);
    item = await store.createItem(
      commandId: 'item',
      name: 'Synthetic interval',
      form: 'tablet',
      unit: 'mg',
      type: 'medicine',
    );
  });
  tearDown(() async {
    await store.close();
    await dir.delete(recursive: true);
  });
  test('explicit qualification, exact preview, restart and current native source agree', () async {
    final p = await save();
    expect((await rows()).rows, isEmpty);
    final a = await actual('actual', 6);
    expect((await rows()).rows, isEmpty);
    final review = await preview(p, a, qualifies: true);
    expect(review.before, isNull);
    expect(review.after!.instant, DateTime.utc(2026, 10, 19, 12));
    await store.qualifyInterval(commandId: 'qualify', review: review);
    final row = (await rows()).rows.single;
    expect(row.expectation.identity.sourceActualId, a.id);
    expect(row.expectation.amount.enteredText, '1.000');
    expect(
      (await store.nextDailyPlans(
        now: now,
        observedZone: 'Europe/London',
      )).rows.single.result.next!.instant,
      review.after!.instant,
    );
    await store.setPlanReminders(
      commandId: 'reminders',
      planId: 'interval',
      personId: meId,
      expectedPlanRevision: 1,
      expectedPersonRevision: 1,
      enabled: true,
    );
    final projection = await store.prepareReminders(
      now: now,
      observedZone: 'Europe/London',
      clockSample: ReminderClockSample(
        bootId: 'boot',
        utcMilliseconds: now.millisecondsSinceEpoch,
        elapsedMilliseconds: 1000,
      ),
      adapterFingerprint: 'test',
    );
    final desired = projection.desired.single;
    expect(desired.trigger, ReminderTrigger.elapsed);
    expect(desired.projectedUtc, review.after!.instant);
    expect(desired.deadlineMilliseconds, 7201000);
    await store.close();
    store = await RecordStore.open(path: path, key: key, isNew: false);
    expect(
      (await rows()).rows.single.expectation.identity,
      row.expectation.identity,
    );
    expect(
      (await store.intervalSources(
        planId: 'interval',
        personId: meId,
      )).single.revision,
      1,
    );
    expect(
      String.fromCharCodes(await File(path).readAsBytes()),
      isNot(contains('Synthetic interval')),
    );
  });
  test('winner correction and void require reviewed source revisions and cancel native requests atomically', () async {
    final p = await save();
    final a = await actual('actual', 6);
    await qualify(p, a);
    await store.setPlanReminders(
      commandId: 'reminders',
      planId: 'interval',
      personId: meId,
      expectedPlanRevision: 1,
      expectedPersonRevision: 1,
      enabled: true,
    );
    final projection = await store.prepareReminders(
      now: now,
      observedZone: 'Europe/London',
      clockSample: ReminderClockSample(
        bootId: 'boot',
        utcMilliseconds: now.millisecondsSinceEpoch,
        elapsedMilliseconds: 1000,
      ),
      adapterFingerprint: 'test',
    );
    final old = projection.desired.single;
    await expectLater(
      store.correct(
        commandId: 'without-review',
        recordId: a.id,
        expectedRevision: 1,
        amount: null,
        actualAt: DateTime.utc(2026, 10, 19, 5),
      ),
      throwsA(isA<CommandConflict>()),
    );
    final reviews = await store.previewIntervalChanges(
      recordId: a.id,
      expectedRevision: 1,
      actualAt: DateTime.utc(2026, 10, 19, 5),
      now: now,
      observedZone: 'Europe/London',
    );
    expect(reviews.single.before!.instant, DateTime.utc(2026, 10, 19, 12));
    expect(reviews.single.after!.instant, DateTime.utc(2026, 10, 19, 11));
    final changed = await store.correct(
      commandId: 'correct',
      recordId: a.id,
      expectedRevision: 1,
      amount: null,
      actualAt: DateTime.utc(2026, 10, 19, 5),
      intervalReviews: reviews,
    );
    expect(
      (await rows()).rows.single.expectation.instant,
      DateTime.utc(2026, 10, 19, 11),
    );
    await expectLater(
      store.snoozeReminder(
        SnoozeCommand(
          commandId: 'stale',
          target: old.target,
          delayMinutes: 5,
          sample: ReminderClockSample(
            bootId: 'boot',
            utcMilliseconds: now.millisecondsSinceEpoch,
            elapsedMilliseconds: 1000,
          ),
          observedZone: 'Europe/London',
        ),
        currentObservedZone: 'Europe/London',
      ),
      throwsA(isA<CommandConflict>()),
    );
    final next = await store.prepareReminders(
      now: now,
      observedZone: 'Europe/London',
      clockSample: ReminderClockSample(
        bootId: 'boot',
        utcMilliseconds: now.millisecondsSinceEpoch,
        elapsedMilliseconds: 1000,
      ),
      adapterFingerprint: 'test',
    );
    expect(next.obsoleteTokens, contains(old.requestToken));
    expect(
      await store.acknowledgeReminder(
        generation: store.generation,
        requestToken: old.requestToken,
        intentRevision: old.intentRevision,
        sequence: next.sequence,
        receipt: ReminderReceipt.accepted,
        adapterFingerprint: 'test',
      ),
      false,
    );
    final voidReviews = await store.previewIntervalChanges(
      recordId: a.id,
      expectedRevision: changed.revision,
      voided: true,
      now: now,
      observedZone: 'Europe/London',
    );
    expect(voidReviews.single.after, isNull);
    await store.voidRecord(
      commandId: 'void',
      recordId: a.id,
      expectedRevision: 2,
      intervalReviews: voidReviews,
    );
    expect((await rows()).rows, isEmpty);
    final replay = await store.correct(
      commandId: 'correct',
      recordId: a.id,
      expectedRevision: 1,
      amount: null,
      actualAt: DateTime.utc(2026, 10, 19, 5),
      intervalReviews: reviews,
    );
    expect(replay.alreadyCommitted, true);
    expect(replay.revision, 2);
  });
  test('older backfill leaves winner, future qualification rejects and competing reviews have one winner', () async {
    final p = await save();
    final a = await actual('new', 6);
    await qualify(p, a);
    final b = await actual('old', 4);
    final review = await preview(p, b, qualifies: true);
    expect(review.before!.instant, review.after!.instant);
    await store.qualifyInterval(commandId: 'backfill', review: review);
    final future = await actual('future', 20);
    await expectLater(preview(p, future, qualifies: true), throwsArgumentError);
    final first = await preview(p, a, qualifies: false);
    final second = await preview(p, b, qualifies: false);
    await store.qualifyInterval(commandId: 'first', review: first);
    await expectLater(
      store.qualifyInterval(commandId: 'second', review: second),
      throwsA(isA<CommandConflict>()),
    );
    expect(
      (await rows()).rows.single.expectation.instant,
      DateTime.utc(2026, 10, 19, 10),
    );
  });
  test('Taken qualifies once, captured history survives source revision and exact replay', () async {
    final p = await save();
    final a = await actual('anchor', 4);
    await qualify(p, a);
    final row = (await rows()).rows.single;
    final taken = await store.actDaily(
      commandId: 'taken',
      row: row,
      kind: DailyActionKind.taken,
      actualAt: DateTime.utc(2026, 10, 19, 9),
    );
    expect(
      (await rows()).rows.single.expectation.instant,
      DateTime.utc(2026, 10, 19, 15),
    );
    expect(
      (await store.capturedDailyRows()).rows.single.expectation.instant,
      DateTime.utc(2026, 10, 19, 10),
    );
    final retry = await store.actDaily(
      commandId: 'taken',
      row: row,
      kind: DailyActionKind.taken,
      actualAt: DateTime.utc(2026, 10, 19, 9),
    );
    expect(retry.alreadyCommitted, true);
    expect(retry.recordId, taken.recordId);
    expect((await store.records()).length, 2);
    final current = (await store.capturedDailyRows()).rows.single;
    final review = await store.previewIntervalChanges(
      recordId: taken.recordId!,
      expectedRevision: 1,
      voided: true,
      now: now,
      observedZone: 'Europe/London',
    );
    await store.undoDaily(
      commandId: 'undo',
      row: current,
      action: current.actions.single,
      intervalReviews: review,
    );
    expect(
      (await rows()).rows.single.expectation.instant,
      DateTime.utc(2026, 10, 19, 10),
    );
  });
  test('same-instant ties are deterministic and independent connections cannot commit stale reviews', () async {
    final p = await save();
    final a = await actual('one', 6), b = await actual('two', 6);
    await qualify(p, a);
    await qualify(p, b, command: 'second');
    final winning = [a.id, b.id]..sort();
    expect(
      (await rows()).rows.single.expectation.identity.sourceActualId,
      winning.first,
    );
    final r1 = await preview(p, a, qualifies: false),
        r2 = await preview(p, b, qualifies: false);
    final other = await RecordStore.open(path: path, key: key, isNew: false);
    try {
      final results = await Future.wait([
        store
            .qualifyInterval(commandId: 'race-one', review: r1)
            .then((_) => true, onError: (Object _) => false),
        other
            .qualifyInterval(commandId: 'race-two', review: r2)
            .then((_) => true, onError: (Object _) => false),
      ]);
      expect(results.where((v) => v), hasLength(1));
    } finally {
      await other.close();
    }
  });
  test('interval product Taken retains vector and exactly one physical outflow on replay', () async {
    final product = await store.createItem(
      commandId: 'product',
      name: 'Synthetic mixed product',
      form: 'liquid',
      unit: 'ml',
      type: 'medicine',
      productComponents: [
        ProductComponent(ingredientId: 'a', name: 'A', concentrationText: '3'),
        ProductComponent(ingredientId: 'b', name: 'B', concentrationText: '7'),
      ],
    );
    final label = (await store.productLabel(
      personId: meId,
      itemId: product.id,
    ))!;
    final container = await store.createStockContainer(
      commandId: 'container',
      personId: meId,
      expectedPersonRevision: 1,
      expectedGeneration: store.generation,
      itemId: product.id,
      label: 'Synthetic bottle',
      unit: 'ml',
      strength: LabelledStrength(ingredientId: product.id, label: 'Volume'),
      productLabel: label,
      opening: ExactAmount(BigInt.one),
    );
    final p = DailyPlanVersion(
      personId: meId,
      planId: 'interval',
      itemId: product.id,
      versionId: 'iv1',
      start: date,
      zoneBasis: FixedHome('Europe/London'),
      timing: ElapsedInterval(
        segmentId: 'segment',
        duration: ExactElapsed.parseHours('6'),
        mode: IntervalMode.qualifyingActual,
        amount: PlannedAmount(
          quantity: ExactQuantity.parse('0.5'),
          enteredText: '0.5',
          unit: 'ml',
        ),
      ),
    );
    final saved = await store.saveDailyPlan(
      commandId: 'plan',
      plan: p,
      expectedPersonRevision: 1,
      expectedGeneration: store.generation,
    );
    final anchor = await store.recordProduct(
      commandId: 'product-anchor',
      personId: meId,
      expectedPersonRevision: 1,
      itemId: product.id,
      actualAt: DateTime.utc(2026, 10, 19, 4),
      use: ProductUseInput(
        expectedGeneration: store.generation,
        label: label,
        enteredVolume: EnteredStockAmount('0.5', 'ml'),
      ),
    );
    await qualify(saved, anchor);
    final row = (await rows()).rows.single;
    final input = ProductUseInput(
      expectedGeneration: store.generation,
      label: label,
      enteredVolume: EnteredStockAmount('0.5', 'ml'),
      containerId: container.id,
      expectedContainerRevision: container.revision,
      sourceLabel: label,
    );
    await expectLater(
      store.actDaily(
        commandId: 'product-earlier',
        row: row,
        kind: DailyActionKind.taken,
        actualAt: DateTime.utc(2026, 10, 19, 3),
        productUse: input,
      ),
      throwsA(
        isA<CommandConflict>().having(
          (e) => e.code,
          'code',
          'interval_actual_review',
        ),
      ),
    );
    expect((await store.records()), hasLength(1));
    expect(
      (await store.intervalSources(planId: 'interval', personId: meId)),
      hasLength(1),
    );
    expect(
      (await store.stockMovements(personId: meId, containerId: container.id)),
      hasLength(1),
    );
    expect((await store.capturedDailyRows()).rows, isEmpty);
    final first = await store.actDaily(
      commandId: 'product-taken',
      row: row,
      kind: DailyActionKind.taken,
      actualAt: DateTime.utc(2026, 10, 19, 9),
      productUse: input,
    );
    final retry = await store.actDaily(
      commandId: 'product-taken',
      row: row,
      kind: DailyActionKind.taken,
      actualAt: DateTime.utc(2026, 10, 19, 9),
      productUse: input,
    );
    expect(retry.alreadyCommitted, true);
    expect(retry.recordId, first.recordId);
    final record = (await store.recordById(first.recordId!))!;
    expect(record.product!.components.map((c) => c.amount.toString()), [
      '3/2',
      '7/2',
    ]);
    expect(
      (await store.stockMovements(
        personId: meId,
        containerId: container.id,
      )).where((m) => m.kind == StockMovementKind.actualUse),
      hasLength(1),
    );
    expect(
      (await rows()).rows.single.expectation.instant,
      DateTime.utc(2026, 10, 19, 15),
    );
  });
  test('older Taken needs review before writes and explicit standalone backfill retains next', () async {
    final p = await save();
    final a = await actual('winning', 6);
    await qualify(p, a);
    final original = (await rows()).rows.single;
    await expectLater(
      store.actDaily(
        commandId: 'older-taken',
        row: original,
        kind: DailyActionKind.taken,
        actualAt: DateTime.utc(2026, 10, 19, 4),
        intervalClockSample: ReminderClockSample(
          bootId: 'boot',
          utcMilliseconds: now.millisecondsSinceEpoch,
          elapsedMilliseconds: 1000,
        ),
      ),
      throwsA(
        isA<CommandConflict>().having(
          (e) => e.code,
          'code',
          'interval_actual_review',
        ),
      ),
    );
    expect((await store.records()), hasLength(1));
    expect(
      (await store.intervalSources(planId: 'interval', personId: meId)),
      hasLength(1),
    );
    expect((await store.capturedDailyRows()).rows, isEmpty);
    final backfill = await actual('explicit-earlier', 4);
    final review = await preview(p, backfill, qualifies: true);
    expect(review.before!.identity, review.after!.identity);
    await store.qualifyInterval(commandId: 'explicit-qualify', review: review);
    final next = (await store.nextDailyPlans(
      now: now,
      observedZone: 'Europe/London',
    )).rows.single.result.next!;
    expect(next.identity, original.expectation.identity);
    expect(next.instant, original.expectation.instant);
    expect((await rows()).rows.single.isResolved, false);
  });
  test('same-boot clock changes retain elapsed native deadline and reboot needs repair', () async {
    await save(mode: IntervalMode.fixedPlanned);
    await store.setPlanReminders(
      commandId: 'reminders',
      planId: 'interval',
      personId: meId,
      expectedPlanRevision: 1,
      expectedPersonRevision: 1,
      enabled: true,
    );
    Future<ReminderProjection> projection(
      DateTime wall,
      String boot,
      int elapsed,
    ) => store.prepareReminders(
      now: wall,
      observedZone: 'Europe/London',
      clockSample: ReminderClockSample(
        bootId: boot,
        utcMilliseconds: wall.millisecondsSinceEpoch,
        elapsedMilliseconds: elapsed,
      ),
      adapterFingerprint: 'test',
    );
    final first = await projection(now, 'boot', 1000);
    final request = first.desired.first;
    final backward = await projection(
      now.subtract(const Duration(hours: 1)),
      'boot',
      2000,
    );
    final retained = backward.desired.singleWhere(
      (x) => x.requestToken == request.requestToken,
    );
    expect(retained.deadlineMilliseconds, request.deadlineMilliseconds);
    final forward = await projection(
      now.add(const Duration(hours: 20)),
      'boot',
      3000,
    );
    expect(
      forward.desired
          .singleWhere((x) => x.requestToken == request.requestToken)
          .deadlineMilliseconds,
      request.deadlineMilliseconds,
    );
    expect(
      forward.desired.map((r) => r.target.row.expectation.identity).toSet(),
      first.desired.map((r) => r.target.row.expectation.identity).toSet(),
    );
    for (final r in forward.desired) {
      expect(
        r.deadlineMilliseconds,
        1000 +
            r.projectedUtc.millisecondsSinceEpoch -
            now.millisecondsSinceEpoch,
      );
    }
    final reboot = await projection(now, 'new-boot', 10);
    expect(
      reboot.attention.any(
        (r) =>
            r.requestToken == request.requestToken &&
            r.repairState == ReminderRepairState.interrupted,
      ),
      true,
    );
  });
  test('delayed first reconciliation uses reviewed basis and missing basis needs explicit recovery', () async {
    final p = await save(mode: IntervalMode.fixedPlanned);
    await store.setPlanReminders(
      commandId: 'reminders',
      planId: 'interval',
      personId: meId,
      expectedPlanRevision: 1,
      expectedPersonRevision: 1,
      enabled: true,
    );
    final jumped = now.add(const Duration(hours: 20));
    final projection = await store.prepareReminders(
      now: jumped,
      observedZone: 'Europe/London',
      clockSample: ReminderClockSample(
        bootId: 'boot',
        utcMilliseconds: jumped.millisecondsSinceEpoch,
        elapsedMilliseconds: 2000,
      ),
      adapterFingerprint: 'test',
    );
    expect(
      projection.desired.first.projectedUtc,
      DateTime.utc(2026, 10, 19, 12),
    );
    expect(projection.desired.first.deadlineMilliseconds, 7201000);
    final reboot = await store.prepareReminders(
      now: now,
      observedZone: 'Europe/London',
      clockSample: ReminderClockSample(
        bootId: 'new-boot',
        utcMilliseconds: now.millisecondsSinceEpoch,
        elapsedMilliseconds: 10,
      ),
      adapterFingerprint: 'test',
    );
    expect(
      reboot.exclusions.any((e) => e.reason == 'elapsed_clock_recovery'),
      true,
    );
    final review = await store.previewIntervalClockRecovery(
      plan: p,
      sample: ReminderClockSample(
        bootId: 'new-boot',
        utcMilliseconds: now.millisecondsSinceEpoch,
        elapsedMilliseconds: 10,
      ),
      reviewedFrom: date,
      observedZone: 'Europe/London',
    );
    expect(review.next!.instant, DateTime.utc(2026, 10, 19, 12));
    await store.resetIntervalClock(commandId: 'reset', review: review);
    await store.resetIntervalClock(commandId: 'reset', review: review);
    final recovered = await store.prepareReminders(
      now: now,
      observedZone: 'Europe/London',
      clockSample: review.sample,
      adapterFingerprint: 'test',
    );
    expect(
      recovered.exclusions.any((e) => e.reason == 'elapsed_clock_recovery'),
      false,
    );
    expect(recovered.desired.first.deadlineMilliseconds, 7200010);
  });
  test('closed prior-boot segment stops blocking after reviewed recovery cutoff without rearming history', () async {
    final oldStart = date.addDays(-1);
    final oldPlan = DailyPlanVersion(
      personId: meId,
      planId: 'interval',
      itemId: item.id,
      versionId: 'old',
      start: oldStart,
      zoneBasis: FixedHome('Europe/London'),
      timing: ElapsedInterval(
        segmentId: 'old-segment',
        duration: ExactElapsed.parseHours('6'),
        mode: IntervalMode.fixedPlanned,
        amount: amount(),
        plannedAnchor: DateTime.utc(2026, 10, 18),
        reminderEnabled: true,
      ),
    );
    await store.saveDailyPlan(
      commandId: 'old',
      plan: oldPlan,
      expectedPersonRevision: 1,
      expectedGeneration: store.generation,
      intervalClockSample: ReminderClockSample(
        bootId: 'old-boot',
        utcMilliseconds: DateTime.utc(2026, 10, 18, 10).millisecondsSinceEpoch,
        elapsedMilliseconds: 1000,
      ),
    );
    await store.setPlanReminders(
      commandId: 'enable-old',
      planId: 'interval',
      personId: meId,
      expectedPlanRevision: 1,
      expectedPersonRevision: 1,
      enabled: true,
    );
    final oldProjection = await store.prepareReminders(
      now: DateTime.utc(2026, 10, 18, 10),
      observedZone: 'Europe/London',
      clockSample: ReminderClockSample(
        bootId: 'old-boot',
        utcMilliseconds: DateTime.utc(2026, 10, 18, 10).millisecondsSinceEpoch,
        elapsedMilliseconds: 1000,
      ),
      adapterFingerprint: 'test',
    );
    final current = await store.saveDailyPlan(
      commandId: 'new',
      plan: plan(mode: IntervalMode.fixedPlanned),
      expectedPersonRevision: 1,
      expectedGeneration: store.generation,
      expectedPlanRevision: 1,
      intervalClockSample: ReminderClockSample(
        bootId: 'boot',
        utcMilliseconds: now.millisecondsSinceEpoch,
        elapsedMilliseconds: 1000,
      ),
    );
    final before = await store.prepareReminders(
      now: now,
      observedZone: 'Europe/London',
      clockSample: ReminderClockSample(
        bootId: 'boot',
        utcMilliseconds: now.millisecondsSinceEpoch,
        elapsedMilliseconds: 1000,
      ),
      adapterFingerprint: 'test',
    );
    expect(
      before.exclusions.any((e) => e.reason == 'elapsed_clock_recovery'),
      true,
    );
    final review = await store.previewIntervalClockRecovery(
      plan: current,
      sample: ReminderClockSample(
        bootId: 'boot',
        utcMilliseconds: now.millisecondsSinceEpoch,
        elapsedMilliseconds: 1000,
      ),
      reviewedFrom: date,
      observedZone: 'Europe/London',
    );
    await store.resetIntervalClock(commandId: 'reset', review: review);
    final after = await store.prepareReminders(
      now: now,
      observedZone: 'Europe/London',
      clockSample: review.sample,
      adapterFingerprint: 'test',
    );
    expect(
      after.exclusions.any((e) => e.reason == 'elapsed_clock_recovery'),
      false,
    );
    expect(
      after.desired.every(
        (r) => r.target.row.expectation.identity.intervalSegmentId == 'segment',
      ),
      true,
    );
    expect(after.desired.every((r) => r.projectedUtc.isAfter(now)), true);
    expect(
      after.obsoleteTokens,
      contains(oldProjection.desired.first.requestToken),
    );
  });
  test('uncaptured native basis remains repairable rather than guessing a first reconciliation clock', () async {
    final p = await store.saveDailyPlan(
      commandId: 'plan',
      plan: plan(mode: IntervalMode.fixedPlanned, reminders: false),
      expectedPersonRevision: 1,
      expectedGeneration: store.generation,
    );
    await store.setPlanReminders(
      commandId: 'enable',
      planId: 'interval',
      personId: meId,
      expectedPlanRevision: 1,
      expectedPersonRevision: 1,
      enabled: true,
    );
    final sample = ReminderClockSample(
      bootId: 'boot',
      utcMilliseconds: now.millisecondsSinceEpoch,
      elapsedMilliseconds: 1000,
    );
    final before = await store.prepareReminders(
      now: now,
      observedZone: 'Europe/London',
      clockSample: sample,
      adapterFingerprint: 'test',
    );
    expect(before.desired, isEmpty);
    expect(
      before.exclusions.any((e) => e.reason == 'elapsed_clock_recovery'),
      true,
    );
    final review = await store.previewIntervalClockRecovery(
      plan: p,
      sample: sample,
      reviewedFrom: date,
      observedZone: 'Europe/London',
    );
    await store.resetIntervalClock(commandId: 'reset', review: review);
    expect(
      (await store.prepareReminders(
        now: now,
        observedZone: 'Europe/London',
        clockSample: sample,
        adapterFingerprint: 'test',
      )).desired,
      isNotEmpty,
    );
  });
  test('actual overdue persists on Today after its original date without inventing further use', () async {
    final p = await save();
    final a = await actual('actual', 4);
    await qualify(p, a);
    final tomorrow = await store.todayDailyRows(
      now: DateTime.utc(2026, 10, 20, 10),
      observedZone: 'Europe/London',
    );
    expect(
      tomorrow.rows.single.expectation.instant,
      DateTime.utc(2026, 10, 19, 10),
    );
    expect((await store.records()), hasLength(1));
  });
  test('frozen populated schema10 preserves products, calendar, drafts and cancellation through encrypted migration', () async {
    await store.close();
    await File(path).delete();
    final raw = sqlite3.open(path);
    raw.execute("PRAGMA cipher='chacha20'");
    raw.execute(
      'PRAGMA key="x\'${key.map((x) => x.toRadixString(16).padLeft(2, '0')).join()}\'"',
    );
    raw.execute(
      File('test/data/fixtures/record_store_v10.sql').readAsStringSync(),
    );
    raw.close();
    store = await RecordStore.open(path: path, key: key, isNew: false);
    expect(
      (await store.productLabel(
        personId: 'other',
        itemId: 'other-item',
      ))!.components,
      hasLength(2),
    );
    expect(
      (await store.recordById(
        'product-fixture',
        personId: 'other',
      ))!.product!.components.map((c) => c.amount.toString()),
      ['1/1', '3/2'],
    );
    expect(
      (await store.dailyPlans(scope: const FeedScope.everyone()))
          .any((p) => p.plan.calendar is SelectedWeekdays),
      true,
    );
    expect(await store.drafts(), isNotEmpty);
    expect((await store.history('record')), hasLength(2));
    final p = await store.prepareReminders(
      now: now,
      observedZone: 'Europe/London',
      clockSample: null,
      adapterFingerprint: 'test',
    );
    expect(p.obsoleteTokens, contains('frozen-cancelled'));
    await store.close();
    store = await RecordStore.open(path: path, key: key, isNew: false);
    expect(
      (await store.productLabel(
        personId: 'other',
        itemId: 'other-item',
      ))!.revision,
      1,
    );
  });
  test('failed schema10 migration rolls back original recovery state', () async {
    final failed = '${dir.path}/failed.db';
    final raw = sqlite3.open(failed);
    raw.execute("PRAGMA cipher='chacha20'");
    raw.execute(
      'PRAGMA key="x\'${key.map((x) => x.toRadixString(16).padLeft(2, '0')).join()}\'"',
    );
    raw.execute(
      File('test/data/fixtures/record_store_v10.sql').readAsStringSync(),
    );
    raw.execute('CREATE TABLE interval_qualification(recovery TEXT)');
    raw.close();
    await expectLater(
      RecordStore.open(path: failed, key: key, isNew: false),
      throwsA(anything),
    );
    final check = sqlite3.open(failed);
    check.execute("PRAGMA cipher='chacha20'");
    check.execute(
      'PRAGMA key="x\'${key.map((x) => x.toRadixString(16).padLeft(2, '0')).join()}\'"',
    );
    expect(check.select('PRAGMA user_version').single.values.single, 10);
    expect(check.select('SELECT * FROM product_label'), hasLength(1));
    expect(check.select('SELECT * FROM ordinary_draft'), isNotEmpty);
    check.close();
  });
}
