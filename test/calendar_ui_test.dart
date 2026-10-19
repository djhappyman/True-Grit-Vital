import 'package:true_grit_vital/ui/vital_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:true_grit_vital/app/app_lock.dart';
import 'package:true_grit_vital/app/vital_app.dart';
import 'package:true_grit_vital/data/record_store.dart';
import 'package:true_grit_vital/features/plans/calendar_editor.dart';
import 'package:true_grit_vital/features/plans/plan_form.dart';
import 'package:true_grit_vital/l10n/app_localizations.dart';

import 'daily_plan_ui_test.dart' show launchPlan, tap;
import 'vital_app_test.dart' show appTest, runIo, settle;

Future<void> fill(WidgetTester tester, Key key, String text) async {
  final field = find.descendant(
    of: find.byKey(key),
    matching: find.byType(TextField),
  );
  await tester.ensureVisible(field);
  await tester.enterText(field, text);
  await settle(tester);
}

void main() {
  appTest('civil day interval keeps chosen anchor and separate untimed count', (
    tester,
  ) async {
    final f = await launchPlan(tester);
    await tester.enterText(find.byType(TextField).at(0), '3');
    await tester.enterText(find.byType(TextField).at(1), '1.2500');
    await tap(tester, 'Days');
    await fill(tester, const ValueKey('calendarInterval'), '2');
    final anchor = CivilDate.fromDateTime(DateTime.now());
    await fill(tester, const ValueKey('calendarAnchor'), anchor.toString());
    await tap(tester, 'Preview');
    expect(
      find.textContaining('3 planned, 1.2500 mg each, untimed'),
      findsWidgets,
    );
    await tap(tester, 'Save');
    final saved = (await runIo(
      tester,
      () => f.store.dailyPlans(itemId: f.item.id),
    ))!.single.plan;
    expect((saved.calendar as EveryNDays).anchor, anchor);
    expect((saved.calendar as EveryNDays).interval, 2);
    expect(saved.timing, isA<DailyCount>());
  });

  testWidgets(
    'sparse next date survives an empty preview and unsupported conversion',
    (tester) async {
      final today = CivilDate.fromDateTime(DateTime.now());
      final future = today.addDays(1000);
      DailyPlanVersion make(bool timed) => DailyPlanVersion(
        personId: meId,
        itemId: 'i',
        planId: 'p',
        versionId: 'v',
        start: today,
        calendar: EveryNDays(anchor: future, interval: 2000),
        zoneBasis: FixedHome('Europe/London'),
        timing: timed
            ? DailySlots([
                DailySlot(
                  id: 's',
                  reminderEnabled: false,
                  time: WallTime(8, 0),
                  amount: PlannedAmount(
                    quantity: ExactQuantity.parse('1'),
                    unit: 'mg',
                  ),
                ),
              ])
            : DailyCount(
                1,
                PlannedAmount(quantity: ExactQuantity.parse('1'), unit: 'mg'),
              ),
      );
      Future<void> show(DailyPlanVersion plan) => tester.pumpWidget(
        ShadcnApp(
          localizationsDelegates: const [AppLocalizations.delegate],
          supportedLocales: const [Locale('en', 'GB')],
          home: Scaffold(
            child: SingleChildScrollView(
              child: PlanPreview(plan: plan, observedZone: 'Europe/London'),
            ),
          ),
        ),
      );
      await show(make(false));
      expect(find.text('Next planned date: $future'), findsOneWidget);
      expect(find.textContaining('beyond the preview range'), findsOneWidget);
      final unsupported = DailyPlanVersion(
        personId: meId,
        itemId: 'i',
        planId: 'p',
        versionId: 'v',
        start: CivilDate(2090, 2, 1),
        calendar: EveryNMonths(
          anchorMonth: CivilDate(2090, 2, 1),
          interval: 12,
          selector: DayOfMonth(28),
        ),
        zoneBasis: FixedHome('Europe/London'),
        timing: make(true).timing,
      );
      await show(unsupported);
      await tester.pump();
      expect(
        find.textContaining('Next calendar date: 2090-02-28.'),
        findsOneWidget,
      );
      expect(find.text('No next planned date within this plan.'), findsNothing);
    },
  );

  appTest('weekday preview Today Taken and captured adult agree', (
    tester,
  ) async {
    final f = await launchPlan(tester, person: 'other');
    await tester.enterText(find.byType(TextField).at(0), '2');
    await tester.enterText(find.byType(TextField).at(1), '0.12500');
    await tap(tester, 'Weekdays');
    final now = CivilDate.fromDateTime(DateTime.now());
    final names = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    await tap(tester, names[now.calendarValue.weekday - 1]);
    await tap(tester, 'Preview');
    expect(
      find.textContaining('2 planned, 0.12500 mg each, untimed'),
      findsWidgets,
    );
    await tap(tester, 'Save');
    await runIo(
      tester,
      () => f.store.saveBrowsingScope(const FeedScope.everyone()),
    );
    await settle(tester);
    await tap(tester, 'Taken');
    final records = (await runIo(
      tester,
      () => f.store.records(scope: const FeedScope.everyone()),
    ))!;
    expect(records.single.personId, f.item.personId);
    expect(records.single.enteredAmount, '0.12500');
    final saved = (await runIo(
      tester,
      () => f.store.dailyPlans(itemId: f.item.id),
    ))!.single;
    expect((saved.plan.calendar as SelectedWeekdays).weekdays, [
      now.calendarValue.weekday,
    ]);
    expect(tester.takeException(), isNull);
  });

  appTest(
    'monthly missing-date choice is explicit and raw invalid draft survives lock',
    (tester) async {
      final f = await launchPlan(tester);
      await tester.enterText(find.byType(TextField).at(0), '1');
      await tester.enterText(find.byType(TextField).at(1), '1.000');
      await tap(tester, 'Months');
      await fill(tester, const ValueKey('calendarAnchor'), '2026-01-15');
      await fill(tester, const ValueKey('calendarNominalDay'), '31');
      await tap(tester, 'Preview');
      expect(
        find.text('Choose Omit or Use for months without the selected date.'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<VitalButton>(find.widgetWithText(VitalButton, 'Save'))
            .onPressed,
        isNull,
      );
      await runIo(
        tester,
        () => f.container.read(appLockProvider.notifier).setEnabled(true),
      );
      f.container.read(appLockProvider.notifier).lock();
      await settle(tester);
      expect(find.text('31'), findsNothing);
      await runIo(
        tester,
        () => f.container.read(appLockProvider.notifier).unlock(),
      );
      await settle(tester);
      expect(
        find.text('Choose Omit or Use for months without the selected date.'),
        findsOneWidget,
      );
      final fields = (await runIo(tester, f.store.drafts))!.single.fields;
      expect(fields['calendarDay'], '31');
      expect(fields['calendarMissing'], '');
      expect(fields['calendarError'], 'missing');
      await tap(tester, 'Use');
      await tap(tester, 'Preview');
      expect(
        find.textContaining('nominal day 31 does not exist.'),
        findsOneWidget,
      );
      expect(
        find.textContaining('The nominal rule stays unchanged.'),
        findsOneWidget,
      );
      await tap(tester, 'Save');
      final saved = (await runIo(
        tester,
        () => f.store.dailyPlans(itemId: f.item.id),
      ))!.single.plan;
      final calendar = saved.calendar as EveryNMonths;
      expect(calendar.anchorMonth, CivilDate(2026, 1, 15));
      expect((calendar.selector as DayOfMonth).day, 31);
      expect(
        (calendar.selector as DayOfMonth).missingDatePolicy,
        MissingDatePolicy.lastValid,
      );
      expect(tester.takeException(), isNull);
    },
  );

  appTest('anchored weeks keep exact date and invalid interval on reopen', (
    tester,
  ) async {
    final f = await launchPlan(tester);
    await tester.enterText(find.byType(TextField).at(0), '1');
    await tester.enterText(find.byType(TextField).at(1), '2');
    await tap(tester, 'Weeks');
    await fill(tester, const ValueKey('calendarAnchor'), '2025-12-29');
    await fill(tester, const ValueKey('calendarInterval'), 'two');
    await tap(tester, 'Monday');
    await tap(tester, 'Preview');
    expect(find.textContaining('Check the calendar dates'), findsOneWidget);
    f.container.read(routerProvider).go('/today');
    await settle(tester);
    await tap(tester, 'Resume');
    final fields = (await runIo(tester, f.store.drafts))!.single.fields;
    expect(fields['calendarInterval'], 'two');
    expect(fields['calendarAnchor'], '2025-12-29');
    expect(find.textContaining('Check the calendar dates'), findsOneWidget);
    await fill(tester, const ValueKey('calendarInterval'), '2');
    await tap(tester, 'Preview');
    expect(
      find.textContaining('Anchor week: 2025-12-29 to 2026-01-04'),
      findsOneWidget,
    );
    await tap(tester, 'Save');
    expect(
      (await runIo(
        tester,
        () => f.store.dailyPlans(itemId: f.item.id),
      ))!.single.plan.calendar,
      isA<EveryNWeeks>(),
    );
  });

  testWidgets(
    'monthly ordinal last weekday and yearly fields keep exact selectors',
    (tester) async {
      final f = CalendarFormFields(initialDate: CivilDate(2026, 1, 1));
      addTearDown(f.dispose);
      VoidCallback rebuild = () {};
      await tester.pumpWidget(
        ShadcnApp(
          localizationsDelegates: const [AppLocalizations.delegate],
          supportedLocales: const [Locale('en', 'GB')],
          home: Scaffold(
            child: StatefulBuilder(
              builder: (context, setState) {
                rebuild = () => setState(() {});
                return SingleChildScrollView(
                  child: CalendarEditor(
                    fields: f,
                    enabled: true,
                    onChanged: () => rebuild(),
                  ),
                );
              },
            ),
          ),
        ),
      );
      await tester.tap(find.text('Months'));
      await tester.pumpAndSettle();
      f.interval.text = '12';
      await tester.tap(find.text('Ordinal'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('5'));
      await tester.tap(find.text('5'));
      await tester.pumpAndSettle();
      expect(() => f.candidate(), throwsFormatException);
      await tester.ensureVisible(find.text('Omit'));
      await tester.tap(find.text('Omit'));
      await tester.pumpAndSettle();
      expect((f.candidate() as EveryNMonths).interval, 12);
      expect(
        ((f.candidate() as EveryNMonths).selector as OrdinalWeekday).ordinal,
        5,
      );
      await tester.ensureVisible(find.text('Last'));
      await tester.tap(find.text('Last'));
      await tester.pumpAndSettle();
      expect((f.candidate() as EveryNMonths).selector, isA<LastWeekday>());
      expect(find.text('Omit'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  appTest(
    'monthly controls fit narrow double text keyboard and resized window',
    (tester) async {
      tester.view.physicalSize = const Size(375, 812);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        tester.platformDispatcher.clearTextScaleFactorTestValue();
      });
      await launchPlan(tester);
      await tester.enterText(find.byType(TextField).at(0), '1');
      await tester.enterText(find.byType(TextField).at(1), '0.500');
      await tap(tester, 'Months');
      await fill(tester, const ValueKey('calendarNominalDay'), '31');
      await tap(tester, 'Omit');
      await tester.showKeyboard(
        find.descendant(
          of: find.byKey(const ValueKey('calendarNominalDay')),
          matching: find.byType(TextField),
        ),
      );
      tester.view.physicalSize = const Size(812, 500);
      await settle(tester);
      await tap(tester, 'Preview');
      expect(
        find.textContaining('No dose is planned for this missing date'),
        findsOneWidget,
      );
      await tap(tester, 'Save');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('leap omission and last day show nominal non-drift boundary', (
    tester,
  ) async {
    final amount = PlannedAmount(
      quantity: ExactQuantity.parse('1'),
      unit: 'mg',
    );
    final plan = DailyPlanVersion(
      personId: meId,
      itemId: 'i',
      planId: 'p',
      versionId: 'v',
      start: CivilDate(2027, 1, 1),
      timing: DailyCount(1, amount),
      zoneBasis: FixedHome('UTC'),
      calendar: EveryNMonths(
        anchorMonth: CivilDate(2024, 2, 1),
        interval: 12,
        selector: DayOfMonth(29, missingDatePolicy: MissingDatePolicy.omit),
      ),
    );
    await tester.pumpWidget(
      ShadcnApp(
        localizationsDelegates: const [AppLocalizations.delegate],
        supportedLocales: const [Locale('en', 'GB')],
        home: Scaffold(
          child: CalendarBoundaryPreview(
            plan: plan,
            from: CivilDate(2027, 1, 1),
          ),
        ),
      ),
    );
    expect(
      find.text('2027-02: nominal day 29 does not exist.'),
      findsOneWidget,
    );
    expect(find.textContaining('2028-02-29'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
