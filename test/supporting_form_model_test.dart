import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:true_grit_vital/domain/supporting/supporting.dart';
import 'package:true_grit_vital/features/supporting/supporting_form_model.dart';

void main() {
  SupportingFormModel model({
    bool observation = false,
    SupportingNumberFormat numberFormat = const SupportingNumberFormat(),
  }) => SupportingFormModel(
    id: 'panel',
    personId: 'adult',
    observation: observation,
    numberFormat: numberFormat,
  )..fields['title'] = 'Source report';
  Map<String, String> row(
    String value, {
    String kind = 'numeric',
    String qualifier = 'exact',
  }) => {
    'id': 'result',
    'metricId': 'metric',
    'marker': 'Marker',
    'originalMarker': 'Source marker',
    'value': value,
    'kind': kind,
    'qualifier': qualifier,
    'unit': 'original UNIT',
    'range': '< 7.0 source range',
    'flag': 'Source flag',
  };
  test('empty panel is truthful and unknown dates never become entry time', () {
    final s = model().snapshot();
    expect(s.results, isEmpty);
    expect(s.collectionDate.precision, SupportingDatePrecision.unknown);
    expect(s.reportDate.precision, SupportingDatePrecision.unknown);
  });
  test('observation requires a component or a note', () {
    expect(() => model(observation: true).snapshot(), throwsArgumentError);
    final noteOnly = model(observation: true)..fields['notes'] = 'Source note';
    final saved = noteOnly.snapshot();
    expect(saved.results, isEmpty);
    expect(saved.notes, 'Source note');
  });
  for (final value in ['-0', '+1.20e-3', '<0.01', '≤2', '>9', '>=4']) {
    test('preserves numeric source lexeme $value', () {
      final f = model()..rows.add(row(value));
      final s = f.snapshot();
      expect(s.results.single.value.originalText, value);
      expect(s.results.single.unit, 'original UNIT');
      expect(
        s.results.single.referenceRange!.originalText,
        '< 7.0 source range',
      );
    });
  }
  test('missing and qualitative remain distinct', () {
    final f = model(observation: true)..rows.add(row('', kind: 'missing'));
    expect(f.snapshot().results.single.value.kind, SupportingValueKind.missing);
    f.rows[0] = row('Not detected', kind: 'qualitative');
    expect(f.snapshot().results.single.value.originalText, 'Not detected');
  });
  test(
    'incomplete raw draft restores stable identities without domain coercion',
    () {
      final f = model()
        ..rows.add(row('1e-'))
        ..fields['collectionPrecision'] = 'partial'
        ..fields['collectionText'] = 'Autumn 2026';
      final encoded = f.encode();
      final restored = SupportingFormModel(
        id: 'other-new-form-id',
        personId: 'adult',
        observation: false,
      )..restore(Map<String, dynamic>.from(jsonDecode(encoded) as Map));
      expect(restored.id, 'panel');
      expect(restored.rows.single['value'], '1e-');
      expect(restored.get('collectionText'), 'Autumn 2026');
      expect(() => restored.snapshot(), throwsFormatException);
    },
  );
  test('draft cannot change person or kind', () {
    final raw = model().toJson();
    expect(
      () => SupportingFormModel(
        id: 'panel',
        personId: 'different',
        observation: false,
      ).restore(raw),
      throwsFormatException,
    );
    expect(
      () => SupportingFormModel(
        id: 'panel',
        personId: 'adult',
        observation: true,
      ).restore(raw),
      throwsFormatException,
    );
  });
  test('exact source offset and zone survive correction', () {
    final f = model()
      ..fields.addAll({
        'collectionPrecision': 'exact',
        'collectionText': '2026-10-25T01:30:00+01:00',
        'collectionZone': 'Europe/London',
        'reportPrecision': 'partial',
        'reportText': '2026-10',
      });
    final s = f.snapshot();
    expect(s.collectionDate.instant, DateTime.utc(2026, 10, 25, 0, 30));
    expect(s.collectionDate.utcOffsetMinutes, 60);
    expect(s.reportDate.precision, SupportingDatePrecision.partial);
    final restored = model()..load(s);
    expect(restored.snapshot().toJson(), s.toJson());
  });
  for (final text in [
    '2026-02-30T12:00:00Z',
    '2026-10-25T24:00:00Z',
    '2026-10-25T01:30:00',
    '2026-10-25T01:30:00+01:99',
  ]) {
    test('rejects normalised or unqualified exact date $text', () {
      final f = model()
        ..fields.addAll({
          'collectionPrecision': 'exact',
          'collectionText': text,
          'collectionZone': 'Europe/London',
        });
      expect(() => f.snapshot(), throwsA(anything));
    });
  }
  test('editing retains result-specific source metadata and parsed range', () {
    final p = SupportingProvenance(
      mode: SupportingProvenanceMode.manualTranscription,
      laboratoryId: 'lab',
      sourceReferences: [
        SupportingSourceReference(
          id: 'file',
          personId: 'adult',
          version: 3,
          kind: SupportingSourceKind.attachment,
          contentVersionId: 'content-v2',
        ),
      ],
    );
    final s = LabPanelSnapshot(
      id: SupportingRecordId(id: 'panel', personId: 'adult'),
      title: 'Source',
      collectionDate: SupportingDate.day(CivilDate(2026, 10, 19)),
      reportDate: SupportingDate.unknown(),
      provenance: p,
      results: [
        LabResultSnapshot(
          id: 'result',
          metricId: 'metric',
          markerName: 'Marker',
          value: SupportingValue.numeric('-0'),
          provenance: p,
          referenceRange: SourceReferenceRange(
            originalText: '0 to 1',
            lower: SupportingRangeBound(value: ExactAmount.zero),
          ),
        ),
      ],
    );
    final f = model()..load(s);
    final fresh = model()
      ..restore(Map<String, dynamic>.from(jsonDecode(f.encode()) as Map));
    expect(fresh.snapshot().toJson(), s.toJson());
  });
  test('locale decimal input keeps the typed source text and reopens', () {
    const format = SupportingNumberFormat(
      decimalSeparator: ',',
      groupSeparator: '.',
    );
    final f = model(numberFormat: format)..rows.add(row('1.000,5'));
    final s = f.snapshot();
    expect(s.results.single.value.originalText, '1.000,5');
    expect(s.results.single.value.exactAmount, parseSupportingNumber('1000.5'));
    final restored = model(numberFormat: format)
      ..restore(Map<String, dynamic>.from(jsonDecode(f.encode()) as Map));
    expect(restored.snapshot().toJson(), s.toJson());
  });
  test(
    'saved source references survive draft restore and reach the snapshot',
    () {
      final f = model()
        ..sourceReferences.add(
          SupportingSourceReference(
            id: 'file',
            personId: 'adult',
            version: 4,
            kind: SupportingSourceKind.attachment,
            contentVersionId: 'content-v3',
            originalText: 'Original report',
          ),
        );
      final restored = model()
        ..restore(Map<String, dynamic>.from(jsonDecode(f.encode()) as Map));
      expect(restored.sourceReferences, hasLength(1));
      final s = restored.snapshot();
      expect(s.provenance.sourceReferences.single.id, 'file');
      expect(s.provenance.sourceReferences.single.version, 4);
      expect(
        s.provenance.sourceReferences.single.contentVersionId,
        'content-v3',
      );
    },
  );
  test('an older draft without a source list keeps its captured sources', () {
    final raw = model().toJson();
    raw.remove('sourceReferences');
    raw['retainedProvenance'] = SupportingProvenance(
      mode: SupportingProvenanceMode.manualTranscription,
      sourceReferences: [
        SupportingSourceReference(
          id: 'legacy-file',
          personId: 'adult',
          version: 1,
          kind: SupportingSourceKind.attachment,
          contentVersionId: 'legacy-content',
        ),
      ],
    ).toJson();
    final restored = model()
      ..restore(Map<String, dynamic>.from(jsonDecode(jsonEncode(raw)) as Map));
    expect(restored.sourceReferences.single.id, 'legacy-file');
    expect(
      restored.snapshot().provenance.sourceReferences.single.contentVersionId,
      'legacy-content',
    );
  });
}
