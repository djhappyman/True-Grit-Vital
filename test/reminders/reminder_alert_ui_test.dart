import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:true_grit_vital/app/appearance.dart';
import 'package:true_grit_vital/app/reminder_alerts.dart';
import 'package:true_grit_vital/app/reminders.dart';
import 'package:true_grit_vital/domain/reminders/alert_preferences.dart';
import 'package:true_grit_vital/features/reminders/reminder_alert_settings.dart';

import 'reminder_ui_test.dart' show UiGateway, launch;
import '../vital_app_test.dart' show appTest, runIo, settle, tap, waitForText;

Future<void> _waitForApplied(WidgetTester tester, UiGateway gateway) async {
  final stop = DateTime.now().add(const Duration(seconds: 10));
  while (gateway.appliedAlerts.isEmpty) {
    if (DateTime.now().isAfter(stop)) {
      fail('The alert adapter never received the initial choice');
    }
    await settle(tester);
  }
}

void main() {
  appTest('alert options render in light and dark with trailing switches', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final fixture = await launch(tester);
    await _waitForApplied(
      tester,
      fixture.container.read(reminderGatewayProvider) as UiGateway,
    );
    for (final theme in [ThemeMode.light, ThemeMode.dark]) {
      fixture.container.read(appearanceProvider.notifier).setMode(theme);
      await settle(tester);
      await tester.ensureVisible(find.text('Alert options'));
      await settle(tester);
      expect(find.text('Alert options'), findsOneWidget);
      expect(find.text('Sound'), findsOneWidget);
      expect(find.text('Vibration'), findsOneWidget);
      expect(find.byType(Switch), findsNWidgets(2));
      for (var index = 0; index < 2; index++) {
        expect(
          tester.getTopRight(find.byType(Switch).at(index)).dx,
          greaterThan(390 * 0.6),
        );
      }
      expect(tester.takeException(), isNull);
    }
  });

  appTest(
    'alert options stay usable at 320 px with double text and no motion',
    (tester) async {
      tester.view.physicalSize = const Size(320, 740);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      final fixture = await launch(tester);
      final gateway =
          fixture.container.read(reminderGatewayProvider) as UiGateway;
      await _waitForApplied(tester, gateway);
      await tester.ensureVisible(find.text('Alert options'));
      await settle(tester);
      expect(find.text('Sound'), findsOneWidget);
      expect(find.text('Vibration'), findsOneWidget);
      expect(find.byType(Switch), findsNWidgets(2));
      for (var index = 0; index < 2; index++) {
        expect(
          tester.widget<Switch>(find.byType(Switch).at(index)).key,
          isA<ValueKey<bool>>(),
        );
      }
      expect(tester.takeException(), isNull);
      await tap(tester, 'Sound');
      final stop = DateTime.now().add(const Duration(seconds: 10));
      while (gateway.appliedAlerts.last.sound) {
        if (DateTime.now().isAfter(stop)) {
          fail('Reduced-motion alert change did not reach the adapter');
        }
        await settle(tester);
      }
      expect(gateway.appliedAlerts.last.sound, false);
    },
  );

  appTest('alert changes persist and an unapplied change offers Retry', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final fixture = await launch(tester);
    final gateway =
        fixture.container.read(reminderGatewayProvider) as UiGateway;
    await _waitForApplied(tester, gateway);
    await tap(tester, 'Sound');
    final appliedStop = DateTime.now().add(const Duration(seconds: 10));
    while (gateway.appliedAlerts.last.sound) {
      if (DateTime.now().isAfter(appliedStop)) {
        fail('The saved sound choice never reached the adapter');
      }
      await settle(tester);
    }
    expect(
      await runIo(
        tester,
        () => fixture.store.readSetting(reminderAlertsSettingKey),
      ),
      '{"sound":false,"vibration":true}',
    );

    gateway.acceptAlerts = false;
    await tap(tester, 'Vibration');
    await waitForText(
      tester,
      'Alert options are saved. Android has not applied them yet.',
    );
    expect(find.text('Vibration'), findsOneWidget);

    gateway.acceptAlerts = true;
    final retry = find.descendant(
      of: find.byType(ReminderAlertSettings),
      matching: find.text('Retry'),
    );
    await tester.ensureVisible(retry);
    await settle(tester);
    await tester.tap(retry);
    await settle(tester);
    expect(
      find.text('Alert options are saved. Android has not applied them yet.'),
      findsNothing,
    );
    expect(
      gateway.appliedAlerts.last,
      const ReminderAlertPreferences(sound: false, vibration: false),
    );
    expect(
      await runIo(
        tester,
        () => fixture.store.readSetting(reminderAlertsSettingKey),
      ),
      '{"sound":false,"vibration":false}',
    );
  });

  appTest('a blocked channel disables alert choices without a silent bypass', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final fixture = await launch(tester);
    final gateway =
        fixture.container.read(reminderGatewayProvider) as UiGateway;
    await _waitForApplied(tester, gateway);
    gateway.channelEnabled = false;
    fixture.container.read(remindersProvider.notifier).refresh();
    await waitForText(
      tester,
      'Android is blocking notifications. Review notification settings.',
    );
    final applied = gateway.appliedAlerts.length;
    await tester.ensureVisible(find.text('Sound'));
    await tester.tap(find.text('Sound'));
    await settle(tester);
    expect(gateway.appliedAlerts.length, applied);
    expect(
      await runIo(
        tester,
        () => fixture.store.readSetting(reminderAlertsSettingKey),
      ),
      isNull,
    );
  });

  appTest('unsupported hosts never show alert choices', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await launch(tester, unsupported: true);
    expect(find.text('Alert options'), findsNothing);
    expect(find.text('Sound'), findsNothing);
    expect(find.text('Vibration'), findsNothing);
    expect(find.byType(Switch), findsNothing);
  });
}
