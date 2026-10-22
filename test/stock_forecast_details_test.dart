import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:true_grit_vital/app/appearance.dart';
import 'package:true_grit_vital/app/app_lock.dart';
import 'package:true_grit_vital/app/vital_app.dart';
import 'package:true_grit_vital/data/record_store.dart';
import 'package:true_grit_vital/features/stock/stock_widgets.dart';
import 'package:true_grit_vital/ui/vital_ui.dart';

import 'private_drafts_ui_test.dart' show FakeAuth;
import 'screen_settings_hub_test.dart' show loadFonts;
import 'design_system_test.dart' show host;
import 'screen_stock_metadata_test.dart' show makeItem, makeContainer, makePlan;
import 'vital_app_test.dart'
    show appTest, launch, runIo, settle, waitForText, tap;

Finder details() => find.descendant(
  of: find.byType(StockForecastDetails).first,
  matching: find.widgetWithText(VitalButton, 'Details'),
);

void main() {
  appTest('forecast details display exact fractions without rounding them', (
    tester,
  ) async {
    final f = await launch(tester);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: f.container,
        child: host(
          StockForecastDetails(
            unit: 'ml',
            projection: StockForecastProjection(
              from: CivilDate(2026, 10, 23),
              through: CivilDate(2026, 10, 24),
              zoneId: 'UTC',
              opening: ExactAmount(BigInt.one),
              planned: ExactAmount(BigInt.two, BigInt.from(3)),
            ),
          ),
        ),
      ),
    );
    await settle(tester);
    await tester.tap(details());
    await settle(tester);
    expect(find.text('Planned use: 2/3 ml'), findsOneWidget);
    expect(find.text('Remaining: 1/3 ml'), findsOneWidget);
    expect(find.textContaining('0.667'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    appTest(
      'forecast disclosure retains exact quantities at 320px/2x in ${mode.name}',
      (tester) async {
        await loadFonts();
        tester.view.physicalSize = const Size(320, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final f = await launch(tester);
        f.container.read(appearanceProvider.notifier).setMode(mode);
        final medicine = (await runIo(
          tester,
          () => makeItem(f.store, 'Example medicine with a long full name'),
        ))!;
        await runIo(tester, () async {
          await makeContainer(
            f.store,
            medicine,
            label: 'Current bottle',
            opening: '2.5',
          );
          await makePlan(f.store, medicine);
        });
        f.container.read(routerProvider).go('/stock/$meId');
        await waitForText(tester, 'Current bottle');
        await settle(tester);
        await tester.ensureVisible(details());
        await settle(tester);
        expect(find.text('Stock now: 2.5 ml'), findsNothing);
        await tester.tap(details());
        await settle(tester);
        await tester.ensureVisible(find.text('Shortfall: 0.5 ml'));
        await settle(tester);
        expect(find.text('Stock now: 2.5 ml'), findsOneWidget);
        expect(find.text('Planned use: 3 ml'), findsOneWidget);
        expect(find.text('Shortfall: 0.5 ml'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(details());
        await settle(tester);
        await tester.tap(details());
        await settle(tester);
        expect(find.text('Stock now: 2.5 ml'), findsNothing);
        expect((await runIo(tester, () => f.store.records()))!, isEmpty);
      },
    );
  }

  appTest(
    'open forecast details hide immediately on lock and remain read-only',
    (tester) async {
      final f = await launch(tester, auth: FakeAuth());
      final medicine = (await runIo(
        tester,
        () => makeItem(f.store, 'Example medicine'),
      ))!;
      final pack = (await runIo(
        tester,
        () => makeContainer(f.store, medicine, label: 'Bottle', opening: '2.5'),
      ))!;
      await runIo(tester, () => makePlan(f.store, medicine));
      f.container.read(routerProvider).go('/stock/$meId');
      await waitForText(tester, 'Bottle');
      await waitForText(tester, 'Run-out');
      await settle(tester);
      await tester.ensureVisible(details());
      await settle(tester);
      await tester.tap(details());
      await settle(tester);
      expect(find.text('Stock now: 2.5 ml'), findsOneWidget);
      await runIo(
        tester,
        () => f.container.read(appLockProvider.notifier).setEnabled(true),
      );
      f.container.read(appLockProvider.notifier).lock();
      await settle(tester);
      expect(find.text('Stock now: 2.5 ml'), findsNothing);
      await tap(tester, 'Unlock');
      await waitForText(tester, 'Bottle');
      final saved = (await runIo(
        tester,
        () => f.store.stockContainerById(personId: meId, containerId: pack.id),
      ))!;
      expect(saved.balance.value, ExactAmount.parseEntry('2.5'));
      expect((await runIo(tester, () => f.store.records()))!, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  appTest('capture exact forecast details in both themes', (tester) async {
    const output = String.fromEnvironment('VITAL_FORECAST_DETAIL_CAPTURES');
    if (output.isEmpty) return;
    await loadFonts();
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final f = await launch(tester);
    final medicine = (await runIo(
      tester,
      () => makeItem(f.store, 'Example medicine'),
    ))!;
    await runIo(tester, () async {
      await makeContainer(
        f.store,
        medicine,
        label: 'Current bottle',
        opening: '2.5',
      );
      await makePlan(f.store, medicine);
    });
    final key = GlobalKey();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: f.container,
        child: RepaintBoundary(key: key, child: const VitalApp()),
      ),
    );
    f.container.read(routerProvider).go('/stock/$meId');
    await waitForText(tester, 'Current bottle');
    await waitForText(tester, 'Run-out');
    await settle(tester);
    await tester.ensureVisible(details());
    await settle(tester);
    await tester.tap(details());
    await settle(tester);
    await Scrollable.ensureVisible(
      tester.element(find.byType(StockForecastLine).first),
      alignment: 0.05,
    );
    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      f.container.read(appearanceProvider.notifier).setMode(mode);
      await settle(tester);
      expect(tester.takeException(), isNull);
      await tester.runAsync(() async {
        final boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final capture = await boundary.toImage();
        try {
          final bytes = await capture.toByteData(
            format: ui.ImageByteFormat.png,
          );
          final file = File('$output/${mode.name}-forecast-details.png');
          await file.parent.create(recursive: true);
          await file.writeAsBytes(bytes!.buffer.asUint8List());
        } finally {
          capture.dispose();
        }
      });
    }
  });
}
