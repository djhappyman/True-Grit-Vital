import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:true_grit_vital/app/appearance.dart';
import 'package:true_grit_vital/app/device_zone.dart';
import 'package:true_grit_vital/app/storage.dart';
import 'package:true_grit_vital/app/vital_app.dart';
import 'package:true_grit_vital/data/record_store.dart';
import 'package:true_grit_vital/features/stock/stock_providers.dart';
import 'package:true_grit_vital/platform/device_zone.dart';
import 'package:true_grit_vital/app/artifact_transfer.dart';
import 'package:true_grit_vital/platform/artifact_transfer.dart';

import 'vital_app_test.dart'
    show appTest, launch, runIo, settle, tap, waitForText;

const captures = String.fromEnvironment('VITAL_STOCK_SORT_CAPTURES');

Future<SubstanceItem> makeItem(RecordStore store, String name) async =>
    store.createItem(
      commandId: newCommandId(),
      expectedPersonRevision: (await store.profileById(meId))!.revision,
      name: name,
      form: 'Tablet',
      unit: 'count',
      type: 'Supplement',
    );

Future<StoredStockContainer> makeContainer(
  RecordStore store,
  SubstanceItem item, {
  required String label,
  CivilDate? expiry,
  String opening = '10',
}) async => store.createStockContainer(
  commandId: newCommandId(),
  personId: meId,
  expectedPersonRevision: (await store.profileById(meId))!.revision,
  expectedGeneration: store.generation,
  itemId: item.id,
  label: label,
  unit: item.unit,
  strength: LabelledStrength(ingredientId: item.id, label: '400 mg'),
  opening: opening == '0' ? ExactAmount.zero : ExactAmount.parseEntry(opening),
  expiryDate: expiry,
);

Finder sortOption(String name) => find.byKey(ValueKey('stock-sort-$name'));

Finder pageScrollable() => find
    .byWidgetPredicate(
      (widget) =>
          widget is Scrollable && widget.axisDirection == AxisDirection.down,
    )
    .first;

Future<void> revealDown(WidgetTester tester, Finder target) async {
  for (var attempt = 0; attempt < 40 && target.evaluate().isEmpty; attempt++) {
    await tester.drag(pageScrollable(), const Offset(0, -600));
    await settle(tester);
  }
  expect(target, findsWidgets);
  await tester.ensureVisible(target.first);
  await settle(tester);
}

Future<void> scrollPageToTop(WidgetTester tester) async {
  for (var attempt = 0; attempt < 40; attempt++) {
    final icon = find.byIcon(LucideIcons.listFilter).first;
    if (icon.hitTestable().evaluate().isNotEmpty) return;
    await tester.drag(pageScrollable(), const Offset(0, 700));
    await settle(tester);
  }
  expect(
    find.byIcon(LucideIcons.listFilter).first.hitTestable(),
    findsOneWidget,
  );
}

Future<void> _revealInFilterSheet(WidgetTester tester, Finder target) async {
  for (
    var attempt = 0;
    attempt < 12 && target.hitTestable().evaluate().isEmpty;
    attempt++
  ) {
    final scrollable = find
        .ancestor(of: target, matching: find.byType(Scrollable))
        .first;
    await tester.drag(scrollable, const Offset(0, -220));
    await settle(tester);
  }
}

Future<void> openFilters(WidgetTester tester) async {
  await tester.tap(find.byIcon(LucideIcons.listFilter).first);
  await settle(tester);
}

Future<void> chooseExpiry(WidgetTester tester) async {
  await openFilters(tester);
  final option = sortOption('expiry');
  await _revealInFilterSheet(tester, option);
  await tester.tap(option);
  await settle(tester);
}

Future<void> dismissFilters(WidgetTester tester) async {
  final done = find.text('Done').last;
  await _revealInFilterSheet(tester, done);
  await tester.tap(done);
  await settle(tester);
}

double topOf(WidgetTester tester, String text) =>
    tester.getTopLeft(find.text(text)).dy;

Finder sortChip() => find.byKey(const ValueKey('stock-sort-chip'));

