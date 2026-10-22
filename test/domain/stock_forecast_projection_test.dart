import 'package:flutter_test/flutter_test.dart';
import 'package:true_grit_vital/domain/records.dart';
import 'package:true_grit_vital/domain/scheduling/daily_plan.dart';
import 'package:true_grit_vital/domain/scheduling/iana_clock.dart';
import 'package:true_grit_vital/domain/scheduling/phase_plan.dart';
import 'package:true_grit_vital/domain/stock/stock_forecast.dart';
import 'package:true_grit_vital/domain/stock/stored_stock.dart';

void main() {
  final now = DateTime.utc(2026, 10, 22, 12);
  ExactAmount exact(String value) =>
      value == '0' ? ExactAmount.zero : ExactAmount.parseEntry(value);
  PhasePlan plan({
    String quantity = '1',
    String unit = 'ml',
    PlanEnd? end,
    DailyZoneBasis? zone,
    DailyTiming? timing,
    CalendarPattern calendar = const EveryDay(),
  }) => PhasePlan(
    end: end,
    phases: [
      DailyPlanVersion(
        personId: meId,
        itemId: 'item',
        planId: 'plan',
        versionId: 'version',
        start: CivilDate(2020, 1, 1),
        zoneBasis: zone ?? FixedHome('UTC'),
        calendar: calendar,
        timing:
            timing ??
            DailyCount(
              1,
              PlannedAmount(
                quantity: ExactQuantity.parse(quantity),
                enteredText: quantity,
                unit: unit,
              ),
            ),
      ),
    ],
  );
  StockRunOutForecast forecast(
    List<PhasePlan> plans, {
    String balance = '10',
    int horizon = 366,
    String? observed = 'UTC',
  }) => forecastStockRunOut(
    balance: StockBalance(exact(balance)),
    unit: 'ml',
    strength: LabelledStrength(
      ingredientId: 'item',
      label: '3 mg/ml',
      mgPerMl: exact('3'),
    ),
    plans: plans,
    now: now,
    observedZone: observed,
    horizonDays: horizon,
  );

  test('run-out details include the whole final day and exact shortfall', () {
    final result = forecast([plan(quantity: '3')]);
    final projection = result.projection!;
    expect(projection.from, CivilDate(2026, 10, 23));
    expect(projection.through, result.date);
    expect(projection.through, CivilDate(2026, 10, 26));
    expect(projection.zoneId, 'UTC');
    expect(projection.opening, exact('10'));
    expect(projection.planned, exact('12'));
    expect(projection.remaining, ExactAmount(BigInt.from(-2)));
  });

  test('projection preserves rational unit conversion and exact depletion', () {
    final result = forecast([plan(unit: 'mg')], balance: '1');
    expect(result.projection!.planned, exact('1'));
    expect(result.projection!.remaining, ExactAmount.zero);
    final limited = forecast([plan(unit: 'mg')], horizon: 2);
    expect(
      limited.projection!.planned,
      ExactAmount(BigInt.two, BigInt.from(3)),
    );
    expect(
      limited.projection!.remaining,
      ExactAmount(BigInt.from(28), BigInt.from(3)),
    );
    expect(limited.reason, StockForecastReason.completeAfterHorizon);
  });

  test('a finite plan has exact totals through its inclusive last date', () {
    final result = forecast([
      plan(
        end: PlanEnd.onDate(
          lastDate: CivilDate(2026, 10, 25),
          zoneId: 'UTC',
          clock: IanaClock(),
        ),
      ),
    ]);
    expect(result.reason, StockForecastReason.planEndsFirst);
    expect(result.projection!.through, CivilDate(2026, 10, 25));
    expect(result.projection!.planned, exact('3'));
    expect(result.projection!.remaining, exact('7'));
  });

  test('projection names the resolved plan zone rather than device zone', () {
    final result = forecast([
      plan(zone: FixedHome('Pacific/Kiritimati')),
    ], balance: '1');
    expect(result.projection!.zoneId, 'Pacific/Kiritimati');
    expect(result.projection!.from, CivilDate(2026, 10, 24));
  });

  test(
    'fixed interval totals include every exact occurrence on the last day',
    () {
      final result = forecast([
        plan(
          timing: ElapsedInterval(
            segmentId: 'fixed',
            duration: ExactElapsed.parseHours('8'),
            mode: IntervalMode.fixedPlanned,
            amount: PlannedAmount(
              quantity: ExactQuantity.parse('1'),
              enteredText: '1',
              unit: 'ml',
            ),
            plannedAnchor: DateTime.utc(2026, 10, 22),
          ),
        ),
      ], balance: '4');
      expect(result.projection!.through, CivilDate(2026, 10, 24));
      expect(result.projection!.planned, exact('6'));
      expect(result.projection!.remaining, ExactAmount(BigInt.from(-2)));
    },
  );

  test(
    'a resolved empty horizon names zero planned use without changing stock',
    () {
      final result = forecast([
        plan(calendar: SelectedWeekdays([DateTime.monday])),
      ], horizon: 2);
      expect(result.reason, StockForecastReason.noPlannedUse);
      expect(result.projection!.planned, ExactAmount.zero);
      expect(result.projection!.remaining, exact('10'));
      expect(result.projection!.through, CivilDate(2026, 10, 24));
    },
  );

  test('unsupported or incomplete calculations disclose no partial totals', () {
    expect(forecast([plan(), plan(unit: 'count')]).projection, isNull);
    expect(forecast([plan(timing: const AsNeeded())]).projection, isNull);
    expect(
      forecast([plan(zone: const FollowingLocal())], observed: null).projection,
      isNull,
    );
    expect(forecast([plan()], balance: '0').projection, isNull);
  });
}
