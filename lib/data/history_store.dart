part of 'record_store.dart';

const historySchemaV17 = [
  'ALTER TABLE daily_expectation ADD COLUMN occurs_at INTEGER',
  'ALTER TABLE daily_expectation ADD COLUMN effective_date TEXT',
  "ALTER TABLE daily_expectation ADD COLUMN item_type TEXT NOT NULL DEFAULT 'legacy_unknown'",
  "ALTER TABLE daily_expectation ADD COLUMN item_name TEXT",
  'ALTER TABLE daily_expectation ADD COLUMN item_id TEXT',
  'ALTER TABLE daily_expectation ADD COLUMN date_only INTEGER NOT NULL DEFAULT 1 CHECK(date_only IN (0,1))',
  'CREATE INDEX history_recorded_type ON revision(type,record,revision)',
  'CREATE INDEX history_planned_type ON daily_expectation(item_type,person,id)',
  'CREATE INDEX history_expectation_global_time ON daily_expectation(occurs_at DESC,id)',
  'CREATE INDEX history_expectation_time ON daily_expectation(person,occurs_at,id)',
  'CREATE INDEX history_expectation_date ON daily_expectation(effective_date,person,id) WHERE date_only=1',
  "CREATE INDEX history_skip ON daily_action(person,bucket,id) WHERE kind='skip' AND undone=0",
  'CREATE INDEX history_combined_time ON combined_action(actual DESC,id)',
  'CREATE INDEX history_combined_person ON combined_action(person,actual DESC,id)',
  'CREATE TABLE event_history_bounds(event TEXT PRIMARY KEY,person TEXT NOT NULL,start INTEGER,end INTEGER,resolved INTEGER NOT NULL CHECK(resolved IN (0,1)),FOREIGN KEY(event,person) REFERENCES event_record(id,person) ON DELETE CASCADE) STRICT',
  'CREATE INDEX history_event_bounds ON event_history_bounds(person,start,end,event)',
];

// Captured occurrence and action identity must share an index: expectation
// identity is not a valid substitute when many skips have the same instant.
const historySchemaV18 = [
  'ALTER TABLE daily_action ADD COLUMN occurs_at INTEGER',
  'UPDATE daily_action SET occurs_at=(SELECT e.occurs_at FROM daily_expectation e WHERE e.id=daily_action.bucket AND e.person=daily_action.person)',
  "CREATE TRIGGER history_action_occurrence_insert BEFORE INSERT ON daily_action WHEN NEW.occurs_at IS NULL OR NOT EXISTS(SELECT 1 FROM daily_expectation e WHERE e.id=NEW.bucket AND e.person=NEW.person AND e.occurs_at=NEW.occurs_at) BEGIN SELECT RAISE(ABORT,'history_action_occurrence'); END",
  "CREATE TRIGGER history_action_occurrence_update BEFORE UPDATE OF occurs_at,bucket,person ON daily_action WHEN NEW.occurs_at IS NULL OR NOT EXISTS(SELECT 1 FROM daily_expectation e WHERE e.id=NEW.bucket AND e.person=NEW.person AND e.occurs_at=NEW.occurs_at) BEGIN SELECT RAISE(ABORT,'history_action_occurrence'); END",
  "CREATE TRIGGER history_expectation_occurrence_update BEFORE UPDATE OF occurs_at ON daily_expectation WHEN NEW.occurs_at IS NOT OLD.occurs_at AND EXISTS(SELECT 1 FROM daily_action d WHERE d.bucket=OLD.id AND d.person=OLD.person) BEGIN SELECT RAISE(ABORT,'history_captured_occurrence'); END",
  "CREATE INDEX history_skip_person_time ON daily_action(person,occurs_at DESC,id) WHERE kind='skip' AND undone=0",
  "CREATE INDEX history_skip_global_time ON daily_action(occurs_at DESC,id) WHERE kind='skip' AND undone=0",
];

Future<void> _migrateHistoryV18(_Database db) async {
  // Do not replace an unknown/missing captured time with a tap time or epoch.
  // The caller owns the transaction, including the schema-version update.
  final invalid = await db
      .customSelect(
        'SELECT d.id FROM daily_action d LEFT JOIN daily_expectation e ON e.id=d.bucket AND e.person=d.person WHERE e.occurs_at IS NULL LIMIT 1',
      )
      .get();
  if (invalid.isNotEmpty) {
    throw StateError('history_occurrence_migration_review');
  }
  for (final sql in historySchemaV18) {
    await db.customStatement(sql);
  }
}

final class HistoryCalendarCell {
  const HistoryCalendarCell({
    required this.date,
    required this.recorded,
    required this.skipped,
    required this.voided,
  });
  final CivilDate date;
  final int recorded, skipped, voided;
  int get total => recorded + skipped + voided;
}

