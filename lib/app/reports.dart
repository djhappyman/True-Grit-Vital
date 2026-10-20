import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/record_store.dart';
import '../domain/artifact_transfer.dart';
import '../reports/templates/report_template_catalog.dart';
import '../reports/report_template.dart';
import 'app_lock.dart';
import 'artifact_transfer.dart';
import 'storage.dart';

export '../domain/reports/reports.dart';

enum ReportArtifactCapability { save, share, saveText }

enum ReportHandoffOutcome { completed, offered, cancelled, unavailable, failed }

final class ReportHandoffResult {
  const ReportHandoffResult(this.outcome);
  final ReportHandoffOutcome outcome;
  bool get completed => outcome == ReportHandoffOutcome.completed;
}

/// T05 owns the real native Save/Share implementation. This seam accepts the
/// complete reviewed artifact (and its text alternative) rather than assuming
/// a whole-file path or a second report renderer.
abstract interface class ReportArtifactGateway {
  Set<ReportArtifactCapability> get capabilities;

  Future<ReportHandoffResult> save(
    ReportArtifact artifact, {
    bool asText = false,
  });

  Future<ReportHandoffResult> share(ReportArtifact artifact);
}

/// Production remains truthful until T05 wires a capability-appropriate path.
final class UnavailableReportArtifactGateway implements ReportArtifactGateway {
  const UnavailableReportArtifactGateway();
  @override
  Set<ReportArtifactCapability> get capabilities => const {};
  @override
  Future<ReportHandoffResult> save(
    ReportArtifact artifact, {
    bool asText = false,
  }) async => const ReportHandoffResult(ReportHandoffOutcome.unavailable);
  @override
  Future<ReportHandoffResult> share(ReportArtifact artifact) async =>
      const ReportHandoffResult(ReportHandoffOutcome.unavailable);
}

final reportArtifactGatewayProvider = Provider<ReportArtifactGateway>(
  ArtifactReportGateway.new,
);

/// Saves the reviewed bytes unchanged; an offered share is not receipt proof.
final class ArtifactReportGateway implements ReportArtifactGateway {
  ArtifactReportGateway(this.ref);
  final Ref ref;

  @override
  Set<ReportArtifactCapability> get capabilities {
    final capability = ref.read(artifactTransferGatewayProvider).capabilities;
    return {
      if (capability.save) ...{
        ReportArtifactCapability.save,
        ReportArtifactCapability.saveText,
      },
      if (capability.share) ReportArtifactCapability.share,
    };
  }

  @override
  Future<ReportHandoffResult> save(
    ReportArtifact artifact, {
    bool asText = false,
  }) => _deliver(artifact, asText: asText, share: false);

  @override
  Future<ReportHandoffResult> share(ReportArtifact artifact) =>
      _deliver(artifact, asText: false, share: true);

  Future<ReportHandoffResult> _deliver(
    ReportArtifact artifact, {
    required bool asText,
    required bool share,
  }) async {
    final bytes = asText ? artifact.textBytes : artifact.bytes;
    final source = ArtifactSource.bytes(
      bytes,
      kind: asText ? ArtifactKind.plainText : ArtifactKind.summaryPdf,
      fileName: asText ? artifact.textFileName : artifact.fileName,
      expectedSha256: asText
          ? sha256.convert(bytes).toString()
          : artifact.sha256,
    );
    final controller = ref.read(artifactTransferControllerProvider.notifier);
    final outcome = await (share
        ? controller.share(source)
        : controller.save(source));
    return ReportHandoffResult(
      outcome.completed
          ? (share
                ? ReportHandoffOutcome.offered
                : ReportHandoffOutcome.completed)
          : outcome.cancelled
          ? ReportHandoffOutcome.cancelled
          : ReportHandoffOutcome.failed,
    );
  }
}

typedef ReportCaptureRequest = ({
  ReportSelection selection,
  DateTime Function() now,
  ReportCancellation cancellation,
});
final reportCaptureProvider =
    Provider<Future<ReportCapture> Function(ReportCaptureRequest)>(
      (ref) => (request) async {
        final store = await ref.read(recordStoreProvider.future);
        return store.captureTemplateReport(
          selection: request.selection,
          now: request.now,
          cancellation: request.cancellation,
        );
      },
    );
final reportNowProvider = Provider<DateTime Function()>(
  (ref) =>
      () => DateTime.now().toUtc(),
);
final reportRendererProvider =
    Provider<ReportTemplateRenderer Function(ReportTemplateId)>(
      (ref) => rendererForTemplate,
    );
