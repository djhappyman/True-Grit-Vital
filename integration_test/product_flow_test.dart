import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:true_grit_vital/app/storage.dart';
import 'package:true_grit_vital/app/vital_app.dart';
import 'package:true_grit_vital/data/record_store.dart';
import 'package:true_grit_vital/features/recording/record_pages.dart';
import 'package:true_grit_vital/platform/storage_bootstrap.dart';

import 'stock_flow_test.dart' as stock;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // Synthetic data only, through check_android_integration.py. The harness
  // restores the dedicated AVD and encrypted files after the test.
  testWidgets('native product volume, correction, Undo and encrypted reopen', (
    tester,
  ) async {
    const bootstrap = AndroidStorageBootstrap();
    final location = await bootstrap.prepare();
    final store = await RecordStore.open(
      path: location.path,
      key: location.key,
      isNew: location.isNew,
    );
    addTearDown(store.close);
    await bootstrap.activate(location);
    final me = (await store.profileById(meId))!;
    if (!me.adultConfirmed) {
      await store.editProfile(
        commandId: newCommandId(),
        personId: meId,
        expectedRevision: me.revision,
        name: me.name,
        adultConfirmed: true,
      );
    }
    final token = DateTime.now().microsecondsSinceEpoch;
    final adult = await store.createProfile(
      commandId: newCommandId(),
      name: 'Synthetic product adult $token',
      adultConfirmed: true,
    );
    List<ProductComponent> components(String first, String second) => [
      ProductComponent(
        ingredientId: 'synthetic-amber-$token',
        name: 'Synthetic amber original ingredient',
        concentrationText: first,
      ),
      ProductComponent(
        ingredientId: 'synthetic-blue-$token',
        name: 'Synthetic blue original ingredient',
        concentrationText: second,
      ),
    ];
    final item = await store.createItem(
      commandId: newCommandId(),
      personId: adult.id,
      expectedPersonRevision: adult.revision,
      name: 'Synthetic ready-mixed product $token',
      form: 'Liquid',
      unit: 'ml',
      type: 'Medicine',
      productComponents: components('3', '5'),
    );
    final defaultLabel = (await store.productLabel(
      personId: adult.id,
      itemId: item.id,
    ))!;
    final sourceLabel = ProductLabelSnapshot(
      personId: adult.id,
      itemId: item.id,
      revision: defaultLabel.revision,
      components: components('7', '11'),
    );
    final source = await store.createStockContainer(
      commandId: newCommandId(),
      expectedGeneration: store.generation,
      personId: adult.id,
      expectedPersonRevision: adult.revision,
      itemId: item.id,
      label: 'Synthetic product source $token',
      unit: 'ml',
      strength: LabelledStrength(ingredientId: item.id, label: item.name),
      productLabel: sourceLabel,
      opening: ExactAmount.parseEntry('5'),
    );
    await store.saveBrowsingScope(FeedScope.person(adult.id));
    final providers = ProviderContainer(
      overrides: [storeLoaderProvider.overrideWithValue(() async => store)],
    );
    addTearDown(providers.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(container: providers, child: const VitalApp()),
    );
    await stock.waitFor(tester, find.text('Substances'));
    providers.read(routerProvider).go('/record/${item.id}');
    await stock.waitFor(tester, stock.amountField());
    await stock.reveal(tester, stock.amountField());
    await tester.enterText(stock.amountField(), '2');
    await stock.tap(tester, find.byKey(ValueKey('choose-${source.id}')));
    expect(find.text('Default label'), findsOneWidget);
    expect(find.text('Selected label'), findsOneWidget);
    await stock.tap(tester, find.text('Save'));
    await stock.waitFor(
      tester,
      find.descendant(
        of: find.byType(RecordCard),
        matching: find.text(item.name),
      ),
    );
    var record = (await store.records(personId: adult.id))
        .singleWhere((r) => r.itemId == item.id);
    expect(record.personId, adult.id);
    expect(record.product!.volume, ExactAmount.parseEntry('2'));
    expect(record.product!.components.map((c) => c.amount), [
      ExactAmount.parseEntry('14'),
      ExactAmount.parseEntry('22'),
    ]);
    expect(
      record.product!.defaultLabel.components.first.concentrationText,
      '3',
    );
    Future<StoredStockContainer> current() async => (await store
        .stockContainerById(personId: adult.id, containerId: source.id))!;
    expect((await current()).balance.value, ExactAmount.parseEntry('3'));

    providers
        .read(routerProvider)
        .go('/correct/${record.id}?person=${adult.id}');
    await stock.waitFor(tester, stock.amountField());
    await stock.reveal(tester, stock.amountField());
    await tester.enterText(stock.amountField(), '1');
    await stock.tap(tester, find.text('Keep consumed'));
    await stock.tap(tester, find.text('Save'));
    await stock.waitFor(
      tester,
      find.descendant(
        of: find.byType(RecordCard),
        matching: find.text(item.name),
      ),
    );
    record = (await store.recordById(record.id, personId: adult.id))!;
    expect(record.revision, 2);
    expect(record.product!.components.map((c) => c.amount), [
      ExactAmount.parseEntry('7'),
      ExactAmount.parseEntry('11'),
    ]);
    expect((await current()).balance.value, ExactAmount.parseEntry('3'));
    final card = find.ancestor(
      of: find.text(item.name),
      matching: find.byType(RecordCard),
    );
    await stock.tap(
      tester,
      find.descendant(of: card, matching: find.text('Undo')),
    );
    await stock.waitFor(tester, find.byType(AlertDialog));
    await stock.tap(tester, find.text('Keep balance'));
    await stock.waitFor(tester, find.text('Voided'));
    final reopened = await RecordStore.open(
      path: location.path,
      key: location.key,
      isNew: false,
    );
    try {
      final history = await reopened.history(record.id);
      expect(history.length, 3);
      expect(
        history.every(
          (r) =>
              r.personId == adult.id &&
              r.product!.label.components.first.name ==
                  'Synthetic amber original ingredient',
        ),
        true,
      );
      expect(history.map((r) => r.product!.volume), [
        ExactAmount.parseEntry('2'),
        ExactAmount.parseEntry('1'),
        ExactAmount.parseEntry('1'),
      ]);
      expect(
        history.first.product!.components.first.amount,
        ExactAmount.parseEntry('14'),
      );
      expect(
        history.last.product!.components.first.amount,
        ExactAmount.parseEntry('7'),
      );
      expect(history.last.isVoided, true);
      expect(
        (await reopened.stockContainerById(
          personId: adult.id,
          containerId: source.id,
        ))!.balance.value,
        ExactAmount.parseEntry('3'),
      );
      final movements = await reopened.stockMovements(
        personId: adult.id,
        containerId: source.id,
      );
      expect(
        movements.where((m) => m.kind == StockMovementKind.actualUse).length,
        1,
      );
      expect(
        (await reopened.productLabel(
          personId: adult.id,
          itemId: item.id,
        ))!.components.first.concentrationText,
        '3',
      );
    } finally {
      await reopened.close();
    }
  });
}
