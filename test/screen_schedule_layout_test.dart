import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:true_grit_vital/features/plans/schedule_screen.dart';
import 'package:true_grit_vital/ui/vital_ui.dart';

import 'screen_schedule_support.dart';
import 'vital_app_test.dart' show appTest, settle, tap;

void main() {
  appTest('schedule survives 320px at double text with the save reachable', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 740);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(() {
      tester.view.reset();
      tester.platformDispatcher.clearTextScaleFactorTestValue();
    });
    await openSchedule(tester, timing: slotsTiming(), saved: true);
    expect(find.text('Full synthetic substance name'), findsOneWidget);
    expect(find.text('mg'), findsWidgets);
    await tap(tester, 'Preview');
    final save = find.widgetWithText(VitalButton, 'Save');
    await tester.showKeyboard(find.byType(TextField).first);
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await settle(tester);
    await tester.ensureVisible(save);
    await settle(tester);
    expect(save.hitTestable(), findsOneWidget);
    final rect = tester.getRect(save);
    expect(rect.top, greaterThanOrEqualTo(0));
    expect(rect.bottom, lessThanOrEqualTo(740 - 300 + .01));
    expect(tester.takeException(), isNull);
  });

  for (final width in [390.0, 430.0]) {
    appTest('schedule choices and commands keep 48px targets at $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await openSchedule(tester, timing: slotsTiming(), saved: true);
      for (final label in [
        'Count',
        'Chosen times',
        'As needed',
        'Interval',
        'Partly timed',
        'Time windows',
        'Before food',
        'Empty stomach',
        'At bedtime',
      ]) {
        final chip = find.ancestor(
          of: find.text(label).last,
          matching: find.byType(ScheduleChoiceChip),
        );
        expect(tester.getSize(chip).height, greaterThanOrEqualTo(48));
      }
      expect(
        tester.getSize(find.widgetWithText(VitalButton, 'Save')).height,
        greaterThanOrEqualTo(48),
      );
      expect(
        tester.getSize(find.widgetWithText(VitalButton, 'Discard')).height,
        greaterThanOrEqualTo(48),
      );
      expect(tester.takeException(), isNull);
    });
  }

  appTest('schedule respects all four landscape safe areas', (tester) async {
    tester.view.physicalSize = const Size(740, 390);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(
      top: 18,
      bottom: 20,
      left: 28,
      right: 32,
    );
    tester.view.viewPadding = tester.view.padding;
    addTearDown(tester.view.reset);
    await openSchedule(tester);
    final rect = tester.getRect(find.byType(Scaffold).last);
    expect(rect.left, 28);
    expect(rect.top, 18);
    expect(rect.right, 708);
    expect(rect.bottom, 370);
    expect(tester.takeException(), isNull);
  });
}
