import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:true_grit_vital/data/record_store.dart';

void main() {
  late Directory directory;
  late RecordStore store;
  final key = List.generate(32, (i) => i + 31);
  final now = DateTime.utc(2026, 10, 22, 12);
  ExactAmount n(int value) => ExactAmount(BigInt.from(value));

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('vital-inventory-');
    store = await RecordStore.open(
      path: '${directory.path}/records.db',
      key: key,
      isNew: true,
    );
  });

  tearDown(() async {
    await store.close();
    await directory.delete(recursive: true);
  });

  Future<SubstanceItem> item(String name, {String unit = 'ml'}) =>
      store.createItem(
        commandId: newCommandId(),
        expectedPersonRevision: 1,
        name: name,
        form: 'liquid',
        unit: unit,
        type: 'medicine',
      );

  Future<StoredStockContainer> container(
    SubstanceItem item, {
    String? label,
    ExactAmount? opening,
    int? threshold,
    bool refill = false,
    CivilDate? expiry,
  }) => store.createStockContainer(
    commandId: newCommandId(),
    personId: meId,
    expectedPersonRevision: 1,
    expectedGeneration: store.generation,
    itemId: item.id,
    label: label ?? '${item.name} bottle',
    unit: item.unit,
    strength: LabelledStrength(
      ingredientId: item.id,
      label: '10 mg/ml',
      mgPerMl: n(10),
    ),
    opening: opening,
    lowThreshold: threshold == null ? null : n(threshold),
    refillEnabled: refill,
    expiryDate: expiry,
  );

  Future<void> plan(
    SubstanceItem item, {
    bool paused = false,
    bool active = true,
    String suffix = '',
    CivilDate? start,
    CivilDate? endExclusive,
  }) => store.saveDailyPlan(
    commandId: newCommandId(),
    expectedPersonRevision: 1,
    expectedGeneration: store.generation,
    plan: DailyPlanVersion(
      personId: meId,
      planId: 'plan-${item.id}$suffix',
      itemId: item.id,
      versionId: 'v1${item.id}$suffix',
      start: start ?? CivilDate(2026, 1, 1),
      endExclusive: endExclusive,
      timing: DailyCount(
        1,
        PlannedAmount(
          quantity: ExactQuantity.parse('1'),
          enteredText: '1',
          unit: item.unit,
        ),
      ),
      zoneBasis: const FollowingLocal(),
      pauses: paused ? [PlanPause(start: DateTime.utc(2026, 10, 1))] : const [],
    ),
  );

  test(
    'whole-collection counts and filters survive more than one page',
    () async {
      final lowItem = await item('Low item');
      final adequateItem = await item('Adequate item');
      final unknownItem = await item('Unknown item');
      final pausedItem = await item('Paused item');
      final unscheduledItem = await item('Unscheduled item');
      await container(lowItem, opening: n(1), threshold: 2);
      await container(adequateItem, opening: n(40));
      await container(unknownItem);
      await container(pausedItem, opening: n(40));
      await container(unscheduledItem, opening: n(40));
      for (var index = 0; index < 55; index++) {
        final extra = await item('Bulk item $index');
        await container(extra, opening: n(40));
        if (index == 0) await plan(extra);
      }
      await plan(lowItem);
      await plan(adequateItem);
      await plan(pausedItem, paused: true);
      // Unknown item has an active plan but an unknown balance.

      final all = await store.stockInventory(
        personId: meId,
        now: now,
        observedZone: 'UTC',
      );
      expect(all.complete, true);
      expect(all.counts.all, 60);
      expect(all.counts.low, 1);
      expect(all.counts.adequate, 58);
      expect(all.counts.unknown, 1);
      expect(all.counts.paused, 1);
      expect(all.containers, hasLength(60));

      final paused = await store.stockInventory(
        personId: meId,
        now: now,
        observedZone: 'UTC',
        filter: StockInventoryFilter.paused,
      );
      expect(paused.containers.single.itemId, pausedItem.id);
      expect(
        paused.planStates[paused.containers.single.id],
        StockInventoryPlanState.paused,
      );

      final unknown = await store.stockInventory(
        personId: meId,
        now: now,
        observedZone: 'UTC',
        filter: StockInventoryFilter.unknown,
      );
      expect(unknown.containers.single.itemId, unknownItem.id);
      expect(
        unknown.balances[unknown.containers.single.id],
        StockInventoryBalance.unknown,
      );

      final low = await store.stockInventory(
        personId: meId,
        now: now,
        observedZone: 'UTC',
        filter: StockInventoryFilter.low,
      );
      expect(low.containers.single.itemId, lowItem.id);

      final adequate = await store.stockInventory(
        personId: meId,
        now: now,
        observedZone: 'UTC',
        filter: StockInventoryFilter.adequate,
      );
      expect(adequate.counts.adequate, 58);
      expect(adequate.containers, hasLength(58));
    },
  );

  test(
    'search and item scope run at the store, not over one loaded page',
    () async {
      for (var index = 0; index < 55; index++) {
        final row = await item('Search item $index');
        await container(
          row,
          label: index == 54 ? 'Last cabinet bottle' : null,
          opening: n(5),
        );
      }
      final byName = await store.stockInventory(
        personId: meId,
        now: now,
        observedZone: 'UTC',
        search: 'Search item 54',
      );
      expect(byName.containers.single.label, 'Last cabinet bottle');
      final byLabel = await store.stockInventory(
        personId: meId,
        now: now,
        observedZone: 'UTC',
        search: 'cabinet',
      );
      expect(byLabel.containers.single.label, 'Last cabinet bottle');
      final literal = await store.stockInventory(
        personId: meId,
        now: now,
        observedZone: 'UTC',
        search: '%',
      );
      expect(literal.containers, isEmpty);
      final scopedItem = (await store.items()).first;
      final scoped = await store.stockInventory(
        personId: meId,
        now: now,
        observedZone: 'UTC',
        itemId: scopedItem.id,
      );
      expect(scoped.containers, hasLength(1));
      expect(scoped.containers.single.itemId, scopedItem.id);
    },
  );

  test(
    'paused is a plan state even when the stock balance is adequate',
    () async {
      final row = await item('Paused but stocked');
      await container(row, opening: n(40));
      await plan(row, paused: true);
      final snapshot = await store.stockInventory(
        personId: meId,
        now: now,
        observedZone: 'UTC',
      );
      expect(
        snapshot.planStates[snapshot.containers.single.id],
        StockInventoryPlanState.paused,
      );
      expect(
        snapshot.balances[snapshot.containers.single.id],
        StockInventoryBalance.adequate,
      );
      expect(snapshot.counts.paused, 1);
      expect(snapshot.counts.adequate, 1);
    },
  );

  test(
    'unknown plan resolution is excluded from paused and unscheduled',
    () async {
      final row = await item('Zone plan item');
      await container(row, opening: n(10));
      await plan(
        row,
        start: CivilDate(2026, 10, 22),
        endExclusive: CivilDate(2026, 10, 24),
      );
      final snapshot = await store.stockInventory(
        personId: meId,
        now: now,
        observedZone: null,
      );
      expect(
        snapshot.planStates[snapshot.containers.single.id],
        StockInventoryPlanState.unresolved,
      );
      expect(snapshot.counts.unresolved, 1);
      expect(snapshot.counts.paused, 0);
    },
  );

  test('locked reads cancel and resume without inventing totals', () async {
    final row = await item('Locked item');
    final bottle = await container(row, opening: n(10));
    store.suspendWrites(true);
    await expectLater(
      store.stockInventory(personId: meId, now: now, observedZone: 'UTC'),
      throwsA(
        isA<CommandConflict>().having((e) => e.code, 'code', 'app_locked'),
      ),
    );
    await expectLater(
      store.stockForecastForContainer(
        personId: meId,
        containerId: bottle.id,
        now: now,
        observedZone: 'UTC',
      ),
      throwsA(
        isA<CommandConflict>().having((e) => e.code, 'code', 'app_locked'),
      ),
    );
    store.suspendWrites(false);
    final resumed = await store.stockInventory(
      personId: meId,
      now: now,
      observedZone: 'UTC',
    );
    expect(resumed.counts.all, 1);
  });

  test(
    'forecast read uses the saved plan engine and container facts',
    () async {
      final row = await item('Forecast item');
      final bottle = await container(row, opening: n(10));
      await plan(row);
      final result = await store.stockForecastForContainer(
        personId: meId,
        containerId: bottle.id,
        now: now,
        observedZone: 'UTC',
      );
      expect(result!.date, CivilDate(2026, 11, 1));
      final paused = await store.stockInventory(
        personId: meId,
        now: now,
        observedZone: 'UTC',
      );
      expect(paused.containers.single.id, bottle.id);
    },
  );

  test('expiry filters compare with the observed local civil day', () async {
    final row = await item('Zone boundary item');
    await container(
      row,
      label: 'Expired earlier',
      opening: n(10),
      expiry: CivilDate(2026, 10, 20),
    );
    await container(
      row,
      label: 'Expired yesterday',
      opening: n(10),
      expiry: CivilDate(2026, 10, 21),
    );
    await container(
      row,
      label: 'Expires today',
      opening: n(10),
      expiry: CivilDate(2026, 10, 22),
    );
    await container(
      row,
      label: 'Expires tomorrow',
      opening: n(10),
      expiry: CivilDate(2026, 10, 23),
    );
    await container(row, label: 'No expiry', opening: n(10));

    final utc = await store.stockInventory(
      personId: meId,
      now: DateTime.utc(2026, 10, 22, 12),
      observedZone: 'UTC',
    );
    expect(utc.expiryDay, CivilDate(2026, 10, 22));
    expect(utc.counts.all, 5);
    expect(utc.counts.expired, 2);
    expect(utc.counts.today, 1);
    expect(utc.counts.count(StockInventoryFilter.expired), 2);

    final utcExpired = await store.stockInventory(
      personId: meId,
      now: DateTime.utc(2026, 10, 22, 12),
      observedZone: 'UTC',
      filter: StockInventoryFilter.expired,
    );
    expect(utcExpired.containers.map((c) => c.label).toSet(), {
      'Expired earlier',
      'Expired yesterday',
    });
    final utcToday = await store.stockInventory(
      personId: meId,
      now: DateTime.utc(2026, 10, 22, 12),
      observedZone: 'UTC',
      filter: StockInventoryFilter.today,
    );
    expect(utcToday.containers.single.label, 'Expires today');

    // The same instant is already Friday 23 October at UTC+14.
    final sameInstant = DateTime.utc(2026, 10, 22, 23, 30);
    final kiritimati = await store.stockInventory(
      personId: meId,
      now: sameInstant,
      observedZone: 'Pacific/Kiritimati',
    );
    expect(kiritimati.expiryDay, CivilDate(2026, 10, 23));
    expect(kiritimati.counts.expired, 3);
    expect(kiritimati.counts.today, 1);
    final kiritimatiToday = await store.stockInventory(
      personId: meId,
      now: sameInstant,
      observedZone: 'Pacific/Kiritimati',
      filter: StockInventoryFilter.today,
    );
    expect(kiritimatiToday.containers.single.label, 'Expires tomorrow');
  });

  test('missing or invalid zone leaves expiry counts unavailable', () async {
    final row = await item('No zone expiry item');
    await container(
      row,
      label: 'Past pack',
      opening: n(10),
      expiry: CivilDate(2026, 10, 21),
    );
    await container(
      row,
      label: 'Today pack',
      opening: n(10),
      expiry: CivilDate(2026, 10, 22),
    );
    for (final zone in [null, 'Mars/Olympus']) {
      final snapshot = await store.stockInventory(
        personId: meId,
        now: DateTime.utc(2026, 10, 22, 23, 30),
        observedZone: zone,
      );
      expect(snapshot.complete, true);
      expect(snapshot.expiryDay, isNull);
      expect(snapshot.counts.all, 2);
      expect(snapshot.counts.expired, isNull);
      expect(snapshot.counts.today, isNull);
      expect(snapshot.counts.expiryKnown, false);
      expect(snapshot.counts.count(StockInventoryFilter.expired), isNull);
      final filtered = await store.stockInventory(
        personId: meId,
        now: DateTime.utc(2026, 10, 22, 23, 30),
        observedZone: zone,
        filter: StockInventoryFilter.expired,
      );
      expect(filtered.containers, isEmpty);
      expect(filtered.counts.expired, isNull);
    }
  });

  test(
    'expiry filters and counts cover more than one page of containers',
    () async {
      final bulkItem = await item('Bulk expiry item');
      for (var index = 0; index < 55; index++) {
        await container(
          bulkItem,
          label: 'Bulk bottle $index',
          opening: n(10),
          expiry: index == 0 ? null : CivilDate(2026, 12, 31),
        );
      }
      final tailItem = await item('Zzz cabinet item');
      await container(
        tailItem,
        label: 'Cabinet expired bottle',
        opening: n(10),
        expiry: CivilDate(2026, 10, 21),
      );
      final all = await store.stockInventory(
        personId: meId,
        now: now,
        observedZone: 'UTC',
      );
      expect(all.counts.all, 56);
      expect(all.counts.expired, 1);
      expect(all.counts.today, 0);

      final expired = await store.stockInventory(
        personId: meId,
        now: now,
        observedZone: 'UTC',
        filter: StockInventoryFilter.expired,
      );
      expect(expired.containers.single.label, 'Cabinet expired bottle');
      final searched = await store.stockInventory(
        personId: meId,
        now: now,
        observedZone: 'UTC',
        search: 'cabinet',
        filter: StockInventoryFilter.expired,
      );
      expect(searched.containers.single.label, 'Cabinet expired bottle');
      expect(searched.counts.all, 1);
      final wrongSearch = await store.stockInventory(
        personId: meId,
        now: now,
        observedZone: 'UTC',
        search: 'Bulk bottle',
        filter: StockInventoryFilter.expired,
      );
      expect(wrongSearch.containers, isEmpty);
      expect(wrongSearch.counts.all, 55);
      final scoped = await store.stockInventory(
        personId: meId,
        now: now,
        observedZone: 'UTC',
        itemId: bulkItem.id,
        filter: StockInventoryFilter.expired,
      );
      expect(scoped.containers, isEmpty);
      expect(scoped.counts.all, 55);
    },
  );

  test('expiry filters stay bounded rather than claiming a total', () async {
    final row = await item('Bounded expiry item');
    for (var index = 0; index < 2001; index++) {
      await container(
        row,
        label: 'Bounded bottle $index',
        opening: n(5),
        expiry: index % 10 == 0 ? CivilDate(2026, 10, 21) : null,
      );
    }
    final all = await store.stockInventory(
      personId: meId,
      now: now,
      observedZone: 'UTC',
    );
    expect(all.complete, false);
    expect(all.containers, hasLength(2000));
    expect(all.counts.all, 2000);
    final countedExpired = all.containers
        .where(
          (c) => c.expiryState(CivilDate(2026, 10, 22)) ==
              StockExpiryState.expired,
        )
        .length;
    expect(all.counts.expired, countedExpired);
    final expired = await store.stockInventory(
      personId: meId,
      now: now,
      observedZone: 'UTC',
      filter: StockInventoryFilter.expired,
    );
    expect(expired.complete, false);
    expect(expired.containers, hasLength(countedExpired));
    expect(
      expired.containers.every(
        (c) => c.expiryState(CivilDate(2026, 10, 22)) ==
            StockExpiryState.expired,
      ),
      true,
    );
  });

  test('metadata edits refresh a watched expiry filter', () async {
    final row = await item('Watched expiry item');
    final bottle = await container(
      row,
      opening: n(10),
      expiry: CivilDate(2026, 10, 24),
    );
    final snapshots = StreamIterator(
      store.watchStockInventory(
        personId: meId,
        now: now,
        observedZone: 'UTC',
        filter: StockInventoryFilter.expired,
      ),
    );
    try {
      expect(await snapshots.moveNext(), isTrue);
      expect(snapshots.current.containers, isEmpty);
      expect(snapshots.current.counts.expired, 0);
      await store.updateStockMetadata(
        commandId: newCommandId(),
        personId: meId,
        expectedPersonRevision: 1,
        expectedGeneration: store.generation,
        containerId: bottle.id,
        expectedContainerRevision: bottle.revision,
        expiryDate: CivilDate(2026, 10, 21),
      );
      expect(await snapshots.moveNext(), isTrue);
      expect(snapshots.current.containers.single.id, bottle.id);
      expect(snapshots.current.counts.expired, 1);
      expect(snapshots.current.counts.today, 0);
    } finally {
      await snapshots.cancel();
    }
  });
}
