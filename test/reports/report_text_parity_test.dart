import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdfrx/pdfrx.dart';
import 'package:true_grit_vital/domain/events/events.dart';
import 'package:true_grit_vital/domain/history/history.dart';
import 'package:true_grit_vital/domain/records.dart';
import 'package:true_grit_vital/domain/reports/reports.dart';
import 'package:true_grit_vital/domain/scheduling/stored_daily.dart';
import 'package:true_grit_vital/domain/supporting/supporting.dart';
import 'package:true_grit_vital/reports/report_fonts.dart';
import 'package:true_grit_vital/reports/templates/r02_history_template.dart';
import 'package:true_grit_vital/reports/templates/r03_event_template.dart';
import 'package:true_grit_vital/reports/templates/report_template_catalog.dart';

import '../domain/history/history_test_data.dart';

final class _TestFontLoader implements ReportFontLoader {
  const _TestFontLoader();
  @override
  Future<ReportFonts> load() async => ReportFonts(
    regular: pw.Font.helvetica(),
    bold: pw.Font.helveticaBold(),
    embedded: false,
  );
}

const _sha = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

ReportCutoff _cutoff() => ReportCutoff(
  generatedAt: DateTime.utc(2026, 10, 20, 12),
  datasetGeneration: 'generation-synthetic',
  personRevision: 3,
  schemaVersion: 21,
);

UseRecord _use({
  required String id,
  required String itemId,
  required String name,
  required String form,
  required String type,
  required String unit,
  required String amount,
  required DateTime at,
  int revision = 1,
}) => UseRecord(
  id: id,
  personId: 'me',
  itemId: itemId,
  name: name,
  form: form,
  unit: unit,
  type: type,
  enteredAmount: amount,
  actualAt: at,
  enteredAt: at.add(const Duration(minutes: 4)),
  revision: revision,
  isVoided: false,
  source: RecordSource.selfReported,
);

