import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:true_grit_vital/domain/records.dart';
import 'package:true_grit_vital/domain/scheduling/daily_plan.dart';
import 'package:true_grit_vital/domain/scheduling/daily_resolver.dart';
import 'package:true_grit_vital/domain/scheduling/iana_clock.dart';

PlannedAmount amount([String value = '1']) =>
    PlannedAmount(quantity: ExactQuantity.parse(value), unit: 'tablet');
DailyPlanVersion plan({
  DailyTiming? timing,
  DailyZoneBasis? zone,
  CivilDate? start,
  CivilDate? end,
  String person = 'ada',
  String version = 'v1',
}) => DailyPlanVersion(
  personId: person,
  planId: 'p1',
  itemId: 'i1',
  versionId: version,
  start: start ?? CivilDate(1900, 1, 1),
  endExclusive: end,
  timing:
      timing ??
      DailySlots([
        DailySlot(
          id: 'am',
          time: WallTime(1, 30),
          amount: amount(),
          reminderEnabled: true,
        ),
      ]),
  zoneBasis: zone ?? FixedHome('Europe/London'),
);
DailyExpectation row(
  DailyResolver resolver,
  DailyPlanVersion p,
  CivilDate date, {
  String observed = 'Europe/London',
  Map<DailyIdentity, ClockDecision> decisions = const {},
  Map<DailyIdentity, DailyExpectation> historical = const {},
}) => resolver
    .resolveDate(
      p,
      date,
      observedZone: observed,
      decisions: {
        for (final entry in decisions.entries)
          entry.key: DailyClockChoice.capture(
            resolver.resolveDate(p, date, observedZone: observed).single,
            entry.value,
          ),
      },
      historical: historical,
    )
    .single;

