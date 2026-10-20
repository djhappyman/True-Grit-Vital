import '../events/events.dart';
import '../history/display_time.dart';
import '../history/timeline_entry.dart';
import '../scheduling/daily_plan.dart';
import '../scheduling/iana_clock.dart';
import '../scheduling/stored_daily.dart';
import '../stock/exact_amount.dart';
import 'report_history.dart';
import 'report_model.dart';
import 'report_selection.dart';
import 'report_template_data.dart';

/// Whether an event member has a recorded use period that is still open.
enum ReportUseStatus { ongoing, ended, noPeriod }

/// One event member with its event-scoped totals and separate use state.
final class ReportEventMember {
  ReportEventMember({
    required this.itemId,
    required this.name,
    required this.form,
    required this.type,
    required this.unit,
    required this.administrations,
    required this.useStatus,
    this.total,
    this.volumeUnit,
    this.ingredients = const [],
    this.usePeriodEnd,
    this.limitReached = false,
    this.identityComplete = true,
    Iterable<ReportItemTotal> quantities = const [],
    Iterable<ReportProductTotal> products = const [],
  }) : quantities = List.unmodifiable(quantities),
       products = List.unmodifiable(products) {
    if (itemId.isEmpty || name.trim().isEmpty || administrations < 0) {
      throw const ReportSelectionFailure('report_event_member');
    }
  }
  final String itemId, name, form, type, unit;
  final int administrations;
  final ReportUseStatus useStatus;
  final ExactAmount? total;
  final String? volumeUnit;
  final List<ReportProductIngredientTotal> ingredients;
  final EventDate? usePeriodEnd;
  final bool limitReached, identityComplete;
  final List<ReportItemTotal> quantities;
  final List<ReportProductTotal> products;

  bool get isProduct => volumeUnit != null;
  String get typeLabel => type.trim().isEmpty ? 'Uncategorised' : type;
}