ReportSnapshot _r02Snapshot({
  bool privateOptions = true,
  int fillerRows = 120,
}) {
  final captured = ReportSnapshot.build(
    selection: ReportSelection(
      template: ReportTemplateId.r02DetailedHistory,
      personId: 'me',
      fromDate: CivilDate(2026, 10, 1),
      beforeDate: CivilDate(2026, 11, 1),
      displayZone: 'UTC',
      reportName: 'Synthetic summary',
      includeNotes: privateOptions,
      includeAttachments: privateOptions,
      includeSupporting: privateOptions,
    ),
    cutoff: _cutoff(),
    person: const ReportPerson(
      id: 'me',
      name: 'Synthetic Person',
      reportName: 'Profile report name',
    ),
    records: [
      ReportRecord.fromUseRecord(
        _use(
          id: 'tablet-one',
          itemId: 'tablet',
          name: 'Example tablet',
          form: 'Tablet',
          type: 'Medicine',
          unit: 'mg',
          amount: '0.125',
          at: DateTime.utc(2026, 10, 2, 8),
        ),
      ),
      ReportRecord.fromUseRecord(
        _use(
          id: 'tablet-two',
          itemId: 'tablet',
          name: 'Example tablet',
          form: 'Tablet',
          type: 'Medicine',
          unit: 'mg',
          amount: '0.375',
          at: DateTime.utc(2026, 10, 3, 8),
        ),
      ),
      ReportRecord.fromUseRecord(
        _use(
          id: 'tablet-three',
          itemId: 'tablet',
          name: 'Example tablet',
          form: 'Tablet',
          type: 'Medicine',
          unit: 'mg',
          amount: '0.5',
          at: DateTime.utc(2026, 10, 4, 8),
          revision: 3,
        ),
      ),
      ReportRecord(
        id: 'blend-one',
        itemId: 'blend',
        name: 'Example blend',
        form: 'Liquid',
        type: 'Blends',
        amount: ExactAmount.parseEntry('0.4'),
        unit: 'ml',
        actualAt: DateTime.utc(2026, 10, 5, 18),
        enteredAt: DateTime.utc(2026, 10, 5, 18, 4),
        revision: 1,
        source: RecordSource.selfReported,
        product: ReportProduct(
          volumeUnit: 'ml',
          ingredients: [
            ReportProductIngredient(
              ingredientId: 'ingredient-a',
              name: 'Ingredient A',
              unit: 'mg',
              strength: '100 mg/ml',
              amount: ExactAmount.parseEntry('40'),
            ),
            const ReportProductIngredient(
              ingredientId: 'ingredient-b',
              name: 'Ingredient B',
              unit: 'mg',
              amount: null,
            ),
          ],
        ),
      ),
      for (var index = 0; index < fillerRows; index++)
        ReportRecord.fromUseRecord(
          _use(
            id: 'filler-$index',
            itemId: 'filler',
            name: 'Example capsule',
            form: 'Capsule',
            type: 'Medicine',
            unit: 'count',
            amount: '1',
            at: DateTime.utc(2026, 10, 6, 8).add(Duration(hours: index)),
          ),
        ),
    ],
    supporting: [
      ReportSupportingEntry(
        id: 'support-1',
        title: 'Synthetic panel',
        kind: SupportingRecordKind.labPanel,
        collectionDate: SupportingDate.day(CivilDate(2026, 10, 5)),
        notes: privateOptions ? 'Synthetic note' : null,
        values: const [
          ReportSupportingValue(
            name: 'Example marker',
            value: '5.5',
            unit: 'mmol/L',
            referenceRange: '3.0-7.0',
          ),
        ],
      ),
    ],
    attachments: [
      const ReportAttachmentRef(
        id: 'attachment-1',
        name: 'Synthetic source.pdf',
        versionId: 'version-1',
        sha256: _sha,
        byteCount: 2048,
        pinned: true,
        targetKind: 'record',
        targetId: 'tablet-one',
      ),
    ],
  );
  final data = ReportHistoryData.build(
    snapshot: captured,
    items: [
      ReportItemDescriptor(
        itemId: 'tablet',
        name: 'Example tablet',
        form: 'Tablet',
        type: 'Medicine',
        unit: 'mg',
      ),
      ReportItemDescriptor(
        itemId: 'blend',
        name: 'Example blend',
        form: 'Liquid',
        type: 'Blends',
        unit: 'ml',
      ),
      ReportItemDescriptor(
        itemId: 'filler',
        name: 'Example capsule',
        form: 'Capsule',
        type: 'Medicine',
        unit: 'count',
      ),
    ],
    skipped: [
      for (var index = 0; index < 2; index++)
        SkippedTimelineEntry(
          action: skipAction(id: 'skip-$index'),
          context: TimelinePlanContext(
            expectation: exactExpectation(
              item: 'tablet',
              plan: 'plan-$index',
              instant: DateTime.utc(2026, 10, 7, 7),
            ),
            planName: 'Example plan ${index + 1}',
            itemName: 'Example tablet',
          ),
        ),
    ],
    dailyRows: [
      for (var index = 0; index < 2; index++)
        DailyRow(
          generation: 'generation-synthetic',
          personRevision: 3,
          planRevision: 1,
          expectation: untimedExpectation(
            item: 'tablet',
            plan: 'unrecorded-$index',
            originalDate: CivilDate(2026, 10, 8),
            zone: 'UTC',
          ),
          personName: 'Synthetic Person',
          itemName: 'Example tablet',
          revision: 1,
          actions: const [],
          takenCount: 0,
          skippedCount: 0,
        ),
    ],
  );
  return captured.withTemplateData(data);
}

/// The test product uses one known and one unknown ingredient amount.

