import '../scheduling/iana_clock.dart';
import 'events.dart';

/// Display-only timing for an event. It never changes membership, plans, stock
/// or doses. Civil dates count calendar days in the saved zone, including the
/// final day. Exact boundaries use completed elapsed and started remaining
/// 24-hour periods.
typedef EventCycleTiming = ({int? elapsed, int? remaining, int? startsIn});

EventCycleTiming cycleTiming(EventRecord event, DateTime now) {
  const unavailable = (elapsed: null, remaining: null, startsIn: null);
  if (event.completed && event.actualEnd == null) return unavailable;
  final clock = IanaClock();
  final startDate = event.actualStart ?? event.plannedStart;
  final endDate = event.actualEnd ?? event.plannedEnd;
  try {
    final start = startDate?.resolve(clock, event.zoneId);
    final end = endDate?.resolve(clock, event.zoneId, inclusiveEnd: true);
    if (startDate != null && start == null || endDate != null && end == null) {
      return unavailable;
    }
    int civilDays(DateTime a, DateTime b) {
      final first = clock.dateAt(a, event.zoneId);
      final last = clock.dateAt(b, event.zoneId);
      return DateTime.utc(
        last.year,
        last.month,
        last.day,
      ).difference(DateTime.utc(first.year, first.month, first.day)).inDays;
    }

    if (start != null && now.isBefore(start)) {
      return (
        elapsed: null,
        remaining: null,
        startsIn: startDate!.precision == EventDatePrecision.day
            ? civilDays(now, start)
            : (start.difference(now).inMicroseconds /
                      Duration.microsecondsPerDay)
                  .ceil(),
      );
    }
    final until = end != null && now.isAfter(end) ? end : now;
    final elapsed = start == null
        ? null
        : startDate!.precision == EventDatePrecision.day
        ? civilDays(start, until)
        : until.difference(start).inDays;
    final remaining = end == null
        ? null
        : !now.isBefore(end)
        ? 0
        : endDate!.precision == EventDatePrecision.day
        ? civilDays(now, end)
        : (end.difference(now).inMicroseconds / Duration.microsecondsPerDay)
              .ceil();
    return (elapsed: elapsed, remaining: remaining, startsIn: null);
  } catch (_) {
    // Partial/unknown boundaries and zones needing review never acquire a date.
    return unavailable;
  }
}

/// The existing Events collection status. Completed wins over every date
/// state. A future resolved start is upcoming; a missing elapsed value means
/// the stored dates need review instead of inventing a phase.
enum EventCollectionPhase { active, upcoming, completed, review }

/// Collection filters mirror [EventCollectionPhase]. They do not add clinical
/// meaning or adherence judgement.
enum EventCollectionFilter { all, active, upcoming, completed, review }

EventCollectionPhase eventCollectionPhase(EventRecord event, DateTime now) {
  if (event.completed) return EventCollectionPhase.completed;
  final timing = cycleTiming(event, now);
  if (timing.startsIn != null) return EventCollectionPhase.upcoming;
  return timing.elapsed == null
      ? EventCollectionPhase.review
      : EventCollectionPhase.active;
}

/// Whole-collection status totals under one instant. Each current event has
/// exactly one phase, so these counts sum to [all].
final class EventCollectionCounts {
  const EventCollectionCounts({
    required this.all,
    required this.active,
    required this.upcoming,
    required this.completed,
    required this.review,
  });
  const EventCollectionCounts.empty()
    : all = 0,
      active = 0,
      upcoming = 0,
      completed = 0,
      review = 0;
  final int all, active, upcoming, completed, review;

  int count(EventCollectionFilter filter) => switch (filter) {
    EventCollectionFilter.all => all,
    EventCollectionFilter.active => active,
    EventCollectionFilter.upcoming => upcoming,
    EventCollectionFilter.completed => completed,
    EventCollectionFilter.review => review,
  };
}

/// One coherent collection snapshot: whole-collection counts plus the
/// deterministic page after filtering. [offset] is the effective page start
/// after clamping a stale page to the current filtered total.
final class EventCollectionSnapshot {
  EventCollectionSnapshot({
    required this.generation,
    required this.asOf,
    required this.filter,
    required this.offset,
    required this.pageSize,
    required Iterable<EventRecord> events,
    required this.counts,
  }) : events = List.unmodifiable(events);
  final String generation;
  final DateTime asOf;
  final EventCollectionFilter filter;
  final int offset, pageSize;
  final List<EventRecord> events;
  final EventCollectionCounts counts;

  int get total => counts.all;
  int get filteredTotal => counts.count(filter);
  bool get hasPrevious => offset > 0;
  bool get hasNext => offset + events.length < filteredTotal;
}
