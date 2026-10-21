import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:true_grit_vital/data/record_store.dart';
import 'package:true_grit_vital/domain/exports/exports.dart';

void main() {
  late Directory directory;
  late String path;
  late RecordStore store;
  final key = List.generate(32, (i) => i + 1);

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('vital-export-');
    path = '${directory.path}/test.db';
    store = await RecordStore.open(path: path, key: key, isNew: true);
    await store.editProfile(
      commandId: 'profile',
      personId: meId,
      expectedRevision: 1,
      name: 'Alex',
      adultConfirmed: true,
      reportName: 'A. Example',
    );
  });

  tearDown(() async {
    await store.close();
    await directory.delete(recursive: true);
  });

  ExportSelection selection({
    ExportFormat format = ExportFormat.json,
    bool includeNotes = false,
    ExportLimits limits = ExportLimits.standard,
    String personId = meId,
    Iterable<ExportContent> contents = const [
      ExportContent.doses,
      ExportContent.supporting,
    ],
  }) => ExportSelection(
    personId: personId,
    fromDay: CivilDate(2026, 10, 1),
    beforeDay: CivilDate(2026, 11, 1),
    zoneId: 'UTC',
    contents: contents,
    format: format,
    includeNotes: includeNotes,
    limits: limits,
  );

  Future<SubstanceItem> item(String personId, {int personRevision = 2}) =>
      store.createItem(
        commandId: 'item-$personId',
        personId: personId,
        expectedPersonRevision: personRevision,
        name: 'Synthetic item $personId',
        form: 'Liquid',
        unit: 'ml',
        type: 'Medicine',
      );

  Future<SupportingRevision> panel({
    String? notes = 'Private note',
    String id = 'panel-1',
    SupportingDate? collectionDate,
  }) => store.saveLabPanel(
    SaveLabPanelCommand(
      commandId: 'panel-$id',
      generation: store.generation,
      expectedPersonRevision: 2,
      panel: LabPanelSnapshot(
        id: SupportingRecordId(id: id, personId: meId),
        title: 'Synthetic report',
        collectionDate:
            collectionDate ?? SupportingDate.day(CivilDate(2026, 10, 2)),
        reportDate: SupportingDate.day(CivilDate(2026, 10, 4)),
        provenance: SupportingProvenance(
          mode: SupportingProvenanceMode.manualTranscription,
          laboratoryName: 'Synthetic laboratory',
          sourceReferences: [
            SupportingSourceReference(
              id: 'report-source-1',
              personId: meId,
              version: 1,
              kind: SupportingSourceKind.report,
            ),
          ],
        ),
        results: [
          LabResultSnapshot(
            id: 'result-1',
            metricId: 'metric-1',
            markerName: 'Marker',
            value: SupportingValue.numeric('1.5'),
            unit: 'mg/L',
          ),
        ],
        notes: notes,
      ),
    ),
  );

  test('captures one person, every correction and original units', () async {
    final mine = await item(meId);
    final recorded = await store.record(
      commandId: 'dose-1',
      itemId: mine.id,
      amount: '2.5',
      actualAt: DateTime.utc(2026, 10, 5, 10),
      expectedPersonRevision: 2,
    );
    await store.correct(
      commandId: 'dose-2',
      recordId: recorded.id,
      expectedRevision: 1,
      amount: '3',
      actualAt: DateTime.utc(2026, 10, 5, 11),
      expectedPersonRevision: 2,
    );
    await store.voidRecord(
      commandId: 'dose-3',
      recordId: recorded.id,
      expectedRevision: 2,
      expectedPersonRevision: 2,
    );
    // Outside the selected range and owned by another adult.
    await store.record(
      commandId: 'outside',
      itemId: mine.id,
      amount: '1',
      actualAt: DateTime.utc(2026, 9, 1, 10),
      expectedPersonRevision: 2,
    );
    final other = await store.createProfile(
      commandId: 'other',
      name: 'Other adult',
      adultConfirmed: true,
    );
    final otherItem = await item(other.id, personRevision: 1);
    await store.record(
      commandId: 'other-dose',
      personId: other.id,
      itemId: otherItem.id,
      amount: '9',
      actualAt: DateTime.utc(2026, 10, 6, 10),
      expectedPersonRevision: 1,
    );
    await panel();

    final document = await store.captureExport(selection());

    expect(document.personName, 'Alex');
    expect(document.reportName, 'A. Example');
    expect(document.recordSchemaVersion, 23);
    expect(document.doseRecords, 1, reason: 'only the selected adult');
    expect(document.doses.map((row) => row.revision), [1, 2, 3]);
    expect(document.doses.map((row) => row.isCurrent), [false, false, true]);
    expect(document.doses.map((row) => row.isVoided), [false, false, true]);
    expect(document.doses.map((row) => row.enteredAmount), ['2.5', '3', '3']);
    expect(document.doses.every((row) => row.enteredUnit == 'ml'), true);
    expect(document.doses.every((row) => row.actualUnit == 'ml'), true);
    expect(document.doses.first.source, RecordSource.selfReported);
    expect(document.doses.first.correctedAt, isNull);
    expect(document.doses[1].correctedAt, isNotNull);
    expect(document.doses.last.actualAt, DateTime.utc(2026, 10, 5, 11));
    expect(document.supportingRecords, 1);
    expect(
      document.supporting.single.snapshot.provenance.laboratoryName,
      'Synthetic laboratory',
    );

    final bytes = utf8.decode(ExportArtifact.build(document).bytes);
    expect(bytes, contains('Alex'));
    expect(bytes, isNot(contains('Other adult')));
    expect(bytes, isNot(contains('999999')));
    expect(bytes, isNot(contains('Private note')));
    expect(bytes, isNot(contains('report-source-1')));
  });

  test('notes require an explicit selection', () async {
    await panel(notes: 'Selected note');
    final hidden = await store.captureExport(selection());
    expect(hidden.supporting.single.snapshot.notes, isNull);
    final shown = await store.captureExport(selection(includeNotes: true));
    expect(shown.supporting.single.snapshot.notes, 'Selected note');
    expect(
      shown.supporting.single.snapshot.provenance.sourceReferences,
      isEmpty,
      reason: 'file references never enter a structured export',
    );
  });

  test('authored item details follow the explicit notes selection', () async {
    final mine = await item(meId);
    await store.record(
      commandId: 'dose-details',
      itemId: mine.id,
      amount: '0.125',
      actualAt: DateTime.utc(2026, 10, 5, 10),
      expectedPersonRevision: 2,
    );
    const instructions = 'Use the labelled amount: 0.125 mg, <0.10.';
    const notes = 'Private note kept word for word.';
    await store.saveItemDetail(
      commandId: 'detail-save',
      itemId: mine.id,
      instructions: instructions,
      notes: notes,
      expectedRevision: null,
      expectedPersonRevision: 2,
    );

    final hidden = await store.captureExport(selection());
    expect(hidden.doses.single.itemInstructions, isNull);
    expect(hidden.doses.single.itemNotes, isNull);
    final hiddenText = utf8.decode(ExportArtifact.build(hidden).bytes);
    expect(hiddenText, isNot(contains('0.125 mg')));
    expect(hiddenText, isNot(contains('word for word')));

    final shown = await store.captureExport(selection(includeNotes: true));
    expect(shown.doses.single.itemInstructions, instructions);
    expect(shown.doses.single.itemNotes, notes);
    final json = utf8.decode(ExportArtifact.build(shown).bytes);
    expect(json, contains('0.125 mg'));
    expect(json, contains('word for word'));
    final csv = await store.captureExport(
      selection(format: ExportFormat.csv, includeNotes: true),
    );
    final csvText = utf8.decode(ExportArtifact.build(csv).bytes);
    expect(csvText.split('\r\n').first, contains('item_instructions'));
    expect(csvText, contains('0.125 mg'));
    expect(csvText, contains('word for word'));
  });

  test('dose, skip and supporting rows share one aligned CSV shape', () async {
    final mine = await item(meId);
    await store.saveItemDetail(
      commandId: 'detail-save',
      itemId: mine.id,
      instructions: 'Use the labelled amount, then review.',
      notes: 'Private detail note.',
      expectedRevision: null,
      expectedPersonRevision: 2,
    );
    await store.record(
      commandId: 'dose-alignment',
      itemId: mine.id,
      amount: '1',
      actualAt: DateTime.utc(2026, 10, 5, 10),
      expectedPersonRevision: 2,
    );
    await panel(notes: 'Private supporting note.');
    final date = CivilDate(2026, 10, 20);
    await store.saveDailyPlan(
      commandId: 'plan-alignment',
      plan: DailyPlanVersion(
        personId: meId,
        planId: 'plan-alignment',
        itemId: mine.id,
        versionId: 'v1',
        start: date,
        timing: DailyCount(
          1,
          PlannedAmount(
            quantity: ExactQuantity.parse('1'),
            enteredText: '1',
            unit: 'ml',
          ),
        ),
        zoneBasis: const FollowingLocal(),
        calendar: const EveryDay(),
      ),
      expectedPersonRevision: 2,
      expectedGeneration: store.generation,
    );
    final planRow = (await store.dailyRows(
      from: date,
      toExclusive: date.addDays(1),
      observedZone: 'UTC',
    )).rows.single;
    final skipped = await store.actDaily(
      commandId: 'skip-alignment',
      row: planRow,
      kind: DailyActionKind.skip,
      skipReason: 'Felt unwell',
    );

    final document = await store.captureExport(
      selection(format: ExportFormat.csv, includeNotes: true),
    );
    expect(document.skipped.single.actionId, skipped.id);
    expect(document.skipped.single.reason, 'Felt unwell');
    final lines = utf8
        .decode(ExportArtifact.build(document).bytes)
        .split('\r\n');
    expect(lines.first.split(','), exportCsvHeader);
    expect(
      lines.every((line) => _fieldCount(line) == exportCsvHeader.length),
      isTrue,
    );
    expect(lines.first, contains('item_instructions'));
    expect(lines.first, contains('skip_reason'));
    expect(
      lines.firstWhere((line) => line.startsWith('skip,')),
      contains('Felt unwell'),
    );
  });

  test('skip bound fails instead of truncating exported actions', () async {
    final date = CivilDate(2026, 10, 20);
    final items = <SubstanceItem>[];
    for (final suffix in ['a', 'b']) {
      final created = await store.createItem(
        commandId: 'skip-bound-item-$suffix',
        expectedPersonRevision: 2,
        name: 'Synthetic skip item $suffix',
        form: 'Liquid',
        unit: 'ml',
        type: 'Medicine',
      );
      items.add(created);
      await store.saveDailyPlan(
        commandId: 'skip-bound-plan-$suffix',
        plan: DailyPlanVersion(
          personId: meId,
          planId: 'skip-bound-plan-$suffix',
          itemId: created.id,
          versionId: 'skip-bound-version-$suffix',
          start: date,
          timing: DailyCount(
            1,
            PlannedAmount(
              quantity: ExactQuantity.parse('1'),
              enteredText: '1',
              unit: 'ml',
            ),
          ),
          zoneBasis: const FollowingLocal(),
          calendar: const EveryDay(),
        ),
        expectedPersonRevision: 2,
        expectedGeneration: store.generation,
      );
    }
    final rows = (await store.dailyRows(
      from: date,
      toExclusive: date.addDays(1),
      observedZone: 'UTC',
    )).rows;
    for (final row in rows) {
      await store.actDaily(
        commandId: 'skip-bound-${row.expectation.itemId}',
        row: row,
        kind: DailyActionKind.skip,
        skipReason: 'Felt unwell',
      );
    }
    await expectLater(
      store.captureExport(
        selection(limits: const ExportLimits(maxSkippedRecords: 1)),
      ),
      throwsA(
        isA<ExportLimitException>().having(
          (error) => error.code,
          'code',
          'export_skipped_records',
        ),
      ),
    );
  });

  test(
    'unknown and partial collection dates are excluded and disclosed',
    () async {
      await item(meId);
      await panel();
      await panel(
        id: 'panel-2',
        notes: null,
        collectionDate: SupportingDate.unknown(
          originalText: 'Unknown sample time',
        ),
      );
      await store.saveLabPanel(
        SaveLabPanelCommand(
          commandId: 'panel-3',
          generation: store.generation,
          expectedPersonRevision: 2,
          panel: LabPanelSnapshot(
            id: SupportingRecordId(id: 'panel-3', personId: meId),
            title: 'Secret partial report',
            collectionDate: SupportingDate.partial(
              year: 2024,
              month: 10,
              originalText: '2024-10',
            ),
            reportDate: SupportingDate.day(CivilDate(2026, 10, 4)),
            provenance: SupportingProvenance(
              mode: SupportingProvenanceMode.manualTranscription,
              laboratoryName: 'Synthetic laboratory',
            ),
            results: [
              LabResultSnapshot(
                id: 'result-3',
                metricId: 'metric-1',
                markerName: 'Marker',
                value: SupportingValue.numeric('2'),
                unit: 'mg/L',
              ),
            ],
            notes: 'Secret partial note',
          ),
        ),
      );

      final document = await store.captureExport(selection());
      expect(document.undatedCollection, isNotNull);
      expect(document.undatedCollection!.counted, isTrue);
      expect(document.undatedCollection!.records, 2);
      // The positioned record keeps its exact in-range cutoff.
      expect(document.supporting.map((row) => row.recordId), ['panel-1']);
      expect(
        document.supporting.single.snapshot.collectionDate.civilDate,
        CivilDate(2026, 10, 2),
      );

      final json = document.toJson();
      final omissions = json['omissions'] as Map<String, Object?>;
      final disclosed =
          omissions['collectionDateUnknownOrPartial'] as Map<String, Object?>;
      expect(disclosed['records'], 2);
      expect(disclosed['counted'], true);
      expect(disclosed.containsKey('title'), isFalse);
      expect(disclosed.containsKey('notes'), isFalse);
      expect(json['supporting'], hasLength(1));

      final bytes = utf8.decode(ExportArtifact.build(document).bytes);
      expect(bytes, contains('collectionDateUnknownOrPartial'));
      expect(bytes, contains('"records": 2'));
      expect(bytes, isNot(contains('Secret partial report')));
      expect(bytes, isNot(contains('Secret partial note')));
      expect(bytes, isNot(contains('2024-10')));

      final csv = await store.captureExport(
        selection(format: ExportFormat.csv),
      );
      final csvBytes = utf8.decode(ExportArtifact.build(csv).bytes);
      expect(csvBytes, isNot(contains('Secret partial report')));
      expect(csvBytes, contains('2026-10-02'));
    },
  );

  test('a voided unpositioned record is disclosed without leaking', () async {
    await panel(
      id: 'panel-2',
      notes: null,
      collectionDate: SupportingDate.unknown(),
    );
    await store.voidSupportingRecord(
      VoidSupportingRecordCommand(
        commandId: 'void',
        generation: store.generation,
        personId: meId,
        id: 'panel-2',
        expectedPersonRevision: 2,
        expectedRevision: 1,
        isVoided: true,
      ),
    );
    final document = await store.captureExport(selection());
    expect(document.supporting, isEmpty);
    expect(document.undatedCollection!.records, 1);
  });

  test('omissions respect the supporting selection', () async {
    await panel(
      id: 'panel-2',
      notes: null,
      collectionDate: SupportingDate.unknown(),
    );
    final dosed = await store.captureExport(
      selection(contents: const [ExportContent.doses]),
    );
    expect(dosed.undatedCollection, isNull);
    expect((dosed.toJson()).containsKey('omissions'), isFalse);
  });

  test('a reached counting bound is uncounted, never fabricated', () async {
    await panel(
      id: 'panel-2',
      notes: null,
      collectionDate: SupportingDate.unknown(),
    );
    await panel(
      id: 'panel-3',
      notes: null,
      collectionDate: SupportingDate.partial(originalText: 'unknown month'),
    );
    final document = await store.captureExport(
      selection(limits: const ExportLimits(maxSupportingRecords: 1)),
    );
    expect(document.undatedCollection!.counted, isFalse);
    expect(document.undatedCollection!.records, isNull);
    final disclosed =
        ((document.toJson()['omissions']
                as Map<String, Object?>)['collectionDateUnknownOrPartial']
            as Map<String, Object?>);
    expect(disclosed['records'], isNull);
    expect(disclosed['counted'], isFalse);
  });

  test(
    'supporting capture crosses bounded pages without dropping revisions',
    () async {
      await panel();
      for (var revision = 1; revision <= 3; revision++) {
        await store.voidSupportingRecord(
          VoidSupportingRecordCommand(
            commandId: 'toggle-$revision',
            generation: store.generation,
            personId: meId,
            id: 'panel-1',
            expectedPersonRevision: 2,
            expectedRevision: revision,
            isVoided: revision.isOdd,
          ),
        );
      }
      final captured = await store.captureExport(
        selection(limits: const ExportLimits(chunk: 1)),
      );
      expect(captured.supporting.map((row) => row.revision), [1, 2, 3, 4]);
      expect(captured.supporting.map((row) => row.isCurrent), [
        false,
        false,
        false,
        true,
      ]);
    },
  );

  test(
    'revision overflow fails instead of returning a truncated history',
    () async {
      final mine = await item(meId);
      final recorded = await store.record(
        commandId: 'dose',
        itemId: mine.id,
        amount: '1',
        actualAt: DateTime.utc(2026, 10, 5),
        expectedPersonRevision: 2,
      );
      await store.correct(
        commandId: 'correct',
        recordId: recorded.id,
        expectedRevision: 1,
        amount: '2',
        actualAt: DateTime.utc(2026, 10, 5),
        expectedPersonRevision: 2,
      );
      await expectLater(
        store.captureExport(
          selection(limits: const ExportLimits(maxDoseRevisions: 1)),
        ),
        throwsA(
          isA<ExportLimitException>().having(
            (error) => error.code,
            'code',
            'export_dose_revisions',
          ),
        ),
      );
    },
  );

  test('a cancelled capture reads nothing and returns no document', () async {
    final token = ExportCancellation()..cancel();
    await expectLater(
      store.captureExport(selection(), cancellation: token),
      throwsA(isA<ExportCancelled>()),
    );
  });

  test('record bounds fail explicitly instead of truncating', () async {
    final mine = await item(meId);
    await store.record(
      commandId: 'dose-a',
      itemId: mine.id,
      amount: '1',
      actualAt: DateTime.utc(2026, 10, 5, 10),
      expectedPersonRevision: 2,
    );
    await store.record(
      commandId: 'dose-b',
      itemId: mine.id,
      amount: '1',
      actualAt: DateTime.utc(2026, 10, 5, 11),
      expectedPersonRevision: 2,
    );
    await expectLater(
      store.captureExport(
        selection(limits: const ExportLimits(maxDoseRecords: 1)),
      ),
      throwsA(
        isA<ExportLimitException>().having(
          (error) => error.code,
          'code',
          'export_dose_records',
        ),
      ),
    );
  });

  test(
    'capture enforces the byte bound before a giant document exists',
    () async {
      final mine = await item(meId);
      await store.record(
        commandId: 'dose',
        itemId: mine.id,
        amount: '1',
        actualAt: DateTime.utc(2026, 10, 5, 10),
        expectedPersonRevision: 2,
      );
      await expectLater(
        store.captureExport(
          selection(limits: const ExportLimits(maxBytes: 1024)),
        ),
        throwsA(
          isA<ExportLimitException>().having(
            (error) => error.code,
            'code',
            'export_bytes',
          ),
        ),
      );
    },
  );

  test('CSV and JSON artifacts share the same captured selection', () async {
    final mine = await item(meId);
    await store.record(
      commandId: 'dose',
      itemId: mine.id,
      amount: '0.125',
      actualAt: DateTime.utc(2026, 10, 5, 10),
      expectedPersonRevision: 2,
    );
    final json = await store.captureExport(selection());
    final csv = await store.captureExport(selection(format: ExportFormat.csv));
    final csvText = utf8.decode(ExportArtifact.build(csv).bytes);
    expect(csvText.split('\r\n').first, contains('actual_amount_exact'));
    expect(csvText, contains('0.125'));
    expect(csvText, contains('1/8'));
    expect(
      json.doses.single.actualAmount,
      ExactAmount(BigInt.one, BigInt.from(8)),
    );
  });
}

int _fieldCount(String line) {
  var fields = 1;
  var quoted = false;
  for (var i = 0; i < line.length; i++) {
    final unit = line.codeUnitAt(i);
    if (unit == 0x22) {
      if (quoted && i + 1 < line.length && line.codeUnitAt(i + 1) == 0x22) {
        i++;
      } else {
        quoted = !quoted;
      }
    } else if (unit == 0x2C && !quoted) {
      fields++;
    }
  }
  return fields;
}
