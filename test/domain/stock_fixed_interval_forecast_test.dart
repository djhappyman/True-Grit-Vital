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
  LabelledStrength strength({String? mgPerMl = '10'}) => LabelledStrength(
    ingredientId: 'ingredient',
    label: mgPerMl == null ? 'Unknown' : '$mgPerMl mg/ml',
    mgPerMl: mgPerMl == null ? null : amount(mgPerMl),
  );
  PlannedAmount planned(String text, String unit) => PlannedAmount(
    quantity: ExactQuantity.parse(text),
    enteredText: text,
    unit: unit,
  );

  DailyPlanVersion intervalPhase({
    required String versionId,
    required String intervalHours,
    required PlannedAmount amount,
    required DateTime anchor,
    CivilDate? start,
    CivilDate? endExclusive,
    String zone = 'UTC',
    Iterable<PlanPause> pauses = const [],
    IntervalMode mode = IntervalMode.fixedPlanned,
  }) => DailyPlanVersion(
    personId: meId,
    planId: 'plan',
    itemId: 'item',
    versionId: versionId,
    start: start ?? CivilDate(2020, 1, 1),
    endExclusive: endExclusive,
    timing: ElapsedInterval(
      segmentId: 'segment-$versionId',
      duration: ExactElapsed.parseHours(intervalHours),
      mode: mode,
      amount: amount,
      plannedAnchor: mode == IntervalMode.fixedPlanned ? anchor : null,
    ),
    zoneBasis: FixedHome(zone),
    pauses: pauses,
  );

  PhasePlan intervalPlan(Iterable<DailyPlanVersion> phases, {PlanEnd? end}) =>
      PhasePlan(phases: phases, end: end);

  StockRunOutForecast forecast(
    String balance,
    Iterable<PhasePlan> plans, {
    String unit = 'ml',
    LabelledStrength? labelled,
    String? zone = 'UTC',
    DateTime? at,
  }) => forecastStockRunOut(
    balance: StockBalance(amount(balance)),
    unit: unit,
    strength: labelled ?? strength(),
    plans: plans,
    now: at ?? now,
    observedZone: zone,
  );

  group('fixed planned intervals', () {
    test('six-hour instants follow the autumn clock change exactly', () {
      final result = forecast('11', [
        intervalPlan([
          intervalPhase(
            versionId: 'v1',
            intervalHours: '6',
            amount: planned('1', 'ml'),
            anchor: DateTime.utc(2026, 10, 20, 23, 10),
            zone: 'Europe/London',
          ),
        ]),
      ], zone: 'Europe/London');

      // 23 and 24 October each contain three local occurrences. The 25-hour
      // clock-change day contains five, so the exact balance ends on 25 Oct.
      expect(result.isAvailable, true);
      expect(result.date, CivilDate(2026, 10, 25));
      expect(result.days, 3);
      expect(result.plannedThrough, CivilDate(2026, 10, 25));
    });

    test('thirty-six-hour instants cross midnight without a daily average', () {
      final result = forecast('3', [
        intervalPlan([
          intervalPhase(
            versionId: 'v1',
            intervalHours: '36',
            amount: planned('1', 'ml'),
            anchor: DateTime.utc(2026, 10, 20, 0, 30),
          ),
        ]),
      ]);

      // The forecast starts on 23 October. Occurrences fall at 00:30 on the
      // 23rd, 12:30 on the 24th and 00:30 on the 26th.
      expect(result.date, CivilDate(2026, 10, 26));
      expect(result.days, 4);
    });

    test('tomorrow starts in the plan zone, not the UTC date', () {
      final result = forecast(
        '1',
        [
          intervalPlan([
            intervalPhase(
              versionId: 'v1',
              intervalHours: '24',
              amount: planned('1', 'ml'),
              anchor: DateTime.utc(2026, 10, 20),
              zone: 'Europe/London',
            ),
          ]),
        ],
        zone: 'Europe/London',
        // 23:30 UTC on 22 October is already 23 October in London.
        at: DateTime.utc(2026, 10, 22, 23, 30),
      );

      expect(result.date, CivilDate(2026, 10, 24));
      expect(result.days, 1);
    });

    test('phase changes keep each interval and amount', () {
      final result = forecast('10', [
        intervalPlan([
          intervalPhase(
            versionId: 'v1',
            intervalHours: '12',
            amount: planned('1', 'ml'),
            anchor: DateTime.utc(2026, 10, 20),
            endExclusive: CivilDate(2026, 10, 25),
          ),
          intervalPhase(
            versionId: 'v2',
            intervalHours: '24',
            amount: planned('2', 'ml'),
            anchor: DateTime.utc(2026, 10, 25, 8),
            start: CivilDate(2026, 10, 25),
          ),
        ]),
      ]);

      expect(result.date, CivilDate(2026, 10, 27));
      expect(result.days, 5);
    });

    test('a dated pause suppresses interval instants and then resumes', () {
      final result = forecast('3', [
        intervalPlan([
          intervalPhase(
            versionId: 'v1',
            intervalHours: '12',
            amount: planned('1', 'ml'),
            anchor: DateTime.utc(2026, 10, 20),
            pauses: [
              PlanPause(
                start: DateTime.utc(2026, 10, 24),
                resume: DateTime.utc(2026, 10, 25),
              ),
            ],
          ),
        ]),
      ]);

      expect(result.date, CivilDate(2026, 10, 25));
      expect(result.days, 3);
    });

    test('an open pause stays an explicit reason', () {
      final result = forecast('10', [
        intervalPlan([
          intervalPhase(
            versionId: 'v1',
            intervalHours: '12',
            amount: planned('1', 'ml'),
            anchor: DateTime.utc(2026, 10, 20),
            pauses: [PlanPause(start: DateTime.utc(2026, 10, 21))],
          ),
        ]),
      ]);

      expect(result.reason, StockForecastReason.paused);
    });

    test('finite plan end is a factual boundary', () {
      final end = PlanEnd.onDate(
        lastDate: CivilDate(2026, 10, 25),
        zoneId: 'UTC',
        clock: IanaClock(),
      );
      final result = forecast('1000', [
        intervalPlan([
          intervalPhase(
            versionId: 'v1',
            intervalHours: '12',
            amount: planned('1', 'ml'),
            anchor: DateTime.utc(2026, 10, 20),
          ),
        ], end: end),
      ]);

      expect(result.reason, StockForecastReason.planEndsFirst);
      expect(result.throughDate, CivilDate(2026, 10, 25));
    });

    test('labelled strength converts each exact interval amount', () {
      final result = forecast(
        '1',
        [
          intervalPlan([
            intervalPhase(
              versionId: 'v1',
              intervalHours: '12',
              amount: planned('1', 'mg'),
              anchor: DateTime.utc(2026, 10, 20),
            ),
          ]),
        ],
        unit: 'ml',
        labelled: strength(mgPerMl: '3'),
      );

      // 1 mg is exactly one third of a millilitre at 3 mg/ml. Two doses on
      // 23 October and the first dose on 24 October exhaust the balance.
      expect(result.date, CivilDate(2026, 10, 24));
      expect(result.days, 2);
    });

    test('incompatible units stay explicit', () {
      final result = forecast('10', [
        intervalPlan([
          intervalPhase(
            versionId: 'v1',
            intervalHours: '12',
            amount: planned('1', 'count'),
            anchor: DateTime.utc(2026, 10, 20),
          ),
        ]),
      ]);

      expect(result.reason, StockForecastReason.incompatibleUnits);
    });

    test('an unresolved zone stays explicit', () {
      final result = forecast('10', [
        PhasePlan(
          phases: [
            DailyPlanVersion(
              personId: meId,
              planId: 'plan',
              itemId: 'item',
              versionId: 'v1',
              start: CivilDate(2020, 1, 1),
              timing: ElapsedInterval(
                segmentId: 'segment',
                duration: ExactElapsed.parseHours('12'),
                mode: IntervalMode.fixedPlanned,
                amount: planned('1', 'ml'),
                plannedAnchor: DateTime.utc(2026, 10, 20),
              ),
              zoneBasis: const FollowingLocal(),
            ),
          ],
        ),
      ], zone: null);

      expect(result.reason, StockForecastReason.unresolvedZone);
    });
  });

  group('interval boundaries and unavailable reasons', () {
    test('the one-year window is disclosed instead of inventing a date', () {
      final result = forecast('1000', [
        intervalPlan([
          intervalPhase(
            versionId: 'v1',
            intervalHours: '36',
            amount: planned('1', 'ml'),
            anchor: DateTime.utc(2026, 10, 20),
          ),
        ]),
      ]);

      expect(result.reason, StockForecastReason.completeAfterHorizon);
    });

    test('excessive occurrence work stays unavailable without truncation', () {
      final result = forecastStockRunOut(
        balance: StockBalance(amount('9000000000')),
        unit: 'ml',
        strength: strength(),
        plans: [
          intervalPlan([
            intervalPhase(
              versionId: 'v1',
              intervalHours: '0.1',
              amount: planned('1', 'ml'),
              anchor: DateTime.utc(2026, 10, 1),
            ),
          ]),
        ],
        now: now,
        observedZone: 'UTC',
      );

      expect(result.isAvailable, false);
      expect(result.reason, StockForecastReason.unsupportedSchedule);
    });

    test('sub-second interval expansion stops at the work limit', () {
      final result = forecast('9000000000', [
        intervalPlan([
          intervalPhase(
            versionId: 'v1',
            intervalHours: '0.000001',
            amount: planned('1', 'ml'),
            anchor: DateTime.utc(2026, 10, 20),
          ),
        ]),
      ]);
      expect(result.reason, StockForecastReason.unsupportedSchedule);
      expect(result.isAvailable, false);
    });

    test('actual-anchored intervals never invent a future dose', () {
      final result = forecast('100', [
        intervalPlan([
          intervalPhase(
            versionId: 'v1',
            intervalHours: '8',
            amount: planned('1', 'ml'),
            anchor: DateTime.utc(2026, 10, 20),
            mode: IntervalMode.qualifyingActual,
          ),
        ]),
      ]);

      expect(result.isAvailable, false);
      expect(result.reason, StockForecastReason.intervalSchedule);
    });

    test('mixed as-needed phases stay conservatively unbounded', () {
      final mixed = PhasePlan(
        phases: [
          intervalPhase(
            versionId: 'scheduled',
            intervalHours: '12',
            amount: planned('1', 'ml'),
            anchor: DateTime.utc(2026, 10, 20),
            start: CivilDate(2026, 1, 1),
            endExclusive: CivilDate(2026, 11, 1),
          ),
          DailyPlanVersion(
            personId: meId,
            planId: 'plan',
            itemId: 'item',
            versionId: 'prn',
            start: CivilDate(2026, 11, 1),
            timing: const AsNeeded(),
            zoneBasis: FixedHome('UTC'),
          ),
        ],
      );

      expect(forecast('100', [mixed]).reason, StockForecastReason.asNeeded);
    });

    test('a fixed interval adds to another scheduled plan exactly', () {
      final result = forecast('4', [
        intervalPlan([
          intervalPhase(
            versionId: 'v1',
            intervalHours: '12',
            amount: planned('1', 'ml'),
            anchor: DateTime.utc(2026, 10, 20),
          ),
        ]),
        PhasePlan(
          phases: [
            DailyPlanVersion(
              personId: meId,
              planId: 'other',
              itemId: 'item',
              versionId: 'daily',
              start: CivilDate(2020, 1, 1),
              timing: DailyCount(1, planned('1', 'ml')),
              zoneBasis: FixedHome('UTC'),
            ),
          ],
        ),
      ]);

      // 3 ml on 23 October leaves 1 ml, and 24 October exhausts it.
      expect(result.date, CivilDate(2026, 10, 24));
      expect(result.days, 2);
    });
  });
}
