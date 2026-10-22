import 'daily_plan.dart';
import 'daily_resolver.dart';
import 'iana_clock.dart';
import 'pause_eligibility.dart';

/// A saved item end, independent of display/travel zone and version bounds.
final class PlanEnd {
  PlanEnd({
    required this.zoneId,
    required this.exclusiveInstant,
    this.lastDate,
  }) {
    if (zoneId.isEmpty || !exclusiveInstant.isUtc) {
      throw ArgumentError('invalid_plan_end');
    }
    final clock = IanaClock();
    clock.validateZone(zoneId);
    if (lastDate != null &&
        !clock
            .candidates(lastDate!.addDays(1), WallTime(0, 0), zoneId)
            .contains(exclusiveInstant)) {
      throw ArgumentError('inconsistent_plan_end_date');
    }
  }
  factory PlanEnd.onDate({
    required CivilDate lastDate,
    required String zoneId,
    required IanaClock clock,
  }) {
    final candidates = clock.candidates(
      lastDate.addDays(1),
      WallTime(0, 0),
      zoneId,
    );
    if (candidates.length != 1) {
      throw ArgumentError('plan_end_requires_clock_choice');
    }
    return PlanEnd(
      zoneId: zoneId,
      exclusiveInstant: candidates.single,
      lastDate: lastDate,
    );
  }
  final String zoneId;
  final DateTime exclusiveInstant;
  final CivilDate? lastDate;
}

/// Explicitly reviewed resolved window endpoints; never inferred from a move.
final class WindowOverrideTarget {
  WindowOverrideTarget({
    required this.start,
    required this.end,
    required this.zoneId,
    this.reminderAnchor,
  }) {
    if (!start.isUtc ||
        !end.isUtc ||
        !end.isAfter(start) ||
        reminderAnchor != null &&
            (!reminderAnchor!.isUtc ||
                reminderAnchor!.isBefore(start) ||
                !reminderAnchor!.isBefore(end))) {
      throw ArgumentError('invalid_window_target');
    }
    IanaClock().validateZone(zoneId);
  }
  final DateTime start, end;
  final String zoneId;
  final DateTime? reminderAnchor;
}

final class OccurrenceOverride {
  OccurrenceOverride({
    required this.identity,
    required this.versionId,
    this.targetInstant,
    this.targetZoneId,
    this.windowTarget,
    this.amount,
    Iterable<DailyIdentity> reviewedCollisions = const [],
  }) : reviewedCollisions = List.unmodifiable(reviewedCollisions) {
    if (versionId.isEmpty ||
        targetInstant == null && windowTarget == null && amount == null ||
        targetInstant != null &&
            (!targetInstant!.isUtc || targetZoneId == null) ||
        targetInstant == null && targetZoneId != null) {
      throw ArgumentError('invalid_occurrence_override');
    }
    if (windowTarget != null &&
        (targetInstant != null || targetZoneId != null)) {
      throw ArgumentError('conflicting_override_targets');
    }
    if (targetZoneId != null) IanaClock().validateZone(targetZoneId!);
  }
  final DailyIdentity identity;
  final String versionId;
  final DateTime? targetInstant;
  final String? targetZoneId;
  final WindowOverrideTarget? windowTarget;
  final PlannedAmount? amount;
  final List<DailyIdentity> reviewedCollisions;
}