final class HistoryCalendar {
  HistoryCalendar({
    required Iterable<HistoryCalendarCell> cells,
    required this.queryIdentity,
    required this.generation,
  }) : cells = List.unmodifiable(cells);
  final List<HistoryCalendarCell> cells;
  final String queryIdentity, generation;
  bool get overflow =>
      false; // Exact indexed counts; no truncated source materialisation.
}

final class HistoryOption {
  const HistoryOption({required this.id, required this.label, this.personId});
  final String id, label;
  final String? personId;
}

final class HistoryOptionPage {
  HistoryOptionPage({
    required Iterable<HistoryOption> options,
    required this.hasMore,
  }) : options = List.unmodifiable(options);
  final List<HistoryOption> options;
  final bool hasMore;
  String? get next => hasMore ? options.last.id : null;
}

final class DailyActionSource {
  const DailyActionSource({
    required this.action,
    required this.context,
    required this.recordedType,
  });
  final DailyAction action;
  final TimelinePlanContext context;
  final String recordedType;
}

final class _HistorySql {
  _HistorySql(this.sql, this.args);
  final String sql;
  final List<Object?> args;
}

extension HistoryRecordStore on RecordStore {
  Future<void> _writeEventHistoryBounds(EventRecord event) async {
    await _writeHistoryEventBounds(_db, event);
  }

  Future<void> _checkHistoryEvents(TimelineQuery query) async {
    final ids = query.filter.eventIds;
    if (ids.isEmpty) return;
    final marks = List.filled(ids.length, '?').join(',');
    final found = await _rows(
      'SELECT event,resolved FROM event_history_bounds WHERE event IN ($marks)',
      ids,
    );
    if (found.any((r) => r['resolved'] == 0)) {
      throw const TimelineQueryException('event_boundary_review');
    }
    final count = await _rows(
      'SELECT event FROM event_membership WHERE event IN ($marks) LIMIT 1001',
      ids,
    );
    if (count.length > TimelineLimits.maxEventMembershipClauses) {
      throw const TimelineQueryException('query_too_broad');
    }
  }

  _HistorySql _historyPredicate(TimelineQuery query, {required bool skip}) {
    final f = query.filter;
    final owner = skip ? 'e.person' : 'a.person';
    final time = skip ? 'e.occurs_at' : 'a.actual';
    final item = skip ? 'e.item_id' : 'a.item';
    final type = skip ? 'e.item_type' : 'r.type';
    final unit = skip
        ? "json_extract(e.snapshot,'\$.amount.unit')"
        : 'COALESCE(q.unit,r.unit)';
    final clauses = <String>[];
    final args = <Object?>[];
    if (f.scope.isEveryone) {
      clauses.add('$owner IN (SELECT id FROM person WHERE archived=0)');
    } else {
      clauses.add('$owner=?');
      args.add(f.scope.personId);
    }
    if (f.itemId != null) {
      clauses.add('$item=?');
      args.add(f.itemId);
    }
    if (f.typeIds.isNotEmpty) {
      clauses.add('$type IN (${List.filled(f.typeIds.length, '?').join(',')})');
      args.addAll(f.typeIds);
    }
    if (f.actualUnit != null) {
      clauses.add('$unit=?');
      args.add(f.actualUnit);
    }
    final display = DisplayTime();
    for (final pair in [(f.fromInstant, '>='), (f.beforeInstant, '<')]) {
      if (pair.$1 == null) continue;
      final at = pair.$1!;
      if (skip) {
        clauses.add(
          '((e.date_only=0 AND $time${pair.$2}?) OR (e.date_only=1 AND e.effective_date${pair.$2}?))',
        );
        args.addAll([
          at.microsecondsSinceEpoch,
          display.instant(at, query.displayZone).civilDate.toString(),
        ]);
      } else {
        clauses.add('$time${pair.$2}?');
        args.add(at.microsecondsSinceEpoch);
      }
    }
    if (f.eventIds.isNotEmpty) {
      clauses.add(
        'EXISTS (SELECT 1 FROM event_membership m JOIN event_history_bounds b ON b.event=m.event AND b.person=m.person WHERE m.person=$owner AND m.item=$item AND m.event IN (${List.filled(f.eventIds.length, '?').join(',')}) AND b.resolved=1 AND m.start<=$time AND (m.end IS NULL OR $time<m.end) AND (b.start IS NULL OR b.start<=$time) AND (b.end IS NULL OR $time<b.end))',
      );
      args.addAll(f.eventIds);
    }
    return _HistorySql(clauses.join(' AND '), args);
  }

