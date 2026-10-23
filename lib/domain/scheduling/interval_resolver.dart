import 'package:timezone/timezone.dart' as tz;

import 'daily_plan.dart';
import 'iana_clock.dart';
import 'pause_eligibility.dart';

enum IntervalIssue { noAnchor, workLimit, rangeLimit, unsupportedTimezoneRange }

final class IntervalNext {
  const IntervalNext({
    this.next,
    required this.complete,
    this.issue,
    this.sourcesExamined = 0,
  });
  final DailyExpectation? next;
  final bool complete;
  final IntervalIssue? issue;
  final int sourcesExamined;
}

final class IntervalExpansion {
  IntervalExpansion(
    Iterable<DailyExpectation> rows, {
    required this.complete,
    this.issue,
    this.resumeInstant,
    this.sourcesExamined = 0,
  }) : rows = List.unmodifiable(rows);
  final List<DailyExpectation> rows;
  final bool complete;
  final IntervalIssue? issue;
  final DateTime? resumeInstant;
  final int sourcesExamined;
}

/// Exact UTC arithmetic with bounded source inspection and ordinal jumps.
///
/// Actual mode deliberately supplies one expectation, even when overdue.
final class IntervalResolver {
  IntervalResolver({IanaClock? clock}) : clock = clock ?? IanaClock();
  final IanaClock clock;
  static const calculatorVersion = 'elapsed-1';
  static final _minimum = BigInt.from(DateTime.utc(1).microsecondsSinceEpoch);
  static final _maximum = BigInt.from(
    DateTime.utc(9999, 12, 31, 23, 59, 59, 999, 999).microsecondsSinceEpoch,
  );

  IntervalNext current(
    DailyPlanVersion plan, {
    required DateTime now,
    required String observedZone,
    Iterable<IntervalSource> sources = const [],
    int maxSources = 100000,
  }) => _resolve(
    plan,
    now: now,
    observedZone: observedZone,
    sources: sources,
    maxSources: maxSources,
  );

  /// Seeks the next expectation strictly after the cursor.
  ///
  /// An overdue actual-derived expectation is absent here. No subsequent
  /// assumed administration is fabricated.
  IntervalNext next(
    DailyPlanVersion plan, {
    required DateTime after,
    required DateTime now,
    required String observedZone,
    Iterable<IntervalSource> sources = const [],
    int maxSources = 100000,
  }) {
    _utc(after);
    return _resolve(
      plan,
      now: now,
      observedZone: observedZone,
      sources: sources,
      maxSources: maxSources,
      after: after,
    );
  }

  /// Seeks the first elapsed expectation on or after a display date.
  ///
  /// An older single actual-derived expectation creates no fresh anchor.
  IntervalNext nextDate(
    DailyPlanVersion plan, {
    required CivilDate from,
    required DateTime now,
    required String observedZone,
    Iterable<IntervalSource> sources = const [],
  }) {
    try {
      final start = _dateBoundary(from, plan.zoneBasis.zoneFor(observedZone));
      return next(
        plan,
        after: start.subtract(const Duration(microseconds: 1)),
        now: now,
        observedZone: observedZone,
        sources: sources,
      );
    } on UnsupportedClockRange {
      return const IntervalNext(
        complete: false,
        issue: IntervalIssue.unsupportedTimezoneRange,
      );
    }
  }

