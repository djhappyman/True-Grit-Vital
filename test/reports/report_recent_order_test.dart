import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdfrx/pdfrx.dart';
import 'package:true_grit_vital/data/record_store.dart';
import 'package:true_grit_vital/reports/r01_summary_template.dart';
import 'package:true_grit_vital/reports/report_fonts.dart';

final class _TestFontLoader implements ReportFontLoader {
  const _TestFontLoader();
  @override
  Future<ReportFonts> load() async => ReportFonts(
    regular: pw.Font.helvetica(),
    bold: pw.Font.helveticaBold(),
    embedded: false,
  );
}

UseRecord _use({
  required String id,
  required String name,
  required DateTime actualAt,
  required DateTime enteredAt,
  String amount = '1',
  String unit = 'mg',
}) => UseRecord(
  id: id,
  personId: 'me',
  itemId: 'item-$id',
  name: name,
  form: 'Tablet',
  unit: unit,
  type: 'Medicine',
  enteredAmount: amount,
  actualAt: actualAt,
  enteredAt: enteredAt,
  revision: 1,
  isVoided: false,
);

ReportSnapshot _snapshot(
  List<UseRecord> records, {
  bool includeNotes = false,
  bool includeAttachments = false,
  bool includeSupporting = false,
}) => ReportSnapshot.build(
  selection: ReportSelection(
    personId: 'me',
    fromDate: CivilDate(2026, 10, 1),
    beforeDate: CivilDate(2026, 11, 1),
    displayZone: 'UTC',
    includeNotes: includeNotes,
    includeAttachments: includeAttachments,
    includeSupporting: includeSupporting,
  ),
  cutoff: ReportCutoff(
    generatedAt: DateTime.utc(2026, 10, 20, 12),
    datasetGeneration: 'generation',
    personRevision: 1,
    schemaVersion: 21,
  ),
  person: const ReportPerson(id: 'me', name: 'Synthetic Person'),
  records: [for (final record in records) ReportRecord.fromUseRecord(record)],
);

String _padded(int index) => index.toString().padLeft(3, '0');

/// 105 doses whose caller order is newest first, so list position alone would
/// select the oldest doses. The two newest share one actual instant.
List<UseRecord> _boundedRecords() {
  final start = DateTime.utc(2026, 10, 1, 8);
  final newest = start.add(const Duration(minutes: 103));
  return [
    for (var index = 104; index >= 0; index--)
      _use(
        id: 'id-${_padded(index)}',
        name: 'Dose${_padded(index)}',
        actualAt: index >= 103 ? newest : start.add(Duration(minutes: index)),
        enteredAt: newest.add(Duration(minutes: 104 - index)),
        amount: '${index + 1}',
      ),
  ];
}

/// Names in the `Doses in period` detail, newest expected first.
List<String> _textDetailNames(ReportSnapshot snapshot) {
  final text = ReportText.build(snapshot: snapshot, use24Hour: true);
  final section = text
      .split('Doses in period\n')
      .last
      .split('\n\nThis report lists')
      .first;
  return [
    for (final line in section.split('\n'))
      if (line.contains(' · ')) line.split(' · ')[1],
  ];
}