/// Explicit nonoverlapping segments; gaps are intentionally unplanned.
final class PhasePlan {
  PhasePlan({
    required Iterable<DailyPlanVersion> phases,
    Iterable<DailyPlanVersion> originPhases = const [],
    this.end,
    Iterable<OccurrenceOverride> overrides = const [],
  }) : phases = List.unmodifiable(phases),
       originPhases = List.unmodifiable(originPhases),
       overrides = List.unmodifiable(overrides) {
    if (this.phases.isEmpty) throw ArgumentError('empty_phases');
    final first = this.phases.first;
    final all = [...this.phases, ...this.originPhases];
    if (all.map((p) => p.versionId).toSet().length != all.length ||
        all.any(
          (p) =>
              p.personId != first.personId ||
              p.planId != first.planId ||
              p.itemId != first.itemId,
        )) {
      throw ArgumentError('invalid_origin_phases');
    }
    final ordered = this.phases.toList()
      ..sort((a, b) {
        final civil = a.start.compareTo(b.start);
        return civil != 0
            ? civil
            : a.effectiveFrom == null
            ? (b.effectiveFrom == null ? 0 : -1)
            : b.effectiveFrom == null
            ? 1
            : a.effectiveFrom!.compareTo(b.effectiveFrom!);
      });
    if (this.phases.map((p) => p.versionId).toSet().length !=
            this.phases.length ||
        this.phases.any(
          (p) =>
              p.personId != first.personId ||
              p.planId != first.planId ||
              p.itemId != first.itemId,
        )) {
      throw ArgumentError('phase_owner_mismatch');
    }
    for (var i = 1; i < ordered.length; i++) {
      final previous = ordered[i - 1], next = ordered[i];
      final civilOverlap =
          previous.endExclusive == null ||
          next.start.compareTo(previous.endExclusive!) < 0;
      final exactSeparate =
          previous.effectiveUntil != null &&
          next.effectiveFrom != null &&
          !previous.effectiveUntil!.isAfter(next.effectiveFrom!);
      if (civilOverlap && !exactSeparate) {
        throw ArgumentError('overlapping_phases');
      }
    }
    if (this.overrides.map((o) => o.identity).toSet().length !=
            this.overrides.length ||
        this.overrides.any(
          (o) =>
              o.identity.personId != personId ||
              o.identity.planId != planId ||
              !all.any((p) => p.versionId == o.versionId),
        )) {
      throw ArgumentError('override_owner_mismatch');
    }
  }
  final List<DailyPlanVersion> phases, originPhases;
  final PlanEnd? end;
  final List<OccurrenceOverride> overrides;
  String get personId => phases.first.personId;
  String get itemId => phases.first.itemId;
  String get planId => phases.first.planId;
}

/// Origin phase, one-off override, hard eligibility, then reminders.
final class PhaseResolver {
  PhaseResolver({IanaClock? clock, this.strictOverrides = false})
    : clock = clock ?? IanaClock();
  final bool strictOverrides;
  final IanaClock clock;
  DailyResolver get daily => DailyResolver(clock: clock);

  List<DailyExpectation> resolveDate(
    PhasePlan plan,
    CivilDate date, {
    required String observedZone,
    Map<DailyIdentity, DailyClockChoice> decisions = const {},
    Map<DailyIdentity, DailyExpectation> historical = const {},
    Iterable<IntervalSource> intervalSources = const [],
    DateTime? now,
  }) {
    final expansion = expand(
      plan,
      from: date,
      toExclusive: date.addDays(1),
      observedZone: observedZone,
      maxDates: 100000,
      maxRows: 100000,
      decisions: decisions,
      historical: historical,
      intervalSources: intervalSources,
      now: now,
    );
    if (!expansion.complete) {
      throw StateError('incomplete_phase_date:${expansion.issue}');
    }
    return expansion.rows;
  }

