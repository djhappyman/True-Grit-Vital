import 'package:flutter_test/flutter_test.dart';
import 'package:true_grit_vital/domain/records.dart';
import 'package:true_grit_vital/domain/scheduling/daily_plan.dart';
import 'package:true_grit_vital/domain/scheduling/iana_clock.dart';
import 'package:true_grit_vital/domain/scheduling/phase_plan.dart';
import 'package:true_grit_vital/domain/stock/stock_forecast.dart';
import 'package:true_grit_vital/domain/stock/stored_stock.dart';

void main() {
  final now = DateTime.utc(2026, 10, 22, 12);
  ExactAmount amount(String text) => ExactAmount.parseEntry(text);
  LabelledStrength strength({
    String? mgPerMl = '10',
    String ingredient = 'ingredient',
  }) => LabelledStrength(
    ingredientId: ingredient,
    label: mgPerMl == null ? 'Unknown' : '$mgPerMl mg/ml',
    mgPerMl: mgPerMl == null ? null : amount(mgPerMl),
  );
  PlannedAmount planned(String text, String unit) => PlannedAmount(
    quantity: ExactQuantity.parse(text),
    enteredText: text,
    unit: unit,
  );
  PhasePlan plan(
    DailyTiming timing, {
    CalendarPattern calendar = const EveryDay(),
    Iterable<PlanPause> pauses = const [],
    PlanEnd? end,
    CivilDate? start,
    CivilDate? endExclusive,
    DailyZoneBasis? zoneBasis,
  }) => PhasePlan(
    phases: [
      DailyPlanVersion(
        personId: meId,
        planId: 'plan',
        itemId: 'item',
        versionId: 'v1',
        start: start ?? CivilDate(2020, 1, 1),
        endExclusive: endExclusive,
        timing: timing,
        zoneBasis: zoneBasis ?? FixedHome('UTC'),
        calendar: calendar,
        pauses: pauses,
      ),
    ],
    end: end,
  );
  StockRunOutForecast forecast(
    String balance,
    Iterable<PhasePlan> plans, {
    String unit = 'ml',
    LabelledStrength? labelled,
    String? zone = 'UTC',
  }) => forecastStockRunOut(
    balance: StockBalance(amount(balance)),
    unit: unit,
    strength: labelled ?? strength(),
    plans: plans,
    now: now,
    observedZone: zone,
  );

  test('daily planned use exhausts the exact balance on a civil date', () {
    final result = forecast('10', [plan(DailyCount(1, planned('2', 'ml')))]);
    expect(result.isAvailable, true);
    expect(result.date, CivilDate(2026, 10, 27));
    expect(result.days, 5);
    expect(result.plannedThrough, CivilDate(2026, 10, 27));
  });

  test('selected weekdays use the calendar engine without a daily average', () {
    final result = forecast('3', [
      plan(
        DailyCount(1, planned('1', 'ml')),
        calendar: SelectedWeekdays([DateTime.monday]),
      ),
    ]);
    // 23 Oct 2026 is Friday. Mondays are 26 Oct, 2 Nov, 9 Nov.
    expect(result.date, CivilDate(2026, 11, 9));
  });

  test('unit conversion uses the labelled strength exactly', () {
    final result = forecast('30', [plan(DailyCount(1, planned('100', 'mg')))]);
    expect(result.date, CivilDate(2026, 10, 25));
  });

  test('explicit unavailable states are never guessed dates', () {
    expect(
      forecast('10', [plan(const AsNeeded())]).reason,
      StockForecastReason.asNeeded,
    );
    expect(
      forecastStockRunOut(
        balance: const StockBalance(null),
        unit: 'ml',
        strength: strength(),
        plans: [plan(DailyCount(1, planned('1', 'ml')))],
        now: now,
        observedZone: 'UTC',
      ).reason,
      StockForecastReason.unknownBalance,
    );
    expect(
      forecastStockRunOut(
        balance: const StockBalance(null, limitReached: true),
        unit: 'ml',
        strength: strength(),
        plans: [plan(DailyCount(1, planned('1', 'ml')))],
        now: now,
        observedZone: 'UTC',
      ).reason,
      StockForecastReason.aggregateLimit,
    );
    expect(
      forecastStockRunOut(
        balance: StockBalance(ExactAmount(BigInt.from(-1))),
        unit: 'ml',
        strength: strength(),
        plans: [plan(DailyCount(1, planned('1', 'ml')))],
        now: now,
        observedZone: 'UTC',
      ).reason,
      StockForecastReason.deficit,
    );
    expect(
      forecast('10', [plan(DailyCount(1, planned('1', 'count')))]).reason,
      StockForecastReason.incompatibleUnits,
    );
    expect(
      forecast('10', [
        plan(DailyCount(1, planned('1', 'count'))),
      ], labelled: strength(mgPerMl: null)).reason,
      StockForecastReason.incompatibleUnits,
    );
    expect(forecast('10', const []).reason, StockForecastReason.unscheduled);
    expect(
      forecast('10', [
        plan(DailyCount(1, planned('1', 'ml')), start: CivilDate(2028, 1, 1)),
      ]).reason,
      StockForecastReason.noPlannedUse,
    );
  });

  test('an indefinite pause is explicit and a dated pause resumes', () {
    final paused = plan(
      DailyCount(1, planned('1', 'ml')),
      pauses: [PlanPause(start: DateTime.utc(2026, 10, 20))],
    );
    expect(forecast('10', [paused]).reason, StockForecastReason.paused);
    final resumed = plan(
      DailyCount(1, planned('1', 'ml')),
      pauses: [
        PlanPause(
          start: DateTime.utc(2026, 10, 20),
          resume: DateTime.utc(2026, 10, 25),
        ),
      ],
    );
    final result = forecast('3', [resumed]);
    expect(result.date, CivilDate(2026, 10, 27));
  });

  test('interval and unsupported schedules report their own reasons', () {
    expect(
      forecast('10', [
        plan(
          ElapsedInterval(
            segmentId: 'segment',
            duration: ExactElapsed.parseHours('8'),
            mode: IntervalMode.fixedPlanned,
            amount: planned('1', 'ml'),
            plannedAnchor: DateTime.utc(2026, 10, 20),
          ),
        ),
      ]).reason,
      StockForecastReason.intervalSchedule,
    );
  });

  test('unresolved zone and clock are explicit', () {
    expect(
      forecastStockRunOut(
        balance: StockBalance(amount('10')),
        unit: 'ml',
        strength: strength(),
        plans: [
          plan(
            DailyCount(1, planned('1', 'ml')),
            zoneBasis: const FollowingLocal(),
          ),
        ],
        now: now,
        observedZone: null,
      ).reason,
      StockForecastReason.unresolvedZone,
    );
    final missing = forecast('10', [
      plan(
        DailySlots([
          DailySlot(
            id: 'slot',
            time: WallTime(1, 30),
            amount: planned('1', 'ml'),
            reminderEnabled: false,
          ),
        ]),
        zoneBasis: FixedHome('Europe/London'),
      ),
    ], zone: 'Europe/London');
    // The forecast starts on 23 October; the ambiguous autumn clock change is
    // inside the bounded window and must not become a guessed dose.
    expect(missing.reason, StockForecastReason.unresolvedClock);
  });

  test('mixed as-needed and scheduled phases are conservatively unbounded', () {
    final mixed = PhasePlan(
      phases: [
        DailyPlanVersion(
          personId: meId,
          planId: 'mixed',
          itemId: 'item',
          versionId: 'scheduled',
          start: CivilDate(2026, 1, 1),
          endExclusive: CivilDate(2027, 1, 1),
          timing: DailyCount(1, planned('1', 'ml')),
          zoneBasis: FixedHome('UTC'),
        ),
        DailyPlanVersion(
          personId: meId,
          planId: 'mixed',
          itemId: 'item',
          versionId: 'prn',
          start: CivilDate(2027, 1, 1),
          timing: const AsNeeded(),
          zoneBasis: FixedHome('UTC'),
        ),
      ],
    );
    expect(forecast('100', [mixed]).reason, StockForecastReason.asNeeded);
  });

  test('saved phase changes are followed instead of a daily average', () {
    final phased = PhasePlan(
      phases: [
        DailyPlanVersion(
          personId: meId,
          planId: 'phased',
          itemId: 'item',
          versionId: 'high',
          start: CivilDate(2026, 1, 1),
          endExclusive: CivilDate(2026, 10, 25),
          timing: DailyCount(1, planned('2', 'ml')),
          zoneBasis: FixedHome('UTC'),
        ),
        DailyPlanVersion(
          personId: meId,
          planId: 'phased',
          itemId: 'item',
          versionId: 'low',
          start: CivilDate(2026, 10, 25),
          timing: DailyCount(1, planned('1', 'ml')),
          zoneBasis: FixedHome('UTC'),
        ),
      ],
    );
    final result = forecast('10', [phased]);
    expect(result.date, CivilDate(2026, 10, 30));
  });

  test('a finite plan end is a factual boundary, not a run-out guess', () {
    final end = PlanEnd.onDate(
      lastDate: CivilDate(2026, 10, 25),
      zoneId: 'UTC',
      clock: IanaClock(),
    );
    final result = forecast('10', [
      plan(DailyCount(1, planned('1', 'ml')), end: end),
    ]);
    expect(result.reason, StockForecastReason.planEndsFirst);
    expect(result.throughDate, CivilDate(2026, 10, 25));
  });

  test('the bounded window is disclosed instead of inventing a date', () {
    expect(
      forecast('1000', [plan(DailyCount(1, planned('1', 'ml')))]).reason,
      StockForecastReason.completeAfterHorizon,
    );
    final farEnd = PlanEnd.onDate(
      lastDate: CivilDate(2029, 1, 1),
      zoneId: 'UTC',
      clock: IanaClock(),
    );
    expect(
      forecast('1000', [
        plan(DailyCount(1, planned('1', 'ml')), end: farEnd),
      ]).reason,
      StockForecastReason.completeAfterHorizon,
    );
  });

  test('capacity ratio is bounded exactly before display conversion', () {
    expect(
      stockCapacityFraction(amount('3'), amount('10')),
      closeTo(0.3, 1e-6),
    );
    expect(
      stockCapacityFraction(ExactAmount(BigInt.from(-1)), amount('10')),
      0,
    );
    expect(stockCapacityFraction(amount('11'), amount('10')), 1);
    final third = ExactAmount(BigInt.one, BigInt.from(3));
    expect(stockCapacityFraction(third, amount('1')), closeTo(1 / 3, 1e-6));
  });

  test('multiple saved plans add their planned use in different units', () {
    final result = forecast('10', [
      plan(DailyCount(1, planned('1', 'ml'))),
      plan(DailyCount(1, planned('20', 'mg'))),
    ]);
    // 3 ml per day from a 10 ml balance.
    expect(result.date, CivilDate(2026, 10, 26));
  });
}
