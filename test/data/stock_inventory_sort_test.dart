import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:true_grit_vital/app/app_lock.dart';
import 'package:true_grit_vital/app/storage.dart';
import 'package:true_grit_vital/data/record_store.dart';
import 'package:true_grit_vital/features/stock/stock_providers.dart';

final class _Unlocked extends AppLockController {
  @override
  AppLockState build() => const AppLockState(ready: true, locked: false);
}

final class _Locked extends AppLockController {
  @override
  AppLockState build() => const AppLockState(ready: true, locked: true);
}

final class _ExpirySort extends StockInventorySortController {
  @override
  StockInventorySort build() => StockInventorySort.expiry;
}

void main() {
  late Directory directory;
  late RecordStore store;
  final key = List.generate(32, (i) => i + 31);
  final now = DateTime.utc(2026, 10, 22, 12);
  ExactAmount n(int value) => ExactAmount(BigInt.from(value));

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('vital-sort-');
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

  Future<SubstanceItem> item(String name) => store.createItem(
    commandId: newCommandId(),
    expectedPersonRevision: 1,
    name: name,
    form: 'tablet',
    unit: 'count',
    type: 'medicine',
  );

  Future<StoredStockContainer> container(
    SubstanceItem item, {
    required String label,
    CivilDate? expiry,
    ExactAmount? opening,
    bool refill = false,
  }) => store.createStockContainer(
    commandId: newCommandId(),
    personId: meId,
    expectedPersonRevision: 1,
    expectedGeneration: store.generation,
    itemId: item.id,
    label: label,
    unit: item.unit,
    strength: LabelledStrength(
      ingredientId: item.id,
      label: '10 mg',
      mgPerCount: n(10),
    ),
    opening: opening ?? n(10),
    refillEnabled: refill,
    expiryDate: expiry,
  );

  /// The declared expiry order: known full dates ascending, unknown dates
  /// last, then saved item name and container id as the stable tie break.
  List<String> declaredExpiryOrder(
    List<StoredStockContainer> rows,
    Map<String, String> names,
  ) =>
      ([...rows]..sort((a, b) {
            final aExpiry = a.expiryDate, bExpiry = b.expiryDate;
            if (aExpiry != null && bExpiry != null) {
              final byExpiry = aExpiry.compareTo(bExpiry);
              if (byExpiry != 0) return byExpiry;
            } else if (aExpiry != null) {
              return -1;
            } else if (bExpiry != null) {
              return 1;
            }
            final byName = names[a.id]!.compareTo(names[b.id]!);
            if (byName != 0) return byName;
            return a.id.compareTo(b.id);
          }))
          .map((row) => row.id)
          .toList();

  test(
    'expiry sort orders known dates, ties and unknown dates across 60 rows',
    () async {
      final containers = <StoredStockContainer>[];
      final names = <String, String>{};
      for (var itemIndex = 0; itemIndex < 12; itemIndex++) {
        final name = 'Sort item ${itemIndex.toString().padLeft(2, '0')}';
        final row = await item(name);
        for (var bottle = 0; bottle < 5; bottle++) {
          final saved = await container(
            row,
            label: 'Bottle $bottle',
            expiry: bottle == 0
                ? null
                : CivilDate(2027, 1, 1 + ((itemIndex * 5 + bottle) % 20)),
          );
          containers.add(saved);
          names[saved.id] = name;
        }
      }

      final byName = await store.stockInventory(
        personId: meId,
        now: now,
        observedZone: 'UTC',
      );
      final explicitName = await store.stockInventory(
        personId: meId,
        now: now,
        observedZone: 'UTC',
        sort: StockInventorySort.name,
      );
      expect(byName.complete, true);
      expect(byName.containers, hasLength(60));
      expect(byName.counts.all, 60);
      expect(
        explicitName.containers.map((c) => c.id),
        byName.containers.map((c) => c.id),
        reason: 'omitting sort must keep the existing name order',
      );

      final nameOrder = byName.containers;
      for (var index = 1; index < nameOrder.length; index++) {
        final previous = nameOrder[index - 1], current = nameOrder[index];
        final byNameComparison = names[previous.id]!.compareTo(
          names[current.id]!,
        );
        expect(
          byNameComparison < 0 ||
              (byNameComparison == 0 && previous.id.compareTo(current.id) <= 0),
          true,
          reason: 'name order uses saved name then container id',
        );
      }

      final byExpiry = await store.stockInventory(
        personId: meId,
        now: now,
        observedZone: 'UTC',
        sort: StockInventorySort.expiry,
      );
      expect(byExpiry.counts.all, 60);
      expect(byExpiry.complete, true);
      expect(
        byExpiry.containers.map((c) => c.id),
        declaredExpiryOrder(containers, names),
      );
      expect(
        byExpiry.containers.map((c) => c.id).toSet(),
        containers.map((c) => c.id).toSet(),
        reason: 'sorting must not drop or duplicate rows',
      );

      final known = byExpiry.containers
          .takeWhile((c) => c.expiryDate != null)
          .toList();
      final unknown = byExpiry.containers.skip(known.length).toList();
      expect(known, hasLength(48));
      expect(unknown, hasLength(12));
      expect(unknown.every((c) => c.expiryDate == null), true);
      for (var index = 1; index < known.length; index++) {
        expect(
          known[index - 1].expiryDate!.compareTo(known[index].expiryDate!),
          lessThanOrEqualTo(0),
        );
      }
    },
  );

  test(
    'expiry sort applies to the whole filtered snapshot before paging',
    () async {
      final bulk = await item('Bulk sort item');
      final other = await item('Other sort item');
      for (var index = 0; index < 55; index++) {
        await container(
          bulk,
          label: 'Bottle ${(index + 1).toString().padLeft(2, '0')}',
          expiry: CivilDate(2027, 12, 31).addDays(-index),
          opening: index % 2 == 0 ? n(0) : n(30),
        );
      }
      await container(
        other,
        label: 'Other low bottle',
        expiry: CivilDate(2026, 12, 31),
        opening: n(0),
        refill: true,
      );

      // Low composes with search. The 55 bulk rows include 28 low balances.
      final low = await store.stockInventory(
        personId: meId,
        now: now,
        observedZone: 'UTC',
        search: 'Bulk sort item',
        filter: StockInventoryFilter.low,
        sort: StockInventorySort.expiry,
      );
      expect(low.complete, true);
      expect(low.counts.all, 55);
      expect(low.containers, hasLength(28));
      expect(low.containers.every((c) => c.label.startsWith('Bottle ')), true);
      for (var index = 1; index < low.containers.length; index++) {
        expect(
          low.containers[index - 1].expiryDate!.compareTo(
            low.containers[index].expiryDate!,
          ),
          lessThanOrEqualTo(0),
        );
      }
      // The first UI page is the first 50 of the whole sorted snapshot.
      final firstPage = low.containers.take(50).toList();
      expect(firstPage, hasLength(28));
      expect(low.containers.first.label, 'Bottle 55');

      final all = await store.stockInventory(
        personId: meId,
        now: now,
        observedZone: 'UTC',
        search: 'Bulk sort item',
        sort: StockInventorySort.expiry,
      );
      expect(all.containers, hasLength(55));
      final page = all.containers.take(50).toList();
      final beyondPage = all.containers.skip(50).toList();
      expect(page, hasLength(50));
      expect(beyondPage.map((c) => c.label), [
        'Bottle 05',
        'Bottle 04',
        'Bottle 03',
        'Bottle 02',
        'Bottle 01',
      ]);
      expect(page.last.label, 'Bottle 06');
      expect(all.counts.all, 55);
    },
  );

  test('expiry sort works without an observed local day', () async {
    final row = await item('Zone free sort item');
    await container(row, label: 'Later bottle', expiry: CivilDate(2028, 5, 1));
    await container(row, label: 'No date bottle');
    await container(
      row,
      label: 'Earlier bottle',
      expiry: CivilDate(2026, 5, 1),
    );

    for (final zone in [null, 'Mars/Olympus']) {
      final snapshot = await store.stockInventory(
        personId: meId,
        now: DateTime.utc(2026, 10, 22, 23, 30),
        observedZone: zone,
        sort: StockInventorySort.expiry,
      );
      expect(snapshot.expiryDay, isNull);
      expect(snapshot.counts.expired, isNull);
      expect(snapshot.containers.map((c) => c.label), [
        'Earlier bottle',
        'Later bottle',
        'No date bottle',
      ]);
    }
  });

  test('live metadata edits reorder a watched expiry view', () async {
    final row = await item('Watched sort item');
    final first = await container(
      row,
      label: 'First bottle',
      expiry: CivilDate(2027, 3, 1),
    );
    final second = await container(
      row,
      label: 'Second bottle',
      expiry: CivilDate(2027, 6, 1),
    );
    final unknown = await container(row, label: 'Unknown bottle');

    final snapshots = StreamIterator(
      store.watchStockInventory(
        personId: meId,
        now: now,
        observedZone: 'UTC',
        sort: StockInventorySort.expiry,
      ),
    );
    try {
      expect(await snapshots.moveNext(), isTrue);
      expect(snapshots.current.containers.map((c) => c.label), [
        'First bottle',
        'Second bottle',
        'Unknown bottle',
      ]);

      await store.updateStockMetadata(
        commandId: newCommandId(),
        personId: meId,
        expectedPersonRevision: 1,
        expectedGeneration: store.generation,
        containerId: unknown.id,
        expectedContainerRevision: unknown.revision,
        expiryDate: CivilDate(2026, 12, 1),
      );
      expect(await snapshots.moveNext(), isTrue);
      expect(snapshots.current.containers.map((c) => c.label), [
        'Unknown bottle',
        'First bottle',
        'Second bottle',
      ]);

      await store.updateStockMetadata(
        commandId: newCommandId(),
        personId: meId,
        expectedPersonRevision: 1,
        expectedGeneration: store.generation,
        containerId: first.id,
        expectedContainerRevision: first.revision,
        expiryDate: CivilDate(2028, 1, 1),
      );
      expect(await snapshots.moveNext(), isTrue);
      expect(snapshots.current.containers.map((c) => c.label), [
        'Unknown bottle',
        'Second bottle',
        'First bottle',
      ]);
      expect(snapshots.current.containers.last.id, first.id);
      expect(snapshots.current.containers.first.id, unknown.id);
      expect(snapshots.current.containers[1].id, second.id);
    } finally {
      await snapshots.cancel();
    }
  });

  test('locked reads cancel an expiry sort without inventing totals', () async {
    final row = await item('Locked sort item');
    await container(row, label: 'Locked bottle', expiry: CivilDate(2027, 1, 1));
    store.suspendWrites(true);
    await expectLater(
      store.stockInventory(
        personId: meId,
        now: now,
        observedZone: 'UTC',
        sort: StockInventorySort.expiry,
      ),
      throwsA(
        isA<CommandConflict>().having((e) => e.code, 'code', 'app_locked'),
      ),
    );
    store.suspendWrites(false);

    final query = (
      personId: meId,
      itemId: null,
      search: '',
      filter: StockInventoryFilter.all,
      asOf: now,
      zone: 'UTC',
      cutoff: null,
    );
    Future<StockInventorySnapshot> first(ProviderContainer container) {
      final value = Completer<StockInventorySnapshot>();
      final subscription = container.listen(stockInventoryProvider(query), (
        _,
        next,
      ) {
        if (next.hasValue && !value.isCompleted) value.complete(next.value);
      }, fireImmediately: true);
      addTearDown(subscription.close);
      return value.future;
    }

    final sorted = ProviderContainer(
      overrides: [
        appLockProvider.overrideWith(_Unlocked.new),
        stockInventorySortProvider.overrideWith(_ExpirySort.new),
        recordStoreProvider.overrideWith((ref) async => store),
      ],
    );
    addTearDown(sorted.dispose);
    final snapshot = await first(sorted);
    expect(snapshot.containers.single.label, 'Locked bottle');
    expect(snapshot.complete, true);
    expect(sorted.read(stockInventorySortProvider), StockInventorySort.expiry);

    final locked = ProviderContainer(
      overrides: [
        appLockProvider.overrideWith(_Locked.new),
        stockInventorySortProvider.overrideWith(_ExpirySort.new),
        recordStoreProvider.overrideWith((ref) async => store),
      ],
    );
    addTearDown(locked.dispose);
    final hidden = await first(locked);
    expect(hidden.containers, isEmpty);
    expect(hidden.counts.all, 0);
    expect(hidden.complete, true);
  });

  test(
    'an incomplete expiry sort keeps the bound and never adds omitted rows',
    () async {
      final loaded = await item('A Loaded sort item');
      for (var index = 0; index < 2000; index++) {
        await container(
          loaded,
          label: 'Loaded bottle $index',
          expiry: CivilDate(2027, 6, 1),
        );
      }
      final omitted = await item('Z Omitted sort item');
      final omittedContainer = await container(
        omitted,
        label: 'Omitted earliest bottle',
        expiry: CivilDate(2027, 1, 1),
      );

      final snapshot = await store.stockInventory(
        personId: meId,
        now: now,
        observedZone: 'UTC',
        sort: StockInventorySort.expiry,
      );
      expect(snapshot.complete, false);
      expect(snapshot.counts.all, 2000);
      expect(snapshot.containers, hasLength(2000));
      expect(
        snapshot.containers.any((c) => c.id == omittedContainer.id),
        false,
        reason: 'the bounded read cannot claim the omitted earliest record',
      );
      expect(snapshot.containers.first.expiryDate, CivilDate(2027, 6, 1));
      expect(
        snapshot.containers.every((c) => c.expiryDate == CivilDate(2027, 6, 1)),
        true,
      );

      final filtered = await store.stockInventory(
        personId: meId,
        now: now,
        observedZone: 'UTC',
        filter: StockInventoryFilter.low,
        sort: StockInventorySort.expiry,
      );
      expect(filtered.complete, false);
      expect(filtered.counts.all, 2000);
      expect(filtered.containers, isEmpty);
    },
  );
}