  DailyExpansion expand(
    PhasePlan plan, {
    required CivilDate from,
    required CivilDate toExclusive,
    required String observedZone,
    required int maxDates,
    required int maxRows,
    Map<DailyIdentity, DailyClockChoice> decisions = const {},
    Map<DailyIdentity, DailyExpectation> historical = const {},
    Iterable<IntervalSource> intervalSources = const [],
    DateTime? now,
  }) {
    if (maxDates < 1 ||
        maxRows < 1 ||
        maxDates > 100000 ||
        maxRows > 100000 ||
        from.compareTo(toExclusive) > 0) {
      throw ArgumentError('invalid_phase_budget');
    }
    final rows = <DailyExpectation>[];
    var examined = 0;
    var complete = true;
    CivilDate? resumeDate;
    DateTime? resumeInstant;
    DailyCalculationIssue? issue;
    final overridden = plan.overrides.map((o) => o.identity).toSet();
    for (final phase in plan.phases) {
      if (examined >= maxDates) {
        complete = false;
        resumeDate = phase.start.compareTo(from) > 0 ? phase.start : from;
        break;
      }
      final result = daily.expand(
        phase,
        from: from,
        toExclusive: toExclusive,
        observedZone: observedZone,
        maxDates: maxDates - examined,
        maxRows: maxRows,
        decisions: decisions,
        historical: historical,
        intervalSources: intervalSources,
        now: now,
      );
      examined += result.datesExamined;
      for (final originalRow in result.rows) {
        final conflict = _windowConflict(plan, originalRow);
        final row = conflict == null
            ? originalRow
            : originalRow.withEligibilityConflict(conflict);
        if (!overridden.contains(row.identity) &&
            (!strictOverrides && row.eligibilityConflict != null ||
                _eligible(plan, row, observedZone))) {
          rows.add(
            row.plannedCount != null &&
                    now != null &&
                    plan.end != null &&
                    !now.isBefore(plan.end!.exclusiveInstant)
                ? _endedBucket(row)
                : row,
          );
        }
      }
      if (!result.complete) {
        complete = false;
        resumeDate = result.resumeDate ?? from;
        resumeInstant = result.resumeInstant;
        issue = result.issue;
        break;
      }
    }
    for (final override in plan.overrides) {
      final phase = [
        ...plan.phases,
        ...plan.originPhases,
      ].singleWhere((p) => p.versionId == override.versionId);
      final originals = daily
          .resolveDate(
            _origin(phase),
            override.identity.originalDate,
            observedZone: observedZone,
            decisions: decisions,
            historical: historical,
            intervalSources: intervalSources,
            now: now,
          )
          .where((r) => r.identity == override.identity);
      if (originals.length != 1) {
        if (strictOverrides) throw ArgumentError('override_origin_unavailable');
        return DailyExpansion(
          rows,
          complete: false,
          datesExamined: examined,
          resumeDate: from,
          issue: DailyCalculationIssue.phaseOriginUnavailable,
        );
      }
      final original = originals.single;
      if (!_eligible(plan, original, observedZone, origin: true)) {
        if (strictOverrides) throw ArgumentError('override_origin_ineligible');
        continue;
      }
      if ((override.targetInstant != null && original.instant == null) ||
          (override.windowTarget != null &&
              (original.windowStart == null || original.windowEnd == null))) {
        if (strictOverrides) {
          throw ArgumentError('override_requires_resolved_origin');
        }
        return DailyExpansion(
          rows,
          complete: false,
          datesExamined: examined,
          resumeDate: from,
          issue: DailyCalculationIssue.phaseClockUnresolved,
        );
      }
      final effective = _override(original, override);
      final conflict = _windowConflict(plan, effective);
      final moved = conflict == null
          ? effective
          : effective.withEligibilityConflict(conflict);
      if (!(!strictOverrides && moved.eligibilityConflict != null) &&
          !_eligible(plan, moved, observedZone)) {
        if (strictOverrides) throw ArgumentError('override_target_ineligible');
        continue;
      }
      final date = moved.effectiveDate ?? moved.identity.originalDate;
      if (date.compareTo(from) >= 0 && date.compareTo(toExclusive) < 0) {
        final collisions = rows.where((r) => _collides(r, moved));
        if (collisions.any(
          (r) => !override.reviewedCollisions.contains(r.identity),
        )) {
          throw ArgumentError('override_collision_review_required');
        }
        rows.add(moved);
      }
    }
    for (final override in plan.overrides) {
      final moved = rows
          .where((r) => r.identity == override.identity)
          .firstOrNull;
      if (moved == null) continue;
      if (rows.any(
        (r) =>
            _collides(r, moved) &&
            !override.reviewedCollisions.contains(r.identity),
      )) {
        throw ArgumentError('override_collision_review_required');
      }
    }
    final identities = <DailyIdentity>{};
    rows.removeWhere((row) => !identities.add(row.identity));
    rows.sort(
      (a, b) =>
          (a.effectiveDate ?? a.identity.originalDate).compareTo(
                b.effectiveDate ?? b.identity.originalDate,
              ) !=
              0
          ? (a.effectiveDate ?? a.identity.originalDate).compareTo(
              b.effectiveDate ?? b.identity.originalDate,
            )
          : a.instant != null && b.instant != null
          ? a.instant!.compareTo(b.instant!)
          : 0,
    );
    if (!complete && resumeDate != null) {
      rows.removeWhere(
        (row) => resumeInstant != null && row.instant != null
            ? !row.instant!.isBefore(resumeInstant)
            : (row.effectiveDate ?? row.identity.originalDate).compareTo(
                    resumeDate!,
                  ) >=
                  0,
      );
    }
    if (rows.length > maxRows) {
      final cutoff =
          rows[maxRows].effectiveDate ?? rows[maxRows].identity.originalDate;
      rows.removeWhere(
        (row) =>
            (row.effectiveDate ?? row.identity.originalDate).compareTo(
              cutoff,
            ) >=
            0,
      );
      complete = false;
      resumeDate = cutoff;
      resumeInstant = null;
    }
    return DailyExpansion(
      rows,
      complete: complete,
      datesExamined: examined,
      resumeDate: resumeDate,
      resumeInstant: resumeInstant,
      issue: issue,
    );
  }

