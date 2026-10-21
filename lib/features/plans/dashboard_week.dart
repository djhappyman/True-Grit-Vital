import '../../domain/scheduling/daily_plan.dart' show AsNeeded, CivilDate;
import '../../domain/scheduling/stored_daily.dart';

/// First civil date of the Monday-based week containing [day].
///
/// Civil arithmetic is used deliberately: a week is seven named dates, not a
/// fixed number of hours, so a daylight-saving change inside the week never
/// moves its boundary or changes which dates it contains.
CivilDate dashboardWeekStart(CivilDate day) =>
    day.addDays(DateTime.monday - day.calendarValue.weekday);

/// The seven civil dates of the week beginning on [start].
List<CivilDate> dashboardWeekDays(CivilDate start) => List.unmodifiable([
  for (var index = 0; index < 7; index++) start.addDays(index),
]);

/// Factual planned, recorded and skipped totals over one week.
///
/// [complete] is false when the query hit a calculation or row limit, a row's
/// action history is only partly loaded, or the observed zone prevented a
/// calculation. Callers must not present a whole-week ratio in that state.
final class DashboardWeekSummary {
  const DashboardWeekSummary({
    required this.planned,
    required this.recorded,
    required this.skipped,
    required this.unresolved,
    required this.complete,
  });
  final int planned, recorded, skipped, unresolved;
  final bool complete;

  bool get hasPlans => planned > 0;
}

DashboardWeekSummary dashboardWeekSummary(DailyRows result) {
  var planned = 0, recorded = 0, skipped = 0, unresolved = 0;
  for (final row in result.rows) {
    var remaining = row.plannedCount - row.takenCount - row.skippedCount;
    if (remaining < 0) remaining = 0;
    planned += row.plannedCount;
    recorded += row.takenCount;
    skipped += row.skippedCount;
    unresolved += remaining;
  }
  return DashboardWeekSummary(
    planned: planned,
    recorded: recorded,
    skipped: skipped,
    unresolved: unresolved,
    complete:
        result.complete &&
        result.issue == null &&
        result.rows.every((row) => row.actionsComplete),
  );
}

/// The whole saved plan collection used by quick-record configuration.
///
/// [complete] is false when the paging cap was reached, so the interface never
/// presents a partial page as the complete collection.
final class DashboardPlanCollection {
  const DashboardPlanCollection({required this.plans, required this.complete});
  final List<SavedDailyPlan> plans;
  final bool complete;

  List<SavedDailyPlan> get asNeeded => List.unmodifiable([
    for (final plan in plans)
      if (plan.plan.timing is AsNeeded) plan,
  ]);
}

/// Saved favourite identities resolved against the current as-needed plans.
///
/// Order follows the saved identities. Plans that changed away from as-needed
/// or no longer exist are counted as unavailable instead of being shown as a
/// working shortcut or silently replaced by another plan.
final class DashboardFavouriteSelection {
  const DashboardFavouriteSelection({
    required this.plans,
    required this.unavailable,
  });
  final List<SavedDailyPlan> plans;
  final int unavailable;
}

DashboardFavouriteSelection dashboardFavouriteSelection(
  Iterable<String> savedIds,
  Iterable<SavedDailyPlan> plans,
) {
  final available = {
    for (final plan in plans)
      if (plan.plan.timing is AsNeeded) plan.plan.planId: plan,
  };
  final seen = <String>{};
  final resolved = <SavedDailyPlan>[];
  var unavailable = 0;
  for (final id in savedIds) {
    if (!seen.add(id)) continue;
    final plan = available[id];
    if (plan == null) {
      unavailable++;
    } else {
      resolved.add(plan);
    }
  }
  return DashboardFavouriteSelection(
    plans: List.unmodifiable(resolved),
    unavailable: unavailable,
  );
}
