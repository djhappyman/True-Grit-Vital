import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:true_grit_vital/app/app_lock.dart';
import 'package:true_grit_vital/app/reminders.dart';
import 'package:true_grit_vital/app/vital_app.dart';
import 'package:true_grit_vital/data/record_store.dart';
import 'package:true_grit_vital/features/plans/pause_editor.dart';
import 'package:true_grit_vital/features/plans/plan_providers.dart';
import 'package:true_grit_vital/features/plans/daily_feed.dart';
import 'package:true_grit_vital/l10n/app_localizations.dart';

import 'calendar_ui_test.dart' show fill;
import 'daily_plan_ui_test.dart' show launchPlan, tap;
import 'reminders/reminder_ui_test.dart' show UiGateway;
import 'vital_app_test.dart' show appTest, runIo, settle;

class PauseGateway extends UiGateway {
  bool available = true;
  Completer<void>? gate;
  @override
  Future<ReminderClockSample> sampleClock() async {
    await gate?.future;
    if (!available) throw TimeoutException('synthetic clock unavailable');
    return clock;
  }
}

void main() {
  test(
    'restarts require an explicit anchor and actual mode stays explicit',
    () {
      DailyPlanVersion plan(DailyTiming timing) => DailyPlanVersion(
        personId: 'person',
        itemId: 'item',
        planId: 'plan',
        versionId: 'old',
        start: CivilDate(2026, 1, 1),
        zoneBasis: FixedHome('UTC'),
        timing: timing,
        pauses: [PlanPause(start: DateTime.utc(2026, 2, 1))],
        onOff: OnOffPattern(
          anchor: CivilDate(2026, 1, 1),
          onDays: 3,
          offDays: 2,
        ),
      );
      final amount = PlannedAmount(
        quantity: ExactQuantity.parse('1'),
        unit: 'mg',
      );
      final p = plan(DailyCount(2, amount));
      expect(
        () => pauseCandidate(
          p,
          versionId: 'new',
          instant: DateTime.utc(2026, 3, 1),
          choice: '',
          restartAnchor: '',
        ),
        throwsFormatException,
      );
      final resumed = pauseCandidate(
        p,
        versionId: 'new',
        instant: DateTime.utc(2026, 3, 1),
        choice: 'restart',
        restartAnchor: '2026-03-05',
      );
      expect(resumed.onOff!.anchor, CivilDate(2026, 3, 5));
      expect(resumed.start, p.start);
      expect(resumed.pauses.single.start, p.pauses.single.start);
      expect(resumed.pauses.single.resume, DateTime.utc(2026, 3, 1));
      final actual = plan(
        ElapsedInterval(
          segmentId: 's',
          duration: ExactElapsed.parseHours('6'),
          mode: IntervalMode.qualifyingActual,
          amount: amount,
        ),
      );
      expect(
        () => pauseCandidate(
          actual,
          versionId: 'new',
          instant: DateTime.utc(2026, 3, 1),
          choice: 'restart',
          restartAnchor: '2026-03-01T08:00Z',
        ),
        throwsFormatException,
      );
    },
  );
  for (final size in [const Size(320, 740), const Size(1200, 900)]) {
    testWidgets('repeating blocks fit $size at double text', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final fields = OnOffFormFields()..enabled = true;
      addTearDown(fields.dispose);
      await tester.pumpWidget(
        ShadcnApp(
          localizationsDelegates: const [AppLocalizations.delegate],
          supportedLocales: const [Locale('en', 'GB')],
          home: MediaQuery(
            data: MediaQueryData(size: size, textScaler: TextScaler.linear(2)),
            child: Scaffold(
              child: SingleChildScrollView(
                child: OnOffEditor(
                  fields: fields,
                  enabled: true,
                  onChanged: () {},
                ),
              ),
            ),
          ),
        ),
      );
      expect(find.text('First active date'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
  appTest(
    'other adult pause preview cancels, preserves progress and resumes one bucket',
    (tester) async {
      tester.view.physicalSize = const Size(375, 812);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        tester.platformDispatcher.clearTextScaleFactorTestValue();
      });
      final f = await launchPlan(tester, person: 'other');
      await tester.enterText(find.byType(TextField).at(0), '2');
      await tester.enterText(find.byType(TextField).at(1), '1.2500');
      await tap(tester, 'Preview');
      await tap(tester, 'Save');
      final saved = (await runIo(
        tester,
        () => f.store.dailyPlans(itemId: f.item.id),
      ))!.single;
      final rows = (await runIo(
        tester,
        () => f.store.todayDailyRows(
          scope: FeedScope.person(f.item.personId),
          now: DateTime.now().toUtc(),
          observedZone: 'Europe/London',
        ),
      ))!.rows;
      await runIo(
        tester,
        () => f.store.actDaily(
          commandId: 'first',
          row: rows.single,
          kind: DailyActionKind.taken,
          actualAt: DateTime.now().toUtc(),
        ),
      );
      f.container
          .read(routerProvider)
          .push('/pause/${f.item.id}?plan=${saved.plan.planId}');
      await settle(tester);
      expect(find.textContaining('Other Adult'), findsWidgets);
      await tap(tester, 'Preview');
      expect(find.textContaining('First affected boundary:'), findsOneWidget);
      await tap(tester, 'Cancel');
      expect(
        (await runIo(
          tester,
          () => f.store.dailyPlans(itemId: f.item.id),
        ))!.single.revision,
        saved.revision,
      );
      await tap(tester, 'Preview');
      await tap(tester, 'Save');
      final paused = (await runIo(
        tester,
        () => f.store.dailyPlans(itemId: f.item.id),
      ))!.single;
      expect(paused.plan.pauses.single.resume, isNull);
      await runIo(
        tester,
        () => f.store.saveBrowsingScope(FeedScope.person(f.item.personId)),
      );
      await settle(tester);
      final taken = tester.widget<PlanCommand>(
        find.byWidgetPredicate((w) => w is PlanCommand && w.label == 'Taken'),
      );
      expect(taken.onPressed, isNull);
      expect(find.textContaining('Record actual use separately'), findsWidgets);
      f.container
          .read(routerProvider)
          .push('/pause/${f.item.id}?plan=${saved.plan.planId}');
      await settle(tester);
      await tap(tester, 'Preview');
      expect(find.textContaining('Choose Preserve or Restart'), findsOneWidget);
      await tap(tester, 'Preserve');
      await tap(tester, 'Preview');
      await tap(tester, 'Save');
      final resumed = (await runIo(
        tester,
        () => f.store.dailyPlans(itemId: f.item.id),
      ))!.single;
      expect(resumed.plan.pauses.single.resume, isNotNull);
      final after = (await runIo(
        tester,
        () => f.store.todayDailyRows(
          scope: FeedScope.person(f.item.personId),
          now: DateTime.now().toUtc(),
          observedZone: 'Europe/London',
        ),
      ))!.rows;
      expect(after.length, 1);
      expect(after.single.takenCount, 1);
      expect(
        after.single.expectation.identity,
        rows.single.expectation.identity,
      );
      expect(after.single.expectation.amount.enteredText, '1.2500');
      expect(tester.takeException(), isNull);
    },
  );
  appTest(
    'repeating block draft keeps malformed entries across lock and reopen',
    (tester) async {
      final f = await launchPlan(tester);
      await tap(tester, 'Repeating breaks');
      await fill(tester, const ValueKey('blockOn'), 'three');
      await fill(tester, const ValueKey('blockOff'), '-1');
      await fill(tester, const ValueKey('blockAnchor'), '2026-02-30');
      await runIo(
        tester,
        () => f.container.read(appLockProvider.notifier).setEnabled(true),
      );
      f.container.read(appLockProvider.notifier).lock();
      await settle(tester);
      expect(find.text('three'), findsNothing);
      await runIo(
        tester,
        () => f.container.read(appLockProvider.notifier).unlock(),
      );
      await settle(tester);
      f.container.read(routerProvider).go('/today');
      await settle(tester);
      await tap(tester, 'Resume');
      final draft = (await runIo(tester, f.store.drafts))!.single;
      expect(draft.fields['blockOn'], 'three');
      expect(draft.fields['blockOff'], '-1');
      expect(draft.fields['blockAnchor'], '2026-02-30');
      expect(
        tester
            .widget<TextField>(
              find.descendant(
                of: find.byKey(const ValueKey('blockOn')),
                matching: find.byType(TextField),
              ),
            )
            .controller!
            .text,
        'three',
      );
    },
  );
  appTest(
    'saved blocks intersect calendar dates and survive an ordinary edit',
    (tester) async {
      final f = await launchPlan(tester);
      await tester.enterText(find.byType(TextField).at(0), '2');
      await tester.enterText(find.byType(TextField).at(1), '1.2500');
      await tap(tester, 'Days');
      await fill(tester, const ValueKey('calendarInterval'), '2');
      final anchor = CivilDate.fromDateTime(DateTime.now());
      await fill(tester, const ValueKey('calendarAnchor'), anchor.toString());
      await tap(tester, 'Repeating breaks');
      await fill(tester, const ValueKey('blockOn'), '3');
      await fill(tester, const ValueKey('blockOff'), '2');
      await fill(tester, const ValueKey('blockAnchor'), anchor.toString());
      await tap(tester, 'Preview');
      expect(
        find.textContaining('3 active days, 2 break days'),
        findsOneWidget,
      );
      expect(
        find.textContaining('both the chosen calendar dates'),
        findsWidgets,
      );
      await tap(tester, 'Save');
      final saved = (await runIo(
        tester,
        () => f.store.dailyPlans(itemId: f.item.id),
      ))!.single;
      expect(saved.plan.onOff!.anchor, anchor);
      expect((saved.plan.calendar as EveryNDays).interval, 2);
      final selected = DailyResolver()
          .expand(
            saved.plan,
            from: anchor,
            toExclusive: anchor.addDays(7),
            maxDates: 7,
            maxRows: 20,
            observedZone: 'Europe/London',
          )
          .rows;
      expect(selected.map((r) => r.identity.originalDate), [
        anchor,
        anchor.addDays(2),
        anchor.addDays(6),
      ]);
      f.container
          .read(routerProvider)
          .push('/pause/${f.item.id}?plan=${saved.plan.planId}');
      await settle(tester);
      await tap(tester, 'Preview');
      await tap(tester, 'Save');
      f.container
          .read(routerProvider)
          .push('/schedule/${f.item.id}?plan=${saved.plan.planId}');
      await settle(tester);
      expect(
        tester
            .widget<TextField>(
              find.descendant(
                of: find.byKey(const ValueKey('blockOn')),
                matching: find.byType(TextField),
              ),
            )
            .controller!
            .text,
        '3',
      );
      await tester.ensureVisible(find.byType(TextField).at(2));
      await tester.enterText(
        find.byType(TextField).at(2),
        anchor.addDays(1).toString(),
      );
      await tap(tester, 'Preview');
      await tap(tester, 'Save');
      final edited = (await runIo(
        tester,
        () => f.store.dailyPlans(itemId: f.item.id),
      ))!.single;
      expect(edited.plan.pauses.single.resume, isNull);
      expect(edited.plan.onOff!.onDays, 3);
      expect(edited.plan.onOff!.offDays, 2);
      expect((edited.plan.calendar as EveryNDays).anchor, anchor);
    },
  );
  for (final available in [true, false]) {
    appTest(
      'restart freezes clock availability $available through failure, lock, reopen and retry',
      (tester) async {
        final f = await launchPlan(tester);
        final now = DateTime.now().toUtc(),
            gateway = PauseGateway()..available = available;
        final owner = (await runIo(
          tester,
          () => f.store.profileById(f.item.personId),
        ))!;
        final plan = DailyPlanVersion(
          personId: owner.id,
          itemId: f.item.id,
          planId: 'retry',
          versionId: 'old',
          start: CivilDate.fromDateTime(now.subtract(const Duration(days: 1))),
          zoneBasis: FixedHome('UTC'),
          pauses: [PlanPause(start: now.subtract(const Duration(hours: 1)))],
          timing: ElapsedInterval(
            segmentId: 'old-segment',
            duration: ExactElapsed.parseHours('6'),
            mode: IntervalMode.fixedPlanned,
            plannedAnchor: now.subtract(const Duration(hours: 2)),
            amount: PlannedAmount(
              quantity: ExactQuantity.parse('1'),
              unit: 'mg',
            ),
          ),
        );
        await runIo(
          tester,
          () => f.store.saveDailyPlan(
            commandId: 'setup-interval',
            plan: plan,
            expectedPersonRevision: owner.revision,
            expectedGeneration: f.store.generation,
            intervalClockSample: gateway.clock,
          ),
        );
        final commands = <String>[], samples = <ReminderClockSample?>[];
        var attempts = 0;
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: f.container,
            child: ProviderScope(
              overrides: [
                reminderGatewayProvider.overrideWithValue(gateway),
                pauseWriterProvider.overrideWithValue((
                  command,
                  review,
                  sample,
                ) async {
                  commands.add(command);
                  samples.add(sample);
                  if (attempts++ == 0) {
                    throw StateError('synthetic precommit failure');
                  }
                  await f.store.savePauseChange(
                    commandId: command,
                    review: review,
                    intervalClockSample: sample,
                  );
                  throw StateError('synthetic reply loss');
                }),
              ],
              child: const VitalApp(),
            ),
          ),
        );
        f.container.invalidate(itemPlansProvider);
        f.container.read(routerProvider).go('/pause/${f.item.id}?plan=retry');
        await settle(tester);
        await tap(tester, 'Restart');
        final resume = now;
        await fill(
          tester,
          const ValueKey('pauseInstant'),
          resume.toIso8601String(),
        );
        await fill(
          tester,
          const ValueKey('restartAnchor'),
          resume.add(const Duration(minutes: 10)).toIso8601String(),
        );
        await tap(tester, 'Preview');
        final sampleGate = Completer<void>();
        gateway.gate = sampleGate;
        await tap(tester, 'Save');
        final pausedInput = tester.widget<TextField>(
          find.descendant(
            of: find.byKey(const ValueKey('pauseInstant')),
            matching: find.byType(TextField),
          ),
        );
        expect(pausedInput.enabled, false);
        sampleGate.complete();
        gateway.gate = null;
        await settle(tester);
        await settle(tester);
        final draft = (await runIo(tester, f.store.drafts))!.single;
        expect(draft.submitted, true);
        expect(
          draft.fields['intervalClockSample'],
          available ? isNotEmpty : isEmpty,
        );
        gateway.available = true;
        gateway.clock = ReminderClockSample(
          utcMilliseconds: now
              .add(const Duration(hours: 3))
              .millisecondsSinceEpoch,
          elapsedMilliseconds: 99999999,
          bootId: 'changed',
        );
        await runIo(
          tester,
          () => f.container.read(appLockProvider.notifier).setEnabled(true),
        );
        f.container.read(appLockProvider.notifier).lock();
        await settle(tester);
        expect(find.text('Planned instant'), findsNothing);
        await runIo(
          tester,
          () => f.container.read(appLockProvider.notifier).unlock(),
        );
        await settle(tester);
        f.container.read(routerProvider).go('/today');
        await settle(tester);
        await tap(tester, 'Resume');
        await tap(tester, 'Retry');
        expect(commands.length, 2);
        expect(commands.toSet().length, 1);
        if (available) {
          expect(samples[1]!.bootId, samples[0]!.bootId);
          expect(samples[1]!.utcMilliseconds, samples[0]!.utcMilliseconds);
          expect(
            samples[1]!.elapsedMilliseconds,
            samples[0]!.elapsedMilliseconds,
          );
        } else {
          expect(samples, [null, null]);
        }
        await tap(tester, 'Retry');
        expect(commands.length, 2);
        final versions = (await runIo(
          tester,
          () => f.store.dailyPlans(itemId: f.item.id),
        ))!;
        expect(versions.single.revision, 2);
        expect(
          (versions.single.plan.timing as ElapsedInterval).segmentId,
          isNot('old-segment'),
        );
        expect(
          (await runIo(
            tester,
            () => f.store.pauseHistory(planId: 'retry', personId: owner.id),
          ))!.length,
          1,
        );
      },
    );
  }
}
