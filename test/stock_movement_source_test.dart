import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:true_grit_vital/app/app_lock.dart';
import 'package:true_grit_vital/app/appearance.dart';
import 'package:true_grit_vital/app/vital_app.dart';
import 'package:true_grit_vital/data/record_store.dart';
import 'package:true_grit_vital/features/stock/stock_source_link.dart';
import 'package:true_grit_vital/ui/vital_ui.dart';

import 'private_drafts_ui_test.dart' show FakeAuth;
import 'vital_app_test.dart'
    show appTest, launch, runIo, settle, tap, waitForText;

const captures = String.fromEnvironment('VITAL_STOCK_SOURCE_CAPTURES');

final _at = DateTime.utc(2026, 10, 20, 9, 30);

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

Future<UseRecord> _record(
  RecordStore store,
  SubstanceItem item,
  StoredStockContainer container, {
  String amount = '1',
}) async {
  final current = await _current(store, container);
  return store.record(
    commandId: newCommandId(),
    itemId: item.id,
    amount: amount,
    actualAt: _at,
    expectedPersonRevision: (await store.profileById(meId))!.revision,
    stockUse: StockUseInput(
      expectedGeneration: store.generation,
      containerId: container.id,
      expectedContainerRevision: current.revision,
      entered: EnteredStockAmount(amount, 'ml'),
    ),
  );
}

Future<StoredStockContainer> _current(
  RecordStore store,
  StoredStockContainer container,
) async => (await store.stockContainerById(
  personId: meId,
  containerId: container.id,
))!;

Future<void> _move(
  RecordStore store,
  StoredStockContainer container,
  StockMovementKind kind, {
  String? amount,
  ExactAmount? measured,
}) async {
  final current = await _current(store, container);
  await store.addStockMovement(
    commandId: newCommandId(),
    personId: meId,
    expectedPersonRevision: (await store.profileById(meId))!.revision,
    expectedGeneration: store.generation,
    containerId: container.id,
    expectedContainerRevision: current.revision,
    kind: kind,
    amount: amount == null ? null : EnteredStockAmount(amount, 'ml'),
    measured: measured,
  );
}

Future<void> _openAdjustment(
  WidgetTester tester,
  ProviderContainer container,
  StoredStockContainer containerRecord,
) async {
  container
      .read(routerProvider)
      .go('/stock/$meId/adjust/${containerRecord.id}');
  await settle(tester);
  await waitForText(tester, 'Stock history');
}

Finder _openFor(StoredStockMovement movement) =>
    find.byKey(ValueKey('stock-movement-open-${movement.id}'));

Finder _openText(Finder open) =>
    find.descendant(of: open, matching: find.text('Open'));

Future<void> _tapOpen(WidgetTester tester, Finder open) async {
  final text = _openText(open);
  await tester.ensureVisible(text);
  await settle(tester);
  await tester.tap(text);
  await settle(tester);
}

