/// FHIR R4 (4.0.1) JSON encoding for one reviewed structured export.
///
/// This is a deliberately narrow mapping, not a profile claim:
///
/// * A self-contained `collection` Bundle.
/// * One local `Patient` with a name and local identifier, never an invented
///   birth date, sex, verification status or clinical identifier.
/// * Patient-reported medication use as `MedicationStatement`, never a
///   `MedicationAdministration` that would claim formal administration detail.
/// * A recorded dose uses `completed`; a voided or superseded revision uses
///   `entered-in-error`; an explicit skip uses `not-taken`.
/// * Supporting lab panels are a parent `Observation` with `hasMember` result
///   Observations. A quick observation uses `component` entries. No clinical
///   interpretation is inferred and no FHIR profile is claimed.
/// * Exact decimals are written as JSON numbers without passing through a
///   floating-point value. A non-terminating rational stays as exact text.
/// * A date-only value stays a date. It is never rewritten as midnight.
///
/// Units and codes are literal text only. No UCUM, LOINC, SNOMED or other
/// clinical code is invented. Local identifier systems are namespaced under
/// `urn:vital:` and are not clinical terminologies.
library;

import 'dart:convert';

import '../records.dart';
import '../scheduling/saved_plan_instruction.dart';
import '../stock/exact_amount.dart';
import '../supporting/supporting.dart';
import 'export_document.dart';

/// The FHIR release this encoder targets.
const fhirR4Version = '4.0.1';

/// The media type for a FHIR R4 JSON artifact.
const fhirR4MediaType = 'application/fhir+json';

/// Local, non-clinical identifier systems used by this export.
const _personSystem = 'urn:vital:person';
const _itemSystem = 'urn:vital:item';
const _doseSystem = 'urn:vital:dose';
const _doseRevisionSystem = 'urn:vital:dose-revision';
const _combinedActionSystem = 'urn:vital:combined-action';
const _skipSystem = 'urn:vital:skip';
const _supportingRecordSystem = 'urn:vital:supporting-record';
const _supportingResultSystem = 'urn:vital:supporting-result';
const _supportingRevisionSystem = 'urn:vital:supporting-revision';
const _accessionSystem = 'urn:vital:accession';
const _reportIdentifierSystem = 'urn:vital:report-identifier';

/// One encoded FHIR artifact and the review facts derived while encoding it.
final class FhirR4Export {
  const FhirR4Export._(this.json, this.summary);

  final String json;
  final FhirExportSummary summary;
}

/// Disclosure shown before Save. Counts are derived in the same pass that
/// builds the bytes, so the review cannot describe a different artifact.
final class FhirExportSummary {
  const FhirExportSummary({
    required this.medicationStatements,
    required this.skippedStatements,
    required this.medications,
    required this.observations,
    required this.dateOnlyTimes,
    required this.uncertainTimes,
    required this.voidedRecords,
    required this.supersededRevisions,
    required this.unresolvedReplacements,
    required this.exactTextQuantities,
    required this.missingValues,
    required this.reportDatesWithoutInstant,
    required this.notesIncluded,
  });

  final int medicationStatements;
  final int skippedStatements;
  final int medications;
  final int observations;
  final int dateOnlyTimes;
  final int uncertainTimes;
  final int voidedRecords;
  final int supersededRevisions;
  final int unresolvedReplacements;
  final int exactTextQuantities;
  final int missingValues;
  final int reportDatesWithoutInstant;
  final bool notesIncluded;
}

/// Encodes one [ExportDocument] as a self-contained FHIR R4 collection Bundle.
///
/// The returned JSON is deterministic for the same document. It is the exact
/// text used for the artifact bytes, preview and Save handoff.
FhirR4Export encodeFhirR4(ExportDocument document) {
  final builder = _BundleBuilder(document);
  final bundle = builder.build();
  return FhirR4Export._(_writeJson(bundle), builder.summary());
}

final class _Summary {
  int medicationStatements = 0;
  int skippedStatements = 0;
  int observations = 0;
  int dateOnlyTimes = 0;
  int uncertainTimes = 0;
  int voidedRecords = 0;
  int supersededRevisions = 0;
  int unresolvedReplacements = 0;
  int exactTextQuantities = 0;
  int missingValues = 0;
  int reportDatesWithoutInstant = 0;
}

