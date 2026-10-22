import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../domain/history/display_time.dart';
import '../../domain/reports/reports.dart';
import '../../domain/scheduling/daily_plan.dart';
import '../report_fonts.dart';

/// Shared typography, page chrome and table cells for R02 and R03.
///
/// These mirror the R01 tokens so every template uses one report face,
/// margin, rule weight and page identity.
abstract final class ReportPalette {
  static const graphite = PdfColor.fromInt(0xFF1F2933);
  static const muted = PdfColor.fromInt(0xFF52606D);
  static const teal = PdfColor.fromInt(0xFF1F6F6B);
  static const rule = PdfColor.fromInt(0xFFD7DDD9);
}

pw.ThemeData reportTheme(ReportFonts fonts) =>
    pw.ThemeData.withFont(base: fonts.regular, bold: fonts.bold).copyWith(
      defaultTextStyle: pw.TextStyle(
        font: fonts.regular,
        fontSize: 9.5,
        color: ReportPalette.graphite,
        lineSpacing: 2,
      ),
      paragraphStyle: pw.TextStyle(
        font: fonts.regular,
        fontSize: 9.5,
        color: ReportPalette.graphite,
        lineSpacing: 2.5,
      ),
      tableHeader: pw.TextStyle(
        font: fonts.bold,
        fontSize: 8.5,
        color: ReportPalette.muted,
      ),
      tableCell: pw.TextStyle(
        font: fonts.regular,
        fontSize: 9,
        color: ReportPalette.graphite,
        lineSpacing: 1.5,
      ),
    );

pw.PageTheme reportPageTheme(pw.ThemeData theme) => pw.PageTheme(
  pageFormat: PdfPageFormat.a4,
  margin: const pw.EdgeInsets.fromLTRB(51, 54, 51, 48),
  theme: theme,
  buildBackground: (_) => pw.FullPage(
    ignoreMargins: true,
    child: pw.Container(color: PdfColors.white),
  ),
);

/// Repeated top identity: person, template version, period and zone.
pw.Widget reportPageHeader(ReportSnapshot snapshot) {
  final selection = snapshot.selection;
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(
            child: pw.Text(
              snapshot.person.displayName,
              style: pw.TextStyle(fontSize: 10, color: ReportPalette.graphite),
            ),
          ),
          pw.Text(
            '${selection.template.id} · Version ${reportTemplateVersion(selection.template)}',
            style: pw.TextStyle(fontSize: 8, color: ReportPalette.muted),
          ),
        ],
      ),
      pw.SizedBox(height: 3),
      pw.Text(
        '${formatCivilDate(selection.fromDate)} to '
        '${formatCivilDate(selection.beforeDate.addDays(-1))} · '
        '${selection.displayZone}',
        style: pw.TextStyle(fontSize: 8, color: ReportPalette.muted),
      ),
      pw.SizedBox(height: 6),
      pw.Divider(color: ReportPalette.rule, thickness: 0.6, height: 1),
    ],
  );
}

/// Repeated footer identity: short name/period plus exact page number.
pw.Widget reportPageFooter(ReportSnapshot snapshot, pw.Context context) {
  final selection = snapshot.selection;
  return pw.Column(
    children: [
      pw.Divider(color: ReportPalette.rule, thickness: 0.6, height: 1),
      pw.SizedBox(height: 4),
      pw.Row(
        children: [
          pw.Expanded(
            child: pw.Text(
              '${snapshot.person.displayName} · '
              '${formatCivilDate(selection.fromDate)} to '
              '${formatCivilDate(selection.beforeDate.addDays(-1))} · '
              'Report ${snapshot.artifactId}',
              style: pw.TextStyle(fontSize: 7.5, color: ReportPalette.muted),
            ),
          ),
          pw.Text(
            'Page ${context.pageNumber} of ${context.pagesCount}',
            style: pw.TextStyle(fontSize: 8, color: ReportPalette.muted),
          ),
        ],
      ),
      pw.SizedBox(height: 2),
      pw.Text(
        'Template ${selection.template.id} v${reportTemplateVersion(selection.template)} · '
        'User-reported records. No treatment or dosing recommendation.',
        style: pw.TextStyle(fontSize: 7.5, color: ReportPalette.muted),
      ),
    ],
  );
}

pw.Widget reportIdentityRow(String label, String value) => pw.Row(
  crossAxisAlignment: pw.CrossAxisAlignment.start,
  children: [
    pw.SizedBox(
      width: 78,
      child: pw.Text(
        label,
        style: pw.TextStyle(fontSize: 8.5, color: ReportPalette.muted),
      ),
    ),
    pw.Expanded(child: pw.Text(value)),
  ],
);

