import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:true_grit_vital/app/appearance.dart';
import 'package:true_grit_vital/app/vital_app.dart';
import 'package:true_grit_vital/data/record_store.dart';
import 'package:true_grit_vital/features/substances/substance_collection.dart';

import 'vital_app_test.dart' show appTest, launch, runIo, settle, waitForText;

const captures = String.fromEnvironment('VITAL_STOCK_CAPTURES');

Future<SubstanceItem> makeItem(
  RecordStore store,
  String name, {
  String unit = 'ml',
}) async => store.createItem(
  commandId: newCommandId(),
  expectedPersonRevision: (await store.profileById(meId))!.revision,
  name: name,
  form: 'Tablet',
  unit: unit,
  type: 'Supplement',
);

Future<StoredStockContainer> makeContainer(
  RecordStore store,
  SubstanceItem item, {
  required String label,
  String? opening,
  String? threshold,
  bool refill = false,
}) async => store.createStockContainer(
  commandId: newCommandId(),
  personId: meId,
  expectedPersonRevision: (await store.profileById(meId))!.revision,
  expectedGeneration: store.generation,
  itemId: item.id,
  label: label,
  unit: item.unit,
  strength: LabelledStrength(ingredientId: item.id, label: '400 mg'),
  opening: opening == null
      ? null
      : opening == '0'
      ? ExactAmount.zero
      : ExactAmount.parseEntry(opening),
  lowThreshold: threshold == null ? null : ExactAmount.parseEntry(threshold),
  refillEnabled: refill,
);

