import '../../domain/reports/reports.dart';
import '../r01_summary_template.dart';
import '../report_fonts.dart';
import '../report_template.dart';
import 'r02_history_template.dart';
import 'r03_event_template.dart';

/// One selectable report design. Templates share the selection, font, page and
/// artifact pipeline; they differ only in body content.
final class ReportTemplateDefinition {
  const ReportTemplateDefinition({
    required this.id,
    required this.requiresEvent,
    required this.acceptsLedgerFilters,
  });
  final ReportTemplateId id;
  final bool requiresEvent, acceptsLedgerFilters;
}

const reportTemplateCatalog = <ReportTemplateDefinition>[
  ReportTemplateDefinition(
    id: ReportTemplateId.r01SubstanceSummary,
    requiresEvent: false,
    acceptsLedgerFilters: false,
  ),
  ReportTemplateDefinition(
    id: ReportTemplateId.r02DetailedHistory,
    requiresEvent: false,
    acceptsLedgerFilters: true,
  ),
  ReportTemplateDefinition(
    id: ReportTemplateId.r03EventReview,
    requiresEvent: true,
    acceptsLedgerFilters: false,
  ),
];

/// The single renderer entry point for the shared artifact controller.
ReportTemplateRenderer rendererForTemplate(
  ReportTemplateId template, {
  ReportFontLoader fontLoader = const AssetReportFontLoader(),
}) => switch (template) {
  ReportTemplateId.r01SubstanceSummary => R01SummaryRenderer(
    fontLoader: fontLoader,
  ),
  ReportTemplateId.r02DetailedHistory => R02HistoryRenderer(
    fontLoader: fontLoader,
  ),
  ReportTemplateId.r03EventReview => R03EventRenderer(fontLoader: fontLoader),
};

/// Complete structured text alternative for the reviewed artifact. R02 and R03
/// describe their own body rather than reusing the R01 summary text.
String reportTextFor(ReportSnapshot snapshot, {required bool use24Hour}) {
  final data = snapshot.templateData;
  return switch (snapshot.selection.template) {
    ReportTemplateId.r01SubstanceSummary => snapshot.structuredText(
      use24Hour: use24Hour,
    ),
    ReportTemplateId.r02DetailedHistory =>
      data is ReportHistoryData
          ? data.structuredText(snapshot, use24Hour: use24Hour)
          : throw const ReportSelectionFailure('report_template_data'),
    ReportTemplateId.r03EventReview =>
      data is ReportEventData
          ? data.structuredText(snapshot, use24Hour: use24Hour)
          : throw const ReportSelectionFailure('report_template_data'),
  };
}
