import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;

import '../supporting/supporting.dart';
import 'export_document.dart';
import 'export_selection.dart';

/// Deterministic bytes for one reviewed export document.
///
/// JSON is pretty-printed with stable key order. CSV follows RFC 4180 quoting
/// and prefixes any cell that begins with a spreadsheet formula character.
Uint8List encodeExport(ExportDocument document) {
  final text = switch (document.selection.format) {
    ExportFormat.json => const JsonEncoder.withIndent(
      '  ',
    ).convert(document.toJson()),
    ExportFormat.csv => encodeExportCsv(document),
  };
  return Uint8List.fromList(utf8.encode(text));
}

/// Exact, locale-independent CSV. Numbers use a full stop; no thousands
/// separators or localised dates are emitted.
String encodeExportCsv(ExportDocument document) {
  final rows = <List<Object?>>[
    exportCsvHeader,
    for (final row in document.doses) _doseCsvRow(row),
    for (final row in document.supporting) ..._supportingCsvRows(row),
  ];
  for (var i = 0; i < rows.length; i++) {
    final row = rows[i];
    if (row.length != exportCsvHeader.length) {
      throw StateError(
        'export_csv_shape $i ${row.length}/${exportCsvHeader.length} ${row.first}',
      );
    }
  }
  return rows.map((row) => row.map(csvCell).join(',')).join('\r\n');
}

const exportCsvHeader = <String>[
  'record_type',
  'record_id',
  'revision',
  'is_current',
  'is_voided',
  'actual_at_utc',
  'entered_at_utc',
  'corrected_at_utc',
  'source',
  'item_id',
  'item_name',
  'item_form',
  'item_type',
  'primary_unit',
  'entered_amount',
  'entered_unit',
  'actual_amount_exact',
  'actual_amount_decimal',
  'actual_unit',
  'site',
  'combined_action_id',
  'catalogue_product_code',
  'catalogue_product_name',
  'catalogue_strength',
  'catalogue_source_id',
  'catalogue_licence',
  'product_label',
  'product_volume_exact',
  'product_volume_decimal',
  'strength_ingredient_id',
  'strength_label',
  'strength_mg_per_ml_exact',
  'replacement_kept',
  'replacement_resolved',
  'supporting_kind',
  'supporting_title',
  'collection_date',
  'report_date',
  'metric_id',
  'marker_name',
  'original_marker_text',
  'value_kind',
  'value_original_text',
  'value_qualifier',
  'value_exact',
  'value_decimal',
  'value_unit',
  'reference_range',
  'source_flag',
  'laboratory',
  'method',
  'specimen',
  'recorded_by',
  'notes',
];

List<Object?> _doseCsvRow(ExportDoseRevision row) {
  final catalogue = row.catalogueSnapshot?.product;
  final product = row.productSnapshot;
  final label = product?.label;
  return [
    'dose',
    row.recordId,
    row.revision,
    _boolean(row.isCurrent),
    _boolean(row.isVoided),
    row.actualAt.toUtc().toIso8601String(),
    row.enteredAt.toUtc().toIso8601String(),
    row.correctedAt?.toUtc().toIso8601String(),
    row.source.name,
    row.itemId,
    row.itemName,
    row.itemForm,
    row.itemType,
    row.primaryUnit,
    row.enteredAmount,
    row.enteredUnit,
    row.actualAmount.toString(),
    exactDecimal(row.actualAmount),
    row.actualUnit,
    row.siteLabel,
    row.combinedActionId,
    catalogue?.code,
    catalogue?.name,
    catalogue?.strength,
    row.catalogueSnapshot?.manifest.sourceId,
    row.catalogueSnapshot?.manifest.licence,
    label?.components
        .map(
          (component) =>
              '${component.name} ${component.concentrationText ?? ''} ${component.massUnit}/${component.volumeUnit}'
                  .trim(),
        )
        .join('; '),
    product?.volume.toString(),
    product == null ? null : exactDecimal(product.volume),
    row.labelledStrength?.ingredientId,
    row.labelledStrength?.label,
    row.labelledStrength?.mgPerMl?.toString(),
    row.replacement?.keep.name,
    _boolean(!row.replacementUnresolved),
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
  ];
}

List<List<Object?>> _supportingCsvRows(ExportSupportingRevision row) {
  final snapshot = row.snapshot;
  final base = <Object?>[
    'supporting',
    row.recordId,
    row.revision,
    _boolean(row.isCurrent),
    _boolean(row.isVoided),
    null,
    row.enteredAt.toUtc().toIso8601String(),
    row.correctedAt?.toUtc().toIso8601String(),
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    snapshot.kind.name,
    snapshot.title,
    _supportingDate(snapshot.collectionDate),
    _supportingDate(snapshot.reportDate),
  ];
  if (snapshot.results.isEmpty) {
    return [
      [...base, for (var i = 0; i < 15; i++) null, snapshot.notes],
    ];
  }
  return [
    for (final result in snapshot.results)
      [
        ...base,
        result.metricId,
        result.markerName,
        result.originalMarkerText,
        result.value.kind.name,
        result.value.originalText,
        result.value.qualifier.name,
        result.value.exactAmount?.toString(),
        result.value.exactAmount == null
            ? null
            : exactDecimal(result.value.exactAmount!),
        result.unit,
        result.referenceRange?.originalText,
        result.sourceFlag,
        (result.provenance ?? snapshot.provenance).laboratoryName,
        (result.provenance ?? snapshot.provenance).methodText,
        (result.provenance ?? snapshot.provenance).specimenText,
        (result.provenance ?? snapshot.provenance).recordedBy,
        snapshot.notes,
      ],
  ];
}

