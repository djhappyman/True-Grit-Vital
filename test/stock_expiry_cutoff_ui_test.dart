import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
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

const captures = String.fromEnvironment('VITAL_EXPIRY_CUTOFF_CAPTURES');

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
}) async => store.createStockContainer(
  commandId: newCommandId(),
  personId: meId,
  expectedPersonRevision: (await store.profileById(meId))!.revision,
  expectedGeneration: store.generation,
  itemId: item.id,
  label: label,
  unit: item.unit,
  strength: LabelledStrength(ingredientId: item.id, label: '400 mg'),
  opening: ExactAmount.parseEntry('10'),
  expiryDate: expiry,
);

Finder cutoffField() => find.descendant(
  of: find.byKey(const ValueKey('stock-cutoff-field')),
  matching: find.byType(TextField),
);

Future<void> _revealInFilterSheet(WidgetTester tester, Finder target) async {
  for (
    var attempt = 0;
    attempt < 12 && target.hitTestable().evaluate().isEmpty;
    attempt++
  ) {
    final scrollable = find
        .ancestor(of: target, matching: find.byType(Scrollable))
        .first;
    await tester.drag(scrollable, const Offset(0, -280));
    await settle(tester);
  }
}

Future<void> applyCutoff(WidgetTester tester, String date) async {
  await tester.tap(find.byIcon(LucideIcons.listFilter).first);
  await settle(tester);
  await _revealInFilterSheet(tester, cutoffField());
  await tester.enterText(cutoffField(), date);
  await settle(tester);
  final apply = find.byKey(const ValueKey('stock-cutoff-apply'));
  await _revealInFilterSheet(tester, apply);
  await tester.tap(apply);
  await settle(tester);
}

Future<void> dismissFilters(WidgetTester tester) async {
  final done = find.text('Done').last;
  await _revealInFilterSheet(tester, done);
  await tester.tap(done);
  await settle(tester);
}

