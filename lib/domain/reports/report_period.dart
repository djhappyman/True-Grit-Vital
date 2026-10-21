import '../scheduling/daily_plan.dart';

enum ReportPeriod { thirtyDays, ninetyDays, year }

/// Inclusive civil days, with the exclusive end used by report selection.
({CivilDate from, CivilDate before}) reportPeriodDates(
  CivilDate today,
  ReportPeriod period,
) {
  if (period == ReportPeriod.year) {
    return (from: CivilDate(today.year, 1, 1), before: today.addDays(1));
  }
  final start = DateTime.utc(
    today.year,
    today.month,
    today.day,
  ).subtract(Duration(days: period == ReportPeriod.thirtyDays ? 29 : 89));
  return (
    from: start.year < 1 ? CivilDate(1, 1, 1) : CivilDate.fromDateTime(start),
    before: today.addDays(1),
  );
}
