import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:true_grit_vital/domain/exports/exports.dart';
import 'package:true_grit_vital/domain/records.dart';
import 'package:true_grit_vital/domain/scheduling/saved_plan_instruction.dart';
import 'package:true_grit_vital/domain/scheduling/schedule_requirement.dart';
import 'package:true_grit_vital/domain/stock/exact_amount.dart';
import 'package:true_grit_vital/domain/supporting/supporting.dart';

ExportSelection fhirSelection({
  bool includeNotes = false,
  List<ExportContent> contents = const [
    ExportContent.doses,
    ExportContent.supporting,
  ],
}) => ExportSelection(
  personId: meId,
  fromDay: CivilDate(2026, 10, 1),
  beforeDay: CivilDate(2026, 11, 1),
  zoneId: 'Europe/London',
  contents: contents,
  format: ExportFormat.fhir,
  includeNotes: includeNotes,
);

ExportDocument document({
  bool includeNotes = false,
  List<ExportDoseRevision> doses = const [],
  List<ExportSkippedAction> skipped = const [],
  List<ExportSupportingRevision> supporting = const [],
  ExportUndatedOmission? undatedCollection,
}) => ExportDocument(
  selection: fhirSelection(includeNotes: includeNotes),
  generatedAt: DateTime.utc(2026, 10, 20, 12),
  personName: 'Synthetic adult',
  doses: doses,
  skipped: skipped,
  supporting: supporting,
  undatedCollection: undatedCollection,
);

ExportDoseRevision dose({
  String recordId = 'dose-1',
  String itemId = 'item-1',
  String itemName = 'Synthetic tablet',
  String itemForm = 'Tablet',
  String itemType = 'Medicine',
  String entered = '2.5',
  String enteredUnit = 'tablet',
  ExactAmount? actualAmount,
  String? actualUnit,
  int revision = 1,
  int currentRevision = 1,
  bool isVoided = false,
  RecordSource source = RecordSource.selfReported,
  String? siteLabel,
  String? notes,
  String? itemNotes,
  String? itemInstructions,
  List<String> contextTags = const [],
  SavedPlanInstruction? planInstruction,
  DateTime? actualAt,
  DateTime? enteredAt,
  LabelledStrength? labelledStrength,
}) => ExportDoseRevision(
  recordId: recordId,
  itemId: itemId,
  revision: revision,
  currentRevision: currentRevision,
  itemName: itemName,
  itemForm: itemForm,
  itemType: itemType,
  primaryUnit: enteredUnit,
  enteredAmount: entered,
  enteredUnit: enteredUnit,
  actualAmount: actualAmount ?? ExactAmount.parseEntry(entered),
  actualUnit: actualUnit ?? enteredUnit,
  actualAt: actualAt ?? DateTime.utc(2026, 10, 5, 10),
  enteredAt: enteredAt ?? DateTime.utc(2026, 10, 5, 10, 2),
  isVoided: isVoided,
  source: source,
  siteLabel: siteLabel,
  notes: notes,
  itemNotes: itemNotes,
  itemInstructions: itemInstructions,
  contextTags: contextTags,
  planInstruction: planInstruction,
  labelledStrength: labelledStrength,
);

ExportSkippedAction skip({
  String actionId = 'skip-1',
  String itemId = 'item-1',
  String itemName = 'Synthetic tablet',
  String itemForm = 'Tablet',
  bool dateOnly = false,
  bool timeNeedsReview = false,
  String? reason,
  SavedPlanInstruction? planInstruction,
}) => ExportSkippedAction(
  actionId: actionId,
  itemId: itemId,
  itemName: itemName,
  itemForm: itemForm,
  itemType: 'Medicine',
  occurredAt: DateTime.utc(2026, 10, 6, 8),
  recordedAt: DateTime.utc(2026, 10, 6, 8, 5),
  dateOnly: dateOnly,
  timeNeedsReview: timeNeedsReview,
  savedDate: CivilDate(2026, 10, 6),
  planZone: 'Europe/London',
  reason: reason,
  planInstruction: planInstruction,
);

