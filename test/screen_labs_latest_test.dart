import 'package:flutter_test/flutter_test.dart';
import 'package:true_grit_vital/app/supporting.dart';
import 'package:true_grit_vital/features/supporting/screen_labs_latest.dart';

SupportingDate civilDay(int dayOfMonth) =>
    SupportingDate.day(CivilDate(2026, 10, dayOfMonth));

SupportingProvenance source({
  String laboratoryId = 'lab-a',
  String methodId = 'method-a',
  String specimenId = 'specimen-a',
}) => SupportingProvenance(
  mode: SupportingProvenanceMode.manualTranscription,
  laboratoryId: laboratoryId,
  laboratoryName: 'Source laboratory',
  methodId: methodId,
  methodText: 'Method A',
  specimenId: specimenId,
  specimenText: 'Serum',
);

LabResultSnapshot result(
  String id, {
  required String metric,
  required String name,
  String? value,
  String? text,
  String? unit = 'mg/L',
  String? originalText,
  SourceReferenceRange? range,
  String? flag,
}) => LabResultSnapshot(
  id: id,
  metricId: metric,
  markerName: name,
  originalMarkerText: originalText ?? name,
  value: value != null
      ? SupportingValue.numeric(value)
      : text != null
      ? SupportingValue.qualitative(text)
      : SupportingValue.missing(),
  unit: unit,
  referenceRange: range,
  sourceFlag: flag,
);

SupportingRevision revision(
  String id,
  int day, {
  required List<LabResultSnapshot> results,
  String title = 'Source panel',
  SupportingProvenance? provenance,
  List<SupportingContextLink> links = const [],
}) => SupportingRevision(
  snapshot: LabPanelSnapshot(
    id: SupportingRecordId(id: id, personId: 'me'),
    title: title,
    collectionDate: civilDay(day),
    reportDate: civilDay(day + 1),
    provenance: provenance ?? source(),
    results: results,
    contextLinks: links,
  ),
  revision: 1,
  operationId: 'operation-$id',
  enteredAt: DateTime.utc(2026, 10, day, 8),
  revisionEnteredAt: DateTime.utc(2026, 10, day, 8),
);

void main() {
  test('newest value wins and a comparable previous value is kept', () {
    final latest = screenLabsProject([
      revision(
        'new',
        19,
        results: [
          result(
            'new-vitamin',
            metric: 'vitamin',
            name: 'Vitamin D',
            value: '58.4',
            unit: 'ng/mL',
          ),
          result('new-crp', metric: 'crp', name: 'hs-CRP', value: '0.45'),
        ],
      ),
      revision(
        'old',
        1,
        results: [
          result(
            'old-vitamin',
            metric: 'vitamin',
            name: 'Vitamin D',
            value: '32.0',
            unit: 'ng/mL',
          ),
          result('old-crp', metric: 'crp', name: 'hs-CRP', value: '0.55'),
        ],
      ),
    ], truncated: false);

    expect(latest.recordCount, 2);
    expect(latest.truncated, isFalse);
    expect(latest.markersTruncated, isFalse);
    expect(latest.values.map((value) => value.metricId), ['vitamin', 'crp']);
    expect(latest.values.first.result.value.originalText, '58.4');
    expect(latest.values.first.previousResult?.value.originalText, '32.0');
    expect(
      screenLabsChange(
        latest.values.first.result.value.exactAmount!,
        latest.values.first.previousResult!.value.exactAmount!,
      ),
      '+26.4',
    );
  });

  test('a newer missing result stays unknown instead of falling back', () {
    final latest = screenLabsProject([
      revision(
        'new',
        19,
        results: [
          result(
            'new-missing',
            metric: 'vitamin',
            name: 'Vitamin D',
            value: null,
            unit: null,
          ),
        ],
      ),
      revision(
        'old',
        1,
        results: [
          result(
            'old-value',
            metric: 'vitamin',
            name: 'Vitamin D',
            value: '32.0',
            unit: 'ng/mL',
          ),
        ],
      ),
    ], truncated: false);

    final value = latest.values.single;
    expect(value.result.value.kind, SupportingValueKind.missing);
    expect(value.result.unit, isNull);
    expect(value.previousResult, isNull);
  });

  test('a missing unit is never compared with a unit-bearing older value', () {
    final latest = screenLabsProject([
      revision(
        'new',
        19,
        results: [
          result(
            'new',
            metric: 'crp',
            name: 'hs-CRP',
            value: '0.45',
            unit: null,
          ),
        ],
      ),
      revision(
        'old',
        1,
        results: [
          result(
            'old',
            metric: 'crp',
            name: 'hs-CRP',
            value: '0.55',
            unit: 'mg/L',
          ),
        ],
      ),
    ], truncated: false);

    expect(latest.values.single.result.unit, isNull);
    expect(latest.values.single.previousResult, isNull);
  });

  test('different laboratory or method details block a comparison', () {
    final latest = screenLabsProject([
      revision(
        'new',
        19,
        provenance: source(methodId: 'method-b'),
        results: [result('new', metric: 'crp', name: 'hs-CRP', value: '0.45')],
      ),
      revision(
        'old',
        1,
        results: [result('old', metric: 'crp', name: 'hs-CRP', value: '0.55')],
      ),
    ], truncated: false);

    expect(latest.values.single.previousResult, isNull);
  });

  test('qualified values are not compared as exact measurements', () {
    final latest = screenLabsProject([
      revision(
        'new',
        19,
        results: [
          LabResultSnapshot(
            id: 'new',
            metricId: 'crp',
            markerName: 'hs-CRP',
            value: SupportingValue.numeric('<0.45'),
            unit: 'mg/L',
          ),
        ],
      ),
      revision(
        'old',
        1,
        results: [result('old', metric: 'crp', name: 'hs-CRP', value: '0.55')],
      ),
    ], truncated: false);

    expect(latest.values.single.previousResult, isNull);
  });

  test('the marker window is bounded and reports truncation', () {
    final latest = screenLabsProject(
      [
        revision(
          'new',
          19,
          results: [
            result('a', metric: 'a', name: 'A', value: '1'),
            result('b', metric: 'b', name: 'B', value: '2'),
            result('c', metric: 'c', name: 'C', value: '3'),
          ],
        ),
      ],
      truncated: true,
      markerLimit: 2,
    );

    expect(latest.values.map((value) => value.metricId), ['a', 'b']);
    expect(latest.markersTruncated, isTrue);
    expect(latest.truncated, isTrue);
  });

  test('change keeps exact short decimals and refuses repeating fractions', () {
    expect(
      screenLabsChange(
        ExactAmount(BigInt.from(584), BigInt.from(10)),
        ExactAmount(BigInt.from(320), BigInt.from(10)),
      ),
      '+26.4',
    );
    expect(
      screenLabsChange(
        ExactAmount(BigInt.one, BigInt.from(3)),
        ExactAmount.zero,
      ),
      isNull,
    );
    expect(screenLabsChange(ExactAmount.zero, ExactAmount.zero), '0');
    expect(
      screenLabsChange(ExactAmount(BigInt.one), ExactAmount(BigInt.from(2))),
      '-1',
    );
  });
}