/// Captured R03 body: one recorded event, its members and the recorded use
/// that actually falls inside it.
final class ReportEventData implements ReportTemplateData {
  ReportEventData._({
    required this.eventId,
    required this.name,
    required this.eventType,
    required this.zoneId,
    required this.plannedStart,
    required this.plannedEnd,
    required this.actualStart,
    required this.actualEnd,
    required this.completed,
    required this.completedAt,
    required this.boundsNeedReview,
    required Iterable<ReportEventMember> members,
    required Iterable<ReportLedgerEntry> entries,
    required this.skippedCount,
    required this.notRecordedCount,
    required this.usePeriodsComplete,
    required this.scopeComplete,
  }) : members = List.unmodifiable(members),
       entries = List.unmodifiable(entries);
  factory ReportEventData.build({
    required ReportSnapshot snapshot,
    required EventRecord event,
    Iterable<ReportItemDescriptor> items = const [],
    Iterable<RecordedUsePeriod> usePeriods = const [],
    Iterable<SkippedTimelineEntry> skipped = const [],
    Iterable<DailyRow> unresolved = const [],
    bool usePeriodsComplete = true,
    bool scopeComplete = true,
    int maxEntries = 10000,
  }) {
    final selection = snapshot.selection;
    if (selection.template != ReportTemplateId.r03EventReview) {
      throw const ReportSelectionFailure('report_template_data');
    }
    if (selection.eventId == null || selection.eventId != event.id) {
      throw const ReportSelectionFailure('report_event');
    }
    if (event.personId != selection.personId) {
      throw const ReportSelectionFailure('report_owner');
    }
    if (maxEntries < 1 || maxEntries > 100000) {
      throw const ReportSelectionFailure('report_limit');
    }
    final descriptors = {for (final item in items) item.itemId: item};
    bool selected(String itemId) =>
        selection.itemIds.isEmpty || selection.itemIds.contains(itemId);
    final entries = [
      for (final record in snapshot.records)
        if (selected(record.itemId)) ReportLedgerEntry.fromRecord(record),
    ]..sort((a, b) => a.occurredAt.compareTo(b.occurredAt));
    if (entries.length > maxEntries) {
      throw const ReportSelectionFailure('report_history_limit');
    }
    var skippedCount = 0;
    for (final skip in skipped) {
      if (skip.personId != event.personId) {
        throw const ReportSelectionFailure('report_owner');
      }
      if (selected(skip.itemId)) skippedCount++;
    }
    var notRecordedCount = 0;
    for (final row in unresolved) {
      final expectation = row.expectation;
      if (expectation.identity.personId != event.personId) {
        throw const ReportSelectionFailure('report_owner');
      }
      if (!selected(expectation.itemId)) continue;
      final remaining = row.plannedCount - row.takenCount - row.skippedCount;
      if (remaining <= 0) continue;
      var occurredAt = expectation.instant;
      if (occurredAt == null) {
        final date =
            expectation.effectiveDate ?? expectation.identity.originalDate;
        try {
          occurredAt = DisplayTime().dayBounds(date, expectation.zoneId).start;
        } catch (_) {
          occurredAt = DisplayTime().dayBounds(date, 'UTC').start;
        }
      }
      if (occurredAt.isBefore(snapshot.cutoff.generatedAt)) {
        notRecordedCount += remaining;
      }
    }

    final periodsByItem = <String, List<RecordedUsePeriod>>{};
    for (final period in usePeriods) {
      if (period.personId != event.personId) {
        throw const ReportSelectionFailure('report_owner');
      }
      if (period.kind != UsePeriodKind.use) continue;
      periodsByItem.putIfAbsent(period.itemId, () => []).add(period);
    }

    final itemTotals = <String, List<ReportItemTotal>>{};
    final productTotals = <String, List<ReportProductTotal>>{};
    for (final group in snapshot.totals.groups) {
      for (final item in group.items) {
        itemTotals.putIfAbsent(item.itemId, () => []).add(item);
      }
      for (final product in group.products) {
        productTotals.putIfAbsent(product.itemId, () => []).add(product);
      }
    }

    final members = <ReportEventMember>[];
    final seen = <String>{};
    for (final membership in event.memberships) {
      if (!selected(membership.itemId) || !seen.add(membership.itemId)) {
        continue;
      }
      final descriptor = descriptors[membership.itemId];
      final quantities =
          itemTotals[membership.itemId] ?? const <ReportItemTotal>[];
      final products =
          productTotals[membership.itemId] ?? const <ReportProductTotal>[];
      final item = quantities.length == 1 && products.isEmpty
          ? quantities.single
          : null;
      final product = products.length == 1 && quantities.isEmpty
          ? products.single
          : null;
      final periods = periodsByItem[membership.itemId] ?? const [];
      // Any open use period means the member is still in use, even if a newer
      // dated period was saved later. Never present an open period as stopped.
      final open = periods.where((period) => period.end == null).toList();
      final latest = _latestPeriod(open.isNotEmpty ? open : periods);
      final useStatus = periods.isEmpty
          ? ReportUseStatus.noPeriod
          : open.isNotEmpty
          ? ReportUseStatus.ongoing
          : ReportUseStatus.ended;
      members.add(
        ReportEventMember(
          itemId: membership.itemId,
          name:
              descriptor?.name ??
              products.firstOrNull?.name ??
              quantities.firstOrNull?.name ??
              membership.itemId,
          form:
              descriptor?.form ??
              products.firstOrNull?.form ??
              quantities.firstOrNull?.form ??
              '',
          type: descriptor?.type ?? '',
          unit: descriptor?.unit ?? product?.volumeUnit ?? item?.unit ?? '',
          administrations: entries
              .where((entry) => entry.itemId == membership.itemId)
              .length,
          quantities: quantities,
          products: products,
          useStatus: useStatus,
          total: product?.volume ?? item?.total,
          volumeUnit: product?.volumeUnit,
          ingredients: product?.ingredients ?? const [],
          usePeriodEnd: latest?.end,
          limitReached:
              products.any((p) => p.limitReached) ||
              quantities.any((q) => q.limitReached),
          identityComplete: descriptor != null,
        ),
      );
    }
    members.sort((a, b) {
      final byType = a.typeLabel.toLowerCase().compareTo(
        b.typeLabel.toLowerCase(),
      );
      if (byType != 0) return byType;
      final byName = a.name.toLowerCase().compareTo(b.name.toLowerCase());
      return byName != 0 ? byName : a.itemId.compareTo(b.itemId);
    });

    var boundsNeedReview = false;
    try {
      event.validateBounds(IanaClock());
    } catch (_) {
      boundsNeedReview = true;
    }

    return ReportEventData._(
      eventId: event.id,
      name: event.name,
      eventType: event.eventType,
      zoneId: event.zoneId,
      plannedStart: event.plannedStart,
      plannedEnd: event.plannedEnd,
      actualStart: event.actualStart,
      actualEnd: event.actualEnd,
      completed: event.completed,
      completedAt: event.completedAt,
      boundsNeedReview: boundsNeedReview,
      members: members,
      entries: entries,
      skippedCount: skippedCount,
      notRecordedCount: notRecordedCount,
      usePeriodsComplete: usePeriodsComplete,
      scopeComplete: scopeComplete,
    );
  }

