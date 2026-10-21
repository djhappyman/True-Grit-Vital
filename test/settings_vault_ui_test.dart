import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:true_grit_vital/app/app_lock.dart';
import 'package:true_grit_vital/app/appearance.dart';
import 'package:true_grit_vital/app/reports.dart';
import 'package:true_grit_vital/app/vital_app.dart';
import 'package:true_grit_vital/data/record_store.dart';
import 'package:true_grit_vital/features/settings/settings_vault.dart';
import 'package:true_grit_vital/features/settings/settings_pages.dart' show SettingsHubGroup;
import 'package:true_grit_vital/ui/vital_ui.dart';

import 'screen_settings_hub_test.dart' show loadFonts;
import 'vital_app_test.dart'
    show appTest, launch, runIo, settle, tap, waitForText;

const captures = String.fromEnvironment('VITAL_VAULT_CAPTURES');

class VaultTestLock extends AppLockController {
  @override
  AppLockState build() => const AppLockState(ready: true, locked: false);
  void hide() => state = const AppLockState(ready: true, locked: true);
}

String? metric(WidgetTester tester, String label) =>
    tester.widget<VitalMetric>(find.widgetWithText(VitalMetric, label)).value;

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

  appTest(
    'Settings counts are live and exact with no fabricated storage value',
    (tester) async {
      final f = await launch(tester);
      f.container.read(routerProvider).go('/settings?group=data');
      await waitForText(tester, 'Recorded doses');
      expect(metric(tester, 'Substances'), '0');
      expect(metric(tester, 'Recorded doses'), '0');
      expect(metric(tester, 'Database files'), isNot('4.2 MB'));
      final record = (await runIo(tester, () async {
        final item = await f.store.createItem(
          commandId: newCommandId(),
          expectedPersonRevision: 2,
          name: 'A real counted item',
          form: 'Tablet',
          unit: 'mg',
          type: 'Test',
        );
        return f.store.record(
          commandId: newCommandId(),
          expectedPersonRevision: 2,
          itemId: item.id,
          amount: '1',
          actualAt: DateTime.utc(2026, 10, 21),
        );
      }))!;
      final timeout = Stopwatch()..start();
      while (metric(tester, 'Recorded doses') != '1' &&
          timeout.elapsed.inSeconds < 15) {
        await settle(tester);
      }
      expect(metric(tester, 'Substances'), '1');
      expect(metric(tester, 'Recorded doses'), '1');
      await runIo(
        tester,
        () => f.store.voidRecord(
          commandId: newCommandId(),
          recordId: record.id,
          expectedRevision: record.revision,
          expectedPersonRevision: 2,
        ),
      );
      while (metric(tester, 'Recorded doses') != '0' &&
          timeout.elapsed.inSeconds < 15) {
        await settle(tester);
      }
      expect(metric(tester, 'Recorded doses'), '0');
    },
  );

  appTest(
    'report shortcuts open reviewed civil dates and return to the Data tab',
    (tester) async {
      final f = await launch(tester);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: f.container,
          child: ProviderScope(
            overrides: [
              settingsDateClockProvider.overrideWithValue(
                () => DateTime(2026, 3, 31),
              ),
            ],
            child: const VitalApp(),
          ),
        ),
      );
      final router = f.container.read(routerProvider);
      router.go('/settings?group=data');
      await waitForText(tester, 'Report dates');
      await tap(tester, '90d');
      expect(find.text('2026-01-01 to 2026-03-31'), findsOneWidget);
      await tap(tester, 'Review');
      await settle(tester);
      expect(router.state.uri.path, '/reports');
      expect(router.state.uri.queryParameters['from'], '2026-01-01');
      expect(router.state.uri.queryParameters['before'], '2026-04-01');
      final selection = f.container.read(reportControllerProvider).selection!;
      expect(selection.includeNotes, false);
      expect(selection.includeAttachments, false);
      expect(selection.fromDate, CivilDate(2026, 1, 1));
      expect(selection.beforeDate, CivilDate(2026, 4, 1));
      await tap(tester, 'Back');
      await waitForText(tester, 'Local data');
      expect(router.state.uri.toString(), '/settings?group=data');
    },
  );

  appTest('failed summary has recovery and private counts disappear on lock', (
    tester,
  ) async {
    final f = await launch(tester);
    var reads = 0;
    final scoped = ProviderContainer(
      parent: f.container,
      overrides: [
        appLockProvider.overrideWith(VaultTestLock.new),
        vaultSummaryProvider.overrideWith(
          (ref) => reads++ == 0
              ? Stream.error(StateError('synthetic read'))
              : Stream.value(
                  const VaultSummary(
                    generation: 'synthetic',
                    substances: 17,
                    doses: 31,
                    supportingRecords: 2,
                    files: 4,
                    databaseBytes: null,
                  ),
                ),
        ),
      ],
    );
    addTearDown(scoped.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(container: scoped, child: const VitalApp()),
    );
    scoped.read(routerProvider).go('/settings?group=data');
    await waitForText(tester, 'Local data could not be read. Try again.');
    expect(find.byType(VitalMetric), findsNothing);
    await tap(tester, 'Retry');
    await waitForText(tester, 'Size unavailable');
    expect(metric(tester, 'Recorded doses'), '31');
    (scoped.read(appLockProvider.notifier) as VaultTestLock).hide();
    await settle(tester);
    expect(find.text('31'), findsNothing);
    expect(find.text('Local data'), findsNothing);
  });

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    appTest(
      'Data summary and shortcuts fit safe areas and double text in ${mode.name}',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(390, 844);
        tester.view.padding = const FakeViewPadding(top: 28, bottom: 24);
        tester.view.viewPadding = const FakeViewPadding(top: 28, bottom: 24);
        addTearDown(tester.view.reset);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final f = await launch(tester);
        final key = GlobalKey();
        f.container.read(appearanceProvider.notifier).setMode(mode);
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: f.container,
            child: RepaintBoundary(key: key, child: const VitalApp()),
          ),
        );
        f.container.read(routerProvider).go('/settings?group=data');
        await waitForText(tester, 'Database files');
        await capture(tester, key, '${mode.name}-settings-data');
        await tester.ensureVisible(find.byType(SettingsReportDates));
        await settle(tester);
        await capture(tester, key, '${mode.name}-report-shortcuts');
        tester.view.physicalSize = const Size(320, 740);
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        await settle(tester);
        final selectedTab = find.descendant(
          of: find.byType(VitalSegments<SettingsHubGroup>),
          matching: find.text('Data'),
        );
        expect(tester.getRect(selectedTab).right, lessThanOrEqualTo(304));
        await tap(tester, '90d');
        final review = find.widgetWithText(VitalButton, 'Review');
        await tester.ensureVisible(review);
        await settle(tester);
        expect(tester.getSize(review).height, greaterThanOrEqualTo(48));
        expect(tester.takeException(), isNull);
        await capture(tester, key, '${mode.name}-report-shortcuts-narrow');
      },
    );
  }
}
