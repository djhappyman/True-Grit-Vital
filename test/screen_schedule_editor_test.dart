import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:true_grit_vital/app/settings_toggle_row.dart';
import 'package:true_grit_vital/data/record_store.dart';
import 'package:true_grit_vital/app/vital_app.dart';
import 'package:true_grit_vital/ui/vital_ui.dart';

import 'screen_schedule_support.dart';
import 'vital_app_test.dart' show appTest, runIo, settle, tap, waitForText;

VitalButton saveButton(WidgetTester tester) =>
    tester.widget<VitalButton>(find.widgetWithText(VitalButton, 'Save'));

void main() {
  appTest('six cadence modes stay real and save waits for a preview', (
    tester,
  ) async {
    await openSchedule(tester);
    for (final label in [
      'Count',
      'Chosen times',
      'As needed',
      'Interval',
      'Partly timed',
      'Time windows',
    ]) {
      expect(find.text(label), findsWidgets, reason: label);
    }
    expect(saveButton(tester).onPressed, isNull);
    await tester.enterText(find.byType(TextField).at(0), '1');
    await tester.enterText(find.byType(TextField).at(1), '1');
    await tap(tester, 'Preview');
    expect(saveButton(tester).onPressed, isNotNull);
    await tester.enterText(find.byType(TextField).at(0), '3');
    await settle(tester);
    expect(saveButton(tester).onPressed, isNull);
    expect(find.textContaining('Avoid Potassium'), findsNothing);
    expect(find.textContaining('Push Notification'), findsNothing);
    expect(find.textContaining('Fires exactly'), findsNothing);
    expect(find.textContaining('on-time'), findsNothing);
    expect(find.textContaining('total daily'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  appTest('slot add and remove keep the surviving planned time identity', (
    tester,
  ) async {
    final f = await openSchedule(tester);
    await tap(tester, 'Chosen times');
    await tester.enterText(find.byType(TextField).at(0), '08:00');
    await tester.enterText(find.byType(TextField).at(1), '1');
    await tap(tester, 'Add');
    await tester.enterText(find.byType(TextField).at(2), '20:00');
    await tester.enterText(find.byType(TextField).at(3), '2');
    expect(find.text('Remove'), findsNWidgets(2));
    final remove = find.text('Remove').first;
    await tester.ensureVisible(remove);
    await tester.tap(remove);
    await settle(tester);
    expect(find.text('Remove'), findsNothing);
    expect(
      tester.widget<TextField>(find.byType(TextField).at(0)).controller!.text,
      '20:00',
    );
    expect(
      tester.widget<TextField>(find.byType(TextField).at(1)).controller!.text,
      '2',
    );
    await tap(tester, 'Preview');
    await tap(tester, 'Save');
    final first = (await runIo<List<SavedDailyPlan>>(
      tester,
      () => f.store.dailyPlans(itemId: f.item.id),
    ))!.single;
    final firstSlots = (first.plan.timing as DailySlots).slots;
    expect(firstSlots, hasLength(1));
    expect(firstSlots.single.time.hour, 20);
    expect(firstSlots.single.time.minute, 0);
    expect(firstSlots.single.amount.enteredText, '2');

    f.container
        .read(routerProvider)
        .push('/schedule/${f.item.id}?plan=${first.plan.planId}');
    await waitForText(tester, 'RECURRENCE');
    await tap(tester, 'Add');
    await tester.enterText(find.byType(TextField).at(2), '21:00');
    await tester.enterText(find.byType(TextField).at(3), '0.5');
    await tap(tester, 'Preview');
    await tap(tester, 'Save');
    final second = (await runIo<List<SavedDailyPlan>>(
      tester,
      () => f.store.dailyPlans(itemId: f.item.id),
    ))!.single;
    final secondSlots = (second.plan.timing as DailySlots).slots;
    expect(secondSlots, hasLength(2));
    expect(secondSlots.first.id, firstSlots.single.id);
    expect(secondSlots.last.time.hour, 21);
    expect(secondSlots.last.time.minute, 0);
    expect(secondSlots.last.amount.enteredText, '0.5');
    expect(tester.takeException(), isNull);
  });

  appTest('pause and phase editors stay reachable from a saved plan', (
    tester,
  ) async {
    final f = await openSchedule(tester, timing: slotsTiming(), saved: true);
    final router = f.container.read(routerProvider);
    await tap(tester, 'Pause');
    await waitForText(tester, 'Pause instant');
    expect(
      router.routerDelegate.currentConfiguration.last.route.path,
      '/pause/:id',
    );
    router.pop();
    await waitForText(tester, 'RECURRENCE');
    await tap(tester, 'Phases');
    expect(
      router.routerDelegate.currentConfiguration.last.route.path,
      '/phases/:id',
    );
    router.pop();
    await waitForText(tester, 'RECURRENCE');
    await tap(tester, 'Interval');
    expect(find.text('Elapsed hours'), findsOneWidget);
    await tap(tester, 'Time windows');
    expect(find.text('Window start'), findsWidgets);
    await tap(tester, 'Chosen times');
    expect(find.text('Planned time'), findsWidgets);
    expect(find.text('Dates'), findsOneWidget);
    expect(find.text('Repeating breaks'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  for (final future in [true, false]) {
    appTest('pause action reflects the current interval, future=$future', (
      tester,
    ) async {
      final now = DateTime.now().toUtc();
      await openSchedule(
        tester,
        saved: true,
        timing: slotsTiming(),
        pauses: [
          PlanPause(
            start: now.add(Duration(days: future ? 1 : -1)),
            resume: future ? null : now.add(const Duration(days: 1)),
          ),
        ],
      );
      expect(find.text(future ? 'Pause' : 'Resume'), findsOneWidget);
      expect(find.text(future ? 'Resume' : 'Pause'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  appTest('a changed plan revision blocks the stale save', (tester) async {
    final f = await openSchedule(
      tester,
      timing: DailyCount(
        1,
        PlannedAmount(
          quantity: ExactQuantity.parse('1'),
          unit: 'mg',
          enteredText: '1',
        ),
      ),
      saved: true,
    );
    await tester.enterText(find.byType(TextField).at(0), '2');
    await tap(tester, 'Preview');
    expect(saveButton(tester).onPressed, isNotNull);
    await runIo<SavedDailyPlan>(
      tester,
      () => f.store.saveDailyPlan(
        commandId: newCommandId(),
        expectedPersonRevision: 2,
        expectedPlanRevision: f.saved!.revision,
        expectedGeneration: f.store.generation,
        plan: DailyPlanVersion(
          personId: meId,
          planId: f.saved!.plan.planId,
          itemId: f.item.id,
          versionId: newCommandId(),
          start: f.saved!.plan.start,
          timing: DailyCount(
            3,
            PlannedAmount(
              quantity: ExactQuantity.parse('1'),
              unit: 'mg',
              enteredText: '1',
            ),
          ),
          zoneBasis: const FollowingLocal(),
          calendar: const EveryDay(),
        ),
      ),
    );
    await settle(tester);
    await tap(tester, 'Save');
    await waitForText(
      tester,
      'This record has changed. Return to History and review the latest version before correcting it.',
    );
    final current = (await runIo<List<SavedDailyPlan>>(
      tester,
      () => f.store.dailyPlans(itemId: f.item.id),
    ))!.single;
    expect((current.plan.timing as DailyCount).count, 3);
    expect(tester.takeException(), isNull);
  });

  appTest('a restored plan draft can be discarded from the schedule', (
    tester,
  ) async {
    final f = await openSchedule(tester);
    await tester.enterText(find.byType(TextField).at(0), '3');
    await waitForDraftCount(tester, f.store, '3');
    f.container.read(routerProvider).go('/today');
    await settle(tester);
    f.container.read(routerProvider).push('/schedule/${f.item.id}');
    await waitForText(tester, 'RECURRENCE');
    final restored = Stopwatch()..start();
    while (tester
            .widget<TextField>(find.byType(TextField).at(0))
            .controller!
            .text !=
        '3') {
      if (restored.elapsed > const Duration(seconds: 10)) {
        fail('The plan draft did not restore.');
      }
      await runIo(
        tester,
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await tester.pumpAndSettle();
    }
    await tapLast(tester, 'Discard');
    await waitForText(tester, 'Unsaved changes');
    await tester.tap(find.text('Discard').last);
    await settle(tester);
    final clock = Stopwatch()..start();
    while ((await runIo<List<OrdinaryDraft>>(
      tester,
      f.store.drafts,
    ))!.isNotEmpty) {
      if (clock.elapsed > const Duration(seconds: 10)) {
        fail('The plan draft was not discarded.');
      }
      await runIo(
        tester,
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await tester.pumpAndSettle();
    }
    expect(
      f.container
          .read(routerProvider)
          .routerDelegate
          .currentConfiguration
          .uri
          .toString(),
      '/today',
    );
    expect(tester.takeException(), isNull);
  });

  appTest('follow-up stays a labelled preview with no delivery promise', (
    tester,
  ) async {
    await openSchedule(tester, timing: slotsTiming(), saved: true);
    expect(find.text('Follow-up'), findsOneWidget);
    final followUp = tester.widget<SettingsToggleRow>(
      find.ancestor(
        of: find.text('Follow-up'),
        matching: find.byType(SettingsToggleRow),
      ),
    );
    expect(followUp.enabled, isFalse);
    expect(followUp.value, isFalse);
    await tester.ensureVisible(find.text('Follow-up'));
    await tester.tap(find.text('Follow-up'));
    await settle(tester);
    expect(
      tester
          .widget<SettingsToggleRow>(
            find.ancestor(
              of: find.text('Follow-up'),
              matching: find.byType(SettingsToggleRow),
            ),
          )
          .value,
      isFalse,
    );
    for (final claim in [
      'Push Notification',
      'Fires exactly',
      'Prompt +30',
      'Avoid Potassium',
    ]) {
      expect(find.textContaining(claim), findsNothing, reason: claim);
    }
    expect(
      find.textContaining('Follow-up alerts are not available yet.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
