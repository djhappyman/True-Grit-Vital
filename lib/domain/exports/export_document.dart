import '../history/timeline_entry.dart';
import '../products/products.dart';
import '../records.dart';
import '../stock/stored_stock.dart';
import '../supporting/supporting.dart';
import 'export_selection.dart';

/// Current portable export schema. Change only with a documented semantics
/// change; readers treat an unknown version as unsupported.
const exportSchemaVersion = 2;

/// The exact container that supplied a recorded dose, when one was chosen.
/// Lot, expiry and capacity are the container's saved facts at capture time.
/// They never imply a verified product identity or a clinical source.
final class ExportStockSource {
  const ExportStockSource({
    required this.containerId,
    required this.label,
    required this.unit,
    this.lot,
    this.expiryDate,
    this.capacity,
  });
  final String containerId, label, unit;
  final String? lot;
  final CivilDate? expiryDate;
  final ExactAmount? capacity;

  Map<String, Object?> toJson() => {
    'containerId': containerId,
    'label': label,
    'unit': unit,
    'lot': lot,
    'expiryDate': expiryDate?.toString(),
    'capacityExact': capacity?.toString(),
    'capacityDecimal': capacity == null ? null : exactDecimal(capacity!),
  };
}

/// Exact decimal text only when the rational terminates within [maxPlaces].
///
/// Non-terminating values return null and remain available as numerator and
/// denominator. No rounded value is ever labelled exact.
String? exactDecimal(ExactAmount amount, {int maxPlaces = 12}) {
  if (maxPlaces < 0 || maxPlaces > 18) throw ArgumentError('decimal_places');
  var remainder = amount.denominator;
  var twos = 0, fives = 0;
  while (remainder % BigInt.two == BigInt.zero) {
    remainder ~/= BigInt.two;
    twos++;
  }
  while (remainder % BigInt.from(5) == BigInt.zero) {
    remainder ~/= BigInt.from(5);
    fives++;
  }
  if (remainder != BigInt.one) return null;
  final places = twos > fives ? twos : fives;
  if (places > maxPlaces) return null;
  final scale = BigInt.from(10).pow(places);
  final scaled = amount.numerator * scale ~/ amount.denominator;
  final negative = scaled.isNegative;
  final digits = scaled.abs().toString().padLeft(places + 1, '0');
  final whole = digits.substring(0, digits.length - places);
  final fraction = places == 0
      ? ''
      : digits
            .substring(digits.length - places)
            .replaceFirst(RegExp(r'0+$'), '');
  return '${negative ? '-' : ''}$whole${fraction.isEmpty ? '' : '.$fraction'}';
}

/// One immutable administration revision.
final class ExportDoseRevision {
  const ExportDoseRevision({
    required this.recordId,
    required this.itemId,
    required this.revision,
    required this.currentRevision,
    required this.itemName,
    required this.itemForm,
    required this.itemType,
    required this.primaryUnit,
    required this.enteredAmount,
    required this.enteredUnit,
    required this.actualAmount,
    required this.actualUnit,
    required this.actualAt,
    required this.enteredAt,
    required this.isVoided,
    required this.source,
    this.siteLabel,
    this.combinedActionId,
    this.catalogueSnapshot,
    this.productSnapshot,
    this.labelledStrength,
    this.replacement,
    this.itemInstructions,
    this.itemNotes,
    this.notes,
    this.contextTags = const [],
    this.stockSource,
  });

  factory ExportDoseRevision.fromRecord(
    UseRecord record, {
    required int currentRevision,
    String? itemInstructions,
    String? itemNotes,
    required bool includeNotes,
    ExportStockSource? stockSource,
  }) => ExportDoseRevision(
    recordId: record.id,
    itemId: record.itemId,
    revision: record.revision,
    currentRevision: currentRevision,
    itemName: record.name,
    itemForm: record.form,
    itemType: record.type,
    primaryUnit: record.unit,
    enteredAmount: record.originalEntry ?? record.enteredAmount,
    enteredUnit: record.originalUnit ?? record.unit,
    actualAmount: record.actualAmount,
    actualUnit: record.actualUnit,
    actualAt: record.actualAt,
    enteredAt: record.enteredAt,
    isVoided: record.isVoided,
    source: record.source,
    siteLabel: record.siteLabel,
    combinedActionId: record.combinedActionId,
    catalogueSnapshot: record.catalogueSnapshot,
    productSnapshot: record.product,
    labelledStrength: record.labelledStrength,
    replacement: record.replacement,
    itemInstructions: itemInstructions,
    itemNotes: itemNotes,
    notes: includeNotes ? record.notes : null,
    contextTags: record.contextTags,
    stockSource: stockSource,
  );

