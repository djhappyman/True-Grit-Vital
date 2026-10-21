import '../scheduling/daily_plan.dart';
import '../scheduling/iana_clock.dart';

enum EventDatePrecision { unknown, year, month, day, exact }

/// Supplied precision is retained. Unknown and partial dates never become doses.
final class EventDate {
  EventDate({required this.precision, this.value}) {
    final v = value;
    switch (precision) {
      case EventDatePrecision.unknown:
        if (v != null) throw ArgumentError('unknown_date_value');
      case EventDatePrecision.year:
        if (v == null || !RegExp(r'^\d{4}$').hasMatch(v) || int.parse(v) < 1) {
          throw ArgumentError('event_year');
        }
      case EventDatePrecision.month:
        if (v == null || !RegExp(r'^\d{4}-\d{2}$').hasMatch(v)) {
          throw ArgumentError('event_month');
        }
        CivilDate.parse('$v-01');
      case EventDatePrecision.day:
        CivilDate.parse(v!);
      case EventDatePrecision.exact:
        final parts = v == null
            ? null
            : RegExp(
                r'^(\d{4}-\d{2}-\d{2})T(\d{2}):(\d{2})(?::(\d{2})(?:\.\d{1,6})?)?(Z|[+-](\d{2}):(\d{2}))$',
              ).firstMatch(v);
        if (parts == null) throw ArgumentError('event_instant');
        CivilDate.parse(parts[1]!);
        if (int.parse(parts[2]!) > 23 ||
            int.parse(parts[3]!) > 59 ||
            int.parse(parts[4] ?? '0') > 59 ||
            int.parse(parts[6] ?? '0') > 23 ||
            int.parse(parts[7] ?? '0') > 59) {
          throw ArgumentError('event_instant');
        }
        final instant = DateTime.parse(v!);
        if (!instant.isUtc || instant.year < 1 || instant.year > 9999) {
          throw ArgumentError('event_instant');
        }
    }
  }
  factory EventDate.unknown() =>
      EventDate(precision: EventDatePrecision.unknown);
  factory EventDate.day(CivilDate value) =>
      EventDate(precision: EventDatePrecision.day, value: value.toString());
  factory EventDate.exact(DateTime value) {
    if (!value.isUtc) throw ArgumentError('event_instant_zone');
    return EventDate(
      precision: EventDatePrecision.exact,
      value: value.toIso8601String(),
    );
  }
  final EventDatePrecision precision;
  final String? value;
  Map<String, Object?> toJson() => {
    'precision': precision.name,
    'value': value,
  };
  factory EventDate.fromJson(Map<String, Object?> json) => EventDate(
    precision: EventDatePrecision.values.byName(json['precision']! as String),
    value: json['value'] as String?,
  );

  /// Exact dates are instants. An inclusive civil end becomes the next midnight.
  /// Missing, folded or unsupported midnights require explicit review.
  DateTime? resolve(
    IanaClock clock,
    String zoneId, {
    bool inclusiveEnd = false,
  }) {
    if (precision == EventDatePrecision.exact) return DateTime.parse(value!);
    if (precision != EventDatePrecision.day) return null;
    final date = CivilDate.parse(value!);
    final candidates = clock.candidates(
      inclusiveEnd ? date.addDays(1) : date,
      WallTime(0, 0),
      zoneId,
    );
    if (candidates.length != 1) throw StateError('event_boundary_review');
    return candidates.single;
  }
}

