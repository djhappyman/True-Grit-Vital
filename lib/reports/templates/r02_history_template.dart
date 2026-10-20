import 'dart:typed_data';

import 'package:pdf/widgets.dart' as pw;

import '../../domain/reports/reports.dart';
import '../report_fonts.dart';
import '../report_template.dart';
import 'report_layout.dart';

/// R02: a paginated ledger of recorded, corrected, skipped and not-recorded
/// rows, with compatible totals and repeated page identity.
final class R02HistoryRenderer implements ReportTemplateRenderer {
  const R02HistoryRenderer({this.fontLoader = const AssetReportFontLoader()});

  final ReportFontLoader fontLoader;

  @override
  ReportTemplateId get template => ReportTemplateId.r02DetailedHistory;

  @override
  String get version => reportTemplateVersion(template);

  @override
  Future<ReportRenderedDocument> render(
    ReportSnapshot snapshot, {
    required bool use24Hour,
    ReportCancellation cancellation = const NeverCancelled(),
    void Function(int completed, int total)? onProgress,
  }) async {
    final data = snapshot.templateData;
    if (data is! ReportHistoryData) {
      throw const ReportSelectionFailure('report_template_data');
    }
    if (cancellation.isCancelled) throw const ReportCancelled();
    final fonts = await fontLoader.load();
    if (cancellation.isCancelled) throw const ReportCancelled();
    final theme = reportTheme(fonts);
    final document = pw.Document(
      title: 'Detailed history',
      author: '',
      creator: 'True Grit Vital',
      subject: 'Recorded detailed history',
      producer: 'True Grit Vital',
      keywords: '',
      theme: theme,
    );
    final totalPages = 12 + (data.entries.length ~/ 100);
    var completed = 0;
    onProgress?.call(completed, totalPages);

    final content = <pw.Widget>[
      _titleBlock(snapshot, data, use24Hour),
      pw.SizedBox(height: 10),
      reportScopeBox(heading: 'Report scope', body: _scopeText(snapshot, data)),
      if (data.coverageNote != null) ...[
        pw.SizedBox(height: 6),
        reportNote(data.coverageNote!),
      ],
      pw.SizedBox(height: 16),
      reportSectionHeading('Administration ledger'),
      pw.SizedBox(height: 6),
      reportNote(
        'Ordered by actual taken time for administrations and planned time for '
        'skipped or not-recorded rows. Entry time stays separate.',
        size: 8,
      ),
      pw.SizedBox(height: 6),
      if (cancellation.isCancelled) throw const ReportCancelled(),
      reportLedgerTable(
        snapshot,
        data.entries,
        use24Hour: use24Hour,
        cancellation: cancellation,
      ),
      pw.SizedBox(height: 16),
    ];
    if (snapshot.totals.groups.isNotEmpty) {
      content
        ..add(reportSectionHeading('Compatible totals'))
        ..add(pw.SizedBox(height: 4))
        ..add(
          reportNote(
            'Doses count administrations. Ingredient rows are amounts within '
            'the same administrations, not extra doses. Totals group '
            'administrations by item and keep unlike units and product '
            'strengths separate. Ready-mixed volume is counted once alongside '
            'its ingredient amounts.',
            size: 8,
          ),
        )
        ..add(pw.SizedBox(height: 6))
        ..add(_totalsBlock(snapshot));
      completed++;
      onProgress?.call(completed, totalPages);
    }
    content
      ..add(pw.SizedBox(height: 14))
      ..add(reportContextBlock(snapshot))
      ..add(pw.SizedBox(height: 12))
      ..add(
        reportNote(
          'Recorded rows are reported entries, not proof that a dose was taken. '
          'A not-recorded row means no dose and no explicit skip were saved for '
          'a planned occurrence. It does not prove the dose was missed. '
          'This report is not medical advice.',
        ),
      );
    if (cancellation.isCancelled) throw const ReportCancelled();
    completed++;
    onProgress?.call(completed, totalPages);

    document.addPage(
      pw.MultiPage(
        pageTheme: reportPageTheme(theme),
        maxPages: 2000,
        header: (_) => reportPageHeader(snapshot),
        footer: (context) => reportPageFooter(snapshot, context),
        build: (_) {
          if (cancellation.isCancelled) throw const ReportCancelled();
          return content;
        },
      ),
    );
    final pageCount = document.document.pdfPageList.pages.length;
    final bytes = await document.save(enableEventLoopBalancing: true);
    if (cancellation.isCancelled) throw const ReportCancelled();
    return ReportRenderedDocument(
      bytes: Uint8List.fromList(bytes),
      pageCount: pageCount,
      fontsEmbedded: fonts.embedded,
    );
  }