void main() {
  final resolver = DailyResolver();
  group('Independent IANA oracle', () {
    final oracle = jsonDecode(
      File('test/scheduling/fixtures/time-oracle.json')
          .readAsStringSync(),
    ) as Map<String, dynamic>;
    for (final testCase in oracle['cases'] as List<dynamic>) {
      final value = testCase as Map<String, dynamic>;
      test('${value['id']} exact candidate set', () {
        final local = DateTime.parse('${value['local']}Z');
        final actual = resolver.clock.candidates(
          CivilDate.fromDateTime(local),
          WallTime(local.hour, local.minute),
          value['zone'] as String,
        );
        expect(
          actual,
          (value['utc'] as List<dynamic>)
              .map((s) => DateTime.parse(s as String))
              .toList(),
        );
      });
    }
    test('2026e Manitoba rule independently checked against zic', () {
      expect(IanaClock.dataVersion, '2026e');
      expect(
        resolver.clock.candidates(
          CivilDate(2026, 11, 2),
          WallTime(12, 0),
          'America/Winnipeg',
        ),
        [DateTime.utc(2026, 11, 2, 17)],
      );
    });
    test(
      'complete asset retains aliases and historical British Standard Time',
      () {
        expect(
          resolver.clock.candidates(
            CivilDate(2026, 7, 11),
            WallTime(8, 0),
            'US/Eastern',
          ),
          [DateTime.utc(2026, 7, 11, 12)],
        );
        expect(
          resolver.clock.candidates(
            CivilDate(1969, 1, 1),
            WallTime(8, 0),
            'Europe/London',
          ),
          [DateTime.utc(1969, 1, 1, 7)],
        );
      },
    );
  });
  group('Daily meaning', () {
    test(
      'count has one stable bucket, exact amount and no invented instant',
      () {
        final p = plan(timing: DailyCount(3, amount('0.333333')));
        final a = row(resolver, p, CivilDate(2026, 10, 19));
        expect(a.plannedCount, 3);
        expect(a.amount.quantity.canonical, '0.333333');
        expect(a.instant, isNull);
        expect(a.originalTime, isNull);
        expect(
          a.reminderStateAt(DateTime.utc(2027)),
          DailyReminderState.untimed,
        );
        expect(a.identity.slotId, isNull);
      },
    );
    test('as-needed never projects expected rows', () {
      final p = plan(timing: const AsNeeded());
      expect(
        resolver.resolveDate(
          p,
          CivilDate(2026, 10, 19),
          observedZone: 'Europe/London',
        ),
        isEmpty,
      );
      expect(
        resolver
            .nextInstant(
              p,
              after: DateTime.utc(2026),
              observedZone: 'Europe/London',
              maxDates: 1,
            )
            .next,
        isNull,
      );
    });
    test(
      'explicit slots keep stable identities, independent amounts/reminders',
      () {
        final p = plan(
          timing: DailySlots([
            DailySlot(
              id: 'am',
              time: WallTime(8, 0),
              amount: amount(),
              reminderEnabled: true,
            ),
            DailySlot(
              id: 'pm',
              time: WallTime(20, 0),
              amount: amount('2'),
              reminderEnabled: false,
            ),
          ]),
        );
        final rows = resolver.resolveDate(
          p,
          CivilDate(2026, 10, 19),
          observedZone: 'Europe/London',
        );
        expect(rows.map((r) => r.instant), [
          DateTime.utc(2026, 10, 19, 7),
          DateTime.utc(2026, 10, 19, 19),
        ]);
        expect(rows.map((r) => r.identity.slotId), ['am', 'pm']);
        expect(rows[1].amount.quantity.canonical, '2');
        expect(
          rows[1].reminderStateAt(DateTime.utc(2026)),
          DailyReminderState.disabled,
        );
      },
    );
    test('missing time remains an expectation; choice preserves original', () {
      final p = plan();
      final date = CivilDate(2026, 3, 29);
      final unresolved = row(resolver, p, date);
      expect(unresolved.resolution, DailyResolution.missingClock);
      expect(unresolved.instant, isNull);
      expect(
        unresolved.reminderStateAt(DateTime.utc(2026)),
        DailyReminderState.reviewClock,
      );
      final replacement = row(
        resolver,
        p,
        date,
        decisions: {unresolved.identity: ReplaceClockTime(WallTime(2, 30))},
      );
      expect(replacement.identity, unresolved.identity);
      expect(replacement.originalTime, WallTime(1, 30));
      expect(replacement.effectiveTime, WallTime(2, 30));
      expect(replacement.instant, DateTime.utc(2026, 3, 29, 1, 30));
      final noAlert = row(
        resolver,
        p,
        date,
        decisions: {unresolved.identity: const NoAlert()},
      );
      expect(noAlert.resolution, DailyResolution.noAlert);
      expect(noAlert.instant, isNull);
      expect(noAlert.identity, unresolved.identity);
      final next = resolver.nextInstant(
        p,
        after: DateTime.utc(2026, 3, 29),
        observedZone: 'Europe/London',
        maxDates: 2,
      );
      expect(next.next!.instant, DateTime.utc(2026, 3, 30, 0, 30));
      expect(next.needsReview.single.identity, unresolved.identity);
    });
    test('fold requires one explicit instance; never doubles', () {
      final p = plan();
      final date = CivilDate(2026, 10, 25);
      final unresolved = row(resolver, p, date);
      expect(unresolved.resolution, DailyResolution.repeatedClock);
      expect(unresolved.instant, isNull);
      for (var i = 0; i < 2; i++) {
        final selected = row(
          resolver,
          p,
          date,
          decisions: {unresolved.identity: ChooseClockInstance(i)},
        );
        expect(selected.instant, DateTime.utc(2026, 10, 25, i, 30));
        expect(selected.identity, unresolved.identity);
      }
      expect(
        () => row(
          resolver,
          p,
          date,
          decisions: {unresolved.identity: const ChooseClockInstance(2)},
        ),
        throwsArgumentError,
      );
    });
    test(
      'clock choice rejects edited version, time, zone and mismatched identity',
      () {
        final date = CivilDate(2026, 10, 25);
        final original = row(resolver, plan(), date);
        final choice = DailyClockChoice.capture(
          original,
          const ChooseClockInstance(0),
        );
        final changedPlans = [
          plan(version: 'v2'),
          plan(zone: FixedHome('America/New_York')),
          plan(
            timing: DailySlots([
              DailySlot(
                id: 'am',
                time: WallTime(1, 45),
                amount: amount(),
                reminderEnabled: true,
              ),
            ]),
          ),
        ];
        for (final changed in changedPlans) {
          expect(
            () => resolver.resolveDate(
              changed,
              date,
              observedZone: 'Europe/London',
              decisions: {original.identity: choice},
            ),
            throwsArgumentError,
          );
        }
        final other = row(resolver, plan(person: 'bea'), date);
        expect(
          () => resolver.resolveDate(
            plan(),
            date,
            observedZone: 'Europe/London',
            decisions: {
              original.identity: DailyClockChoice.capture(
                other,
                const ChooseClockInstance(0),
              ),
            },
          ),
          throwsArgumentError,
        );
        expect(
          () => resolver.resolveDate(
            plan(),
            date,
            observedZone: 'Europe/London',
            historical: {original.identity: other},
          ),
          throwsArgumentError,
        );
      },
    );
    test('Lord Howe replacement keeps half-hour transition explicit', () {
      final p = plan(
        zone: FixedHome('Australia/Lord_Howe'),
        timing: DailySlots([
          DailySlot(
            id: 'am',
            time: WallTime(2, 15),
            amount: amount(),
            reminderEnabled: true,
          ),
        ]),
      );
      final date = CivilDate(2026, 10, 4);
      final missing = row(resolver, p, date);
      expect(missing.resolution, DailyResolution.missingClock);
      final selected = row(
        resolver,
        p,
        date,
        decisions: {missing.identity: ReplaceClockTime(WallTime(2, 45))},
      );
      expect(selected.instant, DateTime.utc(2026, 10, 3, 15, 45));
    });
    test('history uses captured version/zone/amount after future edits', () {
      final date = CivilDate(2026, 10, 19);
      final old = row(resolver, plan(), date);
      final changed = plan(
        version: 'v2',
        zone: const FollowingLocal(),
        timing: DailySlots([
          DailySlot(
            id: 'am',
            time: WallTime(9, 0),
            amount: amount('2'),
            reminderEnabled: false,
          ),
        ]),
      );
      final revised = row(
        resolver,
        changed,
        date,
        observed: 'America/New_York',
      );
      expect(revised.identity, old.identity);
      expect(revised.versionId, 'v2');
      expect(revised.instant, DateTime.utc(2026, 10, 19, 13));
      final retained = row(
        resolver,
        changed,
        date,
        observed: 'America/New_York',
        historical: {old.identity: old},
      );
      expect(identical(retained, old), isTrue);
      expect(retained.versionId, 'v1');
      expect(retained.amount.quantity.canonical, '1');
      expect(retained.zoneId, 'Europe/London');
    });
    test('captured history bypasses newer timezone conversion limits', () {
      final date = CivilDate(1800, 1, 1);
      final identity = DailyIdentity(
        personId: 'ada',
        planId: 'p1',
        originalDate: date,
        slotId: 'am',
      );
      final instant = DateTime.utc(1800, 1, 1, 1, 31, 15);
      final captured = DailyExpectation(
        identity: identity,
        itemId: 'i1',
        versionId: 'historical-version',
        zoneId: 'Europe/London',
        amount: amount(),
        resolution: DailyResolution.exact,
        calculatorVersion: 'historical-calculator',
        timezoneDataVersion: 'historical-data',
        originalTime: WallTime(1, 30),
        effectiveTime: WallTime(1, 30),
        instant: instant,
        clockCandidates: [instant],
      );
      final p = plan(start: CivilDate(1700, 1, 1));
      final actual = row(resolver, p, date, historical: {identity: captured});
      expect(identical(actual, captured), isTrue);
    });
    test('person ownership separates otherwise identical expectations', () {
      final date = CivilDate(2026, 10, 19);
      expect(
        row(resolver, plan(), date).identity,
        isNot(row(resolver, plan(person: 'bea'), date).identity),
      );
    });
  });
  group('Travel and calendar buckets', () {
    final countPlan = plan(
      timing: DailyCount(3, amount()),
      zone: const FollowingLocal(),
    );
    test('T02 returning date reuses bucket and retained progress key', () {
      final now = DateTime.utc(2026, 7, 10, 9);
      final before = resolver.currentDate(
        countPlan,
        now: now,
        observedZone: 'Pacific/Kiritimati',
      );
      final after = resolver.currentDate(
        countPlan,
        now: now,
        observedZone: 'Pacific/Honolulu',
      );
      expect(before, CivilDate(2026, 7, 10));
      expect(after, CivilDate(2026, 7, 9));
      final earlier = row(
        resolver,
        countPlan,
        after,
        observed: 'Pacific/Kiritimati',
      );
      final returned = row(
        resolver,
        countPlan,
        after,
        observed: 'Pacific/Honolulu',
      );
      expect(returned.identity, earlier.identity);
      final progress = {
        earlier.identity: 2,
        row(resolver, countPlan, before).identity: 1,
      };
      expect(progress[returned.identity], 2);
      expect(
        progress[row(
          resolver,
          countPlan,
          resolver.currentDate(
            countPlan,
            now: now.add(const Duration(hours: 1)),
            observedZone: 'Pacific/Honolulu',
          ),
        ).identity],
        1,
      );
      expect(progress.length, 2);
    });
    test('T03/T04 short and skipped dates invent no times or catchup', () {
      final now = DateTime.utc(2026, 7, 10, 9);
      expect(
        resolver.currentDate(
          countPlan,
          now: now,
          observedZone: 'Pacific/Honolulu',
        ),
        CivilDate(2026, 7, 9),
      );
      expect(
        resolver.currentDate(
          countPlan,
          now: now,
          observedZone: 'Pacific/Kiritimati',
        ),
        CivilDate(2026, 7, 10),
      );
      expect(
        resolver.currentDate(
          countPlan,
          now: now.add(const Duration(hours: 1)),
          observedZone: 'Pacific/Kiritimati',
        ),
        CivilDate(2026, 7, 11),
      );
      final later = DateTime.utc(2026, 7, 10, 10, 30);
      expect(
        resolver.currentDate(
          countPlan,
          now: later,
          observedZone: 'Pacific/Honolulu',
        ),
        CivilDate(2026, 7, 10),
      );
      expect(
        resolver.currentDate(
          countPlan,
          now: later,
          observedZone: 'Pacific/Kiritimati',
        ),
        CivilDate(2026, 7, 11),
      );
      expect(row(resolver, countPlan, CivilDate(2026, 7, 11)).instant, isNull);
    });
    test('T05 home calendar ignores observed zone', () {
      final p = plan(
        timing: DailyCount(3, amount()),
        zone: FixedHome('Pacific/Kiritimati'),
      );
      final now = DateTime.utc(2026, 7, 10, 9);
      expect(
        resolver.currentDate(p, now: now, observedZone: 'Pacific/Honolulu'),
        CivilDate(2026, 7, 10),
      );
      expect(
        resolver.currentDate(
          p,
          now: now.add(const Duration(hours: 1)),
          observedZone: 'Pacific/Honolulu',
        ),
        CivilDate(2026, 7, 11),
      );
    });
    test(
      'T06 completed local slot preserved; T07 past has no catchup alert',
      () {
        final p = plan(
          zone: const FollowingLocal(),
          timing: DailySlots([
            DailySlot(
              id: 'am',
              time: WallTime(8, 0),
              amount: amount(),
              reminderEnabled: true,
            ),
          ]),
        );
        final date = CivilDate(2026, 7, 10);
        final captured = row(resolver, p, date);
        final travel = row(
          resolver,
          p,
          date,
          observed: 'America/New_York',
          historical: {captured.identity: captured},
        );
        expect(travel.instant, DateTime.utc(2026, 7, 10, 7));
        expect(
          resolver
              .nextInstant(
                p,
                after: DateTime.utc(2026, 7, 10, 12, 30),
                observedZone: 'America/New_York',
                maxDates: 2,
                historical: {captured.identity: captured},
              )
              .next!
              .instant,
          DateTime.utc(2026, 7, 11, 12),
        );
        expect(
          row(resolver, p, date).reminderStateAt(DateTime.utc(2026, 7, 10, 10)),
          DailyReminderState.past,
        );
      },
    );
  });
  group('Bounded work', () {
    test('range cap emits complete days and truthful resume', () {
      final result = resolver.expand(
        plan(),
        from: CivilDate(2026, 1, 1),
        toExclusive: CivilDate(2026, 2, 1),
        observedZone: 'Europe/London',
        maxDates: 2,
        maxRows: 10,
      );
      expect(result.complete, isFalse);
      expect(result.rows.length, 2);
      expect(result.resumeDate, CivilDate(2026, 1, 3));
      final full = resolver.expand(
        plan(),
        from: CivilDate(2026, 1, 1),
        toExclusive: CivilDate(2026, 1, 3),
        observedZone: 'Europe/London',
        maxDates: 2,
        maxRows: 2,
      );
      expect(full.complete, isTrue);
    });
    test('row cap does not materialise a partial or oversized day', () {
      final p = plan(
        timing: DailySlots([
          DailySlot(
            id: 'a',
            time: WallTime(8, 0),
            amount: amount(),
            reminderEnabled: true,
          ),
          DailySlot(
            id: 'b',
            time: WallTime(20, 0),
            amount: amount(),
            reminderEnabled: true,
          ),
        ]),
      );
      final result = resolver.expand(
        p,
        from: CivilDate(2026, 1, 1),
        toExclusive: CivilDate(2026, 1, 3),
        observedZone: 'Europe/London',
        maxDates: 2,
        maxRows: 1,
      );
      expect(result.complete, isFalse);
      expect(result.rows, isEmpty);
      expect(result.datesExamined, 0);
      expect(result.resumeDate, CivilDate(2026, 1, 1));
    });
    test('old start does not replay history; distant start jumps directly', () {
      final next = resolver.nextInstant(
        plan(),
        after: DateTime.utc(2026, 1, 1),
        observedZone: 'Europe/London',
        maxDates: 1,
      );
      expect(next.datesExamined, 1);
      expect(next.next!.instant, DateTime.utc(2026, 1, 1, 1, 30));
      final future = resolver.nextInstant(
        plan(start: CivilDate(2032, 1, 1)),
        after: DateTime.utc(2026),
        observedZone: 'Europe/London',
        maxDates: 1,
      );
      expect(future.next!.identity.originalDate, CivilDate(2032, 1, 1));
      expect(future.datesExamined, 1);
    });
    test('unsupported asset years return calculation issue instead of invented UTC', () {
      expect(
        () => resolver.clock.candidates(
          CivilDate(1800, 1, 1),
          WallTime(8, 0),
          'Europe/London',
        ),
        throwsA(isA<UnsupportedClockRange>()),
      );
      expect(
        () => resolver.clock.candidates(
          CivilDate(1902, 1, 1),
          WallTime(8, 0),
          'Africa/Nairobi',
        ),
        throwsA(isA<UnsupportedClockRange>()),
      );
      expect(
        resolver.clock.candidates(CivilDate(2090, 7, 1), WallTime(8, 0), 'UTC'),
        [DateTime.utc(2090, 7, 1, 8)],
      );
      final p = plan(start: CivilDate(2090, 7, 1));
      final next = resolver.nextInstant(
        p,
        after: DateTime.utc(2026),
        observedZone: 'Europe/London',
        maxDates: 2,
      );
      expect(next.complete, isFalse);
      expect(next.next, isNull);
      expect(next.issue, DailyCalculationIssue.unsupportedTimezoneRange);
      final expanded = resolver.expand(
        p,
        from: CivilDate(2090, 7, 1),
        toExclusive: CivilDate(2090, 7, 3),
        observedZone: 'Europe/London',
        maxDates: 2,
        maxRows: 2,
      );
      expect(expanded.complete, isFalse);
      expect(expanded.rows, isEmpty);
      expect(expanded.issue, DailyCalculationIssue.unsupportedTimezoneRange);
    });
    test('seek bound is incomplete, finite end is truthfully empty', () {
      final cursor = DateTime.utc(2026, 3, 29);
      final bounded = resolver.nextInstant(
        plan(),
        after: cursor,
        observedZone: 'Europe/London',
        maxDates: 1,
      );
      expect(bounded.complete, isFalse);
      expect(bounded.next, isNull);
      expect(bounded.needsReview.length, 1);
      final ended = resolver.nextInstant(
        plan(end: CivilDate(2026, 3, 30)),
        after: cursor,
        observedZone: 'Europe/London',
        maxDates: 1,
      );
      expect(ended.complete, isTrue);
      expect(ended.next, isNull);
      expect(ended.needsReview.length, 1);
    });
    test('strict seek cursor and next independent of empty visible range', () {
      final p = plan(start: CivilDate(2032, 2, 29));
      expect(
        resolver
            .expand(
              p,
              from: CivilDate(2026, 1, 1),
              toExclusive: CivilDate(2026, 2, 1),
              observedZone: 'Europe/London',
              maxDates: 1,
              maxRows: 1,
            )
            .rows,
        isEmpty,
      );
      expect(
        resolver
            .nextDate(
              p,
              from: CivilDate(2026, 1, 1),
              observedZone: 'Europe/London',
            )
            .next!
            .identity
            .originalDate,
        CivilDate(2032, 2, 29),
      );
      final next = resolver.nextInstant(
        p,
        after: DateTime.utc(2032, 2, 29, 1, 30),
        observedZone: 'Europe/London',
        maxDates: 2,
      );
      expect(next.next!.instant, DateTime.utc(2032, 3, 1, 1, 30));
    });
    test('invalid inputs and pathological budgets fail explicitly', () {
      expect(() => CivilDate(2026, 2, 30), throwsArgumentError);
      expect(() => WallTime(24, 0), throwsArgumentError);
      expect(() => DailyCount(0, amount()), throwsArgumentError);
      expect(
        () => resolver.nextInstant(
          plan(),
          after: DateTime.utc(2026),
          observedZone: 'Europe/London',
          maxDates: 100001,
        ),
        throwsArgumentError,
      );
      expect(
        () => resolver.clock.candidates(
          CivilDate(2026, 1, 1),
          WallTime(8, 0),
          'Not/AZone',
        ),
        throwsA(anything),
      );
    });
  });
  test('daily asset preserves 23-hour and 25-hour wall-clock spacing', () {
    final p = plan(
      timing: DailySlots([
        DailySlot(
          id: 'am',
          time: WallTime(8, 0),
          amount: amount(),
          reminderEnabled: true,
        ),
      ]),
    );
    expect(
      row(
        resolver,
        p,
        CivilDate(2026, 3, 29),
      ).instant!.difference(row(resolver, p, CivilDate(2026, 3, 28)).instant!),
      const Duration(hours: 23),
    );
    expect(
      row(
        resolver,
        p,
        CivilDate(2026, 10, 25),
      ).instant!.difference(row(resolver, p, CivilDate(2026, 10, 24)).instant!),
      const Duration(hours: 25),
    );
  });
  test('host measurement: 250 adults, two slots, 14 days', () {
    final rssBefore = ProcessInfo.currentRss;
    final watch = Stopwatch()..start();
    var rows = 0;
    for (var i = 0; i < 250; i++) {
      final p = plan(
        person: 'adult-$i',
        timing: DailySlots([
          DailySlot(
            id: 'am',
            time: WallTime(8, 0),
            amount: amount(),
            reminderEnabled: true,
          ),
          DailySlot(
            id: 'pm',
            time: WallTime(20, 0),
            amount: amount(),
            reminderEnabled: true,
          ),
        ]),
      );
      final result = resolver.expand(
        p,
        from: CivilDate(2026, 10, 19),
        toExclusive: CivilDate(2026, 11, 2),
        observedZone: 'Europe/London',
        maxDates: 14,
        maxRows: 28,
      );
      expect(result.complete, isTrue);
      rows += result.rows.length;
    }
    watch.stop();
    expect(rows, 7000);
    // Host debug-test evidence only; RSS is whole-process, not allocations.
    // ignore: avoid_print
    print(
      'daily_host rows=$rows elapsed_us=${watch.elapsedMicroseconds} rss_before=$rssBefore rss_after=${ProcessInfo.currentRss}',
    );
  });
}
