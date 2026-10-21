import 'dart:typed_data';

import 'package:pdf/widgets.dart' as pw;

import '../../domain/events/events.dart';
import '../../domain/reports/reports.dart';
import '../report_fonts.dart';
import '../report_template.dart';
import 'report_layout.dart';

/// R03: one recorded event, its member items and the administrations that fall
/// inside it. The event is a grouping; member use periods stay separate.
final class R03EventRenderer implements ReportTemplateRenderer {
  const R03EventRenderer({this.fontLoader = const AssetReportFontLoader()});

  final ReportFontLoader fontLoader;

  @override
  ReportTemplateId get template => ReportTemplateId.r03EventReview;

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
    if (data is! ReportEventData) {
      throw const ReportSelectionFailure('report_template_data');
    }
    if (cancellation.isCancelled) throw const ReportCancelled();
    final fonts = await fontLoader.load();
    if (cancellation.isCancelled) throw const ReportCancelled();
    final theme = reportTheme(fonts);
    final document = pw.Document(
      title: 'Event review',
      author: '',
      creator: 'True Grit Vital',
      subject: 'Recorded event review',
      producer: 'True Grit Vital',
      keywords: '',
      theme: theme,
    );
    final totalPages =
        12 + (data.members.length ~/ 20) + (data.entries.length ~/ 100);
    var completed = 0;
    onProgress?.call(completed, totalPages);

