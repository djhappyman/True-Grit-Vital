import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:true_grit_vital/app/vital_app.dart';
import 'package:true_grit_vital/app/app_lock.dart';
import 'package:true_grit_vital/ui/vital_ui.dart';

import 'stock_ui_test.dart' show item;
import 'screen_settings_hub_test.dart' show loadFonts;
import 'private_drafts_ui_test.dart' show FakeAuth;
import 'vital_app_test.dart' show appTest, launch, runIo, settle;
import 'design_system_test.dart' show host;

void main() {
  testWidgets('wide options close on Escape and return keyboard focus', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        const VitalLocalOptions(
          label: 'Filters',
          content: Text('Local choices'),
        ),
      ),
    );
    final options = find.byType(VitalLocalOptions);
    final triggerFocus = Focus.of(
      tester.element(
        find.descendant(of: options, matching: find.byType(Icon)).first,
      ),
    );
    for (var i = 0; i < 2; i++) {
      await tester.tap(options);
      await tester.pumpAndSettle();
      expect(find.text('Local choices'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('Local choices'), findsNothing);
      expect(triggerFocus.hasFocus, isTrue);
    }
    expect(tester.takeException(), isNull);
  });

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
      final triggerFocus = Focus.of(
        tester.element(
          find.descendant(of: options, matching: find.byType(Icon)).first,
        ),
      );
      triggerFocus.requestFocus();
      await tester.pump();
      await tester.tap(options);
      await settle(tester);
      expect(done, findsOneWidget, reason: path);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await settle(tester);
      expect(done, findsNothing, reason: path);
      expect(triggerFocus.hasFocus, isTrue, reason: '$path restores focus');
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