  /// The same saved-filter semantics against one wrapped `_current` row.
  ///
  /// Used by the page's batched membership read so the matched subset is
  /// derived from rows already read for the page instead of a second query
  /// that starts from the owner's whole history.
  _HistorySql _historyMatchPredicate(TimelineQuery query) {
    final f = query.filter;
    final clauses = <String>[];
    final args = <Object?>[];
    if (f.scope.isEveryone) {
      clauses.add('x.person IN (SELECT id FROM person WHERE archived=0)');
    } else {
      clauses.add('x.person=?');
      args.add(f.scope.personId);
    }
    if (f.itemId != null) {
      clauses.add('x.item=?');
      args.add(f.itemId);
    }
    if (f.typeIds.isNotEmpty) {
      clauses.add(
        'x.type IN (${List.filled(f.typeIds.length, '?').join(',')})',
      );
      args.addAll(f.typeIds);
    }
    if (f.actualUnit != null) {
      clauses.add('COALESCE(x.actual_unit,x.unit)=?');
      args.add(f.actualUnit);
    }
    if (f.fromInstant != null) {
      clauses.add('x.actual>=?');
      args.add(f.fromInstant!.microsecondsSinceEpoch);
    }
    if (f.beforeInstant != null) {
      clauses.add('x.actual<?');
      args.add(f.beforeInstant!.microsecondsSinceEpoch);
    }
    if (f.eventIds.isNotEmpty) {
      clauses.add(
        'EXISTS (SELECT 1 FROM event_membership m JOIN event_history_bounds b ON b.event=m.event AND b.person=m.person WHERE m.person=x.person AND m.item=x.item AND m.event IN (${List.filled(f.eventIds.length, '?').join(',')}) AND b.resolved=1 AND m.start<=x.actual AND (m.end IS NULL OR x.actual<m.end) AND (b.start IS NULL OR b.start<=x.actual) AND (b.end IS NULL OR x.actual<b.end))',
      );
      args.addAll(f.eventIds);
    }
    return _HistorySql(clauses.join(' AND '), args);
  }

  /// Ordered feed path for current administrations.
  ///
  /// Everyone without item/type/unit/event filters starts from the global
  /// `administration_everyone(actual DESC,id)` index instead of iterating a
  /// per-person index and sorting. A person-scoped type filter uses the
  /// person's ordered feed rather than the global `history_recorded_type`
  /// index, whose `(type,record,revision)` shape cannot supply `actual` order
  /// and forces a full-type sort. Item filters keep the item feed.
  String _recordFeed(TimelineQuery query) {
    final f = query.filter;
    if (f.scope.isEveryone && !f.hasIdentityFilters) {
      return 'administration a INDEXED BY administration_everyone';
    }
    if (!f.scope.isEveryone && f.itemId == null && f.typeIds.isNotEmpty) {
      return 'administration a INDEXED BY administration_feed';
    }
    return 'administration a';
  }

  String _combinedScope(TimelineFilter f) => f.scope.isEveryone
      ? 'g.person IN (SELECT id FROM person WHERE archived=0)'
      : 'g.person=?';

  /// Ordered group feed. Everyone without identity filters starts from the
  /// global time index; a person page uses the person-first index.
  String _combinedFeed(TimelineQuery query) {
    final f = query.filter;
    if (f.scope.isEveryone && !f.hasIdentityFilters) {
      return 'combined_action g INDEXED BY history_combined_time';
    }
    if (!f.scope.isEveryone) {
      return 'combined_action g INDEXED BY history_combined_person';
    }
    return 'combined_action g';
  }

  // `combined_member`'s primary key is `(action,position)`, exposed by SQLite
  // as this autoindex. Forcing it keeps the page and correlated probes keyed by
  // the group identity instead of walking the owner's history.
  static const _combinedMemberByAction =
      'combined_member cm INDEXED BY sqlite_autoindex_combined_member_2';
  static const _combinedMemberPage =
      'combined_member c INDEXED BY sqlite_autoindex_combined_member_2';

  List<Object?> _combinedScopeArgs(TimelineFilter f) =>
      f.scope.isEveryone ? const [] : [f.scope.personId];

