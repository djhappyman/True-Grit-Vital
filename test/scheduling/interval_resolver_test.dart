import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:true_grit_vital/domain/records.dart';
import 'package:true_grit_vital/domain/scheduling/daily_plan.dart';
import 'package:true_grit_vital/domain/scheduling/daily_resolver.dart';
import 'package:true_grit_vital/domain/scheduling/interval_resolver.dart';

void main() {
  final amount = PlannedAmount(
    quantity: ExactQuantity.parse('1'),
    unit: 'tablet',
  );
  final resolver = IntervalResolver();
  DateTime utc(String text) => DateTime.parse(text);
  DailyPlanVersion plan({
    bool actual = false,
    String anchor = '2026-03-28T22:00:00Z',
    String hours = '6',
    CivilDate? start,
    CivilDate? end,
  }) => DailyPlanVersion(
    personId: 'p',
    itemId: 'i',
    planId: 'plan',
    versionId: 'v1',
    start: start ?? CivilDate(2026, 1, 1),
    endExclusive: end,
    zoneBasis: const FollowingLocal(),
    timing: ElapsedInterval(
      segmentId: 'segment',
      duration: ExactElapsed.parseHours(hours),
      amount: amount,
      mode: actual ? IntervalMode.qualifyingActual : IntervalMode.fixedPlanned,
      plannedAnchor: actual ? null : utc(anchor),
      reminderEnabled: true,
    ),
  );
  IntervalSource source(
    String id,
    String instant, {
    int revision = 1,
    bool qualifies = true,
    bool isVoid = false,
    String person = 'p',
    String segment = 'segment',
  }) => IntervalSource(
    actualId: id,
    revision: revision,
    personId: person,
    itemId: 'i',
    planId: 'plan',
    segmentId: segment,
    instant: utc(instant),
    qualifies: qualifies,
    isVoid: isVoid,
  );
  final now = utc('2026-10-19T10:00:00Z');
  DailyExpectation? actual(List<IntervalSource> sources) => resolver
      .current(
        plan(actual: true),
        now: now,
        observedZone: 'UTC',
        sources: sources,
      )
      .next;

  test('entered hours have exact precision and checked limits', () {
    expect(ExactElapsed.parseHours('0.0000000025').microseconds, 9);
    expect(ExactElapsed.parseHours('1.25').microseconds, 4500000000);
    for (final invalid in [
      '0',
      '-1',
      '1e2',
      '0.0000000001',
      '99999999999999999999999999999999',
    ]) {
      expect(() => ExactElapsed.parseHours(invalid), throwsFormatException);
    }
  });
  test('E01 E02 fixed elapsed crosses both clocks', () {
    for (final (anchor, expected) in [
      ('2026-03-28T22:00:00Z', '2026-03-29T04:00:00Z'),
      ('2026-10-24T22:00:00Z', '2026-10-25T04:00:00Z'),
    ]) {
      final result = resolver.next(
        plan(anchor: anchor),
        after: utc(anchor),
        now: now,
        observedZone: 'Europe/London',
      );
      expect(result.next!.instant, utc(expected));
      expect(result.next!.identity.intervalOrdinal, 1);
      expect(result.next!.amount.quantity.canonical, '1');
      expect(result.next!.reminderEnabled, isTrue);
    }
  });
  test('fixed strict seek jumps decades without replay', () {
    final result = resolver.next(
      plan(anchor: '2000-01-01T00:00:00Z', start: CivilDate(2000, 1, 1)),
      after: utc('2090-01-01T00:00:00Z'),
      now: now,
      observedZone: 'UTC',
    );
    expect(result.complete, isTrue);
    expect(result.next!.instant, utc('2090-01-01T06:00:00Z'));
    expect(result.next!.identity.intervalOrdinal, 131493);
    expect(result.sourcesExamined, 0);
  });
  test('one actual next remains overdue, strict seek projects no others', () {
    final sources = [source('a', '2026-10-18T06:00:00Z')];
    expect(actual(sources)!.instant, utc('2026-10-18T12:00:00Z'));
    final next = resolver.next(
      plan(actual: true),
      after: now,
      now: now,
      observedZone: 'UTC',
      sources: sources,
    );
    expect(next.next, isNull);
    expect(next.complete, isTrue);
  });
  test('A01-A09 correction backfill extras ties and void fallback', () {
    final original = source('b', '2026-10-19T06:00:00Z');
    expect(actual([original])!.instant, utc('2026-10-19T12:00:00Z'));
    expect(
      actual([source('b', '2026-10-19T05:00:00Z', revision: 2)])!.instant,
      utc('2026-10-19T11:00:00Z'),
    );
    expect(
      actual([original, source('older', '2026-10-18T23:00:00Z')])!
          .identity
          .sourceActualId,
      'b',
    );
    expect(
      actual([original, source('new', '2026-10-19T06:30:00Z')])!.instant,
      utc('2026-10-19T12:30:00Z'),
    );
    expect(
      actual([
        original,
        source('extra', '2026-10-19T06:30:00Z', qualifies: false),
      ])!.identity.sourceActualId,
      'b',
    );
    expect(
      actual([original, source('a', '2026-10-19T06:00:00Z')])!
          .identity
          .sourceActualId,
      'a',
    );
    expect(actual([source('b', '2026-10-19T06:00:00Z', isVoid: true)]), isNull);
    expect(
      actual([original, source('new', '2026-10-19T06:30:00Z', isVoid: true)])!
          .identity
          .sourceActualId,
      'b',
    );
    expect(
      actual([source('foreign', '2026-10-19T07:00:00Z', person: 'other')]),
      isNull,
    );
    expect(
      actual([original, source('b', '2026-10-19T07:00:00Z', segment: 'old')])!
          .identity
          .sourceActualId,
      'b',
    );
  });
  test('no anchor and bounded source failure are distinct', () {
    final empty = resolver.current(
      plan(actual: true),
      now: now,
      observedZone: 'UTC',
    );
    expect(empty.issue, IntervalIssue.noAnchor);
    expect(empty.complete, isTrue);
    final bounded = resolver.current(
      plan(actual: true),
      now: now,
      observedZone: 'UTC',
      sources: [
        source('a', '2026-10-19T05:00:00Z'),
        source('b', '2026-10-19T06:00:00Z'),
      ],
      maxSources: 1,
    );
    expect(bounded.complete, isFalse);
    expect(bounded.next, isNull);
    expect(bounded.issue, IntervalIssue.workLimit);
  });
  test('future qualification rejected and defensively excluded', () {
    final future = source('f', '2026-10-19T11:00:00Z');
    expect(() => future.validateQualificationAt(now), throwsArgumentError);
    expect(actual([future]), isNull);
  });
  test('source revision changes identity; display zone preserves it', () {
    final a = actual([source('a', '2026-10-19T06:00:00Z')])!;
    final b = actual([source('a', '2026-10-19T05:00:00Z', revision: 2)])!;
    expect(a.identity, isNot(b.identity));
    final london = resolver
        .current(
          plan(actual: true),
          now: now,
          observedZone: 'Europe/London',
          sources: [source('a', '2026-10-19T06:00:00Z')],
        )
        .next!;
    expect(a.identity, london.identity);
    expect(a.instant, utc('2026-10-19T12:00:00Z'));
  });
  test('range truncation provides inclusive resume cursor', () {
    final p = plan(anchor: '2026-10-19T00:00:00Z');
    final r = resolver.expand(
      p,
      from: utc('2026-10-19T00:00:00Z'),
      toExclusive: utc('2026-10-20T00:00:00Z'),
      now: now,
      observedZone: 'UTC',
      maxRows: 2,
    );
    expect(r.rows.map((x) => x.instant), [
      utc('2026-10-19T00:00:00Z'),
      utc('2026-10-19T06:00:00Z'),
    ]);
    expect(r.complete, isFalse);
    expect(r.resumeInstant, utc('2026-10-19T12:00:00Z'));
    final resumed = resolver.expand(
      p,
      from: r.resumeInstant!,
      toExclusive: utc('2026-10-20T00:00:00Z'),
      now: now,
      observedZone: 'UTC',
      maxRows: 2,
    );
    expect(resumed.rows.length, 2);
    expect(resumed.complete, isTrue);
  });
  test('daily preview shares rows and captured immutable history', () {
    final p = plan(anchor: '2026-10-19T00:00:00Z');
    final daily = DailyResolver();
    final rows = daily.resolveDate(
      p,
      CivilDate(2026, 10, 19),
      observedZone: 'UTC',
      now: now,
    );
    expect(rows.length, 4);
    final captured = rows.first;
    final expanded = daily.expand(
      p,
      from: CivilDate(2026, 10, 19),
      toExclusive: CivilDate(2026, 10, 20),
      observedZone: 'UTC',
      now: now,
      maxDates: 1,
      maxRows: 10,
      historical: {captured.identity: captured},
    );
    expect(identical(expanded.rows.first, captured), isTrue);
  });
  test('date bounds and named-zone range are explicit', () {
    final p = plan(
      anchor: '2026-10-18T00:00:00Z',
      start: CivilDate(2026, 10, 19),
      end: CivilDate(2026, 10, 20),
    );
    expect(
      resolver.current(p, now: now, observedZone: 'UTC').next!.instant,
      utc('2026-10-19T00:00:00Z'),
    );
    expect(
      resolver
          .next(
            p,
            after: utc('2026-10-19T18:00:00Z'),
            now: now,
            observedZone: 'UTC',
          )
          .next,
      isNull,
    );
    final far = resolver.next(
      plan(),
      after: utc('2090-01-01T00:00:00Z'),
      now: now,
      observedZone: 'Europe/London',
    );
    expect(far.issue, IntervalIssue.unsupportedTimezoneRange);
    expect(far.complete, isFalse);
  });
  final oracle = jsonDecode(
    File('test/fixtures/scheduling/08-11-expected.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  for (final raw in oracle['cases'] as List<dynamic>) {
    final entry = raw as Map<String, dynamic>;
    final id = entry['id'] as String;
    if (!id.startsWith('E') && !id.startsWith('A')) continue;
    test('$id independent saved oracle matches production interval', () {
      final input = entry['inputs'] as Map<String, dynamic>;
      if (id.startsWith('E')) {
        final anchor = utc(input['anchor'] as String);
        final rows = resolver.expand(
          plan(anchor: input['anchor'] as String),
          from: anchor,
          toExclusive: anchor.add(const Duration(hours: 24)),
          now: now,
          observedZone: 'Europe/London',
          maxRows: 10,
        );
        expect(
          rows.rows.map((row) => row.instant),
          (entry['expected'] as List<dynamic>).map(
            (value) => utc(value as String),
          ),
        );
        expect(rows.rows.map((row) => row.identity.intervalOrdinal), [
          0,
          1,
          2,
          3,
        ]);
      } else {
        final sources = [
          for (final rawRecord in input['records'] as List<dynamic>)
            source(
              (rawRecord as Map<String, dynamic>)['id'] as String,
              rawRecord['actual'] as String,
              qualifies: rawRecord['qualifies'] as bool,
              isVoid: rawRecord['voided'] == true,
            ),
        ];
        final result = actual(sources);
        if (id == 'A09') {
          expect(
            [result!.instant],
            (entry['expected'] as List<dynamic>).map(
              (value) => utc(value as String),
            ),
          );
        } else {
          final expected = entry['expected'] as Map<String, dynamic>;
          expect(result?.identity.sourceActualId, expected['anchor']);
          expect(
            result?.instant,
            expected['next'] == null ? null : utc(expected['next'] as String),
          );
        }
      }
    });
  }

  test('host measurement: 10000 ninety-year interval seeks', () {
    final p = plan(
      anchor: '2000-01-01T00:00:00Z',
      start: CivilDate(2000, 1, 1),
    );
    final after = utc('2090-01-01T00:00:00Z');
    final watch = Stopwatch()..start();
    var ordinals = 0;
    for (var i = 0; i < 10000; i++) {
      ordinals += resolver
          .next(p, after: after, now: now, observedZone: 'UTC')
          .next!
          .identity
          .intervalOrdinal!;
    }
    watch.stop();
    expect(ordinals, 1314930000);
    // Host timing is evidence, never a physical-device release assertion.
    stdout.writeln(
      'interval_host seeks=10000 elapsed_us=${watch.elapsedMicroseconds}',
    );
  });
  test(
    'next date honors date cursor rather than first original fixed ordinal',
    () {
      final result = DailyResolver().nextDate(
        plan(anchor: '2026-01-01T00:00:00Z'),
        from: CivilDate(2026, 10, 19),
        now: now,
        observedZone: 'UTC',
      );
      expect(result.next!.instant, utc('2026-10-19T00:00:00Z'));
    },
  );

  test('civil supported-range overflow is incomplete rather than no next', () {
    final p = plan(anchor: '9999-12-31T23:59:59.999999Z');
    final result = resolver.next(
      p,
      after: utc('9999-12-31T23:59:59.999999Z'),
      now: now,
      observedZone: 'UTC',
    );
    expect(result.complete, isFalse);
    expect(result.issue, IntervalIssue.rangeLimit);
  });
}
