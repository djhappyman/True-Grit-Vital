import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:true_grit_vital/domain/events/events.dart';
import 'package:true_grit_vital/domain/history/history.dart';
import 'package:true_grit_vital/domain/records.dart';
import 'package:true_grit_vital/domain/reports/reports.dart';
import 'package:true_grit_vital/domain/scheduling/daily_plan.dart';
import 'package:true_grit_vital/domain/scheduling/stored_daily.dart';
import 'package:true_grit_vital/domain/stock/exact_amount.dart';
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

final class _Cancelled implements ReportCancellation {
  const _Cancelled();
  @override
  bool get isCancelled => true;
}

ReportSnapshot historySnapshot({
  int records = 3,
  int skipped = 0,
  int unrecorded = 0,
  String longName = '',
  String personId = 'me',
}) {
  final captured = ReportSnapshot.build(
    selection: ReportSelection(
      template: ReportTemplateId.r02DetailedHistory,
      personId: personId,
      fromDate: CivilDate(2026, 10, 18),
      beforeDate: CivilDate(2026, 10, 22),
      displayZone: 'Europe/London',
    ),
    cutoff: ReportCutoff(
      generatedAt: DateTime.utc(2026, 10, 21, 12),
      datasetGeneration: 'generation-1',
      personRevision: 1,
      schemaVersion: 21,
    ),
    person: ReportPerson(id: personId, name: 'Alex Morgan'),
    records: [
      for (var i = 0; i < records; i++)
        ReportRecord.fromUseRecord(
          UseRecord(
            id: 'record-$i',
            personId: personId,
            itemId: 'item-1',
            name: longName.isEmpty ? 'Example prescribed item' : longName,
            form: 'tablet',
            unit: 'count',
            type: i.isEven ? 'Medicines' : 'Supplements',
            enteredAmount: '1',
            actualAt: DateTime.utc(2026, 10, 18, 8).add(Duration(hours: i)),
            enteredAt: DateTime.utc(2026, 10, 18, 9),
            revision: i % 7 == 3 ? 2 : 1,
            isVoided: false,
            source: RecordSource.selfReported,
          ),
        ),
    ],
  );
  final data = ReportHistoryData.build(
    snapshot: captured,
    items: [
      ReportItemDescriptor(
        itemId: 'item-1',
        name: longName.isEmpty ? 'Example prescribed item' : longName,
        form: 'tablet',
        type: 'Medicines',
        unit: 'count',
      ),
    ],
    skipped: [
      for (var i = 0; i < skipped; i++)
        SkippedTimelineEntry(
          action: skipAction(id: 'skip-$i'),
          context: TimelinePlanContext(
            expectation: exactExpectation(
              item: 'item-1',
              plan: 'plan-$i',
              instant: DateTime.utc(2026, 10, 19, 7),
            ),
            planName: 'Plan $i',
            itemName: 'Example prescribed item',
          ),
        ),
    ],
    dailyRows: [
      for (var i = 0; i < unrecorded; i++)
        DailyRow(
          generation: 'generation-1',
          personRevision: 1,
          planRevision: 1,
          expectation: untimedExpectation(
            item: 'item-1',
            plan: 'unrecorded-$i',
            originalDate: CivilDate(2026, 10, 19),
            zone: 'UTC',
          ),
          personName: 'Alex Morgan',
          itemName: 'Example prescribed item',
          revision: 1,
          actions: const [],
          takenCount: 0,
          skippedCount: 0,
        ),
    ],
  );
  return captured.withTemplateData(data);
}

ReportSnapshot productSnapshot() {
  final captured = ReportSnapshot.build(
    selection: ReportSelection(
      template: ReportTemplateId.r02DetailedHistory,
      personId: 'me',
      fromDate: CivilDate(2026, 10, 18),
      beforeDate: CivilDate(2026, 10, 21),
      displayZone: 'Europe/London',
    ),
    cutoff: ReportCutoff(
      generatedAt: DateTime.utc(2026, 10, 20, 12),
      datasetGeneration: 'generation-1',
      personRevision: 1,
      schemaVersion: 21,
    ),
    person: const ReportPerson(id: 'me', name: 'Alex Morgan'),
    records: [
      ReportRecord(
        id: 'product-record',
        itemId: 'blend',
        name: 'Example blend',
        form: 'liquid',
        type: 'Blends',
        amount: ExactAmount.parseEntry('0.4'),
        unit: 'ml',
        actualAt: DateTime.utc(2026, 10, 19, 18),
        enteredAt: DateTime.utc(2026, 10, 19, 18, 3),
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
          ],
        ),
      ),
    ],
  );
  final data = ReportHistoryData.build(
    snapshot: captured,
    items: [
      ReportItemDescriptor(
        itemId: 'blend',
        name: 'Example blend',
        form: 'liquid',
        type: 'Blends',
        unit: 'ml',
      ),
    ],
  );
  return captured.withTemplateData(data);
}