final reportItemsProvider = StreamProvider.autoDispose
    .family<List<SubstanceItem>, String>((ref, personId) async* {
      if (ref.watch(appLockProvider.select((state) => state.locked))) {
        yield const [];
        return;
      }
      yield* (await ref.watch(recordStoreProvider.future))
          .watchItems(scope: FeedScope.person(personId), limit: 500);
    });

enum ReportPhase { idle, capturing, rendering, ready, failed, cancelled }

final class ReportState {
  const ReportState({
    this.selection,
    this.phase = ReportPhase.idle,
    this.progress = 0,
    this.artifact,
    this.errorCode,
    this.textPreview = false,
    this.handoffBusy = false,
    this.handoffMessage,
  });
  final ReportSelection? selection;
  final ReportPhase phase;
  final double progress;
  final ReportArtifact? artifact;
  final String? errorCode;
  final bool textPreview, handoffBusy;
  final String? handoffMessage;
  bool get busy =>
      phase == ReportPhase.capturing || phase == ReportPhase.rendering;
  bool get hasArtifact => artifact != null;
}

final reportControllerProvider =
    NotifierProvider.autoDispose<ReportController, ReportState>(
      ReportController.new,
    );

class ReportController extends Notifier<ReportState> {
  _ReportToken? _token;
  Object? _handoffToken;

  bool _current(_ReportToken token) =>
      ref.mounted &&
      identical(_token, token) &&
      !token.isCancelled &&
      !ref.read(appLockProvider).locked;

  @override
  ReportState build() {
    ref.onDispose(() => _token?.cancel());
    ref.listen(appLockProvider.select((state) => state.locked), (_, locked) {
      if (locked) reset();
    });
    return const ReportState();
  }

  void reset() {
    _token?.cancel();
    _token = null;
    _handoffToken = null;
    state = const ReportState();
  }

  void select(ReportSelection selection) {
    if (state.busy || state.handoffBusy) return;
    _token?.cancel();
    _token = null;
    state = ReportState(selection: selection);
  }

  void setIncludeNotes(bool value) =>
      _change((selection) => selection.copyWith(includeNotes: value));
  void setIncludeAttachments(bool value) =>
      _change((selection) => selection.copyWith(includeAttachments: value));
  void setIncludeSupporting(bool value) =>
      _change((selection) => selection.copyWith(includeSupporting: value));
  void setItems(Iterable<String> items) =>
      _change((selection) => selection.copyWith(itemIds: items));
  void setReportName(String? value) => _change(
    (selection) => value == null || value.trim().isEmpty
        ? selection.copyWith(clearReportName: true)
        : selection.copyWith(reportName: value.trim()),
  );

  void _change(ReportSelection Function(ReportSelection) update) {
    final selection = state.selection;
    if (selection == null || state.busy || state.handoffBusy) return;
    final next = update(selection);
    if (next == selection) return;
    state = ReportState(selection: next);
  }

  void cancel() {
    _token?.cancel();
    _token = null;
    _handoffToken = null;
    final selection = state.selection;
    state = ReportState(
      selection: selection,
      phase: ReportPhase.cancelled,
      errorCode: 'report_cancelled',
    );
  }

