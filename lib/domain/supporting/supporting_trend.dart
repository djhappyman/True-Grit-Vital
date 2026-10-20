import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../history/display_time.dart';
import '../scheduling/daily_plan.dart' show CivilDate;
import '../stock/exact_amount.dart';
import 'supporting_date.dart';
import 'supporting_record.dart';
import 'supporting_value.dart';

enum SupportingDateBasis { collection, report, entry }

String _identity(Object value) =>
    sha256.convert(utf8.encode(jsonEncode(value))).toString();

String? _sourceIdentity(String? explicitId, String? savedText) {
  if (explicitId != null && explicitId.trim().isNotEmpty) {
    return 'id:$explicitId';
  }
  if (savedText != null && savedText.trim().isNotEmpty) {
    return 'text:$savedText';
  }
  return null;
}

final class SupportingTrendQuery {
  SupportingTrendQuery({
    required this.personId,
    required this.metricId,
    required this.fromDate,
    required this.beforeDate,
    this.dateBasis = SupportingDateBasis.collection,
    this.displayZone = 'UTC',
    this.comparisonGroup,
  }) {
    supportingText(personId, 'trend_person');
    supportingText(metricId, 'trend_metric');
    supportingText(displayZone, 'trend_zone', max: 256);
    supportingOptionalText(comparisonGroup, 'trend_group');
    if (beforeDate.compareTo(fromDate) <= 0) throw ArgumentError('trend_range');
    if (dateBasis == SupportingDateBasis.entry) {
      // Entry time is audit provenance. It cannot position a measurement.
      throw ArgumentError('trend_basis');
    }
  }
  final String personId, metricId, displayZone;
  final CivilDate fromDate, beforeDate;
  final SupportingDateBasis dateBasis;
  final String? comparisonGroup;
  Map<String, Object?> toJson() => {
    'personId': personId,
    'metricId': metricId,
    'fromDate': fromDate.toString(),
    'beforeDate': beforeDate.toString(),
    'dateBasis': dateBasis.name,
    'displayZone': displayZone,
    'comparisonGroup': comparisonGroup,
  };
  String get identity => _identity(toJson());
  factory SupportingTrendQuery.fromJson(Map<String, dynamic> j) =>
      SupportingTrendQuery(
        personId: j['personId'] as String,
        metricId: j['metricId'] as String,
        fromDate: CivilDate.parse(j['fromDate'] as String),
        beforeDate: CivilDate.parse(j['beforeDate'] as String),
        dateBasis: SupportingDateBasis.values.byName(j['dateBasis'] as String),
        displayZone: j['displayZone'] as String,
        comparisonGroup: j['comparisonGroup'] as String?,
      );
}

/// Technical organisation, never an assertion of clinical interchangeability.
final class SupportingComparisonKey {
  SupportingComparisonKey._({
    required this.personId,
    required this.metricId,
    required this.kind,
    required this.unit,
    required this.laboratoryId,
    required this.methodId,
    required this.specimenId,
    required this.uncertainSource,
  });
  factory SupportingComparisonKey.forResult(
    SupportingRevision record,
    LabResultSnapshot result,
  ) {
    final provenance = result.provenance ?? record.snapshot.provenance;
    // A stable explicit identity wins. When a manual record supplies only the
    // saved source words, those exact words are the local identity. Nothing is
    // trimmed, case-folded or fuzzy-matched: near names stay separate.
    final laboratory = _sourceIdentity(
      provenance.laboratoryId,
      provenance.laboratoryName,
    );
    final method = _sourceIdentity(provenance.methodId, provenance.methodText);
    final specimen = _sourceIdentity(
      provenance.specimenId,
      provenance.specimenText,
    );
    final certain =
        result.unit != null &&
        laboratory != null &&
        method != null &&
        specimen != null;
    return SupportingComparisonKey._(
      personId: record.id.personId,
      metricId: result.metricId,
      // Persisted metric identity owns its person and kind. The store rejects a
      // metric whose owner or kind differs from the parent record, so the
      // parent's persisted kind is the comparison kind.
      kind: record.kind == SupportingRecordKind.labPanel
          ? SupportingMetricKind.lab
          : SupportingMetricKind.observation,
      unit: result.unit,
      laboratoryId: laboratory,
      methodId: method,
      specimenId: specimen,
      uncertainSource: certain ? null : jsonEncode([record.id.id, result.id]),
    );
  }
  final String personId, metricId;
  final SupportingMetricKind kind;
  final String? unit, laboratoryId, methodId, specimenId, uncertainSource;
  bool get certain => uncertainSource == null;
  String get identity => _identity([
    personId,
    metricId,
    kind.name,
    unit,
    laboratoryId,
    methodId,
    specimenId,
    uncertainSource,
  ]);
  @override
  bool operator ==(Object other) =>
      other is SupportingComparisonKey && identity == other.identity;
  @override
  int get hashCode => identity.hashCode;
}

