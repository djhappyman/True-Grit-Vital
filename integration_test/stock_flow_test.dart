import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:true_grit_vital/app/storage.dart';
import 'package:true_grit_vital/app/vital_app.dart';
import 'package:true_grit_vital/data/record_store.dart';
import 'package:true_grit_vital/features/recording/record_pages.dart';
import 'package:true_grit_vital/platform/storage_bootstrap.dart';

Future<void> waitFor(WidgetTester tester, Finder target) async {
  for (var attempt = 0; attempt < 100; attempt++) {
    await tester.pump(const Duration(milliseconds: 100));
    if (target.evaluate().isNotEmpty) {
      await tester.pumpAndSettle();
      return;
    }
  }
  fail('Expected stock UI did not appear: $target');
}

Future<void> reveal(WidgetTester tester, Finder target) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
  if (target.evaluate().isEmpty) {
    final scroll = find.byType(Scrollable).last;
    await tester.drag(scroll, const Offset(0, 2500));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(target, 250, scrollable: scroll);
  }
  await tester.ensureVisible(target.last);
  await tester.pumpAndSettle();
}

Future<void> tap(WidgetTester tester, Finder target) async {
  await reveal(tester, target);
  await tester.tap(target.last);
  await tester.pumpAndSettle();
}

Finder amountField([String label = 'Amount']) => find.descendant(
  of: find.byWidgetPredicate(
    (widget) => widget is LabelledInput && widget.label == label,
  ),
  matching: find.byType(TextField),
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // Only through check_android_integration.py on the synthetic vital_api36 AVD.
  // The harness restores the entire encrypted dataset and Keystore afterward.
  testWidgets('native exact replacement, correction and stock reopen', (
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
    var me = (await store.profileById(meId))!;
    if (!me.adultConfirmed) {
      await store.editProfile(
        commandId: newCommandId(),
        personId: meId,
        expectedRevision: me.revision,
        name: me.name,
        adultConfirmed: true,
      );
      me = (await store.profileById(meId))!;
    }
    final name =
        'Synthetic exact stock ${DateTime.now().microsecondsSinceEpoch}';
    final item = await store.createItem(
      commandId: newCommandId(),
      personId: meId,
      expectedPersonRevision: me.revision,
      name: name,
      form: 'Liquid',
      unit: 'mg',
      type: 'Medicine',
    );
    ExactAmount rational(int numerator, [int denominator = 1]) =>
        ExactAmount(BigInt.from(numerator), BigInt.from(denominator));
    Future<StoredStockContainer> source(int concentration) =>
        store.createStockContainer(
          commandId: newCommandId(),
          personId: meId,
          expectedPersonRevision: me.revision,
          expectedGeneration: store.generation,
          itemId: item.id,
          label: 'Synthetic $concentration mg/ml source',
          unit: 'ml',
          strength: LabelledStrength(
            ingredientId: item.id,
            label: '$concentration mg/ml',
            mgPerMl: rational(concentration),
          ),
          opening: rational(2),
          lowThreshold: rational(1),
        );
    final oldSource = await source(3), newSource = await source(7);
    await store.saveBrowsingScope(const FeedScope.me());
    final providers = ProviderContainer(
      overrides: [storeLoaderProvider.overrideWithValue(() async => store)],
    );
    addTearDown(providers.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(container: providers, child: const VitalApp()),
    );
    await waitFor(tester, find.text('Substances'));
    providers.read(routerProvider).go('/record/${item.id}');
    await waitFor(tester, find.byType(DoseForm));
    await waitFor(tester, amountField());
    await reveal(tester, amountField());
    await tester.enterText(amountField(), '5');
    await tap(tester, find.byKey(ValueKey('choose-${oldSource.id}')));
    await tap(tester, find.byKey(ValueKey('choose-${newSource.id}')));
    await tap(tester, find.text('Keep ml'));
    await tap(tester, find.text('Save'));
    await waitFor(tester, find.textContaining('11.666667'));
    var record = (await store.records()).singleWhere(
      (r) => r.itemId == item.id,
    );
    expect(record.actualAmount, rational(35, 3));
    expect(record.actualUnit, 'mg');
    expect(record.originalEntry, '5');
    expect(record.replacement!.keep, FixedReplacementAmount.millilitres);
    Future<StoredStockContainer> current() async => (await store
        .stockContainerById(personId: meId, containerId: newSource.id))!;
    expect((await current()).balance.value, rational(1, 3));
    expect((await current()).isLow, isTrue);

    await tap(tester, find.text('Correct'));
    await waitFor(tester, find.byType(DoseForm));
    final correctionAmount = amountField('Actual amount (optional)');
    await waitFor(tester, correctionAmount);
    await reveal(tester, correctionAmount);
    // Blank means retain the exact current amount; no rounded decimal is saved.
    await tester.enterText(correctionAmount, '');
    final originalTime = record.actualAt;
    final local = originalTime.toLocal();
    final correctedClock = local.hour == 0 && local.minute == 1
        ? '00:02'
        : '00:01';
    final timeField = amountField('Actual time');
    await reveal(tester, timeField);
    await tester.enterText(timeField, correctedClock);
    await tap(tester, find.text('Keep consumed'));
    await tap(tester, find.text('Save'));
    await waitFor(tester, find.textContaining('11.666667'));
    record = (await store.recordById(record.id))!;
    expect(record.revision, 2);
    expect(record.actualAmount, rational(35, 3));
    expect(record.actualAt, isNot(originalTime));
    expect((await current()).balance.value, rational(1, 3));

    await tap(tester, find.text('Undo'));
    await waitFor(tester, find.byType(AlertDialog));
    await tap(tester, find.text('Keep balance'));
    await waitFor(tester, find.text('Voided'));
    expect((await current()).balance.value, rational(1, 3));
    final reopened = await RecordStore.open(
      path: location.path,
      key: location.key,
      isNew: false,
    );
    try {
      final history = await reopened.history(record.id);
      expect(history.length, 3);
      expect(history.map((r) => r.actualAmount), everyElement(rational(35, 3)));
      expect(history.last.isVoided, isTrue);
      expect(
        (await reopened.stockContainerById(
          personId: meId,
          containerId: newSource.id,
        ))!.balance.value,
        rational(1, 3),
      );
      expect(
        (await reopened.stockContainerById(
          personId: meId,
          containerId: oldSource.id,
        ))!.balance.value,
        rational(2),
      );
      final movements = await reopened.stockMovements(
        personId: meId,
        containerId: newSource.id,
      );
      expect(movements.length, 3); // Opening, one use, one reviewed effect.
      expect(
        movements.where((m) => m.kind == StockMovementKind.actualUse).length,
        1,
      );
    } finally {
      await reopened.close();
    }
  });
}
