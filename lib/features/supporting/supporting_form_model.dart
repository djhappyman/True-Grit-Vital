import 'dart:convert';

import '../../domain/supporting/supporting.dart';

String? supportingOptional(String value) => value.trim().isEmpty ? null : value;

/// Raw form values survive incomplete edits. Domain validation occurs on save.
class SupportingFormModel {
  SupportingFormModel({
    required this.id,
    required this.personId,
    required this.observation,
  });
  String id;
  final String personId;
  final bool observation;
  final Map<String, String> fields = {};
  final List<Map<String, String>> rows = [];
  List<SupportingContextLink> contextLinks = [];
  SupportingProvenance? retainedProvenance;
  final Map<String, LabResultSnapshot> retainedResults = {};
  final Map<String, SupportingDate> retainedDates = {};
  String get(String key) => fields[key] ?? '';
  Map<String, dynamic> toJson() => {
    'id': id,
    'personId': personId,
    'observation': observation,
    'fields': fields,
    'rows': rows,
    'contextLinks': [for (final c in contextLinks) c.toJson()],
    'retainedProvenance': retainedProvenance?.toJson(),
    'retainedDates': {
      for (final e in retainedDates.entries) e.key: e.value.toJson(),
    },
    'retainedResults': {
      for (final e in retainedResults.entries) e.key: e.value.toJson(),
    },
  };
  void restore(Map<String, dynamic> j) {
    if (j['personId'] != personId || j['observation'] != observation) {
      throw const FormatException('form_identity');
    }
    id = j['id'] as String;
    fields
      ..clear()
      ..addAll(Map<String, String>.from(j['fields'] as Map));
    rows
      ..clear()
      ..addAll([
        for (final r in j['rows'] as List) Map<String, String>.from(r as Map),
      ]);
    contextLinks = [
      for (final c in j['contextLinks'] as List)
        SupportingContextLink.fromJson(Map<String, dynamic>.from(c as Map)),
    ];
    retainedProvenance = j['retainedProvenance'] == null
        ? null
        : SupportingProvenance.fromJson(
            Map<String, dynamic>.from(j['retainedProvenance'] as Map),
          );
    retainedDates
      ..clear()
      ..addAll({
        for (final e in (j['retainedDates'] as Map? ?? {}).entries)
          e.key as String: SupportingDate.fromJson(
            Map<String, dynamic>.from(e.value as Map),
          ),
      });
    retainedResults
      ..clear()
      ..addAll({
        for (final e in (j['retainedResults'] as Map? ?? {}).entries)
          e.key as String: LabResultSnapshot.fromJson(
            Map<String, dynamic>.from(e.value as Map),
          ),
      });
  }

  String encode() => jsonEncode(toJson());
  void load(SupportingSnapshot s) {
    fields['title'] = s.title;
    fields['notes'] = s.notes ?? '';
    contextLinks = s.contextLinks;
    retainedProvenance = s.provenance;
    for (final e in {
      'collection': s.collectionDate,
      'report': s.reportDate,
    }.entries) {
      final d = e.value;
      retainedDates[e.key] = d;
      fields['${e.key}Precision'] = d.precision.name;
      fields['${e.key}Text'] =
          d.originalText ??
          d.civilDate?.toString() ??
          (d.instant == null ? '' : _exactSource(d));
      fields['${e.key}Zone'] = d.zoneId ?? '';
    }
    final p = s.provenance;
    fields.addAll({
      'lab': p.laboratoryName ?? '',
      'labId': p.laboratoryId ?? '',
      'method': p.methodText ?? '',
      'methodId': p.methodId ?? '',
      'specimen': p.specimenText ?? '',
      'specimenId': p.specimenId ?? '',
      'source': p.sourceText ?? '',
      'by': p.recordedBy ?? '',
    });
    rows.clear();
    retainedResults.clear();
    for (final r in s.results) {
      retainedResults[r.id] = r;
      rows.add({
        'id': r.id,
        'metricId': r.metricId,
        'marker': r.markerName,
        'originalMarker': r.originalMarkerText,
        'kind': r.value.kind.name,
        'value': r.value.originalText ?? '',
        'qualifier': r.value.qualifier.name,
        'unit': r.unit ?? '',
        'range': r.referenceRange?.originalText ?? '',
        'flag': r.sourceFlag ?? '',
      });
    }
  }

  static String _exactSource(SupportingDate d) {
    final offset = d.utcOffsetMinutes!;
    final local = d.instant!.add(Duration(minutes: offset));
    final clock = local.toIso8601String().replaceFirst(RegExp(r'Z$'), '');
    return '$clock${offset < 0 ? '-' : '+'}${(offset.abs() ~/ 60).toString().padLeft(2, '0')}:${(offset.abs() % 60).toString().padLeft(2, '0')}';
  }

