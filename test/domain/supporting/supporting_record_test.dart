import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'supporting_test_data.dart';

void main() {
  test(
    'collection report entry correction are independent after codec roundtrip',
    () {
      final saved = record(revision: 2, corrected: DateTime.utc(2026, 10, 20));
      final restored = SupportingRevision.fromJson(
        jsonDecode(jsonEncode(saved.toJson())) as Map<String, dynamic>,
      );
      expect(
        restored.snapshot.collectionDate.civilDate,
        CivilDate(2026, 10, 1),
      );
      expect(restored.snapshot.reportDate.civilDate, CivilDate(2026, 10, 4));
      expect(restored.enteredAt, DateTime.utc(2026, 10, 19));
      expect(restored.correctedAt, DateTime.utc(2026, 10, 20));
      expect(restored.toJson(), saved.toJson());
    },
  );
  test('all source date precisions roundtrip without fabricating instants', () {
    final dates = [
      SupportingDate.unknown(originalText: 'Not supplied'),
      SupportingDate.partial(
        year: 2026,
        month: 10,
        originalText: 'October 2026',
      ),
      SupportingDate.day(CivilDate(2026, 10, 25), zoneId: 'Europe/London'),
      SupportingDate.exact(
        DateTime.utc(2026, 10, 25, 0, 30),
        zoneId: 'Europe/London',
        utcOffsetMinutes: 60,
        originalText: '01:30 +01:00',
      ),
    ];
    for (final date in dates) {
      expect(SupportingDate.fromJson(date.toJson()).toJson(), date.toJson());
    }
    expect(dates.take(3).every((d) => d.instant == null), isTrue);
    expect(
      () => SupportingDate.exact(
        DateTime(2026),
        zoneId: 'UTC',
        utcOffsetMinutes: 0,
      ),
      throwsArgumentError,
    );
  });
  test('file-first panel is truthful with no invented missing result', () {
    final saved = record(results: []);
    expect(saved.snapshot.results, isEmpty);
    expect(
      SupportingRevision.fromJson(saved.toJson()).snapshot.results,
      isEmpty,
    );
  });
  test('observations retain named BP pulse components without totals or required lab fields', () {
    final components = [
      result(id: 'systolic', metric: 'bp_systolic', text: '120', unit: 'mmHg'),
      result(id: 'diastolic', metric: 'bp_diastolic', text: '80', unit: 'mmHg'),
      result(id: 'pulse', metric: 'pulse', text: '0', unit: 'bpm'),
    ];
    final observation = ObservationSnapshot(
      id: SupportingRecordId(id: 'bp', personId: 'me'),
      title: 'Reported reading',
      measuredDate: SupportingDate.unknown(),
      provenance: SupportingProvenance(
        mode: SupportingProvenanceMode.manualObservation,
      ),
      components: components,
    );
    expect(
      SupportingSnapshot.fromJson(observation.toJson()).toJson(),
      observation.toJson(),
    );
    expect(observation.reportDate.precision, SupportingDatePrecision.unknown);
    expect(() => observation.components.add(result()), throwsUnsupportedError);
  });
  test('wrong-person context and exact attachment provenance reject', () {
    final id = SupportingRecordId(id: 'panel', personId: 'me');
    expect(
      () => LabPanelSnapshot(
        id: id,
        title: 'Panel',
        collectionDate: SupportingDate.unknown(),
        reportDate: SupportingDate.unknown(),
        provenance: provenance(),
        results: [],
        contextLinks: [
          SupportingContextLink(
            id: 'item',
            personId: 'other',
            kind: SupportingContextKind.item,
          ),
        ],
      ),
      throwsArgumentError,
    );
    final source = SupportingProvenance(
      mode: SupportingProvenanceMode.manualTranscription,
      sourceReferences: [
        SupportingSourceReference(
          id: 'file',
          personId: 'other',
          version: 2,
          contentVersionId: 'exact_content',
          kind: SupportingSourceKind.attachment,
        ),
      ],
    );
    expect(() => record(source: source), throwsArgumentError);
  });
  test('attachment source content version and source text survive', () {
    final source = SupportingSourceReference(
      id: 'file',
      personId: 'me',
      version: 2,
      contentVersionId: 'immutable_content',
      kind: SupportingSourceKind.attachment,
      originalText: 'Lab original',
    );
    expect(
      SupportingSourceReference.fromJson(source.toJson()).toJson(),
      source.toJson(),
    );
  });
  test(
    'custom identity and saved names are independent from later metric labels',
    () {
      final metric = SupportingMetric(
        id: 'custom',
        personId: 'me',
        kind: SupportingMetricKind.lab,
        name: 'New display name',
        revision: 2,
      );
      final row = result(metric: metric.id);
      expect(row.markerName, 'Saved marker');
      expect(row.originalMarkerText, 'Original marker name');
      expect(
        SupportingMetric.fromJson(metric.toJson()).name,
        'New display name',
      );
    },
  );
  test('panel result bound accepts1000 and rejects1001 without truncation', () {
    final rows = [for (var i = 0; i < 1000; i++) result(id: 'r$i')];
    expect(record(results: rows).snapshot.results, hasLength(1000));
    expect(
      () => record(
        results: [
          ...rows,
          result(id: 'overflow'),
        ],
      ),
      throwsA(isA<SupportingLimitException>()),
    );
    expect(() => record(results: [result(), result()]), throwsArgumentError);
  });
  test('observation and source snapshots are immutable and empty observations reject', () {
    final rows = [result()];
    final saved = record(results: rows);
    rows.clear();
    expect(saved.snapshot.results, hasLength(1));
    expect(() => saved.snapshot.results.clear(), throwsUnsupportedError);
    expect(
      () => ObservationSnapshot(
        id: SupportingRecordId(id: 'note', personId: 'me'),
        title: 'Note',
        measuredDate: SupportingDate.unknown(),
        provenance: provenance(),
        components: [],
      ),
      throwsArgumentError,
    );
    final note = ObservationSnapshot(
      id: SupportingRecordId(id: 'note', personId: 'me'),
      title: 'Note',
      measuredDate: SupportingDate.unknown(),
      provenance: SupportingProvenance(
        mode: SupportingProvenanceMode.manualObservation,
      ),
      components: const [],
      notes: 'Source note only',
    );
    expect(note.results, isEmpty);
    expect(note.notes, 'Source note only');
    expect(
      () => SupportingProvenance(
        mode: SupportingProvenanceMode.manualTranscription,
        sourceReferences: [
          SupportingSourceReference(
            id: 'file',
            personId: 'me',
            version: 1,
            kind: SupportingSourceKind.attachment,
            contentVersionId: 'v1',
          ),
          SupportingSourceReference(
            id: 'file',
            personId: 'me',
            version: 1,
            kind: SupportingSourceKind.attachment,
            contentVersionId: 'v1',
          ),
        ],
      ),
      throwsArgumentError,
    );
    expect(
      () => SupportingRecordId(id: '../escape', personId: 'me'),
      throwsA(isA<Exception>()),
    );
  });
}