  DailyPlanVersion _origin(DailyPlanVersion phase) => DailyPlanVersion(
    personId: phase.personId,
    planId: phase.planId,
    itemId: phase.itemId,
    versionId: phase.versionId,
    start: phase.start,
    endExclusive: phase.endExclusive,
    timing: phase.timing,
    zoneBasis: phase.zoneBasis,
    calendar: phase.calendar,
    onOff: phase.onOff,
    instructions: phase.instructions,
    effectiveFrom: phase.effectiveFrom,
    effectiveUntil: phase.effectiveUntil,
  );

  DailyExpectation _endedBucket(DailyExpectation row) => DailyExpectation(
    identity: row.identity,
    itemId: row.itemId,
    versionId: row.versionId,
    zoneId: row.zoneId,
    amount: row.amount,
    resolution: row.resolution,
    calculatorVersion: row.calculatorVersion,
    timezoneDataVersion: row.timezoneDataVersion,
    plannedCount: row.plannedCount,
    originalAmount: row.originalAmount,
    effectiveDate: row.effectiveDate,
    eligibilityConflict: 'plan_ended',
  );

  String? _windowConflict(PhasePlan plan, DailyExpectation row) {
    if (row.eligibilityConflict != null) return row.eligibilityConflict;
    final start = row.windowStart, end = row.windowEnd;
    if (start == null || end == null) return null;
    if (plan.end != null &&
        start.isBefore(plan.end!.exclusiveInstant) &&
        end.isAfter(plan.end!.exclusiveInstant)) {
      return 'window_crosses_plan_end';
    }
    for (final phase in plan.phases) {
      if (phase.pauses.any(
        (pause) =>
            pause.start.isBefore(end) &&
            (pause.resume == null || pause.resume!.isAfter(start)) &&
            !(!pause.start.isAfter(start) &&
                (pause.resume == null || !pause.resume!.isBefore(end))),
      )) {
        return 'window_crosses_pause';
      }
    }
    return null;
  }

