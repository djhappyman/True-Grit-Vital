import 'daily_plan.dart' show CivilDate;

/// Date selection is independent of wall-clock conversion and effective bounds.
sealed class CalendarPattern {
  const CalendarPattern();
}

final class EveryDay extends CalendarPattern {
  const EveryDay();
}

List<int> _weekdays(Iterable<int> values) {
  final result = values.toSet().toList()..sort();
  if (result.isEmpty || result.any((day) => day < 1 || day > 7)) {
    throw ArgumentError('invalid_calendar_weekdays');
  }
  return List.unmodifiable(result);
}

void _interval(int value) {
  // Larger values cannot select a second date in the supported civil domain.
  // Keeping arithmetic within the civil domain also prevents integer overflow.
  if (value <= 0 || value > 3652059) {
    throw ArgumentError('invalid_calendar_interval');
  }
}

final class SelectedWeekdays extends CalendarPattern {
  SelectedWeekdays(Iterable<int> weekdays) : weekdays = _weekdays(weekdays);
  final List<int> weekdays;
}

final class EveryNDays extends CalendarPattern {
  EveryNDays({required this.anchor, required this.interval}) {
    _interval(interval);
  }
  final CivilDate anchor;
  final int interval;
}

final class EveryNWeeks extends CalendarPattern {
  EveryNWeeks({
    required this.anchorWeekStart,
    required this.interval,
    required Iterable<int> weekdays,
  }) : weekdays = _weekdays(weekdays) {
    _interval(interval);
  }
  final CivilDate anchorWeekStart;
  final int interval;
  final List<int> weekdays;
}

enum MissingDatePolicy { omit, lastValid }

sealed class MonthSelector {
  const MonthSelector();
}

final class DayOfMonth extends MonthSelector {
  DayOfMonth(this.day, {this.missingDatePolicy}) {
    if (day < 1 || day > 31 || day > 28 && missingDatePolicy == null) {
      throw ArgumentError('invalid_month_day_or_missing_policy');
    }
  }
  final int day;
  final MissingDatePolicy? missingDatePolicy;
}

final class OrdinalWeekday extends MonthSelector {
  OrdinalWeekday(this.ordinal, this.weekday, {this.missingDatePolicy}) {
    if (ordinal < 1 ||
        ordinal > 5 ||
        weekday < 1 ||
        weekday > 7 ||
        ordinal == 5 && missingDatePolicy == null) {
      throw ArgumentError('invalid_month_weekday_or_missing_policy');
    }
  }
  final int ordinal, weekday;
  final MissingDatePolicy? missingDatePolicy;
}

final class LastWeekday extends MonthSelector {
  LastWeekday(this.weekday) {
    if (weekday < 1 || weekday > 7) throw ArgumentError('invalid_weekday');
  }
  final int weekday;
}

final class EveryNMonths extends CalendarPattern {
  EveryNMonths({
    required this.anchorMonth,
    required this.interval,
    required this.selector,
  }) {
    _interval(interval);
  }
  final CivilDate anchorMonth;
  final int interval;
  final MonthSelector selector;
}

/// Explicitly retained unsupported composition; it never becomes daily timing.
final class UnsupportedCalendarPattern extends CalendarPattern {
  const UnsupportedCalendarPattern(this.reason);
  final String reason;
}

enum CalendarIssue { workLimit, unsupportedComposition, calendarRangeLimit }

final class CalendarResult {
  const CalendarResult({
    this.date,
    required this.complete,
    required this.candidatesExamined,
    this.issue,
  });
  final CivilDate? date;
  final bool complete;
  final int candidatesExamined;
  final CalendarIssue? issue;
}

/// Jumps recurrence ordinals; work depends on selected candidates, not age.
final class CalendarSelector {
  const CalendarSelector();
  static final _last = CivilDate(9999, 12, 31);
  static int _days(CivilDate date) =>
      date.calendarValue.millisecondsSinceEpoch ~/ Duration.millisecondsPerDay;
  static int _month(CivilDate date) => (date.year - 1) * 12 + date.month - 1;

  bool includes(CalendarPattern pattern, CivilDate date) =>
      onOrAfter(pattern, date).date == date;