  final String eventId, name, eventType, zoneId;
  final EventDate? plannedStart, plannedEnd, actualStart, actualEnd;
  final bool completed, boundsNeedReview, usePeriodsComplete, scopeComplete;
  final DateTime? completedAt;
  final List<ReportEventMember> members;
  final List<ReportLedgerEntry> entries;
  final int skippedCount, notRecordedCount;

  @override
  ReportTemplateId get template => ReportTemplateId.r03EventReview;

  bool get ongoing => actualEnd == null && !completed;

  /// Recorded end: an explicit actual end, otherwise the completion instant.
  EventDate? get recordedEnd =>
      actualEnd ?? (completedAt == null ? null : EventDate.exact(completedAt!));

  int get administrationCount => entries
      .where((entry) => entry.status != ReportLedgerStatus.skipped)
      .length;
  int get correctedCount => entries
      .where((entry) => entry.status == ReportLedgerStatus.corrected)
      .length;

  Iterable<ReportEventMember> get ongoingMembers =>
      members.where((member) => member.useStatus == ReportUseStatus.ongoing);

  String structuredText(ReportSnapshot snapshot, {required bool use24Hour}) {
    final selection = snapshot.selection;
    final lines = <String>[
      'Event review',
      '',
      'Person: ${snapshot.person.displayName}',
      'Event: $name',
      'Event type: $eventType',
      'Event zone: $zoneId',
      'Planned: ${_dateRange(plannedStart, plannedEnd, zoneId, use24Hour: use24Hour)}',
      'Actual: ${_dateRange(actualStart, recordedEnd, zoneId, use24Hour: use24Hour)}',
      'Event state: ${ongoing ? 'Ongoing' : 'Ended'}',
      if (completedAt != null)
        'Completed: ${formatInstant(completedAt!, selection.displayZone, use24Hour: use24Hour)}',
      'Report period: ${formatCivilDate(selection.fromDate)} to '
          '${formatCivilDate(selection.beforeDate.addDays(-1))}',
      'Generated: ${formatInstant(snapshot.cutoff.generatedAt, selection.displayZone, use24Hour: use24Hour)}',
      'Template: ${selection.template.id} version ${reportTemplateVersion(selection.template)}',
      'Report ID: ${snapshot.artifactId}',
      '',
      'Recorded administrations: ${entries.length}',
      'Corrected: $correctedCount',
      'Skipped: $skippedCount',
      'Not recorded: $notRecordedCount',
      '',
    ];
    if (boundsNeedReview) {
      lines
        ..add(
          'Event dates need review. Some planned or actual bounds could not be resolved in the event zone.',
        )
        ..add('');
    }
    if (!usePeriodsComplete) {
      lines
        ..add(
          'Some use periods could not be listed. Member states may be incomplete.',
        )
        ..add('');
    }
    if (!scopeComplete) {
      lines
        ..add(
          'Some event dates could not be resolved, so skipped and not-recorded counts may be incomplete.',
        )
        ..add('');
    }
    lines
      ..add('Members')
      ..add('');
    for (final member in members) {
      lines.add(
        '${member.typeLabel} · ${member.name} · ${reportEventMemberUse(member)} · ${_useText(member)}',
      );
    }
    lines
      ..add('')
      ..add('Recorded administrations')
      ..add('');
    for (final entry in entries) {
      lines.add(
        '${entry.dateOnly ? formatCivilDate(_civil(entry.occurredAt, selection.displayZone)) : formatInstant(entry.occurredAt, selection.displayZone, use24Hour: use24Hour)} · '
        '${entry.name} · '
        '${entry.amount == null ? 'No dose recorded' : '${formatAmount(entry.amount!)} ${entry.unit}'} · '
        '${entry.status == ReportLedgerStatus.corrected ? 'Corrected' : 'Recorded'}',
      );
    }
    lines
      ..add('')
      ..add(
        'An event is a grouping. An event end does not mean every included item stopped; '
        'item use periods remain separate. These are recorded entries, not proof of use or a treatment recommendation.',
      );
    return lines.join('\n');
  }
}