Future<List<String>> _pageTexts(Uint8List bytes) async {
  await PdfrxEntryFunctions.instance.init();
  final document = await PdfDocument.openData(
    bytes,
    useProgressiveLoading: false,
    maxSizeToCacheOnMemory: 0,
    sourceName: 'report-recent-order-test',
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

/// PDF text after the `Recent doses` heading, where the totals cannot appear.
String _pdfRecentSection(List<String> pages) {
  final all = pages.join(' ');
  final heading = all.indexOf('Recent doses');
  expect(heading, isNonNegative, reason: 'Missing Recent doses section');
  return all.substring(heading + 'Recent doses'.length);
}

List<String> _pdfDoseNames(String section) => [
  for (final match in RegExp(r'Dose\d{3}').allMatches(section)) match.group(0)!,
];

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

  group('ReportSnapshot.recentRecords', () {
    test('selects by actual time without mutating the captured snapshot', () {
      final snapshot = _snapshot([
        _use(
          id: 'old',
          name: 'Oldest dose',
          actualAt: DateTime.utc(2026, 10, 2, 9),
          enteredAt: DateTime.utc(2026, 10, 2, 9, 1),
          amount: '0.125',
        ),
        _use(
          id: 'new',
          name: 'Newest dose',
          actualAt: DateTime.utc(2026, 10, 9, 9),
          enteredAt: DateTime.utc(2026, 10, 9, 9, 30),
          amount: '2',
          unit: 'ml',
        ),
        _use(
          id: 'middle',
          name: 'Middle dose',
          actualAt: DateTime.utc(2026, 10, 5, 9),
          enteredAt: DateTime.utc(2026, 10, 5, 9, 5),
          amount: '3',
        ),
      ]);

      expect(snapshot.recentRecords().map((record) => record.id), [
        'new',
        'middle',
        'old',
      ]);
      expect(snapshot.records.map((record) => record.id), [
        'old',
        'new',
        'middle',
      ]);
      expect(snapshot.totals.recordCount, 3);
      final newest = snapshot.recentRecords().first;
      expect(newest.name, 'Newest dose');
      expect(newest.amount, ExactAmount.parseEntry('2'));
      expect(newest.unit, 'ml');
      expect(newest.itemId, 'item-new');
    });

    test('bounds a long ledger by actual time, not caller position', () {
      final snapshot = _snapshot(_boundedRecords());
      final recent = snapshot.recentRecords();

      expect(recent.length, 100);
      expect(snapshot.records.length, 105);
      expect(recent.first.actualAt, DateTime.utc(2026, 10, 1, 9, 43));
      expect(snapshot.recentRecords(limit: 3).map((record) => record.id), [
        'id-103',
        'id-104',
        'id-102',
      ]);
      expect(recent.map((record) => record.id), isNot(contains('id-004')));
      expect(recent.map((record) => record.id).last, 'id-005');
      expect(() => snapshot.recentRecords(limit: 0), throwsRangeError);
    });

    test('orders tied actual times consistently whatever the caller order', () {
      final actualAt = DateTime.utc(2026, 10, 9, 9);
      UseRecord tied(String id, String name, int enteredMinute) => _use(
        id: id,
        name: name,
        actualAt: actualAt,
        enteredAt: actualAt.add(Duration(minutes: enteredMinute)),
      );
      final first = _snapshot([
        tied('tie-b', 'Bravo', 2),
        tied('tie-d', 'Delta', 8),
        tied('tie-a', 'Alpha', 6),
        tied('tie-c', 'Charlie', 4),
      ]);
      final second = _snapshot([
        tied('tie-c', 'Charlie', 4),
        tied('tie-a', 'Alpha', 6),
        tied('tie-d', 'Delta', 8),
        tied('tie-b', 'Bravo', 2),
      ]);
      final reversedEntryTimes = _snapshot([
        tied('tie-a', 'Alpha', 8),
        tied('tie-b', 'Bravo', 6),
        tied('tie-c', 'Charlie', 4),
        tied('tie-d', 'Delta', 2),
      ]);

      expect(first.recentRecords().map((record) => record.id), [
        'tie-a',
        'tie-b',
        'tie-c',
        'tie-d',
      ]);
      expect(
        first.recentRecords().map((record) => record.id),
        second.recentRecords().map((record) => record.id),
      );
      expect(
        reversedEntryTimes.recentRecords().map((record) => record.id),
        first.recentRecords().map((record) => record.id),
      );
    });
  });

  group('R01 recent dose rendering', () {
    test(
      'text alternative shows the latest actual doses and keeps privacy',
      () {
        final snapshot = _snapshot(_boundedRecords());
        final names = _textDetailNames(snapshot);
        final text = ReportText.build(snapshot: snapshot, use24Hour: true);

        expect(names.length, 100);
        expect(names.first, 'Dose103');
        expect(names[1], 'Dose104');
        expect(names.last, 'Dose005');
        expect(names, isNot(contains('Dose004')));
        expect(text, contains('Showing the latest 100 of 105 doses.'));
        expect(text, contains('Recorded doses: 105'));
        expect(text, contains('Dose104 · 105 mg'));
        expect(text, contains('Dose103 · 104 mg'));
        expect(text, contains('Private notes: not included'));
        expect(text, contains('Source files: not included'));
        expect(text, contains('Supporting context: not included'));
        expect(text, isNot(contains('Note:')));
      },
    );

    test('PDF and text alternatives select the same latest doses', () async {
      final snapshot = _snapshot(_boundedRecords());
      final rendered = await const R01SummaryRenderer(
        fontLoader: _TestFontLoader(),
      ).render(snapshot, use24Hour: true);
      final section = _pdfRecentSection(await _pageTexts(rendered.bytes));

      expect(
        section,
        contains('Showing the latest 100 of 105 recorded doses.'),
      );
      expect(_pdfDoseNames(section), _textDetailNames(snapshot));
      expect(section, contains('105 mg'));
      expect(section, contains('104 mg'));
      expect(section, isNot(contains('Dose004')));
      expect(section.indexOf('Dose103'), lessThan(section.indexOf('Dose005')));
    });

    test('PDF and text keep the same order for tied actual times', () async {
      final actualAt = DateTime.utc(2026, 10, 9, 9);
      UseRecord tied(String id, String name, int enteredMinute) => _use(
        id: id,
        name: name,
        actualAt: actualAt,
        enteredAt: actualAt.add(Duration(minutes: enteredMinute)),
        amount: name == 'Alpha' ? '0.5' : '1.5',
      );
      final snapshot = _snapshot([
        tied('tie-b', 'Bravo', 2),
        tied('tie-a', 'Alpha', 6),
      ]);
      final rendered = await const R01SummaryRenderer(
        fontLoader: _TestFontLoader(),
      ).render(snapshot, use24Hour: true);
      final pages = await _pageTexts(rendered.bytes);
      final section = _pdfRecentSection(pages);

      expect(_textDetailNames(snapshot), ['Alpha', 'Bravo']);
      expect(section.indexOf('Alpha'), lessThan(section.indexOf('Bravo')));
      expect(section, contains('0.5 mg'));
      expect(section, contains('1.5 mg'));
    });
  });
}
