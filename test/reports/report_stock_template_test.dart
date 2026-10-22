import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdfrx/pdfrx.dart';
import 'package:true_grit_vital/domain/events/events.dart';
import 'package:true_grit_vital/domain/records.dart';
import 'package:true_grit_vital/domain/reports/reports.dart';
import 'package:true_grit_vital/domain/scheduling/daily_plan.dart';
import 'package:true_grit_vital/domain/stock/exact_amount.dart';
import 'package:true_grit_vital/reports/r01_summary_template.dart';
import 'package:true_grit_vital/reports/report_fonts.dart';
import 'package:true_grit_vital/reports/report_template.dart';
import 'package:true_grit_vital/reports/templates/r02_history_template.dart';
import 'package:true_grit_vital/reports/templates/r03_event_template.dart';

final class _TestFontLoader implements ReportFontLoader {
  const _TestFontLoader();
  @override
  Future<ReportFonts> load() async => ReportFonts(
    regular: pw.Font.helvetica(),
    bold: pw.Font.helveticaBold(),
    embedded: false,
  );
}

final bottle = ReportStockSource(
  containerId: 'container-1',
  label: 'Synthetic bottle',
  unit: 'ml',
  lot: 'LOT-7',
  expiryDate: CivilDate(2026, 12, 31),
  capacity: ExactAmount(BigInt.one, BigInt.from(3)),
);

ReportCutoff _cutoff() => ReportCutoff(
  generatedAt: DateTime.utc(2026, 10, 20, 12),
  datasetGeneration: 'generation',
  personRevision: 2,
  schemaVersion: 24,
);

UseRecord _use() => UseRecord(
  id: 'record-1',
  personId: 'me',
  itemId: 'item-1',
  name: 'Synthetic item',
  form: 'Bottle',
  unit: 'ml',
  type: 'Medicine',
  enteredAmount: '0.5',
  actualAt: DateTime.utc(2026, 10, 5, 9),
  enteredAt: DateTime.utc(2026, 10, 5, 9, 2),
  revision: 1,
  isVoided: false,
  source: RecordSource.selfReported,
);

final event = EventRecord(
  id: 'event-1',
  personId: 'me',
  name: 'Synthetic event',
  eventType: 'Course',
  zoneId: 'UTC',
  revision: 1,
  plannedStart: EventDate.day(CivilDate(2026, 10, 1)),
  plannedEnd: EventDate.day(CivilDate(2026, 10, 31)),
  memberships: [
    EventMembership(
      id: 'member-1',
      itemId: 'item-1',
      personId: 'me',
      effectiveFrom: DateTime.utc(2026, 10, 1),
      revision: 1,
    ),
  ],
);

ReportSnapshot _snapshot(
  ReportTemplateId template, {
  bool includeStock = true,
  ReportStockSource? stockSource,
}) => ReportSnapshot.build(
  selection: ReportSelection(
    template: template,
    personId: 'me',
    fromDate: CivilDate(2026, 10, 1),
    beforeDate: CivilDate(2026, 11, 1),
    displayZone: 'UTC',
    includeStock: includeStock,
    eventId: template == ReportTemplateId.r03EventReview ? event.id : null,
  ),
  cutoff: _cutoff(),
  person: const ReportPerson(id: 'me', name: 'Synthetic Person'),
  records: [ReportRecord.fromUseRecord(_use(), stockSource: stockSource)],
);

ReportSnapshot _withData(ReportSnapshot snapshot) =>
    switch (snapshot.selection.template) {
      ReportTemplateId.r01SubstanceSummary => snapshot,
      ReportTemplateId.r02DetailedHistory => snapshot.withTemplateData(
        ReportHistoryData.build(
          snapshot: snapshot,
          items: [
            ReportItemDescriptor(
              itemId: 'item-1',
              name: 'Synthetic item',
              form: 'Bottle',
              type: 'Medicine',
              unit: 'ml',
            ),
          ],
        ),
      ),
      ReportTemplateId.r03EventReview => snapshot.withTemplateData(
        ReportEventData.build(snapshot: snapshot, event: event),
      ),
    };

