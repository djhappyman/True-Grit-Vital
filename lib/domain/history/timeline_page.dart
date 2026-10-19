import 'timeline_entry.dart';
import 'timeline_query.dart';

/// One parent-first page of History entries.
final class TimelinePage {
  TimelinePage({
    required this.query,
    required this.schemaVersion,
    required this.datasetGeneration,
    required Iterable<TimelineEntry> entries,
    this.hasMore = false,
  }) : entries = List.unmodifiable(entries) {
    if (schemaVersion < 1) {
      throw const TimelineModelException('page_schema');
    }
    if (datasetGeneration.isEmpty ||
        datasetGeneration.trim().isEmpty ||
        datasetGeneration.length > 256) {
      throw const TimelineModelException('page_generation');
    }
    if (this.entries.length > query.limit) {
      throw const TimelineModelException('page_limit');
    }
    final cursor = query.cursor;
    if (cursor != null) {
      cursor.validateFor(
        query: query,
        schemaVersion: schemaVersion,
        datasetGeneration: datasetGeneration,
      );
    }
    final identities = <String>{};
    final owner = query.filter.scope.personId;
    TimelineEntry? previous;
    for (final entry in this.entries) {
      if (!identities.add(entry.id.sortKey)) {
        throw const TimelineModelException('page_duplicate');
      }
      if (previous != null && compareTimelineEntries(previous, entry) >= 0) {
        throw const TimelineModelException('page_order');
      }
      if (cursor != null && !timelineEntryIsAfterCursor(entry, cursor)) {
        throw const TimelineModelException('page_cursor');
      }
      if (owner != null && entry.personId != owner) {
        throw const TimelineModelException('page_scope');
      }
      if (!query.filter.status.includes(entry.status)) {
        throw const TimelineModelException('page_status');
      }
      previous = entry;
    }
    if (hasMore && this.entries.isEmpty) {
      throw const TimelineModelException('page_next');
    }
  }

  final TimelineQuery query;
  final int schemaVersion;
  final String datasetGeneration;
  final List<TimelineEntry> entries;
  final bool hasMore;

  /// Exclusive cursor of the last entry when another parent page exists.
  TimelineCursor? get next {
    if (!hasMore) return null;
    final last = entries.last;
    return TimelineCursor.at(
      occurredAt: last.occurredAt,
      sortKey: last.id.sortKey,
      query: query,
      schemaVersion: schemaVersion,
      datasetGeneration: datasetGeneration,
    );
  }

  String get queryIdentity => query.identity;

  bool get isFirstPage => query.cursor == null;
}