  Future<List<_HistorySql>> _historyBranches(TimelineQuery query) async {
    await _checkHistoryEvents(query);
    final f = query.filter;
    final p = _historyPredicate(query, skip: false);
    final branches = <_HistorySql>[];
    if (f.status != TimelineStatus.skipped) {
      final status = f.status == TimelineStatus.recorded
          ? ' AND r.voided=0'
          : f.status == TimelineStatus.voided
          ? ' AND r.voided=1'
          : '';
      const join =
          'revision r ON r.record=a.id AND r.person=a.person AND r.revision=a.revision LEFT JOIN revision_quantity q ON q.record=r.record AND q.revision=r.revision';
      branches.add(
        _HistorySql(
          "SELECT a.id,a.person,a.actual AS at,'r:'||a.id AS key,'record' AS kind,CASE r.voided WHEN 1 THEN 'voided' ELSE 'recorded' END AS status FROM ${_recordFeed(query)} JOIN $join WHERE ${p.sql}$status AND NOT EXISTS(SELECT 1 FROM combined_member cm WHERE cm.record=a.id)",
          p.args,
        ),
      );
      branches.add(
        _HistorySql(
          "SELECT g.id,g.person,g.actual AS at,'c:'||g.id AS key,'combined' AS kind,CASE (SELECT r.voided FROM combined_member m JOIN administration a ON a.id=m.record JOIN revision r ON r.record=a.id AND r.revision=a.revision WHERE m.action=g.id LIMIT 1) WHEN 1 THEN 'voided' ELSE 'recorded' END AS status FROM ${_combinedFeed(query)} WHERE ${_combinedScope(f)} AND EXISTS(SELECT 1 FROM $_combinedMemberByAction CROSS JOIN administration a ON a.id=cm.record AND a.person=cm.person JOIN $join WHERE cm.action=g.id AND cm.person=g.person AND ${p.sql}$status)",
          [..._combinedScopeArgs(f), ...p.args],
        ),
      );
    }
    if (f.status == TimelineStatus.all || f.status == TimelineStatus.skipped) {
      final s = _historyPredicate(query, skip: true);
      branches.add(
        _HistorySql(
          "SELECT d.id,d.person,d.occurs_at AS at,'s:'||d.id AS key,'skipped' AS kind,'skipped' AS status FROM daily_action d INDEXED BY ${f.scope.isEveryone ? 'history_skip_global_time' : 'history_skip_person_time'} CROSS JOIN daily_expectation e ON e.id=d.bucket AND e.person=d.person WHERE d.kind='skip' AND d.undone=0 AND ${f.scope.isEveryone ? 'd.person IN (SELECT id FROM person WHERE archived=0)' : 'd.person=?'} AND ${s.sql}",
          [if (!f.scope.isEveryone) f.scope.personId, ...s.args],
        ),
      );
    }
    return branches;
  }

  Future<TimelinePage> timeline(TimelineQuery query) async {
    _requireWritable();
    return _db.transaction(() async {
      query.cursor?.validateFor(
        query: query,
        schemaVersion: _db.schemaVersion,
        datasetGeneration: generation,
      );
      final branches = await _historyBranches(query);
      final parents = <Map<String, Object?>>[];
      for (final b in branches) {
        final cursor = query.cursor;
        parents.addAll(
          await _rows(
            'SELECT * FROM (${b.sql}) ${cursor == null ? '' : 'WHERE at<=? AND (at<? OR (at=? AND key>?))'} ORDER BY at DESC,id LIMIT ?',
            [
              ...b.args,
              if (cursor != null) ...[
                cursor.occurredAt.microsecondsSinceEpoch,
                cursor.occurredAt.microsecondsSinceEpoch,
                cursor.occurredAt.microsecondsSinceEpoch,
                cursor.sortKey,
              ],
              query.limit + 1,
            ],
          ),
        );
      }
      parents.sort((a, b) {
        final t = (b['at'] as int).compareTo(a['at'] as int);
        return t != 0 ? t : (a['key'] as String).compareTo(b['key'] as String);
      });
      final selected = parents.take(query.limit).toList();
      final entries = await _historyLoad(selected, query);
      return TimelinePage(
        query: query,
        schemaVersion: _db.schemaVersion,
        datasetGeneration: generation,
        entries: entries,
        hasMore: parents.length > query.limit,
      );
    });
  }

