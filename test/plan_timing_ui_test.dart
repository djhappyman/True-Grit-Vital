import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:true_grit_vital/app/vital_app.dart';
import 'package:true_grit_vital/data/record_store.dart';
import 'package:true_grit_vital/features/recording/record_pages.dart'
    show LabelledInput;
import 'package:true_grit_vital/ui/vital_ui.dart';

import 'screen_schedule_support.dart';
import 'vital_app_test.dart' show appTest, runIo, settle, tap, waitForText;

Future<void> fill(WidgetTester tester, String label, String value) async {
  final field = find.descendant(
    of: find.widgetWithText(LabelledInput, label),
    matching: find.byType(TextField),
  );
  await tester.ensureVisible(field);
  await settle(tester);
  await tester.enterText(field, value);
  await settle(tester);
}

void main() {
  appTest('timing choices start off and persist through Preview and Save', (
    tester,
  ) async {
    final f = await openSchedule(tester, timing: slotsTiming(), saved: true);
    await fill(
      tester,
      'Effective date',
      CivilDate.fromDateTime(DateTime.now()).addDays(2).toString(),
    );
    await tap(tester, 'Timing');
    expect(find.text('Allowance (minutes)'), findsNothing);
    expect(find.text('Delay (minutes)'), findsNothing);
    await tap(tester, 'Timing labels');
    await fill(tester, 'Allowance (minutes)', '15');
    await tap(tester, 'Follow-up reminder');
    await fill(tester, 'Delay (minutes)', '30');
    await tap(tester, 'Preview');
    expect(
      find.text('Your window: 15 minutes before or after the planned time.'),
      findsOneWidget,
    );
    expect(
      find.text(
        'One follow-up 30 minutes after the planned time, if you have not recorded or skipped it.',
      ),
      findsOneWidget,
    );
    await tap(tester, 'Save');
    final saved = (await runIo(
      tester,
      () => f.store.dailyPlans(itemId: f.item.id),
    ))!.single;
    expect(saved.plan.timingPolicy!.allowanceMinutes, 15);
    expect(saved.plan.timingPolicy!.followUpMinutes, 30);
    expect(await runIo(tester, f.store.records), isEmpty);
    f.container
        .read(routerProvider)
        .go('/schedule/${f.item.id}?plan=${saved.plan.planId}');
    await waitForText(tester, 'RECURRENCE');
    await tap(tester, 'Timing');
    expect(
      tester
          .widget<TextField>(
            find.descendant(
              of: find.widgetWithText(LabelledInput, 'Allowance (minutes)'),
              matching: find.byType(TextField),
            ),
          )
          .controller!
          .text,
      '15',
    );
    expect(tester.takeException(), isNull);
  });
  appTest(
    'enabling without a valid value cannot save or retain an old preview',
    (tester) async {
      await openSchedule(tester, timing: slotsTiming(), saved: true);
      await tap(tester, 'Preview');
      await tap(tester, 'Timing');
      await tap(tester, 'Follow-up reminder');
      await tap(tester, 'Preview');
      expect(
        find.text('Enter a whole number in the range shown before continuing.'),
        findsOneWidget,
      );
      final save = tester.widget<VitalButton>(
        find.widgetWithText(VitalButton, 'Save'),
      );
      expect(save.onPressed, isNull);
      await fill(tester, 'Delay (minutes)', '0');
      await tap(tester, 'Preview');
      expect(
        tester
            .widget<VitalButton>(find.widgetWithText(VitalButton, 'Save'))
            .onPressed,
        isNull,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
