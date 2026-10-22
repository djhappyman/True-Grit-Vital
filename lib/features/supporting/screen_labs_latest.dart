import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_lock.dart';
import '../../app/storage.dart';
import '../../data/record_store.dart';

/// A marker page is a bounded read, but it is not a whole-collection cap. The
/// collection exposes more markers on request while each request stays bounded.
const screenLabsMarkerPageSize = 24;

/// Sparklines keep a recent sample per marker. The section states this exact
/// coverage so a short line is never presented as the full saved history.
const screenLabsSparkSampleLimit = 24;

/// Bounded saved-context name reads. A page with more distinct links keeps the
/// resolved ones and discloses that some names are not shown.
const screenLabsProjectionLinkLimit = 24;

/// One resolved saved context link, opened by the existing item/event route.
final class ScreenLabsLink {
  const ScreenLabsLink({
    required this.kind,
    required this.id,
    required this.name,
  });
  final SupportingContextKind kind;
  final String id, name;
}

/// One dated exact numeric point in the bounded latest-value trend. The point
/// keeps the saved record and result so the table can show its exact source
/// words instead of a recomputed value.
final class ScreenLabsSparkPoint {
  const ScreenLabsSparkPoint({
    required this.record,
    required this.result,
    required this.day,
  });
  final SupportingRevision record;
  final LabResultSnapshot result;
  final CivilDate day;
}

/// A trend through actual dated exact numeric records with one comparison
/// identity. Segments are separated by a censored, qualitative or missing value
/// for the same identity; no line is drawn across such a point.
final class ScreenLabsSparkSeries {
  ScreenLabsSparkSeries({
    required Iterable<Iterable<ScreenLabsSparkPoint>> segments,
  }) : segments = List.unmodifiable([
         for (final segment in segments)
           List<ScreenLabsSparkPoint>.unmodifiable(segment),
       ]),
       pointCount = segments.fold(
         0,
         (count, segment) => count + segment.length,
       );
  final List<List<ScreenLabsSparkPoint>> segments;
  final int pointCount;
  bool get hasPoints => pointCount > 0;
  ScreenLabsSparkPoint? get first =>
      segments.isEmpty || segments.first.isEmpty ? null : segments.first.first;
  ScreenLabsSparkPoint? get latest =>
      segments.isEmpty || segments.last.isEmpty ? null : segments.last.last;
}

/// The newest saved result for one marker, with an optional comparable earlier
/// result. Only an exact unit, laboratory, method and specimen match is used
/// for comparison, mirroring the trend comparison identity.
final class ScreenLabsLatestValue {
  const ScreenLabsLatestValue({
    required this.record,
    required this.result,
    this.previousRecord,
    this.previousResult,
    this.sparkline,
    this.rawLinks = const [],
    this.links = const [],
  });
  final SupportingRevision record;
  final LabResultSnapshot result;
  final SupportingRevision? previousRecord;
  final LabResultSnapshot? previousResult;

  /// A bounded recent sample from the same filtered collection and comparison
  /// identity. Its exact coverage is disclosed by the section.
  final ScreenLabsSparkSeries? sparkline;

  /// Saved links before names are resolved; the projection never invents one.
  final List<SupportingContextLink> rawLinks;
  final List<ScreenLabsLink> links;
  String get metricId => result.metricId;
  ScreenLabsLatestValue withLinks(List<ScreenLabsLink> links) =>
      ScreenLabsLatestValue(
        record: record,
        result: result,
        previousRecord: previousRecord,
        previousResult: previousResult,
        sparkline: sparkline,
        rawLinks: rawLinks,
        links: links,
      );
}

final class ScreenLabsLatest {
  const ScreenLabsLatest({
    required this.values,
    required this.recordCount,
    required this.markerCount,
    required this.hasMoreMarkers,
    this.truncated = false,
    this.linksTruncated = false,
  });
  static const empty = ScreenLabsLatest(
    values: [],
    recordCount: 0,
    markerCount: 0,
    hasMoreMarkers: false,
  );
  final List<ScreenLabsLatestValue> values;

  /// All dated current records in the current filters, not only the marker page.
  final int recordCount;

  /// All markers with a dated current result in the current filters.
  final int markerCount;

  /// Whether another marker page is available.
  final bool hasMoreMarkers;

  /// Only a direct projection of an explicitly bounded list uses this flag.
  final bool truncated;