  IntervalNext _resolve(
    DailyPlanVersion plan, {
    required DateTime now,
    required String observedZone,
    required Iterable<IntervalSource> sources,
    required int maxSources,
    DateTime? after,
  }) {
    _utc(now);
    _budget(maxSources);
    final timing = plan.timing;
    if (timing is! ElapsedInterval || plan.calendar is! EveryDay) {
      throw ArgumentError('interval_plan_required');
    }
    IntervalSource? winner;
    var examined = 0;
    if (timing.mode == IntervalMode.qualifyingActual) {
      final ids = <String>{};
      for (final source in sources) {
        if (examined == maxSources) {
          return IntervalNext(
            complete: false,
            issue: IntervalIssue.workLimit,
            sourcesExamined: examined,
          );
        }
        examined++;
        if (source.personId != plan.personId ||
            source.itemId != plan.itemId ||
            source.planId != plan.planId ||
            source.segmentId != timing.segmentId) {
          continue;
        }
        if (!ids.add(source.actualId)) {
          throw ArgumentError('duplicate_interval_source');
        }
        if (!source.qualifies || source.isVoid || source.instant.isAfter(now)) {
          continue;
        }
        if (winner == null ||
            source.instant.isAfter(winner.instant) ||
            source.instant == winner.instant &&
                source.actualId.compareTo(winner.actualId) < 0) {
          winner = source;
        }
      }
      if (winner == null) {
        return IntervalNext(
          complete: true,
          issue: IntervalIssue.noAnchor,
          sourcesExamined: examined,
        );
      }
    }
    final anchor = timing.plannedAnchor ?? winner!.instant;
    final step = BigInt.from(timing.duration.microseconds);
    var ordinal = timing.mode == IntervalMode.fixedPlanned
        ? BigInt.zero
        : BigInt.one;
    if (after != null &&
        timing.mode == IntervalMode.fixedPlanned &&
        !after.isBefore(anchor)) {
      ordinal =
          (BigInt.from(after.microsecondsSinceEpoch) -
                  BigInt.from(anchor.microsecondsSinceEpoch)) ~/
              step +
          BigInt.one;
    }
    // Date-effective version bounds remain independent of immutable sequence.
    // At most two candidates cover a display date boundary; UTC ordinal seeks
    // avoid replaying the elapsed sequence from its beginning.
    final zone = plan.zoneBasis.zoneFor(observedZone);
    final startFloor = BigInt.from(
      plan.start.calendarValue
          .subtract(const Duration(days: 1))
          .microsecondsSinceEpoch,
    );
    final base = BigInt.from(anchor.microsecondsSinceEpoch);
    if (timing.mode == IntervalMode.fixedPlanned &&
        base + step * ordinal < startFloor) {
      ordinal = (startFloor - base + step - BigInt.one) ~/ step;
    }
    if (timing.mode == IntervalMode.fixedPlanned &&
        plan.effectiveFrom != null) {
      final exactFloor = BigInt.from(
        plan.effectiveFrom!.microsecondsSinceEpoch,
      );
      if (base + step * ordinal < exactFloor) {
        ordinal = (exactFloor - base + step - BigInt.one) ~/ step;
      }
    }
    var boundAttempts = 0;
    while (true) {
      final value = base + step * ordinal;
      if (value < _minimum || value > _maximum) {
        return IntervalNext(
          complete: false,
          issue: IntervalIssue.rangeLimit,
          sourcesExamined: examined,
        );
      }
      final instant = DateTime.fromMicrosecondsSinceEpoch(
        value.toInt(),
        isUtc: true,
      );
      if (!plan.includesInstant(instant)) {
        // A qualifying actual supplies just one next. An excluded candidate
        // cannot be rolled forward to the version's start as an assumed use.
        return IntervalNext(complete: true, sourcesExamined: examined);
      }
      CivilDate date;
      try {
        date = clock.dateAt(instant, zone);
      } on UnsupportedClockRange {
        return IntervalNext(
          complete: false,
          issue: IntervalIssue.unsupportedTimezoneRange,
          sourcesExamined: examined,
        );
      }
      if (plan.endExclusive != null &&
          date.compareTo(plan.endExclusive!) >= 0) {
        return IntervalNext(complete: true, sourcesExamined: examined);
      }
      if (date.compareTo(plan.start) < 0) {
        if (timing.mode == IntervalMode.qualifyingActual) {
          return IntervalNext(complete: true, sourcesExamined: examined);
        }
        // Advance directly toward the lower local-date bound, allowing all
        // retained zone offsets without assuming today's offset at the anchor.
        if (++boundAttempts > 3) {
          return IntervalNext(
            complete: false,
            issue: IntervalIssue.workLimit,
            sourcesExamined: examined,
          );
        }
        final BigInt midnightCandidate;
        try {
          midnightCandidate = BigInt.from(
            _dateBoundary(plan.start, zone).microsecondsSinceEpoch,
          );
        } on UnsupportedClockRange {
          return IntervalNext(
            complete: false,
            issue: IntervalIssue.unsupportedTimezoneRange,
            sourcesExamined: examined,
          );
        }
        final jump = (midnightCandidate - base + step - BigInt.one) ~/ step;
        ordinal = jump > ordinal ? jump : ordinal + BigInt.one;
        continue;
      }
      if (after != null && !instant.isAfter(after)) {
        return IntervalNext(complete: true, sourcesExamined: examined);
      }
      final pause = PauseEligibility(clock).containing(plan, instant);
      final onOff = plan.onOff;
      if (pause != null || onOff != null && !onOff.includes(date)) {
        // Actual mode has only one derived expectation. Suppression does not
        // fabricate an administration or move its next to the resume boundary.
        if (timing.mode == IntervalMode.qualifyingActual ||
            pause != null && pause.resume == null) {
          return IntervalNext(complete: true, sourcesExamined: examined);
        }
        if (++boundAttempts > 4800) {
          return IntervalNext(
            complete: false,
            issue: IntervalIssue.workLimit,
            sourcesExamined: examined,
          );
        }
        DateTime jump;
        try {
          if (pause != null) {
            jump = pause.resume!;
          } else {
            final active = onOff!.onOrAfter(date);
            if (active == null) {
              return IntervalNext(
                complete: false,
                issue: IntervalIssue.rangeLimit,
                sourcesExamined: examined,
              );
            }
            jump = _dateBoundary(active, zone);
          }
        } on UnsupportedClockRange {
          return IntervalNext(
            complete: false,
            issue: IntervalIssue.unsupportedTimezoneRange,
            sourcesExamined: examined,
          );
        }
        final nextOrdinal =
            (BigInt.from(jump.microsecondsSinceEpoch) -
                base +
                step -
                BigInt.one) ~/
            step;
        ordinal = nextOrdinal > ordinal ? nextOrdinal : ordinal + BigInt.one;
        continue;
      }
      final wall = tz.TZDateTime.from(instant, tz.getLocation(zone));
      final identity = DailyIdentity(
        personId: plan.personId,
        planId: plan.planId,
        originalDate: CivilDate.fromDateTime(instant),
        slotId: 'interval',
        intervalSegmentId: timing.segmentId,
        intervalOrdinal: timing.mode == IntervalMode.fixedPlanned
            ? ordinal.toInt()
            : null,
        sourceActualId: winner?.actualId,
        sourceActualRevision: winner?.revision,
      );
      return IntervalNext(
        complete: true,
        sourcesExamined: examined,
        next: DailyExpectation(
          identity: identity,
          itemId: plan.itemId,
          versionId: plan.versionId,
          timingPolicy: plan.timingPolicy,
          zoneId: zone,
          amount: timing.amount,
          resolution: DailyResolution.exact,
          calculatorVersion: calculatorVersion,
          timezoneDataVersion: IanaClock.dataVersion,
          originalTime: WallTime(wall.hour, wall.minute),
          effectiveTime: WallTime(wall.hour, wall.minute),
          instant: instant,
          reminderEnabled: timing.reminderEnabled,
          clockCandidates: [instant],
        ),
      );
    }
  }

