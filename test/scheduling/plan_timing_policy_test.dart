import 'package:flutter_test/flutter_test.dart';
import 'package:true_grit_vital/data/daily_codec.dart';
import 'package:true_grit_vital/domain/records.dart';
import 'package:true_grit_vital/domain/scheduling/daily_plan.dart';
import 'package:true_grit_vital/domain/scheduling/daily_resolver.dart';

DailyPlanVersion plan({PlanTimingPolicy? policy}) => DailyPlanVersion(
  personId: 'me',
  planId: 'plan',
  itemId: 'item',
  versionId: 'v1',
  start: CivilDate(2026, 10, 23),
  zoneBasis: FixedHome('UTC'),
  timingPolicy: policy,
  timing: DailySlots([
    DailySlot(
      id: 'am',
      time: WallTime(8, 0),
      amount: PlannedAmount(quantity: ExactQuantity.parse('1'), unit: 'count'),
      reminderEnabled: true,
    ),
  ]),
);
void main() {
  test('labels and follow-ups are independently off by default', () {
    final value = plan();
    expect(value.timingPolicy, isNull);
    expect(decodeDailyPlan(encodeDailyPlan(value)).timingPolicy, isNull);
    final now = DateTime.utc(2026, 10, 23, 8);
    expect(doseTimingLabel(policy: null, planned: now, actual: now), isNull);
    expect(planFollowUpInstant(null, now), isNull);
  });
  test('exact inclusive window uses actual elapsed time, including DST', () {
    final policy = PlanTimingPolicy(allowanceMinutes: 30);
    final expected = DateTime.parse('2026-10-25T01:30:00Z');
    DoseTimingLabel? label(DateTime actual) =>
        doseTimingLabel(policy: policy, planned: expected, actual: actual);
    expect(
      label(expected.subtract(const Duration(minutes: 30))),
      DoseTimingLabel.withinWindow,
    );
    expect(
      label(expected.add(const Duration(minutes: 30))),
      DoseTimingLabel.withinWindow,
    );
    expect(
      label(expected.subtract(const Duration(minutes: 30, microseconds: 1))),
      DoseTimingLabel.earlier,
    );
    expect(
      label(expected.add(const Duration(minutes: 30, microseconds: 1))),
      DoseTimingLabel.later,
    );
    expect(
      label(DateTime.parse('2026-10-25T02:30:00+01:00')),
      DoseTimingLabel.withinWindow,
    );
  });
  test('zero allowance means exactly the planned instant', () {
    final expected = DateTime.utc(2026, 10, 23);
    final policy = PlanTimingPolicy(allowanceMinutes: 0);
    expect(
      doseTimingLabel(policy: policy, planned: expected, actual: expected),
      DoseTimingLabel.withinWindow,
    );
    expect(
      doseTimingLabel(
        policy: policy,
        planned: expected,
        actual: expected.add(const Duration(microseconds: 1)),
      ),
      DoseTimingLabel.later,
    );
  });
  test('unknown, date-only, uncertain and voided times are unclassified', () {
    final policy = PlanTimingPolicy(allowanceMinutes: 10);
    final time = DateTime.utc(2026, 10, 23);
    expect(
      doseTimingLabel(policy: policy, planned: null, actual: time),
      isNull,
    );
    expect(
      doseTimingLabel(
        policy: policy,
        planned: time,
        actual: time,
        dateOnly: true,
      ),
      isNull,
    );
    expect(
      doseTimingLabel(
        policy: policy,
        planned: time,
        actual: time,
        timeNeedsReview: true,
      ),
      isNull,
    );
    expect(
      doseTimingLabel(
        policy: policy,
        planned: time,
        actual: time,
        voided: true,
      ),
      isNull,
    );
    expect(
      doseTimingLabel(
        policy: PlanTimingPolicy(followUpMinutes: 5),
        planned: time,
        actual: time,
      ),
      isNull,
    );
  });
  test('policy survives version and captured occurrence JSON without changing old data', () {
    final policy = PlanTimingPolicy(allowanceMinutes: 20, followUpMinutes: 45);
    final value = decodeDailyPlan(encodeDailyPlan(plan(policy: policy)));
    expect(value.timingPolicy!.toJson(), policy.toJson());
    final occurrence = DailyResolver()
        .resolveDate(value, CivilDate(2026, 10, 23), observedZone: 'UTC')
        .single;
    final snapshot = encodeDailyExpectation(occurrence);
    expect(
      decodeDailyExpectation(snapshot).timingPolicy!.toJson(),
      policy.toJson(),
    );
    final old = {...snapshot}..remove('timingPolicy');
    expect(decodeDailyExpectation(old).timingPolicy, isNull);
    expect(
      occurrence.withEligibilityConflict('paused').timingPolicy!.toJson(),
      policy.toJson(),
    );
  });
  test(
    'follow-up crosses civil midnight exactly and refuses final-year overflow',
    () {
      final policy = PlanTimingPolicy(followUpMinutes: 30);
      expect(
        planFollowUpInstant(policy, DateTime.utc(2026, 10, 23, 23, 45)),
        DateTime.utc(2026, 10, 24, 0, 15),
      );
      expect(
        planFollowUpInstant(policy, DateTime.utc(9999, 12, 31, 23, 59)),
        isNull,
      );
      expect(planFollowUpInstant(policy, null), isNull);
    },
  );
  test('malformed policies fail rather than enabling a default', () {
    expect(() => PlanTimingPolicy(), throwsFormatException);
    expect(() => PlanTimingPolicy(followUpMinutes: 0), throwsFormatException);
    expect(() => PlanTimingPolicy(allowanceMinutes: -1), throwsFormatException);
    expect(
      () => PlanTimingPolicy(followUpMinutes: 10081),
      throwsFormatException,
    );
    expect(
      () => PlanTimingPolicy.fromJson({'allowance': 5, 'future': true}),
      throwsFormatException,
    );
  });
}