  final String recordId, itemId, itemName, itemForm, itemType, primaryUnit;
  final String enteredAmount, enteredUnit, actualUnit;
  final int revision, currentRevision;
  final ExactAmount actualAmount;
  final DateTime actualAt, enteredAt;
  final bool isVoided;
  final RecordSource source;
  final String? siteLabel, combinedActionId;
  final CatalogueSnapshot? catalogueSnapshot;
  final ProductAdministrationSnapshot? productSnapshot;
  final LabelledStrength? labelledStrength;
  final StockReplacement? replacement;
  final ExportStockSource? stockSource;
  final String? notes;
  final List<String> contextTags;

  /// Authored item detail. Both stay null unless private notes were selected
  /// for this export and the substance has saved text.
  final String? itemInstructions, itemNotes;

  bool get isCurrent => revision == currentRevision;
  DateTime? get correctedAt => revision == 1 ? null : enteredAt;

  /// The applied correction cannot be represented when its strength is unknown.
  bool get replacementUnresolved =>
      replacement != null &&
      ReplacementAmounts.calculate(
            entered: EnteredStockAmount(enteredAmount, enteredUnit),
            oldStrength: replacement!.oldStrength,
            newStrength: replacement!.newStrength,
            keep: replacement!.keep,
          ) ==
          null;

  Map<String, Object?> toJson() => {
    'recordId': recordId,
    'item': {
      'id': itemId,
      'name': itemName,
      'form': itemForm,
      'type': itemType,
      'primaryUnit': primaryUnit,
      'instructions': itemInstructions,
      'notes': itemNotes,
    },
    'revision': revision,
    'isCurrent': isCurrent,
    'isVoided': isVoided,
    'entered': {'amount': enteredAmount, 'unit': enteredUnit},
    'actual': {
      'amountExact': actualAmount.toString(),
      'amountDecimal': exactDecimal(actualAmount),
      'unit': actualUnit,
    },
    'actualAt': actualAt.toUtc().toIso8601String(),
    'enteredAt': enteredAt.toUtc().toIso8601String(),
    'correctedAt': correctedAt?.toUtc().toIso8601String(),
    'provenance': {
      'source': source.name,
      'site': siteLabel,
      'combinedActionId': combinedActionId,
      'catalogue': catalogueSnapshot?.toJson(),
      'product': productSnapshot?.toJson(),
      'labelledStrength': labelledStrength == null
          ? null
          : {
              'ingredientId': labelledStrength!.ingredientId,
              'label': labelledStrength!.label,
              'mgPerMlExact': labelledStrength!.mgPerMl?.toString(),
              'mgPerMlDecimal': labelledStrength!.mgPerMl == null
                  ? null
                  : exactDecimal(labelledStrength!.mgPerMl!),
            },
      'replacementKept': replacement?.keep == FixedReplacementAmount.milligrams
          ? 'mg'
          : replacement == null
          ? null
          : 'ml',
      'replacementResolved': !replacementUnresolved,
      'stockSource': stockSource?.toJson(),
    },
    'context': {'tags': contextTags, 'note': notes},
  };
}

/// One immutable supporting-record revision with private fields projected out.
final class ExportSupportingRevision {
  const ExportSupportingRevision({
    required this.snapshot,
    required this.revision,
    required this.currentRevision,
    required this.enteredAt,
    required this.revisionEnteredAt,
    required this.isVoided,
  });

  factory ExportSupportingRevision.fromRevision(
    SupportingRevision revision, {
    required int currentRevision,
    required bool includeNotes,
  }) => ExportSupportingRevision(
    snapshot: _privacySnapshot(revision.snapshot, includeNotes: includeNotes),
    revision: revision.revision,
    currentRevision: currentRevision,
    enteredAt: revision.enteredAt,
    revisionEnteredAt: revision.revisionEnteredAt,
    isVoided: revision.isVoided,
  );

  final SupportingSnapshot snapshot;
  final int revision, currentRevision;
  final DateTime enteredAt, revisionEnteredAt;
  final bool isVoided;

  String get recordId => snapshot.id.id;
  bool get isCurrent => revision == currentRevision;
  DateTime? get correctedAt => revision == 1 ? null : revisionEnteredAt;

  Map<String, Object?> toJson() => {
    'recordId': recordId,
    'revision': revision,
    'isCurrent': isCurrent,
    'isVoided': isVoided,
    'enteredAt': enteredAt.toUtc().toIso8601String(),
    'revisionEnteredAt': revisionEnteredAt.toUtc().toIso8601String(),
    'correctedAt': correctedAt?.toUtc().toIso8601String(),
    'record': snapshot.toJson(),
  };
}

