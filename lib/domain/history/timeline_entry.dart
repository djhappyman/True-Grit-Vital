import '../combined_use.dart' show maxCombinedSources;
import '../records.dart';
import '../scheduling/daily_plan.dart';
import '../scheduling/iana_clock.dart';
import '../scheduling/stored_daily.dart';
import 'display_time.dart';
import 'timeline_query.dart';

/// Typed parent-entry or page integrity failure.
final class TimelineModelException implements Exception {
  const TimelineModelException(this.code);

  final String code;

  @override
  String toString() => 'TimelineModelException($code)';
}

enum TimelineEntryKind { record, combined, skipped }

/// Status of one parent entry. Combined status is group-level.
enum TimelineEntryStatus { recorded, skipped, voided }

extension TimelineStatusMatch on TimelineStatus {
  bool includes(TimelineEntryStatus status) => switch (this) {
    TimelineStatus.all => true,
    TimelineStatus.recorded => status == TimelineEntryStatus.recorded,
    TimelineStatus.skipped => status == TimelineEntryStatus.skipped,
    TimelineStatus.voided => status == TimelineEntryStatus.voided,
  };
}

/// Stable prefixed parent identity: `r:`, `c:` or `s:`.
final class TimelineEntryId implements Comparable<TimelineEntryId> {
  TimelineEntryId._(this.kind, this.value) {
    if (value.isEmpty || value.trim().isEmpty || value.length > 256) {
      throw const TimelineModelException('entry_identity');
    }
  }

  factory TimelineEntryId.record(String value) =>
      TimelineEntryId._(TimelineEntryKind.record, value);

  factory TimelineEntryId.combined(String value) =>
      TimelineEntryId._(TimelineEntryKind.combined, value);

  factory TimelineEntryId.skipped(String value) =>
      TimelineEntryId._(TimelineEntryKind.skipped, value);

  factory TimelineEntryId.parse(String sortKey) {
    if (sortKey.length < 3 || sortKey.length > 258 || sortKey[1] != ':') {
      throw const TimelineModelException('entry_identity');
    }
    final kind = switch (sortKey[0]) {
      'r' => TimelineEntryKind.record,
      'c' => TimelineEntryKind.combined,
      's' => TimelineEntryKind.skipped,
      _ => throw const TimelineModelException('entry_identity'),
    };
    return TimelineEntryId._(kind, sortKey.substring(2));
  }

  final TimelineEntryKind kind;
  final String value;

  String get sortKey => switch (kind) {
    TimelineEntryKind.record => 'r:$value',
    TimelineEntryKind.combined => 'c:$value',
    TimelineEntryKind.skipped => 's:$value',
  };

  @override
  int compareTo(TimelineEntryId other) => sortKey.compareTo(other.sortKey);

  @override
  bool operator ==(Object other) =>
      other is TimelineEntryId && kind == other.kind && value == other.value;

  @override
  int get hashCode => Object.hash(kind, value);

  @override
  String toString() => sortKey;
}

/// Plan context retained with a taken daily action or a skipped occurrence.
final class TimelinePlanContext {
  TimelinePlanContext({
    required this.expectation,
    this.planName,
    this.itemName,
    this.requirements,
  }) {
    _checkOptionalText(planName, 'plan_name');
    _checkOptionalText(itemName, 'item_name');
  }

  final DailyExpectation expectation;
  final String? planName, itemName;
  final ScheduleRequirement? requirements;
}

sealed class TimelineEntry {
  TimelineEntry({
    required this.id,
    required this.personId,
    required this.occurredAt,
  }) {
    if (personId.isEmpty || personId.trim().isEmpty || personId.length > 256) {
      throw const TimelineModelException('entry_owner');
    }
    if (!occurredAt.isUtc || occurredAt.year < 1 || occurredAt.year > 9999) {
      throw const TimelineModelException('entry_instant');
    }
  }

  final TimelineEntryId id;

  /// Fixed owner from the owning row, never the currently selected profile.
  final String personId;

  /// Exact UTC ordering instant. Date-only skips use their plan-zone day start.
  final DateTime occurredAt;

  TimelineEntryStatus get status;

  bool get dateOnly => false;

  /// Saved plan zone where the row owns one.
  String? get planZone => null;
}

final class RecordTimelineEntry extends TimelineEntry {
  RecordTimelineEntry({required this.record, this.planContext})
    : super(
        id: TimelineEntryId.record(record.id),
        personId: record.personId,
        occurredAt: record.actualAt,
      ) {
    final context = planContext;
    if (context != null &&
        (context.expectation.identity.personId != record.personId ||
            context.expectation.itemId != record.itemId)) {
      throw const TimelineModelException('record_plan_context');
    }
  }

  final UseRecord record;

  /// Present when a taken daily action produced this single record entry.
  final TimelinePlanContext? planContext;

  bool get isTakenDailyAction => planContext != null;

  @override
  TimelineEntryStatus get status => record.isVoided
      ? TimelineEntryStatus.voided
      : TimelineEntryStatus.recorded;
}

