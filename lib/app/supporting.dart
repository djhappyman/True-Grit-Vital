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
final supportingSourceCandidatesProvider = FutureProvider.autoDispose
    .family<List<AttachmentRecord>, String>((ref, personId) async {
      if (ref.watch(appLockProvider.select((s) => s.locked))) return [];
      ref.watch(recordStoreProvider.select((s) => s.value?.generation));
      final store = await ref.watch(recordStoreProvider.future);
      return store.attachments(personId: personId, limit: 50);
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
