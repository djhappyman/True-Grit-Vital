import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:true_grit_vital/data/record_store.dart';
import 'package:true_grit_vital/reports/r01_summary_template.dart';

ReportCutoff _cutoff(DateTime at) => ReportCutoff(
  generatedAt: at,
  datasetGeneration: 'generation',
  personRevision: 2,
  schemaVersion: 21,
);

UseRecord _record({
  required String id,
  required String name,
  required String type,
  required String unit,
  String form = 'Tablet',
  String amount = '1',
  required DateTime at,
}) => UseRecord(
  id: id,
  personId: 'me',
  itemId: 'item-$type',
  name: name,
  form: form,
  unit: unit,
  type: type,
  enteredAmount: amount,
  actualAt: at,
  enteredAt: at.add(const Duration(minutes: 3)),
  revision: 1,
  isVoided: false,
);

ReportSnapshot _snapshot() {
  final records = <ReportRecord>[
    ReportRecord.fromUseRecord(
      _record(
        id: '1',
        name:
            'A very long synthetic item name with several words that must wrap '
            'inside the table instead of clipping at the edge',
        type: 'Medicine',
        unit: 'mg',
        amount: '0.1',
        at: DateTime.utc(2026, 10, 1, 8),
      ),
    ),
    ReportRecord.fromUseRecord(
      _record(
        id: '2',
        name:
            'A very long synthetic item name with several words that must wrap '
            'inside the table instead of clipping at the edge',
        type: 'Medicine',
        unit: 'mg',
        amount: '0.2',
        at: DateTime.utc(2026, 10, 2, 8),
      ),
    ),
    for (var index = 0; index < 70; index++)
      ReportRecord.fromUseRecord(
        _record(
          id: 'filler-$index',
          name: 'Filler item $index',
          type: index.isEven ? 'Supplement' : 'Medicine',
          unit: 'count',
          amount: '${index + 1}',
          at: DateTime.utc(2026, 10, 3 + index % 20, 9),
        ),
      ),
  ];
  return ReportSnapshot.build(
    selection: ReportSelection(
      personId: 'me',
      fromDate: CivilDate(2026, 10, 1),
      beforeDate: CivilDate(2026, 11, 1),
      displayZone: 'UTC',
      reportName: 'Example report',
    ),
    cutoff: _cutoff(DateTime.utc(2026, 10, 20, 12)),
    person: const ReportPerson(
      id: 'me',
      name: 'Synthetic Person',
      reportName: 'Example report',
    ),
    records: records,
  );
}

Future<List<String>> _pageTexts(Uint8List bytes) async {
  await PdfrxEntryFunctions.instance.init();
  final document = await PdfDocument.openData(
    bytes,
    useProgressiveLoading: false,
    maxSizeToCacheOnMemory: 0,
    sourceName: 'report-test',
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
    'R01 repeats ledger headings on each page of long wrapped rows',
    () async {
      final base = _snapshot();
      final snapshot = ReportSnapshot.build(
        selection: base.selection,
        cutoff: base.cutoff,
        person: base.person,
        records: [
          for (var index = 0; index < 70; index++)
            ReportRecord.fromUseRecord(
              _record(
                id: 'long-$index',
                name: 'Unusually long synthetic substance name that must wrap without hiding quantities or units',
                type: index.isEven ? 'Medicines' : 'Supplements',
                unit: 'count',
                at: DateTime.utc(2026, 10, 1, 8).add(Duration(hours: index)),
              ),
            ),
        ],
      );
      final rendered = await const R01SummaryRenderer().render(
        snapshot,
        use24Hour: true,
      );
      final pages = await _pageTexts(rendered.bytes);
      expect(pages.length, greaterThan(2));
      for (var index = 1; index < pages.length; index++) {
        if (pages[index].contains('Unusually')) {
          expect(
            pages[index],
            contains('When'),
            reason: 'Missing ledger heading on page ${index + 1}',
          );
          expect(pages[index], contains('Amount'));
          expect(
            pages[index].indexOf('When'),
            lessThan(pages[index].indexOf('Unusually')),
            reason: 'The heading must precede the first row on each page',
          );
        }
      }
    },
  );

  test(
    'R01 renders one reviewed artifact with repeated identity and exact text',
    () async {
      final snapshot = _snapshot();
      final renderer = const R01SummaryRenderer();
      final rendered = await renderer.render(snapshot, use24Hour: true);
      final pages = await _pageTexts(rendered.bytes);
      final normalized = pages
          .map((page) => page.replaceAll(RegExp(r'\s+'), ' '))
          .toList();
      final all = normalized.join('\n');

      expect(ascii.decode(rendered.bytes.take(5).toList()), '%PDF-');
      expect(rendered.fontsEmbedded, true);
      expect(rendered.pageCount, greaterThan(1));
      expect(pages.length, rendered.pageCount);
      for (var index = 0; index < normalized.length; index++) {
        final page = normalized[index];
        expect(page, contains('Synthetic Person'));
        expect(page, contains('R01'));
        expect(page, contains('1 October 2026 to 31 October 2026'));
        expect(page, contains('Page ${index + 1} of ${rendered.pageCount}'));
        expect(page, contains('Report ${snapshot.artifactId}'));
      }
      expect(all, contains('Example report'));
      expect(all, contains('0.3 mg'));
      expect(all, contains('72 recorded doses'));
      expect(all, contains('does not confirm that a dose was taken'));
      expect(all, contains('Private notes are not included'));
      expect(all, isNot(contains('Other Adult')));
      expect(latin1.decode(rendered.bytes), isNot(contains('Other Adult')));
      expect(
        latin1.decode(rendered.bytes),
        isNot(contains('Synthetic Person')),
      );
    },
  );
}