  Stream<TimelinePage> watchTimeline(TimelineQuery query) =>
      _watch(() => timeline(query));
  Future<List<TimelineEntry>> _historyLoad(
    List<Map<String, Object?>> parents,
    TimelineQuery query,
  ) async {
    final groupIds = parents
        .where((p) => p['kind'] == 'combined')
        .map((p) => p['id'] as String)
        .toList();
    final singleIds = parents
        .where((p) => p['kind'] == 'record')
        .map((p) => p['id'] as String)
        .toList();
    final records = <String, UseRecord>{};
    final contexts = <String, TimelinePlanContext>{};
    final groups = <String, List<CombinedTimelineComponent>>{};
    if (singleIds.isNotEmpty) {
      // One batched current-row read carries the optional taken-action plan
      // context, so the page does not issue a second context statement.
      final rows = await _rows(
        'SELECT x.*,pd.id AS plan_action_id,e.snapshot AS plan_snapshot,e.item_name AS plan_item_name FROM (${RecordStore._current}) x LEFT JOIN daily_action pd ON pd.record=x.id AND pd.person=x.person LEFT JOIN daily_expectation e ON e.id=pd.bucket AND e.person=pd.person WHERE x.id IN (${List.filled(singleIds.length, '?').join(',')})',
        singleIds,
      );
      for (final row in rows) {
        final record = _record(row);
        records[record.id] = record;
        final snapshot = row['plan_snapshot'];
        if (snapshot != null) {
          contexts[record.id] = TimelinePlanContext(
            expectation: decodeDailyExpectation(
              dailyObject(snapshot as String),
            ),
            itemName: row['plan_item_name'] as String?,
          );
        }
      }
    }
    if (groupIds.isNotEmpty) {
      final match = _historyMatchPredicate(query);
      final rows = await _rows(
        'SELECT c.action,c.position,x.*,CASE WHEN ${match.sql} THEN 1 ELSE 0 END AS matched FROM $_combinedMemberPage JOIN (${RecordStore._current}) x ON x.id=c.record AND x.person=c.person WHERE c.action IN (${List.filled(groupIds.length, '?').join(',')}) ORDER BY c.action,c.position LIMIT 801',
        [...match.args, ...groupIds],
      );
      if (rows.length > TimelineLimits.maxCombinedComponentsPerPage) {
        throw const TimelineQueryException('query_too_broad');
      }
      for (final row in rows) {
        final record = _record(row);
        (groups[row['action'] as String] ??= []).add(
          CombinedTimelineComponent(
            position: row['position'] as int,
            record: record,
            matched: row['matched'] == 1,
          ),
        );
      }
    }
    final skips = parents
        .where((p) => p['kind'] == 'skipped')
        .map((p) => p['id'] as String)
        .toList();
    final skipEntries = <String, SkippedTimelineEntry>{};
    if (skips.isNotEmpty) {
      for (final row in await _rows(
        'SELECT d.*,e.snapshot,e.item_name FROM daily_action d JOIN daily_expectation e ON e.id=d.bucket AND e.person=d.person WHERE d.id IN (${List.filled(skips.length, '?').join(',')})',
        skips,
      )) {
        skipEntries[row['id'] as String] = SkippedTimelineEntry(
          action: _dailyAction(row),
          context: TimelinePlanContext(
            expectation: decodeDailyExpectation(
              dailyObject(row['snapshot'] as String),
            ),
            itemName: row['item_name'] as String?,
          ),
        );
      }
    }
    return [
      for (final p in parents)
        switch (p['kind']) {
          'record' => RecordTimelineEntry(
            record: records[p['id']]!,
            planContext: contexts[p['id']],
          ),
          'combined' => CombinedTimelineEntry(
            actionId: p['id'] as String,
            components: groups[p['id']] ?? [],
          ),
          _ => skipEntries[p['id']]!,
        },
    ];
  }

  Future<TimelineEntry?> historyEntry(
    TimelineEntryId id, {
    required String personId,
  }) async {
    _requireWritable();
    final query = TimelineQuery(
      filter: TimelineFilter(scope: FeedScope.person(personId)),
      displayZone: 'UTC',
    );
    final table = switch (id.kind) {
      TimelineEntryKind.record => 'administration',
      TimelineEntryKind.combined => 'combined_action',
      TimelineEntryKind.skipped => 'daily_action',
    };
    final rows = await _rows(
      'SELECT id,person FROM $table WHERE id=? AND person=?',
      [id.value, personId],
    );
    if (rows.isEmpty) return null;
    if (id.kind == TimelineEntryKind.skipped) {
      final source = await dailyActionSource(id.value, personId: personId);
      if (source == null || source.action.isUndone) return null;
    }
    return (await _historyLoad([
      {...rows.single, 'kind': id.kind.name},
    ], query)).single;
  }

  Future<DailyActionSource?> dailyActionSource(
    String actionId, {
    required String personId,
  }) async {
    _requireWritable();
    final rows = await _rows(
      'SELECT d.*,a.revision AS actual_revision,e.snapshot,e.item_name,e.item_type FROM daily_action d JOIN daily_expectation e ON e.id=d.bucket AND e.person=d.person LEFT JOIN administration a ON a.id=d.record WHERE d.id=? AND d.person=?',
      [actionId, personId],
    );
    if (rows.isEmpty) return null;
    final r = rows.single;
    return DailyActionSource(
      action: _dailyAction(r),
      context: TimelinePlanContext(
        expectation: decodeDailyExpectation(
          dailyObject(r['snapshot'] as String),
        ),
        itemName: r['item_name'] as String?,
      ),
      recordedType: r['item_type'] as String,
    );
  }