  /// Expands a half-open instant range.
  ///
  /// A truncated result has a resumable instant cursor.
  IntervalExpansion expand(
    DailyPlanVersion plan, {
    required DateTime from,
    required DateTime toExclusive,
    required DateTime now,
    required String observedZone,
    required int maxRows,
    Iterable<IntervalSource> sources = const [],
    int maxSources = 100000,
  }) {
    _utc(from);
    _utc(toExclusive);
    _budget(maxRows);
    if (from.isAfter(toExclusive)) throw ArgumentError('reversed_range');
    if (from == toExclusive) return IntervalExpansion([], complete: true);
    final timing = plan.timing;
    if (timing is! ElapsedInterval) {
      throw ArgumentError('interval_plan_required');
    }
    // One microsecond subtraction is safe within the supported civil range.
    var result = timing.mode == IntervalMode.qualifyingActual
        ? current(
            plan,
            now: now,
            observedZone: observedZone,
            sources: sources,
            maxSources: maxSources,
          )
        : next(
            plan,
            after: from.subtract(const Duration(microseconds: 1)),
            now: now,
            observedZone: observedZone,
            maxSources: maxSources,
          );
    final rows = <DailyExpectation>[];
    while (true) {
      final row = result.next;
      if (row == null || !row.instant!.isBefore(toExclusive)) {
        return IntervalExpansion(
          rows,
          complete: result.complete,
          issue: result.issue,
          sourcesExamined: result.sourcesExamined,
        );
      }
      if (!row.instant!.isBefore(from)) {
        if (rows.length == maxRows) {
          return IntervalExpansion(
            rows,
            complete: false,
            issue: IntervalIssue.workLimit,
            resumeInstant: row.instant,
            sourcesExamined: result.sourcesExamined,
          );
        }
        rows.add(row);
      }
      if (timing.mode == IntervalMode.qualifyingActual) {
        return IntervalExpansion(
          rows,
          complete: true,
          sourcesExamined: result.sourcesExamined,
        );
      }
      result = next(
        plan,
        after: row.instant!,
        now: now,
        observedZone: observedZone,
        maxSources: maxSources,
      );
    }
  }

  IntervalExpansion expandDates(
    DailyPlanVersion plan, {
    required CivilDate from,
    required CivilDate toExclusive,
    required DateTime now,
    required String observedZone,
    required int maxRows,
    Iterable<IntervalSource> sources = const [],
  }) {
    if (from.compareTo(toExclusive) > 0) throw ArgumentError('reversed_range');
    final zone = plan.zoneBasis.zoneFor(observedZone);
    try {
      return expand(
        plan,
        from: _dateBoundary(from, zone),
        toExclusive: _dateBoundary(toExclusive, zone),
        now: now,
        observedZone: observedZone,
        maxRows: maxRows,
        sources: sources,
      );
    } on UnsupportedClockRange {
      return IntervalExpansion(
        [],
        complete: false,
        issue: IntervalIssue.unsupportedTimezoneRange,
      );
    }
  }

  DateTime _dateBoundary(CivilDate date, String zone) {
    final candidates = clock.candidates(date, WallTime(0, 0), zone);
    if (candidates.isNotEmpty) return candidates.first;
    // A missing midnight bounds elapsed instants by the first instant of the
    // display date. This never creates a wall-clock occurrence or identity.
    return tz.TZDateTime(
      tz.getLocation(zone),
      date.year,
      date.month,
      date.day,
    ).toUtc();
  }

  void _utc(DateTime value) {
    if (!value.isUtc) throw ArgumentError('interval_requires_utc');
  }

  void _budget(int value) {
    if (value < 1 || value > 100000) {
      throw ArgumentError('invalid_interval_budget');
    }
  }
}
