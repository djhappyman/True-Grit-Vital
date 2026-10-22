part of 'record_store.dart';

/// A latest-value read is one bounded marker page, not a bounded record
/// window. The page keeps the newest dated current result for every marker,
/// however far back its newest result sits. Comparison and sparkline work is
/// limited per marker and disclosed by the presentation.
const supportingLatestCandidateLimit = 48;

/// The saved collection filters used for latest values. Collection date is the
/// only date basis: report and entry dates cannot position a measurement. Only
/// known dates and current, non-voided records are eligible.
final class SupportingLatestQuery {
  SupportingLatestQuery({
    required this.personId,
    this.kind,
    this.fromDate,
    this.beforeDate,
    this.itemId,
    this.eventId,
    this.displayZone = 'UTC',
    this.markerLimit = 24,
  }) {
    supportingText(personId, 'latest_person');
    supportingText(displayZone, 'latest_zone', max: 256);
    if (markerLimit < 1) {
      throw const SupportingLimitException('latest_marker_limit');
    }
    if (fromDate != null &&
        beforeDate != null &&
        beforeDate!.compareTo(fromDate!) <= 0) {
      throw ArgumentError('latest_range');
    }
  }
  final String personId, displayZone;
  final SupportingRecordKind? kind;
  final CivilDate? fromDate, beforeDate;
  final String? itemId, eventId;
  final int markerLimit;
}

/// One saved result with the current revision around it. The revision keeps the
/// complete saved header and the selected result so original units, ranges,
/// flags, provenance and dates are not recomputed.
final class SupportingLatestOccurrence {
  const SupportingLatestOccurrence({
    required this.record,
    required this.result,
    required this.position,
  });
  final SupportingRevision record;
  final LabResultSnapshot result;
  final int position;
}

/// The newest occurrence for one marker plus a bounded newest-first sample of
/// its dated occurrences. [candidatesLimited] is true when older occurrences
/// exist outside the sample, so an absent comparable value is never claimed as
/// a global absence.
final class SupportingLatestMarker {
  SupportingLatestMarker._({
    required this.latest,
    required Iterable<SupportingLatestOccurrence> candidates,
    required this.candidatesLimited,
  }) : candidates = List.unmodifiable(candidates);
  final SupportingLatestOccurrence latest;
  final List<SupportingLatestOccurrence> candidates;
  final bool candidatesLimited;
}

final class SupportingLatestPage {
  SupportingLatestPage._({
    required Iterable<SupportingLatestMarker> markers,
    required this.recordCount,
    required this.markerCount,
  }) : markers = List.unmodifiable(markers);
  final List<SupportingLatestMarker> markers;

  /// All eligible dated current records in the current filters, not just the
  /// marker page. The count is factual even when the marker page is smaller.
  final int recordCount;
  final int markerCount;
}

final class _SupportingLatestRow {
  const _SupportingLatestRow({
    required this.occurrence,
    required this.day,
    required this.instant,
    required this.recordId,
  });
  final SupportingLatestOccurrence occurrence;
  final CivilDate day;
  final DateTime? instant;
  final String recordId;
}

