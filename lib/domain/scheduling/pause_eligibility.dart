import 'daily_plan.dart';
import 'iana_clock.dart';

/// A civil-day boundary requiring an explicit supported clock calculation.
final class PauseBoundaryUnavailable implements Exception {
  const PauseBoundaryUnavailable(this.date, this.zoneId);
  final CivilDate date;
  final String zoneId;
}

/// Shared pause eligibility for previews, feed calculations and reminders.
final class PauseEligibility {
  PauseEligibility(this.clock);
  final IanaClock clock;

  /// Returns the merged pause containing [instant], including open pauses.
  PlanPause? containing(DailyPlanVersion plan, DateTime instant) {
    final ordered = plan.pauses.toList()
      ..sort((a, b) => a.start.compareTo(b.start));
    PlanPause? result;
    for (final pause in ordered) {
      if (result == null) {
        if (pause.contains(instant)) result = pause;
        continue;
      }
      if (result.resume == null) break;
      if (pause.start.isAfter(result.resume!)) break;
      if (pause.resume == null || pause.resume!.isAfter(result.resume!)) {
        result = PlanPause(start: result.start, resume: pause.resume);
      }
    }
    return result;
  }

  /// Resolves metadata for eligibility, never a dose time.
  DateTime boundary(CivilDate date, String zoneId) {
    final candidates = clock.candidates(date, WallTime(0, 0), zoneId);
    if (candidates.isEmpty) throw PauseBoundaryUnavailable(date, zoneId);
    return candidates.first;
  }

  /// Returns a pause only when it covers the complete civil-date bucket.
  PlanPause? coveringDate(
    DailyPlanVersion plan,
    CivilDate date,
    String zoneId,
  ) {
    if (plan.pauses.isEmpty) return null;
    final start = boundary(date, zoneId);
    final pause = containing(plan, start);
    if (pause == null) return null;
    if (pause.resume == null) return pause;
    if (date == CivilDate(9999, 12, 31)) {
      throw PauseBoundaryUnavailable(date, zoneId);
    }
    final end = boundary(date.addDays(1), zoneId);
    return !pause.resume!.isBefore(end) ? pause : null;
  }

  /// Whether a date has any eligible time within the version's exact bounds.
  ///
  /// This preserves one untimed bucket on a partially active date. Boundaries
  /// are eligibility metadata and never become planned dose instants.
  bool hasActiveDate(DailyPlanVersion plan, CivilDate date, String zoneId) {
    if (plan.effectiveFrom == null && plan.effectiveUntil == null) {
      return coveringDate(plan, date, zoneId) == null;
    }
    final dayStart = boundary(date, zoneId);
    if (date == CivilDate(9999, 12, 31)) {
      throw PauseBoundaryUnavailable(date, zoneId);
    }
    final dayEnd = boundary(date.addDays(1), zoneId);
    final start =
        plan.effectiveFrom != null && plan.effectiveFrom!.isAfter(dayStart)
        ? plan.effectiveFrom!
        : dayStart;
    final end =
        plan.effectiveUntil != null && plan.effectiveUntil!.isBefore(dayEnd)
        ? plan.effectiveUntil!
        : dayEnd;
    if (!start.isBefore(end)) return false;
    final pause = containing(plan, start);
    return pause == null || pause.resume != null && pause.resume!.isBefore(end);
  }

  /// Selects the intersection without scanning off days or fully paused dates.
  CalendarResult selected(
    DailyPlanVersion plan,
    CivilDate from, {
    String? zoneId,
    CivilDate? endExclusive,
    int maxCandidates = 4800,
  }) {
    var cursor = from.compareTo(plan.start) < 0 ? plan.start : from;
    final end = endExclusive ?? plan.endExclusive;
    if (zoneId != null && plan.effectiveFrom != null) {
      final firstDate = clock.dateAt(plan.effectiveFrom!, zoneId);
      if (cursor.compareTo(firstDate) < 0) cursor = firstDate;
    }
    const selector = CalendarSelector();
    if (maxCandidates < 1 || maxCandidates > 100000) {
      throw ArgumentError('invalid_calendar_budget');
    }
    var work = 0;
    while (work < maxCandidates) {
      final active =
          plan.onOff?.onOrAfter(cursor) ?? (plan.onOff == null ? cursor : null);
      if (active == null) {
        return CalendarResult(
          complete: false,
          candidatesExamined: work,
          issue: CalendarIssue.calendarRangeLimit,
        );
      }
      final candidate = selector.onOrAfter(
        plan.calendar,
        active,
        endExclusive: end,
        maxCandidates: maxCandidates - work,
      );
      work += candidate.candidatesExamined > 0
          ? candidate.candidatesExamined
          : 1;
      final date = candidate.date;
      if (date == null || !candidate.complete) {
        return CalendarResult(
          date: date,
          complete: candidate.complete,
          candidatesExamined: work,
          issue: candidate.issue,
        );
      }
      if (zoneId != null &&
          plan.effectiveUntil != null &&
          date.compareTo(clock.dateAt(plan.effectiveUntil!, zoneId)) > 0) {
        return CalendarResult(complete: true, candidatesExamined: work);
      }
      if (plan.onOff != null && !plan.onOff!.includes(date)) {
        cursor = date;
        continue;
      }
      if (zoneId != null &&
          plan.timing is DailyCount &&
          !hasActiveDate(plan, date, zoneId)) {
        final pause = containing(plan, boundary(date, zoneId));
        if (pause?.resume != null) {
          final resumeDate = clock.dateAt(pause!.resume!, zoneId);
          if (resumeDate.compareTo(date) > 0) {
            cursor = resumeDate;
            continue;
          }
        }
        if (pause != null && pause.resume == null) {
          return CalendarResult(complete: true, candidatesExamined: work);
        }
        if (date == CivilDate(9999, 12, 31)) {
          return CalendarResult(
            complete: false,
            candidatesExamined: work,
            issue: CalendarIssue.calendarRangeLimit,
          );
        }
        cursor = date.addDays(1);
        continue;
      }
      final pause = zoneId == null ? null : coveringDate(plan, date, zoneId);
      if (pause == null) {
        return CalendarResult(
          date: date,
          complete: true,
          candidatesExamined: work,
        );
      }
      if (pause.resume == null) {
        return CalendarResult(complete: true, candidatesExamined: work);
      }
      cursor = clock.dateAt(pause.resume!, zoneId!);
    }
    return CalendarResult(
      complete: false,
      candidatesExamined: maxCandidates,
      issue: CalendarIssue.workLimit,
    );
  }
}