final class _BundleBuilder {
  _BundleBuilder(this.document);
  final ExportDocument document;
  final _summary = _Summary();
  final _medications = <String, Map<String, Object?>>{};
  final _entries = <Map<String, Object?>>[];
  var _statementCounter = 0;
  var _observationCounter = 0;

  FhirExportSummary summary() => FhirExportSummary(
    medicationStatements: _summary.medicationStatements,
    skippedStatements: _summary.skippedStatements,
    medications: _medications.length,
    observations: _summary.observations,
    dateOnlyTimes: _summary.dateOnlyTimes,
    uncertainTimes: _summary.uncertainTimes,
    voidedRecords: _summary.voidedRecords,
    supersededRevisions: _summary.supersededRevisions,
    unresolvedReplacements: _summary.unresolvedReplacements,
    exactTextQuantities: _summary.exactTextQuantities,
    missingValues: _summary.missingValues,
    reportDatesWithoutInstant: _summary.reportDatesWithoutInstant,
    notesIncluded: document.selection.includeNotes,
  );

  Map<String, Object?> build() {
    _entries.add(_entry(_patient()));

    final statements = <Map<String, Object?>>[];
    for (final row in document.doses) {
      statements.add(_doseStatement(row));
    }
    for (final row in document.skipped) {
      statements.add(_skipStatement(row));
    }

    for (final medication in _medications.values) {
      _entries.add(_entry(medication));
    }
    for (final statement in statements) {
      _entries.add(_entry(statement));
    }
    for (final row in document.supporting) {
      for (final resource in _supporting(row)) {
        _entries.add(_entry(resource));
      }
    }

    return {
      'resourceType': 'Bundle',
      'type': 'collection',
      'timestamp': _instant(document.generatedAt),
      'entry': _entries,
    };
  }

  Map<String, Object?> _entry(Map<String, Object?> resource) => {
    'fullUrl': _fullUrl(
      resource['resourceType'] as String,
      resource['id'] as String,
    ),
    'resource': resource,
  };

  Map<String, Object?> _patient() => {
    'resourceType': 'Patient',
    'id': 'patient',
    'identifier': [
      {'system': _personSystem, 'value': document.selection.personId},
    ],
    if (document.personName.trim().isNotEmpty)
      'name': [
        {'text': document.personName},
      ],
  };

  Map<String, Object?> _doseStatement(ExportDoseRevision row) {
    _countRevision(voided: row.isVoided, current: row.isCurrent);
    if (row.replacement != null && row.replacementUnresolved) {
      _summary.unresolvedReplacements++;
    }
    final medication = _medicationForDose(row);
    final id = 'statement-${++_statementCounter}';
    _summary.medicationStatements++;
    final voided = row.isVoided;
    final superseded = !row.isCurrent;
    final status = voided || superseded ? 'entered-in-error' : 'completed';
    final notes = _noteEntries([
      if (document.selection.includeNotes) row.notes,
      if (document.selection.includeNotes) row.itemNotes,
    ]);
    return {
      'resourceType': 'MedicationStatement',
      'id': id,
      'identifier': _doseIdentifiers(row),
      'status': status,
      if (voided)
        'statusReason': [
          {'text': 'Voided record'},
        ]
      else if (superseded)
        'statusReason': [
          {'text': 'Superseded by revision ${row.currentRevision}'},
        ],
      'medicationReference': _reference(
        'Medication',
        medication['id'] as String,
      ),
      'subject': _reference('Patient', 'patient'),
      'effectiveDateTime': _instant(row.actualAt),
      'dateAsserted': _instant(row.enteredAt),
      if (row.source == RecordSource.selfReported)
        'informationSource': _reference('Patient', 'patient'),
      'dosage': [_dosage(row)],
      if (notes.isNotEmpty) 'note': notes,
    };
  }

  List<Map<String, Object?>> _doseIdentifiers(ExportDoseRevision row) => [
    {'system': _doseSystem, 'value': row.recordId},
    {'system': _doseRevisionSystem, 'value': '${row.revision}'},
    if (row.combinedActionId != null)
      {'system': _combinedActionSystem, 'value': row.combinedActionId!},
  ];

