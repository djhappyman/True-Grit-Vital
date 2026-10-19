import 'package:flutter_test/flutter_test.dart';
import 'package:true_grit_vital/domain/records.dart';
import 'package:true_grit_vital/domain/scheduling/daily_plan.dart';
import 'package:true_grit_vital/domain/scheduling/daily_resolver.dart';
import 'package:true_grit_vital/domain/scheduling/interval_resolver.dart';

void main() {
  final date = CivilDate(2026, 10, 25);
  final cut = DateTime.utc(2026, 10, 25, 12);
  final amount = PlannedAmount(
    quantity: ExactQuantity.parse('1'),
    unit: 'tablet',
  );
  final daily = DailyResolver();
  final interval = IntervalResolver();
  DailyPlanVersion plan(
    String id,
    DailyTiming timing, {
    DateTime? from,
    DateTime? until,
    List<PlanPause> pauses = const [],
  }) => DailyPlanVersion(
    personId: 'p',
    planId: 'plan',
    itemId: 'item',
    versionId: id,
    start: date,
    endExclusive: date.addDays(1),
    timing: timing,
    zoneBasis: FixedHome('UTC'),
    pauses: pauses,
    effectiveFrom: from,
    effectiveUntil: until,
  );
  DailySlots slots() => DailySlots([
    for (final hour in [8, 12, 20])
      DailySlot(
        id: '$hour',
        time: WallTime(hour, 0),
        amount: amount,
        reminderEnabled: true,
      ),
  ]);
  ElapsedInterval elapsed(String segment, DateTime anchor) => ElapsedInterval(
    segmentId: segment,
    duration: ExactElapsed.parseHours('6'),
    mode: IntervalMode.fixedPlanned,
    plannedAnchor: anchor,
    amount: amount,
  );

  test('exact bounds require UTC and a positive half-open interval', () {
    expect(
      () => plan('bad', slots(), from: DateTime(2026)),
      throwsArgumentError,
    );
    expect(
      () => plan('bad', slots(), from: cut, until: cut),
      throwsArgumentError,
    );
    expect(
      () => plan(
        'bad',
        slots(),
        from: cut,
        until: cut.subtract(const Duration(seconds: 1)),
      ),
      throwsArgumentError,
    );
    final p = plan('new', slots(), from: cut);
    expect(p.includesInstant(cut), isTrue);
    expect(
      p.includesInstant(cut.subtract(const Duration(microseconds: 1))),
      isFalse,
    );
  });

  test('uncaptured morning slots keep old version while exact boundary starts new version', () {
    final original = plan('original', slots());
    final old = plan('original', slots(), until: cut);
    final next = plan('restart', slots(), from: cut);
    final before = daily.resolveDate(original, date, observedZone: 'UTC');
    final oldRows = daily.resolveDate(old, date, observedZone: 'UTC');
    final newRows = daily.resolveDate(next, date, observedZone: 'UTC');
    expect(oldRows.map((r) => r.identity.slotId), ['8']);
    expect(oldRows.single.identity, before.first.identity);
    expect(oldRows.single.instant, before.first.instant);
    expect(oldRows.single.versionId, before.first.versionId);
    expect(newRows.map((r) => r.identity.slotId), ['12', '20']);
    expect(newRows.first.instant, cut);
    expect(newRows.first.versionId, 'restart');
    final seek = daily.nextInstant(
      old,
      after: DateTime.utc(2026, 10, 25, 8),
      observedZone: 'UTC',
      maxDates: 2,
    );
    expect(seek.next, isNull);
    expect(seek.complete, isTrue);
  });

  test('uncaptured fixed elapsed ordinals retain old segment before intraday restart', () {
    final old = plan(
      'original',
      elapsed('old-segment', DateTime.utc(2026, 10, 25)),
      until: cut,
    );
    final next = plan('restart', elapsed('new-segment', cut), from: cut);
    List<DailyExpectation> rows(DailyPlanVersion p) => interval
        .expand(
          p,
          from: DateTime.utc(2026, 10, 25),
          toExclusive: DateTime.utc(2026, 10, 26),
          now: DateTime.utc(2026, 10, 26),
          observedZone: 'UTC',
          maxRows: 10,
        )
        .rows;
    final oldRows = rows(old);
    final newRows = rows(next);
    expect(oldRows.map((r) => r.instant), [
      DateTime.utc(2026, 10, 25),
      DateTime.utc(2026, 10, 25, 6),
    ]);
    expect(oldRows.map((r) => r.identity.intervalOrdinal), [0, 1]);
    expect(
      oldRows.map((r) => r.identity.intervalSegmentId),
      everyElement('old-segment'),
    );
    expect(newRows.map((r) => r.instant), [
      cut,
      DateTime.utc(2026, 10, 25, 18),
    ]);
    expect(newRows.map((r) => r.identity.intervalOrdinal), [0, 1]);
    expect(
      newRows.map((r) => r.identity.intervalSegmentId),
      everyElement('new-segment'),
    );
    expect(oldRows.last.identity, isNot(newRows.first.identity));
  });

  test(
    'exact lower bound filters original fixed ordinals without changing anchor',
    () {
      final p = plan(
        'later',
        elapsed('same-segment', DateTime.utc(2026, 10, 25)),
        from: cut.add(const Duration(minutes: 1)),
      );
      final result = interval.current(
        p,
        now: DateTime.utc(2026, 10, 26),
        observedZone: 'UTC',
      );
      expect(result.next!.instant, DateTime.utc(2026, 10, 25, 18));
      expect(result.next!.identity.intervalOrdinal, 3);
      expect(
        (p.timing as ElapsedInterval).plannedAnchor,
        DateTime.utc(2026, 10, 25),
      );
    },
  );

  test('same-day partial count versions share one original bucket and captured progress basis', () {
    final original = daily
        .resolveDate(
          plan('original', DailyCount(3, amount)),
          date,
          observedZone: 'UTC',
        )
        .single;
    final old = plan('original', DailyCount(3, amount), until: cut);
    final next = plan('restart', DailyCount(3, amount), from: cut);
    final rows = [
      ...daily.resolveDate(
        old,
        date,
        observedZone: 'UTC',
        historical: {original.identity: original},
      ),
      ...daily.resolveDate(
        next,
        date,
        observedZone: 'UTC',
        historical: {original.identity: original},
      ),
    ];
    expect(rows.map((r) => r.identity).toSet(), {original.identity});
    expect(rows.every((r) => identical(r, original)), isTrue);
    expect(rows.every((r) => r.plannedCount == 3 && r.instant == null), isTrue);
  });

  test(
    'count eligibility clips to exact version interval before pause coverage',
    () {
      final p = plan(
        'short',
        DailyCount(3, amount),
        from: cut,
        until: cut.add(const Duration(hours: 1)),
        pauses: [
          PlanPause(
            start: cut.subtract(const Duration(hours: 1)),
            resume: cut.add(const Duration(hours: 2)),
          ),
        ],
      );
      expect(daily.resolveDate(p, date, observedZone: 'UTC'), isEmpty);
      final result = daily.nextDate(p, from: date, observedZone: 'UTC');
      expect(result.next, isNull);
      expect(result.complete, isTrue);
    },
  );

  test('actual single next before exact version start remains absent', () {
    final p = plan(
      'actual',
      ElapsedInterval(
        segmentId: 'actual-segment',
        duration: ExactElapsed.parseHours('6'),
        mode: IntervalMode.qualifyingActual,
        amount: amount,
      ),
      from: cut,
    );
    final result = interval.current(
      p,
      now: DateTime.utc(2026, 10, 26),
      observedZone: 'UTC',
      sources: [
        IntervalSource(
          actualId: 'actual',
          revision: 1,
          personId: 'p',
          itemId: 'item',
          planId: 'plan',
          segmentId: 'actual-segment',
          instant: DateTime.utc(2026, 10, 25),
        ),
      ],
    );
    expect(result.next, isNull);
    expect(result.complete, isTrue);
  });
}