void main() {
  setUpAll(() async {
    await (FontLoader('StitchSans')
          ..addFont(rootBundle.load('assets/fonts/StitchNotoSans-Regular.ttf'))
          ..addFont(rootBundle.load('assets/fonts/StitchNotoSans-Medium.ttf'))
          ..addFont(rootBundle.load('assets/fonts/StitchNotoSans-SemiBold.ttf'))
          ..addFont(rootBundle.load('assets/fonts/StitchNotoSans-Bold.ttf')))
        .load();
    await (FontLoader('NotoSans')
          ..addFont(rootBundle.load('assets/fonts/NotoSans-Regular.ttf'))
          ..addFont(rootBundle.load('assets/fonts/NotoSans-Bold.ttf')))
        .load();
    await (FontLoader('packages/shadcn_flutter/LucideIcons')..addFont(
          rootBundle.load('packages/shadcn_flutter/lib/icons/LucideIcons.ttf'),
        ))
        .load();
  });

  appTest('stock notices order refill before low and keep exact balances', (
    tester,
  ) async {
    final f = await launch(tester);
    final (refillItem, lowItem, stockedItem) = (await runIo(tester, () async {
      return (
        await makeItem(f.store, 'Telmisartan'),
        await makeItem(f.store, 'Magnesium Glycinate'),
        await makeItem(f.store, 'Vitamin D3 + K2'),
      );
    }))!;
    final refill = (await runIo(
      tester,
      () => makeContainer(
        f.store,
        refillItem,
        label: 'Telmisartan bottle',
        opening: '0',
        refill: true,
      ),
    ))!;
    final low = (await runIo(
      tester,
      () => makeContainer(
        f.store,
        lowItem,
        label: 'Magnesium bottle',
        opening: '1',
        threshold: '2',
      ),
    ))!;
    await runIo(
      tester,
      () => makeContainer(
        f.store,
        stockedItem,
        label: 'Vitamin bottle',
        opening: '40',
      ),
    );
    f.container.read(routerProvider).go('/stock/$meId');
    await settle(tester);
    await waitForText(tester, 'ACTION NEEDED');
    expect(tester.takeException(), isNull);

    final refillCard = find.byKey(ValueKey('stock-attention-${refill.id}'));
    final lowCard = find.byKey(ValueKey('stock-attention-${low.id}'));
    expect(refillCard, findsOneWidget);
    expect(lowCard, findsOneWidget);
    expect(
      tester.getTopLeft(refillCard).dy,
      lessThan(tester.getTopLeft(lowCard).dy),
    );
    expect(find.text('Refill due'), findsWidgets);
    expect(find.text('Low stock'), findsWidgets);
    expect(find.text('Remaining: 0 ml'), findsWidgets);
    expect(find.text('Remaining: 1 ml'), findsWidgets);
    expect(find.text('Forecast not available yet'), findsWidgets);
    expect(find.text('Stocked'), findsOneWidget);

    await tester.ensureVisible(find.byKey(ValueKey('stock-adjust-${low.id}')));
    await settle(tester);
    await tester.tap(find.byKey(ValueKey('stock-adjust-${low.id}')));
    await settle(tester);
    await waitForText(tester, 'Adjust stock');
    expect(find.text('Container name'), findsNothing);
    await runIo(tester, () async {
      final saved = await f.store.stockContainerById(
        personId: meId,
        containerId: low.id,
      );
      expect(saved!.balance.value, ExactAmount.parseEntry('1'));
    });
  });

  appTest('stock Add is real for one substance and names the limit otherwise', (
    tester,
  ) async {
    final f = await launch(tester);
    final item = (await runIo(tester, () => makeItem(f.store, 'Iron')))!;
    await runIo(
      tester,
      () => makeContainer(f.store, item, label: 'Iron bottle', opening: '5'),
    );
    f.container.read(routerProvider).go('/stock/$meId?item=${item.id}');
    await settle(tester);
    await waitForText(tester, 'Add container');
    expect(
      find.text(
        'Pack scanning, batch lots, expiry, capacity and runout forecasts are not available yet.',
      ),
      findsOneWidget,
    );
    await tester.ensureVisible(find.byKey(const ValueKey('stock-add-action')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('stock-add-action')));
    await settle(tester);
    await waitForText(tester, 'Container name');
    expect(find.text('Iron'), findsWidgets);

    f.container.read(routerProvider).go('/stock/$meId');
    await settle(tester);
    await waitForText(tester, 'Substances');
    expect(find.byType(SubstanceCollection), findsNothing);
    await tester.ensureVisible(find.byKey(const ValueKey('stock-add-action')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('stock-add-action')));
    await settle(tester);
    expect(find.byType(SubstanceCollection), findsOneWidget);
    expect(find.text('Only the loaded page is shown.'), findsNothing);
  });

  appTest('stock containers grow for long names at 320px and double text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 740);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final f = await launch(tester);
    final item = (await runIo(
      tester,
      () => makeItem(f.store, 'Magnesium Glycinate Extra Strength'),
    ))!;
    await runIo(
      tester,
      () => makeContainer(
        f.store,
        item,
        label: 'Original amber bottle from the pharmacy cabinet',
        opening: '22',
        threshold: '30',
      ),
    );
    f.container.read(routerProvider).go('/stock/$meId');
    await settle(tester);
    await waitForText(tester, 'Magnesium Glycinate Extra Strength');
    expect(tester.takeException(), isNull);
    expect(
      find.text('Original amber bottle from the pharmacy cabinet'),
      findsWidgets,
    );
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('stock-add-action')),
      300,
    );
    await settle(tester);
    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('stock-add-action')), findsOneWidget);
  });

  appTest('unknown stock stays unknown and is never shown as zero', (
    tester,
  ) async {
    final f = await launch(tester);
    final item = (await runIo(tester, () => makeItem(f.store, 'Ibuprofen')))!;
    await runIo(
      tester,
      () => makeContainer(f.store, item, label: 'Ibuprofen blister'),
    );
    f.container.read(routerProvider).go('/stock/$meId');
    await settle(tester);
    await waitForText(
      tester,
      'Stock unknown. Measure the remaining amount to establish a balance.',
    );
    expect(find.text('Unknown'), findsOneWidget);
    expect(find.textContaining('Remaining: 0'), findsNothing);
  });

  appTest('stock paging states that only the loaded page is shown', (
    tester,
  ) async {
    final f = await launch(tester);
    final item = (await runIo(tester, () => makeItem(f.store, 'Zinc')))!;
    final rows = (await runIo(tester, () async {
      for (var index = 0; index < 51; index++) {
        await makeContainer(
          f.store,
          item,
          label: 'Zinc bottle ${index + 1}',
          opening: '1',
        );
      }
      return f.store.stockContainers(personId: meId, limit: 100);
    }))!;
    final secondPage = rows[50];
    f.container.read(routerProvider).go('/stock/$meId');
    await settle(tester);
    await waitForText(tester, 'Only the loaded page is shown.');
    expect(find.text(secondPage.label), findsNothing);
    await tester.ensureVisible(find.text('Next'));
    await settle(tester);
    await tester.tap(find.text('Next'));
    await settle(tester);
    expect(find.text(secondPage.label), findsOneWidget);
    expect(find.text('Previous'), findsOneWidget);
  });

  for (final theme in [ThemeMode.dark, ThemeMode.light]) {
    appTest('stock vault renders loaded ${theme.name} records safely', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      tester.view.padding = const FakeViewPadding(top: 28, bottom: 24);
      tester.view.viewPadding = const FakeViewPadding(top: 28, bottom: 24);
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final f = await launch(tester);
      final items = (await runIo(tester, () async {
        return [
          for (final name in [
            'Telmisartan',
            'Vitamin D3 + K2',
            'Magnesium Glycinate',
            'Ibuprofen PRN',
          ])
            await makeItem(f.store, name),
        ];
      }))!;
      await runIo(tester, () async {
        await makeContainer(
          f.store,
          items[0],
          label: 'Telmisartan bottle',
          opening: '3',
          threshold: '5',
          refill: true,
        );
        await makeContainer(
          f.store,
          items[1],
          label: 'Vitamin bottle 60ct',
          opening: '54',
        );
        await makeContainer(
          f.store,
          items[2],
          label: 'Magnesium bottle',
          opening: '22',
          threshold: '30',
        );
        await makeContainer(
          f.store,
          items[3],
          label: 'Ibuprofen blister',
          opening: null,
        );
      });
      f.container.read(appearanceProvider.notifier).setMode(theme);
      final boundaryKey = GlobalKey();
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: f.container,
          child: RepaintBoundary(key: boundaryKey, child: const VitalApp()),
        ),
      );
      await settle(tester);
      f.container.read(routerProvider).go('/stock/$meId');
      await settle(tester);
      await waitForText(tester, 'Ibuprofen blister');
      expect(tester.takeException(), isNull);
      if (captures.isNotEmpty) {
        final boundary =
            boundaryKey.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final image = await boundary.toImage();
          try {
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            final file = File('$captures/${theme.name}-stock.png');
            await file.parent.create(recursive: true);
            await file.writeAsBytes(bytes!.buffer.asUint8List());
          } finally {
            image.dispose();
          }
        });
        final position = tester
            .state<ScrollableState>(find.byType(Scrollable).first)
            .position;
        final content = position.maxScrollExtent + position.viewportDimension;
        final viewport = position.viewportDimension;
        tester.view.physicalSize = Size(
          390,
          (844 + math.max(0, content - viewport)).ceilToDouble(),
        );
        await settle(tester);
        await tester.runAsync(() async {
          final image = await boundary.toImage();
          try {
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            final file = File('$captures/${theme.name}-stock-full.png');
            await file.writeAsBytes(bytes!.buffer.asUint8List());
          } finally {
            image.dispose();
          }
        });
        tester.view.physicalSize = const Size(320, 900);
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        await settle(tester);
        expect(tester.takeException(), isNull);
        await tester.runAsync(() async {
          final image = await boundary.toImage();
          try {
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            final file = File('$captures/${theme.name}-stock-narrow.png');
            await file.writeAsBytes(bytes!.buffer.asUint8List());
          } finally {
            image.dispose();
          }
        });
        await tester.scrollUntilVisible(
          find.byKey(const ValueKey('stock-add-action')),
          300,
        );
        await settle(tester);
        expect(tester.takeException(), isNull);
        await tester.runAsync(() async {
          final image = await boundary.toImage();
          try {
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            final file = File(
              '$captures/${theme.name}-stock-narrow-bottom.png',
            );
            await file.writeAsBytes(bytes!.buffer.asUint8List());
          } finally {
            image.dispose();
          }
        });
      }
    });
  }
}
