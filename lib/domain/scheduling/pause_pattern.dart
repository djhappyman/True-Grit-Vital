import 'daily_plan.dart' show CivilDate;

/// A half-open UTC interval that suppresses plans without recording actual use.
final class PlanPause {
  PlanPause({required this.start, this.resume}) {
    if (!start.isUtc ||
        start.year < 1 ||
        start.year > 9999 ||
        resume != null &&
            (!resume!.isUtc ||
                !resume!.isAfter(start) ||
                resume!.year < 1 ||
                resume!.year > 9999)) {
      throw ArgumentError('invalid_plan_pause');
    }
  }
  final DateTime start;
  final DateTime? resume;

  /// Whether [instant] lies at or after the pause start and before resume.
  bool contains(DateTime instant) =>
      !instant.isBefore(start) && (resume == null || instant.isBefore(resume!));
}

/// Civil active days intersected explicitly with a plan's calendar selection.
///
/// A zero-length break means continuous activity. Elapsed sequences keep their
/// original UTC anchors and ordinals; this selection only filters their dates.
final class OnOffPattern {
  OnOffPattern({
    required this.anchor,
    required this.onDays,
    required this.offDays,
  }) {
    if (onDays <= 0 || offDays < 0 || onDays > 3652059 || offDays > 3652059) {
      throw ArgumentError('invalid_on_off_pattern');
    }
  }
  final CivilDate anchor;
  final int onDays, offDays;

  int _position(CivilDate date) =>
      date.calendarValue.difference(anchor.calendarValue).inDays %
      (onDays + offDays);

  /// Whether [date] is in an active civil block.
  bool includes(CivilDate date) => offDays == 0 || _position(date) < onDays;

  /// Seeks an active date without walking through break days.
  CivilDate? onOrAfter(CivilDate date) {
    if (includes(date)) return date;
    final delta = onDays + offDays - _position(date);
    if (date.calendarValue
                .difference(CivilDate(9999, 12, 31).calendarValue)
                .inDays +
            delta >
        0) {
      return null;
    }
    return date.addDays(delta);
  }
}
