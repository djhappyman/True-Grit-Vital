import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:true_grit_vital/app/appearance.dart';
import 'package:true_grit_vital/app/vital_app.dart';
import 'package:true_grit_vital/data/record_store.dart';
import 'package:true_grit_vital/features/stock/stock_providers.dart';
import 'package:true_grit_vital/ui/stitch_ui.dart';
import 'package:true_grit_vital/ui/vital_ui.dart';

import 'vital_app_test.dart'
    show appTest, launch, runIo, settle, tap, waitForText;

const captures = String.fromEnvironment('VITAL_MOVEMENT_FILTER_CAPTURES');

Future<SubstanceItem> _item(RecordStore store, String name) async =>
    store.createItem(
      commandId: newCommandId(),
      expectedPersonRevision: (await store.profileById(meId))!.revision,
      name: name,
      form: 'liquid',
      unit: 'ml',
      type: 'Medicine',
    );

Future<StoredStockContainer> _container(
  RecordStore store,
  SubstanceItem item, {
  String label = 'Amber bottle',
}) async => store.createStockContainer(
  commandId: newCommandId(),
  personId: meId,
  expectedPersonRevision: (await store.profileById(meId))!.revision,
  expectedGeneration: store.generation,
  itemId: item.id,
  label: label,
  unit: 'ml',
  strength: LabelledStrength(ingredientId: item.id, label: '10 mg/ml'),
  opening: ExactAmount.parseEntry('10'),
);

Future<StoredStockContainer> _move(
  RecordStore store,
  StoredStockContainer container,
  StockMovementKind kind, {
  String? amount,
  ExactAmount? measured,
  String? reason,
}) async {
  final current = (await store.stockContainerById(
    personId: meId,
    containerId: container.id,
  ))!;
  return store.addStockMovement(
    commandId: newCommandId(),
    personId: meId,
    expectedPersonRevision: (await store.profileById(meId))!.revision,
    expectedGeneration: store.generation,
    containerId: container.id,
    expectedContainerRevision: current.revision,
    kind: kind,
    amount: amount == null ? null : EnteredStockAmount(amount, 'ml'),
    measured: measured,
    reason: reason,
  );
}

Future<(StoredStockContainer, UseRecord)> _recordUse(
  RecordStore store,
  SubstanceItem item,
  StoredStockContainer container,
) async {
  final current = (await store.stockContainerById(
    personId: meId,
    containerId: container.id,
  ))!;
  final record = await store.record(
    commandId: newCommandId(),
    itemId: item.id,
    amount: '1',
    actualAt: DateTime.utc(2026, 10, 22, 9),
    expectedPersonRevision: (await store.profileById(meId))!.revision,
    stockUse: StockUseInput(
      expectedGeneration: store.generation,
      containerId: container.id,
      expectedContainerRevision: current.revision,
      entered: EnteredStockAmount('1', 'ml'),
    ),
  );
  return (current, record);
}

Finder _chip(StockMovementKind? kind) =>
    find.byKey(ValueKey('stock-movement-kind-${kind?.name ?? 'all'}'));

bool _selected(WidgetTester tester, StockMovementKind? kind) =>
    tester.widget<StitchButton>(_chip(kind)).primary;

Future<void> _openAdjustment(
  WidgetTester tester,
  ProviderContainer container,
  StoredStockContainer target,
) async {
  container.read(routerProvider).go('/stock/$meId/adjust/${target.id}');
  await settle(tester);
  await waitForText(tester, 'Stock history');
}

Future<void> _choose(WidgetTester tester, StockMovementKind? kind) async {
  await tester.ensureVisible(_chip(kind));
  await settle(tester);
  await tester.tap(_chip(kind));
  await settle(tester);
}