  Map<String, Object?> _dosage(ExportDoseRevision row) {
    final entered = _amountText(row.enteredAmount, row.enteredUnit);
    final actualDecimal = _exactDecimal(row.actualAmount);
    if (actualDecimal == null) _summary.exactTextQuantities++;
    final actual = _exactAmountText(row.actualAmount, row.actualUnit);
    final enteredValue = _tryEntered(row.enteredAmount);
    final differs =
        row.actualUnit != row.enteredUnit ||
        enteredValue == null ||
        row.actualAmount != enteredValue;

    final itemInstruction = document.selection.includeNotes
        ? _optionalText(row.itemInstructions)
        : null;
    final instructions = <Map<String, Object?>>[
      for (final tag in row.contextTags)
        if (_optionalText(tag) case final text?) {'text': text},
      if (itemInstruction case final text?) {'text': text},
    ];
    final patientInstruction = document.selection.includeNotes
        ? _planInstructionText(row.planInstruction)
        : null;
    final enteredDecimal = enteredValue == null
        ? null
        : _exactDecimal(enteredValue);
    if (enteredValue != null && enteredDecimal == null) {
      _summary.exactTextQuantities++;
    }
    return {
      'text': [
        differs ? 'Entered $entered. Recorded as $actual.' : entered,
        if (row.labelledStrength != null)
          'Labelled strength: ${row.labelledStrength!.label}.',
      ].join(' '),
      if (_optionalText(row.siteLabel) case final site?) 'site': {'text': site},
      if (instructions.isNotEmpty) 'additionalInstruction': instructions,
      'patientInstruction': ?patientInstruction,
      if (enteredDecimal != null)
        'doseAndRate': [
          {'doseQuantity': _quantity(enteredDecimal, row.enteredUnit)},
        ],
    };
  }

  Map<String, Object?> _skipStatement(ExportSkippedAction row) {
    final medication = _medicationForSkip(row);
    final id = 'statement-${++_statementCounter}';
    _summary.skippedStatements++;
    if (row.dateOnly || row.timeNeedsReview) _summary.dateOnlyTimes++;
    if (row.timeNeedsReview) _summary.uncertainTimes++;
    final notes = _noteEntries([
      if (row.timeNeedsReview) 'Planned time needs review',
      if (document.selection.includeNotes)
        _planInstructionText(row.planInstruction),
      if (document.selection.includeNotes) row.reason,
    ]);
    return {
      'resourceType': 'MedicationStatement',
      'id': id,
      'identifier': [
        {'system': _skipSystem, 'value': row.actionId},
      ],
      'status': 'not-taken',
      'medicationReference': _reference(
        'Medication',
        medication['id'] as String,
      ),
      'subject': _reference('Patient', 'patient'),
      'effectiveDateTime': row.dateOnly || row.timeNeedsReview
          ? row.savedDate.toString()
          : _instant(row.occurredAt),
      'dateAsserted': _instant(row.recordedAt),
      if (notes.isNotEmpty) 'note': notes,
    };
  }

  Map<String, Object?> _medicationForDose(ExportDoseRevision row) =>
      _medication(
        itemId: row.itemId,
        itemName: row.itemName,
        itemForm: row.itemForm,
        strength: row.labelledStrength,
      );

  Map<String, Object?> _medicationForSkip(ExportSkippedAction row) =>
      _medication(
        itemId: row.itemId,
        itemName: row.itemName,
        itemForm: row.itemForm,
        strength: null,
      );

  Map<String, Object?> _medication({
    required String itemId,
    required String itemName,
    required String itemForm,
    required LabelledStrength? strength,
  }) {
    final key = [
      itemId,
      itemName,
      itemForm,
      strength?.label ?? '',
    ].join('\u0000');
    final existing = _medications[key];
    if (existing != null) return existing;
    final id = 'medication-${_medications.length + 1}';
    final form = itemForm.trim();
    final resource = <String, Object?>{
      'resourceType': 'Medication',
      'id': id,
      'identifier': [
        {'system': _itemSystem, 'value': itemId},
      ],
      'code': {'text': itemName},
      if (form.isNotEmpty) 'form': {'text': itemForm},
    };
    _medications[key] = resource;
    return resource;
  }

  List<Map<String, Object?>> _supporting(ExportSupportingRevision row) {
    _countRevision(voided: row.isVoided, current: row.isCurrent);
    final snapshot = row.snapshot;
    if (snapshot is LabPanelSnapshot) {
      return _panel(row, snapshot);
    }
    if (snapshot is ObservationSnapshot) {
      return [_quickObservation(row, snapshot)];
    }
    // SupportingSnapshot is sealed; the fallback keeps a future subtype from
    // silently producing a partial resource.
    throw StateError('fhir_supporting_kind');
  }