LabPanelSnapshot panel({
  String id = 'panel-1',
  String title = 'Synthetic panel',
  String? notes,
  SupportingDate? collectionDate,
  SupportingDate? reportDate,
  List<LabResultSnapshot>? results,
}) => LabPanelSnapshot(
  id: SupportingRecordId(id: id, personId: meId),
  title: title,
  collectionDate: collectionDate ?? SupportingDate.day(CivilDate(2026, 10, 2)),
  reportDate: reportDate ?? SupportingDate.day(CivilDate(2026, 10, 4)),
  provenance: SupportingProvenance(
    mode: SupportingProvenanceMode.manualTranscription,
    laboratoryName: 'Synthetic laboratory',
    specimenText: 'Blood',
    methodText: 'Synthetic method',
    accessionNumber: 'ACC-1',
    reportIdentifier: 'REP-1',
  ),
  results:
      results ??
      [
        LabResultSnapshot(
          id: 'result-1',
          metricId: 'metric-1',
          markerName: 'Marker',
          originalMarkerText: 'Source marker',
          value: SupportingValue.numeric('5.5'),
          unit: 'mmol/L',
          category: 'Chemistry',
          sourceFlag: 'H',
          referenceRange: SourceReferenceRange(
            originalText: '3.0-7.0',
            lower: SupportingRangeBound(value: ExactAmount.parseEntry('3')),
            upper: SupportingRangeBound(value: ExactAmount.parseEntry('7')),
            unit: 'mmol/L',
          ),
        ),
      ],
  notes: notes,
);

ObservationSnapshot observation({
  String id = 'observation-1',
  String title = 'Synthetic observation',
  String? notes,
  SupportingDate? measuredDate,
  List<LabResultSnapshot>? components,
}) => ObservationSnapshot(
  id: SupportingRecordId(id: id, personId: meId),
  title: title,
  measuredDate: measuredDate ?? SupportingDate.day(CivilDate(2026, 10, 3)),
  provenance: SupportingProvenance(
    mode: SupportingProvenanceMode.manualObservation,
    laboratoryName: 'Synthetic laboratory',
  ),
  components:
      components ??
      [
        LabResultSnapshot(
          id: 'component-1',
          metricId: 'metric-2',
          markerName: 'Component',
          originalMarkerText: 'Source component',
          value: SupportingValue.numeric('12'),
          unit: 'drop',
        ),
      ],
  notes: notes,
);

ExportSupportingRevision supportingRevision(
  SupportingSnapshot snapshot, {
  int revision = 1,
  int currentRevision = 1,
  bool isVoided = false,
}) => ExportSupportingRevision(
  snapshot: snapshot,
  revision: revision,
  currentRevision: currentRevision,
  enteredAt: DateTime.utc(2026, 10, 5, 9),
  revisionEnteredAt: DateTime.utc(2026, 10, 5, 9),
  isVoided: isVoided,
);

Map<String, Object?> bundleOf(ExportDocument value) =>
    jsonDecode(encodeFhirR4(value).json) as Map<String, Object?>;

List<Map<String, Object?>> resources(Map<String, Object?> bundle) => [
  for (final entry in bundle['entry'] as List)
    (entry as Map<String, dynamic>)['resource'] as Map<String, Object?>,
];

Map<String, Object?> patient(Map<String, Object?> bundle) =>
    resources(bundle).firstWhere((r) => r['resourceType'] == 'Patient');

List<Map<String, Object?>> statements(Map<String, Object?> bundle) => [
  for (final r in resources(bundle))
    if (r['resourceType'] == 'MedicationStatement') r,
];

List<Map<String, Object?>> observations(Map<String, Object?> bundle) => [
  for (final r in resources(bundle))
    if (r['resourceType'] == 'Observation') r,
];

Map<String, Object?> firstStatement(Map<String, Object?> bundle) =>
    statements(bundle).first;

String raw(ExportDocument value) => encodeFhirR4(value).json;

const _samplePath = String.fromEnvironment('VITAL_FHIR_SAMPLE');