Future<void> _expectOnlyKind(
  WidgetTester tester,
  StockMovementKind? kind,
) async {
  expect(_selected(tester, kind), isTrue, reason: kind?.name ?? 'all');
  for (final other in <StockMovementKind?>[
    null,
    StockMovementKind.actualUse,
    StockMovementKind.restock,
    StockMovementKind.waste,
    StockMovementKind.reconciliation,
    StockMovementKind.correction,
  ]) {
    if (other == kind) continue;
    expect(_selected(tester, other), isFalse);
  }
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

  appTest('kind filters the whole ledger and Reset restores All', (
    tester,
  ) async {
    final f = await launch(tester);
    final saved = (await runIo(tester, () async {
      final item = await _item(f.store, 'Movement filter medicine');
      var container = await _container(f.store, item);
      for (var index = 1; index <= 50; index++) {
        container = await _move(
          f.store,
          container,
          StockMovementKind.waste,
          amount: '1',
          reason: 'Older waste ${index.toString().padLeft(2, '0')}',
        );
      }
      container = await _move(
        f.store,
        container,
        StockMovementKind.restock,
        amount: '4',
        reason: 'Newest restock',
      );
      return container;
    }))!;

    await _openAdjustment(tester, f.container, saved);
    await _expectOnlyKind(tester, null);
    expect(find.text('Newest restock'), findsOneWidget);
    expect(
      find.text('Older waste 01'),
      findsNothing,
      reason: 'the oldest waste row is beyond the displayed All page',
    );
    expect(find.text('Older waste 03'), findsOneWidget);

    await _choose(tester, StockMovementKind.waste);
    await _expectOnlyKind(tester, StockMovementKind.waste);
    expect(
      find.text('Older waste 01'),
      findsOneWidget,
      reason: 'filtering must read the ledger before the 50-row page',
    );
    expect(find.text('Older waste 50'), findsOneWidget);
    expect(find.text('Newest restock'), findsNothing);
    expect(find.text('Waste: -1 ml'), findsWidgets);
    expect(find.text('Labelled strength: 10 mg/ml'), findsWidgets);
    expect(find.widgetWithText(VitalButton, 'Reset'), findsOneWidget);

    await tap(tester, 'Reset');
    await _expectOnlyKind(tester, null);
    expect(find.text('Newest restock'), findsOneWidget);
    expect(find.text('Older waste 01'), findsNothing);
    expect(find.widgetWithText(VitalButton, 'Reset'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  appTest('choosing a kind resets a later movement page', (tester) async {
    final f = await launch(tester);
    final saved = (await runIo(tester, () async {
      final item = await _item(f.store, 'Movement page medicine');
      var container = await _container(f.store, item);
      for (var index = 1; index <= 55; index++) {
        container = await _move(
          f.store,
          container,
          StockMovementKind.waste,
          amount: '1',
          reason: 'Paged waste ${index.toString().padLeft(2, '0')}',
        );
      }
      for (var index = 1; index <= 5; index++) {
        container = await _move(
          f.store,
          container,
          StockMovementKind.restock,
          amount: '1',
          reason: 'Paged restock ${index.toString().padLeft(2, '0')}',
        );
      }
      return container;
    }))!;

    await _openAdjustment(tester, f.container, saved);
    await tap(tester, 'Next');
    await waitForText(tester, 'Previous');
    expect(find.text('Paged waste 01'), findsOneWidget);
    expect(find.text('Paged waste 55'), findsNothing);

    await _choose(tester, StockMovementKind.waste);
    await _expectOnlyKind(tester, StockMovementKind.waste);
    expect(
      find.text('Previous'),
      findsNothing,
      reason: 'the filter starts at the newest kind row, not the old offset',
    );
    expect(find.text('Paged waste 55'), findsOneWidget);
    expect(find.text('Paged waste 01'), findsNothing);
    expect(find.text('Paged restock 01'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  appTest('every kind maps exactly and Open keeps the selected filter', (
    tester,
  ) async {
    final f = await launch(tester);
    final fixture = (await runIo(tester, () async {
      final item = await _item(f.store, 'Exact movement medicine');
      var container = await _container(f.store, item);
      container = await _move(
        f.store,
        container,
        StockMovementKind.restock,
        amount: '4',
        reason: 'Restock note',
      );
      container = await _move(
        f.store,
        container,
        StockMovementKind.waste,
        amount: '1',
        reason: 'Waste note',
      );
      container = await _move(
        f.store,
        container,
        StockMovementKind.reconciliation,
        measured: ExactAmount.parseEntry('8'),
        reason: 'Measure note',
      );
      final (current, record) = await _recordUse(f.store, item, container);
      await f.store.correct(
        commandId: newCommandId(),
        recordId: record.id,
        expectedRevision: record.revision,
        expectedPersonRevision: (await f.store.profileById(meId))!.revision,
        amount: null,
        actualAt: record.actualAt,
        stockCorrection: PhysicalCorrection.reverseRecordedEffect,
      );
      final movements = await f.store.stockMovements(
        personId: meId,
        containerId: current.id,
      );
      return (
        container: current,
        record: record,
        actual: movements.singleWhere(
          (movement) => movement.kind == StockMovementKind.actualUse,
        ),
      );
    }))!;

    await _openAdjustment(tester, f.container, fixture.container);

    await _choose(tester, StockMovementKind.restock);
    await _expectOnlyKind(tester, StockMovementKind.restock);
    expect(find.text('Restock: 4 ml'), findsOneWidget);
    expect(find.text('Restock note'), findsOneWidget);
    expect(find.text('Waste note'), findsNothing);
    expect(find.text('Measure note'), findsNothing);

    await _choose(tester, StockMovementKind.waste);
    await _expectOnlyKind(tester, StockMovementKind.waste);
    expect(find.text('Waste: -1 ml'), findsOneWidget);
    expect(find.text('Waste note'), findsOneWidget);
    expect(find.text('Restock note'), findsNothing);

    await _choose(tester, StockMovementKind.reconciliation);
    await _expectOnlyKind(tester, StockMovementKind.reconciliation);
    expect(find.text('Measure: 10 ml'), findsOneWidget);
    expect(find.text('Measure: 8 ml'), findsOneWidget);
    expect(find.text('Measure note'), findsOneWidget);

    await _choose(tester, StockMovementKind.correction);
    await _expectOnlyKind(tester, StockMovementKind.correction);
    expect(find.textContaining('Correct use'), findsOneWidget);
    expect(find.text('Measure note'), findsNothing);
    expect(find.text('Open'), findsNothing);

    await _choose(tester, StockMovementKind.actualUse);
    await _expectOnlyKind(tester, StockMovementKind.actualUse);
    expect(find.text('Record dose: -1 ml'), findsOneWidget);
    final open = find.byKey(
      ValueKey('stock-movement-open-${fixture.actual.id}'),
    );
    expect(open, findsOneWidget);
    expect(find.text('Waste note'), findsNothing);

    await tester.ensureVisible(open);
    await settle(tester);
    await tap(tester, 'Open');
    await waitForText(tester, 'Source');
    expect(find.text('Exact movement medicine'), findsWidgets);

    await tap(tester, 'Back');
    await settle(tester);
    expect(find.text('Stock history'), findsOneWidget);
    expect(_selected(tester, StockMovementKind.actualUse), isTrue);
    expect(find.text('Record dose: -1 ml'), findsOneWidget);
    expect(find.text('Waste note'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  appTest(
    'clearing, overlay dismissal and another container reset the filter',
    (tester) async {
      final f = await launch(tester);
      final fixture = (await runIo(tester, () async {
        final item = await _item(f.store, 'Two container medicine');
        var first = await _container(f.store, item, label: 'First bottle');
        first = await _move(
          f.store,
          first,
          StockMovementKind.waste,
          amount: '1',
          reason: 'First waste',
        );
        final second = await _container(f.store, item, label: 'Second bottle');
        return (first: first, second: second);
      }))!;

      await _openAdjustment(tester, f.container, fixture.first);
      await _choose(tester, StockMovementKind.waste);
      expect(find.text('First waste'), findsOneWidget);
      final before = (await runIo(
        tester,
        () => f.store.stockMovements(
          personId: meId,
          containerId: fixture.first.id,
        ),
      ))!;
      expect(before, hasLength(2));

      // The scrim is the same guarded task dismissal as Escape. Filter
      // selection is not form work, so it must not write or invent a decision.
      await tester.tapAt(const Offset(10, 10));
      await settle(tester);
      expect(find.text('Stock history'), findsNothing);
      expect(find.byType(VitalTaskFrame), findsNothing);
      final after = (await runIo(
        tester,
        () => f.store.stockMovements(
          personId: meId,
          containerId: fixture.first.id,
        ),
      ))!;
      expect(after.map((movement) => movement.id), before.map((m) => m.id));

      await _openAdjustment(tester, f.container, fixture.first);
      await _expectOnlyKind(tester, null);
      expect(find.text('First waste'), findsOneWidget);

      await _choose(tester, StockMovementKind.waste);
      expect(_selected(tester, StockMovementKind.waste), isTrue);
      f.container.read(routerProvider).go('/stock/$meId');
      await settle(tester);

      await _openAdjustment(tester, f.container, fixture.second);
      await _expectOnlyKind(tester, null);
      expect(find.text('First waste'), findsNothing);
      expect(find.text('Measure: 10 ml'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  appTest('a shrinking dataset clamps a later page back to the first', (
    tester,
  ) async {
    final f = await launch(tester);
    final container = (await runIo(tester, () async {
      final item = await _item(f.store, 'Shrinking dataset medicine');
      return _container(f.store, item);
    }))!;
    final rows = <StoredStockMovement>[
      for (var index = 60; index >= 1; index--)
        StoredStockMovement(
          id: 'synthetic-$index',
          personId: meId,
          containerId: container.id,
          sequence: index,
          kind: StockMovementKind.waste,
          amount: ExactAmount.parseEntry('1'),
          strength: container.strength,
          recordedAt: DateTime.utc(
            2026,
            10,
            22,
            9,
          ).subtract(Duration(minutes: index)),
          reason: 'Dataset row $index',
        ),
    ];
    final scoped = ProviderContainer(
      parent: f.container,
      overrides: [
        stockMovementsProvider.overrideWith(
          (ref, query) async =>
              rows.skip(query.offset).take(51).toList(growable: false),
        ),
      ],
    );
    addTearDown(scoped.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(container: scoped, child: const VitalApp()),
    );
    await settle(tester);
    await _openAdjustment(tester, scoped, container);
    expect(find.text('Dataset row 60'), findsOneWidget);
    expect(find.text('Dataset row 1'), findsNothing);

    await tap(tester, 'Next');
    await waitForText(tester, 'Dataset row 1');
    expect(find.text('Dataset row 60'), findsNothing);

    // A live correction or dataset replacement can shorten the selected
    // ledger. The empty later page must step back instead of stranding the
    // reader on no rows.
    rows.removeRange(3, rows.length);
    scoped.invalidate(
      stockMovementsProvider((
        personId: meId,
        containerId: container.id,
        offset: 50,
      )),
    );
    await settle(tester);
    await waitForText(tester, 'Dataset row 60');
    expect(find.text('Dataset row 58'), findsOneWidget);
    expect(find.text('Dataset row 57'), findsNothing);
    expect(find.text('Next'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  appTest('filter controls stay honest while history loads or fails', (
    tester,
  ) async {
    final f = await launch(tester);
    final container = (await runIo(tester, () async {
      final item = await _item(f.store, 'Pending history medicine');
      return _container(f.store, item);
    }))!;
    final pending = Completer<List<StoredStockMovement>>();
    final scoped = ProviderContainer(
      parent: f.container,
      overrides: [
        stockMovementsProvider.overrideWith((ref, query) => pending.future),
      ],
    );
    addTearDown(scoped.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(container: scoped, child: const VitalApp()),
    );
    await settle(tester);
    await _openAdjustment(tester, scoped, container);
    expect(find.text('Opening records…'), findsOneWidget);
    expect(_chip(null), findsOneWidget);
    await _choose(tester, StockMovementKind.waste);
    expect(_selected(tester, StockMovementKind.waste), isTrue);
    expect(find.widgetWithText(VitalButton, 'Reset'), findsOneWidget);
    expect(find.text('Opening records…'), findsOneWidget);

    pending.completeError(StateError('synthetic movement failure'));
    await settle(tester);
    await waitForText(
      tester,
      'History could not be loaded. Retry to keep your current view.',
    );
    expect(find.text('Retry'), findsOneWidget);
    expect(_selected(tester, StockMovementKind.waste), isTrue);
    expect(find.widgetWithText(VitalButton, 'Reset'), findsOneWidget);
    expect(find.text('No movements match this filter.'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final theme in [ThemeMode.light, ThemeMode.dark]) {
    appTest('capture filtered history ${theme.name} at 390 and 320 x 2', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      tester.view.padding = const FakeViewPadding(top: 28, bottom: 24);
      tester.view.viewPadding = const FakeViewPadding(top: 28, bottom: 24);
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final f = await launch(tester);
      final saved = (await runIo(tester, () async {
        final item = await _item(f.store, 'Telmisartan');
        var container = await _container(
          f.store,
          item,
          label: 'Telmisartan amber bottle',
        );
        for (var index = 1; index <= 50; index++) {
          container = await _move(
            f.store,
            container,
            StockMovementKind.waste,
            amount: '1',
            reason: 'Older measured waste ${index.toString().padLeft(2, '0')}',
          );
        }
        return _move(
          f.store,
          container,
          StockMovementKind.restock,
          amount: '4',
          reason: 'New pack collected',
        );
      }))!;
      f.container.read(appearanceProvider.notifier).setMode(theme);
      final boundaryKey = GlobalKey();
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: f.container,
          child: RepaintBoundary(key: boundaryKey, child: const VitalApp()),
        ),
      );
      await settle(tester);
      await _openAdjustment(tester, f.container, saved);
      await _choose(tester, StockMovementKind.waste);
      await tester.ensureVisible(_chip(StockMovementKind.waste));
      await settle(tester);
      expect(tester.takeException(), isNull);
      if (captures.isNotEmpty) {
        await _capture(
          tester,
          boundaryKey,
          '$captures/${theme.name}-movement-filter.png',
        );
      }

      tester.view.physicalSize = const Size(320, 900);
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      await settle(tester);
      await tester.ensureVisible(_chip(StockMovementKind.waste));
      await settle(tester);
      expect(_selected(tester, StockMovementKind.waste), isTrue);
      expect(tester.takeException(), isNull);
      if (captures.isNotEmpty) {
        await _capture(
          tester,
          boundaryKey,
          '$captures/${theme.name}-movement-filter-320x2.png',
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
