import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:true_grit_vital/app/appearance.dart';
import 'package:true_grit_vital/app/vital_app.dart';
import 'package:true_grit_vital/data/record_store.dart';
import 'package:true_grit_vital/features/plans/schedule_screen.dart';

import 'design_substance_summary_fixture.dart' show dose, openSummaryFixture;
import 'screen_schedule_support.dart';
import 'vital_app_test.dart' show appTest, runIo, settle, tap, waitForText;

Future<void> choose(WidgetTester tester, String key) async {
  final chip = find.byKey(ValueKey(key));
  await tester.ensureVisible(chip);
  await settle(tester);
  await tester.tap(chip);
  await settle(tester);
}

Future<void> waitForDraftRequirement(
  WidgetTester tester,
  RecordStore store,
  Map<String, String> expected,
) async {
  final clock = Stopwatch()..start();
  while (clock.elapsed < const Duration(seconds: 10)) {
    final fields = (await runIo(tester, store.drafts))?.firstOrNull?.fields;
    if (expected.entries.every((entry) => fields?[entry.key] == entry.value)) {
      return;
    }
    await runIo(
      tester,
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await tester.pumpAndSettle();
  }
  fail('The plan draft did not keep the structured requirement choices.');
}

void main() {
  appTest('saved labels restore, persist through the draft and save exactly', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final f = await openSchedule(
      tester,
      saved: true,
      timing: slotsTiming(),
      instructions: 'Take one tablet in the morning.',
      requirements: const ScheduleRequirement(
        food: FoodRequirement.withFood,
        atBedtime: true,
      ),
    );

    expect(
      tester
          .widget<ScheduleChoiceChip>(
            find.byKey(const ValueKey('requirement-food-withFood')),
          )
          .selected,
      isTrue,
    );
    expect(
      tester
          .widget<ScheduleChoiceChip>(
            find.byKey(const ValueKey('requirement-bedtime-at')),
          )
          .selected,
      isTrue,
    );

    await choose(tester, 'requirement-food-afterFood');
    await waitForDraftRequirement(tester, f.store, {
      'requirementFood': 'afterFood',
      'requirementBedtime': '1',
    });
    f.container.read(routerProvider).go('/today');
    await settle(tester);
    f.container
        .read(routerProvider)
        .push('/schedule/${f.item.id}?plan=${f.saved!.plan.planId}');
    await waitForText(tester, 'RECURRENCE');
    expect(
      tester
          .widget<ScheduleChoiceChip>(
            find.byKey(const ValueKey('requirement-food-afterFood')),
          )
          .selected,
      isTrue,
    );

    await tap(tester, 'Preview');
    expect(find.text('After food'), findsWidgets);
    expect(find.text('At bedtime'), findsWidgets);
    await tap(tester, 'Save');
    await settle(tester);

    final saved = (await runIo(
      tester,
      () => f.store.dailyPlans(itemId: f.item.id),
    ))!.single;
    expect(
      saved.plan.requirements,
      const ScheduleRequirement(
        food: FoodRequirement.afterFood,
        atBedtime: true,
      ),
    );
    expect(saved.plan.instructions, 'Take one tablet in the morning.');
    final audit = (await runIo(
      tester,
      () => f.store.dailyPlanAudit(saved.plan.planId, personId: meId),
    ))!;
    expect(
      audit.first.plan.requirements,
      const ScheduleRequirement(
        food: FoodRequirement.withFood,
        atBedtime: true,
      ),
    );
    expect(tester.takeException(), isNull);
  });

  appTest('clearing both choices saves no structured requirement', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final f = await openSchedule(
      tester,
      saved: true,
      timing: slotsTiming(),
      requirements: const ScheduleRequirement(
        food: FoodRequirement.beforeFood,
        atBedtime: true,
      ),
    );
    await choose(tester, 'requirement-food-none');
    await choose(tester, 'requirement-bedtime-none');
    await waitForDraftRequirement(tester, f.store, {
      'requirementFood': '',
      'requirementBedtime': '0',
    });
    await tap(tester, 'Preview');
    await tap(tester, 'Save');
    await settle(tester);
    final saved = (await runIo(
      tester,
      () => f.store.dailyPlans(itemId: f.item.id),
    ))!.single;
    expect(saved.plan.requirements, isNull);
    expect(find.text('Before food'), findsNothing);
    expect(find.text('At bedtime'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  appTest('overview and shared summary show the chosen labels', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final f = await openSchedule(
      tester,
      saved: true,
      timing: slotsTiming(),
      requirements: const ScheduleRequirement(
        food: FoodRequirement.emptyStomach,
        atBedtime: true,
      ),
    );
    f.container.read(routerProvider).push('/substance/${f.item.id}');
    await waitForText(tester, 'Overview');
    await tap(tester, 'Schedule');
    await waitForText(tester, 'Empty stomach');
    expect(find.text('At bedtime'), findsWidgets);

    final fixture = await openSummaryFixture(tester);
    await fixture.plan(
      'requirements',
      DailyCount(1, dose('1', 'mg')),
      requirements: const ScheduleRequirement(
        food: FoodRequirement.emptyStomach,
        atBedtime: true,
      ),
    );
    await fixture.mount();
    await fixture.waitText('Empty stomach');
    expect(fixture.tester.takeException(), isNull);
  });

  for (final theme in [ThemeMode.light, ThemeMode.dark]) {
    appTest('requirements survive 320px, double text and reduced motion '
        '(${theme.name})', (tester) async {
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
        requirements: const ScheduleRequirement(
          food: FoodRequirement.withFood,
          atBedtime: true,
        ),
      );
      f.container.read(appearanceProvider.notifier).setMode(theme);
      await settle(tester);
      final chip = find.byKey(const ValueKey('requirement-food-withFood'));
      await tester.ensureVisible(chip);
      await settle(tester);
      expect(tester.widget<ScheduleChoiceChip>(chip).selected, isTrue);
      expect(find.text('At bedtime'), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  }
}