extension SupportingLatestStore on RecordStore {
  /// Reads one marker page across the complete filtered saved collection.
  ///
  /// The SQL bounds the marker page and the per-marker comparison sample, then
  /// reads only the current revision headers and result snapshots that the page
  /// uses. It never loads the collection's full record payload into memory.
  Future<SupportingLatestPage> supportingLatest(
    SupportingLatestQuery query,
  ) async {
    _requireWritable();
    return _db.transaction(() async {
      await _chartGeneration();
      final matched = _supportingLatestMatched(query);
      final counts = (await _rows(
        '${matched.sql} SELECT (SELECT COUNT(*) FROM matched) AS records, '
        '(SELECT COUNT(DISTINCT r.metric) FROM supporting_result r '
        'JOIN matched m ON m.id=r.record AND m.person=r.person '
        'AND m.revision=r.revision WHERE r.person=?) AS markers',
        [...matched.args, query.personId],
      )).single;
      final recordCount = counts['records'] as int,
          markerCount = counts['markers'] as int;
      if (markerCount == 0) {
        return SupportingLatestPage._(
          markers: const [],
          recordCount: recordCount,
          markerCount: 0,
        );
      }
      final markerRows = await _rows(
        '${matched.sql} SELECT DISTINCT r.metric AS metric, mtr.name AS name '
        'FROM supporting_result r '
        'JOIN matched m ON m.id=r.record AND m.person=r.person '
        'AND m.revision=r.revision '
        'JOIN supporting_metric mtr ON mtr.id=r.metric '
        'AND mtr.person=r.person '
        'WHERE r.person=? ORDER BY mtr.name,r.metric LIMIT ?',
        [...matched.args, query.personId, query.markerLimit],
      );
      final metrics = [for (final row in markerRows) row['metric'] as String];
      if (metrics.isEmpty) {
        return SupportingLatestPage._(
          markers: const [],
          recordCount: recordCount,
          markerCount: markerCount,
        );
      }
      final ids = List.filled(metrics.length, '?').join(',');
      final candidates = _supportingLatestCandidates(
        matched,
        personId: query.personId,
        metrics: metrics,
        ids: ids,
      );
      final candidate = await _rows(candidates.sql, candidates.args);
      final rows = <String, List<_SupportingLatestRow>>{};
      final limited = <String>{};
      for (final row in candidate) {
        final metric = row['metric'] as String, rn = row['rn'] as int;
        if (rn > supportingLatestCandidateLimit) {
          limited.add(metric);
          continue;
        }
        final at = row['collection_at'] as int?,
            dayText = row['collection_day'] as String?;
        final instant = at == null
            ? null
            : DateTime.fromMicrosecondsSinceEpoch(at, isUtc: true);
        final day = instant == null
            ? CivilDate.parse(dayText!)
            : DisplayTime().instant(instant, query.displayZone).civilDate;
        final record = _supportingLatestRevision(row);
        (rows[metric] ??= []).add(
          _SupportingLatestRow(
            occurrence: SupportingLatestOccurrence(
              record: record,
              result: LabResultSnapshot.fromJson(
                _supportingObject(jsonDecode(row['result_snapshot'] as String)),
              ),
              position: row['position'] as int,
            ),
            day: day,
            instant: instant,
            recordId: record.id.id,
          ),
        );
      }
      final markers = <SupportingLatestMarker>[];
      for (final metric in metrics) {
        final occurrences = rows[metric];
        if (occurrences == null || occurrences.isEmpty) continue;
        occurrences.sort(_supportingLatestCompare);
        final limitedHere =
            limited.contains(metric) ||
            occurrences.length > supportingLatestCandidateLimit;
        final kept = occurrences
            .take(supportingLatestCandidateLimit)
            .map((row) => row.occurrence)
            .toList(growable: false);
        if (kept.isEmpty) continue;
        markers.add(
          SupportingLatestMarker._(
            latest: kept.first,
            candidates: kept,
            candidatesLimited: limitedHere,
          ),
        );
      }
      return SupportingLatestPage._(
        markers: markers,
        recordCount: recordCount,
        markerCount: markerCount,
      );
    });
  }

  Stream<SupportingLatestPage> watchSupportingLatest(
    SupportingLatestQuery query,
  ) => _watch(() => supportingLatest(query));
}

String _supportingLatestContext(String column) =>
    'EXISTS(SELECT 1 FROM supporting_context c WHERE c.record=s.id '
    'AND c.person=s.person AND c.revision=s.revision AND c.$column=?)';