  bool _eligible(
    PhasePlan plan,
    DailyExpectation row,
    String observedZone, {
    bool origin = false,
  }) {
    if (row.eligibilityConflict case final conflict?) {
      if (strictOverrides) throw ArgumentError(conflict);
      return false;
    }
    final start = origin
        ? row.originalWindowStart ??
              row.originalInstant ??
              row.windowStart ??
              row.instant
        : row.windowStart ?? row.instant;
    final end = origin ? row.originalWindowEnd ?? row.windowEnd : row.windowEnd;
    if (end != null && start != null && !end.isAfter(start)) {
      throw ArgumentError('invalid_window_clock_order');
    }
    if (plan.end case final bound?) {
      if (start != null && !start.isBefore(bound.exclusiveInstant)) {
        return false;
      }
      if (end != null && end.isAfter(bound.exclusiveInstant)) {
        if (strictOverrides) throw ArgumentError('window_crosses_plan_end');
        return false;
      }
      if (start == null) {
        final starts = clock.candidates(
          row.identity.originalDate,
          WallTime(0, 0),
          row.zoneId,
        );
        if (starts.length != 1) {
          throw ArgumentError('plan_bound_requires_clock_choice');
        }
        if (!starts.single.isBefore(bound.exclusiveInstant)) return false;
      }
    }
    final eligibility = PauseEligibility(clock);
    for (final phase in plan.phases) {
      if (start != null && eligibility.containing(phase, start) != null) {
        final pause = eligibility.containing(phase, start)!;
        if (end != null &&
            pause.resume != null &&
            pause.resume!.isBefore(end)) {
          if (strictOverrides) throw ArgumentError('window_crosses_pause');
          return false;
        }
        return false;
      }
      if (start != null &&
          end != null &&
          phase.pauses.any(
            (p) =>
                p.start.isBefore(end) &&
                (p.resume == null || p.resume!.isAfter(start)),
          )) {
        if (strictOverrides) throw ArgumentError('window_crosses_pause');
        return false;
      }
    }
    return true;
  }

  DailyExpectation _override(
    DailyExpectation original,
    OccurrenceOverride override,
  ) {
    if (original.plannedCount != null && original.plannedCount! > 1) {
      throw ArgumentError('one_off_requires_single_opportunity');
    }
    final target = override.windowTarget;
    final isWindow = original.windowStart != null || original.windowEnd != null;
    if (isWindow && override.targetInstant != null ||
        !isWindow && target != null) {
      throw ArgumentError('override_target_kind_mismatch');
    }
    if (target != null &&
        (original.windowStart == null || original.windowEnd == null)) {
      throw ArgumentError('override_requires_resolved_window');
    }
    if (target != null &&
        original.reminderEnabled &&
        target.reminderAnchor == null) {
      throw ArgumentError('window_target_requires_reminder_anchor');
    }
    if (override.targetInstant != null && original.instant == null) {
      throw ArgumentError('override_requires_resolved_slot');
    }
    final instant = target != null
        ? target.reminderAnchor
        : override.targetInstant ?? original.instant;
    final zone = target?.zoneId ?? override.targetZoneId ?? original.zoneId;
    return DailyExpectation(
      identity: original.identity,
      itemId: original.itemId,
      versionId: original.versionId,
      zoneId: zone,
      amount: override.amount ?? original.amount,
      resolution: target != null
          ? (instant == null ? DailyResolution.noAlert : DailyResolution.exact)
          : original.resolution,
      calculatorVersion: original.calculatorVersion,
      timezoneDataVersion: original.timezoneDataVersion,
      originalTime: original.originalTime,
      effectiveTime: target != null
          ? clock.timeAt(target.start, zone)
          : override.targetInstant == null
          ? original.effectiveTime
          : clock.timeAt(override.targetInstant!, zone),
      instant: instant,
      plannedCount: original.plannedCount,
      reminderEnabled: original.reminderEnabled,
      clockCandidates: target != null || override.targetInstant != null
          ? [?instant]
          : original.clockCandidates,
      eligibilityConflict: target == null ? original.eligibilityConflict : null,
      windowEndpoints: target == null ? original.windowEndpoints : const [],
      windowStart: target?.start ?? original.windowStart,
      windowEnd: target?.end ?? original.windowEnd,
      reminderAnchor: target != null
          ? target.reminderAnchor
          : original.reminderAnchor,
      originalWindowStart: original.originalWindowStart ?? original.windowStart,
      originalWindowEnd: original.originalWindowEnd ?? original.windowEnd,
      originalReminderAnchor:
          original.originalReminderAnchor ?? original.reminderAnchor,
      originalInstant: original.originalInstant ?? original.instant,
      originalAmount: original.originalAmount ?? original.amount,
      effectiveDate: target != null
          ? clock.dateAt(target.start, zone)
          : override.targetInstant == null
          ? original.effectiveDate
          : clock.dateAt(instant!, zone),
    );
  }

