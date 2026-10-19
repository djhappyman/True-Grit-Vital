part of 'record_store.dart';

/// Current-revision chart input from the same protected store as History.
final class RecordStoreChartSource implements ChartObservationSource {
  const RecordStoreChartSource(this.store);
  final RecordStore store;

  @override
  Future<ChartObservationBatch> read(ChartSourceRequest request) =>
      store.chartObservations(request);
}

/// A History cursor bound to the full chart subject, including its ingredient.
///
/// The nested History cursor still enforces schema, dataset and timeline query
/// identity. Keeping this envelope prevents two ingredient series with the same
/// person/range from silently sharing a cursor.
final class ChartDrilldownCursor {
  ChartDrilldownCursor._(this.requestIdentity, this.timelineCursor);
  final String requestIdentity;
  final TimelineCursor timelineCursor;

  String encode() => base64Url
      .encode(
        utf8.encode(
          jsonEncode({
            'v': 1,
            'request': requestIdentity,
            'timeline': timelineCursor.encode(),
          }),
        ),
      )
      .replaceAll('=', '');

  factory ChartDrilldownCursor.decode(String value) {
    try {
      if (value.length > 8192) throw const FormatException();
      final data = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(value))),
      );
      if (data is! Map ||
          data['v'] is! int ||
          data['v'] != 1 ||
          data['request'] is! String ||
          !RegExp(r'^[a-f0-9]{64}$').hasMatch(data['request'] as String) ||
          data['timeline'] is! String) {
        throw const FormatException();
      }
      return ChartDrilldownCursor._(
        data['request'] as String,
        TimelineCursor.decode(data['timeline'] as String),
      );
    } catch (_) {
      throw const TimelineCursorException('cursor_malformed');
    }
  }
}

/// A complete parent-first source page, never a chart-total approximation.
final class ChartDrilldownPage {
  ChartDrilldownPage._(this.requestIdentity, this.timeline);
  final String requestIdentity;
  final TimelinePage timeline;

  List<TimelineEntry> get entries => timeline.entries;
  ChartDrilldownCursor? get next {
    final cursor = timeline.next;
    return cursor == null
        ? null
        : ChartDrilldownCursor._(requestIdentity, cursor);
  }
}

extension ChartRecordStore on RecordStore {
  /// Store changes start a new complete bounded snapshot for the same request.
  Stream<ChartObservationBatch> watchChartObservations(
    ChartSourceRequest request,
  ) => _watch(() => chartObservations(request));

  /// Reads at most 10,001 indexed current administrations in a single snapshot.
  /// The extra row only detects overflow; an overflow batch has no usable rows.
  Future<ChartObservationBatch> chartObservations(
    ChartSourceRequest request,
  ) async {
    _requireWritable();
    return _db.transaction(() async {
      await _chartGeneration();
      final rows = await _rows(
        '${RecordStore._current} WHERE a.person=? AND a.actual>=? AND a.actual<? ORDER BY a.actual DESC,a.id LIMIT ?',
        [
          request.personId,
          request.fromInstant.microsecondsSinceEpoch,
          request.beforeInstant.microsecondsSinceEpoch,
          ChartLimits.maxSourceRows + 1,
        ],
      );
      _requireWritable();
      final overflow = rows.length > ChartLimits.maxSourceRows;
      return ChartObservationBatch(
        personId: request.personId,
        fromInstant: request.fromInstant,
        beforeInstant: request.beforeInstant,
        schemaVersion: _db.schemaVersion,
        datasetGeneration: generation,
        truncated: overflow,
        observations: overflow
            ? const []
            : rows.map((row) {
                final record = _record(row);
                return ChartObservation(
                  source: ChartSourceRef(
                    recordId: record.id,
                    revision: record.revision,
                    combinedActionId: record.combinedActionId,
                  ),
                  personId: record.personId,
                  itemId: record.itemId,
                  itemName: record.name,
                  amount: record.actualAmount,
                  unit: record.actualUnit,
                  occurredAt: record.actualAt,
                  enteredAmountText:
                      record.originalEntry ?? record.enteredAmount,
                  enteredUnit: record.originalUnit ?? record.unit,
                  typeId: record.type,
                  typeName: record.type,
                  product: record.product,
                  isVoided: record.isVoided,
                );
              }),
      );
    });
  }

