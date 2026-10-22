import '../../domain/events/events.dart';
import '../../domain/history/display_time.dart';
import '../../domain/reports/report_event.dart' show eventSelectionCovers;
import '../../domain/reports/report_selection.dart';
import '../../domain/scheduling/daily_plan.dart';
import '../../domain/scheduling/iana_clock.dart';

/// Canonical Reports entry point. The report editor remains the only screen
/// that chooses or generates a report.
const eventReportsLocation = '/reports';

/// A report window derived from one event's existing recorded boundaries.
///
/// Start uses the actual start when recorded, otherwise the planned start.
/// End uses the actual end, or the completion instant when the event is
/// completed. A planned end is never treated as an actual end.
sealed class EventReportPlan {
  const EventReportPlan();
}

final class EventReportReady extends EventReportPlan {
  const EventReportReady({
    required this.fromDate,
    required this.throughDate,
    required this.ongoing,
  });
  final CivilDate fromDate, throughDate;

  /// True when the event has no recorded end yet. The report window ends at
  /// the current display day, not at an invented event end.
  final bool ongoing;

  CivilDate get beforeDate => throughDate.addDays(1);
}

enum EventReportBlock { startUnavailable, endUnavailable, datesUnavailable }

final class EventReportBlocked extends EventReportPlan {
  const EventReportBlocked(this.reason);
  final EventReportBlock reason;
}

/// Builds one reviewable report window for [event].
///
/// Date-only ends are inclusive and become the next display-zone midnight
/// through the editor's half-open selection. Exact boundaries stay exact.
/// Missing, partial, ambiguous or unavailable boundaries are reported instead
/// of being replaced with guessed dates.
EventReportPlan eventReportPlan(
  EventRecord event, {
  required String displayZone,
  required DateTime now,
}) {
  if (!_zoneAvailable(event.zoneId) || !_zoneAvailable(displayZone)) {
    return const EventReportBlocked(EventReportBlock.datesUnavailable);
  }
  final display = DisplayTime();
  final startDate = event.actualStart ?? event.plannedStart;
  final start = _boundaryInstant(startDate, event.zoneId);
  final from = _displayDate(display, start, displayZone);
  if (from == null) {
    return const EventReportBlocked(EventReportBlock.startUnavailable);
  }

  final endDate = event.actualEnd;
  final end =
      _boundaryInstant(endDate, event.zoneId, endOfDay: true) ??
      event.completedAt;
  CivilDate through;
  var ongoing = false;
  if (end == null) {
    if (event.completed) {
      return const EventReportBlocked(EventReportBlock.endUnavailable);
    }
    ongoing = true;
    final today = _displayDate(display, now.toUtc(), displayZone);
    if (today == null) {
      return const EventReportBlocked(EventReportBlock.datesUnavailable);
    }
    through = today.compareTo(from) < 0 ? from : today;
  } else {
    var lastDate = _displayDate(display, end, displayZone);
    if (lastDate == null) {
      return const EventReportBlocked(EventReportBlock.datesUnavailable);
    }
    if (endDate?.precision == EventDatePrecision.day) {
      final bounds = display.dayBounds(lastDate, displayZone);
      if (bounds.zoneFallback) {
        return const EventReportBlocked(EventReportBlock.datesUnavailable);
      }
      if (bounds.start == end) lastDate = lastDate.addDays(-1);
    }
    through = lastDate;
  }
  if (through.compareTo(from) < 0) {
    return const EventReportBlocked(EventReportBlock.datesUnavailable);
  }
  return EventReportReady(
    fromDate: from,
    throughDate: through,
    ongoing: ongoing,
  );
}

/// The editor selection for a ready event plan. This never opts private
/// context in; the editor's existing toggles remain authoritative.
ReportSelection eventReportSelection(
  EventRecord event,
  EventReportReady plan, {
  required String displayZone,
}) => ReportSelection(
  template: ReportTemplateId.r03EventReview,
  personId: event.personId,
  fromDate: plan.fromDate,
  beforeDate: plan.beforeDate,
  displayZone: displayZone,
  eventId: event.id,
);

/// Canonical editor location. The return path makes Back resolve to the same
/// event after a direct link as well as a pushed route.
String eventReportLocation({
  required String eventId,
  required CivilDate fromDate,
  required CivilDate beforeDate,
  required String returnLocation,
}) {
  final query = Uri(
    queryParameters: {
      'event': eventId,
      'template': 'event',
      'from': fromDate.toString(),
      'before': beforeDate.toString(),
      'return': returnLocation,
    },
  ).query;
  return '$eventReportsLocation?$query';
}

/// The existing editor guidance for a selected event. Missing boundaries keep
/// the entered dates rather than completing the event for the person.
final class EventReportRange {
  const EventReportRange({
    required this.covers,
    required this.fromDate,
    required this.throughDate,
    required this.startKnown,
    required this.endKnown,
  });
  final bool covers;
  final CivilDate fromDate, throughDate;
  final bool startKnown, endKnown;
}

EventReportRange eventReportRange(
  EventRecord event,
  ReportSelection selection,
) {
  final display = DisplayTime();
  CivilDate? displayDate(DateTime? instant) => instant == null
      ? null
      : display.instant(instant, selection.displayZone).civilDate;
  final start = displayDate(
    _boundaryInstant(event.actualStart ?? event.plannedStart, event.zoneId),
  );
  final endDate = event.actualEnd;
  final endInstant =
      _boundaryInstant(endDate, event.zoneId, endOfDay: true) ??
      event.completedAt;
  var end = displayDate(endInstant);
  if (end != null &&
      endDate?.precision == EventDatePrecision.day &&
      display.dayBounds(end, selection.displayZone).start == endInstant) {
    // A final day includes that whole day. The exclusive boundary belongs to
    // the next day, so the last included report date is the day before it.
    end = end.addDays(-1);
  }
  var from = start ?? selection.fromDate;
  var through = end ?? selection.beforeDate.addDays(-1);
  if (end != null && end.compareTo(from) < 0) from = end;
  if (start != null && through.compareTo(start) < 0) through = start;
  return EventReportRange(
    covers: eventSelectionCovers(event, selection),
    fromDate: from,
    throughDate: through,
    startKnown: start != null,
    endKnown: end != null,
  );
}

bool _zoneAvailable(String zoneId) {
  if (zoneId.isEmpty) return false;
  try {
    IanaClock().validateZone(zoneId);
    return true;
  } catch (_) {
    return false;
  }
}

CivilDate? _displayDate(DisplayTime display, DateTime? instant, String zone) {
  if (instant == null) return null;
  final shown = display.instant(instant, zone);
  return shown.zoneFallback ? null : shown.civilDate;
}

DateTime? _boundaryInstant(
  EventDate? date,
  String zone, {
  bool endOfDay = false,
}) {
  try {
    switch (date?.precision) {
      case EventDatePrecision.exact:
        return DateTime.parse(date!.value!).toUtc();
      case EventDatePrecision.day:
        final day = CivilDate.parse(date!.value!);
        final bounds = DisplayTime().dayBounds(
          endOfDay ? day.addDays(1) : day,
          zone,
        );
        return bounds.zoneFallback ? null : bounds.start;
      default:
        return null;
    }
  } catch (_) {
    return null;
  }
}
