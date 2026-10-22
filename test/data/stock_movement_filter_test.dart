import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:true_grit_vital/app/storage.dart';
import 'package:true_grit_vital/app/app_lock.dart';
import 'package:true_grit_vital/data/record_store.dart';
import 'package:true_grit_vital/features/stock/stock_providers.dart';

class _Unlocked extends AppLockController {
  @override
  AppLockState build() => const AppLockState(ready: true, locked: false);
  void locked(bool value) => state = state.copy(locked: value);
}

void main() {
  late Directory directory;
  late RecordStore store;
  final key = List.generate(32, (i) => i + 71);

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('vital-movement-filter-');
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

  Future<SubstanceItem> item() async => store.createItem(
    commandId: newCommandId(),
    expectedPersonRevision: (await store.profileById(meId))!.revision,
    name: 'Synthetic filter item',
    form: 'liquid',
    unit: 'ml',
    type: 'Medicine',
  );

  Future<StoredStockContainer> current(StoredStockContainer container) async =>
      (await store.stockContainerById(
        personId: meId,
        containerId: container.id,
      ))!;

  Future<StoredStockContainer> move(
    StoredStockContainer container,
    StockMovementKind kind, {
    String? amount,
    ExactAmount? measured,
  }) async {
    final existing = await current(container);
    return store.addStockMovement(
      commandId: newCommandId(),
      personId: meId,
      expectedPersonRevision: (await store.profileById(meId))!.revision,
      expectedGeneration: store.generation,
      containerId: container.id,
      expectedContainerRevision: existing.revision,
      kind: kind,
      amount: amount == null ? null : EnteredStockAmount(amount, 'ml'),
      measured: measured,
    );
  }

  Future<(StoredStockContainer, UseRecord)> recordedUse(
    StoredStockContainer container,
  ) async {
    final existing = await current(container);
    final income = (await store.items()).single;
    final record = await store.record(
      commandId: newCommandId(),
      itemId: income.id,
      amount: '1',
      actualAt: DateTime.utc(2026, 10, 22, 9),
      expectedPersonRevision: (await store.profileById(meId))!.revision,
      stockUse: StockUseInput(
        expectedGeneration: store.generation,
        containerId: container.id,
        expectedContainerRevision: existing.revision,
        entered: EnteredStockAmount('1', 'ml'),
      ),
    );
    return (existing, record);
  }

  test(
    'kind filtering applies to the whole ledger before 50-row paging',
    () async {
      final source = await item();
      final saved = await store.createStockContainer(
        commandId: newCommandId(),
        personId: meId,
        expectedPersonRevision: (await store.profileById(meId))!.revision,
        expectedGeneration: store.generation,
        itemId: source.id,
        label: 'Filter bottle',
        unit: 'ml',
        strength: LabelledStrength(ingredientId: source.id, label: '10 mg/ml'),
        opening: ExactAmount.parseEntry('10'),
      );
      var movement = saved;
      // 55 older waste rows, then five newer restocks, then one recorded use.
      // The first All page therefore contains only part of the waste ledger.
      for (var index = 0; index < 55; index++) {
        movement = await move(movement, StockMovementKind.waste, amount: '1');
      }
      for (var index = 0; index < 5; index++) {
        movement = await move(movement, StockMovementKind.restock, amount: '1');
      }
      final (_, record) = await recordedUse(movement);
      await store.correct(
        commandId: newCommandId(),
        recordId: record.id,
        expectedRevision: record.revision,
        amount: null,
        actualAt: record.actualAt,
        stockCorrection: PhysicalCorrection.reverseRecordedEffect,
      );

      final all = await store.stockMovements(
        personId: meId,
        containerId: saved.id,
        limit: 51,
      );
      expect(all, hasLength(51));
      expect(all.first.kind, StockMovementKind.correction);
      final firstPageWaste = all
          .where((row) => row.kind == StockMovementKind.waste)
          .map((row) => row.sequence)
          .toSet();

      final waste = await store.stockMovements(
        personId: meId,
        containerId: saved.id,
        kind: StockMovementKind.waste,
        limit: 51,
      );
      expect(waste, hasLength(51));
      expect(waste.every((row) => row.kind == StockMovementKind.waste), true);
      expect(
        waste.map((row) => row.sequence).toList(),
        [...waste.map((row) => row.sequence)]..sort((a, b) => b.compareTo(a)),
        reason: 'movement identity remains chronological newest first',
      );
      expect(
        waste.any((row) => !firstPageWaste.contains(row.sequence)),
        true,
        reason: 'a kind from beyond the first All page must be found',
      );

      final second = await store.stockMovements(
        personId: meId,
        containerId: saved.id,
        kind: StockMovementKind.waste,
        limit: 51,
        offset: 50,
      );
      expect(second, hasLength(5));
      expect(second.map((row) => row.kind).toSet(), {StockMovementKind.waste});
      expect(
        second.map((row) => row.sequence).toList(),
        [...second.map((row) => row.sequence)]..sort((a, b) => b.compareTo(a)),
      );

      Future<void> exact(StockMovementKind kind, int count) async {
        final rows = await store.stockMovements(
          personId: meId,
          containerId: saved.id,
          kind: kind,
          limit: 51,
        );
        expect(rows, hasLength(count), reason: kind.name);
        expect(rows.every((row) => row.kind == kind), true, reason: kind.name);
      }

      await exact(StockMovementKind.restock, 5);
      await exact(StockMovementKind.actualUse, 1);
      await exact(StockMovementKind.reconciliation, 1);
      await exact(StockMovementKind.correction, 1);
    },
  );

  test(
    'provider defaults to All, follows a reset and keeps containers separate',
    () async {
      final source = await item();
      Future<StoredStockContainer> open(String label) async =>
          store.createStockContainer(
            commandId: newCommandId(),
            personId: meId,
            expectedPersonRevision: (await store.profileById(meId))!.revision,
            expectedGeneration: store.generation,
            itemId: source.id,
            label: label,
            unit: 'ml',
            strength: LabelledStrength(
              ingredientId: source.id,
              label: '10 mg/ml',
            ),
            opening: ExactAmount.parseEntry('10'),
          );

      var first = await open('First bottle');
      for (var index = 0; index < 49; index++) {
        first = await move(first, StockMovementKind.waste, amount: '1');
      }
      final second = await open('Second bottle');

      final container = ProviderContainer(
        overrides: [
          storeLoaderProvider.overrideWithValue(() async => store),
          appLockProvider.overrideWith(_Unlocked.new),
        ],
      );
      addTearDown(container.dispose);
      final filter = container.listen(
        stockMovementKindFilterProvider(first.id),
        (_, _) {},
      );
      addTearDown(filter.close);
      final query = (personId: meId, containerId: first.id, offset: 0);
      final queryListener = container.listen(
        stockMovementsProvider(query),
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(queryListener.close);

      final defaultRows = await container.read(
        stockMovementsProvider(query).future,
      );
      expect(defaultRows, hasLength(50));
      expect(
        defaultRows.map((row) => row.kind).toSet(),
        containsAll([
          StockMovementKind.waste,
          StockMovementKind.reconciliation,
        ]),
        reason: 'the default callers keep the unfiltered ledger',
      );

      container
          .read(stockMovementKindFilterProvider(first.id).notifier)
          .select(StockMovementKind.waste);
      final filtered = await container.read(
        stockMovementsProvider(query).future,
      );
      expect(filtered, hasLength(49));
      expect(
        filtered.every((row) => row.kind == StockMovementKind.waste),
        true,
      );

      final otherQuery = (personId: meId, containerId: second.id, offset: 0);
      final otherListener = container.listen(
        stockMovementsProvider(otherQuery),
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(otherListener.close);
      final other = await container.read(
        stockMovementsProvider(otherQuery).future,
      );
      expect(other, hasLength(1));
      expect(other.single.kind, StockMovementKind.reconciliation);

      container
          .read(stockMovementKindFilterProvider(first.id).notifier)
          .reset();
      final reset = await container.read(stockMovementsProvider(query).future);
      expect(
        reset.map((row) => row.id).toList(),
        defaultRows.map((row) => row.id).toList(),
      );
      container
          .read(stockMovementKindFilterProvider(first.id).notifier)
          .select(StockMovementKind.waste);
      final lock = container.read(appLockProvider.notifier) as _Unlocked;
      lock.locked(true);
      expect(container.read(stockMovementKindFilterProvider(first.id)), isNull);
      lock.locked(false);
      expect(container.read(stockMovementKindFilterProvider(first.id)), isNull);
    },
  );
}
