part of 'record_store.dart';

extension EventSummaryStore on RecordStore {
  /// Aggregates every current matching row using the same saved event bounds
  /// and membership intervals as history/report selection. EXISTS avoids
  /// multiplying an administration across membership rows.
  Future<EventUseSummary?> eventUseSummary(String eventId) async {
    _requireWritable();
    return _db.transaction(() async {
      final event = await eventById(eventId);
      if (event == null || event.personId != meId) return null;
      final bounds = await _rows(
        'SELECT * FROM event_history_bounds WHERE event=? AND person=?',
        [eventId, meId],
      );
      final substances = event.memberships.map((m) => m.itemId).toSet().length;
      if (bounds.isEmpty || bounds.single['resolved'] != 1) {
        _requireWritable();
        return EventUseSummary(
          generation: generation,
          eventRevision: event.revision,
          substances: substances,
        );
      }
      final b = bounds.single;
      String matches(String owner, String item, String time) =>
          '''
        $owner=? AND (? IS NULL OR $time>=?) AND (? IS NULL OR $time<?)
        AND EXISTS (SELECT 1 FROM event_membership m WHERE m.event=?
          AND m.person=$owner AND m.item=$item AND m.start<=$time
          AND (m.end IS NULL OR $time<m.end))''';
      final args = <Object?>[
        meId,
        b['start'],
        b['start'],
        b['end'],
        b['end'],
        eventId,
      ];
      final recorded =
          (await _rows(
                '''SELECT COUNT(*) AS n FROM administration a
        JOIN revision r ON r.record=a.id AND r.person=a.person AND r.revision=a.revision
        WHERE r.voided=0 AND ${matches('a.person', 'a.item', 'a.actual')}''',
                args,
              )).single['n']
              as int;
      final skipped = (await _rows(
        '''SELECT COUNT(*) AS n,
        COALESCE(SUM(CASE WHEN json_extract(e.snapshot,'\$.resolution') IN ('missingClock','repeatedClock') THEN 1 ELSE 0 END),0) AS review
        FROM daily_action d JOIN daily_expectation e ON e.id=d.bucket AND e.person=d.person
        WHERE d.kind='skip' AND d.undone=0 AND ${matches('d.person', 'e.item_id', 'd.occurs_at')}''',
        args,
      )).single;
      _requireWritable();
      return EventUseSummary(
        generation: generation,
        eventRevision: event.revision,
        substances: substances,
        recorded: recorded,
        skipped: skipped['n'] as int,
        skippedTimesNeedReview: skipped['review'] != 0,
      );
    });
  }

  Stream<EventUseSummary?> watchEventUseSummary(String eventId) =>
      _watch(() => eventUseSummary(eventId));
}
