import 'package:flutter_test/flutter_test.dart';
import 'package:true_grit_vital/domain/history/history.dart';
import 'package:true_grit_vital/domain/records.dart';
import 'package:true_grit_vital/domain/reports/reports.dart';
import 'package:true_grit_vital/domain/scheduling/daily_plan.dart';
import 'package:true_grit_vital/domain/scheduling/stored_daily.dart';
import 'package:true_grit_vital/domain/stock/exact_amount.dart';

import '../history/history_test_data.dart';

UseRecord useRecord({
  String id = 'record-1',
  int revision = 1,
  String type = 'medicine',
  String? site,
  DateTime? actualAt,
  DateTime? enteredAt,
}) => UseRecord(
  id: id,
  personId: 'me',
  itemId: 'item-1',
  name: 'Example item',
  form: 'tablet',
  unit: 'mg',
  type: type,
  enteredAmount: '1',
  actualAt: actualAt ?? DateTime.utc(2026, 10, 19, 8),
  enteredAt: enteredAt ?? DateTime.utc(2026, 10, 19, 8, 5),
  revision: revision,
  isVoided: false,
  siteLabel: site,
);

ReportSnapshot snapshot({
  ReportTemplateId template = ReportTemplateId.r02DetailedHistory,
  Iterable<UseRecord> records = const [],
  bool includeSkipped = true,
  bool includeUnrecorded = true,
  bool includeNotes = false,
  String? eventId,
  Iterable<String> itemIds = const [],
  String person = 'me',
  DateTime? generatedAt,
}) => ReportSnapshot.build(
  selection: ReportSelection(
    template: template,
    personId: person,
    fromDate: CivilDate(2026, 10, 18),
    beforeDate: CivilDate(2026, 10, 21),
    displayZone: 'Europe/London',
    eventId: eventId,
    itemIds: itemIds,
    includeSkipped: includeSkipped,
    includeUnrecorded: includeUnrecorded,
    includeNotes: includeNotes,
  ),
  cutoff: ReportCutoff(
    generatedAt: generatedAt ?? DateTime.utc(2026, 10, 20, 12),
    datasetGeneration: 'generation-1',
    personRevision: 1,
    schemaVersion: 21,
  ),
  person: ReportPerson(id: person, name: 'Alex Morgan'),
  records: records.map(ReportRecord.fromUseRecord),
);

DailyRow planRow({
  required DailyExpectation expectation,
  int taken = 0,
  int skipped = 0,
  String itemName = 'Example item',
}) => DailyRow(
  generation: 'generation-1',
  personRevision: 1,
  planRevision: 1,
  expectation: expectation,
  personName: 'Alex Morgan',
  itemName: itemName,
  revision: 1,
  actions: const [],
  takenCount: taken,
  skippedCount: skipped,
);

SkippedTimelineEntry skipEntry({
  String id = 'skip-1',
  DailyExpectation? expectation,
  String person = 'me',
  String? reason,
}) {
  final e =
      expectation ??
      exactExpectation(person: person, instant: DateTime.utc(2026, 10, 19, 7));
  return SkippedTimelineEntry(
    action: skipAction(id: id, reason: reason),
    context: TimelinePlanContext(
      expectation: e,
      planName: 'Morning plan',
      itemName: 'Example item',
    ),
  );
}

