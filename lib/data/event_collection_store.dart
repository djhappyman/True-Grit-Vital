part of 'record_store.dart';

extension EventCollectionStore on RecordStore {
  /// A coherent whole-collection snapshot for the Events destination.
  ///
  /// Status depends on each saved zone, date precision and completion mark, so
  /// SQL cannot safely classify a row. This read decodes the current event
  /// snapshots once and applies the canonical display rule. It deliberately
  /// does not add a LIMIT to the source read: a page is sliced only after the
  /// whole collection has been classified, so counts and filters are never
  /// silently restricted to the loaded page. The widget layer watches the
  /// snapshot instead of decoding events during each frame.
  Future<EventCollectionSnapshot> eventCollection({
    String personId = meId,
    required EventCollectionFilter filter,
    required DateTime now,
    int offset = 0,
    int pageSize = eventCollectionPageSize,
  }) async {
    _pageBounds(pageSize, offset);
    _requireWritable();
    final asOf = now.toUtc();
    final result = await _db.transaction(() async {
      final rowSet = await _rows(
        'SELECT snapshot FROM event_record WHERE person=? ORDER BY id',
        [personId],
      );
      final counts = _MutableEventCounts();
      final filtered = <EventRecord>[];
      for (final row in rowSet) {
        final event = EventRecord.fromJson(
          Map<String, Object?>.from(
            jsonDecode(row['snapshot'] as String) as Map,
          ),
        );
        final phase = eventCollectionPhase(event, asOf);
        counts.add(phase);
        if (_matchesPhase(filter, phase)) filtered.add(event);
      }
      if ((await _rows('SELECT generation FROM dataset'))
              .single['generation'] !=
          generation) {
        throw const CommandConflict('generation');
      }
      // Clamp against the chosen status, never the whole collection: unrelated
      // statuses must not keep a stale page inside a smaller filtered set.
      final filteredTotal = filtered.length;
      final lastOffset = filteredTotal == 0
          ? 0
          : ((filteredTotal - 1) ~/ pageSize) * pageSize;
      final effectiveOffset = offset > lastOffset ? lastOffset : offset;
      return EventCollectionSnapshot(
        generation: generation,
        asOf: asOf,
        filter: filter,
        offset: effectiveOffset,
        pageSize: pageSize,
        events: filtered.skip(effectiveOffset).take(pageSize),
        counts: counts.snapshot(),
      );
    });
    _requireWritable();
    return result;
  }

  Stream<EventCollectionSnapshot> watchEventCollection({
    String personId = meId,
    required EventCollectionFilter filter,
    required DateTime now,
    int offset = 0,
    int pageSize = eventCollectionPageSize,
  }) => _watch(
    () => eventCollection(
      personId: personId,
      filter: filter,
      now: now,
      offset: offset,
      pageSize: pageSize,
    ),
  );
}

const eventCollectionPageSize = 50;

bool _matchesPhase(EventCollectionFilter filter, EventCollectionPhase phase) =>
    switch (filter) {
      EventCollectionFilter.all => true,
      EventCollectionFilter.active => phase == EventCollectionPhase.active,
      EventCollectionFilter.upcoming => phase == EventCollectionPhase.upcoming,
      EventCollectionFilter.completed =>
        phase == EventCollectionPhase.completed,
      EventCollectionFilter.review => phase == EventCollectionPhase.review,
    };

final class _MutableEventCounts {
  int active = 0, upcoming = 0, completed = 0, review = 0;

  void add(EventCollectionPhase phase) {
    switch (phase) {
      case EventCollectionPhase.active:
        active++;
      case EventCollectionPhase.upcoming:
        upcoming++;
      case EventCollectionPhase.completed:
        completed++;
      case EventCollectionPhase.review:
        review++;
    }
  }

  int get total => active + upcoming + completed + review;

  EventCollectionCounts snapshot() => EventCollectionCounts(
    all: total,
    active: active,
    upcoming: upcoming,
    completed: completed,
    review: review,
  );
}