({String sql, List<Object?> args}) _supportingLatestMatched(
  SupportingLatestQuery query,
) {
  final common = <String>['s.person=?', 's.voided=0'],
      commonArgs = <Object?>[query.personId];
  if (query.kind != null) {
    common.add('s.kind=?');
    commonArgs.add(query.kind!.name);
  }
  if (query.itemId != null) {
    common.add(_supportingLatestContext('item'));
    commonArgs.add(query.itemId);
  }
  if (query.eventId != null) {
    common.add(_supportingLatestContext('event'));
    commonArgs.add(query.eventId);
  }
  final exact = <String>[...common, 's.collection_at IS NOT NULL'],
      exactArgs = <Object?>[...commonArgs],
      civil = <String>[
        ...common,
        's.collection_at IS NULL',
        's.collection_day IS NOT NULL',
      ],
      civilArgs = <Object?>[...commonArgs];
  if (query.fromDate != null) {
    exact.add('s.collection_at>=?');
    exactArgs.add(
      DisplayTime()
          .dayBounds(query.fromDate!, query.displayZone)
          .start
          .microsecondsSinceEpoch,
    );
    civil.add('s.collection_day>=?');
    civilArgs.add(query.fromDate.toString());
  }
  if (query.beforeDate != null) {
    exact.add('s.collection_at<?');
    exactArgs.add(
      DisplayTime()
          .dayBounds(query.beforeDate!, query.displayZone)
          .start
          .microsecondsSinceEpoch,
    );
    civil.add('s.collection_day<?');
    civilArgs.add(query.beforeDate.toString());
  }
  const columns = 's.id,s.person,s.revision,s.collection_at,s.collection_day';
  return (
    sql:
        'WITH matched AS MATERIALIZED ('
        'SELECT $columns FROM supporting_record s '
        'INDEXED BY supporting_collection_instant WHERE ${exact.join(' AND ')} '
        'UNION ALL '
        'SELECT $columns FROM supporting_record s '
        'INDEXED BY supporting_collection_civil WHERE ${civil.join(' AND ')} '
        ') ',
    args: [...exactArgs, ...civilArgs],
  );
}

({String sql, List<Object?> args}) _supportingLatestCandidates(
  ({String sql, List<Object?> args}) matched, {
  required String personId,
  required List<String> metrics,
  required String ids,
}) {
  final select =
      'SELECT r.record AS record,r.person AS person,r.revision AS revision,'
      'r.id AS result_id,r.position AS position,r.metric AS metric,'
      'r.snapshot AS result_snapshot,v.header AS header,'
      'm.collection_at AS collection_at,m.collection_day AS collection_day,'
      'ROW_NUMBER() OVER (PARTITION BY r.metric ORDER BY %s) AS rn '
      'FROM supporting_result r '
      'JOIN matched m ON m.id=r.record AND m.person=r.person '
      'AND m.revision=r.revision '
      'JOIN supporting_revision v ON v.record=m.id AND v.person=m.person '
      'AND v.revision=m.revision '
      'WHERE r.person=? AND r.metric IN ($ids) AND %s';
  final exact = select
          .replaceFirst('%s', 'm.collection_at DESC,m.id,r.position')
          .replaceFirst('%s', 'm.collection_at IS NOT NULL'),
      civil = select
          .replaceFirst('%s', 'm.collection_day DESC,m.id,r.position')
          .replaceFirst('%s', 'm.collection_at IS NULL');
  final args = [
    ...matched.args,
    personId,
    ...metrics,
    personId,
    ...metrics,
    supportingLatestCandidateLimit + 1,
  ];
  return (
    sql:
        '${matched.sql}, candidates AS ($exact UNION ALL $civil) '
        'SELECT * FROM candidates WHERE rn<=? ORDER BY metric,rn',
    args: args,
  );
}

SupportingRevision _supportingLatestRevision(Map<String, Object?> row) {
  final header = _supportingObject(jsonDecode(row['header'] as String));
  final snapshot = _supportingObject(header['snapshot']);
  snapshot['results'] = [jsonDecode(row['result_snapshot'] as String)];
  header['snapshot'] = snapshot;
  return SupportingRevision.fromJson(header);
}

int _supportingLatestCompare(_SupportingLatestRow a, _SupportingLatestRow b) {
  final day = b.day.compareTo(a.day);
  if (day != 0) return day;
  final aAt = a.instant, bAt = b.instant;
  if (aAt != null && bAt != null) {
    final instant = bAt.compareTo(aAt);
    if (instant != 0) return instant;
  } else if (aAt != null) {
    // Within one displayed day an exact instant precedes a supplied day-only
    // record, matching the collection chronology.
    return -1;
  } else if (bAt != null) {
    return 1;
  }
  final record = a.recordId.compareTo(b.recordId);
  if (record != 0) return record;
  return a.occurrence.position.compareTo(b.occurrence.position);
}
