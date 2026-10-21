import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:true_grit_vital/app/device_zone.dart';
import 'package:true_grit_vital/app/display_preferences.dart';
import 'package:true_grit_vital/app/storage.dart';
import 'package:true_grit_vital/data/record_store.dart';
import 'package:true_grit_vital/features/plans/today_hero.dart';
import 'package:true_grit_vital/l10n/app_localizations.dart';
import 'package:true_grit_vital/platform/device_zone.dart';
import 'package:true_grit_vital/ui/vital_summary.dart';

const _zone = 'Europe/London';

class _FixedHeroDisplayPreferences extends DisplayPreferencesController {
  @override
  DisplayPreferences build() =>
      const DisplayPreferences(timeFormat: TimeFormat.h24);
}

/// A fixed hero clock so a pending start keeps exact minute arithmetic.
final class _ClockHarness {
  DateTime now = DateTime.now().toUtc();
}

PlannedAmount _oneMg() => PlannedAmount(
  quantity: ExactQuantity.parse('1'),
  enteredText: '1',
  unit: 'mg',
);

DailyExpectation _timed({required String plan, DateTime? start}) {
  final instant = start!;
  return DailyExpectation(
    identity: DailyIdentity(
      personId: 'me',
      planId: plan,
      originalDate: CivilDate.fromDateTime(instant),
      slotId: 's',
    ),
    itemId: 'i-$plan',
    versionId: 'v-$plan',
    zoneId: _zone,
    amount: _oneMg(),
    resolution: DailyResolution.exact,
    calculatorVersion: 'test',
    timezoneDataVersion: 'test',
    originalTime: WallTime(9, 0),
    effectiveTime: WallTime(9, 0),
    instant: instant,
    clockCandidates: [instant],
  );
}

DailyExpectation _untimed({required String plan, int planned = 1}) =>
    DailyExpectation(
      identity: DailyIdentity(
        personId: 'me',
        planId: plan,
        originalDate: CivilDate(2026, 10, 21),
      ),
      itemId: 'i-$plan',
      versionId: 'v-$plan',
      zoneId: _zone,
      amount: _oneMg(),
      resolution: DailyResolution.untimed,
      calculatorVersion: 'test',
      timezoneDataVersion: 'test',
      plannedCount: planned,
    );

DailyRow _row(
  DailyExpectation expectation, {
  int taken = 0,
  int skipped = 0,
  bool actionsComplete = true,
}) => DailyRow(
  generation: 'g',
  personRevision: 1,
  planRevision: 1,
  expectation: expectation,
  personName: 'Main Adult',
  itemName: 'Name ${expectation.identity.planId}',
  revision: 0,
  actions: const [],
  takenCount: taken,
  skippedCount: skipped,
  actionsComplete: actionsComplete,
);

Future<void> _pumpHero(
  WidgetTester tester,
  Widget child, {
  _ClockHarness? harness,
  bool zoneUnavailable = false,
  SubstanceItem? item,
}) async {
  final container = ProviderContainer(
    overrides: [
      displayPreferencesProvider.overrideWith(_FixedHeroDisplayPreferences.new),
      observedDeviceZoneProvider.overrideWith(
        (ref) => Stream.value(
          zoneUnavailable
              ? const DeviceZoneObservation.unavailable()
              : DeviceZoneObservation.fromId(_zone),
        ),
      ),
      if (item != null)
        itemLookupProvider.overrideWith((ref, id) => Stream.value(item)),
      if (harness != null)
        todayNowProvider.overrideWithValue(() => harness.now),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: ShadcnApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
        ],
        supportedLocales: const [Locale('en', 'GB')],
        home: Scaffold(child: SingleChildScrollView(child: child)),
      ),
    ),
  );
}