  /// Whether the bounded saved-context read omitted names.
  final bool linksTruncated;
  ScreenLabsLatest withValues(List<ScreenLabsLatestValue> values) =>
      ScreenLabsLatest(
        values: values,
        recordCount: recordCount,
        markerCount: markerCount,
        hasMoreMarkers: hasMoreMarkers,
        truncated: truncated,
        linksTruncated: linksTruncated,
      );
  ScreenLabsLatest withLinksTruncated(bool value) => ScreenLabsLatest(
    values: values,
    recordCount: recordCount,
    markerCount: markerCount,
    hasMoreMarkers: hasMoreMarkers,
    truncated: truncated,
    linksTruncated: value,
  );
}

typedef ScreenLabsLatestRequest = ({
  String personId,
  String displayZone,
  SupportingRecordKind? kind,
  String? itemId,
  String? eventId,
  CivilDate? fromDate,
  CivilDate? beforeDate,
  int markerLimit,
});

/// Projects the latest value for each marker from records that are already in
/// newest-first order. The first occurrence wins, so a marker with a newer
/// missing result reports that missing state instead of an older value.
///
/// This pure projection is used by focused tests. The live section reads the
/// complete filtered collection through [screenLabsProjectLatest].
ScreenLabsLatest screenLabsProject(
  List<SupportingRevision> records, {
  required bool truncated,
  int? markerLimit,
  String displayZone = 'UTC',
}) {
  final occurrences = <String, List<(SupportingRevision, LabResultSnapshot)>>{};
  for (final record in records) {
    for (final result in record.snapshot.results) {
      (occurrences[result.metricId] ??= []).add((record, result));
    }
  }
  final values = <ScreenLabsLatestValue>[];
  for (final entry in occurrences.entries) {
    final latest = entry.value.first;
    final latestKey = SupportingComparisonKey.forResult(latest.$1, latest.$2);
    final earlier = supportingEarlierComparison(
      viewed: latest.$1,
      result: latest.$2,
      candidates: records,
      displayZone: displayZone,
      windowLimited: truncated,
    ).earlier;
    values.add(
      ScreenLabsLatestValue(
        record: latest.$1,
        result: latest.$2,
        previousRecord: earlier?.record,
        previousResult: earlier?.result,
        sparkline: _sparkline(
          entry.value,
          latestKey: latestKey,
          displayZone: displayZone,
        ),
        rawLinks: latest.$1.snapshot.contextLinks,
      ),
    );
  }
  final kept = markerLimit == null
      ? values
      : values.take(markerLimit).toList(growable: false);
  return ScreenLabsLatest(
    values: kept,
    recordCount: records.length,
    markerCount: values.length,
    hasMoreMarkers: kept.length < values.length,
    truncated: truncated,
  );
}

/// Projects one bounded store page. Every marker's latest result comes from the
/// complete filtered collection; only its comparison and sparkline sample are
/// bounded and disclosed.
ScreenLabsLatest screenLabsProjectLatest(
  SupportingLatestPage page, {
  required String displayZone,
  int sampleLimit = screenLabsSparkSampleLimit,
}) {
  final values = <ScreenLabsLatestValue>[];
  for (final marker in page.markers) {
    final latest = marker.latest;
    final latestKey = SupportingComparisonKey.forResult(
      latest.record,
      latest.result,
    );
    final earlier = supportingEarlierComparison(
      viewed: latest.record,
      result: latest.result,
      candidates: [for (final candidate in marker.candidates) candidate.record],
      displayZone: displayZone,
      windowLimited: marker.candidatesLimited,
    ).earlier;
    values.add(
      ScreenLabsLatestValue(
        record: latest.record,
        result: latest.result,
        previousRecord: earlier?.record,
        previousResult: earlier?.result,
        sparkline: _sparkline(
          [
            for (final candidate in marker.candidates.take(sampleLimit))
              (candidate.record, candidate.result),
          ],
          latestKey: latestKey,
          displayZone: displayZone,
        ),
        rawLinks: latest.record.snapshot.contextLinks,
      ),
    );
  }
  return ScreenLabsLatest(
    values: values,
    recordCount: page.recordCount,
    markerCount: page.markerCount,
    hasMoreMarkers: values.length < page.markerCount,
  );
}

