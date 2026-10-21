import 'package:flutter_test/flutter_test.dart';
import 'package:true_grit_vital/data/record_store.dart';
import 'package:true_grit_vital/features/plans/today_model.dart';

DailySlot slot(String id, WallTime time, String amount) => DailySlot(
  id: id,
  time: time,
  amount: PlannedAmount(
    quantity: ExactQuantity.parse(amount),
    enteredText: amount,
    unit: 'mg',
  ),
  reminderEnabled: false,
);

DailyExpectation timedRow({
  required String plan,
  required String slotId,
  required CivilDate date,
  required DateTime instant,
  required WallTime wall,
  String zone = 'UTC',
  String amount = '1',
}) => DailyExpectation(
  identity: DailyIdentity(
    personId: 'me',
    planId: plan,
    originalDate: date,
    slotId: slotId,
  ),
  itemId: 'i-$plan-$slotId',
  versionId: 'v-$plan-$slotId',
  zoneId: zone,
  amount: PlannedAmount(
    quantity: ExactQuantity.parse(amount),
    enteredText: amount,
    unit: 'mg',
  ),
  resolution: DailyResolution.exact,
  calculatorVersion: 'test',
  timezoneDataVersion: 'test',
  originalTime: wall,
  effectiveTime: wall,
  instant: instant,
  clockCandidates: [instant],
);

