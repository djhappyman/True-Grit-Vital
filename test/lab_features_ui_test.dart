import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:true_grit_vital/app/appearance.dart';
import 'package:true_grit_vital/app/display_preferences.dart';
import 'package:true_grit_vital/features/supporting/screen_panel_widgets.dart';
import 'package:true_grit_vital/app/app_lock.dart';
import 'package:true_grit_vital/app/vital_app.dart';
import 'package:true_grit_vital/data/record_store.dart';
import 'package:true_grit_vital/features/supporting/supporting_sparkline.dart';

import 'supporting_categories_comparison_test.dart' show point;
import 'app_lock_controller_test.dart' show ControlledAuth;
import 'supporting_ui_test.dart' show enter, tap, SupportingOpenLock;
import 'design_system_test.dart' show host;
import 'screen_settings_hub_test.dart' show loadFonts;
import 'settings_vault_ui_test.dart' show capture;
import 'vital_app_test.dart' show appTest, launch, runIo, settle, waitForText;

Future<void> seed(WidgetTester tester, RecordStore store) async {
  for (final row in [
    point('prior', 1, value: '1.25', category: 'Source category'),
    point('viewed', 15, value: '2.0', category: 'Source category'),
    point('newer', 20, value: '99', category: 'Source category'),
  ]) {
    await runIo(
      tester,
      () => store.saveLabPanel(
        SaveLabPanelCommand(
          commandId: 'save-${row.id.id}',
          generation: store.generation,
          expectedPersonRevision: 2,
          panel: row.snapshot as LabPanelSnapshot,
        ),
      ),
    );
  }
}

void main() {
  setUpAll(loadFonts);
  testWidgets('prior result loading and retry do not claim an absent result', (
    tester,
  ) async {
    final viewed = point('viewed', 15, value: '2');
    final request = (
      personId: meId,
      beforeDay: CivilDate(2026, 10, 15),
      displayZone: 'UTC',
    );
    final controller = StreamController<ScreenPanelEarlierWindow>();
    addTearDown(controller.close);
    var reads = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appLockProvider.overrideWith(SupportingOpenLock.new),
          displayZoneProvider.overrideWithValue('UTC'),
          screenPanelEarlierProvider(request).overrideWith(
            (ref) => reads++ == 0
                ? controller.stream
                : Stream.value(
                    const ScreenPanelEarlierWindow(records: [], limited: true),
                  ),
          ),
        ],
        child: host(
          SizedBox(
            width: 320,
            child: ScreenPanelComparison(
              viewed: viewed,
              result: viewed.snapshot.results.single,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Loading previous results.'), findsOneWidget);
    expect(find.textContaining('No comparable'), findsNothing);
    controller.addError(StateError('synthetic read failure'));
    await tester.pumpAndSettle();
    expect(
      find.text('Previous results could not load. Try again.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.textContaining('No comparable earlier'), findsOneWidget);
    expect(find.textContaining('limited to 50 saved records'), findsOneWidget);
    expect(reads, 2);
    expect(tester.takeException(), isNull);
  });
  appTest(
    'panel compares to its own date, discloses identifiers and saves recovered metadata',
    (tester) async {
      final f = await launch(tester, auth: ControlledAuth());
      await seed(tester, f.store);
      final router = f.container.read(routerProvider);
      router.go('/supporting/me/viewed');
      await waitForText(tester, 'Change: +0.75.');
      expect(find.text('Source category'), findsOneWidget);
      expect(find.textContaining('Previous: 1.25 mg/L.'), findsOneWidget);
      expect(find.textContaining('ACC-001'), findsNothing);
      await tap(tester, 'Source details');
      await tap(tester, 'Identifiers');
      expect(find.text('Accession: ACC-001'), findsOneWidget);
      expect(find.text('Report identifier: REPORT/09'), findsOneWidget);
      router.go('/supporting/me/viewed/edit');
      await waitForText(tester, 'Category');
      await enter(tester, 'Category', 'Authored category');
      await tap(tester, 'Source');
      await enter(tester, 'Accession', 'ACC-002');
      await enter(tester, 'Report identifier', 'REPORT/10');
      router.go('/supporting/me/viewed');
      await settle(tester);
      expect((await runIo(tester, () => f.store.drafts()))!, isNotEmpty);
      router.go('/supporting/me/viewed/edit');
      await waitForText(tester, 'Category');
      await tap(tester, 'Source');
      await tap(tester, 'Save');
      await settle(tester);
      final saved = (await runIo(
        tester,
        () => f.store.supportingRecord(meId, 'viewed'),
      ))!;
      expect(saved.snapshot.results.single.category, 'Authored category');
      expect(saved.snapshot.provenance.accessionNumber, 'ACC-002');
      expect(saved.snapshot.provenance.reportIdentifier, 'REPORT/10');
      await runIo(
        tester,
        () => f.container.read(appLockProvider.notifier).setEnabled(true),
      );
      f.container.read(appLockProvider.notifier).lock();
      await settle(tester);
      expect(find.textContaining('ACC-002'), findsNothing);
      expect(find.text('Authored category'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    appTest(
      'lab trends, tables and prior values fit ${mode.name} safe areas and double text',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        tester.view.padding = const FakeViewPadding(top: 28, bottom: 24);
        tester.view.viewPadding = const FakeViewPadding(top: 28, bottom: 24);
        tester.platformDispatcher.accessibilityFeaturesTestValue =
            const FakeAccessibilityFeatures(disableAnimations: true);
        addTearDown(tester.view.reset);
        addTearDown(
          tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
        );
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final f = await launch(tester);
        await seed(tester, f.store);
        f.container.read(appearanceProvider.notifier).setMode(mode);
        final key = GlobalKey();
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: f.container,
            child: RepaintBoundary(key: key, child: const VitalApp()),
          ),
        );
        final router = f.container.read(routerProvider);
        router.go('/supporting');
        await waitForText(tester, 'Source category');
        expect(find.byType(ScreenLabsSparkline), findsOneWidget);
        await tester.ensureVisible(find.text('Source category'));
        await settle(tester);
        await capture(tester, key, '${mode.name}-lab-trends');
        await tap(tester, 'Table');
        expect(find.text('1.25 mg/L'), findsOneWidget);
        expect(find.text('2.0 mg/L'), findsOneWidget);
        tester.view.physicalSize = const Size(320, 740);
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        await settle(tester);
        await tester.ensureVisible(find.text('Table').last);
        await settle(tester);
        await capture(tester, key, '${mode.name}-lab-table-narrow');
        expect(tester.takeException(), isNull);
        router.go('/supporting/me/viewed');
        await waitForText(tester, 'Change: +0.75.');
        await tester.ensureVisible(find.text('Change: +0.75.'));
        await settle(tester);
        await capture(tester, key, '${mode.name}-panel-prior-narrow');
        expect(tester.takeException(), isNull);
      },
    );
  }
}