/// A supporting record may carry private notes and internal attachment links.
/// Structured export keeps neither unless notes are explicitly selected; file
/// references are never included because no attachment bytes are exported.
SupportingSnapshot _privacySnapshot(
  SupportingSnapshot snapshot, {
  required bool includeNotes,
}) {
  final json = Map<String, dynamic>.from(snapshot.toJson());
  if (!includeNotes) json['notes'] = null;
  json['provenance'] = _withoutSources(json['provenance']);
  final results = json['results'];
  if (results is List) {
    json['results'] = [
      for (final result in results)
        if (result is Map)
          {
            ...Map<String, dynamic>.from(result),
            'provenance': _withoutSources(result['provenance']),
          }
        else
          result,
    ];
  }
  return SupportingSnapshot.fromJson(json);
}

Map<String, Object?>? _withoutSources(Object? value) {
  if (value is! Map) return null;
  return {...Map<String, Object?>.from(value), 'sourceReferences': <Object?>[]};
}

/// One immutable explicit skip action inside the selected range.
///
/// A skip is a saved fact, not a dose. It carries the action identity and the
/// planned instant, and never an amount, quantity or revision. [reason] is
/// free text and stays null unless private notes were selected.
final class ExportSkippedAction {
  const ExportSkippedAction({
    required this.actionId,
    required this.itemId,
    required this.itemName,
    required this.itemForm,
    required this.itemType,
    required this.occurredAt,
    required this.recordedAt,
    required this.dateOnly,
    required this.timeNeedsReview,
    required this.savedDate,
    required this.planZone,
    this.planName,
    this.reason,
  });

  factory ExportSkippedAction.fromEntry(
    SkippedTimelineEntry entry, {
    required String? itemName,
    required String? itemForm,
    required String? itemType,
    required bool includeNotes,
  }) => ExportSkippedAction(
    actionId: entry.action.id,
    itemId: entry.itemId,
    itemName: itemName ?? entry.context.itemName ?? entry.itemId,
    itemForm: itemForm ?? '',
    itemType: itemType ?? '',
    occurredAt: entry.occurredAt,
    recordedAt: entry.action.recordedAt,
    dateOnly: entry.dateOnly,
    timeNeedsReview: entry.timeNeedsReview,
    savedDate: entry.savedDate,
    planZone: entry.planZone,
    planName: entry.context.planName,
    reason: includeNotes ? entry.action.reason : null,
  );

  /// Saved daily action identity. Never a fabricated dose record id.
  final String actionId, itemId, itemName, itemForm, itemType;

  /// Planned instant, or the plan-zone day start for a date-only skip.
  final DateTime occurredAt;

  /// When the skip action itself was saved.
  final DateTime recordedAt;
  final bool dateOnly, timeNeedsReview;
  final CivilDate savedDate;
  final String planZone;
  final String? planName, reason;

  Map<String, Object?> toJson() => {
    'actionId': actionId,
    'item': {
      'id': itemId,
      'name': itemName,
      'form': itemForm,
      'type': itemType,
    },
    'occurredAt': occurredAt.toUtc().toIso8601String(),
    'recordedAt': recordedAt.toUtc().toIso8601String(),
    'dateOnly': dateOnly,
    'timeNeedsReview': timeNeedsReview,
    'savedDate': savedDate.toString(),
    'planZone': planZone,
    'planName': planName,
    'reason': reason,
  };
}

/// Truthful disclosure of the supporting records left out of a structured
/// export because their collection date is unknown or partial and therefore
/// not positionable inside the selected range.
///
/// Nothing about the omitted records' content reaches the export. A reached
/// counting bound reports [counted] false instead of a fabricated number.
final class ExportUndatedOmission {
  const ExportUndatedOmission.counted(int this.records)
    : assert(records >= 0),
      counted = true;
  const ExportUndatedOmission.uncounted() : records = null, counted = false;

  /// Number of omitted records, or null when they were not counted.
  final int? records;
  final bool counted;
}

/// One immutable capture of a selected person's records.
///
/// Reading happens in one database transaction. Formatting happens afterwards
/// from this value, so the reviewed preview and the saved file share one
/// artifact and no live query is repeated.
final class ExportDocument {
  ExportDocument({
    required this.selection,
    required this.generatedAt,
    required this.personName,
    required Iterable<ExportDoseRevision> doses,
    required Iterable<ExportSupportingRevision> supporting,
    Iterable<ExportSkippedAction> skipped = const [],
    this.undatedCollection,
    this.reportName,
    this.recordSchemaVersion = 23,
  }) : doses = List.unmodifiable(doses),
       supporting = List.unmodifiable(supporting),
       skipped = List.unmodifiable(skipped) {
    if (!generatedAt.isUtc) throw ArgumentError('generated_at_utc');
    if (!selection.includes(ExportContent.supporting) &&
        undatedCollection != null) {
      throw ArgumentError('export_omissions');
    }
    if (!selection.includes(ExportContent.doses) && skipped.isNotEmpty) {
      throw ArgumentError('export_skips');
    }
  }