DailyExpectation untimedRow({
  required String plan,
  required CivilDate date,
  required int planned,
}) => DailyExpectation(
  identity: DailyIdentity(planId: plan, personId: 'me', originalDate: date),
  itemId: 'i-$plan',
  versionId: 'v-$plan',
  zoneId: 'UTC',
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

DailyRow feedRow(
  DailyExpectation expectation, {
  int taken = 0,
  int skipped = 0,
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
);

void main() {
  final date = CivilDate(2026, 10, 21);

  test('time groups stay separate per zone and fold equal wall times', () {
    final instant815 = DateTime.utc(2026, 10, 21, 8, 15);
    final rows = [
      feedRow(
        timedRow(
          plan: 'a',
          slotId: 'morning',
          date: date,
          instant: instant815,
          wall: WallTime(8, 15),
        ),
      ),
      feedRow(
        timedRow(
          plan: 'b',
          slotId: 'morning',
          date: date,
          instant: instant815,
          wall: WallTime(8, 15),
          amount: '2',
        ),
      ),
      // London is one hour ahead on this date (BST): 06:15 UTC is 07:15 wall.
      feedRow(
        timedRow(
          plan: 'c',
          slotId: 'morning',
          date: date,
          instant: DateTime.utc(2026, 10, 21, 6, 15),
          wall: WallTime(7, 15),
          zone: 'Europe/London',
        ),
      ),
    ];
    final groups = groupTodayRows(
      rows,
      timeLabel: (row, start) => TodayTimeLabel(
        key:
            '${row.expectation.zoneId}|${DisplayTime().instant(start, row.expectation.zoneId).time24}',
        title: DisplayTime().instant(start, row.expectation.zoneId).time24,
      ),
      untimedTitle: 'Due',
    );
    expect(groups.map((g) => g.title), ['07:15', '08:15']);
    expect(groups.first.rows, hasLength(1));
    expect(groups.last.rows, hasLength(2));
    expect(groups.any((g) => g.untimed), isFalse);
  });

  test('untimed rows form one last group titled by the caller', () {
    final rows = [
      feedRow(
        timedRow(
          plan: 'a',
          slotId: 's',
          date: date,
          instant: DateTime.utc(2026, 10, 21, 9),
          wall: WallTime(9, 0),
        ),
      ),
      feedRow(untimedRow(plan: 'b', date: date, planned: 2)),
      feedRow(untimedRow(plan: 'c', date: date, planned: 1)),
    ];
    final groups = groupTodayRows(
      rows,
      timeLabel: (row, start) => TodayTimeLabel(
        key:
            '${row.expectation.zoneId}|${DisplayTime().instant(start, row.expectation.zoneId).time24}',
        title: '0900',
      ),
      untimedTitle: 'Due',
    );
    expect(groups.map((g) => g.untimed), [false, true]);
    expect(groups.last.title, 'Due');
    expect(groups.last.rows.map((r) => r.expectation.identity.planId), [
      'b',
      'c',
    ]);
    expect(groups.first.rows, hasLength(1));
  });

  test('counting keeps recorded, skipped and unresolved separate', () {
    final rows = [
      feedRow(untimedRow(plan: 'a', date: date, planned: 2), taken: 1),
      feedRow(untimedRow(plan: 'b', date: date, planned: 2), skipped: 2),
      feedRow(untimedRow(plan: 'c', date: date, planned: 3)),
    ];
    final count = todayUseCount(rows);
    expect(count.planned, 7);
    expect(count.recorded, 1);
    expect(count.skipped, 2);
    // b:0 + c:3 unresolved; a has one unresolved
    expect(count.unresolved, 4);
    expect(todayUseCount(const []).planned, 0);
    expect(todayUseCount(const []).unresolved, 0);
  });

  test('unresolved cannot go below zero although rows keep real counts', () {
    final count = todayUseCount([
      feedRow(untimedRow(plan: 'x', date: date, planned: 1)),
    ]);
    expect(count.unresolved, 1);
    final resolved = todayUseCount([
      feedRow(untimedRow(plan: 'x', date: date, planned: 1), taken: 1),
    ]);
    expect(resolved.unresolved, 0);
  });

  test(
    'next pending row ignores resolved rows and picks the earliest start',
    () {
      final laterResolved = feedRow(
        timedRow(
          plan: 'p',
          slotId: 'second',
          date: date,
          instant: DateTime.utc(2026, 10, 21, 10),
          wall: WallTime(10, 0),
        ),
        taken: 1,
      );
      final earlier = feedRow(
        timedRow(
          plan: 'q',
          slotId: 'first',
          date: date,
          instant: DateTime.utc(2026, 10, 21, 8),
          wall: WallTime(8, 0),
        ),
      );
      final untimed = feedRow(untimedRow(plan: 'u', date: date, planned: 1));
      final pick = todayNextPendingRow([untimed, laterResolved, earlier]);
      expect(pick, isNotNull);
      expect(pick!.$1.expectation.identity.planId, 'q');
      expect(todayHasPendingUntimed([untimed]), isTrue);
      expect(todayHasPendingUntimed([earlier]), isFalse);
      expect(todayNextPendingRow([untimed]), isNull);
      expect(todayNextPendingRow(const []), isNull);
    },
  );

  DailyPlanNextRow make(String plan, DateTime next) => DailyPlanNextRow(
    plan: DailyPlanVersion(
      personId: 'me',
      planId: plan,
      itemId: 'i',
      versionId: 'v',
      start: CivilDate(2026, 10, 21),
      timing: DailySlots([slot('s', WallTime(next.hour, next.minute), '1')]),
      zoneBasis: FixedHome('UTC'),
    ),
    result: DailyNext(
      next: timedRow(
        plan: plan,
        slotId: 's',
        date: CivilDate(2026, 10, 21),
        instant: next,
        wall: WallTime(next.hour, next.minute),
      ),
      complete: true,
      datesExamined: 1,
    ),
  );

  test('the next future plan start is the earliest after now', () {
    final now = DateTime.utc(2026, 10, 21, 12);
    final rows = [
      make('later', DateTime.utc(2026, 10, 22, 8)),
      make('sooner', DateTime.utc(2026, 10, 21, 18)),
      // Past instants never become the next dose.
      make('past', DateTime.utc(2026, 10, 21, 9)),
    ];
    final pick = todayNextFutureRow(rows, now);
    expect(pick, isNotNull);
    expect(pick!.$1.plan.planId, 'sooner');
    expect(
      todayNextFutureRow(rows.where((r) => r.plan.planId == 'past'), now),
      isNull,
    );
  });

  test('countdown minutes and tick bounds', () {
    final now = DateTime.utc(2026, 10, 21, 12, 0);
    expect(todayCountdownMinutes(now, now), isNull);
    expect(
      todayCountdownMinutes(now, now.add(const Duration(seconds: 59))),
      isNull,
    );
    expect(todayCountdownMinutes(now, now.add(const Duration(seconds: 60))), 1);
    // Ceil the remaining interval: 61 seconds is not understated as 1 minute.
    expect(todayCountdownMinutes(now, now.add(const Duration(seconds: 61))), 2);
    expect(
      todayCountdownMinutes(now, now.add(const Duration(minutes: 35))),
      35,
    );
    expect(
      todayCountdownMinutes(now, now.add(const Duration(hours: 1))),
      isNull,
    );
    expect(
      todayCountdownMinutes(now, now.add(const Duration(hours: 3))),
      isNull,
    );
    final withinMinute = todayCountdownTick(
      now,
      now.add(const Duration(seconds: 30)),
    );
    // A future dose under a minute away still arms exactly one tick, at the
    // expected start itself; it is never shown as due early.
    expect(withinMinute, isNotNull);
    expect(withinMinute!, const Duration(seconds: 30, milliseconds: 1));
    final tick = todayCountdownTick(
      now,
      now.add(const Duration(minutes: 35, seconds: 20)),
    );
    expect(tick, isNotNull);
    expect(tick! > Duration.zero, isTrue);
    expect(tick <= const Duration(minutes: 1), isTrue);
    // Past and far targets arm no timer.
    expect(
      todayCountdownTick(now, now.subtract(const Duration(seconds: 1))),
      isNull,
    );
    expect(todayCountdownTick(now, now.add(const Duration(hours: 2))), isNull);
  });

  test('expectation start prefers the window then the instant', () {
    final instant = DateTime.utc(2026, 10, 21, 8);
    final withWindow = DailyExpectation(
      identity: DailyIdentity(
        personId: 'me',
        planId: 'w',
        originalDate: date,
        slotId: 'w',
      ),
      itemId: 'iw',
      versionId: 'viw',
      zoneId: 'UTC',
      amount: PlannedAmount(quantity: ExactQuantity.parse('1'), unit: 'mg'),
      resolution: DailyResolution.exact,
      calculatorVersion: 'test',
      timezoneDataVersion: 'test',
      instant: instant,
      windowStart: instant.add(const Duration(minutes: -5)),
      windowEnd: instant.add(const Duration(minutes: 5)),
      effectiveTime: WallTime(8, 0),
      originalTime: WallTime(8, 0),
      clockCandidates: [instant],
    );
    expect(
      todayExpectationStart(withWindow),
      instant.add(const Duration(minutes: -5)),
    );
    expect(
      todayRowStart(feedRow(withWindow)),
      instant.add(const Duration(minutes: -5)),
    );
  });
}
