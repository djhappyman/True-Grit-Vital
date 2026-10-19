import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:true_grit_vital/app/reminders.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:true_grit_vital/features/plans/interval_review.dart';
import 'package:true_grit_vital/features/recording/record_pages.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:true_grit_vital/app/vital_app.dart';
import 'package:true_grit_vital/app/app_lock.dart';
import 'package:true_grit_vital/data/record_store.dart';
import 'package:true_grit_vital/features/plans/interval_editor.dart';
import 'package:true_grit_vital/l10n/app_localizations.dart';

import 'calendar_ui_test.dart' show fill;
import 'daily_plan_ui_test.dart' show launchPlan, tap;
import 'reminders/reminder_ui_test.dart' show UiGateway;
import 'vital_app_test.dart' show appTest, runIo, settle;

void main() {
  test(
    'raw interval fields retain malformed input without an implicit anchor',
    () {
      final fields = IntervalFormFields();
      addTearDown(fields.dispose);
      fields.duration.text = 'six';
      fields.anchor.text = '2026-02-30T08:00Z';
      fields.mode = IntervalMode.qualifyingActual;
      final snapshot = fields.capture();
      final restored = IntervalFormFields();
      addTearDown(restored.dispose);
      restored.restore(snapshot);
      expect(restored.capture(), snapshot);
      expect(
        () => restored.candidate(
          PlannedAmount(quantity: ExactQuantity.parse('1'), unit: 'mg'),
        ),
        throwsFormatException,
      );
      restored.duration.text = '6';
      expect(
        restored
            .candidate(
              PlannedAmount(quantity: ExactQuantity.parse('1'), unit: 'mg'),
            )
            .plannedAnchor,
        isNull,
      );
      restored.mode = IntervalMode.fixedPlanned;
      expect(
        () => restored.candidate(
          PlannedAmount(quantity: ExactQuantity.parse('1'), unit: 'mg'),
        ),
        throwsArgumentError,
      );
      restored.anchor.text = '2026-10-19T08:00';
      expect(
        () => restored.candidate(
          PlannedAmount(quantity: ExactQuantity.parse('1'), unit: 'mg'),
        ),
        throwsFormatException,
      );
    },
  );
  test(
    'amount edits preserve segment while timing edits create a fresh segment',
    () {
      final fields = IntervalFormFields();
      addTearDown(fields.dispose);
      final interval = ElapsedInterval(
        segmentId: 'old',
        duration: ExactElapsed.parseHours('6'),
        mode: IntervalMode.qualifyingActual,
        amount: PlannedAmount(quantity: ExactQuantity.parse('1'), unit: 'mg'),
      );
      fields.load(interval);
      expect(
        fields
            .candidate(
              PlannedAmount(quantity: ExactQuantity.parse('2'), unit: 'mg'),
            )
            .segmentId,
        'old',
      );
      fields.duration.text = '7';
      final changed = fields.candidate(interval.amount);
      expect(changed.segmentId, isNot('old'));
      expect(fields.candidate(interval.amount).segmentId, changed.segmentId);
      fields.duration.text = '6';
      expect(fields.candidate(interval.amount).segmentId, 'old');
    },
  );
  for (final size in [const Size(320, 740), const Size(1200, 900)]) {
    testWidgets('interval controls fit $size at double text', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final fields = IntervalFormFields();
      addTearDown(fields.dispose);
      await tester.pumpWidget(
        ShadcnApp(
          localizationsDelegates: const [AppLocalizations.delegate],
          supportedLocales: const [Locale('en', 'GB')],
          home: MediaQuery(
            data: MediaQueryData(size: size, textScaler: TextScaler.linear(2)),
            child: Scaffold(
              child: SingleChildScrollView(
                child: IntervalEditor(
                  fields: fields,
                  enabled: true,
                  onChanged: () {},
                ),
              ),
            ),
          ),
        ),
      );
      expect(find.text('Elapsed hours'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
  appTest('malformed interval draft survives lock and route reopen', (
    tester,
  ) async {
    final f = await launchPlan(tester);
    await tap(tester, 'Interval');
    await fill(tester, const ValueKey('intervalDuration'), 'six');
    await fill(tester, const ValueKey('intervalAnchor'), '2026-10-19T08:00');
    final amountField = find.byType(TextField).at(2);
    await tester.ensureVisible(amountField);
    await tester.enterText(amountField, '1.000');
    await tap(tester, 'Preview');
    expect(find.textContaining('Enter positive elapsed hours'), findsOneWidget);
    await runIo(
      tester,
      () => f.container.read(appLockProvider.notifier).setEnabled(true),
    );
    f.container.read(appLockProvider.notifier).lock();
    await settle(tester);
    expect(find.text('six'), findsNothing);
    await runIo(
      tester,
      () => f.container.read(appLockProvider.notifier).unlock(),
    );
    await settle(tester);
    f.container.read(routerProvider).go('/today');
    await settle(tester);
    await tap(tester, 'Resume');
    final fields = (await runIo(tester, f.store.drafts))!.single.fields;
    expect(fields['intervalDuration'], 'six');
    expect(fields['intervalAnchor'], '2026-10-19T08:00');
    await fill(tester, const ValueKey('intervalDuration'), '6');
    final anchor = DateTime.now().toUtc().subtract(const Duration(hours: 1));
    await fill(
      tester,
      const ValueKey('intervalAnchor'),
      anchor.toIso8601String(),
    );
    await tap(tester, 'Preview');
    expect(find.textContaining('Next planned instant:'), findsOneWidget);
    await tap(tester, 'Save');
    final timing =
        (await runIo(
              tester,
              () => f.store.dailyPlans(itemId: f.item.id),
            ))!.single.plan.timing
            as ElapsedInterval;
    expect(timing.plannedAnchor, anchor);
    expect(timing.amount.enteredText, '1.000');
  });
  appTest(
    'clock recovery review can cancel then explicitly rebase current timing',
    (tester) async {
      final f = await launchPlan(tester);
      final gateway = UiGateway();
      final now = gateway.clock.utc;
      final today = CivilDate.fromDateTime(now);
      final plan = DailyPlanVersion(
        personId: f.item.personId,
        itemId: f.item.id,
        planId: 'recovery',
        versionId: 'recovery-version',
        start: today,
        zoneBasis: FixedHome('UTC'),
        timing: ElapsedInterval(
          segmentId: 'recovery-segment',
          duration: ExactElapsed.parseHours('6'),
          mode: IntervalMode.fixedPlanned,
          plannedAnchor: now,
          reminderEnabled: true,
          amount: PlannedAmount(
            quantity: ExactQuantity.parse('1'),
            enteredText: '1.000',
            unit: 'mg',
          ),
        ),
      );
      final owner = (await runIo(
        tester,
        () => f.store.profileById(f.item.personId),
      ))!;
      await runIo(
        tester,
        () => f.store.saveDailyPlan(
          commandId: 'recovery-save',
          plan: plan,
          expectedPersonRevision: owner.revision,
          expectedGeneration: f.store.generation,
        ),
      );
      final saved = (await runIo(
        tester,
        () => f.store.dailyPlans(itemId: f.item.id),
      ))!.single;
      await runIo(
        tester,
        () => f.store.setPlanReminders(
          commandId: 'recovery-enable',
          planId: saved.plan.planId,
          personId: owner.id,
          expectedPlanRevision: saved.revision,
          expectedPersonRevision: owner.revision,
          enabled: true,
        ),
      );
      Future<ReminderProjection> projection() => f.store.prepareReminders(
        now: now,
        observedZone: 'UTC',
        clockSample: gateway.clock,
        adapterFingerprint: 'test-adapter',
      );
      expect(
        (await runIo(
          tester,
          projection,
        ))!.exclusions.any((e) => e.reason == 'elapsed_clock_recovery'),
        true,
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: f.container,
          child: ProviderScope(
            overrides: [reminderGatewayProvider.overrideWithValue(gateway)],
            child: ShadcnApp(
              localizationsDelegates: const [
                AppLocalizations.delegate,
                GlobalMaterialLocalizations.delegate,
              ],
              supportedLocales: const [Locale('en', 'GB')],
              home: Scaffold(
                child: SingleChildScrollView(
                  child: IntervalClockRecovery(saved: saved),
                ),
              ),
            ),
          ),
        ),
      );
      await settle(tester);
      await tap(tester, 'Review');
      expect(
        find.textContaining('Earlier reminders will not be replayed'),
        findsOneWidget,
      );
      expect(find.textContaining('1.000 mg'), findsOneWidget);
      await tap(tester, 'Cancel');
      expect(
        (await runIo(
          tester,
          projection,
        ))!.exclusions.any((e) => e.reason == 'elapsed_clock_recovery'),
        true,
      );
      await tap(tester, 'Review');
      await tap(tester, 'Save');
      expect(
        (await runIo(
          tester,
          projection,
        ))!.exclusions.any((e) => e.reason == 'elapsed_clock_recovery'),
        false,
      );
    },
  );
  appTest('actual interval has no anchor until a dose is explicitly selected', (
    tester,
  ) async {
    final f = await launchPlan(tester, person: 'other');
    var attempts = 0;
    final commands = <String>[];
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: f.container,
        child: ProviderScope(
          overrides: [
            intervalQualificationWriterProvider.overrideWithValue((
              input,
            ) async {
              commands.add(input.commandId);
              await f.store.qualifyInterval(
                commandId: input.commandId,
                review: input.review,
              );
              if (attempts++ == 0) throw StateError('synthetic reply loss');
            }),
          ],
          child: const VitalApp(),
        ),
      ),
    );
    await settle(tester);
    await tap(tester, 'Interval');
    await tap(tester, 'Recorded');
    await fill(tester, const ValueKey('intervalDuration'), '6');
    final amountField = find.byType(TextField).at(1);
    await tester.ensureVisible(amountField);
    await tester.enterText(amountField, '1.2500');
    await tap(tester, 'Preview');
    expect(find.text('No qualifying dose'), findsOneWidget);
    await tap(tester, 'Save');
    final saved = (await runIo(
      tester,
      () => f.store.dailyPlans(itemId: f.item.id),
    ))!.single;
    expect(
      (saved.plan.timing as ElapsedInterval).mode,
      IntervalMode.qualifyingActual,
    );
    final r = (await runIo(
      tester,
      () => f.store.record(
        commandId: 'extra',
        itemId: f.item.id,
        personId: f.item.personId,
        amount: '1.2500',
        actualAt: DateTime.now().toUtc().subtract(const Duration(hours: 1)),
      ),
    ))!;
    expect(
      (await runIo(
        tester,
        () => f.store.intervalSources(
          planId: saved.plan.planId,
          personId: f.item.personId,
        ),
      ))!,
      isEmpty,
    );
    await runIo(
      tester,
      () => f.store.saveBrowsingScope(FeedScope.person(f.item.personId)),
    );
    f.container.read(routerProvider).go('/history');
    await settle(tester);
    await tap(tester, 'View');
    await tap(tester, 'Review');
    await tap(tester, 'Select');
    expect(find.textContaining('After:'), findsOneWidget);
    await tap(tester, 'Cancel');
    expect(
      (await runIo(
        tester,
        () => f.store.intervalSources(
          planId: saved.plan.planId,
          personId: f.item.personId,
        ),
      ))!,
      isEmpty,
    );
    await tap(tester, 'Select');
    await tap(tester, 'Save');
    expect(
      find.textContaining('The save could not be confirmed'),
      findsWidgets,
    );
    await tap(tester, 'Retry');
    expect(commands.length, 2);
    expect(commands.toSet().length, 1);
    final sources = (await runIo(
      tester,
      () => f.store.intervalSources(
        planId: saved.plan.planId,
        personId: f.item.personId,
      ),
    ))!;
    expect(sources.single.actualId, r.id);
    expect(sources.single.personId, f.item.personId);
    f.container
        .read(routerProvider)
        .push('/correct/${r.id}?person=${r.personId}');
    await settle(tester);
    final changed = r.actualAt.toLocal().subtract(const Duration(minutes: 10));
    final timeField = find.descendant(
      of: find.byWidgetPredicate(
        (w) => w is LabelledInput && w.label == 'Actual time',
      ),
      matching: find.byType(TextField),
    );
    await tester.ensureVisible(timeField);
    await tester.enterText(
      timeField,
      '${changed.hour.toString().padLeft(2, '0')}:${changed.minute.toString().padLeft(2, '0')}',
    );
    await tap(tester, 'Save');
    expect(find.textContaining('Before:'), findsOneWidget);
    expect(find.textContaining('After:'), findsOneWidget);
    await tap(tester, 'Cancel');
    expect(
      (await runIo(
        tester,
        () => f.store.recordById(r.id, personId: r.personId),
      ))!.revision,
      r.revision,
    );
    await tap(tester, 'Save');
    await tap(tester, 'Save');
    final corrected = (await runIo(
      tester,
      () => f.store.recordById(r.id, personId: r.personId),
    ))!;
    expect(corrected.revision, r.revision + 1);
    await tap(tester, 'Undo');
    expect(find.textContaining('After: No qualifying dose'), findsOneWidget);
    await tap(tester, 'Cancel');
    expect(
      (await runIo(
        tester,
        () => f.store.recordById(r.id, personId: r.personId),
      ))!.isVoided,
      false,
    );
    await tap(tester, 'Undo');
    await tap(tester, 'Save');
    expect(
      (await runIo(
        tester,
        () => f.store.recordById(r.id, personId: r.personId),
      ))!.isVoided,
      true,
    );
  });
}