  Future<List<Map<String, Object?>>> dailyActionAudit(
    String actionId, {
    String? personId,
    int? beforeSequence,
    int limit = 25,
  }) async {
    _requireWritable();
    if (limit < 1 || limit > 50) {
      throw const TimelineQueryException('invalid_limit');
    }
    return _rows(
      'SELECT d.* FROM daily_action d WHERE d.bucket=(SELECT bucket FROM daily_action WHERE id=?${personId == null ? '' : ' AND person=?'}) ${beforeSequence == null ? '' : 'AND d.sequence<?'} ORDER BY d.sequence DESC LIMIT ?',
      [actionId, ?personId, ?beforeSequence, limit],
    );
  }

  Future<List<UseRecord>> recordRevisionPage({
    required String recordId,
    required String personId,
    int? beforeRevision,
    int limit = 25,
  }) async {
    _requireWritable();
    if (limit < 1 || limit > 50) {
      throw const TimelineQueryException('invalid_limit');
    }
    final select = RecordStore._current
        .replaceFirst(' AND r.revision=a.revision', '')
        .replaceFirst(
          'WHERE record=a.id AND person=a.person ORDER BY sequence',
          'WHERE record=a.id AND person=a.person AND record_revision<=r.revision ORDER BY sequence',
        );
    return (await _rows(
      '$select WHERE a.id=? AND a.person=? ${beforeRevision == null ? '' : 'AND r.revision<?'} ORDER BY r.revision DESC LIMIT ?',
      [recordId, personId, ?beforeRevision, limit],
    )).map(_record).toList();
  }

  Future<HistoryCalendar> calendar(
    TimelineQuery query, {
    required List<CivilDate> dates,
  }) async {
    _requireWritable();
    if (dates.length > TimelineLimits.maxCalendarCells ||
        dates.toSet().length != dates.length) {
      throw const TimelineQueryException('query_too_broad');
    }
    return _db.transaction(() async {
      await _checkHistoryEvents(query);
      final ranges = <(String, int, int, String, String)>[];
      for (final date in dates) {
        final bounds = DisplayTime().dayBounds(date, query.displayZone);
        final from = query.filter.fromInstant;
        final before = query.filter.beforeInstant;
        final lower = from != null && from.isAfter(bounds.start)
            ? from
            : bounds.start;
        final upper = before != null && before.isBefore(bounds.endExclusive)
            ? before
            : bounds.endExclusive;
        if (upper.isAfter(lower)) {
          final display = DisplayTime();
          ranges.add((
            date.toString(),
            lower.microsecondsSinceEpoch,
            upper.microsecondsSinceEpoch,
            display.instant(lower, query.displayZone).civilDate.toString(),
            display.instant(upper, query.displayZone).civilDate.toString(),
          ));
        }
      }
      final counts = <String, int>{};
      if (ranges.isNotEmpty) {
        final sql = _calendarCounts(query, ranges);
        for (final row in await _rows(sql.sql, sql.args)) {
          counts['${row['cell']}|${row['status']}'] = row['count'] as int;
        }
      }
      return HistoryCalendar(
        cells: [
          for (final date in dates)
            HistoryCalendarCell(
              date: date,
              recorded: counts['${date.toString()}|recorded'] ?? 0,
              skipped: counts['${date.toString()}|skipped'] ?? 0,
              voided: counts['${date.toString()}|voided'] ?? 0,
            ),
        ],
        queryIdentity: query.identity,
        generation: generation,
      );
    });
  }

