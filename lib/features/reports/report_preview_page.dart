import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../app/reports.dart';
import '../../app/vital_app.dart';
import '../../l10n/app_localizations.dart';
import '../../ui/vital_ui.dart';
import '../recording/record_pages.dart';

typedef ReportDocumentViewBuilder = Widget Function(
  BuildContext context,
  ReportArtifact artifact,
);

/// Keeps the reviewed artifact preview in memory. Tests override this seam.
final reportDocumentViewBuilderProvider = Provider<ReportDocumentViewBuilder>(
  (ref) =>
      (context, artifact) => PdfViewer.data(
        artifact.bytes,
        sourceName: 'report-${artifact.artifactId}',
        maxSizeToCacheOnMemory: 0,
      ),
);

class ReportPreviewPage extends ConsumerWidget {
  const ReportPreviewPage({super.key, this.documentView});
  final ReportDocumentViewBuilder? documentView;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final state = ref.watch(reportControllerProvider);
    final artifact = state.artifact;
    final gateway = ref.watch(reportArtifactGatewayProvider);
    final canSave = gateway.capabilities.contains(
      state.textPreview
          ? ReportArtifactCapability.saveText
          : ReportArtifactCapability.save,
    );
    final canShare = gateway.capabilities.contains(
      ReportArtifactCapability.share,
    );
    final ReportDocumentViewBuilder viewer =
        documentView ?? ref.watch(reportDocumentViewBuilderProvider);
    final height = (MediaQuery.sizeOf(context).height * 0.62).clamp(
      360.0,
      760.0,
    );
    return Scaffold(
      headers: [
        SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                VitalButton.secondary(
                  onPressed: () =>
                      context.canPop() ? context.pop() : context.go('/reports'),
                  child: Text(t.back),
                ),
                VitalButton.secondary(
                  onPressed: artifact == null || !canSave || state.handoffBusy
                      ? null
                      : () => ref
                            .read(reportControllerProvider.notifier)
                            .save(asText: state.textPreview),
                  child: Text(t.save),
                ),
                if (!state.textPreview)
                  VitalButton.secondary(
                    onPressed:
                        artifact == null || !canShare || state.handoffBusy
                        ? null
                        : () => ref
                              .read(reportControllerProvider.notifier)
                              .share(),
                    child: Text(t.share),
                  ),
              ],
            ),
          ),
        ),
      ],
      child: artifact == null
          ? PageContent(children: [Text(t.reportUnavailable)])
          : PageContent(
              children: [
                Heading(t.reportPreviewTitle),
                Semantics(
                  header: true,
                  child: Text(
                    artifact.templateTitle,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(height: 4),
                if (artifact.reportName != null)
                  Text(
                    artifact.reportName!,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                Text(artifact.personName),
                Text(
                  t.reportPeriodValue(
                    artifact.periodText.split(' to ').first,
                    artifact.periodText.split(' to ').last,
                    state.selection?.displayZone ?? '',
                  ),
                ),
                Text(
                  t.reportTemplateValue(
                    artifact.templateId,
                    artifact.templateVersion,
                  ),
                ),
                Text(
                  t.reportArtifactValue(
                    artifact.pageCount,
                    (artifact.byteCount / 1024).ceil(),
                  ),
                ),
                const SizedBox(height: 8),
                VitalSegments<bool>(
                  values: const [false, true],
                  selected: state.textPreview,
                  label: (value) => value ? t.reportText : t.reportPreviewMode,
                  onChanged: (value) => ref
                      .read(reportControllerProvider.notifier)
                      .setTextPreview(value),
                ),
                const SizedBox(height: 12),
                if (state.textPreview)
                  VitalSurface(child: SelectableText(artifact.text))
                else
                  VitalSurface(
                    padding: EdgeInsets.zero,
                    child: SizedBox(
                      height: height,
                      child: viewer(context, artifact),
                    ),
                  ),
                if (!canSave || !canShare) ...[
                  const SizedBox(height: 8),
                  Text(
                    !canSave && !canShare
                        ? t.reportHandoffUnavailable
                        : !canSave
                        ? t.reportSaveUnavailable
                        : t.reportShareUnavailable,
                  ),
                ],
                if (state.handoffMessage != null)
                  Semantics(
                    liveRegion: true,
                    child: Text(switch (state.handoffMessage) {
                      'handoff_complete' => t.reportHandoffComplete,
                      'handoff_offered' => t.reportShareOffered,
                      'handoff_cancelled' => t.reportHandoffCancelled,
                      'handoff_unavailable' => t.reportHandoffUnavailable,
                      _ => t.reportHandoffFailed,
                    }),
                  ),
                const SizedBox(height: 8),
                Text(
                  t.reportArtifactIdentity(
                    artifact.artifactId,
                    artifact.sha256.substring(0, 12),
                  ),
                ),
                const SizedBox(height: 8),
                Text(t.reportArtifactLimits),
              ],
            ),
    );
  }
}