ReportSnapshot _r03Snapshot() {
  final event = EventRecord(
    id: 'event-synthetic',
    personId: 'me',
    name: 'Synthetic course',
    eventType: 'Course',
    zoneId: 'UTC',
    revision: 1,
    plannedStart: EventDate.day(CivilDate(2026, 10, 1)),
    plannedEnd: EventDate.day(CivilDate(2026, 10, 31)),
    completed: false,
    memberships: [
      EventMembership(
        id: 'member-tablet',
        itemId: 'tablet',
        personId: 'me',
        effectiveFrom: DateTime.utc(2026, 10, 1),
        revision: 1,
      ),
      EventMembership(
        id: 'member-capsule',
        itemId: 'capsule',
        personId: 'me',
        effectiveFrom: DateTime.utc(2026, 10, 1),
        revision: 1,
      ),
    ],
  );
  final captured = ReportSnapshot.build(
    selection: ReportSelection(
      template: ReportTemplateId.r03EventReview,
      personId: 'me',
      fromDate: CivilDate(2026, 10, 1),
      beforeDate: CivilDate(2026, 11, 1),
      displayZone: 'UTC',
      eventId: event.id,
      reportName: 'Synthetic event review',
      includeNotes: true,
      includeAttachments: true,
      includeSupporting: true,
    ),
    cutoff: _cutoff(),
    person: const ReportPerson(id: 'me', name: 'Synthetic Person'),
    records: [
      for (var index = 0; index < 2; index++)
        ReportRecord.fromUseRecord(
          _use(
            id: 'event-tablet-$index',
            itemId: 'tablet',
            name: 'Example tablet',
            form: 'Tablet',
            type: 'Medicine',
            unit: 'count',
            amount: '1',
            at: DateTime.utc(2026, 10, 2, 8).add(Duration(hours: index)),
          ),
        ),
      ReportRecord.fromUseRecord(
        _use(
          id: 'event-capsule',
          itemId: 'capsule',
          name: 'Example capsule',
          form: 'Capsule',
          type: 'Supplement',
          unit: 'count',
          amount: '1',
          at: DateTime.utc(2026, 10, 3, 8),
        ),
      ),
    ],
    supporting: [
      ReportSupportingEntry(
        id: 'event-support',
        title: 'Synthetic observation',
        kind: SupportingRecordKind.observation,
        collectionDate: SupportingDate.day(CivilDate(2026, 10, 4)),
        notes: 'Synthetic observation note',
        values: const [
          ReportSupportingValue(
            name: 'Example reading',
            value: '72',
            unit: 'bpm',
          ),
        ],
      ),
    ],
    attachments: [
      const ReportAttachmentRef(
        id: 'event-attachment',
        name: 'Synthetic event source.pdf',
        versionId: 'version-1',
        sha256: _sha,
        byteCount: 4096,
        pinned: true,
        targetKind: 'item',
        targetId: 'tablet',
      ),
    ],
  );
  final data = ReportEventData.build(
    snapshot: captured,
    event: event,
    items: [
      ReportItemDescriptor(
        itemId: 'tablet',
        name: 'Example tablet',
        form: 'Tablet',
        type: 'Medicine',
        unit: 'count',
      ),
      ReportItemDescriptor(
        itemId: 'capsule',
        name: 'Example capsule',
        form: 'Capsule',
        type: 'Supplement',
        unit: 'count',
      ),
    ],
    usePeriods: [
      RecordedUsePeriod(
        id: 'period-tablet',
        personId: 'me',
        itemId: 'tablet',
        revision: 1,
        start: EventDate.day(CivilDate(2026, 10, 1)),
      ),
      RecordedUsePeriod(
        id: 'period-capsule',
        personId: 'me',
        itemId: 'capsule',
        revision: 1,
        start: EventDate.day(CivilDate(2026, 9, 20)),
        end: EventDate.day(CivilDate(2026, 9, 30)),
      ),
    ],
    skipped: [
      SkippedTimelineEntry(
        action: skipAction(id: 'event-skip'),
        context: TimelinePlanContext(
          expectation: exactExpectation(
            item: 'tablet',
            plan: 'event-plan',
            instant: DateTime.utc(2026, 10, 5, 7),
          ),
          itemName: 'Example tablet',
          planName: 'Example plan',
        ),
      ),
    ],
    unresolved: [
      DailyRow(
        generation: 'generation-synthetic',
        personRevision: 3,
        planRevision: 1,
        expectation: untimedExpectation(
          item: 'capsule',
          plan: 'event-unrecorded',
          originalDate: CivilDate(2026, 10, 6),
          zone: 'UTC',
        ),
        personName: 'Synthetic Person',
        itemName: 'Example capsule',
        revision: 1,
        actions: const [],
        takenCount: 0,
        skippedCount: 0,
      ),
    ],
  );
  return captured.withTemplateData(data);
}