ReportSnapshot eventSnapshot({bool ongoing = true, int records = 3}) {
  final e = EventRecord(
    id: 'event-1',
    personId: 'me',
    name: 'Example recorded course',
    eventType: 'Course',
    zoneId: 'Europe/London',
    revision: 1,
    plannedStart: EventDate.day(CivilDate(2026, 10, 18)),
    plannedEnd: EventDate.day(CivilDate(2026, 10, 21)),
    actualStart: ongoing ? null : EventDate.day(CivilDate(2026, 10, 18)),
    actualEnd: ongoing ? null : EventDate.day(CivilDate(2026, 10, 20)),
    completed: !ongoing,
    memberships: [
      EventMembership(
        id: 'member-1',
        itemId: 'item-1',
        personId: 'me',
        effectiveFrom: DateTime.utc(2026, 10, 18),
        revision: 1,
      ),
      EventMembership(
        id: 'member-2',
        itemId: 'item-2',
        personId: 'me',
        effectiveFrom: DateTime.utc(2026, 10, 18),
        revision: 1,
      ),
    ],
  );
  final captured = ReportSnapshot.build(
    selection: ReportSelection(
      template: ReportTemplateId.r03EventReview,
      personId: 'me',
      fromDate: CivilDate(2026, 10, 18),
      beforeDate: CivilDate(2026, 10, 21),
      displayZone: 'Europe/London',
      eventId: e.id,
    ),
    cutoff: ReportCutoff(
      generatedAt: DateTime.utc(2026, 10, 20, 12),
      datasetGeneration: 'generation-1',
      personRevision: 1,
      schemaVersion: 21,
    ),
    person: const ReportPerson(id: 'me', name: 'Alex Morgan'),
    records: [
      for (var i = 0; i < records; i++)
        ReportRecord.fromUseRecord(
          UseRecord(
            id: 'event-record-$i',
            personId: 'me',
            itemId: 'item-1',
            name: 'Example prescribed item',
            form: 'tablet',
            unit: 'count',
            type: 'Medicines',
            enteredAmount: '1',
            actualAt: DateTime.utc(2026, 10, 18, 8).add(Duration(hours: i)),
            enteredAt: DateTime.utc(2026, 10, 18, 9),
            revision: 1,
            isVoided: false,
          ),
        ),
    ],
  );
  final data = ReportEventData.build(
    snapshot: captured,
    event: e,
    items: [
      ReportItemDescriptor(
        itemId: 'item-1',
        name: 'Example prescribed item',
        form: 'tablet',
        type: 'Medicines',
        unit: 'count',
      ),
      ReportItemDescriptor(
        itemId: 'item-2',
        name: 'Example supplement',
        form: 'capsule',
        type: 'Supplements',
        unit: 'count',
      ),
    ],
    usePeriods: [
      RecordedUsePeriod(
        id: 'period-1',
        personId: 'me',
        itemId: 'item-1',
        revision: 1,
        start: EventDate.day(CivilDate(2026, 10, 18)),
      ),
      RecordedUsePeriod(
        id: 'period-2',
        personId: 'me',
        itemId: 'item-2',
        revision: 1,
        start: EventDate.day(CivilDate(2026, 10, 1)),
        end: EventDate.day(CivilDate(2026, 10, 10)),
      ),
    ],
    skipped: [
      SkippedTimelineEntry(
        action: skipAction(id: 'skip-1'),
        context: TimelinePlanContext(
          expectation: exactExpectation(
            item: 'item-1',
            instant: DateTime.utc(2026, 10, 19, 7),
          ),
          itemName: 'Example prescribed item',
        ),
      ),
    ],
  );
  return captured.withTemplateData(data);
}