pw.Widget reportSectionHeading(String text) => pw.Container(
  padding: const pw.EdgeInsets.only(bottom: 4),
  decoration: const pw.BoxDecoration(
    border: pw.Border(
      bottom: pw.BorderSide(color: ReportPalette.teal, width: 0.8),
    ),
  ),
  child: pw.Text(
    text,
    style: pw.TextStyle(fontSize: 12, color: ReportPalette.graphite),
  ),
);

pw.Widget reportNote(String text, {double size = 8.5}) => pw.Text(
  text,
  style: pw.TextStyle(fontSize: size, color: ReportPalette.muted),
);

pw.Widget reportScopeBox({required String heading, required String body}) =>
    pw.Container(
      padding: const pw.EdgeInsets.all(9),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: ReportPalette.rule),
        borderRadius: pw.BorderRadius.circular(5),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            heading,
            style: pw.TextStyle(fontSize: 9, color: ReportPalette.graphite),
          ),
          pw.SizedBox(height: 3),
          reportNote(body, size: 8),
        ],
      ),
    );

pw.Widget reportCell(
  String text, {
  bool header = false,
  bool muted = false,
  bool bold = false,
  pw.TextAlign align = pw.TextAlign.left,
}) => pw.Padding(
  padding: const pw.EdgeInsets.symmetric(vertical: 3, horizontal: 4),
  child: pw.Text(
    text,
    textAlign: align,
    style: pw.TextStyle(
      fontSize: header ? 8.5 : 9,
      color: muted ? ReportPalette.muted : ReportPalette.graphite,
      fontWeight: header || bold ? pw.FontWeight.bold : null,
    ),
  ),
);

/// Shared administration ledger used by R02 and R03. Headers repeat on every
/// page and long cells wrap rather than clip.
pw.Widget reportLedgerTable(
  ReportSnapshot snapshot,
  Iterable<ReportLedgerEntry> entries, {
  required bool use24Hour,
  required ReportCancellation cancellation,
}) {
  final zone = snapshot.selection.displayZone;
  return pw.Table(
    border: pw.TableBorder(
      horizontalInside: pw.BorderSide(color: ReportPalette.rule, width: 0.4),
    ),
    columnWidths: const {
      0: pw.FlexColumnWidth(2.4),
      1: pw.FlexColumnWidth(3.7),
      2: pw.FlexColumnWidth(2.0),
      3: pw.FlexColumnWidth(2.9),
    },
    children: [
      pw.TableRow(
        repeat: true,
        children: [
          reportCell('When', header: true),
          reportCell('Item', header: true),
          reportCell('Amount', header: true, align: pw.TextAlign.right),
          reportCell('Status', header: true),
        ],
      ),
      for (final entry in entries)
        if (!cancellation.isCancelled)
          pw.TableRow(
            children: [
              reportCell(ledgerWhenText(entry, zone, use24Hour: use24Hour)),
              reportCell(ledgerItemText(entry, zone, use24Hour: use24Hour)),
              reportCell(ledgerAmountText(entry), align: pw.TextAlign.right),
              reportCell(ledgerStatusText(entry.status)),
            ],
          )
        else
          throw const ReportCancelled(),
    ],
  );
}

String ledgerWhenText(
  ReportLedgerEntry entry,
  String zone, {
  required bool use24Hour,
}) {
  final time = entry.dateOnly
      ? formatCivilDate(ledgerCivil(entry.occurredAt, zone))
      : _ledgerClock(entry.occurredAt, zone, use24Hour);
  return entry.timeNeedsReview ? '$time\nTime needs review' : time;
}

String ledgerItemText(
  ReportLedgerEntry entry,
  String zone, {
  required bool use24Hour,
}) {
  final lines = <String>[entry.name];
  if (entry.form.trim().isNotEmpty) lines.add(entry.form);
  if (!entry.identityComplete) lines.add('Type not recorded');
  if (entry.status == ReportLedgerStatus.corrected && entry.entryAt != null) {
    lines.add(
      'Entered ${formatInstant(entry.entryAt!, zone, use24Hour: use24Hour)}',
    );
  }
  if (entry.site != null) lines.add('Site: ${entry.site}');
  if (entry.contextTags.isNotEmpty) {
    lines.add('Tags: ${entry.contextTags.join(', ')}');
  }
  if (entry.notes != null) lines.add('Note: ${entry.notes}');
  if (entry.skipReason != null) {
    lines.add('Skip reason: ${entry.skipReason}');
  }
  if (entry.planName != null) lines.add('Plan: ${entry.planName}');
  return lines.join('\n');
}

String ledgerAmountText(ReportLedgerEntry entry) {
  if (entry.amount == null) return 'No dose recorded';
  final lines = <String>['${formatAmount(entry.amount!)} ${entry.unit}'];
  final product = entry.product;
  if (product != null) {
    for (final ingredient in product.ingredients) {
      lines.add(
        '${ingredient.name}'
        '${ingredient.strength == null ? '' : ' (${ingredient.strength})'}: '
        '${ingredient.amount == null ? 'Unknown' : '${formatAmount(ingredient.amount!)} ${ingredient.unit}'}',
      );
    }
  }
  return lines.join('\n');
}