Future<List<String>> _pageTexts(Uint8List bytes) async {
  await PdfrxEntryFunctions.instance.init();
  final document = await PdfDocument.openData(
    bytes,
    useProgressiveLoading: false,
    maxSizeToCacheOnMemory: 0,
    sourceName: 'report-parity-test',
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

  group('R02 accessible text', () {
    test('keeps exact totals, ingredients and selected context', () {
      final snapshot = _r02Snapshot();
      final text = reportTextFor(snapshot, use24Hour: true);
      final data = snapshot.templateData! as ReportHistoryData;

      expect(text, startsWith('Detailed history'));
      expect(text, contains('Person: Profile report name'));
      expect(text, contains('Report name: Synthetic summary'));
      expect(text, contains('Ledger rows: 128'));
      expect(text, contains('Recorded: 123'));
      expect(text, contains('Corrected: 1'));
      expect(text, contains('Skipped: 2'));
      expect(text, contains('Not recorded: 2'));

      expect(text, contains('Compatible totals'));
      expect(text, contains('Example tablet · Tablet · 3 doses · Total 1 mg'));
      expect(
        text,
        contains('Example capsule · Capsule · 120 doses · Total 120 count'),
      );
      expect(text, contains('Example blend · Liquid · 1 dose · Volume 0.4 ml'));
      expect(text, contains('Ingredient Ingredient A (100 mg/ml): 40 mg'));
      expect(text, contains('Ingredient Ingredient B: Unknown'));
      expect(text, isNot(contains('~1 mg')));
      expect(text, isNot(contains('Unknown mg')));

      expect(text, contains('Supporting records: included.'));
      expect(text, contains('Private notes: included where recorded.'));
      expect(text, contains('Source files: listed.'));
      expect(text, contains('Synthetic panel (Lab panel)'));
      expect(text, contains('Measured: 5 October 2026'));
      expect(text, contains('Example marker: 5.5 mmol/L (range 3.0-7.0)'));
      expect(text, contains('Note: Synthetic note'));
      expect(
        text,
        contains('Source: Synthetic source.pdf · 2048 bytes · $_sha'),
      );
      expect(text, isNot(contains('Other adult')));

      // Every administration row survives; the long ledger is not truncated.
      expect(data.entries.length, 128);
      final recordedRows = text
          .split('\n')
          .where(
            (line) =>
                line.contains('Example capsule') && line.contains('Recorded'),
          )
          .length;
      expect(recordedRows, 120);
      expect(text, contains('7 October 2026, 07:00 (UTC)'));
      expect(text, contains('8 October 2026'));
    });

    test('states omitted private options in the text alternative', () {
      final snapshot = _r02Snapshot(privateOptions: false);
      final text = reportTextFor(snapshot, use24Hour: true);
      expect(
        text,
        contains('Supporting records and source files: not included.'),
      );
      expect(text, contains('Private notes: not included.'));
      expect(text, isNot(contains('Synthetic panel')));
      expect(text, isNot(contains('Synthetic source.pdf')));
      expect(text, isNot(contains('Synthetic note')));
    });

    test('supporting context respects a separately disabled notes option', () {
      final source = _r02Snapshot();
      final snapshot = ReportSnapshot.build(
        selection: ReportSelection(
          template: ReportTemplateId.r02DetailedHistory,
          personId: 'me',
          fromDate: CivilDate(2026, 10, 1),
          beforeDate: CivilDate(2026, 11, 1),
          displayZone: 'UTC',
          includeSupporting: true,
          includeNotes: false,
        ),
        cutoff: source.cutoff,
        person: source.person,
        records: source.records,
        supporting: source.supporting,
      );
      final text = ReportText.contextLines(snapshot).join('\n');
      expect(text, contains('Synthetic panel (Lab panel)'));
      expect(text, contains('Private notes: not included.'));
      expect(text, isNot(contains('Synthetic note')));
    });

    test('rejects records outside an immutable item selection', () {
      final captured = ReportSnapshot.build(
        selection: ReportSelection(
          template: ReportTemplateId.r02DetailedHistory,
          personId: 'me',
          fromDate: CivilDate(2026, 10, 1),
          beforeDate: CivilDate(2026, 11, 1),
          displayZone: 'UTC',
          itemIds: const {'tablet'},
        ),
        cutoff: _cutoff(),
        person: const ReportPerson(id: 'me', name: 'Synthetic Person'),
        records: [
          ReportRecord.fromUseRecord(
            _use(
              id: 'inside',
              itemId: 'tablet',
              name: 'Example tablet',
              form: 'Tablet',
              type: 'Medicine',
              unit: 'mg',
              amount: '1',
              at: DateTime.utc(2026, 10, 2, 8),
            ),
          ),
          ReportRecord.fromUseRecord(
            _use(
              id: 'outside',
              itemId: 'capsule',
              name: 'Example capsule',
              form: 'Capsule',
              type: 'Medicine',
              unit: 'count',
              amount: '1',
              at: DateTime.utc(2026, 10, 2, 9),
            ),
          ),
        ],
      );
      expect(
        () => ReportHistoryData.build(snapshot: captured),
        throwsA(
          isA<ReportSelectionFailure>().having(
            (error) => error.code,
            'code',
            'report_item',
          ),
        ),
      );
    });

    test(
      'renders repeated identity and ingredient totals across pages',
      () async {
        final snapshot = _r02Snapshot();
        final rendered = await const R02HistoryRenderer(
          fontLoader: _TestFontLoader(),
        ).render(snapshot, use24Hour: true);
        expect(String.fromCharCodes(rendered.bytes.take(5)), '%PDF-');
        expect(rendered.pageCount, greaterThan(2));

        final pages = await _pageTexts(rendered.bytes);
        expect(pages.length, rendered.pageCount);
        for (var index = 0; index < pages.length; index++) {
          expect(pages[index], contains('Profile report name'));
          expect(pages[index], contains('R02'));
          expect(pages[index], contains('1 October 2026 to 31 October 2026'));
          expect(pages[index], contains('Report ${snapshot.artifactId}'));
          expect(
            pages[index],
            contains('Page ${index + 1} of ${rendered.pageCount}'),
          );
        }
        final totalsPage = pages.firstWhere(
          (page) => page.contains('Compatible totals'),
        );
        expect(totalsPage, contains('Ingredient A (100 mg/ml)'));
        expect(totalsPage, contains('40 mg'));
        expect(totalsPage, contains('Ingredient B'));
        expect(totalsPage, contains('Unknown'));
        expect(totalsPage, contains('Volume'));
        expect(totalsPage, contains('0.4 ml'));
      },
    );
  });

  group('R03 accessible text', () {
    test('keeps ongoing use, exact totals and selected context', () {
      final snapshot = _r03Snapshot();
      final text = reportTextFor(snapshot, use24Hour: true);

      expect(text, startsWith('Event review'));
      expect(text, contains('Report name: Synthetic event review'));
      expect(text, contains('Event state: Ongoing'));
      expect(text, contains('Members with an open use period: 1.'));
      expect(text, contains('Recorded administrations: 3'));
      expect(text, contains('Skipped: 1'));
      expect(text, contains('Not recorded: 1'));
      expect(
        text,
        contains('Skipped and not-recorded states are counted separately'),
      );

      expect(text, contains('Ongoing separately'));
      expect(text, contains('Use period ended'));
      expect(text, contains('Example tablet: 2 count'));
      expect(text, contains('Example capsule: 1 count'));
      expect(text, contains('2 administrations'));

      expect(text, contains('Supporting records: included.'));
      expect(text, contains('Synthetic observation (Observation)'));
      expect(text, contains('Example reading: 72 bpm'));
      expect(text, contains('Note: Synthetic observation note'));
      expect(
        text,
        contains('Source: Synthetic event source.pdf · 4096 bytes · $_sha'),
      );
      expect(text, contains('does not mean every included item stopped'));
    });

    test('renders repeated identity for an ongoing event', () async {
      final snapshot = _r03Snapshot();
      final rendered = await const R03EventRenderer(
        fontLoader: _TestFontLoader(),
      ).render(snapshot, use24Hour: true);
      expect(String.fromCharCodes(rendered.bytes.take(5)), '%PDF-');
      final pages = await _pageTexts(rendered.bytes);
      expect(pages.length, rendered.pageCount);
      for (var index = 0; index < pages.length; index++) {
        expect(pages[index], contains('Synthetic Person'));
        expect(pages[index], contains('R03'));
        expect(pages[index], contains('Report ${snapshot.artifactId}'));
        expect(
          pages[index],
          contains('Page ${index + 1} of ${rendered.pageCount}'),
        );
      }
      final all = pages.join('\n');
      expect(all, contains('Ongoing separately'));
      expect(all, contains('Use period ended'));
      expect(all, contains('2 administrations'));
    });
  });
}
