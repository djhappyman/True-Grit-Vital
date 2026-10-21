import 'package:flutter_test/flutter_test.dart';
import 'package:true_grit_vital/data/record_store.dart';
import 'package:true_grit_vital/features/plans/dashboard_week.dart';

DailyExpectation expectation({
  required String plan,
  required CivilDate date,
  int planned = 1,
}) => DailyExpectation(
  identity: DailyIdentity(personId: meId, planId: plan, originalDate: date),
  itemId: 'item-$plan',
  versionId: 'version-$plan',
  zoneId: 'Europe/London',
  amount: PlannedAmount(
    quantity: ExactQuantity.parse('1'),
    enteredText: '1',
    unit: 'mg',
  ),
  resolution: DailyResolution.untimed,
  calculatorVersion: 'test',
  timezoneDataVersion: 'test',
  plannedCount: planned,
);

DailyRow row({
  required String plan,
  required CivilDate date,
  int planned = 1,
  int taken = 0,
  int skipped = 0,
  bool actionsComplete = true,
}) => DailyRow(
  generation: 'generation',
  personRevision: 1,
  planRevision: 1,
  expectation: expectation(plan: plan, date: date, planned: planned),
  personName: 'Main Adult',
  itemName: 'Substance $plan',
  revision: 1,
  actions: const [],
  takenCount: taken,
  skippedCount: skipped,
  actionsComplete: actionsComplete,
);

SavedDailyPlan saved({
  required String plan,
  DailyTiming timing = const AsNeeded(),
}) => SavedDailyPlan(
  plan: DailyPlanVersion(
    personId: meId,
    planId: plan,
    itemId: 'item-$plan',
    versionId: 'version-$plan',
    start: CivilDate(2026, 10, 19),
    timing: timing,
    zoneBasis: FixedHome('Europe/London'),
  ),
  revision: 1,
);

void main() {
  group('dashboard week boundaries', () {
    test('weeks start on Monday and cross month and year borders', () {
      expect(
        dashboardWeekStart(CivilDate(2026, 10, 21)),
        CivilDate(2026, 10, 19),
      );
      expect(
        dashboardWeekStart(CivilDate(2026, 10, 19)),
        CivilDate(2026, 10, 19),
      );
      expect(
        dashboardWeekStart(CivilDate(2026, 10, 25)),
        CivilDate(2026, 10, 19),
      );
      expect(
        dashboardWeekStart(CivilDate(2027, 1, 1)),
        CivilDate(2026, 12, 28),
      );
    });

    test('a daylight-saving week still contains seven named dates', () {
      // London changes clocks on 25 October 2026. The civil week is unchanged.
      final start = dashboardWeekStart(CivilDate(2026, 10, 25));
      expect(start, CivilDate(2026, 10, 19));
      expect(dashboardWeekDays(start), [
        for (var day = 19; day <= 25; day++) CivilDate(2026, 10, day),
      ]);
      final long = DisplayTime().dayBounds(
        CivilDate(2026, 10, 25),
        'Europe/London',
      );
      final short = DisplayTime().dayBounds(
        CivilDate(2026, 3, 29),
        'Europe/London',
      );
      expect(long.duration, const Duration(hours: 25));
      expect(short.duration, const Duration(hours: 23));
      expect(long.zoneFallback, isFalse);
      expect(short.zoneFallback, isFalse);
    });

    test('an unknown zone stays a labelled UTC fallback', () {
      final bounds = DisplayTime().dayBounds(
        CivilDate(2026, 10, 21),
        'Invalid/Zone',
      );
      expect(bounds.zoneFallback, isTrue);
      expect(bounds.zoneId, 'UTC');
      expect(bounds.duration, const Duration(hours: 24));
    });
  });

  group('weekly summary', () {
    final date = CivilDate(2026, 10, 21);

    test('separates planned, recorded and skipped slots', () {
      final summary = dashboardWeekSummary(
        DailyRows(
          rows: [
            row(plan: 'a', date: date, planned: 3, taken: 2, skipped: 1),
            row(plan: 'b', date: date, planned: 2, taken: 1),
          ],
          complete: true,
        ),
      );
      expect(summary.planned, 5);
      expect(summary.recorded, 3);
      expect(summary.skipped, 1);
      expect(summary.unresolved, 1);
      expect(summary.complete, isTrue);
      expect(summary.hasPlans, isTrue);
    });

    test('a zero-plan week has no complete ratio claim', () {
      final summary = dashboardWeekSummary(
        DailyRows(rows: const [], complete: true),
      );
      expect(summary.planned, 0);
      expect(summary.hasPlans, isFalse);
      expect(summary.complete, isTrue);
    });

    test(
      'bounded rows, partial action history and zone issues are incomplete',
      () {
        final date = CivilDate(2026, 10, 21);
        expect(
          dashboardWeekSummary(
            DailyRows(
              rows: [row(plan: 'a', date: date)],
              complete: false,
            ),
          ).complete,
          isFalse,
        );
        expect(
          dashboardWeekSummary(
            DailyRows(
              rows: [row(plan: 'a', date: date, actionsComplete: false)],
              complete: true,
            ),
          ).complete,
          isFalse,
        );
        expect(
          dashboardWeekSummary(
            DailyRows(
              rows: [row(plan: 'a', date: date)],
              complete: true,
              issue: DailyCalculationIssue.observedZoneUnavailable,
            ),
          ).complete,
          isFalse,
        );
      },
    );
  });

  group('quick record favourites', () {
    test('saved order resolves against current as-needed plans only', () {
      final selection = dashboardFavouriteSelection(
        ['three', 'missing', 'one', 'one'],
        [
          saved(plan: 'one'),
          saved(plan: 'two'),
          saved(plan: 'three'),
          // A plan that changed away from as-needed is not a quick action.
          saved(plan: 'changed', timing: DailyCount(1, _amount)),
        ],
      );
      expect(selection.plans.map((p) => p.plan.planId), ['three', 'one']);
      expect(selection.unavailable, 1);
    });

    test(
      'the collection reports every as-needed plan and its completeness',
      () {
        const collection = DashboardPlanCollection(plans: [], complete: false);
        expect(collection.asNeeded, isEmpty);
        final withPlans = DashboardPlanCollection(
          plans: [
            saved(plan: 'one'),
            saved(plan: 'scheduled', timing: DailyCount(1, _amount)),
          ],
          complete: true,
        );
        expect(withPlans.asNeeded.map((p) => p.plan.planId), ['one']);
      },
    );
  });
}

final _amount = PlannedAmount(
  quantity: ExactQuantity.parse('1'),
  enteredText: '1',
  unit: 'mg',
);
