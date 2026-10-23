import 'package:flutter/foundation.dart' show compute;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/record_store.dart';
import '../domain/exports/exports.dart';
import '../domain/artifact_transfer.dart';
import 'app_lock.dart';
import 'artifact_transfer.dart';
import 'storage.dart';

export '../domain/exports/exports.dart';

/// One transaction-bounded capture. Overridable in tests and by later report
/// flows that need the same immutable selection.
typedef ExportCapture = Future<ExportDocument> Function(
  ExportSelection selection, {
  ExportCancellation? cancellation,
});

final exportCaptureProvider = Provider<ExportCapture>(
  (ref) => (selection, {cancellation}) async {
    if (ref.read(appLockProvider).locked) {
      throw const ExportUnavailable('locked');
    }
    final store = await ref.read(recordStoreProvider.future);
    try {
      return await store.captureExport(selection, cancellation: cancellation);
    } on CommandConflict {
      throw const ExportUnavailable('locked');
    }
  },
);

/// Save uses the shared protected staging and platform destination gateway.
final exportHandoffProvider = Provider<ExportHandoff>(
  ArtifactExportHandoff.new,
);

final class ArtifactExportHandoff implements ExportHandoff {
  ArtifactExportHandoff(this.ref);
  final Ref ref;
  @override
  bool get isAvailable =>
      ref.read(artifactTransferGatewayProvider).capabilities.save;

  @override
  Future<ExportDelivery> deliver(
    ExportArtifact artifact, {
    ExportCancellation? cancellation,
    void Function(double)? onProgress,
  }) async {
    if (cancellation?.isCancelled == true) return ExportDelivery.cancelled;
    if (!isAvailable) return ExportDelivery.unavailable;
    if (ref.read(artifactTransferControllerProvider).busy) {
      return ExportDelivery.failed;
    }
    final controller = ref.read(artifactTransferControllerProvider.notifier);
    final subscription = ref.listen(artifactTransferControllerProvider, (
      _,
      next,
    ) {
      if (next.phase == ArtifactPhase.staging && next.progress != null) {
        onProgress?.call(next.progress!);
      }
    });
    final cancel = controller.cancel;
    cancellation?.addCancelListener(cancel);
    try {
      final outcome = await controller.save(
        ArtifactSource.bytes(
          artifact.bytes,
          kind: switch (artifact.format) {
            ExportFormat.json => ArtifactKind.dataJson,
            ExportFormat.csv => ArtifactKind.dataCsv,
            ExportFormat.fhir => ArtifactKind.dataFhir,
          },
          fileName: artifact.fileName,
          expectedSha256: artifact.sha256,
        ),
      );
      if (outcome.completed) return ExportDelivery.saved;
      if (outcome.cancelled) return ExportDelivery.cancelled;
      return ExportDelivery.failed;
    } finally {
      cancellation?.removeCancelListener(cancel);
      subscription.close();
    }
  }
}

enum ExportStage { editing, building, preview, saved }

final class ExportViewState {
  const ExportViewState({
    this.stage = ExportStage.editing,
    this.artifact,
    this.errorCode,
    this.delivery,
    this.progress = 0,
    this.saving = false,
  });

  final ExportStage stage;
  final ExportArtifact? artifact;

  /// Stable code translated by the UI. Raw exceptions never reach the screen.
  final String? errorCode;
  final ExportDelivery? delivery;
  final double progress;
  final bool saving;

  bool get building => stage == ExportStage.building;
  bool get reviewing =>
      stage == ExportStage.preview || stage == ExportStage.saved;
}

final exportControllerProvider = NotifierProvider.autoDispose
    .family<ExportController, ExportViewState, String>(ExportController.new);

/// Cancellation, capture, preview and handoff for one export route.
///
/// The generated [ExportArtifact] is retained so Save delivers exactly the
/// bytes reviewed. Editing the selection returns to [ExportStage.editing] and
/// discards the reviewed artifact.
class ExportController extends Notifier<ExportViewState> {
  ExportController(this.route);
  final String route;
  ExportCancellation? _cancellation;