  bool _collides(DailyExpectation a, DailyExpectation b) {
    if (a.identity == b.identity ||
        a.eligibilityConflict != null ||
        b.eligibilityConflict != null) {
      return false;
    }
    final aStart = a.windowStart ?? a.instant,
        bStart = b.windowStart ?? b.instant;
    if (aStart == null || bStart == null) return false;
    if (a.windowEnd == null && b.windowEnd == null) return aStart == bStart;
    if (a.windowEnd == null) {
      return !aStart.isBefore(bStart) && aStart.isBefore(b.windowEnd!);
    }
    if (b.windowEnd == null) {
      return !bStart.isBefore(aStart) && bStart.isBefore(a.windowEnd!);
    }
    return aStart.isBefore(b.windowEnd!) && bStart.isBefore(a.windowEnd!);
  }

  DailyNext nextDate(
    PhasePlan plan, {
    required CivilDate from,
    required String observedZone,
    Map<DailyIdentity, DailyClockChoice> decisions = const {},
    Map<DailyIdentity, DailyExpectation> historical = const {},
    Iterable<IntervalSource> intervalSources = const [],
    DateTime? now,
  }) {
    if (now != null &&
        plan.end != null &&
        !now.isBefore(plan.end!.exclusiveInstant)) {
      return DailyNext(complete: true, datesExamined: 0);
    }
    DailyExpansion day(CivilDate date) => expand(
      plan,
      from: date,
      toExclusive: date.addDays(1),
      observedZone: observedZone,
      maxDates: 100000,
      maxRows: 100000,
      decisions: decisions,
      historical: historical,
      intervalSources: intervalSources,
      now: now,
    );
    final candidates = <DailyExpectation>[];
    var complete = true, examined = 0;
    DailyCalculationIssue? issue;
    for (final phase in plan.phases) {
      var cursor = from;
      for (var work = 0; work < 4800; work++) {
        final next = daily.nextDate(
          phase,
          from: cursor,
          observedZone: observedZone,
          decisions: decisions,
          historical: historical,
          intervalSources: intervalSources,
          now: now,
        );
        complete = complete && next.complete;
        examined += next.datesExamined;
        issue ??= next.issue;
        final date = next.calendarDate ?? next.next?.identity.originalDate;
        if (date == null) break;
        final resolved = day(date);
        if (!resolved.complete) {
          return DailyNext(
            complete: false,
            datesExamined: examined,
            calendarDate: date,
            issue: resolved.issue,
          );
        }
        final rows = resolved.rows;
        if (rows.isNotEmpty) {
          candidates.addAll(rows);
          break;
        }
        if (plan.end != null &&
            !PauseEligibility(clock)
                .boundary(date, phase.zoneBasis.zoneFor(observedZone))
                .isBefore(plan.end!.exclusiveInstant)) {
          break;
        }
        if (date == CivilDate(9999, 12, 31)) break;
        cursor = date.addDays(1);
        if (work == 4799) {
          complete = false;
          issue ??= DailyCalculationIssue.calendarWorkLimit;
        }
      }
    }
    for (final override in plan.overrides) {
      if ((override.windowTarget?.start ?? override.targetInstant)
          case final instant?) {
        final date = clock.dateAt(
          instant,
          override.windowTarget?.zoneId ?? override.targetZoneId!,
        );
        if (date.compareTo(from) >= 0) {
          final resolved = day(date);
          if (!resolved.complete) {
            return DailyNext(
              complete: false,
              datesExamined: examined,
              calendarDate: date,
              issue: resolved.issue,
            );
          }
          candidates.addAll(resolved.rows);
        }
      }
    }
    candidates.sort(
      (a, b) => (a.effectiveDate ?? a.identity.originalDate).compareTo(
        b.effectiveDate ?? b.identity.originalDate,
      ),
    );
    final row = candidates.firstOrNull;
    return DailyNext(
      next: row,
      calendarDate: row == null
          ? null
          : row.effectiveDate ?? row.identity.originalDate,
      complete: complete,
      datesExamined: examined,
      issue: issue,
    );
  }