  /// One bounded aggregate over every visible cell range.
  ///
  /// The cells are a `VALUES` table, so record, combined and skip branches
  /// each use one index range per day instead of one statement per day and
  /// branch. Status stays a grouped output column, never a materialised row.
  _HistorySql _calendarCounts(
    TimelineQuery query,
    List<(String, int, int, String, String)> ranges,
  ) {
    final f = query.filter;
    final values = List.filled(ranges.length, '(?,?,?,?,?)').join(',');
    final args = <Object?>[
      for (final range in ranges) ...[
        range.$1,
        range.$2,
        range.$3,
        range.$4,
        range.$5,
      ],
    ];
    final branches = <String>[];
    // Cell ranges already encode the clipped date filter. Build the filter
    // predicate without from/before so a date range is not applied twice.
    final dayQuery = query.restart(
      filter: query.filter.restart(clearFrom: true, clearBefore: true),
    );
    final p = _historyPredicate(dayQuery, skip: false);
    final status = switch (f.status) {
      TimelineStatus.recorded => ' AND r.voided=0',
      TimelineStatus.voided => ' AND r.voided=1',
      _ => '',
    };
    if (f.status != TimelineStatus.skipped) {
      branches.add(
        "SELECT cell,status,COUNT(*) AS count FROM (SELECT c.day AS cell,CASE r.voided WHEN 1 THEN 'voided' ELSE 'recorded' END AS status FROM cells c JOIN ${_recordFeed(dayQuery)} JOIN revision r ON r.record=a.id AND r.person=a.person AND r.revision=a.revision LEFT JOIN revision_quantity q ON q.record=r.record AND q.revision=r.revision WHERE a.actual>=c.lo AND a.actual<c.hi AND ${p.sql}$status AND NOT EXISTS(SELECT 1 FROM combined_member cm WHERE cm.record=a.id)) GROUP BY cell,status",
      );
      args.addAll(p.args);
      branches.add(
        "SELECT cell,status,COUNT(*) AS count FROM (SELECT c.day AS cell,CASE (SELECT r.voided FROM combined_member m JOIN administration a ON a.id=m.record JOIN revision r ON r.record=a.id AND r.revision=a.revision WHERE m.action=g.id LIMIT 1) WHEN 1 THEN 'voided' ELSE 'recorded' END AS status FROM cells c JOIN ${_combinedFeed(dayQuery)} ON g.actual>=c.lo AND g.actual<c.hi WHERE ${_combinedScope(f)} AND EXISTS(SELECT 1 FROM $_combinedMemberByAction CROSS JOIN administration a ON a.id=cm.record AND a.person=cm.person JOIN revision r ON r.record=a.id AND r.person=a.person AND r.revision=a.revision LEFT JOIN revision_quantity q ON q.record=r.record AND q.revision=r.revision WHERE cm.action=g.id AND cm.person=g.person AND ${p.sql}$status)) GROUP BY cell,status",
      );
      args.addAll(_combinedScopeArgs(f));
      args.addAll(p.args);
    }
    if (f.status == TimelineStatus.all || f.status == TimelineStatus.skipped) {
      final s = _historyPredicate(dayQuery, skip: true);
      final timeIndex = f.scope.isEveryone
          ? 'history_expectation_global_time'
          : 'history_expectation_time';
      branches.add(
        "SELECT c.day AS cell,'skipped' AS status,COUNT(*) AS count FROM cells c JOIN daily_expectation e INDEXED BY $timeIndex ON e.occurs_at>=c.lo AND e.occurs_at<c.hi CROSS JOIN daily_action d ON d.bucket=e.id AND d.person=e.person WHERE d.kind='skip' AND d.undone=0 AND e.date_only=0 AND ${s.sql} GROUP BY c.day",
      );
      args.addAll(s.args);
      branches.add(
        "SELECT c.day AS cell,'skipped' AS status,COUNT(*) AS count FROM cells c JOIN daily_expectation e INDEXED BY history_expectation_date ON e.effective_date=c.day CROSS JOIN daily_action d ON d.bucket=e.id AND d.person=e.person WHERE d.kind='skip' AND d.undone=0 AND e.date_only=1 AND e.effective_date>=c.lower_day AND e.effective_date<c.upper_day AND ${s.sql} GROUP BY c.day",
      );
      args.addAll(s.args);
    }
    return _HistorySql(
      'WITH cells(day,lo,hi,lower_day,upper_day) AS (VALUES $values) ${branches.join(' UNION ALL ')}',
      args,
    );
  }

  Future<HistoryOptionPage> historyTypeOptions({
    FeedScope scope = const FeedScope.everyone(),
    String search = '',
    String? after,
    int limit = 25,
  }) async {
    _requireWritable();
    _historyOptionBounds(search, limit);
    final owner = scope.isEveryone
        ? 'person IN (SELECT id FROM person WHERE archived=0)'
        : 'person=?';
    final rows = await _rows(
      "SELECT type AS id FROM (SELECT r.type,a.person FROM administration a JOIN revision r ON r.record=a.id AND r.revision=a.revision UNION ALL SELECT item_type,person FROM daily_expectation) WHERE $owner AND type>? AND instr(lower(type),lower(?))>0 GROUP BY type ORDER BY type LIMIT ?",
      [if (!scope.isEveryone) scope.personId, after ?? '', search, limit + 1],
    );
    return HistoryOptionPage(
      options: rows
          .take(limit)
          .map(
            (r) =>
                HistoryOption(id: r['id'] as String, label: r['id'] as String),
          ),
      hasMore: rows.length > limit,
    );
  }