  /// Exact sources for one series/bucket. The ingredient predicate is applied
  /// to immutable saved labels before the page limit, never to current labels.
  Future<ChartDrilldownPage> chartDrilldown(
    ChartDrilldownRequest request, {
    ChartDrilldownCursor? cursor,
  }) async {
    _requireWritable();
    if (cursor != null && cursor.requestIdentity != request.identity) {
      throw const TimelineCursorException('cursor_expired');
    }
    final query = cursor == null
        ? request.timelineQuery
        : request.timelineQuery.withCursor(cursor.timelineCursor);
    return _db.transaction(() async {
      await _chartGeneration();
      query.cursor?.validateFor(
        query: query,
        schemaVersion: _db.schemaVersion,
        datasetGeneration: generation,
      );
      final predicate = _historyPredicate(query, skip: false);
      final ingredient = request.requiresIngredientPredicate;
      final savedLabel = ingredient
          ? ''' AND EXISTS (
        SELECT 1 FROM revision_product rp, json_each(rp.snapshot,'\$.label.components') ingredient
        WHERE rp.record=r.record AND rp.revision=r.revision
        AND json_extract(ingredient.value,'\$.ingredientId')=?
        AND json_extract(ingredient.value,'\$.massUnit')=?)'''
          : '';
      final status = switch (request.status) {
        TimelineStatus.all => '',
        TimelineStatus.recorded => ' AND r.voided=0',
        TimelineStatus.voided => ' AND r.voided=1',
        TimelineStatus.skipped => ' AND 0',
      };
      const join =
          'administration a JOIN revision r ON r.record=a.id AND r.person=a.person AND r.revision=a.revision LEFT JOIN revision_quantity q ON q.record=r.record AND q.revision=r.revision';
      final condition = '${predicate.sql}$status$savedLabel';
      final args = <Object?>[
        ...predicate.args,
        if (ingredient) ...[request.series.subject.id, request.series.unit],
      ];
      final branches = [
        _HistorySql(
          "SELECT a.id,a.person,a.actual AS at,'r:'||a.id AS key,'record' AS kind FROM $join WHERE $condition AND NOT EXISTS (SELECT 1 FROM combined_member cm WHERE cm.record=a.id)",
          args,
        ),
        _HistorySql(
          "SELECT g.id,g.person,g.actual AS at,'c:'||g.id AS key,'combined' AS kind FROM combined_action g WHERE g.person=? AND g.actual>=? AND g.actual<? AND EXISTS (SELECT 1 FROM combined_member cm JOIN ${join.replaceFirst('administration a', 'administration a ON a.id=cm.record AND a.person=cm.person')} WHERE cm.action=g.id AND $condition)",
          [
            request.series.personId,
            request.fromInstant.microsecondsSinceEpoch,
            request.beforeInstant.microsecondsSinceEpoch,
            ...args,
          ],
        ),
      ];
      final parents = <Map<String, Object?>>[];
      for (final branch in branches) {
        parents.addAll(
          await _rows(
            'SELECT * FROM (${branch.sql}) ${cursor == null ? '' : 'WHERE at<=? AND (at<? OR (at=? AND key>?))'} ORDER BY at DESC,id LIMIT ?',
            [
              ...branch.args,
              if (cursor != null) ...[
                cursor.timelineCursor.occurredAt.microsecondsSinceEpoch,
                cursor.timelineCursor.occurredAt.microsecondsSinceEpoch,
                cursor.timelineCursor.occurredAt.microsecondsSinceEpoch,
                cursor.timelineCursor.sortKey,
              ],
              query.limit + 1,
            ],
          ),
        );
      }
      parents.sort((a, b) {
        final time = (b['at'] as int).compareTo(a['at'] as int);
        return time != 0
            ? time
            : (a['key'] as String).compareTo(b['key'] as String);
      });
      final loaded = await _historyLoad(
        parents.take(query.limit).toList(),
        query,
      );
      final entries = loaded.map(
        (entry) => entry is! CombinedTimelineEntry
            ? entry
            : CombinedTimelineEntry(
                actionId: entry.actionId,
                components: [
                  for (final component in entry.components)
                    CombinedTimelineComponent(
                      position: component.position,
                      record: component.record,
                      matched: _chartRecordMatches(request, component.record),
                    ),
                ],
              ),
      );
      _requireWritable();
      return ChartDrilldownPage._(
        request.identity,
        TimelinePage(
          query: query,
          schemaVersion: _db.schemaVersion,
          datasetGeneration: generation,
          entries: entries,
          hasMore: parents.length > query.limit,
        ),
      );
    });
  }