void main() {
  group('ReportHistoryData', () {
    test('selected substances filter skipped and not-recorded rows too', () {
      final captured = snapshot(itemIds: const ['selected']);
      final data = ReportHistoryData.build(
        snapshot: captured,
        skipped: [skipEntry()],
        dailyRows: [planRow(expectation: exactExpectation())],
      );
      expect(data.entries, isEmpty);
    });

    test(
      'keeps recorded, corrected, skipped and not-recorded rows distinct',
      () {
        final captured = snapshot(
          records: [
            useRecord(id: 'record-1'),
            useRecord(
              id: 'record-2',
              revision: 2,
              actualAt: DateTime.utc(2026, 10, 19, 9),
              enteredAt: DateTime.utc(2026, 10, 20, 10),
            ),
          ],
        );
        final data = ReportHistoryData.build(
          snapshot: captured,
          items: [
            ReportItemDescriptor(
              itemId: 'item-1',
              name: 'Example item',
              form: 'tablet',
              type: 'medicine',
              unit: 'mg',
            ),
          ],
          skipped: [skipEntry()],
          dailyRows: [
            planRow(
              expectation: exactExpectation(
                instant: DateTime.utc(2026, 10, 18, 8),
                originalDate: CivilDate(2026, 10, 18),
              ),
            ),
          ],
        );

        expect(data.entries.length, 4);
        expect(data.recordedCount, 1);
        expect(data.correctedCount, 1);
        expect(data.skippedCount, 1);
        expect(data.notRecordedCount, 1);
        expect(data.entries.map((entry) => entry.status).toSet(), {
          ReportLedgerStatus.recorded,
          ReportLedgerStatus.corrected,
          ReportLedgerStatus.skipped,
          ReportLedgerStatus.notRecorded,
        });
        final corrected = data.entries.firstWhere(
          (entry) => entry.status == ReportLedgerStatus.corrected,
        );
        expect(corrected.entryAt, DateTime.utc(2026, 10, 20, 10));
        final notRecorded = data.entries.firstWhere(
          (entry) => entry.status == ReportLedgerStatus.notRecorded,
        );
        expect(notRecorded.amount, isNull);
        expect(notRecorded.typeLabel, 'medicine');
      },
    );

    test('orders rows by the actual or planned time', () {
      final captured = snapshot(
        records: [
          useRecord(id: 'later', actualAt: DateTime.utc(2026, 10, 19, 18)),
          useRecord(id: 'earlier', actualAt: DateTime.utc(2026, 10, 19, 7)),
        ],
      );
      final data = ReportHistoryData.build(snapshot: captured);
      expect(data.entries.first.id, 'r:earlier');
      expect(data.entries.last.id, 'r:later');
    });

    test('does not invent not-recorded rows for resolved occurrences', () {
      final captured = snapshot();
      final data = ReportHistoryData.build(
        snapshot: captured,
        dailyRows: [
          planRow(expectation: exactExpectation(), taken: 1),
          planRow(expectation: exactExpectation(), skipped: 1),
          planRow(
            expectation: DailyExpectation(
              identity: DailyIdentity(
                personId: 'me',
                planId: 'plan-2',
                originalDate: CivilDate(2026, 10, 19),
              ),
              itemId: 'item-1',
              versionId: 'version-1',
              zoneId: 'Europe/London',
              amount: PlannedAmount(
                quantity: ExactQuantity.parse('1'),
                unit: 'mg',
              ),
              resolution: DailyResolution.untimed,
              calculatorVersion: 'calculator-1',
              timezoneDataVersion: '2026e',
              plannedCount: 2,
            ),
            taken: 1,
          ),
        ],
      );
      expect(data.notRecordedCount, 1);
      expect(data.entries.single.itemId, 'item-1');
    });

    test('respects the explicit skipped and not-recorded choices', () {
      final captured = snapshot(
        includeSkipped: false,
        includeUnrecorded: false,
      );
      final data = ReportHistoryData.build(
        snapshot: captured,
        skipped: [skipEntry()],
        dailyRows: [planRow(expectation: exactExpectation())],
      );
      expect(data.entries, isEmpty);
    });

    test('does not read another adult into the ledger', () {
      final captured = snapshot();
      expect(
        () => ReportHistoryData.build(
          snapshot: captured,
          skipped: [skipEntry(person: 'adult-2')],
        ),
        throwsA(
          isA<ReportSelectionFailure>().having(
            (error) => error.code,
            'code',
            'report_owner',
          ),
        ),
      );
    });

    test(
      'reports incomplete plan coverage instead of silently omitting rows',
      () {
        final data = ReportHistoryData.build(
          snapshot: snapshot(),
          planCoverageComplete: false,
          planIssue: 'observedZoneUnavailable',
        );
        expect(data.coverageNote, contains('may be incomplete'));
        expect(data.coverageNote, isNot(contains('observedZoneUnavailable')));
      },
    );

    test(
      'keeps a skip row while hiding its reason unless notes are selected',
      () {
        final private = snapshot();
        final privateData = ReportHistoryData.build(
          snapshot: private,
          skipped: [skipEntry(reason: 'Felt unwell')],
        );
        final privateEntry = privateData.entries.single;
        expect(privateEntry.id, 's:skip-1');
        expect(privateEntry.status, ReportLedgerStatus.skipped);
        expect(privateEntry.skipReason, isNull);
        expect(
          privateData.structuredText(private, use24Hour: true),
          isNot(contains('Felt unwell')),
        );

        final shared = snapshot(includeNotes: true);
        final sharedData = ReportHistoryData.build(
          snapshot: shared,
          skipped: [skipEntry(reason: 'Felt unwell')],
        );
        expect(sharedData.entries.single.skipReason, 'Felt unwell');
        expect(
          sharedData.structuredText(shared, use24Hour: true),
          contains('Skip reason: Felt unwell'),
        );
      },
    );

    test('structured text keeps status meanings and ownership', () {
      final captured = snapshot(
        records: [useRecord(id: 'record-1', revision: 2)],
      );
      final data = ReportHistoryData.build(
        snapshot: captured,
        skipped: [skipEntry()],
        dailyRows: [planRow(expectation: exactExpectation())],
      );
      final text = data.structuredText(captured, use24Hour: true);
      expect(text, startsWith('Detailed history'));
      expect(text, contains('Person: Alex Morgan'));
      expect(text, contains('Corrected: 1'));
      expect(text, contains('Skipped: 1'));
      expect(text, contains('Not recorded: 1'));
      expect(text, contains('It does not prove the dose was missed.'));
      expect(text, isNot(contains('adult-2')));
    });

    test(
      'keeps a ready-mixed product separate from its ingredient amounts',
      () {
        final product = ReportProduct(
          volumeUnit: 'ml',
          ingredients: [
            ReportProductIngredient(
              ingredientId: 'ingredient-a',
              name: 'Ingredient A',
              unit: 'mg',
              strength: '100 mg/ml',
              amount: ExactAmount.parseEntry('40'),
            ),
            ReportProductIngredient(
              ingredientId: 'ingredient-b',
              name: 'Ingredient B',
              unit: 'mg',
              strength: '50 mg/ml',
              amount: ExactAmount.parseEntry('20'),
            ),
          ],
        );
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
              product: product,
            ),
          ],
        );
        final data = ReportHistoryData.build(snapshot: captured);
        final entry = data.entries.single;
        expect(entry.unit, 'ml');
        expect(formatAmount(entry.amount!), '0.4');
        expect(entry.product!.ingredients.length, 2);
        final text = data.structuredText(captured, use24Hour: true);
        expect(text, contains('Ingredient Ingredient A (100 mg/ml): 40 mg'));
        expect(text, contains('Ingredient Ingredient B (50 mg/ml): 20 mg'));
        expect(captured.totals.productAdministrations, 1);
      },
    );

    test('rejects a payload for another template', () {
      final captured = snapshot(template: ReportTemplateId.r01SubstanceSummary);
      expect(
        () => ReportHistoryData.build(snapshot: captured),
        throwsA(isA<ReportSelectionFailure>()),
      );
    });
  });
}
