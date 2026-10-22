import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:true_grit_vital/app/appearance.dart';
import 'package:true_grit_vital/data/record_store.dart';
import 'package:true_grit_vital/features/reminders/stock_alert_settings.dart';

import '../vital_app_test.dart' show appTest, runIo, settle, tap, waitForText;
import 'reminder_ui_test.dart' show launch;

void main() {
  Future<void> addLowContainer(RecordStore store) async {
    final item = await store.createItem(
      commandId: 'stock-ui-item',
      expectedPersonRevision: 2,
      name: 'Synthetic stock',
      form: 'liquid',
      unit: 'ml',
      type: 'medicine',
    );
    await store.createStockContainer(
      commandId: 'stock-ui-container',
      personId: meId,
      expectedPersonRevision: 2,
      expectedGeneration: store.generation,
      itemId: item.id,
      label: 'Cabinet bottle',
      unit: item.unit,
      strength: LabelledStrength(
        ingredientId: item.id,
        label: '10 mg/ml',
        mgPerMl: ExactAmount(BigInt.from(10)),
      ),
      opening: ExactAmount(BigInt.from(1)),
      lowThreshold: ExactAmount(BigInt.from(5)),
    );
  }

  appTest('stock alerts default off and prepare one private notice', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final fixture = await launch(tester);
    final stockSwitch = find.descendant(
      of: find.byType(StockAlertSettings),
      matching: find.byType(Switch),
    );
    expect(stockSwitch, findsOneWidget);
    expect(tester.widget<Switch>(stockSwitch).value, isFalse);
    expect(
      find.text(
        'Notify about known low or refill states for configured containers. '
        'Off by default; lock-screen text stays private.',
      ),
      findsOneWidget,
    );
    for (final theme in [ThemeMode.light, ThemeMode.dark]) {
      fixture.container.read(appearanceProvider.notifier).setMode(theme);
      await settle(tester);
      expect(find.text('Stock alerts'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
    await runIo(tester, () => addLowContainer(fixture.store));
    await settle(tester);
    expect(tester.widget<Switch>(stockSwitch).value, isFalse);
    await tap(tester, 'Stock alerts');
    await waitForText(tester, 'Synthetic stock');
    expect(tester.widget<Switch>(stockSwitch).value, isTrue);
    expect(find.text('Low stock'), findsOneWidget);
    expect(find.text('Cabinet bottle'), findsOneWidget);
    expect(find.text('Remaining: 1 ml'), findsOneWidget);
    expect(
      find.text('Alert status: Prepared.'),
      findsOneWidget,
      reason: 'prepared is not a delivery claim',
    );
    expect(find.textContaining('Delivered'), findsNothing);
    expect(find.text('Open'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  appTest('stock alerts stay readable at 320 px, double text, no motion', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 740);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    final fixture = await launch(tester);
    fixture.container.read(appearanceProvider.notifier).setMode(ThemeMode.dark);
    await runIo(tester, () async {
      await addLowContainer(fixture.store);
      await fixture.store.setStockAlerts(
        commandId: 'stock-ui-on',
        enabled: true,
        expectedRevision: 0,
      );
    });
    await settle(tester);
    await waitForText(tester, 'Synthetic stock');
    final open = find.text('Open');
    await tester.ensureVisible(open);
    await settle(tester);
    expect(open, findsOneWidget);
    expect(find.text('Low stock'), findsOneWidget);
    expect(find.text('Cabinet bottle'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tap(tester, 'Open');
    await settle(tester);
    // The canonical stock page opens for the affected item.
    expect(find.text('Synthetic stock'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