  List<Map<String, Object?>> _panel(
    ExportSupportingRevision row,
    LabPanelSnapshot snapshot,
  ) {
    final status = _supportingStatus(row);
    final parentId = _nextObservationId();
    final results = [
      for (final result in snapshot.results)
        _panelResult(row, snapshot, result, status),
    ];
    final effective = _supportingDate(snapshot.collectionDate);
    if (snapshot.collectionDate.precision == SupportingDatePrecision.day) {
      _summary.dateOnlyTimes++;
    }
    final issued = _issued(snapshot.reportDate);
    if (issued == null && _reportDateNeedsDisclosure(snapshot.reportDate)) {
      _summary.reportDatesWithoutInstant++;
    }
    final notes = _noteEntries([
      if (effective == null) 'Collection date not recorded',
      if (document.selection.includeNotes) snapshot.notes,
    ]);
    final parent = <String, Object?>{
      'resourceType': 'Observation',
      'id': parentId,
      'identifier': _supportingIdentifiers(
        recordId: row.recordId,
        revision: row.revision,
        accession: snapshot.provenance.accessionNumber,
        reportIdentifier: snapshot.provenance.reportIdentifier,
      ),
      'status': status,
      'code': {'text': snapshot.title},
      'subject': _reference('Patient', 'patient'),
      'effectiveDateTime': ?effective,
      'issued': ?issued,
      if (snapshot.provenance.laboratoryName case final laboratory?)
        'performer': [
          {'display': laboratory},
        ],
      if (snapshot.provenance.specimenText case final specimen?)
        'specimen': {'display': specimen},
      if (snapshot.provenance.methodText case final method?)
        'method': {'text': method},
      if (results.isNotEmpty)
        'hasMember': [
          for (final result in results)
            _reference('Observation', result['id'] as String),
        ],
      if (notes.isNotEmpty) 'note': notes,
    };
    return [parent, ...results];
  }

  Map<String, Object?> _panelResult(
    ExportSupportingRevision row,
    LabPanelSnapshot snapshot,
    LabResultSnapshot result,
    String status,
  ) {
    final provenance = result.provenance ?? snapshot.provenance;
    final effective = _supportingDate(snapshot.collectionDate);
    return {
      'resourceType': 'Observation',
      'id': _nextObservationId(),
      'identifier': _supportingIdentifiers(
        recordId: row.recordId,
        revision: row.revision,
        resultId: result.id,
        accession: provenance.accessionNumber,
        reportIdentifier: provenance.reportIdentifier,
      ),
      'status': status,
      if (result.category case final category?)
        'category': [
          {'text': category},
        ],
      'code': {'text': result.originalMarkerText},
      'subject': _reference('Patient', 'patient'),
      'effectiveDateTime': ?effective,
      if (provenance.laboratoryName case final laboratory?)
        'performer': [
          {'display': laboratory},
        ],
      if (provenance.specimenText case final specimen?)
        'specimen': {'display': specimen},
      if (provenance.methodText case final method?) 'method': {'text': method},
      ..._valueFields(result.value, result.unit),
      if (result.referenceRange case final range?)
        'referenceRange': [_referenceRange(range)],
      if (result.sourceFlag case final flag?)
        'interpretation': [
          {'text': flag},
        ],
    };
  }

