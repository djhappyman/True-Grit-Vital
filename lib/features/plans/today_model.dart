import '../../domain/scheduling/daily_plan.dart';
import '../../domain/scheduling/stored_daily.dart';

/// The display wall time that groups one row with other rows of the same
/// expected time. The key also carries the row zone so different zones never
/// fold into one group by coincidence.
final class TodayTimeLabel {
  const TodayTimeLabel({required this.key, required this.title});
  final String key;
  final String title;
}

/// A compact expectation-time group of today's rows.
///
/// Groups are an expectation projection only; they never claim a dose was
/// taken. Timed groups follow their expected start in order, the untimed
/// bucket comes last, and every row keeps its identity inside its group so an
/// action never moves its Undo under a different card.
final class TodayGroup {
  TodayGroup({
    required this.key,
    required this.title,
    required List<DailyRow> rows,
    required this.untimed,
  }) : rows = List.unmodifiable(rows);
  final String key;
  final String title;
  final List<DailyRow> rows;
  final bool untimed;
}

/// The expected start of one row: the window start when a window exists,
/// otherwise the exact expectation instant. Null identifies the untimed count
/// bucket, which has no expected moment on this date.
DateTime? todayRowStart(DailyRow row) =>
    row.expectation.windowStart ?? row.expectation.instant;

/// The same expectation start for next-plan summaries. Untimed plans offer no
/// start until the resolver provides one.
DateTime? todayExpectationStart(DailyExpectation expectation) =>
    expectation.windowStart ?? expectation.instant;

/// Groups rows by their expected display time inside each row's own zone.
///
/// Rows without an expected start share one [TodayGroup] titled with the
/// caller's untimed label. Rows are grouped by the shown wall time within
/// their own plan zone; two plans with the same wall time share the group, and
/// plans in different zones keep separate groups. Ties keep the feed order.
List<TodayGroup> groupTodayRows(
  List<DailyRow> rows, {
  required TodayTimeLabel Function(DailyRow row, DateTime start) timeLabel,
  required String untimedTitle,
}) {
  final untimed = <DailyRow>[];
  final timed = <(DateTime, int, DailyRow)>[];
  for (final (index, row) in rows.indexed) {
    final start = todayRowStart(row);
    if (start == null) {
      untimed.add(row);
    } else {
      timed.add((start, index, row));
    }
  }
  timed.sort((first, second) {
    final order = first.$1.compareTo(second.$1);
    if (order != 0) return order;
    return first.$2.compareTo(second.$2);
  });
  final groups = <TodayGroup>[];
  final times = <String, (String, List<DailyRow>)>{};
  for (final (_, _, row) in timed) {
    final label = timeLabel(row, todayRowStart(row)!);
    times.putIfAbsent(label.key, () => (label.title, <DailyRow>[])).$2.add(row);
  }
  for (final entry in times.entries) {
    final (title, members) = entry.value;
    groups.add(
      TodayGroup(key: entry.key, title: title, rows: members, untimed: false),
    );
  }
  if (untimed.isNotEmpty) {
    groups.add(
      TodayGroup(
        key: 'untimed',
        title: untimedTitle,
        rows: untimed,
        untimed: true,
      ),
    );
  }
  return groups;
}

/// Separate day counts over the shown rows. Recorded and skipped stay
/// distinct; the summary is a planning projection, not proof of use.
final class TodayUseCount {
  const TodayUseCount({
    required this.planned,
    required this.recorded,
    required this.skipped,
    required this.unresolved,
  });
  final int planned, recorded, skipped;

  /// Planned opportunities without a decision yet.
  final int unresolved;
}

TodayUseCount todayUseCount(List<DailyRow> rows) {
  var planned = 0, recorded = 0, skipped = 0, unresolved = 0;
  for (final row in rows) {
    final expected = row.plannedCount;
    planned += expected;
    recorded += row.takenCount;
    skipped += row.skippedCount;
    unresolved += switch (expected - row.takenCount - row.skippedCount) {
      > 0 => expected - row.takenCount - row.skippedCount,
      _ => 0,
    };
  }
  return TodayUseCount(
    planned: planned,
    recorded: recorded,
    skipped: skipped,
    unresolved: unresolved,
  );
}

/// The earliest pending timed row with its start; the hero's countdown source.
(DailyRow, DateTime)? todayNextPendingRow(List<DailyRow> rows) {
  (DailyRow, DateTime)? pick;
  for (final row in rows) {
    if (row.isResolved) continue;
    final start = todayRowStart(row);
    if (start == null) continue;
    if (pick == null || start.isBefore(pick.$2)) pick = (row, start);
  }
  return pick;
}

/// Whether any pending row stays untimed, so no countdown can be claimed.
bool todayHasPendingUntimed(List<DailyRow> rows) =>
    rows.any((row) => !row.isResolved && todayRowStart(row) == null);

/// The next-plan summary with the earliest future start, for its display zone.
(DailyPlanNextRow, DateTime)? todayNextFutureRow(
  Iterable<DailyPlanNextRow> summaries,
  DateTime now,
) {
  (DailyPlanNextRow, DateTime)? pick;
  for (final summary in summaries) {
    final next = summary.result.next;
    final start = next == null ? null : todayExpectationStart(next);
    if (start == null || !start.isAfter(now)) continue;
    if (pick == null || start.isBefore(pick.$2)) pick = (summary, start);
  }
  return pick;
}

/// The visible minute countdown for [target], or null when no honest minute
/// countdown exists: the start passed, less than a minute away, or it is an
/// hour away or more. The widget states the under-minute case itself, so a
/// dose 30 seconds away is never shown as due.
int? todayCountdownMinutes(DateTime now, DateTime target) {
  final remaining = target.difference(now);
  if (remaining <= Duration.zero ||
      remaining < const Duration(minutes: 1) ||
      remaining >= const Duration(hours: 1)) {
    return null;
  }
  // Ceil the remaining time: 95 seconds truthfully reads as 2 minutes, and a
  // whole minute is never understated to zero.
  return (remaining.inMicroseconds / Duration.microsecondsPerMinute).ceil();
}

/// Delay until the shown countdown value changes next, or null when no
/// countdown is shown. One-shot timers mirror the established history page
/// pattern: no periodic frame schedule, and the caller cancels on dispose.
Duration? todayCountdownTick(DateTime now, DateTime target) {
  final remaining = target.difference(now);
  if (remaining <= Duration.zero || remaining >= const Duration(hours: 1)) {
    return null;
  }
  final withinMinute =
      remaining.inMicroseconds % Duration.microsecondsPerMinute;
  return Duration(microseconds: withinMinute + 1000);
}
