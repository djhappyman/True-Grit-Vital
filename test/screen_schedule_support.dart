import 'package:flutter/widgets.dart' show FocusManager;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:true_grit_vital/app/vital_app.dart';
import 'package:true_grit_vital/data/record_store.dart';

import 'vital_app_test.dart' show launch, runIo, settle, waitForText;

Future<
  ({
    RecordStore store,
    ProviderContainer container,
    SubstanceItem item,
    SavedDailyPlan? saved,
  })
>
openSchedule(
  WidgetTester tester, {
  DailyTiming timing = const AsNeeded(),
  bool saved = false,
  List<PlanPause> pauses = const [],
  String instructions = '',
  ScheduleRequirement? requirements,
}) async {
  final f = await launch(tester);
  final item = (await runIo(
    tester,
    () => f.store.createItem(
      commandId: newCommandId(),
      expectedPersonRevision: 2,
      name: 'Full synthetic substance name',
      form: 'Tablet',
      unit: 'mg',
      type: 'Medicine',
    ),
  ))!;
  SavedDailyPlan? plan;
  if (saved) {
    plan = (await runIo(
      tester,
      () => f.store.saveDailyPlan(
        commandId: newCommandId(),
        expectedPersonRevision: 2,
        expectedGeneration: f.store.generation,
        plan: DailyPlanVersion(
          personId: meId,
          planId: newCommandId(),
          itemId: item.id,
          versionId: newCommandId(),
          start: CivilDate.fromDateTime(DateTime.now()),
          timing: timing,
          zoneBasis: const FollowingLocal(),
          calendar: const EveryDay(),
          pauses: pauses,
          instructions: instructions,
          requirements: requirements,
        ),
      ),
    ))!;
  }
  f.container
      .read(routerProvider)
      .push(
        '/schedule/${item.id}${plan == null ? '' : '?plan=${plan.plan.planId}'}',
      );
  await waitForText(tester, 'RECURRENCE');
  return (store: f.store, container: f.container, item: item, saved: plan);
}

DailySlots slotsTiming() => DailySlots([
  DailySlot(
    id: newCommandId(),
    time: WallTime(8, 0),
    amount: PlannedAmount(
      quantity: ExactQuantity.parse('1'),
      unit: 'mg',
      enteredText: '1',
    ),
    reminderEnabled: true,
  ),
  DailySlot(
    id: newCommandId(),
    time: WallTime(20, 0),
    amount: PlannedAmount(
      quantity: ExactQuantity.parse('1'),
      unit: 'mg',
      enteredText: '1',
    ),
    reminderEnabled: false,
  ),
]);

Future<void> tapLast(WidgetTester tester, String text) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await settle(tester);
  final target = find.text(text).last;
  await tester.ensureVisible(target);
  await settle(tester);
  expect(target.hitTestable(), findsOneWidget);
  await tester.tap(target);
  await settle(tester);
}

Future<void> waitForDraftCount(
  WidgetTester tester,
  RecordStore store,
  String value,
) async {
  final clock = Stopwatch()..start();
  while (clock.elapsed < const Duration(seconds: 10)) {
    final drafts = await runIo(tester, store.drafts);
    final fields = drafts?.firstOrNull?.fields;
    if (fields?['count'] == value) return;
    await runIo(
      tester,
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await tester.pumpAndSettle();
  }
  fail('The plan draft did not keep count $value.');
}