void main() {
  test('original food and bedtime labels require notes consent in FHIR', () {
    const instruction = SavedPlanInstruction(
      planId: 'plan',
      versionId: 'old',
      text: '',
      requirements: ScheduleRequirement(
        food: FoodRequirement.withFood,
        atBedtime: true,
      ),
    );
    final doseRow = dose(planInstruction: instruction);
    final skipped = skip(planInstruction: instruction);
    final shared = bundleOf(
      document(includeNotes: true, doses: [doseRow], skipped: [skipped]),
    );
    final all = statements(shared);
    expect(
      ((all.first['dosage'] as List).single
          as Map<String, dynamic>)['patientInstruction'],
      'With food · At bedtime',
    );
    expect(
      ((all.last['note'] as List).single as Map<String, dynamic>)['text'],
      'With food · At bedtime',
    );
    expect(
      () => document(doses: [doseRow], skipped: [skipped]),
      throwsArgumentError,
    );
    final hidden = raw(document(doses: [dose()], skipped: [skip()]));
    expect(hidden, isNot(contains('With food')));
    expect(hidden, isNot(contains('At bedtime')));
  });

  test('writes a representative sample for external FHIR validation', () {
    if (_samplePath.isEmpty) return;
    final value = document(
      includeNotes: true,
      doses: [
        dose(
          recordId: 'dose-exact',
          entered: '1234567890.123456',
          actualAmount: ExactAmount(
            BigInt.parse('1234567890123456'),
            BigInt.from(1000000),
          ),
          contextTags: const ['With food'],
          siteLabel: 'Left thigh',
          notes: 'Synthetic note',
          planInstruction: const SavedPlanInstruction(
            planId: 'plan',
            versionId: 'v1',
            text: '',
            requirements: ScheduleRequirement(
              food: FoodRequirement.withFood,
              atBedtime: true,
            ),
          ),
          labelledStrength: LabelledStrength(
            ingredientId: 'ingredient-1',
            label: '500 mg/5 ml',
            mgPerMl: ExactAmount(BigInt.from(100)),
          ),
        ),
        dose(
          recordId: 'dose-third',
          entered: '1',
          actualAmount: ExactAmount(BigInt.one, BigInt.from(3)),
        ),
        dose(
          recordId: 'dose-void',
          revision: 1,
          currentRevision: 2,
          isVoided: true,
        ),
      ],
      skipped: [skip(dateOnly: true, timeNeedsReview: true)],
      supporting: [
        supportingRevision(panel(notes: 'Synthetic panel note')),
        supportingRevision(observation()),
      ],
    );
    final artifact = ExportArtifact.build(value);
    File(_samplePath)
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(utf8.decode(artifact.bytes));
  });

  test(
    'collection Bundle keeps a local Patient and resolves every reference',
    () {
      final value = document(
        doses: [dose()],
        skipped: [skip()],
        supporting: [
          supportingRevision(panel()),
          supportingRevision(observation()),
        ],
      );
      final bundle = bundleOf(value);
      expect(bundle['resourceType'], 'Bundle');
      expect(bundle['type'], 'collection');
      expect(bundle['timestamp'], '2026-10-20T12:00:00.000Z');

      final patientResource = patient(bundle);
      expect(patientResource['id'], 'patient');
      expect(patientResource, isNot(contains('birthDate')));
      expect(patientResource, isNot(contains('gender')));
      expect((patientResource['identifier'] as List).first, {
        'system': 'urn:vital:person',
        'value': meId,
      });

      final all = resources(bundle);
      final ids = <String>{};
      final fullUrls = <String>{};
      for (final resource in all) {
        expect(resource['resourceType'], isNot('MedicationAdministration'));
        final id = '${resource['resourceType']}/${resource['id']}';
        expect(ids.add(id), isTrue, reason: 'duplicate $id');
        final fullUrl =
            'urn:vital:resource:${resource['resourceType']}:${resource['id']}';
        expect(fullUrls.add(fullUrl), isTrue, reason: 'duplicate $fullUrl');
      }
      for (final reference in _references(all)) {
        expect(fullUrls, contains(reference), reason: 'unresolved $reference');
      }
      expect(
        all.where((r) => r['resourceType'] == 'Observation').length,
        greaterThanOrEqualTo(2),
      );
      expect(raw(value), isNot(contains('meta')));
      expect(raw(value), isNot(contains('profile')));
    },
  );

  test(
    'exact decimals stay exact and non-terminating quantities stay text',
    () {
      final exact = document(
        doses: [
          dose(
            entered: '1234567890.123456',
            actualAmount: ExactAmount(
              BigInt.parse('1234567890123456'),
              BigInt.from(1000000),
            ),
          ),
        ],
      );
      final text = raw(exact);
      expect(text, contains('"value": 1234567890.123456'));
      expect(text, isNot(contains('1234567890.123457')));
      expect(text, isNot(contains('1.234567890123456e')));

      final third = document(
        doses: [
          dose(
            entered: '1',
            actualAmount: ExactAmount(BigInt.one, BigInt.from(3)),
            actualUnit: 'tablet',
          ),
        ],
      );
      final thirdText = raw(third);
      expect(thirdText, contains('Recorded as 1/3 tablet.'));
      expect(thirdText, isNot(contains('0.333333')));
      expect(encodeFhirR4(third).summary.exactTextQuantities, 1);
    },
  );

  test('odd units remain literal text with no UCUM system or code', () {
    final value = document(
      doses: [dose(entered: '3', enteredUnit: 'drop')],
      supporting: [
        supportingRevision(
          observation(
            components: [
              LabResultSnapshot(
                id: 'component-odd',
                metricId: 'metric-odd',
                markerName: 'Odd marker',
                value: SupportingValue.numeric('2'),
                unit: 'scoop',
              ),
            ],
          ),
        ),
      ],
    );
    final text = raw(value);
    expect(text, contains('"unit": "drop"'));
    expect(text, contains('"unit": "scoop"'));
    expect(text, isNot(contains('"system": "http://unitsofmeasure.org"')));
    expect(text, isNot(contains('"code": "mg"')));
  });

  test('uncertain clock without a dateOnly flag stays a date', () {
    final bundle = bundleOf(document(skipped: [skip(timeNeedsReview: true)]));
    expect(firstStatement(bundle)['effectiveDateTime'], '2026-10-06');
  });

  test(
    'labelled strength stays factual text without inventing an ingredient',
    () {
      final value = document(
        doses: [
          dose(
            labelledStrength: LabelledStrength(
              ingredientId: 'local-item',
              label: '500 mg/5 ml',
              mgPerMl: ExactAmount(BigInt.from(100)),
            ),
          ),
        ],
      );
      final bundle = bundleOf(value);
      expect(
        resources(bundle)
            .where((r) => r['resourceType'] == 'Medication')
            .single,
        isNot(contains('ingredient')),
      );
      expect(raw(value), contains('Labelled strength: 500 mg/5 ml.'));
    },
  );

  test('date-only and uncertain skips never become midnight', () {
    final value = document(
      skipped: [
        skip(dateOnly: true, timeNeedsReview: true, reason: 'Felt unwell'),
      ],
    );
    final statement = firstStatement(bundleOf(value));
    expect(statement['status'], 'not-taken');
    expect(statement['effectiveDateTime'], '2026-10-06');
    expect(statement['effectiveDateTime'], isNot(contains('T00:00')));
    expect(statement, isNot(contains('dosage')));
    expect(
      (statement['note'] as List).map(
        (n) => (n as Map<String, dynamic>)['text'],
      ),
      contains('Planned time needs review'),
    );
    final summary = encodeFhirR4(value).summary;
    expect(summary.skippedStatements, 1);
    expect(summary.dateOnlyTimes, 1);
    expect(summary.uncertainTimes, 1);
  });

  test('corrections, voids and skips use truthful standard statuses', () {
    final value = document(
      doses: [
        dose(recordId: 'dose-a', revision: 1, currentRevision: 2),
        dose(recordId: 'dose-a', revision: 2, currentRevision: 2),
        dose(recordId: 'dose-b', isVoided: true),
      ],
      skipped: [skip()],
    );
    final rows = statements(bundleOf(value));
    expect(rows, hasLength(4));
    expect(rows[0]['status'], 'entered-in-error');
    expect(
      ((rows[0]['statusReason'] as List).first as Map<String, dynamic>)['text'],
      'Superseded by revision 2',
    );
    expect(rows[1]['status'], 'completed');
    expect(rows[2]['status'], 'entered-in-error');
    expect(
      ((rows[2]['statusReason'] as List).first as Map<String, dynamic>)['text'],
      'Voided record',
    );
    expect(rows[3]['status'], 'not-taken');
    final summary = encodeFhirR4(value).summary;
    expect(summary.supersededRevisions, 1);
    expect(summary.voidedRecords, 1);
  });

  test(
    'duplicate records keep unique resource ids and shared Medication ids',
    () {
      final value = document(
        doses: [
          dose(recordId: 'dose-1'),
          dose(recordId: 'dose-2'),
        ],
      );
      final bundle = bundleOf(value);
      final all = resources(bundle);
      final statementIds = [
        for (final s in all.where(
          (r) => r['resourceType'] == 'MedicationStatement',
        ))
          s['id'],
      ];
      expect(statementIds.toSet(), hasLength(2));
      final medicationRefs = {
        for (final s in all.where(
          (r) => r['resourceType'] == 'MedicationStatement',
        ))
          ((s['medicationReference'] as Map<String, dynamic>)['reference']
              as String),
      };
      expect(medicationRefs, hasLength(1));
      expect(raw(value), contains('"system": "urn:vital:dose"'));
      expect(raw(value), contains('"system": "urn:vital:dose-revision"'));
    },
  );

  test('empty authored text is omitted instead of an empty FHIR string', () {
    final value = document(
      includeNotes: true,
      doses: [
        dose(
          planInstruction: const SavedPlanInstruction(
            planId: 'plan-1',
            versionId: 'version-1',
            text: '',
          ),
        ),
      ],
      skipped: [
        skip(
          planInstruction: const SavedPlanInstruction(
            planId: 'plan-1',
            versionId: 'version-1',
            text: '',
          ),
        ),
      ],
    );
    final text = raw(value);
    expect(text, isNot(contains('"patientInstruction"')));
    expect(text, isNot(contains('"text": ""')));
  });

  test('privacy choices keep private text out and structured facts in', () {
    final private = document(
      doses: [
        dose(
          notes: 'Private dose note',
          itemNotes: 'Private item note',
          itemInstructions: 'Private instructions',
          contextTags: const ['With food'],
          siteLabel: 'Left thigh',
        ),
      ],
      skipped: [skip(reason: 'Private skip reason')],
      supporting: [supportingRevision(panel(notes: 'Private panel note'))],
    );
    final privateText = raw(private);
    expect(privateText, isNot(contains('Private dose note')));
    expect(privateText, isNot(contains('Private item note')));
    expect(privateText, isNot(contains('Private instructions')));
    expect(privateText, isNot(contains('Private plan instruction')));
    expect(privateText, isNot(contains('Private skip reason')));
    expect(privateText, isNot(contains('Private panel note')));
    expect(privateText, contains('With food'));
    expect(privateText, contains('Left thigh'));

    final shared = document(
      includeNotes: true,
      doses: [
        dose(
          notes: 'Private dose note',
          itemNotes: 'Private item note',
          itemInstructions: 'Private instructions',
          planInstruction: const SavedPlanInstruction(
            planId: 'plan-1',
            versionId: 'version-1',
            text: 'Private plan instruction',
          ),
        ),
      ],
      skipped: [
        skip(
          reason: 'Private skip reason',
          planInstruction: const SavedPlanInstruction(
            planId: 'plan-1',
            versionId: 'version-1',
            text: 'Private plan instruction',
          ),
        ),
      ],
      supporting: [supportingRevision(panel(notes: 'Private panel note'))],
    );
    final sharedText = raw(shared);
    for (final text in [
      'Private dose note',
      'Private item note',
      'Private instructions',
      'Private plan instruction',
      'Private skip reason',
      'Private panel note',
    ]) {
      expect(sharedText, contains(text));
    }
  });

  test('panel and quick observation map only recorded values and ranges', () {
    final value = document(
      supporting: [
        supportingRevision(panel()),
        supportingRevision(
          observation(
            components: [
              LabResultSnapshot(
                id: 'component-1',
                metricId: 'metric-2',
                markerName: 'Recorded',
                originalMarkerText: 'Recorded source',
                value: SupportingValue.numeric('12'),
                unit: 'drop',
              ),
              LabResultSnapshot(
                id: 'component-2',
                metricId: 'metric-3',
                markerName: 'Missing',
                value: SupportingValue.missing(originalText: 'Not reported'),
              ),
            ],
          ),
        ),
      ],
    );
    final all = observations(bundleOf(value));
    final panelParent = all.firstWhere(
      (r) => (r['code'] as Map<String, dynamic>)['text'] == 'Synthetic panel',
    );
    final members = panelParent['hasMember'] as List;
    expect(members, hasLength(1));
    final result = all.firstWhere(
      (r) => (r['code'] as Map<String, dynamic>)['text'] == 'Source marker',
    );
    expect((result['category'] as List).first, {'text': 'Chemistry'});
    expect((result['interpretation'] as List).first, {'text': 'H'});
    expect((result['valueQuantity'] as Map<String, dynamic>)['unit'], 'mmol/L');
    expect(
      ((result['referenceRange'] as List).first
          as Map<String, dynamic>)['text'],
      '3.0-7.0',
    );
    expect(result, isNot(contains('dataAbsentReason')));

    final quick = all.firstWhere(
      (r) =>
          (r['code'] as Map<String, dynamic>)['text'] ==
          'Synthetic observation',
    );
    final components = quick['component'] as List;
    expect(components, hasLength(2));
    final missing = components.firstWhere(
      (c) =>
          ((c as Map<String, dynamic>)['code']
              as Map<String, dynamic>)['text'] ==
          'Missing',
    );
    expect((missing as Map<String, dynamic>)['dataAbsentReason'], {
      'text': 'Not reported',
    });
    expect(missing, isNot(contains('valueString')));
  });

  test('official structural constraints hold for representative resources', () {
    final value = document(
      doses: [
        dose(),
        dose(isVoided: true, recordId: 'dose-2'),
      ],
      skipped: [skip(dateOnly: true)],
      supporting: [
        supportingRevision(panel()),
        supportingRevision(observation()),
      ],
    );
    final bundle = bundleOf(value);
    final all = resources(bundle);
    final statuses = {
      'MedicationStatement': {
        'active',
        'completed',
        'entered-in-error',
        'intended',
        'stopped',
        'on-hold',
        'unknown',
        'not-taken',
      },
      'Observation': {
        'registered',
        'preliminary',
        'final',
        'amended',
        'cancelled',
        'entered-in-error',
        'unknown',
      },
    };
    for (final resource in all) {
      final type = resource['resourceType'] as String;
      expect({
        'Patient',
        'Medication',
        'MedicationStatement',
        'Observation',
      }, contains(type));
      if (type != 'Patient' && type != 'Medication') {
        expect(statuses[type], contains(resource['status']));
      }
      if (type == 'Observation') {
        final hasValue = resource.keys.any((key) => key.startsWith('value'));
        final hasReason = resource.containsKey('dataAbsentReason');
        expect(hasValue && hasReason, isFalse, reason: 'obs-6');
      }
      if (type == 'Medication') {
        expect(resource['code'], isA<Map<String, dynamic>>());
      }
      if (type == 'MedicationStatement') {
        expect(resource['medicationReference'], isA<Map<String, dynamic>>());
        expect(resource['subject'], {
          'reference': 'urn:vital:resource:Patient:patient',
        });
      }
    }
    expect(all.first['resourceType'], 'Patient');
  });

  test(
    'cancel before encoding leaves no artifact and exact bytes are reused',
    () {
      final value = document(doses: [dose()]);
      final token = ExportCancellation()..cancel();
      expect(
        () => ExportArtifact.build(value, cancellation: token),
        throwsA(isA<ExportCancelled>()),
      );
      final artifact = ExportArtifact.build(value);
      expect(artifact.format, ExportFormat.fhir);
      expect(artifact.mimeType, 'application/fhir+json');
      expect(artifact.bytes, Uint8List.fromList(utf8.encode(raw(value))));
      expect(artifact.preview.fhir, isNotNull);
      expect(artifact.preview.sha256, artifact.sha256);
    },
  );
}

Iterable<String> _references(Iterable<Map<String, Object?>> resources) sync* {
  for (final resource in resources) {
    for (final value in resource.values) {
      yield* _referencesIn(value);
    }
  }
}

Iterable<String> _referencesIn(Object? value) sync* {
  if (value is Map) {
    final reference = value['reference'];
    if (reference is String) yield reference;
    for (final child in value.values) {
      yield* _referencesIn(child);
    }
  } else if (value is List) {
    for (final child in value) {
      yield* _referencesIn(child);
    }
  }
}