  DailyNext nextInstant(
    PhasePlan plan, {
    required DateTime after,
    required String observedZone,
    required int maxDates,
    Map<DailyIdentity, DailyClockChoice> decisions = const {},
    Map<DailyIdentity, DailyExpectation> historical = const {},
    Iterable<IntervalSource> intervalSources = const [],
    DateTime? now,
  }) {
    if (now != null &&
        plan.end != null &&
        !now.isBefore(plan.end!.exclusiveInstant)) {
      return DailyNext(complete: true, datesExamined: 0);
    }
    final candidates = <DailyExpectation>[];
    final review = <DailyExpectation>[];
    var complete = true, examined = 0;
    DailyCalculationIssue? issue;
    for (final phase in plan.phases) {
      var cursor = after;
      var remaining = maxDates;
      for (var i = 0; i < maxDates; i++) {
        final next = daily.nextInstant(
          phase,
          after: cursor,
          observedZone: observedZone,
          maxDates: remaining,
          decisions: decisions,
          historical: historical,
          intervalSources: intervalSources,
          now: now,
        );
        review.addAll(next.needsReview);
        complete = complete && next.complete;
        examined += next.datesExamined;
        issue ??= next.issue;
        final row = next.next;
        if (row == null) break;
        if (!plan.overrides.any((o) => o.identity == row.identity) &&
            _eligible(plan, row, observedZone)) {
          candidates.add(row);
          break;
        }
        if (plan.end != null &&
            !row.instant!.isBefore(plan.end!.exclusiveInstant)) {
          break;
        }
        cursor = row.instant!;
        remaining -= next.datesExamined > 0 ? next.datesExamined : 1;
        if (remaining <= 0) {
          complete = false;
          issue ??= DailyCalculationIssue.calendarWorkLimit;
          break;
        }
      }
    }
    for (final override in plan.overrides) {
      final phase = [
        ...plan.phases,
        ...plan.originPhases,
      ].singleWhere((p) => p.versionId == override.versionId);
      final originals = daily
          .resolveDate(
            _origin(phase),
            override.identity.originalDate,
            observedZone: observedZone,
            decisions: decisions,
            historical: historical,
            intervalSources: intervalSources,
            now: now,
          )
          .where((r) => r.identity == override.identity)
          .toList();
      if (originals.length != 1) {
        return DailyNext(
          complete: false,
          datesExamined: examined,
          issue: DailyCalculationIssue.phaseOriginUnavailable,
        );
      }
      final original = originals.single;
      if ((override.targetInstant != null && original.instant == null) ||
          (override.windowTarget != null &&
              (original.windowStart == null || original.windowEnd == null))) {
        return DailyNext(
          complete: false,
          datesExamined: examined,
          issue: DailyCalculationIssue.phaseClockUnresolved,
        );
      }
      final row = _override(original, override);
      if (row.instant != null &&
          row.instant!.isAfter(after) &&
          _eligible(plan, original, observedZone, origin: true) &&
          _eligible(plan, row, observedZone)) {
        candidates.add(row);
      }
    }
    candidates.sort((a, b) => a.instant!.compareTo(b.instant!));
    return DailyNext(
      next: candidates.firstOrNull,
      complete: complete,
      datesExamined: examined,
      needsReview: review,
      issue: issue,
    );
  }
}