  Map<String, Object?> _quickObservation(
    ExportSupportingRevision row,
    ObservationSnapshot snapshot,
  ) {
    final status = _supportingStatus(row);
    final effective = _supportingDate(snapshot.measuredDate);
    if (snapshot.measuredDate.precision == SupportingDatePrecision.day) {
      _summary.dateOnlyTimes++;
    }
    if (_reportDateNeedsDisclosure(snapshot.reportDate)) {
      _summary.reportDatesWithoutInstant++;
    }
    final components = [
      for (final result in snapshot.results)
        {
          'code': {'text': result.originalMarkerText},
          ..._valueFields(result.value, result.unit),
          if (result.referenceRange case final range?)
            'referenceRange': [_referenceRange(range)],
          if (result.sourceFlag case final flag?)
            'interpretation': [
              {'text': flag},
            ],
        },
    ];
    final category = snapshot.results.length == 1
        ? snapshot.results.single.category
        : null;
    final provenance = snapshot.provenance;
    final notes = _noteEntries([
      if (effective == null) 'Collection date not recorded',
      if (document.selection.includeNotes) snapshot.notes,
    ]);
    return {
      'resourceType': 'Observation',
      'id': _nextObservationId(),
      'identifier': _supportingIdentifiers(
        recordId: row.recordId,
        revision: row.revision,
        accession: provenance.accessionNumber,
        reportIdentifier: provenance.reportIdentifier,
      ),
      'status': status,
      if (category case final category?)
        'category': [
          {'text': category},
        ],
      'code': {'text': snapshot.title},
      'subject': _reference('Patient', 'patient'),
      'effectiveDateTime': ?effective,
      if (provenance.laboratoryName case final laboratory?)
        'performer': [
          {'display': laboratory},
        ],
      if (provenance.specimenText case final specimen?)
        'specimen': {'display': specimen},
      if (provenance.methodText case final method?) 'method': {'text': method},
      if (components.isNotEmpty) 'component': components,
      if (components.isEmpty) 'dataAbsentReason': {'text': 'No value recorded'},
      if (notes.isNotEmpty) 'note': notes,
    };
  }

  Map<String, Object?> _valueFields(SupportingValue value, String? unit) {
    switch (value.kind) {
      case SupportingValueKind.numeric:
        final exact = value.exactAmount;
        final decimal = exact == null ? null : _exactDecimal(exact);
        if (decimal == null) {
          _summary.exactTextQuantities++;
          return {'valueString': value.originalText ?? value.parseText ?? ''};
        }
        return {
          'valueQuantity': _quantity(
            decimal,
            unit,
            comparator: _comparator(value.qualifier),
          ),
        };
      case SupportingValueKind.qualitative:
        return {'valueString': value.originalText ?? ''};
      case SupportingValueKind.missing:
        _summary.missingValues++;
        final text = value.originalText?.trim();
        return {
          'dataAbsentReason': {
            'text': text == null || text.isEmpty ? 'No value recorded' : text,
          },
        };
    }
  }

  Map<String, Object?> _referenceRange(SourceReferenceRange range) {
    final result = <String, Object?>{};
    final lower = range.lower;
    if (lower != null) {
      final low = _bound(lower, range.unit);
      if (low != null) result['low'] = low;
    }
    final upper = range.upper;
    if (upper != null) {
      final high = _bound(upper, range.unit);
      if (high != null) result['high'] = high;
    }
    if (range.applicabilityText case final applies?) {
      result['appliesTo'] = [
        {'text': applies},
      ];
    }
    result['text'] = range.originalText;
    return result;
  }

  Map<String, Object?>? _bound(SupportingRangeBound bound, String? unit) {
    final decimal = _exactDecimal(bound.value);
    if (decimal == null) {
      _summary.exactTextQuantities++;
      return null;
    }
    return _quantity(decimal, unit);
  }

  Map<String, Object?> _quantity(
    String decimal,
    String? unit, {
    String? comparator,
  }) => {
    'value': _JsonNumber(decimal),
    'comparator': ?comparator,
    if (unit != null && unit.trim().isNotEmpty) 'unit': unit,
  };

  List<Map<String, Object?>> _supportingIdentifiers({
    required String recordId,
    required int revision,
    String? resultId,
    String? accession,
    String? reportIdentifier,
  }) => [
    {'system': _supportingRecordSystem, 'value': recordId},
    {'system': _supportingRevisionSystem, 'value': '$revision'},
    if (resultId != null)
      {'system': _supportingResultSystem, 'value': resultId},
    if (accession != null) {'system': _accessionSystem, 'value': accession},
    if (reportIdentifier != null)
      {'system': _reportIdentifierSystem, 'value': reportIdentifier},
  ];

  String _nextObservationId() {
    _summary.observations++;
    return 'observation-${++_observationCounter}';
  }

  String _supportingStatus(ExportSupportingRevision row) {
    if (row.isVoided || !row.isCurrent) return 'entered-in-error';
    if (row.revision > 1) return 'amended';
    return 'final';
  }

  void _countRevision({required bool voided, required bool current}) {
    if (voided) {
      _summary.voidedRecords++;
    } else if (!current) {
      _summary.supersededRevisions++;
    }
  }

