import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdfrx/pdfrx.dart';
import 'package:true_grit_vital/data/record_store.dart';
import 'package:true_grit_vital/reports/r01_summary_template.dart';
import 'package:true_grit_vital/reports/report_fonts.dart';
import 'package:true_grit_vital/reports/report_template.dart';
import 'package:true_grit_vital/reports/templates/r02_history_template.dart';
import 'package:true_grit_vital/reports/templates/r03_event_template.dart';

class TestFonts implements ReportFontLoader {
  const TestFonts();
  @override
  Future<ReportFonts> load() async => ReportFonts(
    regular: pw.Font.helvetica(),
    bold: pw.Font.helveticaBold(),
    embedded: false,
  );
}

final prep = VialPreparation(
  powderAmount: '24',
  massUnit: 'mg',
  finalVolumeMl: '12',
  liquid: 'Entered liquid source',
  addedVolumeMl: '11.8',
  preparedOn: '2026-10-22',
);
UseRecord dose({
  String id = 'dose-A',
  LabelledStrength? strength,
  String amount = '0.25',
  String unit = 'ml',
  StockReplacement? replacement,
}) => UseRecord(
  id: id,
  personId: meId,
  itemId: 'item',
  name: 'Synthetic complete brand name',
  form: 'Injectable',
  unit: unit,
  type: 'Medicine',
  enteredAmount: amount,
  actualAt: DateTime.utc(2026, 10, 22, 8),
  enteredAt: DateTime.utc(2026, 10, 22, 8, 1),
  revision: 1,
  isVoided: false,
  replacement: replacement,
  labelledStrength:
      strength ??
      LabelledStrength(
        ingredientId: 'item',
        label: 'Private container label',
        mgPerMl: prep.mgPerMl,
        preparation: prep,
      ),
);
ReportSelection selection(ReportTemplateId t, bool stock) => ReportSelection(
  template: t,
  personId: meId,
  fromDate: CivilDate(2026, 10, 1),
  beforeDate: CivilDate(2026, 11, 1),
  displayZone: 'UTC',
  includeStock: stock,
  eventId: t == ReportTemplateId.r03EventReview ? 'event' : null,
);
ReportSnapshot snapshot(
  ReportTemplateId t,
  bool stock, {
  List<UseRecord>? doses,
}) {
  final s = ReportSnapshot.build(
    selection: selection(t, stock),
    cutoff: ReportCutoff(
      generatedAt: DateTime.utc(2026, 10, 22, 12),
      datasetGeneration: 'generation',
      personRevision: 1,
      schemaVersion: currentRecordSchemaVersion,
    ),
    person: const ReportPerson(id: meId, name: 'Synthetic Person'),
    records: [
      for (final r in doses ?? [dose()])
        ReportRecord.fromUseRecord(r, includeStock: stock),
    ],
  );
  return switch (t) {
    ReportTemplateId.r01SubstanceSummary => s,
    ReportTemplateId.r02DetailedHistory => s.withTemplateData(
      ReportHistoryData.build(
        snapshot: s,
        items: [
          ReportItemDescriptor(
            itemId: 'item',
            name: 'Synthetic complete brand name',
            form: 'Injectable',
            type: 'Medicine',
            unit: 'ml',
          ),
        ],
      ),
    ),
    ReportTemplateId.r03EventReview => s.withTemplateData(
      ReportEventData.build(
        snapshot: s,
        event: EventRecord(
          id: 'event',
          personId: meId,
          name: 'Synthetic course',
          eventType: 'Course',
          zoneId: 'UTC',
          revision: 1,
          plannedStart: EventDate.day(CivilDate(2026, 10, 1)),
          plannedEnd: EventDate.day(CivilDate(2026, 10, 31)),
          memberships: [
            EventMembership(
              id: 'member',
              itemId: 'item',
              personId: meId,
              effectiveFrom: DateTime.utc(2026, 10, 1),
              revision: 1,
            ),
          ],
        ),
      ),
    ),
  };
}

