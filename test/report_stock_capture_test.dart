import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:true_grit_vital/app/appearance.dart';
import 'package:true_grit_vital/app/reports.dart';
import 'package:true_grit_vital/app/vital_app.dart';
import 'package:true_grit_vital/data/record_store.dart';

import 'screen_settings_hub_test.dart' show loadFonts;
import 'vital_app_test.dart'
    show appTest, launch, runIo, settle, tap, waitForText;

const captures = String.fromEnvironment('VITAL_REPORT_STOCK_CAPTURES');

Future<void> capture(WidgetTester tester, GlobalKey key, String name) async {
  if (captures.isEmpty) return;
  await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage();
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('$captures/$name.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

void main() {
  setUpAll(loadFonts);
  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    appTest('report stock details review in ${mode.name}', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      tester.view.padding = const FakeViewPadding(top: 28, bottom: 24);
      tester.view.viewPadding = const FakeViewPadding(top: 28, bottom: 24);
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      final f = await launch(tester);
      await runIo(tester, () async {
        final me = (await f.store.profileById(meId))!;
        final item = await f.store.createItem(
          commandId: newCommandId(),
          expectedPersonRevision: me.revision,
          name: 'Synthetic stock item with a long descriptive name',
          form: 'Bottle',
          unit: 'ml',
          type: 'Medicine',
        );
        final container = await f.store.createStockContainer(
          commandId: newCommandId(),
          personId: meId,
          expectedPersonRevision: me.revision,
          expectedGeneration: f.store.generation,
          itemId: item.id,
          label: 'Synthetic bottle from the fridge shelf',
          unit: 'ml',
          strength: LabelledStrength(ingredientId: item.id, label: 'Volume'),
          opening: ExactAmount.parseEntry('10'),
          lot: 'LOT-7',
          expiryDate: CivilDate(2027, 3, 31),
          capacity: ExactAmount(BigInt.one, BigInt.from(3)),
        );
        await f.store.record(
          commandId: newCommandId(),
          expectedPersonRevision: (await f.store.profileById(meId))!.revision,
          itemId: item.id,
          amount: '0.5',
          actualAt: DateTime.now().toUtc(),
          stockUse: StockUseInput(
            expectedGeneration: f.store.generation,
            containerId: container.id,
            expectedContainerRevision: container.revision,
            entered: EnteredStockAmount('0.5', 'ml'),
          ),
        );
      });
      final key = GlobalKey();
      f.container.read(appearanceProvider.notifier).setMode(mode);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: f.container,
          child: RepaintBoundary(key: key, child: const VitalApp()),
        ),
      );
      f.container.read(routerProvider).go('/reports');
      await waitForText(tester, 'Stock details');
      expect(
        f.container.read(reportControllerProvider).selection!.includeStock,
        isFalse,
      );
      await tap(tester, 'Stock details');
      expect(
        f.container.read(reportControllerProvider).selection!.includeStock,
        isTrue,
      );
      await tester.ensureVisible(find.text('Stock details: included'));
      await settle(tester);
      expect(tester.takeException(), isNull);
      await capture(tester, key, '${mode.name}-report-stock');

      tester.view.physicalSize = const Size(320, 740);
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          FakeAccessibilityFeatures(disableAnimations: true);
      await settle(tester);
      await tester.ensureVisible(find.text('Stock details'));
      await settle(tester);
      expect(find.text('Stock details: included'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await capture(tester, key, '${mode.name}-report-stock-narrow');

      tester.view.physicalSize = const Size(430, 932);
      await settle(tester);
      await tester.ensureVisible(find.text('Stock details: included'));
      await settle(tester);
      expect(find.text('Stock details: included'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