final class EventMembership {
  EventMembership({
    required this.id,
    required this.itemId,
    required this.personId,
    required this.effectiveFrom,
    this.effectiveUntil,
    required this.revision,
  }) {
    if ([id, itemId, personId].any((v) => v.isEmpty) ||
        revision < 1 ||
        !effectiveFrom.isUtc ||
        effectiveUntil != null &&
            (!effectiveUntil!.isUtc ||
                !effectiveUntil!.isAfter(effectiveFrom))) {
      throw ArgumentError('event_membership');
    }
  }
  final String id, itemId, personId;
  final DateTime effectiveFrom;
  final DateTime? effectiveUntil;
  final int revision;
  bool includes(DateTime instant) =>
      !instant.isBefore(effectiveFrom) &&
      (effectiveUntil == null || instant.isBefore(effectiveUntil!));
  Map<String, Object?> toJson() => {
    'id': id,
    'itemId': itemId,
    'personId': personId,
    'effectiveFrom': effectiveFrom.toIso8601String(),
    'effectiveUntil': effectiveUntil?.toIso8601String(),
    'revision': revision,
  };
  factory EventMembership.fromJson(Map<String, Object?> json) =>
      EventMembership(
        id: json['id']! as String,
        itemId: json['itemId']! as String,
        personId: json['personId']! as String,
        effectiveFrom: DateTime.parse(json['effectiveFrom']! as String),
        effectiveUntil: _instant(json['effectiveUntil']),
        revision: json['revision']! as int,
      );
}

/// A civil boundary could not be resolved without choosing a time policy.
final class EventBoundaryReview implements Exception {
  const EventBoundaryReview(this.code);
  final String code;
}

final class EventRecord {
  EventRecord({
    required this.id,
    required this.personId,
    required this.name,
    required this.eventType,
    required this.zoneId,
    required this.revision,
    this.plannedStart,
    this.plannedEnd,
    this.actualStart,
    this.actualEnd,
    this.completed = false,
    this.completedAt,
    this.endReviewDismissed = false,
    this.notes = '',
    Iterable<EventMembership> memberships = const [],
  }) : memberships = List.unmodifiable(memberships) {
    if ([
          id,
          personId,
          name.trim(),
          eventType.trim(),
          zoneId,
        ].any((v) => v.isEmpty) ||
        revision < 1 ||
        notes.length > 8000 ||
        completedAt != null && !completedAt!.isUtc ||
        this.memberships.any((m) => m.personId != personId) ||
        this.memberships.map((m) => m.id).toSet().length !=
            this.memberships.length) {
      throw ArgumentError('event_record');
    }
    for (final a in this.memberships) {
      for (final b in this.memberships) {
        if (a.id != b.id &&
            a.itemId == b.itemId &&
            (b.effectiveUntil == null ||
                a.effectiveFrom.isBefore(b.effectiveUntil!)) &&
            (a.effectiveUntil == null ||
                b.effectiveFrom.isBefore(a.effectiveUntil!))) {
          throw ArgumentError('event_membership_overlap');
        }
      }
    }
  }
  final String id, personId, name, eventType, zoneId;
  final String notes;
  final int revision;
  final EventDate? plannedStart, plannedEnd, actualStart, actualEnd;
  final bool completed, endReviewDismissed;
  final DateTime? completedAt;
  final List<EventMembership> memberships;
  EventRecord copyWith({
    String? name,
    String? eventType,
    String? zoneId,
    String? notes,
    int? revision,
    EventDate? plannedStart,
    EventDate? plannedEnd,
    EventDate? actualStart,
    EventDate? actualEnd,
    bool? completed,
    DateTime? completedAt,
    bool clearCompletedAt = false,
    bool? endReviewDismissed,
    Iterable<EventMembership>? memberships,
    bool clearPlannedStart = false,
    bool clearPlannedEnd = false,
    bool clearActualStart = false,
    bool clearActualEnd = false,
  }) => EventRecord(
    id: id,
    personId: personId,
    name: name ?? this.name,
    eventType: eventType ?? this.eventType,
    zoneId: zoneId ?? this.zoneId,
    notes: notes ?? this.notes,
    revision: revision ?? this.revision,
    plannedStart: clearPlannedStart ? null : plannedStart ?? this.plannedStart,
    plannedEnd: clearPlannedEnd ? null : plannedEnd ?? this.plannedEnd,
    actualStart: clearActualStart ? null : actualStart ?? this.actualStart,
    actualEnd: clearActualEnd ? null : actualEnd ?? this.actualEnd,
    completed: completed ?? this.completed,
    completedAt: clearCompletedAt ? null : completedAt ?? this.completedAt,
    endReviewDismissed: endReviewDismissed ?? this.endReviewDismissed,
    memberships: memberships ?? this.memberships,
  );
  DateTime? endReviewAt(IanaClock clock) {
    final actual = actualEnd?.resolve(clock, zoneId, inclusiveEnd: true);
    if (actual != null) return actual;
    if (completed) return completedAt;
    return plannedEnd?.resolve(clock, zoneId, inclusiveEnd: true);
  }