String ledgerStatusText(ReportLedgerStatus status) => switch (status) {
  ReportLedgerStatus.recorded => 'Recorded',
  ReportLedgerStatus.corrected => 'Corrected',
  ReportLedgerStatus.skipped => 'Skipped',
  ReportLedgerStatus.notRecorded => 'Not recorded',
};

String _ledgerClock(DateTime instant, String zone, bool use24Hour) {
  final shown = DisplayTime().instant(instant, zone);
  final hour = use24Hour
      ? shown.hour.toString().padLeft(2, '0')
      : (shown.hour % 12 == 0 ? 12 : shown.hour % 12).toString();
  final minute = shown.minute.toString().padLeft(2, '0');
  final period = use24Hour ? '' : (shown.hour < 12 ? ' am' : ' pm');
  return '${formatCivilDate(shown.civilDate)}\n$hour:$minute$period';
}

CivilDate ledgerCivil(DateTime instant, String zone) {
  try {
    return DisplayTime().instant(instant, zone).civilDate;
  } catch (_) {
    return DisplayTime().instant(instant, 'UTC').civilDate;
  }
}

/// Selected supporting records and source files, shared by R01-style context.
pw.Widget reportContextBlock(ReportSnapshot snapshot) {
  final selection = snapshot.selection;
  final details = ReportText.itemDetailLines(snapshot);
  if (!selection.includeSupporting &&
      !selection.includeAttachments &&
      details.isEmpty) {
    return reportNote(
      'Supporting records and source files were not included in this report.',
    );
  }
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      reportSectionHeading('Selected context'),
      pw.SizedBox(height: 6),
      if (selection.includeSupporting) ...[
        if (snapshot.supporting.isEmpty)
          reportNote('No supporting records fall inside this period.')
        else
          pw.Table(
            border: pw.TableBorder(
              horizontalInside: pw.BorderSide(
                color: ReportPalette.rule,
                width: 0.4,
              ),
            ),
            columnWidths: const {
              0: pw.FlexColumnWidth(2.4),
              1: pw.FlexColumnWidth(1.6),
              2: pw.FlexColumnWidth(2.2),
              3: pw.FlexColumnWidth(1.5),
            },
            children: [
              pw.TableRow(
                repeat: true,
                children: [
                  reportCell('Record', header: true),
                  reportCell('Measured', header: true),
                  reportCell('Result', header: true),
                  reportCell('Range', header: true),
                ],
              ),
              for (final entry in snapshot.supporting)
                for (final value in entry.values)
                  pw.TableRow(
                    children: [
                      reportCell(entry.title),
                      reportCell(formatSupportingDate(entry.collectionDate)),
                      reportCell(
                        '${value.name}: ${value.value}'
                        '${value.unit == null ? '' : ' ${value.unit}'}',
                      ),
                      reportCell(value.referenceRange ?? ''),
                    ],
                  ),
            ],
          ),
        if (snapshot.supportingTruncated)
          reportNote(
            'Supporting context is limited to the first 50 records.',
            size: 8,
          ),
        if (ReportText.supportingOmissionNotice(snapshot) case final notice?)
          reportNote(notice, size: 8),
        for (final entry in snapshot.supporting)
          for (final line in ReportText.supportingMetadataLines(entry))
            pw.Text(
              '${entry.title}: $line',
              overflow: pw.TextOverflow.span,
              style: pw.TextStyle(fontSize: 8.5, color: ReportPalette.graphite),
            ),
        for (final entry in snapshot.supporting)
          if (entry.notes != null) ...[
            pw.SizedBox(height: 6),
            pw.Text(
              '${entry.title} note: ${entry.notes}',
              style: pw.TextStyle(fontSize: 8.5, color: ReportPalette.graphite),
            ),
          ],
      ],
      if (details.isNotEmpty) ...[
        pw.SizedBox(height: 10),
        reportSectionHeading(details.first),
        pw.SizedBox(height: 4),
        for (final line in details.skip(1))
          pw.Text(
            line,
            style: pw.TextStyle(fontSize: 8.5, color: ReportPalette.graphite),
          ),
      ],
      if (selection.includeAttachments) ...[
        pw.SizedBox(height: 10),
        pw.Text(
          'Source files',
          style: pw.TextStyle(fontSize: 10, color: ReportPalette.graphite),
        ),
        pw.SizedBox(height: 4),
        if (snapshot.attachments.isEmpty)
          reportNote('No source files were selected.')
        else
          for (final attachment in snapshot.attachments)
            pw.Text(
              '${attachment.name} · ${attachment.byteCount} bytes · ${attachment.sha256}',
              style: pw.TextStyle(fontSize: 8, color: ReportPalette.muted),
            ),
      ],
    ],
  );
}
