import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:true_grit_vital/domain/supporting/supporting.dart';
import 'package:true_grit_vital/features/supporting/screen_labs_latest.dart';
import 'package:true_grit_vital/features/supporting/supporting_form_model.dart';

SupportingRevision point(
  String id,
  int day, {
  String value = '1.25',
  String? category,
  String unit = 'mg/L',
  String lab = 'lab',
  String method = 'method',
  String specimen = 'serum',
  SupportingDate? date,
  bool voided = false,
  int revision = 1,
}) => SupportingRevision(
  snapshot: LabPanelSnapshot(
    id: SupportingRecordId(id: id, personId: 'me'),
    title: 'Source panel',
    collectionDate: date ?? SupportingDate.day(CivilDate(2026, 10, day)),
    reportDate: SupportingDate.unknown(),
    provenance: SupportingProvenance(
      mode: SupportingProvenanceMode.manualTranscription,
      laboratoryId: lab,
      methodId: method,
      specimenId: specimen,
      accessionNumber: 'ACC-001',
      reportIdentifier: 'REPORT/09',
    ),
    results: [
      LabResultSnapshot(
        id: 'result-$id',
        metricId: 'marker',
        markerName: 'Full marker name',
        value: SupportingValue.numeric(value),
        unit: unit,
        category: category,
      ),
    ],
  ),
  revision: revision,
  operationId: '$id-$revision',
  enteredAt: DateTime.utc(2026),
  revisionEnteredAt: DateTime.utc(2026),
  isVoided: voided,
);

SupportingEarlierComparison compare(
  SupportingRevision viewed,
  List<SupportingRevision> candidates, {
  bool limited = false,
}) => supportingEarlierComparison(
  viewed: viewed,
  result: viewed.snapshot.results.single,
  candidates: candidates,
  displayZone: 'UTC',
  windowLimited: limited,
);

void main() {
  test('categories keep authored text, order and one final unnamed group', () {
    final groups = groupSupportingCategories([
      'Z',
      '',
      'A',
      'Z',
      ' ',
    ], (v) => v);
    expect(groups.map((g) => g.label), ['Z', 'A', null]);
    expect(groups.first.values, ['Z', 'Z']);
    expect(groups.last.values, ['', ' ']);
  });
  test('category and exact source identifiers survive raw drafts and clear explicitly', () {
    final original = point('panel', 20, category: 'Source category').snapshot;
    final form = SupportingFormModel(
      id: 'panel',
      personId: 'me',
      observation: false,
    )..load(original);
    final restored = SupportingFormModel(
      id: 'unused',
      personId: 'me',
      observation: false,
    )..restore(jsonDecode(form.encode()) as Map<String, dynamic>);
    expect(restored.snapshot().toJson(), original.toJson());
    restored.fields['accession'] = '';
    restored.fields['reportId'] = '';
    restored.rows.single['category'] = '';
    final cleared = restored.snapshot();
    expect(cleared.provenance.accessionNumber, isNull);
    expect(cleared.provenance.reportIdentifier, isNull);
    expect(cleared.results.single.category, isNull);
    final old =
        jsonDecode(jsonEncode(original.toJson())) as Map<String, dynamic>;
    (old['provenance'] as Map).remove('accessionNumber');
    (old['provenance'] as Map).remove('reportIdentifier');
    ((old['results'] as List).single as Map).remove('category');
    expect(SupportingSnapshot.fromJson(old).provenance.accessionNumber, isNull);
    expect(SupportingSnapshot.fromJson(old).results.single.category, isNull);
  });
  test('category and identifiers enforce bounded source text', () {
    expect(() => point('panel', 20, category: 'a' * 129), throwsArgumentError);
    expect(
      () => SupportingProvenance(
        mode: SupportingProvenanceMode.manualTranscription,
        accessionNumber: 'a' * 257,
      ),
      throwsArgumentError,
    );
  });
  test('older viewed panel compares backwards, never to the latest panel or itself', () {
    final viewed = point('middle', 15, value: '2.0');
    final prior = point('old', 1, value: '1.25');
    final result = compare(viewed, [
      point('future', 20, value: '99'),
      viewed,
      prior,
    ]);
    expect(result.earlier!.record.id.id, 'old');
    expect(result.change, '+0.75');
    expect(compare(viewed, [viewed, point('same-day', 15)]).earlier, isNull);
  });
  test(
    'earlier exact clocks compare within a day, equal clocks stay ambiguous',
    () {
      SupportingDate at(int hour) => SupportingDate.exact(
        DateTime.utc(2026, 10, 20, hour),
        zoneId: 'UTC',
        utcOffsetMinutes: 0,
      );
      final viewed = point('new', 20, date: at(12));
      expect(compare(viewed, [point('prior', 20, date: at(8))]).found, isTrue);
      expect(
        compare(viewed, [point('equal', 20, date: at(12))]).found,
        isFalse,
      );
      expect(compare(viewed, [point('unknown-clock', 20)]).found, isFalse);
    },
  );
  test('units, laboratory, method, specimen and qualifiers never cross comparison identity', () {
    final viewed = point('new', 20);
    for (final earlier in [
      point('unit', 1, unit: 'g/L'),
      point('lab', 1, lab: 'elsewhere'),
      point('method', 1, method: 'other'),
      point('specimen', 1, specimen: 'plasma'),
      point('qualified', 1, value: '<1.0'),
      point('void', 1, voided: true),
      point('unknown', 1, date: SupportingDate.unknown()),
    ]) {
      expect(compare(viewed, [earlier]).found, isFalse, reason: earlier.id.id);
    }
    expect(
      compare(viewed, [], limited: true).status,
      SupportingEarlierStatus.truncated,
    );
    expect(
      compare(point('unknown', 1, date: SupportingDate.unknown()), []).status,
      SupportingEarlierStatus.incomplete,
    );
  });
  test(
    'current revisions and ambiguous prior dates are handled conservatively',
    () {
      final viewed = point('viewed', 20);
      expect(
        compare(viewed, [
          point('old', 1),
          point('old', 1, revision: 2, voided: true),
        ]).found,
        isFalse,
      );
      expect(
        compare(viewed, [point('a', 1), point('b', 1)]).status,
        SupportingEarlierStatus.incomplete,
      );
    },
  );
  test('sparkline uses real dates and breaks at qualified, incompatible and undated points', () {
    final projected = screenLabsProject([
      point('last', 20, value: '1.50'),
      point('qualified', 18, value: '<0.5'),
      point('middle', 15, value: '1.25'),
      point('other-lab', 8, lab: 'other'),
      point('first', 1, value: '1.00'),
    ], truncated: true);
    final series = projected.values.single.sparkline!;
    expect(series.segments.map((s) => s.length), [1, 1, 1]);
    expect(series.first!.day, CivilDate(2026, 10, 1));
    expect(series.latest!.day, CivilDate(2026, 10, 20));
    expect(series.pointCount, 3);
    expect(projected.truncated, isTrue);
    expect(
      screenLabsProject([
        point('one', 1),
      ], truncated: false).values.single.sparkline!.pointCount,
      1,
    );
  });
}