String _supportingDate(SupportingDate date) =>
    date.civilDate?.toString() ??
    date.instant?.toUtc().toIso8601String() ??
    date.originalText ??
    'unknown';

String _boolean(bool value) => value ? 'true' : 'false';

final _plainNegativeNumber = RegExp(
  r'^-?(0|[1-9][0-9]*)(\.[0-9]+)?$|^-[0-9]+/[0-9]+$',
);

/// Escapes one CSV cell and neutralises leading formula characters.
///
/// Spreadsheet applications may trim leading whitespace, so the first
/// non-space character is checked. A plain negative number or exact negative
/// rational keeps its numeric meaning; other cells beginning with a formula
/// character receive a literal apostrophe inside the quoted cell. The original
/// value remains visible to a reader.
String csvCell(Object? value) {
  var text = value == null ? '' : value.toString();
  final probe = text.trimLeft();
  if (probe.isNotEmpty &&
      '=+-@\t\r'.contains(probe[0]) &&
      !_plainNegativeNumber.hasMatch(text)) {
    text = "'$text";
  }
  if (text.contains('"') ||
      text.contains(',') ||
      text.contains('\n') ||
      text.contains('\r')) {
    text = '"${text.replaceAll('"', '""')}"';
  }
  return text;
}

/// One reviewed artifact. [preview] and any handoff consume these same bytes.
final class ExportArtifact {
  ExportArtifact._({
    required this.bytes,
    required this.sha256,
    required this.fileName,
    required this.document,
    required this.preview,
    required this.limits,
  });

  final Uint8List bytes;
  final String sha256;
  final String fileName;
  final ExportDocument document;
  final ExportPreview preview;
  final ExportLimits limits;

  int get byteCount => bytes.length;
  ExportFormat get format => document.selection.format;
  String get mimeType => format.mimeType;

  static ExportArtifact build(
    ExportDocument document, {
    ExportCancellation? cancellation,
  }) {
    cancellation?.throwIfCancelled();
    final bytes = encodeExport(document);
    cancellation?.throwIfCancelled();
    final limits = document.selection.limits;
    if (bytes.length > limits.maxBytes) {
      throw const ExportLimitException('export_bytes');
    }
    final digest = crypto.sha256.convert(bytes).toString();
    final day = document.generatedAt
        .toUtc()
        .toIso8601String()
        .substring(0, 10)
        .replaceAll('-', '');
    // Neutral by default: no person name, substance name or internal id.
    final fileName =
        'vital-export-$day-${digest.substring(0, 8)}.${document.selection.format.extension}';
    final preview = ExportPreview._from(document, bytes, digest, limits);
    return ExportArtifact._(
      bytes: bytes.asUnmodifiableView(),
      sha256: digest,
      fileName: fileName,
      document: document,
      preview: preview,
      limits: limits,
    );
  }
}

/// Review data derived from the same capture and bytes that a handoff receives.
final class ExportPreview {
  ExportPreview._from(
    ExportDocument document,
    Uint8List bytes,
    this.sha256,
    ExportLimits limits,
  ) : personName = document.personName,
      fromDay = document.selection.fromDay,
      beforeDay = document.selection.beforeDay,
      zoneId = document.selection.zoneId,
      format = document.selection.format,
      contents = document.selection.contents,
      notesIncluded = document.selection.includeNotes,
      doseRecords = document.doseRecords,
      doseRevisions = document.doses.length,
      supportingRecords = document.supportingRecords,
      supportingResults = document.supportingResults,
      byteCount = bytes.length,
      excerpt = _excerpt(bytes, limits.previewCharacters);

  final String personName, zoneId, sha256;
  final CivilDate fromDay, beforeDay;
  final ExportFormat format;
  final Set<ExportContent> contents;
  final bool notesIncluded;
  final int doseRecords,
      doseRevisions,
      supportingRecords,
      supportingResults,
      byteCount;
  final String excerpt;

  static String _excerpt(Uint8List bytes, int limit) {
    final text = utf8.decode(bytes, allowMalformed: true);
    if (text.length <= limit) return text;
    var cut = limit;
    // Never split a surrogate pair at the preview boundary.
    if (cut > 0 && _isHighSurrogate(text.codeUnitAt(cut - 1))) cut--;
    return text.substring(0, cut);
  }

  static bool _isHighSurrogate(int unit) => unit >= 0xD800 && unit <= 0xDBFF;
}
