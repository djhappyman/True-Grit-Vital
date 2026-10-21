import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_lock.dart';
import '../../app/storage.dart';
import '../../data/record_store.dart';

/// The latest-value panel is a deliberately bounded projection. Three pages of
/// 25 are enough to cover a normal lab history without reading the whole store;
/// the section states exactly which window it used.
const screenLabsProjectionPageSize = 25;
const screenLabsProjectionPages = 3;
const screenLabsProjectionRecordLimit =
    screenLabsProjectionPageSize * screenLabsProjectionPages;
const screenLabsProjectionMarkerLimit = 60;
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

/// The newest saved result for one marker, with an optional comparable earlier
/// result. Only an exact unit, laboratory, method and specimen match is used
/// for comparison, mirroring the trend comparison identity.
final class ScreenLabsLatestValue {
  const ScreenLabsLatestValue({
    required this.record,
    required this.result,
    this.previousRecord,
    this.previousResult,
    this.rawLinks = const [],
    this.links = const [],
  });
  final SupportingRevision record;
  final LabResultSnapshot result;
  final SupportingRevision? previousRecord;
  final LabResultSnapshot? previousResult;

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
        rawLinks: rawLinks,
        links: links,
      );
}

final class ScreenLabsLatest {
  const ScreenLabsLatest({
    required this.values,
    required this.recordCount,
    required this.truncated,
    required this.markersTruncated,
  });
  static const empty = ScreenLabsLatest(
    values: [],
    recordCount: 0,
    truncated: false,
    markersTruncated: false,
  );
  final List<ScreenLabsLatestValue> values;

  /// How many dated records the projection actually examined.
  final int recordCount;

  /// Whether older dated records exist outside the bounded window.
  final bool truncated;

  /// Whether more measurable markers exist than the display window keeps.
  final bool markersTruncated;
  ScreenLabsLatest withValues(List<ScreenLabsLatestValue> values) =>
      ScreenLabsLatest(
        values: values,
        recordCount: recordCount,
        truncated: truncated,
        markersTruncated: markersTruncated,
      );
}

typedef ScreenLabsLatestRequest = ({
  String personId,
  String displayZone,
  SupportingRecordKind? kind,
  String? itemId,
  String? eventId,
});

/// Projects the latest value for each marker from records that are already in
/// newest-first order. The first occurrence wins, so a marker with a newer
/// missing result reports that missing state instead of an older value.
ScreenLabsLatest screenLabsProject(
  List<SupportingRevision> records, {
  required bool truncated,
  int markerLimit = screenLabsProjectionMarkerLimit,
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
    final latestValue = latest.$2.value;
    final exact = latestValue.isExactNumeric;
    final qualitative = latestValue.kind == SupportingValueKind.qualitative;
    (SupportingRevision, LabResultSnapshot)? previous;
    if (latestKey.certain && (exact || qualitative)) {
      for (final candidate in entry.value.skip(1)) {
        if (candidate.$1.id == latest.$1.id) continue;
        final key = SupportingComparisonKey.forResult(
          candidate.$1,
          candidate.$2,
        );
        if (!key.certain || key != latestKey) continue;
        final candidateValue = candidate.$2.value;
        if (exact
            ? !candidateValue.isExactNumeric
            : !(candidateValue.kind == SupportingValueKind.qualitative)) {
          continue;
        }
        previous = candidate;
        break;
      }
    }
    values.add(
      ScreenLabsLatestValue(
        record: latest.$1,
        result: latest.$2,
        previousRecord: previous?.$1,
        previousResult: previous?.$2,
        rawLinks: latest.$1.snapshot.contextLinks,
      ),
    );
  }
  final kept = values.take(markerLimit).toList(growable: false);
  return ScreenLabsLatest(
    values: kept,
    recordCount: records.length,
    truncated: truncated,
    markersTruncated: values.length > kept.length,
  );
}

/// A change is shown only when it has an exact short decimal form. A repeating
/// or very long fraction is omitted rather than rounded into a false value.
String? screenLabsChange(ExactAmount latest, ExactAmount previous) {
  final change = latest - previous;
  if (change == ExactAmount.zero) return '0';
  var denominator = change.denominator;
  var twos = 0, fives = 0;
  while (denominator % BigInt.two == BigInt.zero) {
    denominator ~/= BigInt.two;
    twos++;
  }
  while (denominator % BigInt.from(5) == BigInt.zero) {
    denominator ~/= BigInt.from(5);
    fives++;
  }
  if (denominator != BigInt.one) return null;
  final places = twos > fives ? twos : fives;
  if (places > 6) return null;
  final text = change.roundedDecimal(places: places);
  return text.startsWith('-') ? text : '+$text';
}

/// Reads the bounded latest window live. Unknown and voided records stay out of
/// the projection: an undated record cannot be positioned as newest, and a
/// voided record is not a current value. The list below still exposes both.
final screenLabsLatestProvider = StreamProvider.autoDispose
    .family<ScreenLabsLatest, ScreenLabsLatestRequest>((ref, request) async* {
      if (ref.watch(appLockProvider.select((s) => s.locked))) {
        yield ScreenLabsLatest.empty;
        return;
      }
      final store = await ref.watch(recordStoreProvider.future);
      final query = SupportingQuery(
        personId: request.personId,
        kind: request.kind,
        dateBasis: SupportingDateBasis.collection,
        includeUnknownDates: false,
        includeVoided: false,
        itemId: request.itemId,
        eventId: request.eventId,
        limit: screenLabsProjectionPageSize,
        displayZone: request.displayZone,
      );
      // The watch keeps the summary current after a save, correction or void.
      // Each emission re-reads the same bounded window from the first page.
      await for (final first in store.watchSupportingRecords(query)) {
        final records = [...first.entries];
        var next = first.next;
        while (next != null &&
            records.length < screenLabsProjectionRecordLimit) {
          final more = await store.supportingRecords(query, cursor: next);
          records.addAll(more.entries);
          next = more.next;
        }
        final projected = screenLabsProject(records, truncated: next != null);
        yield await _withLinkNames(
          store,
          projected,
          personId: request.personId,
        );
      }
    });

Future<ScreenLabsLatest> _withLinkNames(
  RecordStore store,
  ScreenLabsLatest latest, {
  required String personId,
}) async {
  final cache = <String, ScreenLabsLink?>{};
  final shown = <String>{};
  var reads = 0;
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
  return latest.withValues(values);
}