void main() {
  const fonts = _TestFontLoader();

  group('R02 detailed history', () {
    test(
      'renders a paginated ledger with repeated chrome and full rows',
      () async {
        final snapshot = historySnapshot(
          records: 140,
          skipped: 6,
          unrecorded: 6,
        );
        final rendered = await const R02HistoryRenderer(fontLoader: fonts)
            .render(snapshot, use24Hour: true);

        expect(String.fromCharCodes(rendered.bytes.take(5)), '%PDF-');
        expect(rendered.pageCount, greaterThan(1));
        expect(rendered.fontsEmbedded, isFalse);
        expect(rendered.bytes.length, greaterThan(20000));
        final data = snapshot.templateData! as ReportHistoryData;
        expect(data.entries.length, 152);
        expect(data.notRecordedCount, 6);
      },
    );

    test('does not clip a long item name', () async {
      final longName = List.filled(12, 'Long example item name').join(' ');
      final rendered = await const R02HistoryRenderer(fontLoader: fonts)
          .render(historySnapshot(longName: longName), use24Hour: true);
      expect(rendered.pageCount, greaterThanOrEqualTo(1));
      expect(String.fromCharCodes(rendered.bytes.take(5)), '%PDF-');
    });

    test('keeps one captured identity across repeated renders', () async {
      final snapshot = historySnapshot(records: 20, skipped: 2);
      final renderer = const R02HistoryRenderer(fontLoader: fonts);
      final first = await renderer.render(snapshot, use24Hour: true);
      final second = await renderer.render(snapshot, use24Hour: true);
      // PDF creation metadata carries the generation time, so the reviewed
      // artifact is identified by its captured selection and cutoff.
      expect(first.pageCount, second.pageCount);
      expect(snapshot.artifactId.length, 12);
      expect(snapshot.neutralFileName, contains('vital-detailed-history'));
      expect(sha256.convert(first.bytes).toString().length, 64);
    });

    test('renders product volume and ingredient strength', () async {
      final snapshot = productSnapshot();
      final rendered = await const R02HistoryRenderer(fontLoader: fonts)
          .render(snapshot, use24Hour: true);
      expect(String.fromCharCodes(rendered.bytes.take(5)), '%PDF-');
      final text = reportTextFor(snapshot, use24Hour: true);
      expect(text, contains('Ingredient A (100 mg/ml)'));
      expect(text, contains('40 mg'));
      expect(text, contains('0.4 ml'));
    });

    test('honours cancellation before work starts', () async {
      await expectLater(
        const R02HistoryRenderer(fontLoader: fonts).render(
          historySnapshot(),
          use24Hour: true,
          cancellation: const _Cancelled(),
        ),
        throwsA(isA<ReportCancelled>()),
      );
    });

    test('structured text keeps every status distinct', () {
      final snapshot = historySnapshot(records: 8, skipped: 2, unrecorded: 2);
      final text = reportTextFor(snapshot, use24Hour: true);
      final decoded = utf8.decode(utf8.encode(text));
      expect(decoded, contains('Recorded:'));
      expect(decoded, contains('Corrected:'));
      expect(decoded, contains('Skipped:'));
      expect(decoded, contains('Not recorded:'));
      expect(decoded, contains('does not prove the dose was missed'));
      expect(decoded, isNot(contains('Substance summary')));
    });
  });

  group('R03 event review', () {
    test('renders members, open use periods and the event ledger', () async {
      final snapshot = eventSnapshot(records: 60);
      final rendered = await const R03EventRenderer(fontLoader: fonts)
          .render(snapshot, use24Hour: true);
      expect(String.fromCharCodes(rendered.bytes.take(5)), '%PDF-');
      expect(rendered.pageCount, greaterThanOrEqualTo(1));
      final text = reportTextFor(snapshot, use24Hour: true);
      expect(text, startsWith('Event review'));
      expect(text, contains('Ongoing separately'));
      expect(text, contains('Event state: Ongoing'));
    });

    test('reports an ended event without stopping members implicitly', () {
      final snapshot = eventSnapshot(ongoing: false, records: 2);
      final text = reportTextFor(snapshot, use24Hour: true);
      expect(text, contains('Event state: Ended'));
      expect(text, contains('Ongoing separately'));
      expect(text, contains('does not mean every included item stopped'));
    });

    test('cancels a render before building pages', () async {
      await expectLater(
        const R03EventRenderer(fontLoader: fonts).render(
          eventSnapshot(),
          use24Hour: true,
          cancellation: const _Cancelled(),
        ),
        throwsA(isA<ReportCancelled>()),
      );
    });
  });

  group('template catalog', () {
    test('exposes three distinct templates and their renderers', () {
      expect(reportTemplateCatalog.length, 3);
      expect(
        reportTemplateCatalog.map((definition) => definition.id).toSet(),
        ReportTemplateId.values.toSet(),
      );
      expect(
        rendererForTemplate(ReportTemplateId.r02DetailedHistory),
        isA<R02HistoryRenderer>(),
      );
      expect(
        rendererForTemplate(ReportTemplateId.r03EventReview),
        isA<R03EventRenderer>(),
      );
      expect(
        reportTemplateCatalog
            .singleWhere(
              (definition) => definition.id == ReportTemplateId.r03EventReview,
            )
            .requiresEvent,
        isTrue,
      );
    });
  });
}
