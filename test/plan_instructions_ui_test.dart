import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:true_grit_vital/app/appearance.dart';
import 'package:true_grit_vital/app/vital_app.dart';
import 'package:true_grit_vital/data/record_store.dart';
import 'package:true_grit_vital/features/recording/record_pages.dart'
    show LabelledInput;
import 'package:true_grit_vital/ui/vital_ui.dart';

import 'design_substance_summary_fixture.dart' show dose, openSummaryFixture;
import 'screen_schedule_support.dart';
import 'vital_app_test.dart' show appTest, runIo, settle, tap, waitForText;

Finder instructionsField() => find.descendant(
  of: find.widgetWithText(LabelledInput, 'Instructions'),
  matching: find.byType(TextField),
);

Future<void> enterField(WidgetTester tester, String label, String value) async {
  final field = find.descendant(
    of: find.widgetWithText(LabelledInput, label),
    matching: find.byType(TextField),
  );
  await tester.enterText(field, value);
  await settle(tester);
}

Future<void> waitForDraftInstructions(
  WidgetTester tester,
  RecordStore store,
  String value,
) async {
  final clock = Stopwatch()..start();
  while (clock.elapsed < const Duration(seconds: 10)) {
    final drafts = await runIo(tester, store.drafts);
    if (drafts?.firstOrNull?.fields['instructions'] == value) return;
    await runIo(
      tester,
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await tester.pumpAndSettle();
  }
  fail('The plan draft did not keep the instructions.');
}

Future<void> waitForInstructions(WidgetTester tester, String value) async {
  final clock = Stopwatch()..start();
  while (tester.widget<TextField>(instructionsField()).controller!.text !=
      value) {
    if (clock.elapsed > const Duration(seconds: 10)) {
      fail('The plan instructions did not restore.');
    }
    await runIo(
      tester,
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await tester.pumpAndSettle();
  }
}

VitalButton saveButton(WidgetTester tester) =>
    tester.widget<VitalButton>(find.widgetWithText(VitalButton, 'Save'));

void main() {
  appTest('saved instructions restore through the draft and clear on save', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    const original = 'Take with food.\nAt bedtime.';
    final f = await openSchedule(
      tester,
      saved: true,
      timing: slotsTiming(),
      instructions: original,
    );
    expect(find.text('PLAN INSTRUCTIONS'), findsOneWidget);
    expect(
      tester.widget<TextField>(instructionsField()).controller!.text,
      original,
    );

    const edited = 'With breakfast.\nAt bedtime.';
    await tester.enterText(instructionsField(), edited);
    await waitForDraftInstructions(tester, f.store, edited);
    f.container.read(routerProvider).go('/today');
    await settle(tester);
    f.container
        .read(routerProvider)
        .push('/schedule/${f.item.id}?plan=${f.saved!.plan.planId}');
    await waitForText(tester, 'RECURRENCE');
    await waitForInstructions(tester, edited);

    await tap(tester, 'Preview');
    expect(find.text(edited), findsWidgets);
    await tester.enterText(instructionsField(), '');
    await settle(tester);
    await tap(tester, 'Preview');
    await tap(tester, 'Save');
    await settle(tester);

    final saved = (await runIo(
      tester,
      () => f.store.dailyPlans(itemId: f.item.id),
    ))!.single;
    expect(saved.plan.instructions, isEmpty);
    final audit = (await runIo(
      tester,
      () => f.store.dailyPlanAudit(saved.plan.planId, personId: meId),
    ))!;
    expect(audit.first.plan.instructions, original);
    expect(tester.takeException(), isNull);
  });

  appTest('the overview schedule summary shows the authored text', (
    tester,
  ) async {
    const text = 'Take with food.\nAt bedtime.';
    final f = await openSchedule(
      tester,
      saved: true,
      timing: slotsTiming(),
      instructions: text,
    );
    f.container.read(routerProvider).push('/substance/${f.item.id}');
    await waitForText(tester, 'Overview');
    await tap(tester, 'Schedule');
    await waitForText(tester, text);
    expect(find.text('Plan instructions'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  appTest('shared summary names the text only in its detailed presentation', (
    tester,
  ) async {
    const text = 'Take with food.\nAt bedtime.';
    final fixture = await openSummaryFixture(tester);
    await fixture.plan(
      'instructions',
      DailyCount(1, dose('1', 'mg')),
      instructions: text,
    );
    await fixture.mount();
    await fixture.waitText('Plan instructions');
    expect(find.text(text), findsNothing);

    await fixture.mount(detailed: true);
    await fixture.waitText(text);
    expect(find.text('Plan instructions'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  appTest('over-limit instructions stay beside the field and block saving', (
    tester,
  ) async {
    final f = await openSchedule(tester);
    await enterField(tester, 'Count', '1');
    await enterField(tester, 'Amount', '1');
    final tooLong = 'x' * (DailyPlanVersion.maxInstructionsLength + 1);
    await tester.enterText(instructionsField(), tooLong);
    await settle(tester);
    expect(
      find.text('Keep plan instructions within 4000 characters.'),
      findsOneWidget,
    );
    await waitForDraftInstructions(tester, f.store, tooLong);
    await tap(tester, 'Preview');
    expect(saveButton(tester).onPressed, isNull);

    await tester.enterText(instructionsField(), 'A short note.\nSecond line.');
    await settle(tester);
    expect(
      find.text('Keep plan instructions within 4000 characters.'),
      findsNothing,
    );
    await tap(tester, 'Preview');
    expect(saveButton(tester).onPressed, isNotNull);
    expect(find.text('A short note.\nSecond line.'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  for (final theme in [ThemeMode.light, ThemeMode.dark]) {
    appTest(
      'instructions survive 320px, double text and reduced motion (${theme.name})',
      (tester) async {
        tester.view.physicalSize = const Size(320, 740);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        tester.platformDispatcher.accessibilityFeaturesTestValue =
            const FakeAccessibilityFeatures(disableAnimations: true);
        addTearDown(() {
          tester.view.reset();
          tester.platformDispatcher.clearTextScaleFactorTestValue();
          tester.platformDispatcher.clearAccessibilityFeaturesTestValue();
        });
        final f = await openSchedule(
          tester,
          saved: true,
          timing: slotsTiming(),
          instructions: 'Take with food.\nAt bedtime.',
        );
        f.container.read(appearanceProvider.notifier).setMode(theme);
        await settle(tester);
        expect(find.text('PLAN INSTRUCTIONS'), findsOneWidget);
        await tester.ensureVisible(instructionsField());
        await settle(tester);
        expect(
          tester.widget<TextField>(instructionsField()).controller!.text,
          'Take with food.\nAt bedtime.',
        );
        expect(find.text('mg'), findsWidgets);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
