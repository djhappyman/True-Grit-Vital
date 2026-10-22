import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:true_grit_vital/app/appearance.dart';
import 'package:true_grit_vital/app/reports.dart';
import 'package:true_grit_vital/app/vital_app.dart';

import 'report_stock_capture_test.dart' show capture;
import 'screen_settings_hub_test.dart' show loadFonts;
import 'vital_app_test.dart' show appTest, launch, settle, tap, waitForText;

void main() {
  setUpAll(loadFonts);
  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    appTest('plan output consent in ${mode.name}', (tester) async {
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
      f.container.read(appearanceProvider.notifier).setMode(mode);
      final key = GlobalKey();
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: f.container,
          child: RepaintBoundary(key: key, child: const VitalApp()),
        ),
      );
      f.container.read(routerProvider).go('/reports');
      await waitForText(tester, 'Private notes');
      await tester.ensureVisible(find.text('Private notes'));
      await settle(tester);
      expect(
        f.container.read(reportControllerProvider).selection!.includeNotes,
        isFalse,
      );
      await tap(tester, 'Private notes');
      expect(
        f.container.read(reportControllerProvider).selection!.includeNotes,
        isTrue,
      );
      expect(
        find.textContaining('original plan instructions'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await capture(tester, key, '${mode.name}-plan-report');

      tester.view.physicalSize = const Size(320, 740);
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          FakeAccessibilityFeatures(disableAnimations: true);
      await settle(tester);
      await tester.ensureVisible(find.text('Private notes'));
      await settle(tester);
      expect(
        f.container.read(reportControllerProvider).selection!.includeNotes,
        isTrue,
      );
      expect(tester.takeException(), isNull);
      await capture(tester, key, '${mode.name}-plan-report-narrow');

      tester.view.physicalSize = const Size(430, 932);
      await settle(tester);
      expect(tester.takeException(), isNull);
      f.container.read(routerProvider).go('/exports');
      await waitForText(tester, 'Notes');
      await tester.ensureVisible(find.text('Notes'));
      await settle(tester);
      expect(find.textContaining('saved plan instructions'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await capture(tester, key, '${mode.name}-plan-export-large');
    });
  }
}