  pw.Widget _titleBlock(
    ReportSnapshot snapshot,
    ReportHistoryData data,
    bool use24Hour,
  ) {
    final selection = snapshot.selection;
    final reportName = snapshot.reportIdentity;
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'Detailed history',
          style: pw.TextStyle(fontSize: 22, color: ReportPalette.teal),
        ),
        pw.SizedBox(height: 10),
        if (reportName != null && reportName.isNotEmpty) ...[
          reportIdentityRow('Report', reportName),
          pw.SizedBox(height: 3),
        ],
        reportIdentityRow('Person', snapshot.person.displayName),
        pw.SizedBox(height: 3),
        reportIdentityRow(
          'Period',
          '${formatCivilDate(selection.fromDate)} to '
              '${formatCivilDate(selection.beforeDate.addDays(-1))}',
        ),
        pw.SizedBox(height: 3),
        reportIdentityRow('Time zone', selection.displayZone),
        pw.SizedBox(height: 3),
        reportIdentityRow(
          'Generated',
          formatInstant(
            snapshot.cutoff.generatedAt,
            selection.displayZone,
            use24Hour: use24Hour,
          ),
        ),
        pw.SizedBox(height: 3),
        reportIdentityRow(
          'Rows',
          '${data.entries.length} · ${data.recordedCount} recorded · '
              '${data.correctedCount} corrected · ${data.skippedCount} skipped · '
              '${data.notRecordedCount} not recorded',
        ),
      ],
    );
  }

  String _scopeText(ReportSnapshot snapshot, ReportHistoryData data) {
    final selection = snapshot.selection;
    if (data.entries.isEmpty) {
      return 'No ledger rows fall inside this period for '
          '${snapshot.person.displayName}.';
    }
    return 'Included types: ${data.typeLabels.join(', ')}. '
        'Recorded and corrected rows always appear; skipped rows are '
        '${selection.includeSkipped ? 'included' : 'not included'}; '
        'not-recorded rows are '
        '${selection.includeUnrecorded ? 'included' : 'not included'}. '
        'Only ${snapshot.person.displayName} is included.';
  }

  pw.Widget _totalsBlock(ReportSnapshot snapshot) => pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      for (final group in snapshot.totals.groups) ...[
        pw.Text(
          group.type.isEmpty ? 'Uncategorised' : group.type,
          style: pw.TextStyle(fontSize: 10, color: ReportPalette.teal),
        ),
        pw.SizedBox(height: 3),
        if (group.items.isNotEmpty)
          pw.Table(
            border: pw.TableBorder(
              horizontalInside: pw.BorderSide(
                color: ReportPalette.rule,
                width: 0.4,
              ),
            ),
            columnWidths: const {
              0: pw.FlexColumnWidth(3.2),
              1: pw.FlexColumnWidth(1.7),
              2: pw.FlexColumnWidth(0.9),
              3: pw.FlexColumnWidth(1.9),
            },
            children: [
              pw.TableRow(
                repeat: true,
                children: [
                  reportCell('Item', header: true),
                  reportCell('Form', header: true),
                  reportCell('Doses', header: true, align: pw.TextAlign.right),
                  reportCell('Total', header: true, align: pw.TextAlign.right),
                ],
              ),
              for (final item in group.items)
                pw.TableRow(
                  children: [
                    reportCell(item.name),
                    reportCell(item.form),
                    reportCell('${item.count}', align: pw.TextAlign.right),
                    reportCell(
                      item.total == null
                          ? 'Unavailable'
                          : '${formatAmount(item.total!)} ${item.unit}',
                      align: pw.TextAlign.right,
                    ),
                  ],
                ),
            ],
          ),
        if (group.products.isNotEmpty) ...[
          pw.SizedBox(height: 4),
          pw.Table(
            border: pw.TableBorder(
              horizontalInside: pw.BorderSide(
                color: ReportPalette.rule,
                width: 0.4,
              ),
            ),
            columnWidths: const {
              0: pw.FlexColumnWidth(3),
              1: pw.FlexColumnWidth(1.4),
              2: pw.FlexColumnWidth(0.9),
              3: pw.FlexColumnWidth(1.9),
            },
            children: [
              pw.TableRow(
                repeat: true,
                children: [
                  reportCell('Product', header: true),
                  reportCell('Form', header: true),
                  reportCell('Doses', header: true, align: pw.TextAlign.right),
                  reportCell('Volume', header: true, align: pw.TextAlign.right),
                ],
              ),
              for (final product in group.products) ...[
                pw.TableRow(
                  children: [
                    reportCell(product.name),
                    reportCell(product.form),
                    reportCell(
                      '${product.administrations}',
                      align: pw.TextAlign.right,
                    ),
                    reportCell(
                      product.volume == null
                          ? 'Unavailable'
                          : '${formatAmount(product.volume!)} ${product.volumeUnit}',
                      align: pw.TextAlign.right,
                    ),
                  ],
                ),
                for (final ingredient in product.ingredients)
                  pw.TableRow(
                    children: [
                      reportCell(
                        '  ${ingredient.name}'
                        '${ingredient.strength == null ? '' : ' (${ingredient.strength})'}',
                        muted: true,
                      ),
                      reportCell('Ingredient', muted: true),
                      reportCell('', align: pw.TextAlign.right),
                      reportCell(
                        ingredient.complete
                            ? '${formatAmount(ingredient.knownSubtotal!)} '
                                  '${ingredient.unit}'
                            : 'Unknown',
                        align: pw.TextAlign.right,
                      ),
                    ],
                  ),
              ],
            ],
          ),
        ],
        pw.SizedBox(height: 10),
      ],
      if (snapshot.totals.limitReached)
        reportNote(
          'One or more totals were too large to display. Narrow the period or item selection.',
        ),
    ],
  );
}