/// A real store and app container that lets the inventory read be held in a
/// loading or failed state without mocking any screen.
Future<({RecordStore store, ProviderContainer container})> launchWithInventory(
  WidgetTester tester,
  Stream<StockInventorySnapshot> Function(Ref ref, StockInventoryQuery query)
  inventory,
) async {
  final directory = (await runIo(
    tester,
    () => Directory.systemTemp.createTemp('vital-cutoff-ui-'),
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

  appTest('cutoff includes the chosen day, validates and clears', (
    tester,
  ) async {
    final f = await launch(tester);
    await runIo(tester, () async {
      final item = await makeItem(f.store, 'Cutoff medicine');
      await makeContainer(
        f.store,
        item,
        label: 'Earlier bottle',
        expiry: CivilDate(2027, 1, 10),
      );
      await makeContainer(
        f.store,
        item,
        label: 'Cutoff bottle',
        expiry: CivilDate(2027, 1, 11),
      );
      await makeContainer(
        f.store,
        item,
        label: 'Later bottle',
        expiry: CivilDate(2027, 1, 12),
      );
      await makeContainer(f.store, item, label: 'No expiry bottle');
    });
    f.container.read(routerProvider).go('/stock/$meId');
    await settle(tester);
    await waitForText(tester, 'No expiry bottle');

    await applyCutoff(tester, '2027-01-11');
    await waitForText(tester, 'Earlier bottle');
    expect(find.text('Cutoff bottle'), findsOneWidget);
    expect(find.text('Later bottle'), findsNothing);
    expect(find.text('No expiry bottle'), findsNothing);
    expect(find.text('Matching containers (2)'), findsOneWidget);
    expect(
      find.text('Expiry 2027-01-11 or earlier'),
      findsWidgets,
      reason: 'the full cutoff stays visible in the disclosure and chip',
    );

    await tester.enterText(cutoffField(), '2027-02-30');
    await settle(tester);
    final apply = find.byKey(const ValueKey('stock-cutoff-apply'));
    await tester.ensureVisible(apply);
    await settle(tester);
    await tester.tap(apply);
    await settle(tester);
    expect(find.text('Enter a date as YYYY-MM-DD.'), findsOneWidget);
    expect(find.text('Earlier bottle'), findsOneWidget);
    expect(find.text('Later bottle'), findsNothing);

    await tap(tester, 'Clear');
    await waitForText(tester, 'No expiry bottle');
    expect(find.text('Later bottle'), findsOneWidget);
    expect(find.textContaining(' or earlier'), findsNothing);

    await dismissFilters(tester);
    await applyCutoff(tester, '2027-01-10');
    await dismissFilters(tester);
    await waitForText(tester, 'Earlier bottle');
    expect(find.byKey(const ValueKey('stock-cutoff-chip')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('stock-cutoff-chip')));
    await settle(tester);
    await waitForText(tester, 'No expiry bottle');
    expect(find.text('Later bottle'), findsOneWidget);
    expect(find.byKey(const ValueKey('stock-cutoff-chip')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  appTest('cutoff composes with search and pages past fifty rows', (
    tester,
  ) async {
    final f = await launch(tester);
    final item = (await runIo(
      tester,
      () => makeItem(f.store, 'Bulk cutoff medicine'),
    ))!;
    await runIo(tester, () async {
      for (var index = 0; index < 55; index++) {
        await makeContainer(
          f.store,
          item,
          label: 'Bulk bottle ${index + 1}',
          expiry: CivilDate(2027, 1, 10),
        );
      }
      await makeContainer(
        f.store,
        item,
        label: 'Later bottle',
        expiry: CivilDate(2028, 1, 10),
      );
      await makeContainer(f.store, item, label: 'No expiry bottle');
    });
    f.container.read(routerProvider).go('/stock/$meId');
    await settle(tester);
    await waitForText(tester, 'Only the loaded page is shown.');

    await applyCutoff(tester, '2027-01-31');
    await dismissFilters(tester);
    await waitForText(tester, 'Only the loaded page is shown.');

    final snapshot = (await runIo(
      tester,
      () => f.store.stockInventory(
        personId: meId,
        now: DateTime.now().toUtc(),
        observedZone: 'Europe/London',
        expiryCutoff: CivilDate(2027, 1, 31),
      ),
    ))!;
    expect(snapshot.containers, hasLength(55));
    final beyondFirstPage = snapshot.containers[50];
    expect(find.text(beyondFirstPage.label), findsNothing);
    expect(find.text('Later bottle'), findsNothing);
    expect(find.text('No expiry bottle'), findsNothing);

    await tap(tester, 'More');
    expect(find.text(beyondFirstPage.label), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'Bulk bottle 17');
    await settle(tester);
    await waitForText(tester, 'Bulk bottle 17');
    expect(find.text('Bulk bottle 18'), findsNothing);
    expect(find.text('Only the loaded page is shown.'), findsNothing);

    await tester.enterText(find.byType(TextField).first, 'Later bottle');
    await settle(tester);
    await waitForText(tester, 'No matching containers');
    expect(
      find.text('No saved container expiry is on or before 2027-01-31.'),
      findsOneWidget,
    );
    await tap(tester, 'Clear');
    await waitForText(tester, 'Later bottle');
    expect(find.byKey(const ValueKey('stock-cutoff-chip')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  appTest('inventory loading keeps the cutoff controls honest', (tester) async {
    final pending = StreamController<StockInventorySnapshot>();
    addTearDown(pending.close);
    final f = await launchWithInventory(tester, (ref, query) => pending.stream);
    f.container.read(routerProvider).go('/stock/$meId');
    await settle(tester);
    await waitForText(tester, 'Opening records…');
    await tester.tap(find.byIcon(LucideIcons.listFilter).first);
    await settle(tester);
    await tester.ensureVisible(cutoffField());
    await settle(tester);
    await tester.enterText(cutoffField(), '2027-01-31');
    final apply = find.byKey(const ValueKey('stock-cutoff-apply'));
    await tester.ensureVisible(apply);
    await settle(tester);
    await tester.tap(apply);
    await settle(tester);
    // A cutoff can be chosen while the whole-collection read is pending, but no
    // container or count is claimed until the read arrives.
    expect(find.text('Expiry 2027-01-31 or earlier'), findsWidgets);
    expect(find.text('Active containers'), findsNothing);
    expect(find.text('No matching containers'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  appTest('inventory failure leaves cutoff state to retry', (tester) async {
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
    expect(find.text('No matching containers'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final theme in [ThemeMode.light, ThemeMode.dark]) {
    appTest('cutoff fits ${theme.name} at 320 px and double text', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 740);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final f = await launch(tester);
      final boundaryKey = GlobalKey();
      if (captures.isNotEmpty) {
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: f.container,
            child: RepaintBoundary(key: boundaryKey, child: const VitalApp()),
          ),
        );
      }
      await runIo(tester, () async {
        final item = await makeItem(
          f.store,
          'Long expiry cutoff medicine name',
        );
        await makeContainer(
          f.store,
          item,
          label: 'Long original amber bottle from the pharmacy cabinet',
          expiry: CivilDate(2027, 1, 10),
        );
        await makeContainer(
          f.store,
          item,
          label: 'Later narrow bottle',
          expiry: CivilDate(2027, 1, 12),
        );
      });
      f.container.read(appearanceProvider.notifier).setMode(theme);
      f.container.read(routerProvider).go('/stock/$meId');
      await settle(tester);
      await waitForText(tester, 'Later narrow bottle');
      await applyCutoff(tester, '2027-01-11');
      if (captures.isNotEmpty) {
        await _revealInFilterSheet(tester, cutoffField());
        await _capture(
          tester,
          boundaryKey,
          '$captures/${theme.name}-cutoff-sheet-narrow.png',
        );
      }
      await dismissFilters(tester);
      await settle(tester);
      await waitForText(
        tester,
        'Long original amber bottle from the pharmacy cabinet',
      );
      expect(find.text('Later narrow bottle'), findsNothing);
      expect(find.text('Expiry 2027-01-11 or earlier'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  for (final theme in [ThemeMode.light, ThemeMode.dark]) {
    appTest('capture cutoff ${theme.name} inventory', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      tester.view.padding = const FakeViewPadding(top: 28, bottom: 24);
      tester.view.viewPadding = const FakeViewPadding(top: 28, bottom: 24);
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final f = await launch(tester);
      await runIo(tester, () async {
        final earlier = await makeItem(f.store, 'Telmisartan');
        final cutoff = await makeItem(f.store, 'Vitamin D3 + K2');
        final later = await makeItem(f.store, 'Magnesium Glycinate');
        await makeContainer(
          f.store,
          earlier,
          label: 'Telmisartan amber bottle',
          expiry: CivilDate(2027, 1, 10),
        );
        await makeContainer(
          f.store,
          cutoff,
          label: 'Vitamin bottle 60ct',
          expiry: CivilDate(2027, 1, 11),
        );
        await makeContainer(
          f.store,
          later,
          label: 'Magnesium refill pouch',
          expiry: CivilDate(2028, 4, 30),
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
      await waitForText(tester, 'Magnesium refill pouch');
      await applyCutoff(tester, '2027-01-11');
      await dismissFilters(tester);
      await waitForText(tester, 'Telmisartan amber bottle');
      expect(find.text('Magnesium refill pouch'), findsNothing);
      expect(tester.takeException(), isNull);
      if (captures.isNotEmpty) {
        await _capture(
          tester,
          boundaryKey,
          '$captures/${theme.name}-cutoff.png',
        );
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
        await _capture(
          tester,
          boundaryKey,
          '$captures/${theme.name}-cutoff-full.png',
        );
        tester.view.physicalSize = const Size(320, 900);
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        await settle(tester);
        expect(tester.takeException(), isNull);
        await _capture(
          tester,
          boundaryKey,
          '$captures/${theme.name}-cutoff-narrow.png',
        );
      }
    });
  }

  appTest(
    'narrow filters open, accept keyboard entry, close and reopen with reduced motion',
    (tester) async {
      tester.view.physicalSize = const Size(320, 740);
      tester.view.devicePixelRatio = 1;
      tester.view.padding = const FakeViewPadding(top: 24, bottom: 20);
      tester.view.viewPadding = const FakeViewPadding(top: 24, bottom: 20);
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      final f = await launch(tester);
      await runIo(tester, () async {
        final medicine = await makeItem(f.store, 'Keyboard cutoff medicine');
        await makeContainer(
          f.store,
          medicine,
          label: 'Matching bottle',
          expiry: CivilDate(2027, 1, 11),
        );
      });
      f.container.read(routerProvider).go('/stock/$meId');
      await waitForText(tester, 'Matching bottle');
      await tester.tap(find.byIcon(LucideIcons.listFilter).first);
      await settle(tester);
      await _revealInFilterSheet(tester, cutoffField());
      expect(cutoffField().hitTestable(), findsOneWidget);
      await tester.enterText(cutoffField(), '2027-01-11');
      tester.view.viewInsets = const FakeViewPadding(bottom: 280);
      await settle(tester);
      final apply = find.byKey(const ValueKey('stock-cutoff-apply'));
      await _revealInFilterSheet(tester, apply);
      expect(apply.hitTestable(), findsOneWidget);
      expect(tester.getRect(apply).bottom, lessThanOrEqualTo(460));
      await tester.tap(apply);
      await settle(tester);
      tester.view.viewInsets = const FakeViewPadding();
      await settle(tester);
      await dismissFilters(tester);
      expect(cutoffField(), findsNothing);
      await applyCutoff(tester, '2027-01-10');
      await dismissFilters(tester);
      await waitForText(tester, 'No matching containers');
      expect(tester.takeException(), isNull);
    },
  );
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
