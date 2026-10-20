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
/// unbounded rows. Continuation uses the store's keyset cursor rather than an
/// offset, so a file added or deleted while someone is choosing cannot shift
/// the next page past a surviving file. A file newer than the captured cursor
/// waits for a deliberate refresh instead of restarting the visible list.
const supportingSourcePageSize = 50;

final class SupportingSourceRequest {
  const SupportingSourceRequest({required this.personId, this.cursor});
  final String personId;
  final AttachmentPageCursor? cursor;
  @override
  bool operator ==(Object other) =>
      other is SupportingSourceRequest &&
      other.personId == personId &&
      other.cursor == cursor;
  @override
  int get hashCode => Object.hash(personId, cursor);
}

final class SupportingSourcePage {
  const SupportingSourcePage({
    required this.records,
    required this.nextCursor,
    required this.generation,
  });
  final List<AttachmentRecord> records;

  /// The cursor to request next, or null when this was the last page.
  final AttachmentPageCursor? nextCursor;

  /// Null only for the locked empty result, which the form discards.
  final String? generation;
  bool get hasMore => nextCursor != null;
}

typedef SupportingSourceReader =
    Future<SupportingSourcePage> Function(SupportingSourceRequest request);

/// Reads one newest-first page through the stable attachment keyset query.
/// Files for another adult, staging or deleting files and files from a
/// replaced generation are not eligible sources. Continuation advances by the
/// raw queried sort keys, so filtering a row out never loops or skips an older
/// surviving row.
final supportingSourceReaderProvider = Provider<SupportingSourceReader>(
  (ref) => (request) async {
    final store = await ref.read(recordStoreProvider.future);
    final page = await store.attachmentPage(
      personId: request.personId,
      limit: supportingSourcePageSize,
      cursor: request.cursor,
    );
    return SupportingSourcePage(
      records: [
        for (final record in page.records)
          if (supportingSourceEligible(
            record,
            personId: request.personId,
            generation: store.generation,
          ))
            record,
      ],
      nextCursor: page.nextCursor,
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
          nextCursor: null,
          generation: null,
        );
      }
      ref.watch(recordStoreProvider.select((s) => s.value?.generation));
      return ref.watch(supportingSourceReaderProvider)(request);
    });

/// The bounded store watcher for one trend query. A visible page keeps this
/// subscription open; leaving the page, locking or replacing the dataset
/// cancels it through provider disposal.
typedef SupportingTrendWatcher =
    Stream<SupportingTrendPage> Function(
      SupportingTrendQuery query, {
      int requestGeneration,
    });

final supportingTrendWatcherProvider = Provider<SupportingTrendWatcher>(
  (ref) => (query, {requestGeneration = 0}) async* {
    yield* (await ref.read(
      recordStoreProvider.future,
    )).watchSupportingTrend(query, requestGeneration: requestGeneration);
  },
);

/// One fence per encoded query. It lives as long as the trend provider, so a
/// rebuild advances the request sequence while a retired stream's pending
/// emission still carries the previous token.
final _supportingTrendFenceProvider = Provider.autoDispose
    .family<_SupportingTrendFence, String>(
      (ref, encoded) => _SupportingTrendFence(),
    );

/// View-owned sequencing for a live trend. The schema version is fixed for the
/// running process and the page token still carries it; a late emission is
/// fenced by the request sequence plus the exact query and dataset identity.
final class _SupportingTrendFence {
  int _request = 0;
  int begin() => ++_request;
  bool accepts(
    SupportingTrendPage page, {
    required int request,
    required SupportingTrendQuery query,
    required String datasetGeneration,
  }) =>
      page.requestGeneration == request &&
      page.query.identity == query.identity &&
      page.datasetGeneration == datasetGeneration;
}

/// Watches the current query while this provider has a listener. The first
/// emission replaces the whole model, so a correction, void or insert is
/// visible without invalidating a one-shot read manually.
final supportingTrendProvider = StreamProvider.autoDispose
    .family<SupportingTrendPage?, String>((ref, encoded) async* {
      if (ref.watch(appLockProvider.select((s) => s.locked))) {
        yield null;
        return;
      }
      final query = SupportingTrendQuery.fromJson(_decode(encoded));
      // Only a settled current store may be read. A manual refresh and the
      // dataset-swap path both retain the retired store in `.value` while the
      // surface reloads, so `.isLoading`/`.hasError` must gate this read rather
      // than `.isReloading`. The settled rebuild then starts a fresh watcher.
      final record = ref.watch(recordStoreProvider);
      final store = (record.isLoading || record.hasError) ? null : record.value;
      if (store == null) {
        await ref.watch(recordStoreProvider.future);
        return;
      }
      final fence = ref.watch(_supportingTrendFenceProvider(encoded));
      final request = fence.begin();
      final generation = store.generation;
      yield* ref
          .watch(supportingTrendWatcherProvider)(
            query,
            requestGeneration: request,
          )
          .where(
            (page) => fence.accepts(
              page,
              request: request,
              query: query,
              datasetGeneration: generation,
            ),
          );
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
      yield* (await ref.watch(
        recordStoreProvider.future,
      )).watchSupportingRecords(request.query, cursor: request.cursor);
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
