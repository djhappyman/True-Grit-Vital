import '../attachments.dart' show attachmentIdentity;
import 'supporting_date.dart';
import 'supporting_value.dart';

enum SupportingRecordKind { labPanel, observation }

enum SupportingMetricKind { lab, observation }

enum SupportingProvenanceMode { manualTranscription, manualObservation }

enum SupportingSourceKind { report, attachment }

enum SupportingContextKind { item, event }

final class SupportingLimits {
  static const maxResults = 1000;
  static const maxTrendRows = 10000;
  static const defaultPageSize = 25;
  static const maxPageSize = 50;
}

final class SupportingLimitException implements Exception {
  const SupportingLimitException(this.code);
  final String code;
  @override
  String toString() => 'SupportingLimitException($code)';
}

final class SupportingRecordId {
  SupportingRecordId({required this.id, required this.personId}) {
    attachmentIdentity(id);
    attachmentIdentity(personId);
  }
  final String id, personId;
  Map<String, Object?> toJson() => {'id': id, 'personId': personId};
  factory SupportingRecordId.fromJson(Map<String, dynamic> json) =>
      SupportingRecordId(
        id: json['id'] as String,
        personId: json['personId'] as String,
      );
  @override
  bool operator ==(Object other) =>
      other is SupportingRecordId &&
      other.id == id &&
      other.personId == personId;
  @override
  int get hashCode => Object.hash(id, personId);
}

final class SupportingMetric {
  SupportingMetric({
    required this.id,
    required this.personId,
    required this.kind,
    required this.name,
    this.revision = 1,
  }) {
    supportingText(id, 'metric_id');
    supportingText(personId, 'metric_person');
    supportingText(name, 'metric_name');
    if (revision < 1) throw ArgumentError('metric_revision');
  }
  final String id, personId, name;
  final SupportingMetricKind kind;
  final int revision;
  Map<String, Object?> toJson() => {
    'id': id,
    'personId': personId,
    'kind': kind.name,
    'name': name,
    'revision': revision,
  };
  factory SupportingMetric.fromJson(Map<String, dynamic> j) => SupportingMetric(
    id: j['id'] as String,
    personId: j['personId'] as String,
    kind: SupportingMetricKind.values.byName(j['kind'] as String),
    name: j['name'] as String,
    revision: j['revision'] as int,
  );
}

final class SupportingSourceReference {
  SupportingSourceReference({
    required this.id,
    required this.personId,
    required this.version,
    required this.kind,
    this.originalText,
    this.contentVersionId,
  }) {
    supportingText(id, 'source_id');
    supportingText(personId, 'source_person');
    if (version < 1) throw ArgumentError('source_version');
    supportingOptionalText(originalText, 'source_text');
    supportingOptionalText(
      contentVersionId,
      'source_content_version',
      max: 512,
    );
  }
  final String id, personId;
  final int version;
  final SupportingSourceKind kind;
  final String? originalText, contentVersionId;
  Map<String, Object?> toJson() => {
    'id': id,
    'personId': personId,
    'version': version,
    'kind': kind.name,
    'originalText': originalText,
    'contentVersionId': contentVersionId,
  };
  factory SupportingSourceReference.fromJson(Map<String, dynamic> j) =>
      SupportingSourceReference(
        id: j['id'] as String,
        personId: j['personId'] as String,
        version: j['version'] as int,
        kind: SupportingSourceKind.values.byName(j['kind'] as String),
        originalText: j['originalText'] as String?,
        contentVersionId: j['contentVersionId'] as String?,
      );
}

