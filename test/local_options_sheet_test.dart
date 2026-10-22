import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:true_grit_vital/app/vital_app.dart';
import 'package:true_grit_vital/app/app_lock.dart';
import 'package:true_grit_vital/ui/vital_ui.dart';

import 'stock_ui_test.dart' show item;
import 'screen_settings_hub_test.dart' show loadFonts;
import 'private_drafts_ui_test.dart' show FakeAuth;
import 'vital_app_test.dart' show appTest, launch, runIo, settle;

void main() {
  appTest('large-text collection filters open and close across destinations', (
    tester,
  ) async {
    await loadFonts();
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final f = await launch(tester, auth: FakeAuth());
    await runIo(tester, () => item(f.store));
    for (final path in [
      '/stock/me',
      '/history',
      '/substances',
      '/supporting',
    ]) {
      f.container.read(routerProvider).go(path);
      await settle(tester);
      final options = find.byType(VitalLocalOptions).hitTestable().first;
      expect(options, findsOneWidget, reason: path);
      await tester.tap(options);
      await settle(tester);
      final done = find.widgetWithText(Button, 'Done');
      await tester.ensureVisible(done);
      await settle(tester);
      expect(done.hitTestable(), findsOneWidget, reason: path);
      expect(tester.getRect(done).bottom, lessThanOrEqualTo(900), reason: path);
      await tester.tap(done);
      await settle(tester);
      expect(done, findsNothing, reason: path);
      expect(tester.takeException(), isNull, reason: path);
    }
    await tester.tap(find.byType(VitalLocalOptions).hitTestable().first);
    await settle(tester);
    await runIo(
      tester,
      () => f.container.read(appLockProvider.notifier).setEnabled(true),
    );
    f.container.read(appLockProvider.notifier).lock();
    await settle(tester);
    expect(find.text('Unlock'), findsWidgets);
    expect(find.widgetWithText(Button, 'Done'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