/// Whether the selected half-open period covers the event start and any
/// recorded end. An ongoing event may extend beyond the capture cutoff; a
/// recorded end outside the period would silently cut the review short.
bool eventSelectionCovers(EventRecord event, ReportSelection selection) {
  final display = DisplayTime();
  final from = display
      .dayBounds(selection.fromDate, selection.displayZone)
      .start;
  final before = display
      .dayBounds(selection.beforeDate, selection.displayZone)
      .start;
  final start = _eventBoundary(
    event.actualStart ?? event.plannedStart,
    event.zoneId,
  );
  if (start != null && (start.isBefore(from) || !start.isBefore(before))) {
    return false;
  }
  final endDate = event.actualEnd;
  final end =
      _eventBoundary(endDate, event.zoneId, endOfDay: true) ??
      event.completedAt;
  if (end != null) {
    if (endDate?.precision == EventDatePrecision.day) {
      if (!end.isAfter(from) || end.isAfter(before)) return false;
    } else if (end.isBefore(from) || !end.isBefore(before)) {
      return false;
    }
  }
  return true;
}

DateTime? _eventBoundary(
  EventDate? date,
  String zone, {
  bool endOfDay = false,
}) {
  switch (date?.precision) {
    case EventDatePrecision.exact:
      return DateTime.parse(date!.value!).toUtc();
    case EventDatePrecision.day:
      final day = CivilDate.parse(date!.value!);
      return DisplayTime()
          .dayBounds(endOfDay ? day.addDays(1) : day, zone)
          .start;
    default:
      return null;
  }
}

RecordedUsePeriod? _latestPeriod(List<RecordedUsePeriod> periods) {
  if (periods.isEmpty) return null;
  final sorted = [...periods]..sort((a, b) => _dateCompare(a.start, b.start));
  return sorted.last;
}

int _dateCompare(EventDate a, EventDate b) {
  final rank = _rank(a.precision).compareTo(_rank(b.precision));
  if (rank != 0) return rank;
  return (a.value ?? '').compareTo(b.value ?? '');
}

int _rank(EventDatePrecision precision) => switch (precision) {
  EventDatePrecision.unknown => 0,
  EventDatePrecision.year => 1,
  EventDatePrecision.month => 2,
  EventDatePrecision.day => 3,
  EventDatePrecision.exact => 4,
};

String _dateRange(
  EventDate? start,
  EventDate? end,
  String zone, {
  required bool use24Hour,
}) {
  final from = start == null
      ? 'Not recorded'
      : formatEventDate(start, zone, use24Hour: use24Hour);
  final to = end == null
      ? 'Ongoing'
      : formatEventDate(end, zone, use24Hour: use24Hour);
  if (start == null && end == null) return 'Not recorded';
  return '$from to $to';
}

/// Absolute event date text retaining the supplied precision.
String formatEventDate(
  EventDate date,
  String zone, {
  required bool use24Hour,
}) => switch (date.precision) {
  EventDatePrecision.unknown => 'Unknown',
  EventDatePrecision.year => 'Year ${date.value}',
  EventDatePrecision.month => 'Month ${date.value}',
  EventDatePrecision.day => formatCivilDate(CivilDate.parse(date.value!)),
  EventDatePrecision.exact => formatInstant(
    DateTime.parse(date.value!),
    zone,
    use24Hour: use24Hour,
  ),
};

String _useText(ReportEventMember member) => switch (member.useStatus) {
  ReportUseStatus.ongoing => 'Ongoing separately',
  ReportUseStatus.ended => 'Use period ended',
  ReportUseStatus.noPeriod => 'No use period recorded',
};

CivilDate _civil(DateTime instant, String zone) {
  try {
    return DisplayTime().instant(instant, zone).civilDate;
  } catch (_) {
    return DisplayTime().instant(instant, 'UTC').civilDate;
  }
}

/// Compatible quantity groups stay separate even when they share one item id.
String reportEventMemberUse(ReportEventMember member) {
  if (member.administrations == 0) return 'No use recorded';
  final lines = <String>[];
  for (final quantity in member.quantities) {
    lines.add(
      '${quantity.name}: ${quantity.total == null ? 'Total unavailable' : '${formatAmount(quantity.total!)} ${quantity.unit}'}',
    );
  }
  for (final product in member.products) {
    lines.add(
      '${product.name}: ${product.volume == null ? 'Volume unavailable' : '${formatAmount(product.volume!)} ${product.volumeUnit} product'}',
    );
    for (final ingredient in product.ingredients) {
      lines.add(
        '${ingredient.name}${ingredient.strength == null ? '' : ' (${ingredient.strength})'}: ${ingredient.complete ? formatAmount(ingredient.knownSubtotal!) : 'Unknown'} ${ingredient.unit}',
      );
    }
  }
  if (member.quantities.isEmpty && member.products.isEmpty) {
    lines.add(
      member.total == null
          ? 'Total unavailable'
          : '${formatAmount(member.total!)} ${member.volumeUnit ?? member.unit}',
    );
  }
  lines.add('${member.administrations} administrations');
  return lines.join('\n');
}