String _location(ProviderContainer container) {
  final configuration = container
      .read(routerProvider)
      .routerDelegate
      .currentConfiguration;
  final last = configuration.matches.lastOrNull;
  return last is ImperativeRouteMatch
      ? last.matches.uri.toString()
      : configuration.uri.toString();
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

  test('source location encodes identities and keeps the nested return', () {
    final nasty = 'record /?#% ü';
    final target = singleStockSourceTarget(nasty);
    final returnLocation = '/stock/me/adjust/box?details=true';
    final location = stockSourceLocation(
      target,
      personId: 'me adult/one',
      returnLocation: returnLocation,
    );
    final uri = Uri.parse(location);
    expect(uri.pathSegments, ['history-source', 'record', nasty]);
    expect(uri.queryParameters['person'], 'me adult/one');
    expect(uri.queryParameters['return'], returnLocation);
    expect(uri.toString(), isNot(contains('me adult/one')));
    expect(uri.toString(), isNot(contains('record /#?')));
    expect(target.kind.name, 'record');
  });

  appTest('recorded movement opens its current dose and Back keeps history', (
    tester,
  ) async {
    final f = await launch(tester);
    final encoded = stockSourceLocation(
      singleStockSourceTarget('record /?#% ü'),
      personId: meId,
      returnLocation: '/stock/$meId',
    );
    final matched = f.container
        .read(routerProvider)
        .configuration
        .findMatch(Uri.parse(encoded));
    expect(matched.isError, isFalse);
    expect(matched.pathParameters['id'], 'record /?#% ü');
    final item = (await runIo(tester, () => _item(f.store, 'Synthetic dose')))!;
    final container = (await runIo(tester, () => _container(f.store, item)))!;
    final record = (await runIo(
      tester,
      () => _record(f.store, item, container),
    ))!;
    await _openAdjustment(tester, f.container, container);
    final movements = (await runIo(
      tester,
      () => f.store.stockMovements(personId: meId, containerId: container.id),
    ))!;
    final actual = movements.singleWhere(
      (movement) => movement.kind == StockMovementKind.actualUse,
    );
    expect(actual.recordId, record.id);
    final open = _openFor(actual);
    await tester.ensureVisible(_openText(open));
    await settle(tester);
    expect(open, findsOneWidget);
    final semantics = tester.getSemantics(
      find.descendant(of: open, matching: find.byType(Button)),
    );
    expect(
      semantics,
      isSemantics(isButton: true, label: 'Open recorded dose', isEnabled: true),
    );

    await _tapOpen(tester, open);
    await waitForText(tester, 'Source');
    final location = Uri.parse(_location(f.container));
    expect(location.path, endsWith('/history-source/record/${record.id}'));
    expect(location.queryParameters['person'], meId);
    expect(
      location.queryParameters['return'],
      '/stock/$meId/adjust/${container.id}',
    );
    // The underlying history also has a Recorded filter.
    expect(find.text('Recorded'), findsWidgets);
    expect(find.text('Synthetic dose'), findsWidgets);

    await tap(tester, 'Back');
    await settle(tester);
    expect(find.text('Stock history'), findsOneWidget);
    expect(open, findsOneWidget);

    final latest = (await runIo(
      tester,
      () => f.store.recordById(record.id, personId: meId),
    ))!;
    await runIo(
      tester,
      () async => f.store.correct(
        commandId: newCommandId(),
        recordId: record.id,
        expectedRevision: latest.revision,
        expectedPersonRevision: (await f.store.profileById(meId))!.revision,
        amount: '2',
        actualAt: _at,
        stockCorrection: PhysicalCorrection.retainPhysicalEffect,
      ),
    );
    await settle(tester);
    await _tapOpen(tester, open);
    await waitForText(tester, 'Source');
    // The underlying history also has a Recorded filter.
    expect(find.text('Recorded'), findsWidgets);
    expect(find.text('Me: 2 ml'), findsOneWidget);
    await tap(tester, 'Back');
    await settle(tester);

    final corrected = (await runIo(
      tester,
      () => f.store.recordById(record.id, personId: meId),
    ))!;
    await runIo(
      tester,
      () async => f.store.voidRecord(
        commandId: newCommandId(),
        recordId: record.id,
        expectedRevision: corrected.revision,
        expectedPersonRevision: (await f.store.profileById(meId))!.revision,
        stockCorrection: PhysicalCorrection.retainPhysicalEffect,
      ),
    );
    await settle(tester);
    await _tapOpen(tester, open);
    await waitForText(tester, 'Voided');
    expect(find.text('Voided'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  appTest('restock, waste, measure and correction never fabricate a source', (
    tester,
  ) async {
    final f = await launch(tester);
    final item = (await runIo(
      tester,
      () => _item(f.store, 'Synthetic movement'),
    ))!;
    final container = (await runIo(tester, () => _container(f.store, item)))!;
    await runIo(tester, () async {
      await _move(f.store, container, StockMovementKind.restock, amount: '4');
      await _move(f.store, container, StockMovementKind.waste, amount: '1');
      await _move(
        f.store,
        container,
        StockMovementKind.reconciliation,
        measured: ExactAmount.parseEntry('9'),
      );
    });
    await _openAdjustment(tester, f.container, container);
    final before = (await runIo(
      tester,
      () => f.store.stockMovements(personId: meId, containerId: container.id),
    ))!;
    for (final movement in before) {
      expect(
        _openFor(movement),
        findsNothing,
        reason: '${movement.kind.name} has no recorded-dose identity',
      );
    }
    expect(find.byType(VitalButton), findsWidgets);

    final record = (await runIo(
      tester,
      () => _record(f.store, item, container),
    ))!;
    await runIo(
      tester,
      () async => f.store.correct(
        commandId: newCommandId(),
        recordId: record.id,
        expectedRevision: record.revision,
        expectedPersonRevision: (await f.store.profileById(meId))!.revision,
        amount: '2',
        actualAt: _at,
        stockCorrection: PhysicalCorrection.reverseRecordedEffect,
      ),
    );
    await settle(tester);
    final after = (await runIo(
      tester,
      () => f.store.stockMovements(personId: meId, containerId: container.id),
    ))!;
    final actual = after.singleWhere(
      (movement) => movement.kind == StockMovementKind.actualUse,
    );
    final correction = after.singleWhere(
      (movement) => movement.kind == StockMovementKind.correction,
    );
    expect(actual.recordId, record.id);
    expect(correction.recordId, isNull);
    expect(correction.reversesId, actual.id);
    expect(_openFor(actual), findsOneWidget);
    expect(_openFor(correction), findsNothing);
    expect(tester.takeException(), isNull);
  });

  appTest('combined movement opens the canonical combined source', (
    tester,
  ) async {
    final f = await launch(tester);
    final item = (await runIo(
      tester,
      () => _item(f.store, 'Synthetic combined'),
    ))!;
    final container = (await runIo(tester, () => _container(f.store, item)))!;
    final first = StockUseInput(
      expectedGeneration: f.store.generation,
      containerId: container.id,
      expectedContainerRevision: container.revision,
      entered: EnteredStockAmount('0.5', 'ml'),
    );
    final group = (await runIo(
      tester,
      () async => f.store.recordCombined(
        CombinedUseCommand(
          commandId: newCommandId(),
          personId: meId,
          expectedGeneration: f.store.generation,
          expectedPersonRevision: (await f.store.profileById(meId))!.revision,
          actualAt: _at,
          components: [
            CombinedUseComponent(
              itemId: item.id,
              expectedItemRevision: item.revision,
              enteredAmount: '0.5',
              stockUse: first,
            ),
            CombinedUseComponent(
              itemId: item.id,
              expectedItemRevision: item.revision,
              enteredAmount: '0.5',
              stockUse: StockUseInput(
                expectedGeneration: f.store.generation,
                containerId: container.id,
                expectedContainerRevision: container.revision,
                entered: EnteredStockAmount('0.5', 'ml'),
              ),
            ),
          ],
        ),
      ),
    ))!;
    await _openAdjustment(tester, f.container, container);
    final movements = (await runIo(
      tester,
      () => f.store.stockMovements(personId: meId, containerId: container.id),
    ))!;
    final uses = movements
        .where((movement) => movement.kind == StockMovementKind.actualUse)
        .toList();
    expect(uses, hasLength(2));
    expect(uses.map((movement) => movement.recordId).toSet(), {
      group.records[0].id,
      group.records[1].id,
    });
    for (final movement in uses) {
      expect(_openFor(movement), findsOneWidget);
    }

    final open = _openFor(uses.first);
    await _tapOpen(tester, open);
    await waitForText(tester, 'Source');
    final location = Uri.parse(_location(f.container));
    expect(
      location.path,
      endsWith('/history-source/combined/${group.actionId}'),
    );
    // The underlying history also has a Recorded filter.
    expect(find.text('Recorded'), findsWidgets);
    expect(
      find.text(
        'Correct or undo every source together. Each source retains its own history.',
      ),
      findsWidgets,
    );
    await tap(tester, 'Back');
    await settle(tester);
    expect(find.text('Stock history'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  appTest('missing source and app lock use the canonical states', (
    tester,
  ) async {
    final f = await launch(tester, auth: FakeAuth());
    final item = (await runIo(tester, () => _item(f.store, 'Locked dose')))!;
    final container = (await runIo(tester, () => _container(f.store, item)))!;
    await runIo(tester, () => _record(f.store, item, container));
    await _openAdjustment(tester, f.container, container);
    final movements = (await runIo(
      tester,
      () => f.store.stockMovements(personId: meId, containerId: container.id),
    ))!;
    final open = _openFor(
      movements.singleWhere(
        (movement) => movement.kind == StockMovementKind.actualUse,
      ),
    );
    await _tapOpen(tester, open);
    await waitForText(tester, 'Source');
    expect(find.text('Locked dose'), findsWidgets);

    await runIo(
      tester,
      () => f.container.read(appLockProvider.notifier).setEnabled(true),
    );
    f.container.read(appLockProvider.notifier).lock();
    await settle(tester);
    expect(find.text('Locked dose'), findsNothing);
    expect(find.text('Source'), findsNothing);
    await tap(tester, 'Unlock');
    await settle(tester);
    await waitForText(tester, 'Source');
    expect(find.text('Locked dose'), findsWidgets);

    f.container
        .read(routerProvider)
        .go('/history-source/record/missing-record?person=$meId');
    await settle(tester);
    await waitForText(
      tester,
      'This source is no longer available. Return to history and refresh.',
    );
    expect(
      find.text(
        'This source is no longer available. Return to history and refresh.',
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  appTest('keyboard opens a page-two source and Back keeps the page', (
    tester,
  ) async {
    final f = await launch(tester);
    final item = (await runIo(
      tester,
      () => _item(f.store, 'Synthetic paging'),
    ))!;
    final container = (await runIo(tester, () => _container(f.store, item)))!;
    final record = (await runIo(
      tester,
      () => _record(f.store, item, container),
    ))!;
    await runIo(tester, () async {
      for (var index = 0; index < 55; index++) {
        await _move(f.store, container, StockMovementKind.restock, amount: '1');
      }
    });
    await _openAdjustment(tester, f.container, container);
    final movements = (await runIo(
      tester,
      () => f.store.stockMovements(personId: meId, containerId: container.id),
    ))!;
    final actual = movements.singleWhere(
      (movement) => movement.kind == StockMovementKind.actualUse,
    );
    expect(movements, hasLength(57));
    final open = _openFor(actual);
    expect(open, findsNothing, reason: 'the saved dose is on the older page');
    await tap(tester, 'Next');
    await waitForText(tester, 'Previous');
    await tester.ensureVisible(_openText(open));
    await settle(tester);
    expect(open, findsOneWidget);

    final node = Focus.maybeOf(tester.element(_openText(open)));
    expect(node, isNotNull);
    node!.requestFocus();
    await settle(tester);
    expect(node.hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await settle(tester);
    await waitForText(tester, 'Source');
    // The underlying history also has a Recorded filter.
    expect(find.text('Recorded'), findsWidgets);

    await tap(tester, 'Back');
    await settle(tester);
    expect(find.text('Stock history'), findsOneWidget);
    expect(find.text('Previous'), findsOneWidget);
    expect(open, findsOneWidget);
    expect(_location(f.container), '/stock/$meId/adjust/${container.id}');
    expect(record.id, actual.recordId);
    expect(tester.takeException(), isNull);
  });

  appTest('nested Back keeps the inventory search and the movement page', (
    tester,
  ) async {
    final f = await launch(tester);
    final item = (await runIo(
      tester,
      () => _item(f.store, 'Synthetic retained'),
    ))!;
    final container = (await runIo(tester, () => _container(f.store, item)))!;
    await runIo(tester, () => _record(f.store, item, container));
    final movements = (await runIo(
      tester,
      () => f.store.stockMovements(
        personId: meId,
        containerId: container.id,
        limit: 51,
      ),
    ))!;
    final open = _openFor(
      movements.singleWhere(
        (movement) => movement.kind == StockMovementKind.actualUse,
      ),
    );
    f.container.read(routerProvider).go('/stock/$meId');
    await waitForText(tester, 'Amber bottle');
    await tester.enterText(find.byType(TextField).first, 'Synthetic');
    await settle(tester);
    await waitForText(tester, 'Amber bottle');
    f.container
        .read(routerProvider)
        .push('/stock/$meId/adjust/${container.id}');
    await settle(tester);
    await waitForText(tester, 'Stock history');
    await _tapOpen(tester, open);
    await waitForText(tester, 'Source');
    await tap(tester, 'Back');
    await settle(tester);
    expect(find.text('Stock history'), findsOneWidget);
    f.container.read(routerProvider).pop();
    await settle(tester);
    expect(find.text('Stock history'), findsNothing);
    expect(
      tester.widget<TextField>(find.byType(TextField).first).controller!.text,
      'Synthetic',
    );
    expect(find.text('Amber bottle'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final theme in [ThemeMode.light, ThemeMode.dark]) {
    appTest('source link fits ${theme.name} at 320 px and double text', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
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
      final item = (await runIo(
        tester,
        () => _item(f.store, 'Long original recorded medicine name'),
      ))!;
      final container = (await runIo(
        tester,
        () => _container(
          f.store,
          item,
          label: 'Long amber bottle from the pharmacy cabinet',
        ),
      ))!;
      await runIo(tester, () => _record(f.store, item, container));
      f.container.read(appearanceProvider.notifier).setMode(theme);
      f.container.read(appearanceProvider.notifier).setReduceMotion(true);
      await _openAdjustment(tester, f.container, container);
      final movements = (await runIo(
        tester,
        () => f.store.stockMovements(personId: meId, containerId: container.id),
      ))!;
      final open = _openFor(
        movements.singleWhere(
          (movement) => movement.kind == StockMovementKind.actualUse,
        ),
      );
      await tester.ensureVisible(_openText(open));
      await settle(tester);
      expect(open, findsOneWidget);
      expect(tester.takeException(), isNull);
      if (captures.isNotEmpty) {
        await _capture(
          tester,
          boundaryKey,
          '$captures/${theme.name}-history-320x2.png',
        );
      }
      await _tapOpen(tester, open);
      await waitForText(tester, 'Source');
      // The underlying history also has a Recorded filter.
      expect(find.text('Recorded'), findsWidgets);
      expect(tester.takeException(), isNull);
      if (captures.isNotEmpty) {
        await _capture(
          tester,
          boundaryKey,
          '$captures/${theme.name}-source-320x2.png',
        );
      }
      await tap(tester, 'Back');
      await settle(tester);
      expect(find.text('Stock history'), findsOneWidget);
      expect(tester.takeException(), isNull);

      // A wider phone keeps the same controls at double text.
      tester.view.physicalSize = const Size(430, 900);
      await settle(tester);
      await tester.ensureVisible(_openText(open));
      await settle(tester);
      await _tapOpen(tester, open);
      await waitForText(tester, 'Source');
      // The underlying history also has a Recorded filter.
      expect(find.text('Recorded'), findsWidgets);
      expect(tester.takeException(), isNull);
      await tap(tester, 'Back');
      await settle(tester);
      expect(find.text('Stock history'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  for (final theme in [ThemeMode.light, ThemeMode.dark]) {
    appTest('capture source link ${theme.name} on a standard phone', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      tester.view.padding = const FakeViewPadding(top: 28, bottom: 24);
      tester.view.viewPadding = const FakeViewPadding(top: 28, bottom: 24);
      addTearDown(tester.view.reset);
      final f = await launch(tester);
      final boundaryKey = GlobalKey();
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: f.container,
          child: RepaintBoundary(key: boundaryKey, child: const VitalApp()),
        ),
      );
      final item = (await runIo(tester, () => _item(f.store, 'Telmisartan')))!;
      final container = (await runIo(
        tester,
        () => _container(f.store, item, label: 'Telmisartan amber bottle'),
      ))!;
      final record = (await runIo(
        tester,
        () => _record(f.store, item, container),
      ))!;
      await runIo(
        tester,
        () async => f.store.correct(
          commandId: newCommandId(),
          recordId: record.id,
          expectedRevision: record.revision,
          expectedPersonRevision: (await f.store.profileById(meId))!.revision,
          amount: '2',
          actualAt: _at,
          stockCorrection: PhysicalCorrection.reverseRecordedEffect,
        ),
      );
      f.container.read(appearanceProvider.notifier).setMode(theme);
      await settle(tester);
      await _openAdjustment(tester, f.container, container);
      final movements = (await runIo(
        tester,
        () => f.store.stockMovements(personId: meId, containerId: container.id),
      ))!;
      final open = _openFor(
        movements.singleWhere(
          (movement) => movement.kind == StockMovementKind.actualUse,
        ),
      );
      await tester.ensureVisible(_openText(open));
      await settle(tester);
      expect(tester.takeException(), isNull);
      if (captures.isNotEmpty) {
        await _capture(
          tester,
          boundaryKey,
          '$captures/${theme.name}-history.png',
        );
      }
      await _tapOpen(tester, open);
      await waitForText(tester, 'Source');
      // The underlying history also has a Recorded filter.
      expect(find.text('Recorded'), findsWidgets);
      if (captures.isNotEmpty) {
        await _capture(
          tester,
          boundaryKey,
          '$captures/${theme.name}-source.png',
        );
      }
      expect(tester.takeException(), isNull);
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
