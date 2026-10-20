import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdfrx/pdfrx.dart';
import 'package:true_grit_vital/data/record_store.dart';
import 'package:true_grit_vital/reports/r01_summary_template.dart';
import 'package:true_grit_vital/reports/report_fonts.dart';
import 'package:true_grit_vital/reports/templates/r02_history_template.dart';
import 'package:true_grit_vital/reports/templates/r03_event_template.dart';
import 'package:true_grit_vital/reports/templates/report_template_catalog.dart';

final class _TestFontLoader implements ReportFontLoader {
  const _TestFontLoader();
  @override
  Future<ReportFonts> load() async => ReportFonts(
    regular: pw.Font.helvetica(),
    bold: pw.Font.helveticaBold(),
    embedded: false,
  );
}

const _hiddenUnknownTitles = [
  'Hidden unknown panel',
  'Hidden partial panel',
  'Hidden edited panel',
  'Hidden voided panel',
];

ReportSelection _selection({
  ReportTemplateId template = ReportTemplateId.r01SubstanceSummary,
  bool supporting = true,
  bool notes = false,
  String? eventId,
}) => ReportSelection(
  template: template,
  personId: meId,
  fromDate: CivilDate(2026, 10, 1),
  beforeDate: CivilDate(2026, 11, 1),
  displayZone: 'UTC',
  eventId: eventId,
  includeSupporting: supporting,
  includeNotes: notes,
);