  final ExportSelection selection;
  final DateTime generatedAt;
  final String personName;
  final String? reportName;
  final int recordSchemaVersion;
  final List<ExportDoseRevision> doses;
  final List<ExportSupportingRevision> supporting;
  final List<ExportSkippedAction> skipped;

  /// Set exactly when supporting content is selected. Discloses the records
  /// excluded for an unknown or partial collection date without their content.
  final ExportUndatedOmission? undatedCollection;

  int get doseRecords => doses.map((row) => row.recordId).toSet().length;
  int get skippedActions => skipped.length;
  int get supportingRecords =>
      supporting.map((row) => row.recordId).toSet().length;
  int get supportingResults =>
      supporting.fold(0, (total, row) => total + row.snapshot.results.length);

  Map<String, Object?> toJson() => {
    'schemaVersion': exportSchemaVersion,
    'generatedAt': generatedAt.toIso8601String(),
    'application': {
      'name': 'True Grit: Vital',
      'recordSchemaVersion': recordSchemaVersion,
    },
    'selection': {
      'person': {
        'id': selection.personId,
        'name': personName,
        'reportName': reportName,
      },
      'fromDay': selection.fromDay.toString(),
      'beforeDay': selection.beforeDay.toString(),
      'timeZone': selection.zoneId,
      'format': selection.format.name,
      'contents': [
        for (final content in ExportContent.values)
          if (selection.includes(content)) content.name,
      ],
      'notesIncluded': selection.includeNotes,
    },
    'semantics': _semantics,
    if (undatedCollection != null)
      'omissions': {
        'collectionDateUnknownOrPartial': {
          'records': undatedCollection!.records,
          'counted': undatedCollection!.counted,
        },
      },
    'doses': [for (final row in doses) row.toJson()],
    'skipped': [for (final row in skipped) row.toJson()],
    'supporting': [for (final row in supporting) row.toJson()],
  };
}

const _semantics = <String, String>{
  'quantities': 'amountExact is numerator/denominator. amountDecimal is an exact decimal only when it terminates within 12 places; otherwise it is null. No rounded value is labelled exact.',
  'units': 'Units are stored as entered. No unit conversion, rounding or inferred concentration is applied.',
  'times': 'Instants are ISO 8601 UTC. fromDay is inclusive and beforeDay is exclusive in selection.timeZone.',
  'provenance': 'source is unspecified, selfReported or recordedOnBehalf. Catalogue, product, strength and site values are immutable snapshots saved with the revision.',
  'corrections': 'Every saved revision is included. Revision 1 enteredAt is the original entry time. Later enteredAt values are correction times. isCurrent marks the revision used by the app.',
  'context': 'context.tags are neutral labels chosen by the person for the dose. context.note is null unless notesIncluded is true. Neither value is inferred from a substance, label or schedule.',
  'skipped': 'skipped lists explicit skip actions saved inside the selected range when doses content is selected. actionId is the saved daily action identity. occurredAt is the planned instant, or the plan-zone day start for a date-only skip; recordedAt is when the skip itself was saved. reason is null unless notesIncluded is true. A skip has no amount, quantity or revision, and its item values are current item metadata, never inferred content.',
  'stockSource': 'provenance.stockSource names the exact container saved with a dose when one was chosen. label, lot, expiryDate, capacityExact and unit are the container pack facts at capture time. capacityDecimal is exact only when it terminates within 12 places. These facts are descriptive and do not verify the physical product or its contents.',
  'supportingMetadata': 'Selected supporting records retain authored or source-printed result categories and manually transcribed accessionNumber/reportIdentifier. They are source metadata, not inferred clinical classifications. Private notes remain excluded unless notesIncluded is true. Internal file references remain excluded.',
  'privacy': 'Only the selected adult is exported. Supporting notes, authored substance instructions and notes, dose notes and skip reasons appear only when notesIncluded is true. Dose context tags are structured metadata chosen by the person and are always included. Skip facts and their action identity are always included. File attachments and their internal references are never included.',
  'omissions': 'Supporting records whose collection date is unknown or partial have no positionable date inside the selected range and are excluded. omissions.collectionDateUnknownOrPartial discloses how many were omitted, never their content. counted false means they exceeded the bounded counting window and records is null.',
};