/// Identities are explicit, never derived by fuzzy matching source names.
final class SupportingProvenance {
  SupportingProvenance({
    required this.mode,
    this.laboratoryId,
    this.laboratoryName,
    this.methodId,
    this.methodText,
    this.specimenId,
    this.specimenText,
    this.sourceText,
    this.recordedBy,
    Iterable<SupportingSourceReference> sourceReferences = const [],
  }) : sourceReferences = List.unmodifiable(sourceReferences) {
    for (final value in [laboratoryId, methodId, specimenId]) {
      supportingOptionalText(value, 'provenance_identity', max: 512);
    }
    for (final value in [
      laboratoryName,
      methodText,
      specimenText,
      sourceText,
      recordedBy,
    ]) {
      supportingOptionalText(value, 'provenance_text');
    }
    if (this.sourceReferences.length > 100) {
      throw const SupportingLimitException('source_references');
    }
    final seen = <String>{};
    for (final source in this.sourceReferences) {
      final key = [
        source.id,
        source.personId,
        source.kind.name,
        source.version,
        source.contentVersionId,
      ].join('\u0000');
      if (!seen.add(key)) throw ArgumentError('supporting_source_duplicate');
    }
  }
  final SupportingProvenanceMode mode;
  final String? laboratoryId,
      laboratoryName,
      methodId,
      methodText,
      specimenId,
      specimenText,
      sourceText,
      recordedBy;
  final List<SupportingSourceReference> sourceReferences;
  Map<String, Object?> toJson() => {
    'mode': mode.name,
    'laboratoryId': laboratoryId,
    'laboratoryName': laboratoryName,
    'methodId': methodId,
    'methodText': methodText,
    'specimenId': specimenId,
    'specimenText': specimenText,
    'sourceText': sourceText,
    'recordedBy': recordedBy,
    'sourceReferences': [for (final s in sourceReferences) s.toJson()],
  };
  factory SupportingProvenance.fromJson(Map<String, dynamic> j) =>
      SupportingProvenance(
        mode: SupportingProvenanceMode.values.byName(j['mode'] as String),
        laboratoryId: j['laboratoryId'] as String?,
        laboratoryName: j['laboratoryName'] as String?,
        methodId: j['methodId'] as String?,
        methodText: j['methodText'] as String?,
        specimenId: j['specimenId'] as String?,
        specimenText: j['specimenText'] as String?,
        sourceText: j['sourceText'] as String?,
        recordedBy: j['recordedBy'] as String?,
        sourceReferences: [
          for (final s in j['sourceReferences'] as List)
            SupportingSourceReference.fromJson(_map(s)),
        ],
      );
}

final class SupportingContextLink {
  SupportingContextLink({
    required this.id,
    required this.personId,
    required this.kind,
  }) {
    supportingText(id, 'context_id');
    supportingText(personId, 'context_person');
  }
  final String id, personId;
  final SupportingContextKind kind;
  Map<String, Object?> toJson() => {
    'id': id,
    'personId': personId,
    'kind': kind.name,
  };
  factory SupportingContextLink.fromJson(Map<String, dynamic> j) =>
      SupportingContextLink(
        id: j['id'] as String,
        personId: j['personId'] as String,
        kind: SupportingContextKind.values.byName(j['kind'] as String),
      );
}

final class LabResultSnapshot {
  LabResultSnapshot({
    required this.id,
    required this.metricId,
    required this.markerName,
    required this.value,
    String? originalMarkerText,
    this.unit,
    this.referenceRange,
    this.sourceFlag,
    this.provenance,
  }) : originalMarkerText = originalMarkerText ?? markerName {
    supportingText(id, 'result_id');
    supportingText(metricId, 'result_metric');
    supportingText(markerName, 'result_name');
    supportingText(this.originalMarkerText, 'result_original_name', max: 8192);
    supportingOptionalText(unit, 'result_unit', max: 512);
    supportingOptionalText(sourceFlag, 'result_flag');
  }
  final String id, metricId, markerName, originalMarkerText;
  final SupportingValue value;
  final String? unit, sourceFlag;
  final SourceReferenceRange? referenceRange;