  void validateBounds(IanaClock clock) {
    try {
      clock.validateZone(zoneId);
    } catch (_) {
      throw const EventBoundaryReview('event_zone_review');
    }
    try {
      for (final pair in [
        (plannedStart, plannedEnd),
        (actualStart, actualEnd),
      ]) {
        final start = pair.$1?.resolve(clock, zoneId);
        final end = pair.$2?.resolve(clock, zoneId, inclusiveEnd: true);
        if (start != null && end != null && !end.isAfter(start)) {
          throw ArgumentError('event_bounds');
        }
      }
    } on ArgumentError {
      rethrow;
    } catch (_) {
      throw const EventBoundaryReview('event_boundary_review');
    }
  }

  bool includes({
    required String ownerId,
    required String itemId,
    required DateTime actualAt,
    required IanaClock clock,
  }) {
    if (ownerId != personId || !actualAt.isUtc) return false;
    final start = (actualStart ?? plannedStart)?.resolve(clock, zoneId);
    final end = (actualEnd ?? plannedEnd)?.resolve(
      clock,
      zoneId,
      inclusiveEnd: true,
    );
    return (start == null || !actualAt.isBefore(start)) &&
        (end == null || actualAt.isBefore(end)) &&
        memberships.any((m) => m.itemId == itemId && m.includes(actualAt));
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'personId': personId,
    'name': name,
    'eventType': eventType,
    'zoneId': zoneId,
    'revision': revision,
    'plannedStart': plannedStart?.toJson(),
    'plannedEnd': plannedEnd?.toJson(),
    'actualStart': actualStart?.toJson(),
    'actualEnd': actualEnd?.toJson(),
    'completed': completed,
    'completedAt': completedAt?.toIso8601String(),
    'endReviewDismissed': endReviewDismissed,
    if (notes.isNotEmpty) 'notes': notes,
    'memberships': memberships.map((m) => m.toJson()).toList(),
  };
  factory EventRecord.fromJson(Map<String, Object?> json) => EventRecord(
    id: json['id']! as String,
    personId: json['personId']! as String,
    name: json['name']! as String,
    eventType: json['eventType']! as String,
    zoneId: json['zoneId']! as String,
    revision: json['revision']! as int,
    plannedStart: _date(json['plannedStart']),
    plannedEnd: _date(json['plannedEnd']),
    actualStart: _date(json['actualStart']),
    actualEnd: _date(json['actualEnd']),
    completed: json['completed']! as bool,
    completedAt: _instant(json['completedAt']),
    endReviewDismissed: json['endReviewDismissed']! as bool,
    notes: json['notes'] as String? ?? '',
    memberships: (json['memberships']! as List).map(
      (v) => EventMembership.fromJson(Map<String, Object?>.from(v as Map)),
    ),
  );
}

enum UsePeriodKind { use, breakPeriod }

