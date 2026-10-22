import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_lock.dart';
import '../../app/storage.dart';
import '../../data/record_store.dart';

/// Every representable civil day in [month], from the first to the last.
///
/// [CivilDate] accepts years 1 through 9999, so the month length comes from
/// the calendar rather than a fixed 28 to 31 range. The page asks for the
/// browsed month only; the 42-cell surrounding-month grid is never aggregated.
List<CivilDate> routineActivityMonthDates(CivilDate month) {
  final days = DateTime.utc(month.year, month.month + 1, 0).day;
  return [
    for (var day = 1; day <= days; day++)
      CivilDate(month.year, month.month, day),
  ];
}

/// One immutable request for the browsed month and its current History query.
final class RoutineActivityRequest {
  RoutineActivityRequest({required this.query, required CivilDate month})
    : month = CivilDate(month.year, month.month, 1);

  final TimelineQuery query;

  /// First day of the browsed month.
  final CivilDate month;

  List<CivilDate> get dates => routineActivityMonthDates(month);

  @override
  bool operator ==(Object other) =>
      other is RoutineActivityRequest &&
      other.month == month &&
      other.query.identity == query.identity;

  @override
  int get hashCode => Object.hash(month, query.identity);
}

/// Exact factual activity in one browsed month under one History query.
///
/// [recordedDays] counts days with at least one current non-void recorded
/// entry. [recordedEntries], [skippedEntries] and [voidedEntries] are entry
/// counts, not doses: a combined entry stays one entry, matching the calendar
/// cells. There is deliberately no adherence percentage, streak, planned
/// denominator or timing judgement here.
final class RoutineActivitySummary {
  const RoutineActivitySummary({
    required this.month,
    required this.queryIdentity,
    required this.generation,
    required this.status,
    required this.recordedDays,
    required this.recordedEntries,
    required this.skippedEntries,
    required this.voidedEntries,
  });

  final CivilDate month;
  final String queryIdentity;
  final String generation;
  final TimelineStatus status;
  final int recordedDays;
  final int recordedEntries;
  final int skippedEntries;
  final int voidedEntries;

  bool get showsRecorded =>
      status == TimelineStatus.all || status == TimelineStatus.recorded;

  bool get showsSkipped =>
      status == TimelineStatus.all || status == TimelineStatus.skipped;

  bool get showsVoided =>
      status == TimelineStatus.all || status == TimelineStatus.voided;

  int get totalEntries => recordedEntries + skippedEntries + voidedEntries;

  bool get hasEntries => totalEntries > 0;
}

/// Aggregates the exact calendar cells for [request]'s representable month.
///
/// Cells outside the month are ignored even when a caller passes the wider
/// 42-cell grid. [routineActivityFor] adds the query and dataset generation
/// fences used by the live provider; this function stays independently
/// testable as a pure count.
RoutineActivitySummary routineActivitySummary({
  required HistoryCalendar calendar,
  required RoutineActivityRequest request,
}) {
  var recordedDays = 0;
  var recordedEntries = 0;
  var skippedEntries = 0;
  var voidedEntries = 0;
  for (final cell in calendar.cells) {
    if (cell.date.year != request.month.year ||
        cell.date.month != request.month.month) {
      continue;
    }
    if (cell.recorded > 0) recordedDays++;
    recordedEntries += cell.recorded;
    skippedEntries += cell.skipped;
    voidedEntries += cell.voided;
  }
  return RoutineActivitySummary(
    month: request.month,
    queryIdentity: calendar.queryIdentity,
    generation: calendar.generation,
    status: request.query.filter.status,
    recordedDays: recordedDays,
    recordedEntries: recordedEntries,
    skippedEntries: skippedEntries,
    voidedEntries: voidedEntries,
  );
}

/// Returns the summary only when it still belongs to [request]'s query and
/// [generation]. A late read from a replaced dataset or an old filter is
/// dropped instead of being shown as the current month.
RoutineActivitySummary? routineActivityFor({
  required HistoryCalendar calendar,
  required RoutineActivityRequest request,
  required String generation,
}) {
  if (calendar.queryIdentity != request.query.identity ||
      calendar.generation != generation) {
    return null;
  }
  return routineActivitySummary(calendar: calendar, request: request);
}

/// Current dataset generation, or null while the store is still opening.
///
/// The monthly summary keeps this fence next to the query identity so a value
/// retained across a restore or database replacement is never shown as the
/// current month.
final routineActivityGenerationProvider = Provider<String?>((ref) {
  final store = ref.watch(recordStoreProvider);
  return store.isLoading || store.hasError ? null : store.value?.generation;
});

/// The browsed month's exact counts, refreshed by the existing store watch.
///
/// The stream follows record, correction, void, Undo and skip changes through
/// [RecordStore.watchCalendar]. Every event is fenced against the query that
/// owns this provider instance and the current dataset generation, so a late
/// completion from an earlier filter, zone or restore never reaches the UI.
/// A locked app yields no summary at all.
final routineActivityProvider = StreamProvider.autoDispose
    .family<RoutineActivitySummary?, RoutineActivityRequest>(
      retry: (_, _) => null,
      (ref, request) async* {
        if (ref.watch(appLockProvider.select((state) => state.locked))) {
          yield null;
          return;
        }
        final store = await ref.watch(recordStoreProvider.future);
        await for (final calendar in store.watchCalendar(
          request.query,
          dates: request.dates,
        )) {
          if (!ref.mounted) return;
          final snapshot = ref.read(recordStoreProvider);
          if (!snapshot.hasValue || snapshot.isLoading || snapshot.hasError) {
            continue;
          }
          final summary = routineActivityFor(
            calendar: calendar,
            request: request,
            generation: snapshot.requireValue.generation,
          );
          if (summary != null) yield summary;
        }
      },
    );