  String? _supportingDate(SupportingDate date) => switch (date.precision) {
    SupportingDatePrecision.exact => _instant(date.instant!),
    SupportingDatePrecision.day => date.civilDate!.toString(),
    SupportingDatePrecision.unknown || SupportingDatePrecision.partial => null,
  };

  String? _issued(SupportingDate date) =>
      date.precision == SupportingDatePrecision.exact
      ? _instant(date.instant!)
      : null;

  bool _reportDateNeedsDisclosure(SupportingDate date) =>
      date.precision == SupportingDatePrecision.day ||
      date.precision == SupportingDatePrecision.partial;
}

List<Map<String, Object?>> _noteEntries(Iterable<String?> texts) => [
  for (final text in texts)
    if (_optionalText(text) case final note?) {'text': note},
];

String? _optionalText(String? value) {
  if (value == null || value.trim().isEmpty) return null;
  return value;
}

String _fullUrl(String type, String id) => 'urn:vital:resource:$type:$id';

Map<String, Object?> _reference(String type, String id) => {
  'reference': _fullUrl(type, id),
};

String? _planInstructionText(SavedPlanInstruction? value) {
  if (value == null) return null;
  final lines = [
    ?_optionalText(value.text),
    if (value.requirements?.isNotEmpty == true)
      value.requirements!.reportSummary,
  ];
  return lines.isEmpty ? null : lines.join('\n');
}

String _instant(DateTime value) => value.toUtc().toIso8601String();

String _amountText(String amount, String unit) =>
    '${amount.trim()} ${unit.trim()}'.trim();

String _exactAmountText(ExactAmount amount, String unit) {
  final text = _exactDecimal(amount) ?? amount.toString();
  return '${text.trim()} ${unit.trim()}'.trim();
}

String? _exactDecimal(ExactAmount amount) =>
    exactDecimal(amount, maxPlaces: 18);

ExactAmount? _tryEntered(String text) {
  try {
    return ExactAmount.parseEntry(text);
  } catch (_) {
    return null;
  }
}

String? _comparator(SupportingQualifier qualifier) => switch (qualifier) {
  SupportingQualifier.exact => null,
  SupportingQualifier.lessThan => '<',
  SupportingQualifier.lessOrEqual => '<=',
  SupportingQualifier.greaterThan => '>',
  SupportingQualifier.greaterOrEqual => '>=',
};

/// A JSON number written from its exact decimal text.
final class _JsonNumber {
  const _JsonNumber(this.text);
  final String text;
}

/// Deterministic pretty JSON with exact decimal literals.
///
/// `JsonEncoder` would turn a decimal into a `double`, losing the source
/// precision this export must preserve. Scalars are the only place a number
/// enters the tree; all dates, identifiers and units remain JSON strings.
String _writeJson(Object? value) {
  final out = StringBuffer();
  _writeValue(out, value, 0);
  return out.toString();
}

void _writeValue(StringBuffer out, Object? value, int depth) {
  switch (value) {
    case null:
      out.write('null');
    case final String text:
      out.write(jsonEncode(text));
    case final bool flag:
      out.write(flag ? 'true' : 'false');
    case final int number:
      out.write(number);
    case final _JsonNumber number:
      out.write(number.text);
    case final List<Object?> list:
      if (list.isEmpty) {
        out.write('[]');
        return;
      }
      out.write('[\n');
      for (var i = 0; i < list.length; i++) {
        _indent(out, depth + 1);
        _writeValue(out, list[i], depth + 1);
        if (i < list.length - 1) out.write(',');
        out.write('\n');
      }
      _indent(out, depth);
      out.write(']');
    case final Map<Object?, Object?> map:
      if (map.isEmpty) {
        out.write('{}');
        return;
      }
      out.write('{\n');
      var i = 0;
      for (final entry in map.entries) {
        final key = entry.key;
        if (key is! String) throw StateError('fhir_json_key');
        _indent(out, depth + 1);
        out.write(jsonEncode(key));
        out.write(': ');
        _writeValue(out, entry.value, depth + 1);
        if (++i < map.length) out.write(',');
        out.write('\n');
      }
      _indent(out, depth);
      out.write('}');
    default:
      throw StateError('fhir_json_value ${value.runtimeType}');
  }
}

void _indent(StringBuffer out, int depth) => out.write('  ' * depth);