  Future<HistoryOptionPage> historyEventOptions({
    FeedScope scope = const FeedScope.everyone(),
    String search = '',
    String? after,
    int limit = 25,
  }) async {
    _requireWritable();
    _historyOptionBounds(search, limit);
    final rows = await _rows(
      "SELECT id,person,json_extract(snapshot,'\$.name') AS label FROM event_record WHERE ${scope.isEveryone ? 'person IN (SELECT id FROM person WHERE archived=0)' : 'person=?'} AND id>? AND instr(lower(json_extract(snapshot,'\$.name')),lower(?))>0 ORDER BY id LIMIT ?",
      [if (!scope.isEveryone) scope.personId, after ?? '', search, limit + 1],
    );
    return HistoryOptionPage(
      options: rows
          .take(limit)
          .map(
            (r) => HistoryOption(
              id: r['id'] as String,
              label: r['label'] as String,
              personId: r['person'] as String,
            ),
          ),
      hasMore: rows.length > limit,
    );
  }

  void _historyOptionBounds(String search, int limit) {
    if (search.length > 256 || limit < 1 || limit > 50) {
      throw const TimelineQueryException('invalid_limit');
    }
  }
}

Future<void> _writeHistoryEventBounds(_Database db, EventRecord event) async {
  int? start, end;
  var resolved = 1;
  try {
    final clock = IanaClock();
    clock.validateZone(event.zoneId);
    start = (event.actualStart ?? event.plannedStart)
        ?.resolve(clock, event.zoneId)
        ?.microsecondsSinceEpoch;
    end = (event.actualEnd ?? event.plannedEnd)
        ?.resolve(clock, event.zoneId, inclusiveEnd: true)
        ?.microsecondsSinceEpoch;
  } catch (_) {
    resolved = 0;
  }
  await db.customStatement(
    'INSERT INTO event_history_bounds VALUES (?,?,?,?,?) ON CONFLICT(event) DO UPDATE SET start=excluded.start,end=excluded.end,resolved=excluded.resolved',
    [event.id, event.personId, start, end, resolved],
  );
}

Future<void> _migrateHistoryV17(_Database db) async {
  for (final sql in historySchemaV17) {
    await db.customStatement(sql);
  }
  String? after;
  while (true) {
    final rows = await db
        .customSelect(
          'SELECT id,snapshot FROM daily_expectation WHERE id>? ORDER BY id LIMIT 256',
          variables: [drift.Variable(after ?? '')],
        )
        .get();
    if (rows.isEmpty) break;
    for (final row in rows) {
      final r = row.data;
      final e = decodeDailyExpectation(dailyObject(r['snapshot'] as String));
      final at =
          e.instant ??
          DisplayTime()
              .dayBounds(e.effectiveDate ?? e.identity.originalDate, e.zoneId)
              .start;
      await db.customStatement(
        'UPDATE daily_expectation SET occurs_at=?,effective_date=?,item_id=?,date_only=? WHERE id=?',
        [
          at.microsecondsSinceEpoch,
          (e.effectiveDate ?? e.identity.originalDate).toString(),
          e.itemId,
          e.instant == null ? 1 : 0,
          r['id'],
        ],
      );
    }
    after = rows.last.data['id'] as String;
  }
  after = null;
  while (true) {
    final groups = await db
        .customSelect(
          'SELECT id FROM combined_action WHERE id>? ORDER BY id LIMIT 256',
          variables: [drift.Variable(after ?? '')],
        )
        .get();
    if (groups.isEmpty) break;
    for (final group in groups) {
      final id = group.data['id'];
      final members = await db
          .customSelect(
            'SELECT COUNT(*) AS count,MIN(a.actual) AS lo,MAX(a.actual) AS hi,MIN(r.voided) AS vlo,MAX(r.voided) AS vhi FROM combined_member m JOIN administration a ON a.id=m.record AND a.person=m.person JOIN revision r ON r.record=a.id AND r.revision=a.revision WHERE m.action=?',
            variables: [drift.Variable(id as String)],
          )
          .getSingle();
      final r = members.data;
      if ((r['count'] as int) < 2 ||
          (r['count'] as int) > 16 ||
          r['lo'] != r['hi'] ||
          r['vlo'] != r['vhi']) {
        throw const TimelineModelException('combined_migration_review');
      }
      await db.customStatement(
        'UPDATE combined_action SET actual=? WHERE id=?',
        [r['lo'], id],
      );
    }
    after = groups.last.data['id'] as String;
  }
  after = null;
  while (true) {
    final events = await db
        .customSelect(
          'SELECT id,snapshot FROM event_record WHERE id>? ORDER BY id LIMIT 256',
          variables: [drift.Variable(after ?? '')],
        )
        .get();
    if (events.isEmpty) break;
    for (final e in events) {
      await _writeHistoryEventBounds(
        db,
        EventRecord.fromJson(
          Map<String, Object?>.from(
            jsonDecode(e.data['snapshot'] as String) as Map,
          ),
        ),
      );
    }
    after = events.last.data['id'] as String;
  }
}