void main() {
  testWidgets('countdown runs from minutes to the due state without a leak', (
    tester,
  ) async {
    final harness = _ClockHarness();
    final target = harness.now.add(const Duration(minutes: 30));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [todayNowProvider.overrideWithValue(() => harness.now)],
        child: ShadcnApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
          ],
          supportedLocales: const [Locale('en', 'GB')],
          home: Scaffold(child: TodayCountdown(target: target)),
        ),
      ),
    );
    expect(find.text('Next dose in 30 minutes.'), findsOneWidget);
    // An early tick keeps the minute count unchanged.
    await tester.pump(const Duration(seconds: 5));
    expect(find.text('Next dose in 30 minutes.'), findsOneWidget);
    // The last minute states the remaining interval; a dose 59 seconds away
    // is not due.
    harness.now = target.subtract(const Duration(seconds: 59));
    await tester.pump(const Duration(minutes: 2));
    expect(find.text('Next dose in under a minute.'), findsOneWidget);
    // The exact expected start reaches the due state.
    harness.now = target;
    await tester.pump(const Duration(minutes: 2));
    expect(find.text('Next dose is due now.'), findsOneWidget);
    // One second past the start stays due.
    harness.now = harness.now.add(const Duration(seconds: 1));
    await tester.pump(const Duration(minutes: 2));
    expect(find.text('Next dose is due now.'), findsOneWidget);
    // The due state holds and arms no further timers.
    await tester.pump(const Duration(hours: 5));
    expect(find.text('Next dose is due now.'), findsOneWidget);
    // Unmount: a leaked timer would schedule further frames and throw here.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(hours: 12));
    expect(tester.takeException(), isNull);
  });

  testWidgets('far targets and a future dose under a minute are not due yet', (
    tester,
  ) async {
    final harness = _ClockHarness();
    final far = TodayCountdown(
      target: harness.now.add(const Duration(minutes: 90)),
    );
    final near = TodayCountdown(
      target: harness.now.add(const Duration(seconds: 30)),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [todayNowProvider.overrideWithValue(() => harness.now)],
        child: ShadcnApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
          ],
          supportedLocales: const [Locale('en', 'GB')],
          home: Scaffold(child: Column(children: [far, near])),
        ),
      ),
    );
    // An hour-away target offers no countdown, and a dose 30 seconds away is
    // still future work, never an early due state.
    expect(find.textContaining('Next dose in'), findsNWidgets(1));
    expect(find.text('Next dose in under a minute.'), findsOneWidget);
    expect(find.text('Next dose is due now.'), findsNothing);
    // Unmount cancels the armed one-shot timers.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(hours: 1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('the countdown re-arms when the target instant changes', (
    tester,
  ) async {
    final harness = _ClockHarness();
    Widget host(int minutes) => ProviderScope(
      overrides: [todayNowProvider.overrideWithValue(() => harness.now)],
      child: ShadcnApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
        ],
        supportedLocales: const [Locale('en', 'GB')],
        home: Scaffold(
          child: TodayCountdown(
            target: harness.now.add(Duration(minutes: minutes)),
          ),
        ),
      ),
    );
    await tester.pumpWidget(host(20));
    expect(find.text('Next dose in 20 minutes.'), findsOneWidget);
    await tester.pumpWidget(host(5));
    expect(find.text('Next dose in 5 minutes.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('hero keeps recorded and skipped separate with the next facts', (
    tester,
  ) async {
    final harness = _ClockHarness();
    final start = harness.now.add(const Duration(minutes: 35));
    final rows = DailyRows(
      rows: [
        _row(_timed(plan: 'timed', start: start)),
        _row(_untimed(plan: 'untimed', planned: 2), taken: 1),
      ],
      complete: true,
    );
    await _pumpHero(
      tester,
      TodayHero(
        result: rows,
        next: const AsyncValue<DailyPlanNextRows>.loading(),
        observedZone: _zone,
      ),
      harness: harness,
    );
    await tester.pump();
    expect(find.text('Daily schedule'), findsOneWidget);
    expect(find.text('1 of 3 doses recorded, 0 skipped.'), findsOneWidget);
    expect(find.text('2 remaining'), findsOneWidget);
    // The measured bar comes from VitalProgress and paints exactly the
    // recorded share of planned doses.
    final bar = tester.widget<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    );
    expect(bar.value, closeTo(1 / 3, 1e-6));
    // The earliest pending start drives the next dose facts.
    expect(find.textContaining('Next planned dose:'), findsOneWidget);
    expect(find.textContaining('Name timed, 1 mg'), findsOneWidget);
    expect(find.textContaining('Next dose in 35 minutes.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('hero reports an untimed day without a fabricated countdown', (
    tester,
  ) async {
    final harness = _ClockHarness();
    final nextTomorrow = DailyPlanNextRow(
      plan: DailyPlanVersion(
        personId: 'me',
        planId: 'count',
        itemId: 'i-count',
        versionId: 'v',
        start: CivilDate(2026, 10, 21),
        timing: DailyCount(2, _oneMg()),
        zoneBasis: FixedHome(_zone),
      ),
      // Untimed plans carry no next instant; only a calendar date.
      result: DailyNext(
        next: null,
        complete: true,
        datesExamined: 1,
        calendarDate: CivilDate(2026, 10, 22),
      ),
    );
    final rows = DailyRows(
      rows: [_row(_untimed(plan: 'count', planned: 3), taken: 2)],
      complete: true,
    );
    await _pumpHero(
      tester,
      TodayHero(
        result: rows,
        next: AsyncValue.data(
          DailyPlanNextRows(rows: [nextTomorrow], complete: true),
        ),
        observedZone: _zone,
      ),
      harness: harness,
    );
    await tester.pump();
    expect(find.text('2 of 3 doses recorded, 0 skipped.'), findsOneWidget);
    expect(find.text('The next dose has no expected time.'), findsOneWidget);
    expect(find.textContaining('Next planned dose:'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a day with no planned doses never claims progress', (
    tester,
  ) async {
    final harness = _ClockHarness();
    await _pumpHero(
      tester,
      TodayHero(
        result: DailyRows(rows: const [], complete: true),
        next: const AsyncValue<DailyPlanNextRows>.loading(),
        observedZone: _zone,
      ),
      harness: harness,
    );
    await tester.pump();
    expect(find.text('No doses are planned today.'), findsOneWidget);
    expect(find.textContaining('remaining'), findsNothing);
    // No meter exists for a zero planned day.
    expect(find.byType(VitalProgress), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a resolved day follows the next timed plan start', (
    tester,
  ) async {
    final harness = _ClockHarness();
    final nextStart = harness.now.add(const Duration(hours: 1));
    final nextShown = DisplayTime().instant(nextStart, _zone);
    final nextWall = WallTime(nextShown.hour, nextShown.minute);
    final summary = DailyPlanNextRow(
      plan: DailyPlanVersion(
        personId: 'me',
        planId: 'slots',
        itemId: 'i-slots',
        versionId: 'v',
        start: nextShown.civilDate,
        timing: DailySlots([
          DailySlot(
            id: 's',
            time: nextWall,
            amount: _oneMg(),
            reminderEnabled: false,
          ),
        ]),
        zoneBasis: FixedHome(_zone),
      ),
      result: DailyNext(
        next: _timed(plan: 'slots', start: nextStart),
        complete: true,
        datesExamined: 1,
      ),
    );
    await _pumpHero(
      tester,
      TodayHero(
        result: DailyRows(
          rows: [
            _row(
              _timed(
                plan: 'done',
                start: harness.now.subtract(const Duration(minutes: 90)),
              ),
              taken: 1,
            ),
          ],
          complete: true,
        ),
        next: AsyncValue.data(
          DailyPlanNextRows(rows: [summary], complete: true),
        ),
        observedZone: _zone,
      ),
      harness: harness,
      item: SubstanceItem(
        id: 'i-slots',
        personId: 'me',
        name: 'Name slots',
        form: 'Tablet',
        unit: 'mg',
        type: 'Medicine',
      ),
    );
    await tester.pump();
    // Today's expectation is decided, so the hero follows the next plan.
    expect(find.textContaining('Next planned dose:'), findsOneWidget);
    expect(find.textContaining('Name slots, 1 mg'), findsOneWidget);
    expect(find.textContaining('Next dose in'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an incompletely calculated day claims no whole-day ratio', (
    tester,
  ) async {
    final harness = _ClockHarness();
    await _pumpHero(
      tester,
      TodayHero(
        result: DailyRows(
          rows: [
            _row(
              _timed(
                plan: 'partial',
                start: harness.now.add(const Duration(minutes: 10)),
              ),
            ),
          ],
          complete: false,
        ),
        next: const AsyncValue<DailyPlanNextRows>.loading(),
        observedZone: _zone,
      ),
      harness: harness,
    );
    await tester.pump();
    // The shown counts stay visible as provisional facts, and no bar or
    // remaining whole-day total is drawn.
    expect(find.textContaining('so far.'), findsOneWidget);
    expect(
      find.text('The calculation limit was reached. This view is incomplete.'),
      findsOneWidget,
    );
    expect(find.textContaining('remaining'), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.byType(VitalProgress), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a row with incomplete action history keeps counts provisional', (
    tester,
  ) async {
    final harness = _ClockHarness();
    await _pumpHero(
      tester,
      TodayHero(
        result: DailyRows(
          rows: [
            _row(
              _untimed(plan: 'actions', planned: 2),
              taken: 1,
              actionsComplete: false,
            ),
          ],
          complete: true,
        ),
        next: const AsyncValue<DailyPlanNextRows>.loading(),
        observedZone: _zone,
      ),
      harness: harness,
    );
    await tester.pump();
    expect(find.textContaining('so far.'), findsOneWidget);
    expect(
      find.text('Some dose actions are still loading. Counts may change.'),
      findsOneWidget,
    );
    expect(find.textContaining('remaining'), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final complete in [true, false]) {
    testWidgets(
      'an empty shown day shows future dose with complete=$complete',
      (tester) async {
        final harness = _ClockHarness();
        final nextStart = harness.now.add(const Duration(days: 1));
        final nextShown = DisplayTime().instant(nextStart, _zone);
        final summary = DailyPlanNextRow(
          plan: DailyPlanVersion(
            personId: 'me',
            planId: 'future',
            itemId: 'i-future',
            versionId: 'v',
            start: nextShown.civilDate,
            timing: DailySlots([
              DailySlot(
                id: 's',
                time: WallTime(nextShown.hour, nextShown.minute),
                amount: _oneMg(),
                reminderEnabled: false,
              ),
            ]),
            zoneBasis: FixedHome(_zone),
          ),
          result: DailyNext(
            next: _timed(plan: 'future', start: nextStart),
            complete: true,
            datesExamined: 1,
          ),
        );
        await _pumpHero(
          tester,
          TodayHero(
            result: DailyRows(rows: const [], complete: true),
            next: AsyncValue.data(
              DailyPlanNextRows(rows: [summary], complete: complete),
            ),
            observedZone: _zone,
          ),
          harness: harness,
          item: SubstanceItem(
            id: 'i-future',
            personId: 'me',
            name: 'Name future',
            form: 'Tablet',
            unit: 'mg',
            type: 'Medicine',
          ),
        );
        await tester.pump();
        expect(find.text('No doses are planned today.'), findsOneWidget);
        // The future dose keeps its substance, planned amount and zone stamp.
        expect(find.textContaining('Next planned dose:'), findsOneWidget);
        expect(find.textContaining('Name future, 1 mg'), findsOneWidget);
        expect(find.textContaining('Europe/London'), findsOneWidget);
        if (!complete) {
          final t = AppLocalizations.of(tester.element(find.byType(TodayHero)));
          expect(find.text(t.planIncomplete), findsOneWidget);
        }
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('a future plan without a substance name stays anonymous', (
    tester,
  ) async {
    final harness = _ClockHarness();
    final nextStart = harness.now.add(const Duration(days: 1));
    final nextShown = DisplayTime().instant(nextStart, _zone);
    final summary = DailyPlanNextRow(
      plan: DailyPlanVersion(
        personId: 'me',
        planId: 'future',
        itemId: 'i-future',
        versionId: 'v',
        start: nextShown.civilDate,
        timing: DailySlots([
          DailySlot(
            id: 's',
            time: WallTime(nextShown.hour, nextShown.minute),
            amount: _oneMg(),
            reminderEnabled: false,
          ),
        ]),
        zoneBasis: FixedHome(_zone),
      ),
      result: DailyNext(
        next: _timed(plan: 'future', start: nextStart),
        complete: true,
        datesExamined: 1,
      ),
    );
    await _pumpHero(
      tester,
      TodayHero(
        result: DailyRows(rows: const [], complete: true),
        next: AsyncValue.data(
          DailyPlanNextRows(rows: [summary], complete: true),
        ),
        observedZone: _zone,
      ),
      harness: harness,
    );
    await tester.pump();
    // No substance name is invented while its lookup is unavailable.
    expect(find.textContaining('Name '), findsNothing);
    expect(find.textContaining('Next planned dose:'), findsOneWidget);
    expect(find.textContaining('1 mg'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final failed in [false, true]) {
    testWidgets(
      'next dose keeps its pending or failed state visible: $failed',
      (tester) async {
        await _pumpHero(
          tester,
          TodayHero(
            result: DailyRows(rows: const [], complete: true),
            next: failed
                ? AsyncValue<DailyPlanNextRows>.error(
                    StateError('synthetic'),
                    StackTrace.current,
                  )
                : const AsyncValue<DailyPlanNextRows>.loading(),
            observedZone: _zone,
          ),
          harness: _ClockHarness(),
        );
        final t = AppLocalizations.of(tester.element(find.byType(TodayHero)));
        expect(
          find.text(failed ? t.planNextReview : t.loadingRecords),
          findsOneWidget,
        );
      },
    );
  }

  testWidgets('an unavailable device zone labels the shown UTC date', (
    tester,
  ) async {
    final harness = _ClockHarness();
    await _pumpHero(
      tester,
      TodayHero(
        result: DailyRows(rows: const [], complete: true),
        next: const AsyncValue<DailyPlanNextRows>.loading(),
        observedZone: null,
      ),
      harness: harness,
      zoneUnavailable: true,
    );
    await tester.pump();
    // The date stays shown, but explicitly as the UTC fallback rather than a
    // claimed local day.
    expect(find.textContaining('(UTC)'), findsOneWidget);
    final dateLine = tester.widget<Text>(find.textContaining('(UTC)'));
    expect(dateLine.data, contains('(UTC)'));
    expect(tester.takeException(), isNull);
  });
}