String text(ReportSnapshot s) => switch (s.templateData) {
  final ReportHistoryData h => h.structuredText(s, use24Hour: true),
  final ReportEventData e => e.structuredText(s, use24Hour: true),
  _ => s.structuredText(use24Hour: true),
};
ReportTemplateRenderer renderer(ReportTemplateId t) => switch (t) {
  ReportTemplateId.r01SubstanceSummary => const R01SummaryRenderer(
    fontLoader: TestFonts(),
  ),
  ReportTemplateId.r02DetailedHistory => const R02HistoryRenderer(
    fontLoader: TestFonts(),
  ),
  ReportTemplateId.r03EventReview => const R03EventRenderer(
    fontLoader: TestFonts(),
  ),
};
Future<String> pdfText(Uint8List bytes) async {
  await PdfrxEntryFunctions.instance.init();
  final d = await PdfDocument.openData(
    bytes,
    useProgressiveLoading: false,
    maxSizeToCacheOnMemory: 0,
    sourceName: 'strength-test',
  );
  try {
    return [for (final p in d.pages) (await p.loadText())?.fullText ?? '']
        .join(' ')
        .replaceAll(RegExp(r'\s+'), ' ');
  } finally {
    await d.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    final f = File('build/native_assets/linux/libpdfium.so');
    if (Platform.isLinux && f.existsSync()) {
      Pdfrx.pdfiumModulePath = f.absolute.path;
    }
  });
  for (final t in ReportTemplateId.values) {
    test(
      '${t.id} exact strength agrees in PDF/text and mixing facts follow consent',
      () async {
        for (final stock in [false, true]) {
          final s = snapshot(t, stock);
          final txt = text(s);
          final rendered = await renderer(t).render(s, use24Hour: true);
          final pdf = await pdfText(rendered.bytes);
          for (final out in [txt, pdf]) {
            expect(out, contains('Strength: 2 mg per ml.'));
            expect(out, contains('Equivalent: 0.5 mg.'));
            expect(out, contains('dose-A'));
            expect(out, contains('Synthetic complete brand name'));
            expect(out, isNot(contains('Private container label')));
            if (stock) {
              expect(out, contains('24 mg in 12 ml final volume'));
              expect(out, contains('Liquid added: 11.8 ml'));
              expect(out, contains('Entered liquid source'));
            } else {
              expect(out, isNot(contains('Entered liquid source')));
              expect(out, isNot(contains('Liquid added:')));
              expect(out, isNot(contains('Prepared on:')));
            }
          }
          const destination = String.fromEnvironment('VITAL_STRENGTH_REPORTS');
          if (destination.isNotEmpty && stock) {
            await Directory(destination).create(recursive: true);
            await File('$destination/${t.id}.pdf').writeAsBytes(rendered.bytes);
          }
        }
      },
    );
  }
  test(
    'recurring vial strength and count strengths retain exact equivalents',
    () {
      final p = VialPreparation(
        powderAmount: '1',
        massUnit: 'mg',
        finalVolumeMl: '3',
      );
      final liquid = dose(
        strength: LabelledStrength(
          ingredientId: 'item',
          label: 'Vial',
          mgPerMl: p.mgPerMl,
          preparation: p,
        ),
      );
      final tablet = dose(
        id: 'tablet',
        unit: 'count',
        amount: '2',
        strength: LabelledStrength(
          ingredientId: 'item',
          label: '250 micrograms',
          mgPerCount: ExactAmount.parseEntry('0.25'),
        ),
      );
      final txt = text(
        snapshot(
          ReportTemplateId.r01SubstanceSummary,
          true,
          doses: [liquid, tablet],
        ),
      );
      expect(txt, contains('Strength: 1/3 mg per ml.'));
      expect(txt, contains('Equivalent: 1/12 mg.'));
      expect(txt, contains('Strength: 0.25 mg per item.'));
      expect(txt, contains('Equivalent: 0.5 mg.'));
    },
  );
  test('unknown strength does not invent a mass equivalent', () {
    final s = snapshot(
      ReportTemplateId.r01SubstanceSummary,
      false,
      doses: [
        dose(
          strength: LabelledStrength(ingredientId: 'item', label: 'Unknown'),
        ),
      ],
    );
    final lines = ReportText.doseStrengthLines(s).join('\n');
    expect(lines, contains('Strength: unknown.'));
    expect(lines, isNot(contains('Equivalent:')));
  });
  test('a snapshot rejects preparation facts when stock details are off', () {
    final s = snapshot(ReportTemplateId.r01SubstanceSummary, true);
    expect(
      () => ReportSnapshot.build(
        selection: s.selection.copyWith(includeStock: false),
        cutoff: s.cutoff,
        person: s.person,
        records: s.records,
      ),
      throwsA(isA<ReportSelectionFailure>()),
    );
  });
  test('capture uses frozen dose strength after defaults and stock metadata change', () async {
    final dir = await Directory.systemTemp.createTemp('vital-report-strength-');
    final store = await RecordStore.open(
      path: '${dir.path}/records.db',
      key: List.generate(32, (i) => i + 1),
      isNew: true,
    );
    try {
      final item = await store.createItem(
        commandId: 'item',
        name: 'Synthetic medicine',
        form: 'Powder',
        unit: 'ml',
        type: 'Medicine',
      );
      final container = await store.createStockContainer(
        commandId: 'container',
        personId: meId,
        expectedPersonRevision: 1,
        expectedGeneration: store.generation,
        itemId: item.id,
        label: 'Original vial',
        unit: 'ml',
        strength: LabelledStrength(
          ingredientId: item.id,
          label: '2 mg/ml',
          mgPerMl: prep.mgPerMl,
          preparation: prep,
        ),
        opening: ExactAmount.parseEntry('12'),
      );
      await store.record(
        commandId: 'dose',
        itemId: item.id,
        amount: '0.25',
        actualAt: DateTime.utc(2026, 10, 22, 8),
        stockUse: StockUseInput(
          expectedGeneration: store.generation,
          containerId: container.id,
          expectedContainerRevision: container.revision,
          entered: EnteredStockAmount('0.25', 'ml'),
        ),
      );
      final first = await store.captureReport(
        selection: selection(ReportTemplateId.r01SubstanceSummary, true),
        now: () => DateTime.utc(2026, 10, 22, 12),
      );
      await store.saveItemDetail(
        commandId: 'changed-default',
        itemId: item.id,
        instructions: '',
        notes: '',
        expectedRevision: null,
        profile: SubstanceProfile(
          route: SubstanceRoute.injectable,
          form: SubstanceForm.oil,
          strengthText: '400',
        ),
      );
      final second = await store.captureReport(
        selection: selection(ReportTemplateId.r01SubstanceSummary, false),
        now: () => DateTime.utc(2026, 10, 22, 13),
      );
      expect(
        first.snapshot.records.single.strength!.mgPerMl,
        ExactAmount.parseEntry('2'),
      );
      expect(
        second.snapshot.records.single.strength!.mgPerMl,
        ExactAmount.parseEntry('2'),
      );
      expect(second.snapshot.records.single.strength!.preparation, isNull);
      expect(
        ReportText.doseStrengthLines(first.snapshot).join(' '),
        contains('11.8'),
      );
      expect(
        ReportText.doseStrengthLines(second.snapshot).join(' '),
        isNot(contains('11.8')),
      );
    } finally {
      await store.close();
      await dir.delete(recursive: true);
    }
  });
  test('an unresolved strength replacement never publishes a calculated equivalent', () {
    final known = LabelledStrength(
      ingredientId: 'item',
      label: 'New strength',
      mgPerMl: ExactAmount.parseEntry('2'),
    );
    final r = dose(
      strength: known,
      replacement: StockReplacement(
        oldStrength: LabelledStrength(
          ingredientId: 'item',
          label: 'Unknown original',
        ),
        newStrength: known,
        keep: FixedReplacementAmount.milligrams,
      ),
    );
    expect(r.replacementResolved, isFalse);
    final s = snapshot(ReportTemplateId.r01SubstanceSummary, false, doses: [r]);
    final lines = ReportText.doseStrengthLines(s).join(' ');
    expect(lines, contains('Strength change unresolved.'));
    expect(lines, isNot(contains('Equivalent:')));
  });
}