final class RecordedUsePeriod {
  RecordedUsePeriod({
    required this.id,
    required this.personId,
    required this.itemId,
    required this.revision,
    required this.start,
    this.end,
    this.kind = UsePeriodKind.use,
    this.firstEver = false,
  }) {
    if ([id, personId, itemId].any((v) => v.isEmpty) ||
        revision < 1 ||
        firstEver && kind != UsePeriodKind.use) {
      throw ArgumentError('use_period');
    }
    if (end != null &&
        start.precision == end!.precision &&
        start.value != null &&
        end!.value != null &&
        (start.precision == EventDatePrecision.exact
            ? DateTime.parse(end!.value!).isBefore(DateTime.parse(start.value!))
            : end!.value!.compareTo(start.value!) < 0)) {
      throw ArgumentError('use_period_bounds');
    }
  }
  final String id, personId, itemId;
  final int revision;
  final EventDate start;
  final EventDate? end;
  final UsePeriodKind kind;
  final bool firstEver;

  /// Only fully known same-precision dates produce a duration. No adherence inference.
  Duration? duration(IanaClock clock, String zoneId) {
    if (start.precision != end?.precision) return null;
    final a = start.resolve(clock, zoneId);
    final b = end?.resolve(clock, zoneId, inclusiveEnd: true);
    if (a == null || b == null) return null;
    if (b.isBefore(a)) throw ArgumentError('use_period_bounds');
    return b.difference(a);
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'personId': personId,
    'itemId': itemId,
    'revision': revision,
    'start': start.toJson(),
    'end': end?.toJson(),
    'kind': kind.name,
    'firstEver': firstEver,
  };
  factory RecordedUsePeriod.fromJson(Map<String, Object?> json) =>
      RecordedUsePeriod(
        id: json['id']! as String,
        personId: json['personId']! as String,
        itemId: json['itemId']! as String,
        revision: json['revision']! as int,
        start: _date(json['start'])!,
        end: _date(json['end']),
        kind: UsePeriodKind.values.byName(json['kind']! as String),
        firstEver: json['firstEver']! as bool,
      );
}

final class SaveEventCommand {
  const SaveEventCommand({
    required this.commandId,
    required this.generation,
    required this.expectedRevision,
    required this.event,
    this.expectedPersonRevision = 1,
  });
  final String commandId, generation;
  final int? expectedRevision;
  final EventRecord event;
  final int expectedPersonRevision;
  Map<String, Object?> toJson() => {
    'commandId': commandId,
    'generation': generation,
    'expectedRevision': expectedRevision,
    'expectedPersonRevision': expectedPersonRevision,
    'event': event.toJson(),
  };
  factory SaveEventCommand.fromJson(Map<String, Object?> json) =>
      SaveEventCommand(
        commandId: json['commandId']! as String,
        generation: json['generation']! as String,
        expectedRevision: json['expectedRevision'] as int?,
        expectedPersonRevision: json['expectedPersonRevision']! as int,
        event: EventRecord.fromJson(
          Map<String, Object?>.from(json['event']! as Map),
        ),
      );
}

final class SaveUsePeriodCommand {
  const SaveUsePeriodCommand({
    required this.commandId,
    required this.generation,
    required this.expectedRevision,
    required this.period,
    this.expectedPersonRevision = 1,
  });
  final String commandId, generation;
  final int? expectedRevision;
  final RecordedUsePeriod period;
  final int expectedPersonRevision;
  Map<String, Object?> toJson() => {
    'commandId': commandId,
    'generation': generation,
    'expectedRevision': expectedRevision,
    'expectedPersonRevision': expectedPersonRevision,
    'period': period.toJson(),
  };
  factory SaveUsePeriodCommand.fromJson(Map<String, Object?> json) =>
      SaveUsePeriodCommand(
        commandId: json['commandId']! as String,
        generation: json['generation']! as String,
        expectedRevision: json['expectedRevision'] as int?,
        expectedPersonRevision: json['expectedPersonRevision']! as int,
        period: RecordedUsePeriod.fromJson(
          Map<String, Object?>.from(json['period']! as Map),
        ),
      );
}

EventDate? _date(Object? value) => value == null
    ? null
    : EventDate.fromJson(Map<String, Object?>.from(value as Map));
DateTime? _instant(Object? value) =>
    value == null ? null : DateTime.parse(value as String);