  bool _current(ExportCancellation token) =>
      ref.mounted &&
      identical(_cancellation, token) &&
      !ref.read(appLockProvider).locked;

  @override
  ExportViewState build() {
    ref.onDispose(() => _cancellation?.cancel());
    ref.listen(appLockProvider.select((state) => state.locked), (_, locked) {
      if (locked) edit();
    });
    return const ExportViewState();
  }

  Future<void> generate(ExportSelection selection) async {
    if (state.building || ref.read(appLockProvider).locked) return;
    _cancellation?.cancel();
    final token = _cancellation = ExportCancellation();
    state = const ExportViewState(stage: ExportStage.building);
    try {
      final document = await ref.read(exportCaptureProvider)(
        selection,
        cancellation: token,
      );
      if (!_current(token)) return;
      token.throwIfCancelled();
      // Encoding and hashing large, bounded captures must leave the UI free
      // to process Cancel and lock transitions. Only detached domain data is
      // sent to the worker; a cancelled result is discarded on return.
      final artifact = await compute(ExportArtifact.build, document);
      if (!_current(token)) return;
      if (token.isCancelled) {
        state = const ExportViewState(errorCode: 'cancelled');
        return;
      }
      state = ExportViewState(stage: ExportStage.preview, artifact: artifact);
    } on ExportCancelled {
      if (_current(token)) {
        state = const ExportViewState(errorCode: 'cancelled');
      }
    } on ExportLimitException catch (error) {
      if (_current(token)) {
        state = ExportViewState(errorCode: error.code);
      }
    } on ExportUnavailable catch (error) {
      if (_current(token)) {
        state = ExportViewState(errorCode: error.code);
      }
    } catch (_) {
      if (_current(token)) {
        state = const ExportViewState(errorCode: 'export_failed');
      }
    }
  }

  void cancel() {
    _cancellation?.cancel();
    if (state.building) {
      _cancellation = null;
      state = const ExportViewState(errorCode: 'cancelled');
    }
  }

  void edit() {
    _cancellation?.cancel();
    _cancellation = null;
    state = const ExportViewState();
  }

  Future<void> save() async {
    final artifact = state.artifact;
    if (artifact == null ||
        state.building ||
        state.saving ||
        ref.read(appLockProvider).locked) {
      return;
    }
    final handoff = ref.read(exportHandoffProvider);
    if (!handoff.isAvailable) {
      state = ExportViewState(
        stage: ExportStage.preview,
        artifact: artifact,
        errorCode: 'export_handoff_unavailable',
      );
      return;
    }
    final token = _cancellation = ExportCancellation();
    state = ExportViewState(
      stage: ExportStage.preview,
      artifact: artifact,
      saving: true,
    );
    try {
      final delivery = await handoff.deliver(
        artifact,
        cancellation: token,
        onProgress: (value) {
          if (_current(token) &&
              !token.isCancelled &&
              value >= 0 &&
              value <= 1) {
            state = ExportViewState(
              stage: ExportStage.preview,
              artifact: artifact,
              saving: true,
              progress: value,
            );
          }
        },
      );
      if (!_current(token)) return;
      state = switch (delivery) {
        ExportDelivery.saved || ExportDelivery.shared => ExportViewState(
          stage: ExportStage.saved,
          artifact: artifact,
          delivery: delivery,
          progress: 1,
        ),
        ExportDelivery.cancelled => ExportViewState(
          stage: ExportStage.preview,
          artifact: artifact,
          errorCode: 'export_handoff_cancelled',
        ),
        ExportDelivery.unavailable => ExportViewState(
          stage: ExportStage.preview,
          artifact: artifact,
          errorCode: 'export_handoff_unavailable',
        ),
        ExportDelivery.failed => ExportViewState(
          stage: ExportStage.preview,
          artifact: artifact,
          errorCode: 'export_handoff_failed',
        ),
      };
    } catch (_) {
      if (_current(token)) {
        state = ExportViewState(
          stage: ExportStage.preview,
          artifact: artifact,
          errorCode: 'export_handoff_failed',
        );
      }
    }
  }
}