Future<List<String>> _pageTexts(Uint8List bytes) async {
  await PdfrxEntryFunctions.instance.init();
  final document = await PdfDocument.openData(
    bytes,
    useProgressiveLoading: false,
    maxSizeToCacheOnMemory: 0,
    sourceName: 'report-omission-test',
  );
  try {
    return [
      for (final page in document.pages)
        ((await page.loadText())?.fullText ?? '').replaceAll(
          RegExp(r'\s+'),
          ' ',
        ),
    ];
  } finally {
    await document.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    if (Platform.isLinux) {
      final module = File('build/native_assets/linux/libpdfium.so');
      if (module.existsSync()) {
        Pdfrx.pdfiumModulePath = module.absolute.path;
      }
    }
  });

  late Directory directory;
  late RecordStore store;
  late SubstanceItem item;
  final now = DateTime.utc(2026, 10, 20, 12);

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('vital-report-omission-');
    store = await RecordStore.open(
      path: '${directory.path}/report.db',
      key: List.generate(32, (index) => index + 1),
      isNew: true,
    );
    await store.editProfile(
      commandId: 'profile',
      personId: meId,
      expectedRevision: 1,
      name: 'Synthetic Person',
      adultConfirmed: true,
    );
    final me = (await store.profileById(meId))!;
    item = await store.createItem(
      commandId: 'item',
      name: 'Example tablet',
      form: 'Tablet',
      unit: 'count',
      type: 'Medicine',
      expectedPersonRevision: me.revision,
    );
    await store.record(
      commandId: 'dose',
      itemId: item.id,
      amount: '1',
      actualAt: DateTime.utc(2026, 10, 5, 8),
      expectedPersonRevision: me.revision,
    );
  });

  tearDown(() async {
    await store.close();
    await directory.delete(recursive: true);
  });

  Future<SupportingRevision> panel({
    required String id,
    required SupportingDate collection,
    required String title,
    String? notes,
    String marker = 'Hidden marker',
    String value = '987.65',
    int? expectedRevision,
    String? command,
  }) async => store.saveLabPanel(
    SaveLabPanelCommand(
      commandId: command ?? 'panel-$id',
      generation: store.generation,
      expectedPersonRevision: (await store.profileById(meId))!.revision,
      expectedRevision: expectedRevision,
      panel: LabPanelSnapshot(
        id: SupportingRecordId(id: id, personId: meId),
        title: title,
        collectionDate: collection,
        reportDate: SupportingDate.day(CivilDate(2026, 10, 4)),
        provenance: SupportingProvenance(
          mode: SupportingProvenanceMode.manualTranscription,
          laboratoryName: 'Synthetic laboratory',
        ),
        results: [
          LabResultSnapshot(
            id: 'result-$id',
            metricId: 'metric-$id',
            markerName: marker,
            value: SupportingValue.numeric(value),
            unit: 'mg/L',
          ),
        ],
        notes: notes,
      ),
    ),
  );

  Future<void> voidPanel(String id) async {
    final revision = (await store.profileById(meId))!.revision;
    await store.voidSupportingRecord(
      VoidSupportingRecordCommand(
        commandId: 'void-$id',
        generation: store.generation,
        personId: meId,
        id: id,
        expectedPersonRevision: revision,
        expectedRevision: 1,
      ),
    );
  }

  /// One dated record inside the period, one dated record outside it, and
  /// current records whose collection date is unknown, partial, corrected to
  /// unknown, or voided.
  Future<void> seedMixed() async {
    await panel(
      id: 'dated-inside',
      collection: SupportingDate.day(CivilDate(2026, 10, 2)),
      title: 'Dated inside panel',
      marker: 'Visible marker',
      value: '5.5',
    );
    await panel(
      id: 'dated-outside',
      collection: SupportingDate.day(CivilDate(2026, 12, 2)),
      title: 'Dated outside panel',
    );
    await panel(
      id: 'unknown',
      collection: SupportingDate.unknown(originalText: 'Spring 2025'),
      title: 'Hidden unknown panel',
      notes: 'Hidden private note',
    );
    await panel(
      id: 'partial',
      collection: SupportingDate.partial(
        year: 2025,
        originalText: 'Some time in 2025',
      ),
      title: 'Hidden partial panel',
    );
    await panel(
      id: 'edited',
      collection: SupportingDate.day(CivilDate(2026, 10, 3)),
      title: 'Hidden edited panel',
    );
    await panel(
      id: 'edited',
      collection: SupportingDate.unknown(),
      title: 'Hidden edited panel',
      expectedRevision: 1,
      command: 'panel-edited-unknown',
    );
    await panel(
      id: 'voided',
      collection: SupportingDate.unknown(),
      title: 'Hidden voided panel',
    );
    await voidPanel('voided');
  }

  Future<void> seedDatedOnly() async {
    await panel(
      id: 'dated-inside',
      collection: SupportingDate.day(CivilDate(2026, 10, 2)),
      title: 'Dated inside panel',
      marker: 'Visible marker',
      value: '5.5',
    );
  }

  test('a mixed fixture counts only current undated records', () async {
    await seedMixed();
    final capture = await store.captureReport(
      selection: _selection(),
      now: () => now,
    );
    final snapshot = capture.snapshot;

    expect(snapshot.supporting.map((entry) => entry.title), [
      'Dated inside panel',
    ]);
    expect(snapshot.supportingTruncated, false);
    expect(snapshot.supportingOmission!.count, 3);
    expect(snapshot.supportingOmission!.identityToken, [
      'supporting-collection-date',
      'counted',
      3,
    ]);

    final text = snapshot.structuredText(use24Hour: true);
    expect(
      text,
      contains(
        '3 supporting records have unknown or partial collection dates. '
        'They are not shown.',
      ),
    );
    expect(text, contains('Dated inside panel'));
    expect(text, contains('Visible marker: 5.5 mg/L'));

    // The mixed fixture is a meaningful record set; the omitted content never
    // reaches the text, and the selected known record does.
    for (final hidden in _hiddenUnknownTitles) {
      expect(text, isNot(contains(hidden)));
    }
    expect(text, isNot(contains('Hidden private note')));
    expect(text, isNot(contains('Spring 2025')));
    expect(text, isNot(contains('Some time in 2025')));
    expect(text, isNot(contains('987.65')));
    expect(text, isNot(contains('Dated outside panel')));

    final rendered = await const R01SummaryRenderer(
      fontLoader: _TestFontLoader(),
    ).render(snapshot, use24Hour: true);
    final pages = await _pageTexts(rendered.bytes);
    final all = pages.join('\n');
    expect(
      all,
      contains(
        '3 supporting records have unknown or partial collection dates. '
        'They are not shown.',
      ),
    );
    expect(all, contains('Dated inside panel'));
    for (final hidden in _hiddenUnknownTitles) {
      expect(all, isNot(contains(hidden)));
    }
    expect(all, isNot(contains('Hidden private note')));
    expect(all, isNot(contains('Spring 2025')));
    expect(all, isNot(contains('987.65')));
  });

  test(
    'the counting bound reports uncounted without rejecting records',
    () async {
      await seedMixed();
      final counted = await store.captureReport(
        selection: _selection(),
        now: () => now,
        maxSupportingOmissions: 3,
      );
      expect(counted.snapshot.supportingOmission!.count, 3);

      final bound = await store.captureReport(
        selection: _selection(),
        now: () => now,
        maxSupportingOmissions: 2,
      );
      final omission = bound.snapshot.supportingOmission!;
      expect(omission.count, isNull);
      expect(omission.identityToken, [
        'supporting-collection-date',
        'uncounted',
      ]);
      expect(
        bound.snapshot.supporting.map((entry) => entry.title),
        counted.snapshot.supporting.map((entry) => entry.title),
      );
      expect(
        bound.snapshot.totals.recordCount,
        counted.snapshot.totals.recordCount,
      );

      final text = bound.snapshot.structuredText(use24Hour: true);
      expect(
        text,
        contains(
          'Supporting records with unknown or partial collection dates are not '
          'shown. Their number was above the report\'s counting limit.',
        ),
      );
      expect(text, isNot(contains('0 supporting records')));

      final zeroBudget = await store.captureReport(
        selection: _selection(),
        now: () => now,
        maxSupportingOmissions: 0,
      );
      expect(zeroBudget.snapshot.supportingOmission!.count, isNull);
    },
  );

  test(
    'an exact zero keeps the artifact identity and adds no notice',
    () async {
      await seedDatedOnly();
      final capture = await store.captureReport(
        selection: _selection(),
        now: () => now,
      );
      final snapshot = capture.snapshot;
      expect(snapshot.supportingOmission!.count, 0);
      expect(snapshot.supportingOmission!.identityToken, isNull);
      expect(ReportText.supportingOmissionNotice(snapshot), isNull);
      expect(
        snapshot.structuredText(use24Hour: true),
        isNot(contains('unknown or partial collection dates')),
      );

      final withoutOmission = ReportSnapshot.build(
        selection: snapshot.selection,
        cutoff: snapshot.cutoff,
        person: snapshot.person,
        records: snapshot.records,
        supporting: snapshot.supporting,
      );
      expect(snapshot.artifactId, withoutOmission.artifactId);

      await seedMixed();
      final positive = await store.captureReport(
        selection: _selection(),
        now: () => now,
      );
      expect(positive.snapshot.supportingOmission!.count, 3);
      expect(positive.snapshot.artifactId, isNot(snapshot.artifactId));
    },
  );

  test('a single omitted record uses singular wording', () {
    final snapshot = ReportSnapshot.build(
      selection: _selection(),
      cutoff: ReportCutoff(
        generatedAt: now,
        datasetGeneration: store.generation,
        personRevision: 2,
        schemaVersion: 21,
      ),
      person: const ReportPerson(id: meId, name: 'Synthetic Person'),
      records: const [],
      supportingOmission: const ReportSupportingOmission.counted(1),
    );
    expect(
      ReportText.supportingOmissionNotice(snapshot),
      '1 supporting record has an unknown or partial collection date. '
      'It is not shown.',
    );
  });

  test('supporting off carries no metadata and no omitted content', () async {
    await seedMixed();
    final capture = await store.captureReport(
      selection: _selection(supporting: false, notes: true),
      now: () => now,
    );
    final snapshot = capture.snapshot;
    expect(snapshot.supportingOmission, isNull);
    expect(snapshot.supporting, isEmpty);

    final text = snapshot.structuredText(use24Hour: true);
    expect(text, contains('Supporting context: not included'));
    expect(text, isNot(contains('unknown or partial collection dates')));
    for (final hidden in _hiddenUnknownTitles) {
      expect(text, isNot(contains(hidden)));
    }
    expect(text, isNot(contains('Spring 2025')));

    final rendered = await const R01SummaryRenderer(
      fontLoader: _TestFontLoader(),
    ).render(snapshot, use24Hour: true);
    final all = (await _pageTexts(rendered.bytes)).join('\n');
    expect(
      all,
      contains('Supporting records and source files were not included'),
    );
    expect(all, isNot(contains('unknown or partial collection dates')));
    expect(all, isNot(contains('Hidden unknown panel')));

    expect(
      () => ReportSnapshot.build(
        selection: _selection(supporting: false),
        cutoff: snapshot.cutoff,
        person: snapshot.person,
        records: snapshot.records,
        supportingOmission: const ReportSupportingOmission.counted(1),
      ),
      throwsA(
        isA<ReportSelectionFailure>().having(
          (error) => error.code,
          'code',
          'report_supporting_omission',
        ),
      ),
    );
  });

  test('captured metadata cannot change after concurrent edits', () async {
    await seedMixed();
    final snapshot = (await store.captureReport(
      selection: _selection(),
      now: () => now,
    )).snapshot;
    expect(snapshot.supportingOmission!.count, 3);

    await panel(
      id: 'later-one',
      collection: SupportingDate.unknown(),
      title: 'Later hidden panel',
    );
    await panel(
      id: 'later-two',
      collection: SupportingDate.partial(year: 2024, originalText: '2024'),
      title: 'Later hidden panel',
    );
    await voidPanel('unknown');

    expect(snapshot.supportingOmission!.count, 3);
    expect(snapshot.supporting.single.title, 'Dated inside panel');
    expect(snapshot.supportingTruncated, false);
    expect(
      snapshot.structuredText(use24Hour: true),
      contains('3 supporting records have unknown or partial collection dates'),
    );

    final later = (await store.captureReport(
      selection: _selection(),
      now: () => now,
    )).snapshot;
    expect(later.supportingOmission!.count, 4);
    expect(later.artifactId, isNot(snapshot.artifactId));
  });

  test('R02 and R03 capture and output keep the omission', () async {
    await seedMixed();
    final r02 = await store.captureTemplateReport(
      selection: _selection(
        template: ReportTemplateId.r02DetailedHistory,
        notes: true,
      ),
      now: () => now,
    );
    expect(r02.snapshot.supportingOmission!.count, 3);
    final r02Text = reportTextFor(r02.snapshot, use24Hour: true);
    expect(
      r02Text,
      contains('3 supporting records have unknown or partial collection dates'),
    );
    expect(r02Text, isNot(contains('Hidden unknown panel')));
    expect(r02Text, isNot(contains('Spring 2025')));

    final r02Rendered = await const R02HistoryRenderer(
      fontLoader: _TestFontLoader(),
    ).render(r02.snapshot, use24Hour: true);
    final r02Pages = (await _pageTexts(r02Rendered.bytes)).join('\n');
    expect(
      r02Pages,
      contains('3 supporting records have unknown or partial collection dates'),
    );
    expect(r02Pages, isNot(contains('Hidden unknown panel')));
    expect(r02Pages, isNot(contains('Spring 2025')));

    final event = EventRecord(
      id: 'event-omission',
      personId: meId,
      name: 'Synthetic course',
      eventType: 'Course',
      zoneId: 'UTC',
      revision: 1,
      plannedStart: EventDate.day(CivilDate(2026, 10, 1)),
      plannedEnd: EventDate.day(CivilDate(2026, 10, 31)),
    );
    await store.saveEvent(
      SaveEventCommand(
        commandId: 'event-omission',
        generation: store.generation,
        expectedRevision: null,
        expectedPersonRevision: (await store.profileById(meId))!.revision,
        event: event,
      ),
    );
    final r03 = await store.captureTemplateReport(
      selection: _selection(
        template: ReportTemplateId.r03EventReview,
        notes: true,
        eventId: event.id,
      ),
      now: () => now,
    );
    expect(r03.snapshot.supportingOmission!.count, 3);
    final r03Text = reportTextFor(r03.snapshot, use24Hour: true);
    expect(
      r03Text,
      contains('3 supporting records have unknown or partial collection dates'),
    );
    expect(r03Text, isNot(contains('Hidden private note')));

    final r03Rendered = await const R03EventRenderer(
      fontLoader: _TestFontLoader(),
    ).render(r03.snapshot, use24Hour: true);
    final r03Pages = (await _pageTexts(r03Rendered.bytes)).join('\n');
    expect(
      r03Pages,
      contains('3 supporting records have unknown or partial collection dates'),
    );
    expect(r03Pages, isNot(contains('Hidden private note')));

    expect(
      r02.snapshot
          .withTemplateData(r02.snapshot.templateData)
          .supportingOmission!
          .count,
      3,
    );
  });
}