  /// A supplied override replaces provenance as a whole. Null identities in an
  /// override remain unknown; the parent cannot silently fill them back in.
  final SupportingProvenance? provenance;
  Map<String, Object?> toJson() => {
    'id': id,
    'metricId': metricId,
    'markerName': markerName,
    'originalMarkerText': originalMarkerText,
    'value': value.toJson(),
    'unit': unit,
    'referenceRange': referenceRange?.toJson(),
    'sourceFlag': sourceFlag,
    'provenance': provenance?.toJson(),
  };
  factory LabResultSnapshot.fromJson(Map<String, dynamic> j) =>
      LabResultSnapshot(
        id: j['id'] as String,
        metricId: j['metricId'] as String,
        markerName: j['markerName'] as String,
        originalMarkerText: j['originalMarkerText'] as String,
        value: SupportingValue.fromJson(_map(j['value'])),
        unit: j['unit'] as String?,
        referenceRange: j['referenceRange'] == null
            ? null
            : SourceReferenceRange.fromJson(_map(j['referenceRange'])),
        sourceFlag: j['sourceFlag'] as String?,
        provenance: j['provenance'] == null
            ? null
            : SupportingProvenance.fromJson(_map(j['provenance'])),
      );
}

sealed class SupportingSnapshot {
  SupportingSnapshot({
    required this.id,
    required this.title,
    required this.collectionDate,
    required this.reportDate,
    required this.provenance,
    required Iterable<LabResultSnapshot> results,
    this.notes,
    Iterable<SupportingContextLink> contextLinks = const [],
  }) : results = List.unmodifiable(results),
       contextLinks = List.unmodifiable(contextLinks) {
    supportingText(title, 'supporting_title');
    supportingOptionalText(notes, 'supporting_notes', max: 32768);
    if (this.results.length > SupportingLimits.maxResults) {
      throw const SupportingLimitException('panel_results');
    }
    if (this.results.map((r) => r.id).toSet().length != this.results.length) {
      throw ArgumentError('supporting_duplicate_result');
    }
    if (this.contextLinks.length > 100) {
      throw const SupportingLimitException('context_links');
    }
    for (final link in this.contextLinks) {
      if (link.personId != id.personId) {
        throw ArgumentError('supporting_context_owner');
      }
    }
    for (final p in [
      provenance,
      ...this.results
          .map((r) => r.provenance)
          .whereType<SupportingProvenance>(),
    ]) {
      for (final source in p.sourceReferences) {
        if (source.personId != id.personId) {
          throw ArgumentError('supporting_source_owner');
        }
      }
    }
  }
  final SupportingRecordId id;
  final String title;
  final SupportingDate collectionDate, reportDate;
  final SupportingProvenance provenance;
  final List<LabResultSnapshot> results;
  final String? notes;
  final List<SupportingContextLink> contextLinks;
  SupportingRecordKind get kind;
  Map<String, Object?> toJson() => {
    'kind': kind.name,
    'id': id.toJson(),
    'title': title,
    'collectionDate': collectionDate.toJson(),
    'reportDate': reportDate.toJson(),
    'provenance': provenance.toJson(),
    'results': [for (final r in results) r.toJson()],
    'notes': notes,
    'contextLinks': [for (final c in contextLinks) c.toJson()],
  };
  factory SupportingSnapshot.fromJson(Map<String, dynamic> j) =>
      switch (SupportingRecordKind.values.byName(j['kind'] as String)) {
        SupportingRecordKind.labPanel => LabPanelSnapshot.fromJson(j),
        SupportingRecordKind.observation => ObservationSnapshot.fromJson(j),
      };
}

final class LabPanelSnapshot extends SupportingSnapshot {
  LabPanelSnapshot({
    required super.id,
    required super.title,
    required super.collectionDate,
    required super.reportDate,
    required super.provenance,
    required super.results,
    super.notes,
    super.contextLinks,
  });
  @override
  SupportingRecordKind get kind => SupportingRecordKind.labPanel;
  factory LabPanelSnapshot.fromJson(Map<String, dynamic> j) => LabPanelSnapshot(
    id: SupportingRecordId.fromJson(_map(j['id'])),
    title: j['title'] as String,
    collectionDate: SupportingDate.fromJson(_map(j['collectionDate'])),
    reportDate: SupportingDate.fromJson(_map(j['reportDate'])),
    provenance: SupportingProvenance.fromJson(_map(j['provenance'])),
    results: [
      for (final r in j['results'] as List) LabResultSnapshot.fromJson(_map(r)),
    ],
    notes: j['notes'] as String?,
    contextLinks: [
      for (final c in j['contextLinks'] as List)
        SupportingContextLink.fromJson(_map(c)),
    ],
  );
}