final class CombinedTimelineComponent {
  const CombinedTimelineComponent({
    required this.position,
    required this.record,
    this.matched = false,
  });

  /// Membership position, ascending within the group.
  final int position;

  final UseRecord record;

  /// The current filter matched this component.
  final bool matched;
}

final class CombinedTimelineEntry extends TimelineEntry {
  factory CombinedTimelineEntry({
    required String actionId,
    required Iterable<CombinedTimelineComponent> components,
  }) {
    _checkText(actionId, 'combined_action');
    final list = List<CombinedTimelineComponent>.unmodifiable(components);
    if (list.length < 2 || list.length > maxCombinedSources) {
      throw const TimelineModelException('combined_components');
    }
    var previousPosition = -1;
    final recordIds = <String>{};
    for (final component in list) {
      if (component.position < 0 || component.position <= previousPosition) {
        throw const TimelineModelException('combined_position');
      }
      previousPosition = component.position;
      final record = component.record;
      if (!recordIds.add(record.id)) {
        throw const TimelineModelException('combined_duplicate');
      }
      if (record.combinedActionId != null &&
          record.combinedActionId != actionId) {
        throw const TimelineModelException('combined_membership');
      }
    }
    final first = list.first.record;
    for (final component in list.skip(1)) {
      final record = component.record;
      if (record.personId != first.personId) {
        throw const TimelineModelException('combined_owner');
      }
      if (record.actualAt != first.actualAt) {
        throw const TimelineModelException('combined_time');
      }
      if (record.isVoided != first.isVoided) {
        throw const TimelineModelException('combined_status');
      }
    }
    return CombinedTimelineEntry._(
      actionId: actionId,
      components: list,
      personId: first.personId,
      occurredAt: first.actualAt,
    );
  }

  CombinedTimelineEntry._({
    required this.actionId,
    required this.components,
    required super.personId,
    required super.occurredAt,
  }) : super(id: TimelineEntryId.combined(actionId));

  final String actionId;

  /// Full immutable group, ordered by membership position.
  final List<CombinedTimelineComponent> components;

  late final List<UseRecord> records = List.unmodifiable(
    components.map((component) => component.record),
  );

  /// Distinct record IDs selected by the current filter.
  late final List<String> matchedRecordIds = List.unmodifiable(
    components
        .where((component) => component.matched)
        .map((component) => component.record.id),
  );

  UseRecord get representative => components.first.record;

  @override
  TimelineEntryStatus get status => representative.isVoided
      ? TimelineEntryStatus.voided
      : TimelineEntryStatus.recorded;
}

final class SkippedTimelineEntry extends TimelineEntry {
  factory SkippedTimelineEntry({
    required DailyAction action,
    required TimelinePlanContext context,
    IanaClock? clock,
  }) {
    if (action.kind != DailyActionKind.skip ||
        action.isUndone ||
        action.recordId != null) {
      throw const TimelineModelException('skip_action');
    }
    final expectation = context.expectation;
    final savedDate =
        expectation.effectiveDate ?? expectation.identity.originalDate;
    final ordering =
        expectation.instant ??
        DisplayTime(clock: clock)
            .dayBounds(savedDate, expectation.zoneId)
            .start;
    return SkippedTimelineEntry._(
      action: action,
      context: context,
      savedDate: savedDate,
      dateOnly: expectation.instant == null,
      personId: expectation.identity.personId,
      occurredAt: ordering,
      planZone: expectation.zoneId,
    );
  }

  SkippedTimelineEntry._({
    required this.action,
    required this.context,
    required this.savedDate,
    required this.dateOnly,
    required super.personId,
    required super.occurredAt,
    required this.planZone,
  }) : super(id: TimelineEntryId.skipped(action.id));

  final DailyAction action;
  final TimelinePlanContext context;

  /// Effective date when present, otherwise the original plan date.
  final CivilDate savedDate;

  @override
  final bool dateOnly;

  @override
  final String planZone;

  DailyExpectation get expectation => context.expectation;

  String get itemId => expectation.itemId;

  PlannedAmount get amount => expectation.amount;

  bool get timeNeedsReview =>
      expectation.resolution == DailyResolution.missingClock ||
      expectation.resolution == DailyResolution.repeatedClock;

  @override
  TimelineEntryStatus get status => TimelineEntryStatus.skipped;
}

/// Total order: `occurredAt DESC, sortKey ASC`.
int compareTimelineEntries(TimelineEntry a, TimelineEntry b) =>
    TimelineCursor.comparePositions(
      aAt: a.occurredAt,
      aKey: a.id.sortKey,
      bAt: b.occurredAt,
      bKey: b.id.sortKey,
    );

bool timelineEntryIsAfterCursor(TimelineEntry entry, TimelineCursor cursor) =>
    cursor.isAfterCursor(
      occurredAt: entry.occurredAt,
      sortKey: entry.id.sortKey,
    );

void _checkText(String value, String code) {
  if (value.isEmpty || value.trim().isEmpty || value.length > 256) {
    throw TimelineModelException(code);
  }
}

void _checkOptionalText(String? value, String code) {
  if (value != null) _checkText(value, code);
}