  SupportingDate date(String key) {
    final retained = retainedDates[key];
    if (retained != null &&
        get('${key}Precision') == retained.precision.name &&
        get('${key}Text') ==
            (retained.originalText ??
                retained.civilDate?.toString() ??
                (retained.instant == null ? '' : _exactSource(retained))) &&
        get('${key}Zone') == (retained.zoneId ?? '')) {
      return retained;
    }
    final text = get('${key}Text'),
        zone = supportingOptional(get('${key}Zone'));
    return switch (get('${key}Precision')) {
      'day' => SupportingDate.day(
        CivilDate.parse(text),
        zoneId: zone,
        originalText: text,
      ),
      'exact' => _exact(text, zone),
      'partial' => SupportingDate.partial(
        originalText: text,
        year: RegExp(r'^\d{4}($|-)').hasMatch(text)
            ? int.tryParse(text.substring(0, 4))
            : null,
        month: RegExp(r'^\d{4}-\d{2}$').hasMatch(text)
            ? int.tryParse(text.substring(5))
            : null,
      ),
      _ => SupportingDate.unknown(originalText: supportingOptional(text)),
    };
  }

  SupportingDate _exact(String text, String? zone) {
    if (zone == null || !RegExp(r'(Z|[+-]\d{2}:\d{2})$').hasMatch(text)) {
      throw const FormatException('date_offset');
    }
    final source = RegExp(
      r'^(\d{4}-\d{2}-\d{2})T(\d{2}):(\d{2})(?::(\d{2})(?:\.\d{1,6})?)?(?:Z|[+-]\d{2}:\d{2})$',
    ).firstMatch(text);
    if (source == null ||
        int.parse(source[2]!) > 23 ||
        int.parse(source[3]!) > 59 ||
        int.parse(source[4] ?? '0') > 59) {
      throw const FormatException('date_clock');
    }
    CivilDate.parse(source[1]!);
    final match = RegExp(r'([+-])(\d{2}):(\d{2})$').firstMatch(text);
    if (match != null &&
        (int.parse(match[2]!) > 23 || int.parse(match[3]!) > 59)) {
      throw const FormatException('date_offset');
    }
    final offset = match == null
        ? 0
        : (int.parse(match[2]!) * 60 + int.parse(match[3]!)) *
              (match[1] == '-' ? -1 : 1);
    return SupportingDate.exact(
      DateTime.parse(text).toUtc(),
      zoneId: zone,
      utcOffsetMinutes: offset,
      originalText: text,
    );
  }

  SupportingSnapshot snapshot() {
    final p = SupportingProvenance(
      mode: observation
          ? SupportingProvenanceMode.manualObservation
          : SupportingProvenanceMode.manualTranscription,
      laboratoryId: supportingOptional(get('labId')),
      laboratoryName: supportingOptional(get('lab')),
      methodId: supportingOptional(get('methodId')),
      methodText: supportingOptional(get('method')),
      specimenId: supportingOptional(get('specimenId')),
      specimenText: supportingOptional(get('specimen')),
      sourceText: supportingOptional(get('source')),
      recordedBy: supportingOptional(get('by')),
      sourceReferences: retainedProvenance?.sourceReferences ?? const [],
    );
    final results = <LabResultSnapshot>[];
    for (final r in rows) {
      final old = retainedResults[r['id']];
      final value = switch (r['kind']) {
        'qualitative' => SupportingValue.qualitative(r['value'] ?? ''),
        'missing' => SupportingValue.missing(
          originalText: supportingOptional(r['value'] ?? ''),
        ),
        _ => SupportingValue.numeric(
          r['value'] ?? '',
          qualifier: SupportingQualifier.values.byName(
            r['qualifier'] ?? 'exact',
          ),
        ),
      };
      final range = supportingOptional(r['range'] ?? '');
      results.add(
        LabResultSnapshot(
          id: r['id']!,
          metricId: r['metricId']!,
          markerName: r['marker'] ?? '',
          originalMarkerText: supportingOptional(r['originalMarker'] ?? ''),
          value: value,
          unit: supportingOptional(r['unit'] ?? ''),
          referenceRange: range == null
              ? null
              : range == old?.referenceRange?.originalText
              ? old!.referenceRange
              : SourceReferenceRange(originalText: range),
          sourceFlag: supportingOptional(r['flag'] ?? ''),
          provenance: old?.provenance,
        ),
      );
    }
    final identity = SupportingRecordId(id: id, personId: personId);
    return observation
        ? ObservationSnapshot(
            id: identity,
            title: get('title'),
            measuredDate: date('collection'),
            provenance: p,
            components: results,
            notes: supportingOptional(get('notes')),
            contextLinks: contextLinks,
          )
        : LabPanelSnapshot(
            id: identity,
            title: get('title'),
            collectionDate: date('collection'),
            reportDate: date('report'),
            provenance: p,
            results: results,
            notes: supportingOptional(get('notes')),
            contextLinks: contextLinks,
          );
  }
}
