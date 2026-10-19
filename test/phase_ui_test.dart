import 'package:true_grit_vital/app/display_preferences.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'dart:convert';
import 'dart:async';

import 'package:true_grit_vital/app/reminders.dart';

import 'pause_ui_test.dart' show PauseGateway;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:true_grit_vital/app/app_lock.dart';
import 'package:true_grit_vital/app/vital_app.dart';
import 'package:true_grit_vital/data/record_store.dart';
import 'package:true_grit_vital/features/plans/phase_editor.dart';
import 'package:true_grit_vital/features/plans/plan_form.dart';
import 'package:true_grit_vital/features/plans/plan_providers.dart';
import 'package:true_grit_vital/l10n/app_localizations.dart';

import 'daily_plan_ui_test.dart' show launchPlan, tap;
import 'calendar_ui_test.dart' show fill;
import 'vital_app_test.dart' show appTest, runIo, settle;

class PreviewDisplayPreferences extends DisplayPreferencesController {
  @override
  DisplayPreferences build() =>
      const DisplayPreferences(timeFormat: TimeFormat.h24);
}

void main() {
  test('raw phase fields recover without parsing invalid values and preserve exact source bounds', () {
    final amount = PlannedAmount(
      quantity: ExactQuantity.parse('1.2500'),
      unit: 'mg',
      enteredText: '1.2500',
    );
    final source = DailyPlanVersion(
      personId: 'p',
      itemId: 'i',
      planId: 'plan',
      versionId: 'v',
      start: CivilDate(2026, 10, 19),
      zoneBasis: FixedHome('UTC'),
      effectiveFrom: DateTime.utc(2026, 10, 19, 8),
      effectiveUntil: DateTime.utc(2026, 10, 19, 17),
      timing: DailyCount(3, amount),
    );
    final entry = PhaseEntry()..load(source), recovered = PhaseEntry();
    addTearDown(entry.dispose);
    addTearDown(recovered.dispose);
    final unchanged = entry.candidate(source, 'mg');
    expect(unchanged.effectiveFrom, source.effectiveFrom);
    expect(unchanged.effectiveUntil, source.effectiveUntil);
    expect(unchanged.versionId, 'v');
    entry.count.text = 'three';
    entry.start.text = '2026-02-30';
    recovered.restore(
      Map<String, dynamic>.from(jsonDecode(jsonEncode(entry.capture())) as Map),
    );
    expect(recovered.count.text, 'three');
    expect(recovered.start.text, '2026-02-30');
    expect(recovered.source!.effectiveFrom, source.effectiveFrom);
  });
  test(
    'interval phase draft restores original segment before applying raw fields',
    () {
      final p = DailyPlanVersion(
        personId: 'p',
        itemId: 'i',
        planId: 'plan',
        versionId: 'v',
        start: CivilDate(2026, 10, 19),
        zoneBasis: FixedHome('UTC'),
        timing: ElapsedInterval(
          segmentId: 'original-segment',
          duration: ExactElapsed.parseHours('6'),
          mode: IntervalMode.fixedPlanned,
          plannedAnchor: DateTime.utc(2026, 10, 19, 8),
          amount: PlannedAmount(quantity: ExactQuantity.parse('1'), unit: 'mg'),
        ),
      );
      final entry = PhaseEntry()..load(p), recovered = PhaseEntry();
      addTearDown(entry.dispose);
      addTearDown(recovered.dispose);
      recovered.restore(
        Map<String, dynamic>.from(
          jsonDecode(jsonEncode(entry.capture())) as Map,
        ),
      );
      final result = recovered.candidate(p, 'mg');
      expect(result.versionId, 'v');
      expect((result.timing as ElapsedInterval).segmentId, 'original-segment');
    },
  );
  test(
    'mixed counts retain slots and untimed amount without inferred spacing',
    () {
      final base = DailyPlanVersion(
        personId: 'p',
        itemId: 'i',
        planId: 'plan',
        versionId: 'v',
        start: CivilDate(2026, 10, 19),
        zoneBasis: FixedHome('UTC'),
        timing: const AsNeeded(),
      );
      final entry = PhaseEntry()
        ..start.text = '2026-10-19'
        ..mode = 'mixed'
        ..count.text = '3'
        ..amount.text = '1.000';
      entry.slots.add(PlanSlotEntry(time: '23:30', amount: '2.00'));
      addTearDown(entry.dispose);
      final timing = entry.candidate(base, 'mg').timing as MixedDailyCount;
      expect(timing.count, 3);
      expect(timing.slots.single.time, WallTime(23, 30));
      expect(timing.amount.enteredText, '1.000');
      entry.count.text = '1';
      expect(() => entry.candidate(base, 'mg'), throwsArgumentError);
    },
  );
  appTest(
    'finite review belongs to other adult, cancels without writes then saves inclusive zone end',
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
      f.container
          .read(routerProvider)
          .push('/phases/${f.item.id}?plan=${saved.plan.planId}');
      await settle(tester);
      await settle(tester);
      expect(find.textContaining('Other Adult'), findsWidgets);
      await tap(tester, 'Last day');
      final last = CivilDate.fromDateTime(DateTime.now()).addDays(2);
      await fill(tester, const ValueKey('phaseEndValue'), last.toString());
      await fill(tester, const ValueKey('phaseEndZone'), 'Europe/London');
      await tap(tester, 'Preview');
      expect(find.textContaining('1.2500 mg'), findsWidgets);
      expect(find.textContaining('Saved zone: Europe/London'), findsOneWidget);
      await tap(tester, 'Cancel');
      expect(
        await runIo(
          tester,
          () => f.store.phasePlan(
            planId: saved.plan.planId,
            personId: f.item.personId,
          ),
        ),
        isNull,
      );
      await tap(tester, 'Preview');
      await tap(tester, 'Save');
      final aggregate = (await runIo(
        tester,
        () => f.store.phasePlan(
          planId: saved.plan.planId,
          personId: f.item.personId,
        ),
      ))!;
      expect(aggregate.end!.lastDate, last);
      expect(aggregate.end!.zoneId, 'Europe/London');
      expect(aggregate.phases.single.personId, f.item.personId);
      f.container
          .read(routerProvider)
          .push('/phases/${f.item.id}?plan=${saved.plan.planId}');
      await settle(tester);
      await settle(tester);
      await fill(
        tester,
        const ValueKey('phaseOriginalDate'),
        CivilDate.fromDateTime(DateTime.now()).toString(),
      );
      await tap(tester, 'Review');
      expect(
        find.textContaining('This group has 2 untimed doses'),
        findsOneWidget,
      );
      expect(find.text('Select'), findsNothing);
      await tap(tester, 'Record');
      expect(find.textContaining('Other Adult'), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );
  appTest('invalid raw phase recovers after lock and route reopen', (
    tester,
  ) async {
    final f = await launchPlan(tester);
    await tester.enterText(find.byType(TextField).at(0), '2');
    await tester.enterText(find.byType(TextField).at(1), '1');
    await tap(tester, 'Preview');
    await tap(tester, 'Save');
    final saved = (await runIo(
      tester,
      () => f.store.dailyPlans(itemId: f.item.id),
    ))!.single;
    f.container
        .read(routerProvider)
        .push('/phases/${f.item.id}?plan=${saved.plan.planId}');
    await settle(tester);
    await settle(tester);
    await fill(
      tester,
      ValueKey('phaseStart-${saved.plan.versionId}'),
      '2026-02-30',
    );
    await tap(tester, 'Preview');
    expect(find.textContaining('Check phase dates'), findsOneWidget);
    await runIo(
      tester,
      () => f.container.read(appLockProvider.notifier).setEnabled(true),
    );
    f.container.read(appLockProvider.notifier).lock();
    await settle(tester);
    expect(find.text('2026-02-30'), findsNothing);
    await runIo(
      tester,
      () => f.container.read(appLockProvider.notifier).unlock(),
    );
    await settle(tester);
    f.container.read(routerProvider).go('/today');
    await settle(tester);
    await tap(tester, 'Resume');
    await settle(tester);
    final field = tester.widget<TextField>(
      find.descendant(
        of: find.byKey(ValueKey('phaseStart-${saved.plan.versionId}')),
        matching: find.byType(TextField),
      ),
    );
    expect(field.controller!.text, '2026-02-30');
    expect(tester.takeException(), isNull);
  });
  appTest(
    'one-off move across phase retains original amount and reviews collision',
    (tester) async {
      final f = await launchPlan(tester, person: 'other');
      final date = CivilDate.fromDateTime(DateTime.now().toUtc()).addDays(1),
          owner = (await runIo(
            tester,
            () => f.store.profileById(f.item.personId),
          ))!;
      PlannedAmount amount(String text) => PlannedAmount(
        quantity: ExactQuantity.parse(text),
        unit: 'mg',
        enteredText: text,
      );
      final first = DailyPlanVersion(
        personId: owner.id,
        itemId: f.item.id,
        planId: 'move',
        versionId: 'first',
        start: date,
        endExclusive: date.addDays(1),
        zoneBasis: FixedHome('UTC'),
        timing: DailySlots([
          DailySlot(
            id: 'a',
            time: WallTime(23, 30),
            amount: amount('1.2500'),
            reminderEnabled: false,
          ),
        ]),
      );
      final saved = (await runIo(
        tester,
        () => f.store.saveDailyPlan(
          commandId: 'first',
          plan: first,
          expectedPersonRevision: owner.revision,
          expectedGeneration: f.store.generation,
        ),
      ))!;
      final second = DailyPlanVersion(
        personId: owner.id,
        itemId: f.item.id,
        planId: 'move',
        versionId: 'second',
        start: date.addDays(1),
        zoneBasis: FixedHome('UTC'),
        timing: DailySlots([
          DailySlot(
            id: 'b',
            time: WallTime(0, 30),
            amount: amount('2.000'),
            reminderEnabled: false,
          ),
        ]),
      );
      final review = (await runIo(
        tester,
        () => f.store.previewPhasePlan(
          plan: saved,
          proposed: PhasePlan(phases: [first, second]),
          now: DateTime.now().toUtc(),
          observedZone: 'UTC',
        ),
      ))!;
      await runIo(
        tester,
        () => f.store.savePhasePlan(commandId: 'phases', review: review),
      );
      f.container.invalidate(itemPlansProvider);
      f.container.read(routerProvider).go('/phases/${f.item.id}?plan=move');
      await settle(tester);
      await settle(tester);
      await fill(tester, const ValueKey('phaseOriginalDate'), date.toString());
      await tap(tester, 'Review');
      await tap(tester, 'Select');
      final moved = DateTime.utc(
        date.addDays(1).year,
        date.addDays(1).month,
        date.addDays(1).day,
        0,
        30,
      );
      await fill(
        tester,
        const ValueKey('phaseTarget'),
        moved.toIso8601String(),
      );
      await tap(tester, 'Add');
      expect(
        find.textContaining('Separate doses share this time'),
        findsOneWidget,
      );
      expect(find.textContaining('2.000 mg'), findsWidgets);
      await tap(tester, 'Review');
      await tap(tester, 'Add');
      expect(find.textContaining('Original:'), findsWidgets);
      expect(find.textContaining('1.2500 mg'), findsWidgets);
      await tap(tester, 'Preview');
      await tap(tester, 'Save');
      final aggregate = (await runIo(
        tester,
        () => f.store.phasePlan(planId: 'move', personId: owner.id),
      ))!;
      final override = aggregate.overrides.single;
      expect(override.identity.originalDate, date);
      expect(override.identity.slotId, 'a');
      expect(override.amount, isNull);
      expect(override.reviewedCollisions.single.slotId, 'b');
      final rows = PhaseResolver().resolveDate(
        aggregate,
        date.addDays(1),
        observedZone: 'UTC',
      );
      expect(
        rows.map((r) => r.amount.enteredText),
        containsAll(['1.2500', '2.000']),
      );
      expect(rows.map((r) => r.identity).toSet().length, 2);
      expect(tester.takeException(), isNull);
    },
  );
  appTest(
    'one-off window move retains both explicit endpoints and reminder anchor',
    (tester) async {
      final f = await launchPlan(tester),
          date = CivilDate.fromDateTime(DateTime.now().toUtc()).addDays(1),
          owner = (await runIo(
            tester,
            () => f.store.profileById(f.item.personId),
          ))!;
      final plan = DailyPlanVersion(
        personId: owner.id,
        itemId: f.item.id,
        planId: 'window-move',
        versionId: 'window-first',
        start: date,
        zoneBasis: FixedHome('UTC'),
        timing: DailyWindows(
          windows: [
            DailyWindow(
              id: 'w',
              start: WallTime(23, 0),
              end: WallTime(1, 0),
              amount: PlannedAmount(
                quantity: ExactQuantity.parse('1.2500'),
                unit: 'mg',
                enteredText: '1.2500',
              ),
              reminderAnchor: WallTime(23, 30),
            ),
          ],
        ),
      );
      await runIo(
        tester,
        () => f.store.saveDailyPlan(
          commandId: 'window',
          plan: plan,
          expectedPersonRevision: owner.revision,
          expectedGeneration: f.store.generation,
        ),
      );
      f.container.invalidate(itemPlansProvider);
      f.container
          .read(routerProvider)
          .go('/phases/${f.item.id}?plan=window-move');
      await settle(tester);
      await settle(tester);
      await fill(tester, const ValueKey('phaseOriginalDate'), date.toString());
      await tap(tester, 'Review');
      await tap(tester, 'Select');
      await fill(tester, const ValueKey('phaseTarget'), '2026-02-30T20:00Z');
      await fill(tester, const ValueKey('phaseWindowTargetEnd'), 'unfinished');
      await runIo(
        tester,
        () => f.container.read(appLockProvider.notifier).setEnabled(true),
      );
      f.container.read(appLockProvider.notifier).lock();
      await settle(tester);
      await runIo(
        tester,
        () => f.container.read(appLockProvider.notifier).unlock(),
      );
      await settle(tester);
      f.container.read(routerProvider).go('/today');
      await settle(tester);
      await tap(tester, 'Resume');
      await settle(tester);
      expect(
        tester
            .widget<TextField>(
              find.descendant(
                of: find.byKey(const ValueKey('phaseWindowTargetEnd')),
                matching: find.byType(TextField),
              ),
            )
            .controller!
            .text,
        'unfinished',
      );
      final targetDate = date.addDays(1),
          start = DateTime.utc(
            targetDate.year,
            targetDate.month,
            targetDate.day,
            20,
          ),
          end = DateTime.utc(
            targetDate.year,
            targetDate.month,
            targetDate.day,
            22,
          ),
          anchor = DateTime.utc(
            targetDate.year,
            targetDate.month,
            targetDate.day,
            21,
          );
      await fill(
        tester,
        const ValueKey('phaseTarget'),
        start.toIso8601String(),
      );
      await fill(
        tester,
        const ValueKey('phaseWindowTargetEnd'),
        end.toIso8601String(),
      );
      await fill(
        tester,
        const ValueKey('phaseWindowTargetAnchor'),
        anchor.toIso8601String(),
      );
      await tap(tester, 'Add');
      expect(find.textContaining('Original window:'), findsWidgets);
      expect(find.textContaining('Changed window:'), findsWidgets);
      await tap(tester, 'Preview');
      await tap(tester, 'Save');
      final aggregate = (await runIo(
            tester,
            () => f.store.phasePlan(planId: 'window-move', personId: owner.id),
          ))!,
          override = aggregate.overrides.single;
      expect(override.identity.originalDate, date);
      expect(override.windowTarget!.start, start);
      expect(override.windowTarget!.end, end);
      expect(override.windowTarget!.reminderAnchor, anchor);
      expect(override.targetInstant, isNull);
      expect(override.amount, isNull);
      expect(tester.takeException(), isNull);
    },
  );
  appTest(
    'actual phase review names missing qualifying source and offers Record',
    (tester) async {
      final f = await launchPlan(tester),
          owner = (await runIo(
            tester,
            () => f.store.profileById(f.item.personId),
          ))!;
      final plan = DailyPlanVersion(
        personId: owner.id,
        itemId: f.item.id,
        planId: 'no-anchor',
        versionId: 'no-anchor-v',
        start: CivilDate.fromDateTime(DateTime.now().toUtc()),
        zoneBasis: FixedHome('UTC'),
        timing: ElapsedInterval(
          segmentId: 'no-source',
          duration: ExactElapsed.parseHours('6'),
          mode: IntervalMode.qualifyingActual,
          amount: PlannedAmount(quantity: ExactQuantity.parse('1'), unit: 'mg'),
        ),
      );
      await runIo(
        tester,
        () => f.store.saveDailyPlan(
          commandId: 'no-source-plan',
          plan: plan,
          expectedPersonRevision: owner.revision,
          expectedGeneration: f.store.generation,
        ),
      );
      f.container.invalidate(itemPlansProvider);
      f.container
          .read(routerProvider)
          .go('/phases/${f.item.id}?plan=no-anchor');
      await settle(tester);
      await settle(tester);
      await tap(tester, 'Preview');
      expect(find.text('Before: No qualifying dose'), findsOneWidget);
      expect(find.text('After: No qualifying dose'), findsOneWidget);
      expect(
        find.text(
          'Record a dose, then review whether it qualifies for this plan.',
        ),
        findsWidgets,
      );
      await tap(tester, 'Record');
      expect(tester.takeException(), isNull);
    },
  );
  for (final available in [true, false]) {
    appTest(
      'phase retry freezes clock $available through lock and lost reply',
      (tester) async {
        final f = await launchPlan(tester),
            gateway = PauseGateway()..available = available;
        final now = DateTime.now().toUtc(),
            owner = (await runIo(
              tester,
              () => f.store.profileById(f.item.personId),
            ))!;
        final plan = DailyPlanVersion(
          personId: owner.id,
          itemId: f.item.id,
          planId: 'phase-retry',
          versionId: 'phase-old',
          start: CivilDate.fromDateTime(now),
          zoneBasis: FixedHome('UTC'),
          timing: ElapsedInterval(
            segmentId: 'old',
            duration: ExactElapsed.parseHours('6'),
            mode: IntervalMode.fixedPlanned,
            plannedAnchor: now.add(const Duration(hours: 1)),
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
                phaseWriterProvider.overrideWithValue((
                  command,
                  review,
                  sample,
                ) async {
                  commands.add(command);
                  samples.add(sample);
                  if (attempts++ == 0) throw StateError('synthetic precommit');
                  await f.store.savePhasePlan(
                    commandId: command,
                    review: review,
                    intervalClockSample: sample,
                  );
                  throw StateError('synthetic lost reply');
                }),
              ],
              child: const VitalApp(),
            ),
          ),
        );
        f.container.invalidate(itemPlansProvider);
        f.container
            .read(routerProvider)
            .go('/phases/${f.item.id}?plan=phase-retry');
        await settle(tester);
        await settle(tester);
        await tap(tester, 'Exact end');
        await fill(
          tester,
          const ValueKey('phaseEndValue'),
          now.add(const Duration(days: 2)).toIso8601String(),
        );
        await fill(tester, const ValueKey('phaseEndZone'), 'UTC');
        await tap(tester, 'Preview');
        final gate = Completer<void>();
        gateway.gate = gate;
        await tap(tester, 'Save');
        final input = tester.widget<TextField>(
          find.descendant(
            of: find.byKey(const ValueKey('phaseEndValue')),
            matching: find.byType(TextField),
          ),
        );
        expect(input.enabled, false);
        gate.complete();
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
        await runIo(
          tester,
          () => f.container.read(appLockProvider.notifier).unlock(),
        );
        await settle(tester);
        f.container.read(routerProvider).go('/today');
        await settle(tester);
        await tap(tester, 'Resume');
        await settle(tester);
        await tap(tester, 'Retry');
        await settle(tester);
        expect(attempts, 2);
        expect(commands.toSet().length, 1);
        expect(samples[0]?.bootId, samples[1]?.bootId);
        expect(samples[0]?.utcMilliseconds, samples[1]?.utcMilliseconds);
        expect(
          samples[0]?.elapsedMilliseconds,
          samples[1]?.elapsedMilliseconds,
        );
        expect(samples[1]?.bootId, available ? isNot('changed') : isNull);
        await tap(tester, 'Retry');
        await settle(tester);
        expect(attempts, 2);
        expect(
          await runIo(
            tester,
            () => f.store.phasePlan(planId: 'phase-retry', personId: owner.id),
          ),
          isNotNull,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
  for (final size in [const Size(320, 740), const Size(1200, 900)]) {
    testWidgets(
      'window preview keeps explicit endpoints at double text $size',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final p = DailyPlanVersion(
          personId: 'p',
          itemId: 'i',
          planId: 'plan',
          versionId: 'v',
          start: CivilDate.fromDateTime(DateTime.now()),
          zoneBasis: FixedHome('UTC'),
          timing: DailyWindows(
            windows: [
              DailyWindow(
                id: 'w',
                start: WallTime(23, 0),
                end: WallTime(1, 0),
                amount: PlannedAmount(
                  quantity: ExactQuantity.parse('1.2500'),
                  unit: 'mg',
                  enteredText: '1.2500',
                ),
                reminderAnchor: WallTime(23, 30),
              ),
            ],
          ),
        );
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              displayPreferencesProvider.overrideWith(
                PreviewDisplayPreferences.new,
              ),
            ],
            child: ShadcnApp(
              localizationsDelegates: const [
                AppLocalizations.delegate,
                GlobalMaterialLocalizations.delegate,
              ],
              supportedLocales: const [Locale('en', 'GB')],
              home: MediaQuery(
                data: MediaQueryData(
                  size: size,
                  textScaler: TextScaler.linear(2),
                ),
                child: Scaffold(
                  child: SingleChildScrollView(
                    child: PlanPreview(plan: p, observedZone: 'UTC'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.textContaining('23:00, UTC (UTC+00:00) to'), findsWidgets);
        expect(
          find.textContaining('01:00, UTC (UTC+00:00), 1.2500 mg'),
          findsWidgets,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}