final class SupportingTrendEntry {
  SupportingTrendEntry._({
    required this.record,
    required this.result,
    required this.date,
    required this.day,
    required this.exactInstant,
    required this.groupKey,
    required this.positionZoneId,
    required this.positionZoneFallback,
  });
  final SupportingRevision record;
  final LabResultSnapshot result;
  final SupportingDate date;
  final CivilDate? day;
  final DateTime? exactInstant;
  final SupportingComparisonKey groupKey;
  final String? positionZoneId;
  final bool positionZoneFallback;
  ExactAmount? get numericValue =>
      result.value.isExactNumeric ? result.value.exactAmount : null;
  bool get isGap => numericValue == null;
  String get identity => jsonEncode([
    record.id.personId,
    record.id.id,
    record.revision,
    result.id,
  ]);
}

final class SupportingTrendGroup {
  SupportingTrendGroup._(
    this.key,
    Iterable<SupportingTrendEntry> entries, {
    this.hasUnpositionedGap = false,
  }) : entries = List.unmodifiable(entries);
  final SupportingComparisonKey key;
  final List<SupportingTrendEntry> entries;

  /// True when a matching result for this identity has no full date, so the
  /// plotted line cannot claim to be the complete series.
  final bool hasUnpositionedGap;
  bool get canConnect => key.certain;

  /// No line crosses a censored, missing or qualitative result. An uncertain
  /// identity supports isolated points only, even if values happen to match.
  /// Repeated same-day day-only points and one repeated instant stay separate
  /// markers rather than becoming a vertical line.
  List<List<SupportingTrendEntry>> get runs {
    final runs = <List<SupportingTrendEntry>>[];
    var current = <SupportingTrendEntry>[];
    for (final entry in entries) {
      if (entry.isGap) {
        if (current.isNotEmpty) runs.add(List.unmodifiable(current));
        current = [];
        continue;
      }
      if (!canConnect) {
        runs.add(List.unmodifiable([entry]));
        continue;
      }
      if (current.isNotEmpty && _repeatsPosition(current.last, entry)) {
        runs.add(List.unmodifiable(current));
        current = [];
      }
      current.add(entry);
    }
    if (current.isNotEmpty) runs.add(List.unmodifiable(current));
    return List.unmodifiable(runs);
  }
}

bool _repeatsPosition(
  SupportingTrendEntry previous,
  SupportingTrendEntry next,
) {
  if (previous.day != next.day) return false;
  if (previous.exactInstant == null && next.exactInstant == null) return true;
  return previous.exactInstant != null &&
      previous.exactInstant == next.exactInstant;
}

final class SupportingTrendToken {
  const SupportingTrendToken({
    required this.queryIdentity,
    required this.schemaVersion,
    required this.datasetGeneration,
    required this.requestGeneration,
  });
  final String queryIdentity, datasetGeneration;
  final int schemaVersion, requestGeneration;
  bool matches(SupportingTrendToken other) =>
      queryIdentity == other.queryIdentity &&
      schemaVersion == other.schemaVersion &&
      datasetGeneration == other.datasetGeneration &&
      requestGeneration == other.requestGeneration;
}

/// View-owned sequencing only; lock, disposal, person or dataset changes call
/// invalidate. Even a repeated same query receives a new request generation.
final class SupportingTrendRequestGuard {
  int _sequence = 0;
  SupportingTrendToken? _current;
  SupportingTrendToken begin(
    SupportingTrendQuery query, {
    required int schemaVersion,
    required String datasetGeneration,
  }) => _current = SupportingTrendToken(
    queryIdentity: query.identity,
    schemaVersion: schemaVersion,
    datasetGeneration: datasetGeneration,
    requestGeneration: ++_sequence,
  );
  bool accepts(SupportingTrendToken token) => _current?.matches(token) == true;
  void invalidate() {
    _sequence++;
    _current = null;
  }
}

