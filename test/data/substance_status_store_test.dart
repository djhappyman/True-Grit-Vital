import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:true_grit_vital/data/record_store.dart';

void main() {
  late Directory dir;
  late RecordStore store;
  const zone = 'Europe/London';
  final key = List.generate(32, (i) => i + 1);

  DateTime now() => DateTime.now().toUtc();
  CivilDate today() => DailyResolver().clock.dateAt(now(), zone);

  PlannedAmount amount([String text = '1']) => PlannedAmount(
    quantity: ExactQuantity.parse(text),
    enteredText: text,
    unit: 'mg',
  );

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('vital-substance-status-');
    store = await RecordStore.open(
      path: '${dir.path}/records.db',
      key: key,
      isNew: true,
    );
  });

  tearDown(() async {
    await store.close();
    await dir.delete(recursive: true);
  });

  Future<SubstanceItem> item(String name, {String type = 'Medicine'}) =>
      store.createItem(
        commandId: 'item-${newCommandId()}',
        name: name,
        form: 'Tablet',
        unit: 'mg',
        type: type,
      );

  Future<SavedDailyPlan> plan({
    required SubstanceItem item,
    required String planId,
    required DailyTiming timing,
    CivilDate? start,
    CivilDate? endExclusive,
    Iterable<PlanPause> pauses = const [],
    CalendarPattern calendar = const EveryDay(),
    DailyZoneBasis? zoneBasis,
    String? versionId,
    int? expectedPlanRevision,
    String? commandId,
  }) async {
    final owner = (await store.profileById(meId))!;
    return store.saveDailyPlan(
      commandId: commandId ?? 'plan-${newCommandId()}',
      plan: DailyPlanVersion(
        personId: meId,
        planId: planId,
        itemId: item.id,
        versionId: versionId ?? 'version-${newCommandId()}',
        start: start ?? today().addDays(-7),
        endExclusive: endExclusive,
        timing: timing,
        zoneBasis: zoneBasis ?? FixedHome(zone),
        calendar: calendar,
        pauses: pauses,
      ),
      expectedPersonRevision: owner.revision,
      expectedGeneration: store.generation,
      expectedPlanRevision: expectedPlanRevision,
    );
  }

  Future<SubstanceStatusSnapshot> snapshot({
    String? search,
    String? typeId,
    DateTime? at,
    String? observedZone = zone,
  }) => store.substanceStatusSnapshot(
    scope: const FeedScope.me(),
    search: search,
    typeId: typeId,
    now: at ?? now(),
    observedZone: observedZone,
  );

  test('whole-collection counts and filters reach past the first page', () async {
    final items = <SubstanceItem>[];
    for (var i = 0; i < 120; i++) {
      items.add(await item('Item ${i.toString().padLeft(3, '0')}'));
    }
    // 60 active, 20 paused, 20 as needed, 20 unscheduled.
    for (var i = 0; i < 60; i++) {
      await plan(
        item: items[i],
        planId: 'plan-$i',
        timing: DailyCount(1, amount()),
      );
    }
    final pause = PlanPause(
      start: now().subtract(const Duration(hours: 1)),
      resume: now().add(const Duration(hours: 1)),
    );
    for (var i = 60; i < 80; i++) {
      await plan(
        item: items[i],
        planId: 'plan-$i',
        timing: DailyCount(1, amount()),
        pauses: [pause],
      );
    }
    for (var i = 80; i < 100; i++) {
      await plan(
        item: items[i],
        planId: 'plan-$i',
        timing: const AsNeeded(),
      );
    }
    final result = await snapshot();
    expect(result.counts.all, 120);
    expect(result.counts.active, 60);
    expect(result.counts.paused, 20);
    expect(result.counts.asNeeded, 20);
    expect(result.counts.unscheduled, 20);
    expect(result.counts.unresolved, 0);
    // Active has a second page and includes an item stored beyond position 100.
    final active = result.itemIdsFor(SubstanceStatusFilter.active).toList();
    expect(active.length, 60);
    expect(active.last, items[59].id);
    final secondPage = (await store.itemsByIds(active.skip(50).take(51))).toList();
    expect(secondPage.length, 10);
    expect(secondPage.first.name, 'Item 050');
    // Unscheduled includes stored items past position 100.
    final unscheduled = result
        .itemIdsFor(SubstanceStatusFilter.unscheduled)
        .toList();
    expect(unscheduled.length, 20);
    expect(unscheduled.first, items[100].id);
    // A paused As needed plan is paused only, not As needed.
    expect(
      result.statusesFor(items[60].id),
      {SubstancePlanStatus.paused},
    );
  });

  test('name, type and status compose over one snapshot', () async {
    final alpha = await item('Alpha', type: 'Medicine');
    final beta = await item('Beta', type: 'Medicine');
    final gamma = await item('Gamma', type: 'Medicine');
    final delta = await item('Delta', type: 'Supplement');
    final epsilon = await item('Epsilon', type: 'Supplement');
    await item('Zeta', type: 'Supplement');
    await plan(item: alpha, planId: 'alpha', timing: DailyCount(1, amount()));
    await plan(item: beta, planId: 'beta', timing: DailyCount(1, amount()));
    await plan(
      item: gamma,
      planId: 'gamma',
      timing: DailyCount(1, amount()),
      pauses: [PlanPause(start: now().subtract(const Duration(hours: 1)))],
    );
    await plan(item: delta, planId: 'delta', timing: DailyCount(1, amount()));
    await plan(item: epsilon, planId: 'epsilon', timing: const AsNeeded());

    final medicine = await snapshot(typeId: alpha.typeId);
    expect(medicine.counts.all, 3);
    expect(medicine.counts.active, 2);
    expect(medicine.counts.paused, 1);
    expect(medicine.counts.asNeeded, 0);
    expect(medicine.counts.unscheduled, 0);

    final named = await snapshot(search: 'Beta');
    expect(named.counts.all, 1);
    expect(named.counts.active, 1);
    expect(named.itemIdsFor(SubstanceStatusFilter.active), [beta.id]);

    final combined = await snapshot(
      search: 'Beta',
      typeId: alpha.typeId,
    );
    expect(combined.counts.all, 1);
    final supplement = await snapshot(
      search: 'Beta',
      typeId: delta.typeId,
    );
    expect(supplement.counts.all, 0);
    expect(supplement.counts.active, 0);

    final all = await snapshot();
    expect(all.counts.all, 6);
    expect(all.counts.unscheduled, 1);
    expect(all.itemIdsFor(SubstanceStatusFilter.unscheduled).single, isNot(delta.id));
  });

  test('pauses, resume boundaries and historical versions are evaluated', () async {
    final scheduled = await item('Scheduled');
    final start = today().addDays(-10);
    await plan(
      item: scheduled,
      planId: 'scheduled',
      start: start,
      timing: DailySlots([
        DailySlot(
          id: 'slot',
          time: WallTime(8, 0),
          amount: amount(),
          reminderEnabled: false,
        ),
      ]),
    );
    // A newer live version changes the configuration, while the older version
    // remains the truthful configuration for a historical query.
    final revision = (await store.dailyPlans(itemId: scheduled.id)).single;
    await plan(
      item: scheduled,
      planId: 'scheduled',
      start: today(),
      timing: const AsNeeded(),
      expectedPlanRevision: revision.revision,
    );
    final current = await snapshot();
    expect(current.statusesFor(scheduled.id), {SubstancePlanStatus.asNeeded});
    final historical = await snapshot(at: now().subtract(const Duration(days: 5)));
    expect(historical.statusesFor(scheduled.id), {SubstancePlanStatus.active});

    // A real pause inside the version makes it paused, then active after resume.
    final paused = await item('Paused');
    final pauseStart = now().subtract(const Duration(hours: 1));
    final resume = now().add(const Duration(hours: 1));
    await plan(
      item: paused,
      planId: 'paused',
      timing: DailyCount(1, amount()),
      pauses: [PlanPause(start: pauseStart, resume: resume)],
    );
    final during = await snapshot();
    expect(during.statusesFor(paused.id), {SubstancePlanStatus.paused});
    final after = await snapshot(at: resume.add(const Duration(seconds: 1)));
    expect(after.statusesFor(paused.id), {SubstancePlanStatus.active});
  });

  test('future-only, ended and off-weekday plans stay truthful', () async {
    final future = await item('Future');
    await plan(
      item: future,
      planId: 'future',
      start: today().addDays(1),
      timing: DailyCount(1, amount()),
    );
    final ended = await item('Ended');
    await plan(
      item: ended,
      planId: 'ended',
      start: today().addDays(-10),
      endExclusive: today().addDays(-5),
      timing: DailyCount(1, amount()),
    );
    final off = await item('Off weekday');
    final weekday = today().calendarValue.weekday;
    final otherWeekday = weekday == 7 ? 1 : weekday + 1;
    await plan(
      item: off,
      planId: 'off',
      timing: DailyCount(1, amount()),
      calendar: SelectedWeekdays([otherWeekday]),
    );
    final result = await snapshot();
    expect(result.counts.unscheduled, 2);
    expect(
      result.itemIdsFor(SubstanceStatusFilter.unscheduled).toSet(),
      {future.id, ended.id},
    );
    expect(result.statusesFor(off.id), {SubstancePlanStatus.active});
    expect(result.counts.active, 1);
  });

  test('unknown local zone and phase ends never invent a status', () async {
    final local = await item('Local');
    final envelope = DailyResolver().clock.dateEnvelopeAt(now());
    await plan(
      item: local,
      planId: 'local',
      start: envelope.$1.addDays(1),
      timing: DailyCount(1, amount()),
      zoneBasis: const FollowingLocal(),
    );
    final unresolved = await snapshot(observedZone: null);
    expect(unresolved.counts.all, 1);
    expect(unresolved.counts.unresolved, 1);
    expect(unresolved.counts.unscheduled, 0);
    expect(unresolved.counts.active, 0);
    expect(unresolved.itemIdsFor(SubstanceStatusFilter.unscheduled), isEmpty);
    // The same stored plan resolves once the local zone is known.
    final resolved = await snapshot(observedZone: 'Pacific/Auckland');
    expect(resolved.counts.unresolved, 0);
    expect(
      resolved.statusesFor(local.id),
      {SubstancePlanStatus.active},
    );

    final fixed = await item('Fixed');
    await plan(
      item: fixed,
      planId: 'fixed',
      timing: DailyCount(1, amount()),
      zoneBasis: FixedHome('Etc/UTC'),
    );
    final withoutObservation = await snapshot(observedZone: null);
    expect(
      withoutObservation.statusesFor(fixed.id),
      {SubstancePlanStatus.active},
    );
    expect(withoutObservation.counts.unresolved, 1);
  });

  test('plan evaluation is set based and phase ends are respected', () {
    final at = DateTime.utc(2026, 10, 21, 12);
    final clock = DailyResolver().clock;
    final envelope = clock.dateEnvelopeAt(at);
    DailyPlanVersion version(
      String id,
      DailyTiming timing, {
      CivilDate? start,
    }) => DailyPlanVersion(
      personId: meId,
      planId: 'plan',
      itemId: 'item',
      versionId: id,
      start: start ?? CivilDate(2026, 10, 1),
      timing: timing,
      zoneBasis: FixedHome('Etc/UTC'),
    );
    // Two current configurations on one item keep both truthful statuses.
    final overlap = evaluateSubstancePlanPresence(
      versions: [
        version('scheduled', DailyCount(1, amount())),
        version('prn', const AsNeeded()),
      ],
      now: at,
      observedZone: null,
      envelope: envelope,
    );
    expect(overlap.statuses, {
      SubstancePlanStatus.active,
      SubstancePlanStatus.asNeeded,
    });
    // A paused As needed plan is paused only while the pause lasts.
    final pausedPrn = evaluateSubstancePlanPresence(
      versions: [
        DailyPlanVersion(
          personId: meId,
          planId: 'plan',
          itemId: 'item',
          versionId: 'paused-prn',
          start: CivilDate(2026, 10, 1),
          timing: const AsNeeded(),
          zoneBasis: FixedHome('Etc/UTC'),
          pauses: [
            PlanPause(
              start: at.subtract(const Duration(minutes: 30)),
              resume: at.add(const Duration(minutes: 30)),
            ),
          ],
        ),
      ],
      now: at,
      observedZone: null,
      envelope: envelope,
    );
    expect(pausedPrn.statuses, {SubstancePlanStatus.paused});
    // A phase end in the past makes the plan unscheduled even if its version
    // bounds are open. A future end keeps it configured.
    final ended = PlanEnd.onDate(
      lastDate: CivilDate(2026, 10, 20),
      zoneId: 'Etc/UTC',
      clock: clock,
    );
    expect(
      evaluateSubstancePlanPresence(
        versions: [version('ended', DailyCount(1, amount()))],
        now: at,
        observedZone: null,
        envelope: envelope,
        end: ended,
      ).isUnscheduled,
      isTrue,
    );
    final futureEnd = PlanEnd.onDate(
      lastDate: CivilDate(2026, 10, 22),
      zoneId: 'Etc/UTC',
      clock: clock,
    );
    expect(
      evaluateSubstancePlanPresence(
        versions: [version('future-end', DailyCount(1, amount()))],
        now: at,
        observedZone: null,
        envelope: envelope,
        end: futureEnd,
      ).statuses,
      {SubstancePlanStatus.active},
    );
  });

  test('itemsByIds and its watch read in the requested order', () async {
    final first = await item('First');
    final second = await item('Second');
    final direct = await store.itemsByIds([second.id, first.id]);
    expect(direct.map((i) => i.name), ['Second', 'First']);
    final watched = await store
        .watchItemsByIds([second.id, first.id])
        .first
        .timeout(const Duration(seconds: 5));
    expect(watched.map((i) => i.name), ['Second', 'First']);
  });

  test('a live snapshot updates after a plan is saved', () async {
    final live = await item('Live');
    final updates = <SubstanceStatusSnapshot>[];
    final subscription = store
        .watchSubstanceStatusSnapshot(
          scope: const FeedScope.me(),
          now: now(),
          observedZone: zone,
        )
        .listen(updates.add);
    addTearDown(subscription.cancel);
    final initialDeadline = DateTime.now().add(const Duration(seconds: 5));
    while (updates.isEmpty && DateTime.now().isBefore(initialDeadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect(updates, isNotEmpty);
    expect(updates.last.counts.active, 0);
    await plan(item: live, planId: 'live', timing: DailyCount(1, amount()));
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (updates.last.counts.active == 0 && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect(updates.last.counts.active, 1);
    expect(updates.last.statusesFor(live.id), {SubstancePlanStatus.active});
  });
}