  Future<void> generate({required bool use24Hour}) async {
    final selection = state.selection;
    if (selection == null || state.busy || state.handoffBusy) return;
    if (ref.read(appLockProvider).locked) {
      state = ReportState(
        selection: selection,
        phase: ReportPhase.failed,
        errorCode: 'report_locked',
      );
      return;
    }
    final token = _token = _ReportToken();
    state = ReportState(
      selection: selection,
      phase: ReportPhase.capturing,
      progress: 0.05,
    );
    ReportCapture? capture;
    try {
      capture = await ref.read(reportCaptureProvider)((
        selection: selection,
        now: ref.read(reportNowProvider),
        cancellation: token,
      ));
      if (!_current(token)) return;
      state = ReportState(
        selection: selection,
        phase: ReportPhase.rendering,
        progress: 0.25,
      );
      final renderer = ref.read(reportRendererProvider)(selection.template);
      final rendered = await renderer.render(
        capture.snapshot,
        use24Hour: use24Hour,
        cancellation: token,
        onProgress: (completed, total) {
          if (!_current(token)) return;
          final fraction = total < 1 ? 1.0 : completed / total;
          state = ReportState(
            selection: selection,
            phase: ReportPhase.rendering,
            progress: 0.25 + fraction * 0.65,
          );
        },
      );
      if (!_current(token)) return;
      var text = reportTextFor(capture.snapshot, use24Hour: use24Hour);
      if (!rendered.fontsEmbedded) {
        text =
            '$text\n\nEmbedded report font unavailable. Standard PDF fonts were used.';
      }
      final artifact = ReportArtifact(
        selectionIdentity: selection.identity,
        artifactId: capture.snapshot.artifactId,
        templateId: selection.template.id,
        templateVersion: renderer.version,
        templateTitle: selection.template.title,
        personName: capture.snapshot.person.name,
        reportName: capture.snapshot.reportIdentity,
        periodText:
            '${formatCivilDate(selection.fromDate)} to '
            '${formatCivilDate(selection.beforeDate.addDays(-1))}',
        generatedAt: capture.snapshot.cutoff.generatedAt,
        bytes: rendered.bytes,
        text: text,
        fileName: capture.snapshot.neutralFileName,
        textFileName: capture.snapshot.textFileName,
        pageCount: rendered.pageCount,
        sha256: sha256.convert(rendered.bytes).toString(),
        fontsEmbedded: rendered.fontsEmbedded,
        use24Hour: use24Hour,
      );
      if (!_current(token)) return;
      state = ReportState(
        selection: selection,
        phase: ReportPhase.ready,
        progress: 1,
        artifact: artifact,
      );
    } on ReportCancelled {
      if (_current(token)) {
        state = ReportState(
          selection: selection,
          phase: ReportPhase.cancelled,
          errorCode: 'report_cancelled',
        );
      }
    } on ReportSelectionFailure catch (error) {
      if (_current(token)) {
        state = ReportState(
          selection: selection,
          phase: ReportPhase.failed,
          errorCode: error.code,
        );
      }
    } catch (_) {
      if (_current(token)) {
        state = ReportState(
          selection: selection,
          phase: ReportPhase.failed,
          errorCode: 'report_failed',
        );
      }
    } finally {
      // The capture owns cleanup independently of this provider's lifetime.
      // Navigation or a lock may dispose the controller while rendering.
      try {
        await capture?.releasePins?.call();
      } catch (_) {}
    }
  }

  void setTextPreview(bool value) => state = ReportState(
    selection: state.selection,
    phase: state.phase,
    progress: state.progress,
    artifact: state.artifact,
    errorCode: state.errorCode,
    textPreview: value,
    handoffBusy: state.handoffBusy,
    handoffMessage: state.handoffMessage,
  );

  void clearHandoffMessage() => state = ReportState(
    selection: state.selection,
    phase: state.phase,
    progress: state.progress,
    artifact: state.artifact,
    errorCode: state.errorCode,
    textPreview: state.textPreview,
  );

  Future<void> save({bool asText = false}) =>
      _handoff((gateway, artifact) => gateway.save(artifact, asText: asText));

  Future<void> share() =>
      _handoff((gateway, artifact) => gateway.share(artifact));

  Future<void> _handoff(
    Future<ReportHandoffResult> Function(
      ReportArtifactGateway gateway,
      ReportArtifact artifact,
    )
    action,
  ) async {
    final artifact = state.artifact;
    if (artifact == null ||
        state.handoffBusy ||
        ref.read(appLockProvider).locked) {
      return;
    }
    final operation = _handoffToken = Object();
    final gateway = ref.read(reportArtifactGatewayProvider);
    state = ReportState(
      selection: state.selection,
      phase: state.phase,
      progress: state.progress,
      artifact: artifact,
      errorCode: state.errorCode,
      textPreview: state.textPreview,
      handoffBusy: true,
    );
    ReportHandoffResult result;
    try {
      result = await action(gateway, artifact);
    } catch (_) {
      result = const ReportHandoffResult(ReportHandoffOutcome.failed);
    }
    if (!ref.mounted ||
        !identical(_handoffToken, operation) ||
        !identical(state.artifact, artifact) ||
        ref.read(appLockProvider).locked) {
      return;
    }
    state = ReportState(
      selection: state.selection,
      phase: state.phase,
      progress: state.progress,
      artifact: artifact,
      errorCode: state.errorCode,
      textPreview: state.textPreview,
      handoffMessage: switch (result.outcome) {
        ReportHandoffOutcome.completed => 'handoff_complete',
        ReportHandoffOutcome.offered => 'handoff_offered',
        ReportHandoffOutcome.cancelled => 'handoff_cancelled',
        ReportHandoffOutcome.unavailable => 'handoff_unavailable',
        ReportHandoffOutcome.failed => 'handoff_failed',
      },
    );
  }
}

final class _ReportToken implements ReportCancellation {
  bool _cancelled = false;
  @override
  bool get isCancelled => _cancelled;
  void cancel() => _cancelled = true;
}
