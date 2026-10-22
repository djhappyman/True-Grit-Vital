import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../domain/reports/reports.dart';
import 'report_fonts.dart';
import 'report_template.dart';

/// R01: a concise, type-grouped substance summary.
final class R01SummaryRenderer implements ReportTemplateRenderer {
  const R01SummaryRenderer({this.fontLoader = const AssetReportFontLoader()});

  final ReportFontLoader fontLoader;

  static const _graphite = PdfColor.fromInt(0xFF1F2933);
  static const _muted = PdfColor.fromInt(0xFF52606D);
  static const _teal = PdfColor.fromInt(0xFF1F6F6B);
  static const _rule = PdfColor.fromInt(0xFFD7DDD9);

  @override
  ReportTemplateId get template => ReportTemplateId.r01SubstanceSummary;

  @override
  String get version => reportTemplateVersion(template);

  @override
  Future<ReportRenderedDocument> render(
    ReportSnapshot snapshot, {
    required bool use24Hour,
    ReportCancellation cancellation = const NeverCancelled(),
    void Function(int completed, int total)? onProgress,
  }) async {
    if (cancellation.isCancelled) throw const ReportCancelled();
    if (snapshot.totals.itemCount > 1200) {
      throw const ReportSelectionFailure('report_page_limit');
    }
    final fonts = await fontLoader.load();
    if (cancellation.isCancelled) throw const ReportCancelled();
    final theme = pw.ThemeData.withFont(base: fonts.regular, bold: fonts.bold)
        .copyWith(
          defaultTextStyle: pw.TextStyle(
            font: fonts.regular,
            fontSize: 9.5,
            color: _graphite,
            lineSpacing: 2,
          ),
          paragraphStyle: pw.TextStyle(
            font: fonts.regular,
            fontSize: 9.5,
            color: _graphite,
            lineSpacing: 2.5,
          ),
          tableHeader: pw.TextStyle(
            font: fonts.bold,
            fontSize: 8.5,
            color: _muted,
          ),
          tableCell: pw.TextStyle(
            font: fonts.regular,
            fontSize: 9,
            color: _graphite,
            lineSpacing: 1.5,
          ),
        );
    final document = pw.Document(
      title: 'Substance summary',
      author: '',
      creator: 'True Grit Vital',
      subject: 'Recorded substance summary',
      producer: 'True Grit Vital',
      keywords: '',
      theme: theme,
    );
    final selection = snapshot.selection;
    final totalGroups = snapshot.totals.groups.length;
    var completed = 0;
    onProgress?.call(completed, totalGroups + 1);

    final content = <pw.Widget>[
      _identityBlock(snapshot, use24Hour),
      pw.SizedBox(height: 16),
      _countsBlock(snapshot),
      pw.SizedBox(height: 6),
      pw.Text(
        'Private notes are ${selection.includeNotes ? 'included where recorded' : 'not included'}. '
        'Source files are ${selection.includeAttachments ? 'listed separately' : 'not included'}. '
        'Supporting context is ${selection.includeSupporting ? 'included' : 'not included'}.',
        style: pw.TextStyle(fontSize: 8.5, color: _muted),
      ),
      pw.SizedBox(height: 6),
      pw.Text(
        'This report lists recorded entries. It does not confirm that a dose was taken, '
        'does not prove that no dose was missed, and is not medical advice.',
        style: pw.TextStyle(fontSize: 8.5, color: _muted),
      ),
      pw.SizedBox(height: 18),
    ];
    if (snapshot.totals.limitReached) {
      content
        ..add(
          pw.Container(
            padding: const pw.EdgeInsets.all(8),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: _rule),
              borderRadius: pw.BorderRadius.circular(4),
            ),
            child: pw.Text(
              'One or more totals were too large to display. Narrow the period or item selection.',
            ),
          ),
        )
        ..add(pw.SizedBox(height: 12));
    }
    for (final group in snapshot.totals.groups) {
      if (cancellation.isCancelled) throw const ReportCancelled();
      content
        ..add(_typeHeading(group.type))
        ..add(pw.SizedBox(height: 6));
      if (group.items.isNotEmpty) {
        content
          ..addAll(_itemTables(group.items))
          ..add(pw.SizedBox(height: 12));
      }
      if (group.products.isNotEmpty) {
        content
          ..add(
            pw.Text(
              'Ready-mixed products',
              style: pw.TextStyle(font: fonts.bold, fontSize: 10, color: _teal),
            ),
          )
          ..add(pw.SizedBox(height: 4))
          ..addAll(_productTables(group.products))
          ..add(pw.SizedBox(height: 12));
      }
      completed++;
      onProgress?.call(completed, totalGroups + 1);
    }
    content.addAll(_contextBlock(snapshot, use24Hour));
    content.add(pw.SizedBox(height: 18));
    content.addAll(_recentBlock(snapshot, use24Hour, cancellation));
    content.addAll(_stockBlock(snapshot, use24Hour));
    content.add(pw.SizedBox(height: 12));
    completed++;
    onProgress?.call(completed, totalGroups + 1);
    if (cancellation.isCancelled) throw const ReportCancelled();

    document.addPage(
      pw.MultiPage(
        pageTheme: pw.PageTheme(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.fromLTRB(51, 54, 51, 48),
          theme: theme,
          buildBackground: (_) => pw.FullPage(
            ignoreMargins: true,
            child: pw.Container(color: PdfColors.white),
          ),
        ),
        maxPages: 200,
        header: (context) => _header(snapshot),
        footer: (context) => _footer(snapshot, context),
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

  pw.Widget _header(ReportSnapshot snapshot) {
    final selection = snapshot.selection;
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: pw.Text(
                snapshot.person.name,
                style: pw.TextStyle(fontSize: 10, color: _graphite),
              ),
            ),
            pw.Text(
              'R01 · Version ${reportTemplateVersion(selection.template)}',
              style: pw.TextStyle(fontSize: 8, color: _muted),
            ),
          ],
        ),
        pw.SizedBox(height: 3),
        pw.Text(
          '${formatCivilDate(selection.fromDate)} to '
          '${formatCivilDate(selection.beforeDate.addDays(-1))} · '
          '${selection.displayZone}',
          style: pw.TextStyle(fontSize: 8, color: _muted),
        ),
        pw.SizedBox(height: 6),
        pw.Divider(color: _rule, thickness: 0.6, height: 1),
      ],
    );
  }

  pw.Widget _footer(ReportSnapshot snapshot, pw.Context context) => pw.Column(
    children: [
      pw.Divider(color: _rule, thickness: 0.6, height: 1),
      pw.SizedBox(height: 4),
      pw.Row(
        children: [
          pw.Expanded(
            child: pw.Text(
              'Report ${snapshot.artifactId} · R01 v${reportTemplateVersion(snapshot.selection.template)}',
              style: pw.TextStyle(fontSize: 8, color: _muted),
            ),
          ),
          pw.Text(
            'Page ${context.pageNumber} of ${context.pagesCount}',
            style: pw.TextStyle(fontSize: 8, color: _muted),
          ),
        ],
      ),
    ],
  );

  pw.Widget _identityBlock(ReportSnapshot snapshot, bool use24Hour) {
    final selection = snapshot.selection;
    final reportName = snapshot.reportIdentity;
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'Substance summary',
          style: pw.TextStyle(fontSize: 22, color: _teal),
        ),
        pw.SizedBox(height: 10),
        if (reportName != null && reportName.isNotEmpty) ...[
          _identityRow('Report', reportName),
          pw.SizedBox(height: 3),
        ],
        _identityRow('Person', snapshot.person.name),
        pw.SizedBox(height: 3),
        _identityRow(
          'Period',
          '${formatCivilDate(selection.fromDate)} to '
              '${formatCivilDate(selection.beforeDate.addDays(-1))}',
        ),
        pw.SizedBox(height: 3),
        _identityRow('Time zone', selection.displayZone),
        pw.SizedBox(height: 3),
        _identityRow(
          'Generated',
          formatInstant(
            snapshot.cutoff.generatedAt,
            selection.displayZone,
            use24Hour: use24Hour,
          ),
        ),
        pw.SizedBox(height: 3),
        _identityRow(
          'Scope',
          selection.itemIds.isEmpty
              ? 'All items in the period'
              : '${selection.itemIds.length} selected items',
        ),
      ],
    );
  }

  pw.Widget _identityRow(String label, String value) => pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.SizedBox(
        width: 70,
        child: pw.Text(
          label,
          style: pw.TextStyle(fontSize: 8.5, color: _muted),
        ),
      ),
      pw.Expanded(child: pw.Text(value)),
    ],
  );

  pw.Widget _countsBlock(ReportSnapshot snapshot) => pw.Container(
    padding: const pw.EdgeInsets.all(10),
    decoration: pw.BoxDecoration(
      border: pw.Border.all(color: _rule),
      borderRadius: pw.BorderRadius.circular(5),
    ),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          '${snapshot.totals.recordCount} recorded doses · '
          '${snapshot.totals.itemCount} items · '
          '${snapshot.totals.typeCount} types',
          style: pw.TextStyle(fontSize: 10, color: _graphite),
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          'Doses count recorded administrations. Items and types group those administrations. '
          'Only current revisions are included; voided records are excluded.',
          style: pw.TextStyle(fontSize: 8, color: _muted),
        ),
      ],
    ),
  );

  pw.Widget _typeHeading(String type) => pw.Container(
    padding: const pw.EdgeInsets.only(bottom: 4),
    decoration: const pw.BoxDecoration(
      border: pw.Border(bottom: pw.BorderSide(color: _teal, width: 0.8)),
    ),
    child: pw.Text(
      type.isEmpty ? 'Other' : type,
      style: pw.TextStyle(fontSize: 12, color: _graphite),
    ),
  );

  List<pw.Widget> _itemTables(List<ReportItemTotal> items) => _rowsTable(
    header: const ['Item', 'Form', 'Doses', 'Total'],
    rows: [
      for (final item in items)
        [
          item.name,
          item.form,
          '${item.count}',
          item.total == null
              ? 'Unavailable'
              : '${formatAmount(item.total!)} ${item.unit}',
        ],
    ],
    widths: const [210, 95, 60, 128],
    aligns: const [
      pw.TextAlign.left,
      pw.TextAlign.left,
      pw.TextAlign.right,
      pw.TextAlign.right,
    ],
  );

  List<pw.Widget> _productTables(
    List<ReportProductTotal> products,
  ) => _rowsTable(
    header: const ['Product', 'Form', 'Doses', 'Volume'],
    rows: [
      for (final product in products) ...[
        [
          product.name,
          product.form,
          '${product.administrations}',
          product.volume == null
              ? 'Unavailable'
              : '${formatAmount(product.volume!)} ${product.volumeUnit}',
        ],
        for (final ingredient in product.ingredients)
          [
            '  ${ingredient.name}'
                '${ingredient.strength == null ? '' : ' (${ingredient.strength})'}',
            'Ingredient',
            '',
            ingredient.complete
                ? '${formatAmount(ingredient.knownSubtotal!)} ${ingredient.unit}'
                : 'Unknown',
          ],
      ],
    ],
    widths: const [200, 90, 60, 143],
    aligns: const [
      pw.TextAlign.left,
      pw.TextAlign.left,
      pw.TextAlign.right,
      pw.TextAlign.right,
    ],
  );

  /// Uses a spanning table so headings stay with the data and repeat on each
  /// page, including pages created by wrapped names or supporting values.
  List<pw.Widget> _rowsTable({
    required List<String> header,
    required List<List<String>> rows,
    required List<double> widths,
    required List<pw.TextAlign> aligns,
  }) {
    if (rows.isEmpty) return const [];
    pw.Widget cell(String text, int index, {bool heading = false}) =>
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 3, horizontal: 2),
          child: pw.Text(
            text,
            textAlign: aligns[index],
            style: pw.TextStyle(
              fontSize: heading ? 8.5 : 9,
              color: heading ? _muted : _graphite,
              fontWeight: heading ? pw.FontWeight.bold : null,
            ),
          ),
        );
    return [
      pw.Table(
        border: pw.TableBorder(
          horizontalInside: pw.BorderSide(color: _rule, width: 0.4),
        ),
        columnWidths: {
          for (var index = 0; index < widths.length; index++)
            index: pw.FlexColumnWidth(widths[index]),
        },
        children: [
          pw.TableRow(
            repeat: true,
            children: [
              for (var index = 0; index < header.length; index++)
                cell(header[index], index, heading: true),
            ],
          ),
          for (final row in rows)
            pw.TableRow(
              children: [
                for (var index = 0; index < row.length; index++)
                  cell(row[index], index),
              ],
            ),
        ],
      ),
    ];
  }

  List<pw.Widget> _contextBlock(ReportSnapshot snapshot, bool use24Hour) {
    final selection = snapshot.selection;
    final details = ReportText.reportDetailLines(snapshot);
    if (!selection.includeSupporting &&
        !selection.includeAttachments &&
        details.isEmpty) {
      return [
        pw.Text(
          'Supporting records and source files were not included in this report.',
          style: pw.TextStyle(fontSize: 8.5, color: _muted),
        ),
      ];
    }
    final content = <pw.Widget>[
      pw.Text(
        'Selected context',
        style: pw.TextStyle(fontSize: 12, color: _graphite),
      ),
      pw.SizedBox(height: 6),
    ];
    if (selection.includeSupporting) {
      if (snapshot.supporting.isEmpty) {
        content.add(
          pw.Text(
            'No supporting records fall inside this period.',
            style: pw.TextStyle(fontSize: 8.5, color: _muted),
          ),
        );
      } else {
        content.addAll(
          _rowsTable(
            header: const ['Record', 'Measured', 'Result', 'Range'],
            rows: [
              for (final entry in snapshot.supporting)
                for (final value in entry.values)
                  [
                    entry.title,
                    formatSupportingDate(entry.collectionDate),
                    '${value.name}: ${value.value}'
                        '${value.unit == null ? '' : ' ${value.unit}'}',
                    value.referenceRange ?? '',
                  ],
            ],
            widths: const [145, 95, 145, 108],
            aligns: const [
              pw.TextAlign.left,
              pw.TextAlign.left,
              pw.TextAlign.left,
              pw.TextAlign.left,
            ],
          ),
        );
      }
      if (snapshot.supportingTruncated) {
        content.add(
          pw.Text(
            'Supporting context is limited to the first 50 records.',
            style: pw.TextStyle(fontSize: 8, color: _muted),
          ),
        );
      }
      final omission = ReportText.supportingOmissionNotice(snapshot);
      if (omission != null) {
        content.add(
          pw.Text(omission, style: pw.TextStyle(fontSize: 8, color: _muted)),
        );
      }
      for (final entry in snapshot.supporting) {
        for (final line in ReportText.supportingMetadataLines(entry)) {
          content.add(
            pw.Text(
              '${entry.title}: $line',
              overflow: pw.TextOverflow.span,
              style: pw.TextStyle(fontSize: 8.5, color: _graphite),
            ),
          );
        }
      }
      for (final entry in snapshot.supporting) {
        if (entry.notes == null) continue;
        content
          ..add(pw.SizedBox(height: 6))
          ..add(
            pw.Text(
              '${entry.title} note: ${entry.notes}',
              style: pw.TextStyle(fontSize: 8.5, color: _graphite),
            ),
          );
      }
    }
    if (details.isNotEmpty) {
      content
        ..add(pw.SizedBox(height: 10))
        ..add(
          pw.Text(
            details.first,
            style: pw.TextStyle(fontSize: 10, color: _graphite),
          ),
        )
        ..add(pw.SizedBox(height: 4));
      for (final line in details.skip(1)) {
        content.add(
          pw.Text(
            line,
            overflow: pw.TextOverflow.span,
            style: pw.TextStyle(fontSize: 8.5, color: _graphite),
          ),
        );
      }
    }
    if (selection.includeAttachments) {
      content
        ..add(pw.SizedBox(height: 10))
        ..add(
          pw.Text(
            'Source files',
            style: pw.TextStyle(fontSize: 10, color: _graphite),
          ),
        )
        ..add(pw.SizedBox(height: 4));
      if (snapshot.attachments.isEmpty) {
        content.add(
          pw.Text(
            'No source files were selected.',
            style: pw.TextStyle(fontSize: 8.5, color: _muted),
          ),
        );
      } else {
        for (final attachment in snapshot.attachments) {
          content.add(
            pw.Text(
              '${attachment.name} · ${attachment.byteCount} bytes · ${attachment.sha256}',
              style: pw.TextStyle(fontSize: 8, color: _muted),
            ),
          );
        }
      }
    }
    return content;
  }

  List<pw.Widget> _stockBlock(ReportSnapshot snapshot, bool use24Hour) {
    if (!snapshot.selection.includeStock) return const [];
    final recent = snapshot.recentRecords();
    final linked = [
      for (final record in recent)
        if (record.stockSource != null) record,
    ];
    final coverage = ReportText.stockCoverageNote(
      snapshot.records.map((record) => record.stockSource),
    );
    return [
      pw.SizedBox(height: 14),
      pw.Text(
        'Stock source details',
        style: pw.TextStyle(fontSize: 12, color: _graphite),
      ),
      pw.SizedBox(height: 4),
      pw.Text(
        ReportText.stockSourceDisclosure,
        style: pw.TextStyle(fontSize: 8, color: _muted),
      ),
      if (coverage != null) ...[
        pw.SizedBox(height: 2),
        pw.Text(coverage, style: pw.TextStyle(fontSize: 8, color: _muted)),
      ],
      if (linked.isNotEmpty) ...[
        pw.SizedBox(height: 6),
        ..._rowsTable(
          header: const ['When', 'Item', 'Amount', 'Stock source'],
          rows: [
            for (final record in linked)
              [
                formatInstant(
                  record.actualAt,
                  snapshot.selection.displayZone,
                  use24Hour: use24Hour,
                ),
                record.name,
                '${formatAmount(record.amount)} ${record.unit}',
                ReportText.stockSourceText(record.stockSource!),
              ],
          ],
          widths: const [105, 125, 75, 188],
          aligns: const [
            pw.TextAlign.left,
            pw.TextAlign.left,
            pw.TextAlign.right,
            pw.TextAlign.left,
          ],
        ),
      ],
    ];
  }

  List<pw.Widget> _recentBlock(
    ReportSnapshot snapshot,
    bool use24Hour,
    ReportCancellation cancellation,
  ) {
    final recent = snapshot.recentRecords();
    final rows = <List<String>>[];
    for (final record in recent) {
      if (cancellation.isCancelled) throw const ReportCancelled();
      rows.add([
        formatInstant(
          record.actualAt,
          snapshot.selection.displayZone,
          use24Hour: use24Hour,
        ),
        record.name,
        '${formatAmount(record.amount)} ${record.unit}',
        record.type,
      ]);
    }
    return [
      pw.Text(
        'Recent doses',
        style: pw.TextStyle(fontSize: 12, color: _graphite),
      ),
      pw.SizedBox(height: 4),
      pw.Text(
        snapshot.records.length > recent.length
            ? 'Showing the latest ${recent.length} of ${snapshot.records.length} recorded doses.'
            : 'All ${recent.length} recorded doses in the period.',
        style: pw.TextStyle(fontSize: 8, color: _muted),
      ),
      pw.SizedBox(height: 6),
      ..._rowsTable(
        header: const ['When', 'Item', 'Amount', 'Type'],
        rows: rows,
        widths: const [130, 190, 90, 83],
        aligns: const [
          pw.TextAlign.left,
          pw.TextAlign.left,
          pw.TextAlign.right,
          pw.TextAlign.left,
        ],
      ),
    ];
  }
}
