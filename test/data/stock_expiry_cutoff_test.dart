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

void main() {
  late Directory directory;
  late RecordStore store;
  final key = List.generate(32, (i) => i + 31);
  final now = DateTime.utc(2026, 10, 22, 12);
  ExactAmount n(int value) => ExactAmount(BigInt.from(value));

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('vital-cutoff-');
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
    expiryDate: expiry,
  );

  test(
    'cutoff includes its exact day and excludes later or unknown dates',
    () async {
      final row = await item('Cutoff medicine');
      await container(
        row,
        label: 'Earlier pack',
        expiry: CivilDate(2026, 9, 30),
      );
      await container(
        row,
        label: 'Cutoff day pack',
        expiry: CivilDate(2026, 10, 22),
      );
      await container(
        row,
        label: 'Later pack',
        expiry: CivilDate(2026, 10, 23),
      );
      await container(row, label: 'No expiry pack');

      final snapshot = await store.stockInventory(
        personId: meId,
        now: now,
        observedZone: 'UTC',
        expiryCutoff: CivilDate(2026, 10, 22),
      );

      expect(snapshot.containers.map((c) => c.label).toSet(), {
        'Earlier pack',
        'Cutoff day pack',
      });
      expect(snapshot.complete, true);
      expect(snapshot.counts.all, 4);
      // The existing observed-day counts are unchanged by the cutoff.
      expect(snapshot.counts.expired, 1);
      expect(snapshot.counts.today, 1);
      expect(snapshot.expiryDay, CivilDate(2026, 10, 22));
    },
  );

  test('an explicit cutoff works without an observed local day', () async {
    final row = await item('No zone cut-off medicine');
    await container(row, label: 'Past pack', expiry: CivilDate(2026, 10, 21));
    await container(row, label: 'Future pack', expiry: CivilDate(2026, 10, 25));
    await container(row, label: 'No expiry pack');

    for (final zone in [null, 'Mars/Olympus']) {
      final snapshot = await store.stockInventory(
        personId: meId,
        now: DateTime.utc(2026, 10, 22, 23, 30),
        observedZone: zone,
        expiryCutoff: CivilDate(2026, 10, 22),
      );
      expect(snapshot.expiryDay, isNull);
      expect(snapshot.counts.expired, isNull);
      expect(snapshot.counts.today, isNull);
      expect(snapshot.containers.single.label, 'Past pack');
      expect(snapshot.complete, true);
    }
  });

  test(
    'cutoff composes with search and item scope past the first page',
    () async {
      final bulk = await item('Bulk cutoff item');
      final other = await item('Other cutoff item');
      for (var index = 0; index < 60; index++) {
        await container(
          bulk,
          label: 'Bulk bottle ${index + 1}',
          expiry: CivilDate(2026, 10, 10),
        );
      }
      await container(
        bulk,
        label: 'Bulk later bottle',
        expiry: CivilDate(2026, 12, 31),
      );
      await container(bulk, label: 'Bulk no expiry bottle');
      await container(
        other,
        label: 'Other matching bottle',
        expiry: CivilDate(2026, 10, 10),
      );

      final filtered = await store.stockInventory(
        personId: meId,
        now: now,
        observedZone: 'UTC',
        search: 'bulk',
        expiryCutoff: CivilDate(2026, 10, 31),
      );
      expect(filtered.containers, hasLength(60));
      expect(
        filtered.containers.every((c) => c.label.startsWith('Bulk bottle ')),
        true,
      );
      expect(filtered.counts.all, 62);

      final scoped = await store.stockInventory(
        personId: meId,
        now: now,
        observedZone: 'UTC',
        itemId: other.id,
        search: 'bottle',
        expiryCutoff: CivilDate(2026, 10, 31),
      );
      expect(scoped.containers.single.label, 'Other matching bottle');
      expect(scoped.counts.all, 1);

      final inclusive = await store.stockInventory(
        personId: meId,
        now: now,
        observedZone: 'UTC',
        itemId: bulk.id,
        expiryCutoff: CivilDate(2026, 10, 10),
      );
      expect(inclusive.containers, hasLength(60));
    },
  );

  test(
    'cutoff composes with a balance filter without hiding overlap',
    () async {
      final row = await item('Overlap cutoff item');
      await container(
        row,
        label: 'Low and expiring',
        opening: n(0),
        expiry: CivilDate(2026, 10, 20),
      );
      await container(
        row,
        label: 'Adequate and expiring',
        opening: n(30),
        expiry: CivilDate(2026, 10, 20),
      );

      final low = await store.stockInventory(
        personId: meId,
        now: now,
        observedZone: 'UTC',
        filter: StockInventoryFilter.low,
        expiryCutoff: CivilDate(2026, 10, 20),
      );
      expect(low.containers.single.label, 'Low and expiring');

      final laterCutoff = await store.stockInventory(
        personId: meId,
        now: now,
        observedZone: 'UTC',
        filter: StockInventoryFilter.low,
        expiryCutoff: CivilDate(2026, 10, 19),
      );
      expect(laterCutoff.containers, isEmpty);
    },
  );

  test(
    'provider passes the cutoff and a locked app yields no inventory',
    () async {
      final row = await item('Provider cutoff item');
      await container(
        row,
        label: 'Provider matching pack',
        expiry: CivilDate(2026, 10, 20),
      );
      await container(
        row,
        label: 'Provider later pack',
        expiry: CivilDate(2026, 11, 20),
      );
      final query = (
        personId: meId,
        itemId: null,
        search: '',
        filter: StockInventoryFilter.all,
        asOf: now,
        zone: 'UTC',
        cutoff: CivilDate(2026, 10, 31),
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

      final unlocked = ProviderContainer(
        overrides: [
          appLockProvider.overrideWith(_Unlocked.new),
          recordStoreProvider.overrideWith((ref) async => store),
        ],
      );
      addTearDown(unlocked.dispose);
      final snapshot = await first(unlocked);
      expect(snapshot.containers.single.label, 'Provider matching pack');
      expect(snapshot.complete, true);

      final locked = ProviderContainer(
        overrides: [
          appLockProvider.overrideWith(_Locked.new),
          recordStoreProvider.overrideWith((ref) async => store),
        ],
      );
      addTearDown(locked.dispose);
      final hidden = await first(locked);
      expect(hidden.containers, isEmpty);
      expect(hidden.counts.all, 0);
      expect(hidden.complete, true);
    },
  );
}
