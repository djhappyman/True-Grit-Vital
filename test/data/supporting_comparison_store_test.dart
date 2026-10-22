import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:true_grit_vital/data/record_store.dart';

void main() {
  late Directory directory;
  late RecordStore store;
  final key = List.generate(32, (i) => i + 1);

  SupportingProvenance provenance({
    String laboratory = 'lab',
    String method = 'method',
    String specimen = 'serum',
  }) => SupportingProvenance(
    mode: SupportingProvenanceMode.manualTranscription,
    laboratoryId: laboratory,
    methodId: method,
    specimenId: specimen,
  );

  LabResultSnapshot result({
    String id = 'result',
    String metric = 'marker',
    String value = '1.25',
    String? unit = 'mg/L',
    SupportingProvenance? source,
  }) => LabResultSnapshot(
    id: id,
    metricId: metric,
    markerName: 'Full marker name',
    value: SupportingValue.numeric(value),
    unit: unit,
    provenance: source,
  );

  LabPanelSnapshot panel(
    String id, {
    required SupportingDate date,
    List<LabResultSnapshot>? results,
    SupportingProvenance? source,
  }) => LabPanelSnapshot(
    id: SupportingRecordId(id: id, personId: meId),
    title: 'Source panel',
    collectionDate: date,
    reportDate: SupportingDate.unknown(),
    provenance: source ?? provenance(),
    results: results ?? [result()],
  );

  Future<SupportingRevision> save(
    LabPanelSnapshot value, {
    int? revision,
    String? operation,
  }) => store.saveLabPanel(
    SaveLabPanelCommand(
      commandId: operation ?? 'save-${value.id.id}-${revision ?? 1}',
      generation: store.generation,
      expectedPersonRevision: 1,
      expectedRevision: revision,
      panel: value,
    ),
  );

  Future<SupportingEarlierComparison> compare(
    String viewedId,
    String resultId, {
    String zone = 'UTC',
  }) => store.supportingEarlierComparisonFor(
    personId: meId,
    recordId: viewedId,
    recordRevision: 1,
    resultId: resultId,
    displayZone: zone,
  );

  SupportingDate day(int value) =>
      SupportingDate.day(CivilDate(2026, 10, value));
  SupportingDate exact(int day, int hour) => SupportingDate.exact(
    DateTime.utc(2026, 10, day, hour),
    zoneId: 'UTC',
    utcOffsetMinutes: 0,
  );

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('vital-comparison-');
    store = await RecordStore.open(
      path: '${directory.path}/db',
      key: key,
      isNew: true,
    );
  });
  tearDown(() async {
    await store.close();
    await directory.delete(recursive: true);
  });

  test('finds a comparable result beyond fifty unrelated panels', () async {
    for (var i = 0; i < 60; i++) {
      await save(
        panel(
          'unrelated-$i',
          date: day(2),
          results: [result(id: 'other-$i', metric: 'other', value: '9')],
        ),
      );
    }
    final prior = await save(
      panel(
        'prior',
        date: day(1),
        results: [result(value: '1.25')],
      ),
    );
    await save(
      panel(
        'viewed',
        date: day(20),
        results: [result(value: '2.0')],
      ),
    );

    final comparison = await compare('viewed', 'result');
    expect(comparison.found, isTrue);
    expect(comparison.earlier!.record.id.id, prior.id.id);
    expect(comparison.change, '+0.75');
  });

  test('a viewed historical panel never compares with newer results', () async {
    await save(
      panel(
        'prior',
        date: day(1),
        results: [result(value: '1.25')],
      ),
    );
    await save(
      panel(
        'viewed',
        date: day(15),
        results: [result(value: '2.0')],
      ),
    );
    await save(
      panel(
        'newer',
        date: day(20),
        results: [result(value: '99')],
      ),
    );

    final comparison = await compare('viewed', 'result');
    expect(comparison.found, isTrue);
    expect(comparison.earlier!.record.id.id, 'prior');
    expect(comparison.change, '+0.75');
  });

  test('same-day exact instants compare only when strictly earlier', () async {
    await save(
      panel(
        'earlier',
        date: exact(20, 8),
        results: [result(value: '1.0')],
      ),
    );
    await save(
      panel(
        'equal',
        date: exact(20, 12),
        results: [result(value: '5.0')],
      ),
    );
    await save(
      panel(
        'viewed',
        date: exact(20, 12),
        results: [result(value: '2.0')],
      ),
    );

    final comparison = await compare('viewed', 'result');
    expect(comparison.found, isTrue);
    expect(comparison.earlier!.record.id.id, 'earlier');
    expect(comparison.change, '+1');
  });

  test(
    'an exact and day-only candidate on the same day stay ambiguous',
    () async {
      await save(
        panel(
          'exact',
          date: exact(19, 8),
          results: [result(value: '1.0')],
        ),
      );
      await save(
        panel(
          'day-only',
          date: day(19),
          results: [result(value: '2.0')],
        ),
      );
      await save(
        panel(
          'viewed',
          date: exact(20, 12),
          results: [result(value: '3.0')],
        ),
      );

      final comparison = await compare('viewed', 'result');
      expect(comparison.status, SupportingEarlierStatus.incomplete);
    },
  );

  test('a day-only viewed panel excludes its own day', () async {
    await save(
      panel(
        'same-day',
        date: day(20),
        results: [result(value: '1.0')],
      ),
    );
    await save(
      panel(
        'viewed',
        date: day(20),
        results: [result(value: '2.0')],
      ),
    );

    final comparison = await compare('viewed', 'result');
    expect(comparison.status, SupportingEarlierStatus.none);
  });

  test('unit, laboratory, method and specimen never cross identity', () async {
    await save(
      panel(
        'unit',
        date: day(1),
        results: [result(value: '1.0', unit: 'g/L')],
      ),
    );
    await save(
      panel(
        'lab',
        date: day(2),
        results: [result(value: '1.0')],
        source: provenance(laboratory: 'other'),
      ),
    );
    await save(
      panel(
        'method',
        date: day(3),
        results: [result(value: '1.0')],
        source: provenance(method: 'other'),
      ),
    );
    await save(
      panel(
        'specimen',
        date: day(4),
        results: [result(value: '1.0')],
        source: provenance(specimen: 'plasma'),
      ),
    );
    await save(
      panel(
        'override',
        date: day(5),
        results: [
          result(
            value: '1.0',
            source: provenance(laboratory: 'other'),
          ),
        ],
      ),
    );
    await save(
      panel(
        'override-match',
        date: day(6),
        results: [
          result(
            value: '1.5',
            source: provenance(laboratory: 'override'),
          ),
        ],
      ),
    );
    await save(
      panel(
        'viewed',
        date: day(20),
        results: [result(value: '2.0')],
      ),
    );

    var comparison = await compare('viewed', 'result');
    expect(comparison.status, SupportingEarlierStatus.none);

    await save(
      panel(
        'viewed-override',
        date: day(20),
        results: [
          result(
            value: '2.0',
            source: provenance(laboratory: 'override'),
          ),
        ],
      ),
    );
    comparison = await compare('viewed-override', 'result');
    expect(comparison.found, isTrue);
    expect(comparison.earlier!.record.id.id, 'override-match');
    expect(comparison.change, '+0.5');
  });

  test('corrections, void and restore change the live answer', () async {
    await save(
      panel(
        'prior',
        date: day(1),
        results: [result(value: '1.0')],
      ),
    );
    await save(
      panel(
        'viewed',
        date: day(20),
        results: [result(value: '4.0')],
      ),
    );

    final corrected = await save(
      panel(
        'prior',
        date: day(2),
        results: [result(value: '3.0')],
      ),
      revision: 1,
      operation: 'correct-prior',
    );
    var comparison = await compare('viewed', 'result');
    expect(comparison.found, isTrue);
    expect(comparison.earlier!.record.revision, corrected.revision);
    expect(comparison.change, '+1');

    final voided = await store.voidSupportingRecord(
      VoidSupportingRecordCommand(
        commandId: 'void-prior',
        generation: store.generation,
        personId: meId,
        id: 'prior',
        expectedPersonRevision: 1,
        expectedRevision: corrected.revision,
      ),
    );
    comparison = await compare('viewed', 'result');
    expect(comparison.status, SupportingEarlierStatus.none);

    await store.voidSupportingRecord(
      VoidSupportingRecordCommand(
        commandId: 'restore-prior',
        generation: store.generation,
        personId: meId,
        id: 'prior',
        expectedPersonRevision: 1,
        expectedRevision: voided.revision,
        isVoided: false,
      ),
    );
    comparison = await compare('viewed', 'result');
    expect(comparison.found, isTrue);
    expect(comparison.change, '+1');
  });

  test('qualitative values compare without numeric neighbours', () async {
    await save(
      panel(
        'qualitative',
        date: day(1),
        results: [
          LabResultSnapshot(
            id: 'result',
            metricId: 'marker',
            markerName: 'Full marker name',
            value: SupportingValue.qualitative('Negative'),
            unit: 'mg/L',
          ),
        ],
      ),
    );
    await save(
      panel(
        'numeric',
        date: day(10),
        results: [result(value: '8.0')],
      ),
    );
    await save(
      panel(
        'viewed',
        date: day(20),
        results: [
          LabResultSnapshot(
            id: 'result',
            metricId: 'marker',
            markerName: 'Full marker name',
            value: SupportingValue.qualitative('Positive'),
            unit: 'mg/L',
          ),
        ],
      ),
    );

    final comparison = await compare('viewed', 'result');
    expect(comparison.found, isTrue);
    expect(comparison.earlier!.record.id.id, 'qualitative');
    expect(comparison.earlier!.result.value.originalText, 'Negative');
    expect(comparison.change, isNull);
  });

  test('censored and missing values stay incomparable', () async {
    await save(
      panel(
        'exact',
        date: day(1),
        results: [result(value: '1.0')],
      ),
    );
    await save(
      panel(
        'censored',
        date: day(2),
        results: [result(value: '<0.5')],
      ),
    );
    await save(
      panel(
        'missing',
        date: day(3),
        results: [
          LabResultSnapshot(
            id: 'result',
            metricId: 'marker',
            markerName: 'Full marker name',
            value: SupportingValue.missing(),
            unit: 'mg/L',
          ),
        ],
      ),
    );
    await save(
      panel(
        'qualitative-newer',
        date: day(4),
        results: [
          LabResultSnapshot(
            id: 'result',
            metricId: 'marker',
            markerName: 'Full marker name',
            value: SupportingValue.qualitative('Trace'),
            unit: 'mg/L',
          ),
        ],
      ),
    );
    await save(
      panel(
        'viewed',
        date: day(20),
        results: [result(value: '2.0')],
      ),
    );
    var comparison = await compare('viewed', 'result');
    expect(comparison.found, isTrue);
    expect(comparison.earlier!.record.id.id, 'exact');

    await save(
      panel(
        'viewed-censored',
        date: day(20),
        results: [result(value: '<1.0')],
      ),
    );
    comparison = await compare('viewed-censored', 'result');
    expect(comparison.status, SupportingEarlierStatus.incompatible);

    await save(
      panel(
        'viewed-missing',
        date: day(20),
        results: [
          LabResultSnapshot(
            id: 'result',
            metricId: 'marker',
            markerName: 'Full marker name',
            value: SupportingValue.missing(),
            unit: 'mg/L',
          ),
        ],
      ),
    );
    comparison = await compare('viewed-missing', 'result');
    expect(comparison.status, SupportingEarlierStatus.incompatible);

    await save(
      panel(
        'viewed-unit',
        date: day(20),
        results: [result(value: '2.0', unit: null)],
      ),
    );
    comparison = await compare('viewed-unit', 'result');
    expect(comparison.status, SupportingEarlierStatus.incompatible);

    await save(
      panel(
        'viewed-undated',
        date: SupportingDate.unknown(originalText: 'Date unknown'),
        results: [result(value: '2.0')],
      ),
    );
    comparison = await compare('viewed-undated', 'result');
    expect(comparison.status, SupportingEarlierStatus.incomplete);
  });
}