/// A complete bounded measurement window, never a total, mean or sample.
/// The adapter supplies current revisions for the requested dates plus unknown
/// dates. Overflow rejects the whole model before a partial plot can publish.
final class SupportingTrendPage {
  SupportingTrendPage._({
    required this.query,
    required this.schemaVersion,
    required this.datasetGeneration,
    required this.requestGeneration,
    required Iterable<SupportingTrendGroup> groups,
    required Iterable<SupportingTrendEntry> unpositioned,
    required this.sourceCount,
  }) : groups = List.unmodifiable(groups),
       unpositioned = List.unmodifiable(unpositioned);
  factory SupportingTrendPage.build({
    required SupportingTrendQuery query,
    required Iterable<SupportingRevision> records,
    required int schemaVersion,
    required String datasetGeneration,
    int requestGeneration = 0,
  }) {
    if (schemaVersion < 1 || requestGeneration < 0) {
      throw ArgumentError('trend_generation');
    }
    supportingText(datasetGeneration, 'trend_dataset');
    final entries = <SupportingTrendEntry>[],
        unpositioned = <SupportingTrendEntry>[];
    final parents = <String>{};
    var seen = 0;
    for (final record in records) {
      if (record.id.personId != query.personId) {
        throw ArgumentError('trend_owner');
      }
      if (!parents.add(record.id.id)) {
        throw ArgumentError('trend_duplicate_revision');
      }
      if (record.isVoided) continue;
      final date = switch (query.dateBasis) {
        SupportingDateBasis.collection => record.snapshot.collectionDate,
        SupportingDateBasis.report => record.snapshot.reportDate,
        SupportingDateBasis.entry => throw ArgumentError('trend_basis'),
      };
      final projected = date.precision == SupportingDatePrecision.exact
          ? DisplayTime().instant(date.instant!, query.displayZone)
          : null;
      final day = date.precision == SupportingDatePrecision.day
          ? date.civilDate
          : projected?.civilDate;
      for (final result in record.snapshot.results) {
        if (result.metricId != query.metricId) continue;
        final group = SupportingComparisonKey.forResult(record, result);
        if (query.comparisonGroup != null &&
            query.comparisonGroup != group.identity) {
          continue;
        }
        // Cap only rows that can actually contribute. Rows outside the
        // requested window or comparison group must not consume the bound.
        final positioned =
            day != null &&
            day.compareTo(query.fromDate) >= 0 &&
            day.compareTo(query.beforeDate) < 0;
        if (day != null && !positioned) continue;
        if (++seen > SupportingLimits.maxTrendRows) {
          throw const SupportingLimitException('trend_rows');
        }
        final entry = SupportingTrendEntry._(
          record: record,
          result: result,
          date: date,
          day: day,
          exactInstant: date.instant,
          groupKey: group,
          positionZoneId: projected?.zoneId ?? date.zoneId,
          positionZoneFallback: projected?.zoneFallback ?? false,
        );
        if (day == null) {
          unpositioned.add(entry);
        } else {
          entries.add(entry);
        }
      }
    }
    entries.sort(_compare);
    unpositioned.sort((a, b) => a.identity.compareTo(b.identity));
    final grouped = <SupportingComparisonKey, List<SupportingTrendEntry>>{};
    for (final entry in entries) {
      grouped.putIfAbsent(entry.groupKey, () => []).add(entry);
    }
    final keys = grouped.keys.toList()
      ..sort((a, b) => a.identity.compareTo(b.identity));
    final unpositionedKeys = {for (final entry in unpositioned) entry.groupKey};
    return SupportingTrendPage._(
      query: query,
      schemaVersion: schemaVersion,
      datasetGeneration: datasetGeneration,
      requestGeneration: requestGeneration,
      groups: [
        for (final key in keys)
          SupportingTrendGroup._(
            key,
            grouped[key]!,
            hasUnpositionedGap: unpositionedKeys.contains(key),
          ),
      ],
      unpositioned: unpositioned,
      sourceCount: entries.length + unpositioned.length,
    );
  }
  final SupportingTrendQuery query;
  final int schemaVersion, requestGeneration, sourceCount;
  final String datasetGeneration;
  final List<SupportingTrendGroup> groups;
  final List<SupportingTrendEntry> unpositioned;
  SupportingTrendToken get token => SupportingTrendToken(
    queryIdentity: query.identity,
    schemaVersion: schemaVersion,
    datasetGeneration: datasetGeneration,
    requestGeneration: requestGeneration,
  );
}

int _compare(SupportingTrendEntry a, SupportingTrendEntry b) {
  final day = a.day!.compareTo(b.day!);
  if (day != 0) return day;
  final ai = a.exactInstant, bi = b.exactInstant;
  if (ai != null && bi != null) {
    final at = ai.compareTo(bi);
    if (at != 0) return at;
  } else if (ai != null) {
    // Within one shown day an exact instant precedes a supplied day-only
    // record, which has no asserted clock time. This matches feed chronology.
    return -1;
  } else if (bi != null) {
    return 1;
  }
  return a.identity.compareTo(b.identity);
}
