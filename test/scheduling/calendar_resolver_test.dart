import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:true_grit_vital/domain/records.dart';
import 'package:true_grit_vital/domain/scheduling/daily_plan.dart';
import 'package:true_grit_vital/domain/scheduling/daily_resolver.dart';

CivilDate d(String text) => CivilDate.parse(text);
PlannedAmount amount() =>
    PlannedAmount(quantity: ExactQuantity.parse('1.25'), unit: 'tablet');
DailyPlanVersion plan(
  CalendarPattern pattern, {
  DailyTiming? timing,
  String zone = 'UTC',
  CivilDate? end,
}) => DailyPlanVersion(
  personId: 'ada',
  planId: 'plan',
  itemId: 'item',
  versionId: 'v1',
  start: d('1900-01-01'),
  endExclusive: end,
  timing: timing ?? DailyCount(3, amount()),
  zoneBasis: FixedHome(zone),
  calendar: pattern,
);

void main() {
  final resolver = DailyResolver();
  final fixture = jsonDecode(
    File('test/fixtures/scheduling/08-11-expected.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  final cases = (fixture['cases'] as List).cast<Map<String, dynamic>>();
  Map<String, dynamic> oracle(String id) =>
      cases.singleWhere((c) => c['id'] == id);
  for (var number = 1; number <= 9; number++) {
    final id = 'C${number.toString().padLeft(2, '0')}';
    test(
      '$id production selected dates, counts and stable original identity',
      () {
        final c = oracle(id),
            input = oracle(id)['inputs'] as Map<String, dynamic>;
        late CalendarPattern pattern;
        late CivilDate from, end;
        if (number <= 3) {
          from = d(input['start'] as String);
          end = d(input['end'] as String);
          pattern = number == 1
              ? SelectedWeekdays(
                  (input['weekdays'] as List).cast<int>().map((x) => x + 1),
                )
              : EveryNDays(
                  anchor: d(input['anchor'] as String),
                  interval: input['every_days'] as int,
                );
        } else if (number == 4) {
          from = d(input['anchor_week'] as String);
          end = d(input['end'] as String);
          pattern = EveryNWeeks(
            anchorWeekStart: from,
            interval: input['every_weeks'] as int,
            weekdays: (input['weekdays'] as List).cast<int>().map((x) => x + 1),
          );
        } else if (number == 9) {
          from = d('2027-01-01');
          end = d('2027-04-01');
          pattern = EveryNMonths(
            anchorMonth: from,
            interval: 1,
            selector: LastWeekday(1),
          );
        } else {
          from = CivilDate(input['year'] as int, input['month'] as int, 1);
          end = CivilDate.fromDateTime(
            DateTime.utc(
              from.year,
              from.month +
                  (input['candidate_months'] as int) *
                      (input['every_months'] as int),
              1,
            ),
          );
          pattern = EveryNMonths(
            anchorMonth: from,
            interval: input['every_months'] as int,
            selector: DayOfMonth(
              input['nominal_day'] as int,
              missingDatePolicy: input['missing_date'] == 'omit'
                  ? MissingDatePolicy.omit
                  : MissingDatePolicy.lastValid,
            ),
          );
        }
        final result = resolver.expand(
          plan(pattern),
          from: from,
          toExclusive: end,
          observedZone: 'UTC',
          maxDates: 50,
          maxRows: 50,
        );
        expect(result.complete, isTrue);
        expect(
          result.rows.map((r) => r.identity.originalDate.toString()).toList(),
          c['expected'],
        );
        for (final row in result.rows) {
          expect(row.identity.personId, 'ada');
          expect(row.identity.slotId, isNull);
          expect(row.plannedCount, 3);
          expect(row.amount.quantity.canonical, '1.25');
          expect(row.instant, isNull);
        }
      },
    );
  }
  test('C10/C11 sparse leap next remains separate from empty preview', () {
    for (final policy in MissingDatePolicy.values) {
      final p = plan(
        EveryNMonths(
          anchorMonth: d('2028-02-29'),
          interval: 12,
          selector: DayOfMonth(29, missingDatePolicy: policy),
        ),
      );
      final preview = resolver.expand(
        p,
        from: d('2028-03-01'),
        toExclusive: d('2028-04-01'),
        observedZone: 'UTC',
        maxDates: 1,
        maxRows: 1,
      );
      expect(preview.complete, isTrue);
      expect(preview.rows, isEmpty);
      final next = resolver.nextCalendarDate(p, after: d('2028-03-01'));
      final expected = policy == MissingDatePolicy.omit
          ? (oracle('C10')['expected'] as Map)['next_date']
          : oracle('C11')['expected'];
      expect(next.date.toString(), expected);
      expect(next.complete, isTrue);
      expect(next.candidatesExamined, lessThanOrEqualTo(4));
    }
  });
  test('B01 direct civil ordinal seek and bounded UTC instant work', () {
    final p = plan(
      EveryNDays(anchor: d('2000-01-01'), interval: 2),
      timing: DailySlots([
        DailySlot(
          id: 'am',
          time: WallTime(8, 0),
          amount: amount(),
          reminderEnabled: true,
        ),
      ]),
    );
    final result = resolver.nextCalendarDate(p, after: d('2090-01-01'));
    expect(result.date.toString(), oracle('B01')['expected']);
    expect(result.candidatesExamined, 1);
    final next = resolver.nextInstant(
      p,
      after: DateTime.utc(2090, 1, 1),
      observedZone: 'UTC',
      maxDates: 1,
    );
    expect(next.next!.instant, DateTime.utc(2090, 1, 2, 8));
    expect(next.datesExamined, 1);
  });
  test('host measurement: 10000 old-anchor sparse calendar seeks', () {
    final p = plan(EveryNDays(anchor: d('2000-01-01'), interval: 2));
    final before = ProcessInfo.currentRss;
    final watch = Stopwatch()..start();
    var work = 0;
    for (var i = 0; i < 10000; i++) {
      final next = resolver.nextCalendarDate(p, after: d('2090-01-01'));
      expect(next.date, d('2090-01-02'));
      work += next.candidatesExamined;
    }
    watch.stop();
    expect(work, 10000);
    // Host debug test, not a physical-device or allocation measurement.
    // ignore: avoid_print
    print(
      'calendar_host seeks=10000 candidates=$work elapsed_us=${watch.elapsedMicroseconds} rss_before=$before rss_after=${ProcessInfo.currentRss}',
    );
  });
  test('B03 malformed rules reject rather than approximate', () {
    expect(
      () => EveryNDays(anchor: d('2026-01-01'), interval: 0),
      throwsArgumentError,
    );
    expect(
      () => EveryNWeeks(
        anchorWeekStart: d('2026-01-01'),
        interval: -1,
        weekdays: [1],
      ),
      throwsArgumentError,
    );
    expect(() => DayOfMonth(31), throwsArgumentError);
    expect(
      () => plan(SelectedWeekdays([1]), timing: const AsNeeded()),
      throwsArgumentError,
    );
    expect(() => OrdinalWeekday(5, 1), throwsArgumentError);
    expect(() => SelectedWeekdays([]), throwsArgumentError);
    expect(
      () => EveryNDays(anchor: d('2026-01-01'), interval: 1 << 62),
      throwsArgumentError,
    );
    final result = resolver.expand(
      plan(const UnsupportedCalendarPattern('elapsed_weekday_filter')),
      from: d('2026-01-01'),
      toExclusive: d('2026-02-01'),
      observedZone: 'UTC',
      maxDates: 2,
      maxRows: 2,
    );
    expect(result.complete, isFalse);
    expect(result.issue, DailyCalculationIssue.unsupportedCalendarComposition);
  });
  test('ordinal fifth fallback retains nominal selector and last weekday is direct', () {
    for (final policy in MissingDatePolicy.values) {
      final p = plan(
        EveryNMonths(
          anchorMonth: d('2027-01-01'),
          interval: 1,
          selector: OrdinalWeekday(5, 1, missingDatePolicy: policy),
        ),
      );
      final result = resolver.expand(
        p,
        from: d('2027-02-01'),
        toExclusive: d('2027-04-01'),
        observedZone: 'UTC',
        maxDates: 5,
        maxRows: 5,
      );
      expect(
        result.rows.map((r) => r.identity.originalDate.toString()).toList(),
        policy == MissingDatePolicy.omit
            ? ['2027-03-29']
            : ['2027-02-22', '2027-03-29'],
      );
    }
  });
  test('budgets, half-open bounds, set weekdays and immutable non-Monday week anchor', () {
    final p = plan(SelectedWeekdays([1, 1, 4]));
    final range = resolver.expand(
      p,
      from: d('2026-10-19'),
      toExclusive: d('2026-10-26'),
      observedZone: 'UTC',
      maxDates: 1,
      maxRows: 5,
    );
    expect(range.complete, isFalse);
    expect(range.resumeDate, d('2026-10-22'));
    final finite = plan(p.calendar, end: d('2026-10-22'));
    expect(
      resolver.nextCalendarDate(finite, after: d('2026-10-19')).date,
      isNull,
    );
    final weekly = EveryNWeeks(
      anchorWeekStart: d('2026-12-30'),
      interval: 2,
      weekdays: [1, 4],
    );
    expect(
      const CalendarSelector().onOrAfter(weekly, d('2027-01-05')).date,
      d('2027-01-14'),
    );
    final sparse = plan(
      EveryNMonths(
        anchorMonth: d('2028-02-29'),
        interval: 12,
        selector: DayOfMonth(29, missingDatePolicy: MissingDatePolicy.omit),
      ),
    );
    final limited = resolver.nextCalendarDate(
      sparse,
      after: d('2028-03-01'),
      maxCandidates: 1,
    );
    expect(limited.complete, isFalse);
    expect(limited.issue, CalendarIssue.workLimit);
    final overflow = resolver.nextCalendarDate(
      plan(const EveryDay()),
      after: d('9999-12-31'),
    );
    expect(overflow.complete, isFalse);
    expect(overflow.issue, CalendarIssue.calendarRangeLimit);
  });
  for (final id in ['Z01', 'Z02', 'Z03', 'Z04']) {
    test('$id calendar selected clock ambiguity retains original slot', () {
      final c = oracle(id),
          input = oracle(id)['inputs'] as Map<String, dynamic>;
      final local = DateTime.parse('${input['local']}Z');
      final date = CivilDate.fromDateTime(local);
      final p = plan(
        SelectedWeekdays([local.weekday]),
        zone: input['zone'] as String,
        timing: DailySlots([
          DailySlot(
            id: 'am',
            time: WallTime(local.hour, local.minute),
            amount: amount(),
            reminderEnabled: true,
          ),
        ]),
      );
      final row = resolver.resolveDate(p, date, observedZone: 'UTC').single;
      expect(
        row.clockCandidates
            .map((x) => x.toIso8601String().replaceFirst('.000Z', 'Z'))
            .toList(),
        c['expected'],
      );
      expect(row.identity.originalDate, date);
      expect(row.identity.slotId, 'am');
      expect(row.instant, isNull);
      if (row.clockCandidates.isNotEmpty) {
        final choice = DailyClockChoice.capture(
          row,
          const ChooseClockInstance(1),
        );
        final resolved = resolver
            .resolveDate(
              p,
              date,
              observedZone: 'UTC',
              decisions: {row.identity: choice},
            )
            .single;
        expect(resolved.identity, row.identity);
        expect(resolved.instant, row.clockCandidates[1]);
      }
    });
  }
  test('calendar date survives named-zone range issue; civil interval is not 48 hours', () {
    DailyTiming timing() => DailySlots([
      DailySlot(
        id: 'am',
        time: WallTime(8, 0),
        amount: amount(),
        reminderEnabled: true,
      ),
    ]);
    final p = plan(
      EveryNDays(anchor: d('2026-03-28'), interval: 2),
      zone: 'Europe/London',
      timing: timing(),
    );
    final rows = resolver
        .expand(
          p,
          from: d('2026-03-28'),
          toExclusive: d('2026-03-31'),
          observedZone: 'UTC',
          maxDates: 2,
          maxRows: 2,
        )
        .rows;
    expect(
      rows.last.instant!.difference(rows.first.instant!),
      const Duration(hours: 47),
    );
    final future = resolver.nextDate(
      p,
      from: d('2090-01-01'),
      observedZone: 'UTC',
    );
    expect(future.complete, isFalse);
    expect(future.calendarDate, isNotNull);
    expect(future.issue, DailyCalculationIssue.unsupportedTimezoneRange);
  });
}
