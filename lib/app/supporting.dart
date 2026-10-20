import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/record_store.dart';
import 'app_lock.dart';
import 'storage.dart';

export '../domain/supporting/supporting.dart';

final supportingLookupProvider = FutureProvider.autoDispose
    .family<SupportingRevision?, ({String personId, String id, int? revision})>(
      (ref, request) async {
        if (ref.watch(appLockProvider.select((s) => s.locked))) return null;
        final store = await ref.watch(recordStoreProvider.future);
        return store.supportingRecord(
          request.personId,
          request.id,
          revision: request.revision,
        );
      },
    );
final supportingRevisionsProvider = FutureProvider.autoDispose
    .family<
      List<SupportingRevision>,
      ({String personId, String id, int? before})
    >((ref, request) async {
      if (ref.watch(appLockProvider.select((s) => s.locked))) return [];
      return (await ref.watch(recordStoreProvider.future)).supportingRevisions(
        request.personId,
        request.id,
        beforeRevision: request.before,
      );
    });
final supportingMetricsProvider = FutureProvider.autoDispose
    .family<
      List<SupportingMetric>,
      ({String personId, SupportingMetricKind kind, String search, int offset})
    >((ref, request) async {
      if (ref.watch(appLockProvider.select((s) => s.locked))) return [];
      return (await ref.watch(recordStoreProvider.future)).supportingMetrics(
        personId: request.personId,
        kind: request.kind,
        search: request.search,
        offset: request.offset,
      );
    });

/// Ready protected files owned by this adult, for authoring a saved source
/// reference. The form freezes the selected file id, metadata revision and
/// content version; a later file change cannot rewrite that captured source.
///
/// Only one bounded page is read at a time so a long file list never loads
/// unbounded rows. The newest-first offset order is stable; the form merges
/// later pages by id and rejects any page from a replaced generation.
const supportingSourcePageSize = 50;

final class SupportingSourceRequest {
  const SupportingSourceRequest({required this.personId, required this.offset});
  final String personId;
  final int offset;
  @override
  bool operator ==(Object other) =>
      other is SupportingSourceRequest &&
      other.personId == personId &&
      other.offset == offset;
  @override
  int get hashCode => Object.hash(personId, offset);
}

final class SupportingSourcePage {
  const SupportingSourcePage({
    required this.records,
    required this.nextOffset,
    required this.generation,
  });
  final List<AttachmentRecord> records;

  /// The offset to request next, or null when this was the last page.
  final int? nextOffset;

  /// Null only for the locked empty result, which the form discards.
  final String? generation;
  bool get hasMore => nextOffset != null;
}

typedef SupportingSourceReader = Future<SupportingSourcePage> Function(
  SupportingSourceRequest request,
);

/// Reads one newest-first page through the existing attachment query. Files
/// for another adult, staging or deleting files and files from a replaced
/// generation are not eligible sources.
final supportingSourceReaderProvider = Provider<SupportingSourceReader>(
  (ref) => (request) async {
    final store = await ref.read(recordStoreProvider.future);
    final found = await store.attachments(
      personId: request.personId,
      limit: supportingSourcePageSize,
      offset: request.offset,
    );
    return SupportingSourcePage(
      records: [
        for (final record in found)
          if (supportingSourceEligible(
            record,
            personId: request.personId,
            generation: store.generation,
          ))
            record,
      ],
      nextOffset: found.length == supportingSourcePageSize
          ? request.offset + found.length
          : null,
      generation: store.generation,
    );
  },
);

final supportingSourceCandidatesProvider = FutureProvider.autoDispose
    .family<SupportingSourcePage, SupportingSourceRequest>((
      ref,
      request,
    ) async {
      if (ref.watch(appLockProvider.select((s) => s.locked))) {
        return const SupportingSourcePage(
          records: [],
          nextOffset: null,
          generation: null,
        );
      }
      ref.watch(recordStoreProvider.select((s) => s.value?.generation));
      return ref.watch(supportingSourceReaderProvider)(request);
    });

final supportingTrendReaderProvider =
    Provider<Future<SupportingTrendPage> Function(SupportingTrendQuery)>(
      (ref) =>
          (query) async =>
              (await ref.read(recordStoreProvider.future))
                  .supportingTrend(query),
    );

final supportingTrendProvider = FutureProvider.autoDispose
    .family<SupportingTrendPage?, String>((ref, encoded) async {
      if (ref.watch(appLockProvider.select((s) => s.locked))) return null;
      final query = SupportingTrendQuery.fromJson(_decode(encoded));
      ref.watch(recordStoreProvider.select((s) => s.value?.generation));
      return ref.watch(supportingTrendReaderProvider)(query);
    });

Map<String, dynamic> _decode(String value) =>
    Map<String, dynamic>.from(jsonDecode(value) as Map);

class SupportingPageRequest {
  const SupportingPageRequest(this.query, {this.cursor});
  final SupportingQuery query;
  final SupportingCursor? cursor;
  @override
  bool operator ==(Object other) =>
      other is SupportingPageRequest &&
      other.query.identity == query.identity &&
      other.cursor?.encode() == cursor?.encode();
  @override
  int get hashCode => Object.hash(query.identity, cursor?.encode());
}

final supportingPageProvider = StreamProvider.autoDispose
    .family<SupportingPage?, SupportingPageRequest>((ref, request) async* {
      if (ref.watch(appLockProvider.select((s) => s.locked))) {
        yield null;
        return;
      }
      yield* (await ref.watch(recordStoreProvider.future))
          .watchSupportingRecords(request.query, cursor: request.cursor);
    });

typedef SupportingSave = ({
  String commandId,
  String generation,
  int personRevision,
  int? targetRevision,
  SupportingSnapshot snapshot,
});
final supportingWriterProvider =
    Provider<Future<SupportingRevision> Function(SupportingSave)>(
      (ref) => (input) async {
        final store = await ref.read(recordStoreProvider.future),
            snapshot = input.snapshot;
        return snapshot is LabPanelSnapshot
            ? store.saveLabPanel(
                SaveLabPanelCommand(
                  commandId: input.commandId,
                  generation: input.generation,
                  expectedPersonRevision: input.personRevision,
                  expectedRevision: input.targetRevision,
                  panel: snapshot,
                ),
              )
            : store.saveObservation(
                SaveObservationCommand(
                  commandId: input.commandId,
                  generation: input.generation,
                  expectedPersonRevision: input.personRevision,
                  expectedRevision: input.targetRevision,
                  observation: snapshot as ObservationSnapshot,
                ),
              );
      },
    );