    final content = <pw.Widget>[
      _titleBlock(snapshot, data, use24Hour),
      pw.SizedBox(height: 10),
      reportScopeBox(heading: 'Event scope', body: _scopeText(snapshot, data)),
      if (data.boundsNeedReview) ...[
        pw.SizedBox(height: 6),
        reportNote(
          'Event dates need review. Some planned or actual bounds could not be '
          'resolved in the event zone.',
        ),
      ],
      if (!data.scopeComplete) ...[
        pw.SizedBox(height: 6),
        reportNote(
          'Some event dates could not be resolved, so skipped and not-recorded '
          'counts may be incomplete.',
        ),
      ],
      pw.SizedBox(height: 16),
      _countsBox(data),
      if (data.notes.isNotEmpty) ...[
        pw.SizedBox(height: 12),
        reportSectionHeading('Event notes'),
        pw.SizedBox(height: 6),
        pw.Text(data.notes, overflow: pw.TextOverflow.span),
      ],
      pw.SizedBox(height: 16),
      reportSectionHeading('Event members'),
      pw.SizedBox(height: 6),
      reportNote(
        'Recorded use is scoped to this event. A member use period and its plan '
        'remain separate from the event grouping.',
        size: 8,
      ),
      pw.SizedBox(height: 6),
      _memberTable(snapshot, data, use24Hour),
      pw.SizedBox(height: 16),
      reportSectionHeading('Recorded administrations'),
      pw.SizedBox(height: 6),
      if (data.entries.isEmpty)
        reportNote(
          'No current administration revisions fall inside this event.',
        )
      else
        reportLedgerTable(
          snapshot,
          data.entries,
          use24Hour: use24Hour,
          cancellation: cancellation,
        ),
      pw.SizedBox(height: 14),
      reportContextBlock(snapshot),
      pw.SizedBox(height: 12),
      reportNote(
        'An event is a grouping. The event end does not mean every included item '
        'stopped; item use periods remain separate. Recorded entries are not proof '
        'of use and this report is not a treatment recommendation.',
      ),
    ];
    completed++;
    onProgress?.call(completed, totalPages);
    if (cancellation.isCancelled) throw const ReportCancelled();

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
    ReportEventData data,
    bool use24Hour,
  ) {
    final selection = snapshot.selection;
    final reportName = snapshot.reportIdentity;
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'Event review',
          style: pw.TextStyle(fontSize: 22, color: ReportPalette.teal),
        ),
        pw.SizedBox(height: 10),
        if (reportName != null && reportName.isNotEmpty) ...[
          reportIdentityRow('Report', reportName),
          pw.SizedBox(height: 3),
        ],
        reportIdentityRow('Person', snapshot.person.displayName),
        pw.SizedBox(height: 3),
        reportIdentityRow('Event', data.name),
        pw.SizedBox(height: 3),
        reportIdentityRow('Type', data.eventType),
        pw.SizedBox(height: 3),
        reportIdentityRow('Event zone', data.zoneId),
        pw.SizedBox(height: 3),
        reportIdentityRow(
          'Planned',
          _range(data.plannedStart, data.plannedEnd, data.zoneId, use24Hour),
        ),
        pw.SizedBox(height: 3),
        reportIdentityRow(
          'Actual',
          _range(data.actualStart, data.recordedEnd, data.zoneId, use24Hour),
        ),
        pw.SizedBox(height: 3),
        reportIdentityRow('State', data.ongoing ? 'Ongoing' : 'Ended'),
        if (data.completedAt != null) ...[
          pw.SizedBox(height: 3),
          reportIdentityRow(
            'Completed',
            formatInstant(
              data.completedAt!,
              selection.displayZone,
              use24Hour: use24Hour,
            ),
          ),
        ],
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
      ],
    );
  }

  String _scopeText(ReportSnapshot snapshot, ReportEventData data) {
    final selection = snapshot.selection;
    final ongoing = data.ongoingMembers.length;
    final memberWord = data.members.length == 1 ? 'member' : 'members';
    final ongoingText = ongoing == 1
        ? '1 member has an open use period.'
        : '$ongoing members have an open use period.';
    return 'Includes ${data.members.length} event $memberWord and '
        '${data.entries.length} recorded administrations for '
        '${snapshot.person.displayName}. $ongoingText '
        'Supporting records are ${selection.includeSupporting ? 'included' : 'not included'}. '
        'Source files are ${selection.includeAttachments ? 'listed' : 'not included'}.';
  }

  pw.Widget _countsBox(ReportEventData data) => pw.Container(
    padding: const pw.EdgeInsets.all(10),
    decoration: pw.BoxDecoration(
      border: pw.Border.all(color: ReportPalette.rule),
      borderRadius: pw.BorderRadius.circular(5),
    ),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          '${data.entries.length} recorded administrations · '
          '${data.skippedCount} explicitly skipped · '
          '${data.notRecordedCount} not recorded',
          style: pw.TextStyle(fontSize: 10, color: ReportPalette.graphite),
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          'Skipped and not-recorded states are counted separately and are not '
          'administrations. They do not prove a dose was missed.',
          style: pw.TextStyle(fontSize: 8, color: ReportPalette.muted),
        ),
      ],
    ),
  );

  pw.Widget _memberTable(
    ReportSnapshot snapshot,
    ReportEventData data,
    bool use24Hour,
  ) => pw.Table(
    border: pw.TableBorder(
      horizontalInside: pw.BorderSide(color: ReportPalette.rule, width: 0.4),
    ),
    columnWidths: const {
      0: pw.FlexColumnWidth(3.2),
      1: pw.FlexColumnWidth(3.5),
      2: pw.FlexColumnWidth(2.4),
    },
    children: [
      pw.TableRow(
        repeat: true,
        children: [
          reportCell('Member', header: true),
          reportCell('Recorded use', header: true, align: pw.TextAlign.right),
          reportCell('Use state', header: true),
        ],
      ),
      for (final member in data.members)
        pw.TableRow(
          children: [
            reportCell('${member.typeLabel}\n${member.name}'),
            reportCell(_memberUse(member), align: pw.TextAlign.right),
            reportCell(_memberState(member, data.zoneId, use24Hour)),
          ],
        ),
    ],
  );

  String _memberUse(ReportEventMember member) => reportEventMemberUse(member);

  String _memberState(ReportEventMember member, String zone, bool use24Hour) {
    final end = member.usePeriodEnd;
    return switch (member.useStatus) {
      ReportUseStatus.ongoing => 'Ongoing separately',
      ReportUseStatus.ended =>
        end == null
            ? 'Use period ended'
            : 'Use period ended\n${formatEventDate(end, zone, use24Hour: use24Hour)}',
      ReportUseStatus.noPeriod => 'No use period recorded',
    };
  }

  String _range(EventDate? start, EventDate? end, String zone, bool use24Hour) {
    if (start == null && end == null) return 'Not recorded';
    final from = start == null
        ? 'Not recorded'
        : formatEventDate(start, zone, use24Hour: use24Hour);
    final to = end == null
        ? 'Ongoing'
        : formatEventDate(end, zone, use24Hour: use24Hour);
    return '$from to $to';
  }
}