  Future<void> _chartGeneration() async {
    if ((await _rows('SELECT generation FROM dataset')).single['generation'] !=
        generation) {
      throw const CommandConflict('generation');
    }
  }
}

bool _chartRecordMatches(ChartDrilldownRequest request, UseRecord record) {
  if (!request.requiresIngredientPredicate) {
    return record.itemId == request.series.subject.id &&
        record.actualUnit == request.series.unit;
  }
  return record.product?.label.components.any(
        (component) =>
            component.ingredientId == request.series.subject.id &&
            component.massUnit == request.series.unit,
      ) ??
      false;
}

/// Factual context with an explicit completeness flag when source bounds stop
/// the read. The UI must not present a partial hidden count as a complete count.
final class ChartContextBatch {
  ChartContextBatch({
    required Iterable<ChartAnnotation> annotations,
    required this.complete,
  }) : annotations = List.unmodifiable(annotations);
  final List<ChartAnnotation> annotations;
  final bool complete;
}

extension ChartContextStore on RecordStore {
  Future<ChartContextBatch> chartContext(ChartQuery query) async {
    _requireWritable();
    return _db.transaction(() async {
      await _chartGeneration();
      final request = query.sourceRequest;
      final focus = query.focus;
      List<String>? items;
      if (focus != null) {
        if (focus.subject.kind == ChartSubjectKind.item) {
          items = [focus.subject.id];
        } else {
          final rows = await _rows(
            '''SELECT DISTINCT a.item FROM administration a
            JOIN revision_product rp ON rp.record=a.id AND rp.revision=a.revision
            WHERE a.person=? AND a.actual>=? AND a.actual<? AND EXISTS (
              SELECT 1 FROM json_each(rp.snapshot,'\$.label.components') component
              WHERE json_extract(component.value,'\$.ingredientId')=?
              AND json_extract(component.value,'\$.massUnit')=?) LIMIT 129''',
            [
              request.personId,
              request.fromInstant.microsecondsSinceEpoch,
              request.beforeInstant.microsecondsSinceEpoch,
              focus.subject.id,
              focus.unit,
            ],
          );
          if (rows.length > 128) {
            return ChartContextBatch(annotations: [], complete: false);
          }
          items = rows.map((r) => r['item'] as String).toList();
          if (items.isEmpty) {
            return ChartContextBatch(annotations: [], complete: true);
          }
        }
      }
      final result = <ChartAnnotation>[];
      var complete = true;
      final seen = <String>{};
      void add(
        ChartAnnotationKind kind,
        String id,
        ChartAnnotationDate? at,
        String? label,
      ) {
        if (at == null) return;
        if (result.length >= 4000) {
          complete = false;
          return;
        }
        if (seen.add('${kind.name}:$id')) {
          result.add(
            ChartAnnotation(
              kind: kind,
              sourceId: id,
              personId: request.personId,
              at: at,
              label: label,
            ),
          );
        }
      }

      ChartAnnotationDate? eventDate(EventDate? date, String zone) {
        if (date == null) return null;
        return switch (date.precision) {
          EventDatePrecision.exact => ChartAnnotationDate.exact(
            DateTime.parse(date.value!),
          ),
          EventDatePrecision.day => ChartAnnotationDate.dateOnly(
            date: CivilDate.parse(date.value!),
            zoneId: zone,
          ),
          _ => () {
            complete = false;
            return null;
          }(),
        };
      }

      final lower = request.fromInstant
          .subtract(const Duration(days: 2))
          .microsecondsSinceEpoch;
      final upper = request.beforeInstant
          .add(const Duration(days: 2))
          .microsecondsSinceEpoch;
      final itemSql = items == null
          ? ''
          : ' AND p.item IN (${List.filled(items.length, '?').join(',')})';
      final eventRows = await _rows(
        '''SELECT e.snapshot,b.resolved FROM event_record e
        LEFT JOIN event_history_bounds b ON b.event=e.id AND b.person=e.person
        WHERE e.person=? AND (b.resolved IS NULL OR b.resolved=0 OR (b.start>=? AND b.start<?) OR (b.end>=? AND b.end<?))
        ${items == null ? '' : 'AND EXISTS (SELECT 1 FROM event_membership m WHERE m.event=e.id AND m.person=e.person AND m.item IN (${List.filled(items.length, '?').join(',')}))'}
        ORDER BY e.id LIMIT 1001''',
        [request.personId, lower, upper, lower, upper, ...?items],
      );
      if (eventRows.length > 1000) complete = false;
      for (final row in eventRows.take(1000)) {
        if (row['resolved'] != 1) complete = false;
        final event = EventRecord.fromJson(
          dailyObject(row['snapshot'] as String),
        );
        add(
          ChartAnnotationKind.eventStart,
          event.id,
          eventDate(event.actualStart ?? event.plannedStart, event.zoneId),
          event.name,
        );
        add(
          ChartAnnotationKind.eventEnd,
          event.id,
          eventDate(event.actualEnd ?? event.plannedEnd, event.zoneId),
          event.name,
        );
      }
      final firstDate = DisplayTime()
          .instant(
            request.fromInstant.subtract(const Duration(days: 2)),
            query.viewport.zoneId,
          )
          .dateText;
      final lastDate = DisplayTime()
          .instant(
            request.beforeInstant.add(const Duration(days: 2)),
            query.viewport.zoneId,
          )
          .dateText;
      final versions = await _rows(
        '''SELECT v.id,v.snapshot,EXISTS(SELECT 1 FROM phase_plan f WHERE f.plan=p.id AND f.person=p.person) AS phased FROM daily_version v
        JOIN daily_plan p ON p.id=v.plan AND p.person=v.person
        WHERE p.person=? $itemSql AND ((v.start>=? AND v.start<?) OR (v.end>=? AND v.end<?)
          OR (json_type(v.snapshot,'\$.effectiveFrom')='integer' AND json_extract(v.snapshot,'\$.effectiveFrom')>=? AND json_extract(v.snapshot,'\$.effectiveFrom')<?)
          OR json_type(v.snapshot,'\$.effectiveFrom') NOT IN ('integer','null')
          OR (json_type(v.snapshot,'\$.effectiveUntil')='integer' AND json_extract(v.snapshot,'\$.effectiveUntil')>=? AND json_extract(v.snapshot,'\$.effectiveUntil')<?)
          OR json_type(v.snapshot,'\$.effectiveUntil') NOT IN ('integer','null')
          OR EXISTS (SELECT 1 FROM json_each(v.snapshot,'\$.pauses') pause
            WHERE (json_extract(pause.value,'\$.start')>=? AND json_extract(pause.value,'\$.start')<?)
            OR (json_extract(pause.value,'\$.resume')>=? AND json_extract(pause.value,'\$.resume')<?)
            OR json_type(pause.value,'\$.start') IS NOT 'integer'
            OR json_type(pause.value,'\$.resume') NOT IN ('integer','null')))
        ORDER BY v.start,v.id LIMIT 1001''',
        [
          request.personId,
          ...?items,
          firstDate,
          lastDate,
          firstDate,
          lastDate,
          lower,
          upper,
          lower,
          upper,
          lower,
          upper,
          lower,
          upper,
        ],
      );
      if (versions.length > 1000) complete = false;
      for (final row in versions.take(1000)) {
        final DailyPlanVersion plan;
        try {
          plan = decodeDailyPlan(dailyObject(row['snapshot'] as String));
        } on Object {
          // A saved but unsupported boundary is not a complete context read.
          complete = false;
          continue;
        }
        // Daily versions do not snapshot an item name. A live catalogue name
        // must not be presented as a historical saved annotation label.
        const String? name = null;
        final zone = plan.zoneBasis is FixedHome
            ? (plan.zoneBasis as FixedHome).zoneId
            : null;
        ChartAnnotationDate? civil(CivilDate date) {
          if (zone == null) {
            complete = false;
            return null;
          }
          return ChartAnnotationDate.dateOnly(date: date, zoneId: zone);
        }

        final start = plan.effectiveFrom == null
            ? civil(plan.start)
            : ChartAnnotationDate.exact(plan.effectiveFrom!);
        add(ChartAnnotationKind.planChanged, plan.versionId, start, name);
        if (row['phased'] == 1) {
          add(ChartAnnotationKind.phaseStart, plan.versionId, start, name);
        }
        final end = plan.effectiveUntil != null
            ? ChartAnnotationDate.exact(plan.effectiveUntil!)
            : plan.endExclusive == null
            ? null
            : civil(plan.endExclusive!.addDays(-1));
        if (row['phased'] == 1) {
          add(ChartAnnotationKind.phaseEnd, plan.versionId, end, name);
        } else {
          add(ChartAnnotationKind.planEnd, plan.versionId, end, name);
        }
        for (var index = 0; index < plan.pauses.length; index++) {
          if (result.length >= 4000) {
            complete = false;
            break;
          }
          final pause = plan.pauses[index], id = '${plan.versionId}:$index';
          add(
            ChartAnnotationKind.pauseStart,
            id,
            ChartAnnotationDate.exact(pause.start),
            name,
          );
          if (pause.resume case final resume?) {
            add(
              ChartAnnotationKind.pauseEnd,
              id,
              ChartAnnotationDate.exact(resume),
              name,
            );
          }
        }
      }
      final ends = await _rows(
        '''SELECT p.id,json_extract(f.snapshot,'\$.end') AS ending FROM phase_plan f
        JOIN daily_plan p ON p.id=f.plan AND p.person=f.person
        WHERE p.person=? $itemSql AND ((json_extract(f.snapshot,'\$.end.instant')>=? AND json_extract(f.snapshot,'\$.end.instant')<?)
          OR (json_type(f.snapshot,'\$.end') NOT IN ('null') AND json_type(f.snapshot,'\$.end.instant') IS NOT 'integer'))
        ORDER BY p.id LIMIT 1001''',
        [request.personId, ...?items, lower, upper],
      );
      if (ends.length > 1000) complete = false;
      for (final row in ends.take(1000)) {
        try {
          final end = dailyObject(row['ending'] as String);
          add(
            ChartAnnotationKind.planEnd,
            row['id'] as String,
            end['lastDate'] == null
                ? ChartAnnotationDate.exact(
                    DateTime.fromMicrosecondsSinceEpoch(
                      end['instant'] as int,
                      isUtc: true,
                    ),
                  )
                : ChartAnnotationDate.dateOnly(
                    date: CivilDate.parse(end['lastDate'] as String),
                    zoneId: end['zone'] as String,
                  ),
            null,
          );
        } on Object {
          complete = false;
        }
      }
      _requireWritable();
      return ChartContextBatch(annotations: result, complete: complete);
    });
  }
}