  CalendarResult onOrAfter(
    CalendarPattern pattern,
    CivilDate from, {
    CivilDate? endExclusive,
    int maxCandidates = 4800,
  }) {
    if (maxCandidates < 1 || maxCandidates > 100000) {
      throw ArgumentError('invalid_calendar_budget');
    }
    CalendarResult found(CivilDate date, int work) => CalendarResult(
      date: endExclusive != null && date.compareTo(endExclusive) >= 0
          ? null
          : date,
      complete: true,
      candidatesExamined: work,
    );
    CalendarResult exhausted(int work) => CalendarResult(
      complete: endExclusive != null,
      candidatesExamined: work,
      issue: endExclusive == null ? CalendarIssue.calendarRangeLimit : null,
    );
    CivilDate? advance(CivilDate base, int delta) {
      if (delta > _days(_last) - _days(base)) return null;
      return base.addDays(delta);
    }

    if (endExclusive != null && from.compareTo(endExclusive) >= 0) {
      return const CalendarResult(complete: true, candidatesExamined: 0);
    }
    switch (pattern) {
      case UnsupportedCalendarPattern():
        return const CalendarResult(
          complete: false,
          candidatesExamined: 0,
          issue: CalendarIssue.unsupportedComposition,
        );
      case EveryDay():
        return found(from, 1);
      case SelectedWeekdays(:final weekdays):
        final weekday = from.calendarValue.weekday;
        final offsets = weekdays.map((day) => (day - weekday + 7) % 7);
        final delta = offsets.reduce((a, b) => a < b ? a : b);
        final date = advance(from, delta);
        return date == null ? exhausted(1) : found(date, 1);
      case EveryNDays(:final anchor, :final interval):
        final delta = _days(from) - _days(anchor);
        final ordinal = delta <= 0 ? 0 : (delta + interval - 1) ~/ interval;
        final date = advance(anchor, ordinal * interval);
        return date == null ? exhausted(1) : found(date, 1);
      case EveryNWeeks(
        :final anchorWeekStart,
        :final interval,
        :final weekdays,
      ):
        final delta = _days(from) - _days(anchorWeekStart);
        final stride = interval * 7;
        var cycle = delta <= 0 ? 0 : delta ~/ stride;
        final offsets =
            weekdays
                .map(
                  (day) =>
                      (day - anchorWeekStart.calendarValue.weekday + 7) % 7,
                )
                .toList()
              ..sort();
        for (var attempt = 0; attempt < 2; attempt++, cycle++) {
          for (final offset in offsets) {
            final distance = cycle * stride + offset;
            if (distance < delta) continue;
            final date = advance(anchorWeekStart, distance);
            return date == null ? exhausted(1) : found(date, 1);
          }
        }
        return exhausted(1);
      case EveryNMonths(:final anchorMonth, :final interval, :final selector):
        final first = _month(anchorMonth);
        final delta = _month(from) - first;
        var ordinal = delta <= 0 ? 0 : (delta + interval - 1) ~/ interval;
        for (var work = 1; work <= maxCandidates; work++, ordinal++) {
          final index = first + ordinal * interval;
          if (index >= 9999 * 12) return exhausted(work);
          final year = index ~/ 12 + 1, month = index % 12 + 1;
          final monthStart = CivilDate(year, month, 1);
          if (endExclusive != null && monthStart.compareTo(endExclusive) >= 0) {
            return CalendarResult(complete: true, candidatesExamined: work);
          }
          final day = _selectedDay(year, month, selector);
          if (day == null) continue;
          final date = CivilDate(year, month, day);
          if (date.compareTo(from) >= 0) return found(date, work);
        }
        return CalendarResult(
          complete: false,
          candidatesExamined: maxCandidates,
          issue: CalendarIssue.workLimit,
        );
    }
  }

  int? _selectedDay(int year, int month, MonthSelector selector) {
    final last = DateTime.utc(year, month + 1, 0).day;
    int lastWeekday(int weekday) =>
        last - (DateTime.utc(year, month, last).weekday - weekday + 7) % 7;
    return switch (selector) {
      DayOfMonth(:final day, :final missingDatePolicy) =>
        day <= last
            ? day
            : missingDatePolicy == MissingDatePolicy.lastValid
            ? last
            : null,
      LastWeekday(:final weekday) => lastWeekday(weekday),
      OrdinalWeekday(
        :final ordinal,
        :final weekday,
        :final missingDatePolicy,
      ) =>
        () {
          final day =
              1 +
              (weekday - DateTime.utc(year, month, 1).weekday + 7) % 7 +
              (ordinal - 1) * 7;
          return day <= last
              ? day
              : missingDatePolicy == MissingDatePolicy.lastValid
              ? lastWeekday(weekday)
              : null;
        }(),
    };
  }
}
