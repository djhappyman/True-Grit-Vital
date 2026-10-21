import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:true_grit_vital/app/appearance.dart';
import 'package:true_grit_vital/app/vital_app.dart';
import 'package:true_grit_vital/ui/vital_ui.dart';

import 'item_setup_ui_test.dart' show createItem, enter;
import 'screen_settings_hub_test.dart' show loadFonts;
import 'settings_vault_ui_test.dart' show capture;
import 'vital_app_test.dart' show appTest, launch, runIo, settle, waitForText;

void main() {
  setUpAll(loadFonts);
  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    appTest('setup and details use shared safe surfaces in ${mode.name}', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      tester.view.padding = const FakeViewPadding(top: 28, bottom: 24);
      tester.view.viewPadding = const FakeViewPadding(top: 28, bottom: 24);
      addTearDown(tester.view.reset);
      final f = await launch(tester);
      final item = (await runIo(
        tester,
        () => createItem(f.store, 'Morning mineral supplement'),
      ))!;
      final key = GlobalKey();
      f.container.read(appearanceProvider.notifier).setMode(mode);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: f.container,
          child: RepaintBoundary(key: key, child: const VitalApp()),
        ),
      );
      final router = f.container.read(routerProvider);
      router.go('/substance/${item.id}/setup');
      await waitForText(tester, 'Setup');
      expect(
        tester.getRect(find.text('Setup').last).top,
        greaterThanOrEqualTo(28),
      );
      await capture(tester, key, '${mode.name}-substance-setup');
      router.go('/substance/${item.id}/details');
      await waitForText(tester, 'Instructions');
      await enter(tester, 'Instructions', 'Store in the original container.');
      await enter(tester, 'Private notes', 'Personal note entered by hand.');
      FocusManager.instance.primaryFocus?.unfocus();
      await settle(tester);
      await tester.ensureVisible(find.widgetWithText(VitalButton, 'Save'));
      await settle(tester);
      expect(
        tester.getSize(find.widgetWithText(VitalButton, 'Save')).height,
        greaterThanOrEqualTo(48),
      );
      await capture(tester, key, '${mode.name}-substance-details');
      expect(tester.takeException(), isNull);
    });
  }
}