/// A real store and app container that lets the inventory read be held in a
/// loading or failed state without mocking any screen.
Future<({RecordStore store, ProviderContainer container})> launchWithInventory(
  WidgetTester tester,
  Stream<StockInventorySnapshot> Function(Ref ref, StockInventoryQuery query)
  inventory,
) async {
  final directory = (await runIo(
    tester,
    () => Directory.systemTemp.createTemp('vital-sort-ui-'),
  ))!;
  final store = (await runIo(
    tester,
    () => RecordStore.open(
      path: '${directory.path}/records.db',
      key: List.generate(32, (i) => i + 1),
      isNew: true,
    ),
  ))!;
  await runIo(tester, () async {
    final me = (await store.profileById(meId))!;
    await store.editProfile(
      commandId: 'fixture-adult',
      personId: meId,
      expectedRevision: me.revision,
      name: 'Me',
      adultConfirmed: true,
    );
    await store.saveBrowsingScope(const FeedScope.me());
  });
  final container = ProviderContainer(
    overrides: [
      storeLoaderProvider.overrideWithValue(() async => store),
      observedDeviceZoneProvider.overrideWith(
        (ref) => Stream.value(DeviceZoneObservation.fromId('Europe/London')),
      ),
      artifactTransferGatewayProvider.overrideWithValue(
        const UnsupportedArtifactTransfer(),
      ),
      stockInventoryProvider.overrideWith(inventory),
    ],
  );
  addTearDown(() async {
    container.dispose();
    await runIo(tester, store.close);
    await directory.delete(recursive: true);
  });
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const VitalApp()),
  );
  await settle(tester);
  return (store: store, container: container);
}

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

  appTest('expiry sort orders the whole page and exposes a reset', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final f = await launch(tester);
    await runIo(tester, () async {
      for (var index = 0; index < 55; index++) {
        final row = await makeItem(
          f.store,
          'Medicine ${(index + 1).toString().padLeft(2, '0')}',
        );
        await makeContainer(
          f.store,
          row,
          label: 'Bottle ${(index + 1).toString().padLeft(2, '0')}',
          expiry: CivilDate(2028, 1, 1).addDays(54 - index),
        );
      }
    });
    f.container.read(routerProvider).go('/stock/$meId');
    await settle(tester);
    await waitForText(tester, 'Medicine 01');
    await waitForText(tester, 'Medicine 02');
    expect(
      topOf(tester, 'Medicine 01'),
      lessThan(topOf(tester, 'Medicine 02')),
    );
    expect(find.text('Medicine 55'), findsNothing);

    await chooseExpiry(tester);
    expect(
      f.container.read(stockInventorySortProvider),
      StockInventorySort.expiry,
    );
    await dismissFilters(tester);
    await waitForText(tester, 'Medicine 55');
    await waitForText(tester, 'Medicine 54');
    expect(
      topOf(tester, 'Medicine 55'),
      lessThan(topOf(tester, 'Medicine 54')),
    );
    expect(
      topOf(tester, 'Medicine 54'),
      lessThan(topOf(tester, 'Medicine 53')),
    );
    expect(find.text('Medicine 01'), findsNothing);
    expect(find.text('Medicine 05'), findsNothing);
    expect(sortChip(), findsOneWidget);
    expect(find.text('Sorted by expiry'), findsOneWidget);

    await tap(tester, 'More');
    await revealDown(tester, find.text('Medicine 05'));
    expect(find.text('Medicine 05'), findsOneWidget);
    expect(find.text('Medicine 01'), findsOneWidget);

    // Choosing expiry again after More resets paging to the first 50 rows.
    await scrollPageToTop(tester);
    await chooseExpiry(tester);
    await dismissFilters(tester);
    await waitForText(tester, 'Medicine 55');
    await revealDown(tester, find.text('Medicine 06'));
    expect(find.text('Medicine 05'), findsNothing);
    expect(find.text('Medicine 06'), findsOneWidget);

    // The chip resets both the sort and the page slice.
    await scrollPageToTop(tester);
    await tester.ensureVisible(sortChip());
    await settle(tester);
    await tester.tap(sortChip());
    await settle(tester);
    await scrollPageToTop(tester);
    await waitForText(tester, 'Medicine 01');
    await waitForText(tester, 'Medicine 02');
    expect(sortChip(), findsNothing);
    expect(
      topOf(tester, 'Medicine 01'),
      lessThan(topOf(tester, 'Medicine 02')),
    );
    expect(find.text('Medicine 55'), findsNothing);

    // Clear resets the sort together with the other controls.
    await openFilters(tester);
    await tap(tester, 'Clear');
    await dismissFilters(tester);
    await waitForText(tester, 'Medicine 01');
    expect(sortChip(), findsNothing);
    expect(find.text('Medicine 55'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  appTest('expiry sort composes with search and a balance filter', (
    tester,
  ) async {
    final f = await launch(tester);
    await runIo(tester, () async {
      final alpha = await makeItem(f.store, 'Compose Alpha');
      final beta = await makeItem(f.store, 'Compose Beta');
      final gamma = await makeItem(f.store, 'Compose Gamma');
      final delta = await makeItem(f.store, 'Compose Delta');
      await makeContainer(
        f.store,
        alpha,
        label: 'Alpha adequate bottle',
        expiry: CivilDate(2028, 4, 1),
      );
      await makeContainer(
        f.store,
        beta,
        label: 'Beta low bottle',
        expiry: CivilDate(2027, 3, 1),
        opening: '0',
      );
      await makeContainer(
        f.store,
        gamma,
        label: 'Gamma low bottle',
        expiry: CivilDate(2027, 1, 1),
        opening: '0',
      );
      await makeContainer(
        f.store,
        delta,
        label: 'Delta adequate bottle',
        expiry: CivilDate(2026, 12, 1),
      );
    });
    f.container.read(routerProvider).go('/stock/$meId');
    await settle(tester);
    await waitForText(tester, 'Compose Alpha');
    expect(find.text('Low (2)'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'Compose');
    await settle(tester);
    await tap(tester, 'Low (2)');
    await waitForText(tester, 'Compose Beta');
    await chooseExpiry(tester);
    await dismissFilters(tester);
    await waitForText(tester, 'Compose Gamma');
    expect(
      topOf(tester, 'Compose Gamma'),
      lessThan(topOf(tester, 'Compose Beta')),
    );
    expect(find.text('Compose Alpha'), findsNothing);
    expect(find.text('Compose Delta'), findsNothing);
    expect(find.text('Matching containers (2)'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'Compose Gamma');
    await settle(tester);
    await waitForText(tester, 'Compose Gamma');
    expect(find.text('Compose Beta'), findsNothing);
    expect(find.text('Matching containers (1)'), findsOneWidget);

    await openFilters(tester);
    await tap(tester, 'Clear');
    await dismissFilters(tester);
    await waitForText(tester, 'Compose Alpha');
    expect(find.text('Compose Beta'), findsOneWidget);
    expect(find.textContaining('Matching containers'), findsNothing);
    expect(sortChip(), findsNothing);
    expect(tester.takeException(), isNull);
  });

  appTest('sort options stay honest while inventory loads', (tester) async {
    final pending = StreamController<StockInventorySnapshot>();
    addTearDown(pending.close);
    final f = await launchWithInventory(tester, (ref, query) => pending.stream);
    f.container.read(routerProvider).go('/stock/$meId');
    await settle(tester);
    await waitForText(tester, 'Opening records…');
    await openFilters(tester);
    final option = sortOption('expiry');
    await _revealInFilterSheet(tester, option);
    expect(option.hitTestable(), findsOneWidget);
    await tester.tap(option);
    await settle(tester);
    expect(
      f.container.read(stockInventorySortProvider),
      StockInventorySort.expiry,
    );
    expect(sortChip(), findsOneWidget);
    expect(find.text('No matching containers'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  appTest('sort options survive an inventory failure', (tester) async {
    final f = await launchWithInventory(
      tester,
      (ref, query) => Stream.error(StateError('stock_inventory_failed')),
    );
    f.container.read(routerProvider).go('/stock/$meId');
    await settle(tester);
    await waitForText(
      tester,
      'History could not be loaded. Retry to keep your current view.',
    );
    expect(find.text('Retry'), findsOneWidget);
    await chooseExpiry(tester);
    expect(
      f.container.read(stockInventorySortProvider),
      StockInventorySort.expiry,
    );
    expect(sortChip(), findsOneWidget);
    expect(find.text('No matching containers'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  appTest('narrow sort accepts keyboard entry, Back and reduced motion', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 740);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(top: 24, bottom: 20);
    tester.view.viewPadding = const FakeViewPadding(top: 24, bottom: 20);
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    final f = await launch(tester);
    await runIo(tester, () async {
      final later = await makeItem(f.store, 'Narrow later medicine');
      final earlier = await makeItem(f.store, 'Narrow earlier medicine');
      await makeContainer(
        f.store,
        later,
        label: 'Later narrow bottle',
        expiry: CivilDate(2028, 6, 1),
      );
      await makeContainer(
        f.store,
        earlier,
        label: 'Earlier narrow bottle',
        expiry: CivilDate(2026, 6, 1),
      );
    });
    f.container.read(routerProvider).go('/stock/$meId');
    await settle(tester);
    await waitForText(tester, 'Narrow later medicine');

    await openFilters(tester);
    final option = sortOption('expiry');
    await _revealInFilterSheet(tester, option);
    final focus = Focus.maybeOf(tester.element(find.text('Expiry')));
    expect(focus, isNotNull);
    focus!.requestFocus();
    await settle(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await settle(tester);
    expect(
      f.container.read(stockInventorySortProvider),
      StockInventorySort.expiry,
    );

    await tester.binding.handlePopRoute();
    await settle(tester);
    expect(find.text('Expiry'), findsNothing);
    expect(
      f.container.read(stockInventorySortProvider),
      StockInventorySort.expiry,
    );
    await waitForText(tester, 'Narrow earlier medicine');
    expect(
      topOf(tester, 'Narrow earlier medicine'),
      lessThan(topOf(tester, 'Narrow later medicine')),
    );

    await openFilters(tester);
    await _revealInFilterSheet(tester, sortOption('expiry'));
    Focus.of(tester.element(find.text('Expiry'))).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settle(tester);
    expect(find.text('Expiry'), findsNothing);
    expect(
      f.container.read(stockInventorySortProvider),
      StockInventorySort.expiry,
    );

    await tester.ensureVisible(sortChip());
    await settle(tester);
    expect(sortChip().hitTestable(), findsOneWidget);
    await tester.tap(sortChip());
    await settle(tester);
    expect(sortChip(), findsNothing);
    for (final width in [320.0, 390.0, 430.0]) {
      tester.view.physicalSize = Size(width, 740);
      await settle(tester);
      expect(tester.takeException(), isNull, reason: '$width at double text');
    }
  });

  for (final theme in [ThemeMode.light, ThemeMode.dark]) {
    appTest('capture sort ${theme.name} inventory', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      tester.view.padding = const FakeViewPadding(top: 28, bottom: 24);
      tester.view.viewPadding = const FakeViewPadding(top: 28, bottom: 24);
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final f = await launch(tester);
      await runIo(tester, () async {
        final longLater = await makeItem(
          f.store,
          'Long original amlodipine medicine name',
        );
        final longEarlier = await makeItem(
          f.store,
          'Long original atorvastatin medicine name',
        );
        await makeContainer(
          f.store,
          longLater,
          label: 'Long original amber bottle from the pharmacy cabinet',
          expiry: CivilDate(2028, 7, 31),
        );
        await makeContainer(
          f.store,
          longEarlier,
          label: 'Earlier original white bottle from the pharmacy cabinet',
          expiry: CivilDate(2027, 1, 15),
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
      await waitForText(tester, 'Long original amlodipine medicine name');
      await chooseExpiry(tester);
      if (captures.isNotEmpty) {
        await _revealInFilterSheet(tester, sortOption('expiry'));
        await _capture(
          tester,
          boundaryKey,
          '$captures/${theme.name}-sort-sheet.png',
        );
      }
      await dismissFilters(tester);
      await waitForText(tester, 'Long original atorvastatin medicine name');
      expect(
        topOf(tester, 'Long original atorvastatin medicine name'),
        lessThan(topOf(tester, 'Long original amlodipine medicine name')),
      );
      expect(sortChip(), findsOneWidget);
      expect(tester.takeException(), isNull);
      if (captures.isNotEmpty) {
        await _capture(tester, boundaryKey, '$captures/${theme.name}-sort.png');
        tester.view.physicalSize = const Size(320, 900);
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        await settle(tester);
        expect(tester.takeException(), isNull);
        await _capture(
          tester,
          boundaryKey,
          '$captures/${theme.name}-sort-narrow.png',
        );
      }
    });
  }
}

Future<void> _capture(
  WidgetTester tester,
  GlobalKey boundaryKey,
  String path,
) async {
  final boundary =
      boundaryKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File(path);
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}