ReportTemplateRenderer _renderer(ReportTemplateId template) =>
    switch (template) {
      ReportTemplateId.r01SubstanceSummary => const R01SummaryRenderer(
        fontLoader: _TestFontLoader(),
      ),
      ReportTemplateId.r02DetailedHistory => const R02HistoryRenderer(
        fontLoader: _TestFontLoader(),
      ),
      ReportTemplateId.r03EventReview => const R03EventRenderer(
        fontLoader: _TestFontLoader(),
      ),
    };

String _text(ReportSnapshot snapshot) {
  final data = snapshot.templateData;
  return switch (snapshot.selection.template) {
    ReportTemplateId.r01SubstanceSummary => snapshot.structuredText(
      use24Hour: true,
    ),
    ReportTemplateId.r02DetailedHistory =>
      (data! as ReportHistoryData).structuredText(snapshot, use24Hour: true),
    ReportTemplateId.r03EventReview =>
      (data! as ReportEventData).structuredText(snapshot, use24Hour: true),
  };
}

String _normalise(String value) => value.replaceAll(RegExp(r'\s+'), ' ').trim();

Future<List<String>> _pageTexts(Uint8List bytes) async {
  await PdfrxEntryFunctions.instance.init();
  final document = await PdfDocument.openData(
    bytes,
    useProgressiveLoading: false,
    maxSizeToCacheOnMemory: 0,
    sourceName: 'report-stock-test',
  );
  try {
    final texts = <String>[];
    for (final page in document.pages) {
      texts.add((await page.loadText())?.fullText ?? '');
    }
    return texts;
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

  test(
    'formatExactQuantity keeps terminating decimals and exact fractions',
    () {
      expect(formatExactQuantity(ExactAmount.parseEntry('0.125')), '0.125');
      expect(
        formatExactQuantity(ExactAmount(BigInt.one, BigInt.from(3))),
        '1/3',
      );
      expect(
        formatExactQuantity(ExactAmount(BigInt.from(2), BigInt.from(3))),
        '2/3',
      );
    },
  );

  for (final template in ReportTemplateId.values) {
    test(
      '${template.id} text and PDF carry the same chosen stock facts',
      () async {
        final snapshot = _withData(_snapshot(template, stockSource: bottle));
        final text = _normalise(_text(snapshot));
        for (final expected in [
          'Synthetic bottle',
          'Unit ml',
          'Lot LOT-7',
          'Expires 31 December 2026',
          'Capacity 1/3 ml',
          ReportText.stockSourceDisclosure,
        ]) {
          expect(text, contains(expected), reason: '${template.id} text');
        }
        final rendered = await _renderer(template)
            .render(snapshot, use24Hour: true);
        final pdf = _normalise((await _pageTexts(rendered.bytes)).join(' '));
        for (final expected in [
          'Synthetic bottle',
          'Unit ml',
          'Lot LOT-7',
          'Expires 31 December 2026',
          'Capacity 1/3 ml',
        ]) {
          expect(pdf, contains(expected), reason: '${template.id} PDF');
        }
      },
    );

    test('${template.id} omits stock facts when the option is off', () async {
      final snapshot = _withData(
        _snapshot(template, includeStock: false, stockSource: null),
      );
      final text = _normalise(_text(snapshot));
      expect(text, isNot(contains('Synthetic bottle')));
      expect(text, isNot(contains(ReportText.stockSourceDisclosure)));
      final rendered = await _renderer(template)
          .render(snapshot, use24Hour: true);
      final pdf = _normalise((await _pageTexts(rendered.bytes)).join(' '));
      expect(pdf, isNot(contains('Synthetic bottle')));
      expect(pdf, isNot(contains('Stock source details')));
    });
  }

  test(
    'a selected stock section reports a truthful stockless result',
    () async {
      final snapshot = _snapshot(ReportTemplateId.r01SubstanceSummary);
      final text = _normalise(snapshot.structuredText(use24Hour: true));
      expect(text, contains(ReportText.noChosenStockSource));
      expect(text, isNot(contains('Stock source: ')));
      final rendered = await _renderer(ReportTemplateId.r01SubstanceSummary)
          .render(snapshot, use24Hour: true);
      final pdf = _normalise((await _pageTexts(rendered.bytes)).join(' '));
      expect(pdf, contains(ReportText.noChosenStockSource));
      expect(pdf, isNot(contains('Capacity 1/3 ml')));
    },
  );
}
