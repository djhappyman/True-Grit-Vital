import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:true_grit_vital/domain/records.dart';
import 'package:true_grit_vital/domain/scheduling/daily_plan.dart';
import 'package:true_grit_vital/domain/scheduling/daily_resolver.dart';
import 'package:true_grit_vital/domain/scheduling/interval_resolver.dart';
import 'package:true_grit_vital/domain/scheduling/iana_clock.dart';
import 'package:true_grit_vital/domain/scheduling/pause_eligibility.dart';

void main() {
  DateTime utc(String value) => DateTime.parse(value);
  CivilDate date(String value) => CivilDate.parse(value);
  final amount = PlannedAmount(
    quantity: ExactQuantity.parse('1'),
    unit: 'tablet',
  );
  final daily = DailyResolver();
  final interval = IntervalResolver();
  final now = utc('2026-10-26T12:00:00Z');
  DailyPlanVersion plan({
    DailyTiming? timing,
    CalendarPattern calendar = const EveryDay(),
    List<PlanPause> pauses = const [],
    OnOffPattern? onOff,
    String zone = 'UTC',
    CivilDate? start,
    CivilDate? end,
  }) => DailyPlanVersion(
    personId: 'p',
    planId: 'plan',
    itemId: 'i',
    versionId: 'v',
    start: start ?? date('2000-01-01'),
    endExclusive: end,
    timing: timing ?? DailyCount(3, amount),
    calendar: calendar,
    zoneBasis: FixedHome(zone),
    pauses: pauses,
    onOff: onOff,
  );
  ElapsedInterval elapsed({
    String anchor = '2026-10-24T21:00:00Z',
    bool actual = false,
    String segment = 'old',
    String hours = '6',
  }) => ElapsedInterval(
    segmentId: segment,
    duration: ExactElapsed.parseHours(hours),
    mode: actual ? IntervalMode.qualifyingActual : IntervalMode.fixedPlanned,
    plannedAnchor: actual ? null : utc(anchor),
    amount: amount,
  );
  DailySlots slots() => DailySlots([
    DailySlot(
      id: 'morning',
      time: WallTime(8, 0),
      amount: amount,
      reminderEnabled: true,
    ),
    DailySlot(
      id: 'evening',
      time: WallTime(20, 0),
      amount: amount,
      reminderEnabled: true,
    ),
  ]);
  IntervalSource source(String instant) => IntervalSource(
    actualId: 'actual',
    revision: 1,
    personId: 'p',
    itemId: 'i',
    planId: 'plan',
    segmentId: 'old',
    instant: utc(instant),
  );

  test('half-open UTC pause validation and exact resume eligibility', () {
    final pause = PlanPause(
      start: utc('2026-10-25T08:00:00Z'),
      resume: utc('2026-10-25T20:00:00Z'),
    );
    expect(pause.contains(pause.start), isTrue);
    expect(pause.contains(pause.resume!), isFalse);
    expect(() => PlanPause(start: DateTime(2026)), throwsArgumentError);
    expect(
      () => PlanPause(start: pause.start, resume: pause.start),
      throwsArgumentError,
    );
    final p = plan(timing: slots(), pauses: [pause]);
    final rows = daily.resolveDate(p, date('2026-10-25'), observedZone: 'UTC');
    expect(rows.single.identity.slotId, 'evening');
    expect(rows.single.instant, pause.resume);
  });

  test('partial untimed day keeps original bucket and count; fully paused day absent', () {
    final baseline = daily
        .resolveDate(plan(), date('2026-10-25'), observedZone: 'UTC')
        .single;
    final partial = plan(
      pauses: [
        PlanPause(
          start: utc('2026-10-25T09:00:00Z'),
          resume: utc('2026-10-25T21:00:00Z'),
        ),
      ],
    );
    final row = daily
        .resolveDate(
          partial,
          date('2026-10-25'),
          observedZone: 'UTC',
          historical: {baseline.identity: baseline},
        )
        .single;
    expect(identical(row, baseline), isTrue);
    expect(row.plannedCount, 3);
    expect(row.instant, isNull);
    final full = plan(
      pauses: [
        PlanPause(
          start: utc('2026-10-25T00:00:00Z'),
          resume: utc('2026-10-26T00:00:00Z'),
        ),
      ],
    );
    expect(
      daily.resolveDate(full, date('2026-10-25'), observedZone: 'UTC'),
      isEmpty,
    );
  });

  test('touching and overlapping pauses combine for full-date coverage', () {
    final p = plan(
      pauses: [
        PlanPause(
          start: utc('2026-10-24T20:00:00Z'),
          resume: utc('2026-10-25T12:00:00Z'),
        ),
        PlanPause(
          start: utc('2026-10-25T12:00:00Z'),
          resume: utc('2026-10-26T00:00:00Z'),
        ),
      ],
    );
    expect(
      daily.resolveDate(p, date('2026-10-25'), observedZone: 'UTC'),
      isEmpty,
    );
  });

  test(
    'captured snapshots stay unchanged while active planned rows suppress',
    () {
      final captured = daily
          .resolveDate(
            plan(timing: slots()),
            date('2026-10-25'),
            observedZone: 'UTC',
          )
          .first;
      final p = plan(
        timing: slots(),
        pauses: [
          PlanPause(
            start: utc('2026-10-25T08:00:00Z'),
            resume: utc('2026-10-25T09:00:00Z'),
          ),
        ],
      );
      final rows = daily.resolveDate(
        p,
        date('2026-10-25'),
        observedZone: 'UTC',
        historical: {captured.identity: captured},
      );
      expect(rows.map((r) => r.identity.slotId), ['evening']);
      expect(captured.instant, utc('2026-10-25T08:00:00Z'));
      expect(captured.versionId, 'v');
    },
  );

  test('actual sole next inside pause remains absent after resume without invented actual', () {
    final p = plan(
      timing: elapsed(actual: true),
      pauses: [
        PlanPause(
          start: utc('2026-10-25T01:00:00Z'),
          resume: utc('2026-10-25T08:00:00Z'),
        ),
      ],
    );
    final result = interval.current(
      p,
      now: now,
      observedZone: 'UTC',
      sources: [source('2026-10-24T21:00:00Z')],
    );
    expect(result.next, isNull);
    expect(result.complete, isTrue);
    final during = interval.current(
      p,
      now: now,
      observedZone: 'UTC',
      sources: [source('2026-10-25T04:00:00Z')],
    );
    expect(during.next!.instant, utc('2026-10-25T10:00:00Z'));
    expect(during.next!.identity.sourceActualId, 'actual');
    expect(during.next!.identity.sourceActualRevision, 1);
    expect(during.next!.identity.intervalOrdinal, isNull);
  });

  test(
    'elapsed on/off filters original instants without resetting ordinal',
    () {
      final p = plan(
        timing: elapsed(anchor: '2026-10-24T21:00:00Z'),
        onOff: OnOffPattern(anchor: date('2026-10-24'), onDays: 1, offDays: 1),
        zone: 'Europe/London',
      );
      final result = interval.next(
        p,
        after: utc('2026-10-24T21:00:00Z'),
        now: now,
        observedZone: 'UTC',
      );
      expect(result.next!.instant, utc('2026-10-26T03:00:00Z'));
      expect(result.next!.identity.intervalOrdinal, 5);
      expect(result.next!.identity.intervalSegmentId, 'old');
    },
  );

  test('on/off intersection, continuous zero-off and bounded impossible intersection', () {
    final p = plan(
      calendar: SelectedWeekdays([1]),
      onOff: OnOffPattern(anchor: date('2026-10-19'), onDays: 3, offDays: 2),
    );
    final result = daily.nextDate(
      p,
      from: date('2026-10-25'),
      observedZone: 'UTC',
    );
    expect(result.next!.identity.originalDate, date('2026-10-26'));
    expect(
      OnOffPattern(
        anchor: date('2026-10-25'),
        onDays: 3,
        offDays: 0,
      ).includes(date('2026-01-01')),
      isTrue,
    );
    final impossible = plan(
      calendar: EveryNDays(anchor: date('2026-10-20'), interval: 2),
      onOff: OnOffPattern(anchor: date('2026-10-19'), onDays: 1, offDays: 1),
    );
    final bounded = daily.nextCalendarDate(
      impossible,
      after: date('2026-10-18'),
      maxCandidates: 5,
    );
    expect(bounded.complete, isFalse);
    expect(bounded.issue, CalendarIssue.workLimit);
    expect(bounded.candidatesExamined, 5);
  });

  test('open pause and finite plan bounds terminate without scanning', () {
    final p = plan(
      timing: slots(),
      pauses: [PlanPause(start: utc('2026-03-01T00:00:00Z'))],
    );
    final result = daily.nextInstant(
      p,
      after: utc('2026-03-01T00:00:00Z'),
      observedZone: 'UTC',
      maxDates: 1,
    );
    expect(result.complete, isTrue);
    expect(result.next, isNull);
    expect(result.datesExamined, 0);
    final fixed = interval.current(
      plan(timing: elapsed(), pauses: p.pauses),
      now: now,
      observedZone: 'UTC',
    );
    expect(fixed.complete, isTrue);
    expect(fixed.next, isNull);
  });

  test(
    'long pause crosses both London clocks and jumps directly to resume',
    () {
      final p = plan(
        timing: slots(),
        zone: 'Europe/London',
        pauses: [
          PlanPause(
            start: utc('2026-01-01T00:00:00Z'),
            resume: utc('2026-11-01T08:00:00Z'),
          ),
        ],
      );
      final result = daily.nextInstant(
        p,
        after: utc('2026-01-01T00:00:00Z'),
        observedZone: 'UTC',
        maxDates: 2,
      );
      expect(result.complete, isTrue);
      expect(result.next!.instant, utc('2026-11-01T08:00:00Z'));
      expect(result.datesExamined, 1);
    },
  );

  test(
    'missing eligibility boundary remains explicit without invented midnight',
    () {
      final p = plan(
        zone: 'America/Sao_Paulo',
        pauses: [PlanPause(start: utc('2018-11-03T00:00:00Z'))],
      );
      expect(
        () =>
            PauseEligibility(IanaClock())
                .coveringDate(p, date('2018-11-04'), 'America/Sao_Paulo'),
        throwsA(isA<PauseBoundaryUnavailable>()),
      );
      final result = daily.nextDate(
        p,
        from: date('2018-11-04'),
        observedZone: 'UTC',
      );
      expect(result.complete, isFalse);
      expect(result.issue, DailyCalculationIssue.unsupportedTimezoneRange);
    },
  );

  final oracle = jsonDecode(
    File('test/fixtures/scheduling/08-11-expected.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  for (final raw in oracle['cases'] as List<dynamic>) {
    final entry = raw as Map<String, dynamic>;
    final id = entry['id'] as String;
    if (!id.startsWith('P') && id != 'B02') continue;
    test('$id matches independently saved pause oracle', () {
      final input = entry['inputs'] as Map<String, dynamic>;
      if (id == 'P05') {
        final p = plan(
          timing: elapsed(anchor: input['anchor'] as String),
          zone: 'Europe/London',
          pauses: [
            PlanPause(
              start: utc(input['pause'] as String),
              resume: utc(input['resume'] as String),
            ),
          ],
        );
        final row = interval
            .next(
              p,
              after: utc(input['pause'] as String),
              now: now,
              observedZone: 'UTC',
            )
            .next!;
        expect(row.instant, utc(entry['expected'] as String));
        expect(row.identity.intervalOrdinal, 2);
      } else if (id == 'P06') {
        final p = plan(
          timing: elapsed(
            anchor: input['first_selected'] as String,
            segment: 'restart',
          ),
        );
        final rows = interval.expand(
          p,
          from: utc(input['resume'] as String),
          toExclusive: utc(input['resume'] as String)
              .add(const Duration(hours: 12)),
          now: now,
          observedZone: 'UTC',
          maxRows: 5,
        );
        expect(
          rows.rows.map((r) => r.instant),
          (entry['expected'] as List).map((e) => utc(e as String)),
        );
        expect(
          rows.rows.map((r) => r.identity.intervalSegmentId),
          everyElement('restart'),
        );
        expect(rows.rows.map((r) => r.identity.intervalOrdinal), [0, 1]);
      } else if (id == 'P03' || id == 'P04') {
        final p = plan(
          onOff: OnOffPattern(
            anchor: date(input['anchor'] as String),
            onDays: input['on_days'] as int,
            offDays: input['off_days'] as int,
          ),
        );
        final rows = daily.expand(
          p,
          from: date(input['start'] as String),
          toExclusive: date(input['end'] as String),
          observedZone: 'UTC',
          maxDates: 20,
          maxRows: 20,
        );
        expect(rows.complete, isTrue);
        expect(
          rows.rows.map((r) => r.identity.originalDate.toString()),
          entry['expected'],
        );
      } else {
        final restart = id == 'P02';
        final anchor = date(
          input[restart ? 'new_segment' : 'anchor'] as String,
        );
        final resume = date(
          input[restart ? 'new_segment' : 'resume'] as String,
        );
        final p = plan(
          calendar: EveryNDays(
            anchor: anchor,
            interval: input['every_days'] as int,
          ),
          pauses: restart
              ? []
              : [
                  PlanPause(
                    start: utc(
                      '${input['pause_start'] ?? '2026-03-29'}T00:00:00Z',
                    ),
                    resume: utc('${input['resume']}T00:00:00Z'),
                  ),
                ],
        );
        if (id == 'B02') {
          final result = daily.nextDate(
            p,
            from: date('2026-01-01'),
            observedZone: 'UTC',
          );
          expect(
            result.next!.identity.originalDate.toString(),
            entry['expected'],
          );
          expect(result.datesExamined, 1);
        } else {
          final rows = daily.expand(
            p,
            from: resume,
            toExclusive: resume.addDays(restart ? 6 : 4),
            observedZone: 'UTC',
            maxDates: 10,
            maxRows: 10,
          );
          expect(
            rows.rows.map((r) => r.identity.originalDate.toString()),
            entry['expected'],
          );
        }
      }
    });
  }

  test('host evidence: 10000 twenty-year pauses preserve calendar/elapsed identity', () {
    final pause = PlanPause(
      start: utc('2026-01-01T00:00:00Z'),
      resume: utc('2046-01-01T00:00:00Z'),
    );
    final p = plan(
      calendar: EveryNDays(anchor: date('2000-01-01'), interval: 2),
      pauses: [pause],
    );
    final e = plan(
      timing: elapsed(anchor: '2000-01-01T00:00:00Z'),
      pauses: [pause],
    );
    final watch = Stopwatch()..start();
    var count = 0;
    for (var i = 0; i < 10000; i++) {
      final next = daily.nextDate(
        p,
        from: date('2026-01-01'),
        observedZone: 'UTC',
      );
      expect(next.datesExamined, 1);
      count += interval
          .next(e, after: pause.start, now: now, observedZone: 'UTC')
          .next!
          .identity
          .intervalOrdinal!;
    }
    watch.stop();
    expect(count, greaterThan(0));
    stdout.writeln(
      'pause_host seeks=20000 elapsed_us=${watch.elapsedMicroseconds} ordinal_sum=$count',
    );
  });
}