/// Exact numeric points from the sample, oldest first. A value for the same
/// identity that is censored, qualitative or missing breaks the line instead of
/// becoming a zero or a joined point.
ScreenLabsSparkSeries? _sparkline(
  List<(SupportingRevision, LabResultSnapshot)> occurrences, {
  required SupportingComparisonKey latestKey,
  required String displayZone,
}) {
  if (!latestKey.certain) return null;
  final segments = <List<ScreenLabsSparkPoint>>[];
  var current = <ScreenLabsSparkPoint>[];
  void close() {
    if (current.isNotEmpty) {
      segments.add(current);
      current = [];
    }
  }

  for (final candidate in occurrences.reversed) {
    final (record, result) = candidate;
    final key = SupportingComparisonKey.forResult(record, result);
    if (record.isVoided || key != latestKey) {
      close();
      continue;
    }
    if (!result.value.isExactNumeric) {
      close();
      continue;
    }
    final day = switch (record.snapshot.collectionDate.precision) {
      SupportingDatePrecision.day => record.snapshot.collectionDate.civilDate,
      SupportingDatePrecision.exact =>
        DisplayTime()
            .instant(record.snapshot.collectionDate.instant!, displayZone)
            .civilDate,
      SupportingDatePrecision.unknown ||
      SupportingDatePrecision.partial => null,
    };
    if (day == null) {
      close();
      continue;
    }
    current.add(ScreenLabsSparkPoint(record: record, result: result, day: day));
  }
  close();
  if (segments.isEmpty) return null;
  return ScreenLabsSparkSeries(segments: segments);
}

/// A change is shown only when it has an exact short decimal form. A repeating
/// or very long fraction is omitted rather than rounded into a false value.
String? screenLabsChange(ExactAmount latest, ExactAmount previous) =>
    supportingExactChange(latest, previous);

/// Reads the complete filtered collection for latest values. Unknown and
/// voided records stay out of the projection: an undated record cannot be
/// positioned as newest, and a voided record is not a current value. The list
/// below still exposes both.
final screenLabsLatestProvider = StreamProvider.autoDispose
    .family<ScreenLabsLatest, ScreenLabsLatestRequest>((ref, request) async* {
      if (ref.watch(appLockProvider.select((s) => s.locked))) {
        yield ScreenLabsLatest.empty;
        return;
      }
      final store = await ref.watch(recordStoreProvider.future);
      final query = SupportingLatestQuery(
        personId: request.personId,
        kind: request.kind,
        fromDate: request.fromDate,
        beforeDate: request.beforeDate,
        itemId: request.itemId,
        eventId: request.eventId,
        displayZone: request.displayZone,
        markerLimit: request.markerLimit,
      );
      // The watch keeps the summary current after a save, correction or void.
      // Each emission re-reads the same filtered collection from the store.
      try {
        await for (final page in store.watchSupportingLatest(query)) {
          yield await _withLinkNames(
            store,
            screenLabsProjectLatest(page, displayZone: request.displayZone),
            personId: request.personId,
          );
        }
      } on CommandConflict catch (error) {
        if (error.code != 'app_locked') rethrow;
      }
    });

Future<ScreenLabsLatest> _withLinkNames(
  RecordStore store,
  ScreenLabsLatest latest, {
  required String personId,
}) async {
  final cache = <String, ScreenLabsLink?>{};
  final shown = <String>{};
  var reads = 0, linksTruncated = false;
  final values = <ScreenLabsLatestValue>[];
  for (final value in latest.values) {
    final links = <ScreenLabsLink>[];
    for (final link in value.rawLinks) {
      final key = '${link.kind.name}:${link.id}';
      // The same saved context can sit on several panels. Keep the pill on the
      // newest marker only instead of repeating it down the section.
      if (!shown.add(key)) continue;
      if (!cache.containsKey(key)) {
        if (reads >= screenLabsProjectionLinkLimit) {
          cache[key] = null;
          linksTruncated = true;
        } else {
          reads++;
          final name = link.kind == SupportingContextKind.item
              ? (await store.itemById(link.id, personId: personId))?.name
              : (await store.eventById(link.id))?.name;
          cache[key] = name == null
              ? null
              : ScreenLabsLink(kind: link.kind, id: link.id, name: name);
        }
      }
      final resolved = cache[key];
      if (resolved != null) links.add(resolved);
    }
    values.add(value.withLinks(links));
  }
  return latest.withValues(values).withLinksTruncated(linksTruncated);
}
