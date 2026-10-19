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
    final certain =
        result.unit != null &&
        provenance.laboratoryId != null &&
        provenance.methodId != null &&
        provenance.specimenId != null;
    return SupportingComparisonKey._(
      personId: record.id.personId,
      metricId: result.metricId,
      kind: record.kind == SupportingRecordKind.labPanel
          ? SupportingMetricKind.lab
          : SupportingMetricKind.observation,
      unit: result.unit,
      laboratoryId: provenance.laboratoryId,
      methodId: provenance.methodId,
      specimenId: provenance.specimenId,
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
  SupportingTrendGroup._(this.key, Iterable<SupportingTrendEntry> entries)
    : entries = List.unmodifiable(entries);
  final SupportingComparisonKey key;
  final List<SupportingTrendEntry> entries;
  bool get canConnect => key.certain;

  /// No line crosses a censored, missing or qualitative result. An uncertain
  /// identity supports isolated points only, even if values happen to match.
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
      current.add(entry);
    }
    if (current.isNotEmpty) runs.add(List.unmodifiable(current));
    return List.unmodifiable(runs);
  }
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
        SupportingDateBasis.entry => SupportingDate.exact(
          record.enteredAt,
          zoneId: 'UTC',
          utcOffsetMinutes: 0,
        ),
      };
      final projected = date.precision == SupportingDatePrecision.exact
          ? DisplayTime().instant(date.instant!, query.displayZone)
          : null;
      final day = date.precision == SupportingDatePrecision.day
          ? date.civilDate
          : projected?.civilDate;
      for (final result in record.snapshot.results) {
        if (result.metricId != query.metricId) continue;
        if (++seen > SupportingLimits.maxTrendRows) {
          throw const SupportingLimitException('trend_rows');
        }
        final group = SupportingComparisonKey.forResult(record, result);
        if (query.comparisonGroup != null &&
            query.comparisonGroup != group.identity) {
          continue;
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
          continue;
        }
        if (day.compareTo(query.fromDate) >= 0 &&
            day.compareTo(query.beforeDate) < 0) {
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
    return SupportingTrendPage._(
      query: query,
      schemaVersion: schemaVersion,
      datasetGeneration: datasetGeneration,
      requestGeneration: requestGeneration,
      groups: [
        for (final key in keys) SupportingTrendGroup._(key, grouped[key]!),
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
    return 1;
  } else if (bi != null) {
    return -1;
  }
  return a.identity.compareTo(b.identity);
}
