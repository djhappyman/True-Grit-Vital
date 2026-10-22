import '../../domain/history/display_time.dart';
import '../../domain/scheduling/daily_plan.dart';

/// Compact date ranges shared with the Settings report shortcuts.
enum ExportRangeShortcut { thirtyDays, ninetyDays, year }

/// Why a shortcut cannot give an exact civil-day range.
enum ExportRangeFailure { zoneUnavailable, rangeUnavailable }

final class ExportRangeException implements Exception {
  const ExportRangeException(this.failure);
  final ExportRangeFailure failure;
  @override
  String toString() => 'ExportRangeException($failure)';
}

/// The inclusive [from] day and exclusive [before] day for [shortcut].
///
/// The 30 and 90 day choices include [today]; the year choice starts on
/// 1 January and also includes [today]. Arithmetic is on civil dates, so a
/// daylight-saving transition cannot shorten or lengthen the selected days.
({CivilDate from, CivilDate before}) exportShortcutRange(
  CivilDate today,
  ExportRangeShortcut shortcut,
) {
  final before = _nextDay(today);
  if (shortcut == ExportRangeShortcut.year) {
    return (from: CivilDate(today.year, 1, 1), before: before);
  }
  final span = shortcut == ExportRangeShortcut.thirtyDays ? 29 : 89;
  final start = today.calendarValue.subtract(Duration(days: span));
  if (start.year < 1) {
    throw const ExportRangeException(ExportRangeFailure.rangeUnavailable);
  }
  return (from: CivilDate.fromDateTime(start), before: before);
}

/// Today's civil day in [zoneId], never a substitute UTC day.
///
/// An unavailable zone, an instant outside the verified clock range or a
/// result outside the representable civil dates is a typed failure so the
/// caller can show recovery instead of silently shifting the range.
CivilDate exportCivilToday(DateTime now, String zoneId) {
  if (zoneId.trim().isEmpty) {
    throw const ExportRangeException(ExportRangeFailure.zoneUnavailable);
  }
  try {
    final shown = DisplayTime().instant(now.toUtc(), zoneId);
    if (shown.zoneFallback) {
      throw const ExportRangeException(ExportRangeFailure.zoneUnavailable);
    }
    return shown.civilDate;
  } on ExportRangeException {
    rethrow;
  } on ArgumentError {
    // DisplayTime rejects an instant outside years 1..9999 before resolving a
    // zone. That is an unrepresentable clock, not an unavailable zone.
    throw const ExportRangeException(ExportRangeFailure.rangeUnavailable);
  } catch (_) {
    throw const ExportRangeException(ExportRangeFailure.zoneUnavailable);
  }
}

CivilDate _nextDay(CivilDate today) {
  try {
    return today.addDays(1);
  } on ArgumentError {
    throw const ExportRangeException(ExportRangeFailure.rangeUnavailable);
  }
}
