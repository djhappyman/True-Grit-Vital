import '../../domain/history/display_time.dart';
import '../../domain/scheduling/daily_plan.dart';

/// A strictly ordered half-open civil range, with a representable through day.
final class ReportDateRange {
  const ReportDateRange._(this.from, this.before);
  final CivilDate from, before;
  CivilDate get through => before.addDays(-1);
}

/// Parses a civil date without normalising impossible calendar components.
CivilDate? parseReportDate(String text) {
  try {
    return CivilDate.parse(text);
  } catch (_) {
    return null;
  }
}

ReportDateRange? _range(CivilDate? from, CivilDate? before) {
  if (from == null || before == null || before.compareTo(from) <= 0) {
    return null;
  }
  return ReportDateRange._(from, before);
}

/// Builds a range from explicit link dates or the existing display-day defaults.
///
/// Explicit link dates must be valid even when the other edge is omitted.
/// Only absent edges use the current display year's start or tomorrow. No UTC
/// or device-local date is substituted when the display projection is unavailable.
ReportDateRange? reportSeedRange({
  required DateTime now,
  required String displayZone,
  String? from,
  String? before,
}) {
  try {
    final start = from == null ? null : parseReportDate(from);
    final end = before == null ? null : parseReportDate(before);
    if ((from != null && start == null) || (before != null && end == null)) {
      return null;
    }
    final shown = DisplayTime().instant(now.toUtc(), displayZone);
    if (shown.zoneFallback) return null;
    final today = shown.civilDate;
    return _range(
      start ?? CivilDate(today.year, 1, 1),
      end ?? today.addDays(1),
    );
  } catch (_) {
    return null;
  }
}

/// Builds a range including the manual through day.
///
/// Overflow beyond year 9999 fails.
ReportDateRange? reportThroughRange(String from, String through) {
  try {
    final start = parseReportDate(from.trim());
    final end = parseReportDate(through.trim());
    return _range(start, end?.addDays(1));
  } catch (_) {
    return null;
  }
}