final class ObservationSnapshot extends SupportingSnapshot {
  ObservationSnapshot({
    required super.id,
    required super.title,
    required SupportingDate measuredDate,
    required super.provenance,
    required Iterable<LabResultSnapshot> components,
    super.notes,
    super.contextLinks,
  }) : super(
         collectionDate: measuredDate,
         reportDate: SupportingDate.unknown(),
         results: components,
       ) {
    // A quick observation may be a note alone. It does not invent a value and
    // remains ineligible for a measurement trend.
    if (results.isEmpty && notes == null) {
      throw ArgumentError('observation_empty_components');
    }
  }
  SupportingDate get measuredDate => collectionDate;
  List<LabResultSnapshot> get components => results;
  @override
  SupportingRecordKind get kind => SupportingRecordKind.observation;
  factory ObservationSnapshot.fromJson(Map<String, dynamic> j) =>
      ObservationSnapshot(
        id: SupportingRecordId.fromJson(_map(j['id'])),
        title: j['title'] as String,
        measuredDate: SupportingDate.fromJson(_map(j['collectionDate'])),
        provenance: SupportingProvenance.fromJson(_map(j['provenance'])),
        components: [
          for (final r in j['results'] as List)
            LabResultSnapshot.fromJson(_map(r)),
        ],
        notes: j['notes'] as String?,
        contextLinks: [
          for (final c in j['contextLinks'] as List)
            SupportingContextLink.fromJson(_map(c)),
        ],
      );
}

final class SupportingRevision {
  SupportingRevision({
    required this.snapshot,
    required this.revision,
    required this.operationId,
    required this.enteredAt,
    required this.revisionEnteredAt,
    this.isVoided = false,
  }) {
    supportingText(operationId, 'supporting_operation');
    if (revision < 1 ||
        !enteredAt.isUtc ||
        !revisionEnteredAt.isUtc ||
        revisionEnteredAt.isBefore(enteredAt) ||
        revision == 1 && revisionEnteredAt != enteredAt) {
      throw ArgumentError('supporting_revision');
    }
  }
  final SupportingSnapshot snapshot;
  final int revision;
  final String operationId;
  final DateTime enteredAt, revisionEnteredAt;
  final bool isVoided;
  SupportingRecordId get id => snapshot.id;
  SupportingRecordKind get kind => snapshot.kind;
  DateTime? get correctedAt => revision == 1 ? null : revisionEnteredAt;
  Map<String, Object?> toJson() => {
    'snapshot': snapshot.toJson(),
    'revision': revision,
    'operationId': operationId,
    'enteredAt': enteredAt.microsecondsSinceEpoch,
    'revisionEnteredAt': revisionEnteredAt.microsecondsSinceEpoch,
    'isVoided': isVoided,
  };
  factory SupportingRevision.fromJson(Map<String, dynamic> j) =>
      SupportingRevision(
        snapshot: SupportingSnapshot.fromJson(_map(j['snapshot'])),
        revision: j['revision'] as int,
        operationId: j['operationId'] as String,
        enteredAt: DateTime.fromMicrosecondsSinceEpoch(
          j['enteredAt'] as int,
          isUtc: true,
        ),
        revisionEnteredAt: DateTime.fromMicrosecondsSinceEpoch(
          j['revisionEnteredAt'] as int,
          isUtc: true,
        ),
        isVoided: j['isVoided'] as bool,
      );
}

Map<String, dynamic> _map(Object? value) =>
    Map<String, dynamic>.from(value as Map);
