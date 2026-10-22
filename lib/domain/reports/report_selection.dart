import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../scheduling/daily_plan.dart' show CivilDate;

/// Stable identifiers for report templates. R02 and R03 add their own values.
enum ReportTemplateId {
  r01SubstanceSummary('R01', 'Substance summary'),
  r02DetailedHistory('R02', 'Detailed history'),
  r03EventReview('R03', 'Event review');

  const ReportTemplateId(this.id, this.title);
  final String id, title;

  /// R03 renders one recorded event rather than a free date range.
  bool get requiresEvent => this == ReportTemplateId.r03EventReview;
}

final class ReportSelectionFailure implements Exception {
  const ReportSelectionFailure(this.code);
  final String code;
  @override
  String toString() => 'ReportSelectionFailure($code)';
}

/// Every input that changes the reviewed document must change this identity.
///
/// Private notes and attachments are explicit opt-ins. Empty [itemIds] means
/// every recorded item in the period; a non-empty set is an exact inclusion.
/// [eventId] scopes R03 to one recorded event. [includeSkipped] and
/// [includeUnrecorded] control R02 ledger rows only; R01 ignores them.
/// [includeStock] adds the chosen container facts captured with each dose. It
/// stays off by default and never infers a source from a balance.
final class ReportSelection {
  ReportSelection({
    this.template = ReportTemplateId.r01SubstanceSummary,
    required this.personId,
    required this.fromDate,
    required this.beforeDate,
    required this.displayZone,
    this.reportName,
    this.eventId,
    this.includeNotes = false,
    this.includeAttachments = false,
    this.includeSupporting = false,
    this.includeSkipped = true,
    this.includeUnrecorded = true,
    this.includeStock = false,
    Iterable<String> itemIds = const [],
  }) : itemIds = Set.unmodifiable(itemIds) {
    if (!RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(personId)) {
      throw const ReportSelectionFailure('report_person');
    }
    if (beforeDate.compareTo(fromDate) <= 0) {
      throw const ReportSelectionFailure('report_range');
    }
    if (displayZone.isEmpty || displayZone.length > 256) {
      throw const ReportSelectionFailure('report_zone');
    }
    if (reportName != null &&
        (reportName!.trim().isEmpty || reportName!.length > 120)) {
      throw const ReportSelectionFailure('report_name');
    }
    if (eventId != null &&
        !RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(eventId!)) {
      throw const ReportSelectionFailure('report_event');
    }
    if (this.itemIds.any(
      (id) => !RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(id),
    )) {
      throw const ReportSelectionFailure('report_item');
    }
  }
  final ReportTemplateId template;
  final String personId, displayZone;
  final String? reportName, eventId;
  final CivilDate fromDate, beforeDate;
  final bool includeNotes, includeAttachments, includeSupporting;
  final bool includeSkipped, includeUnrecorded, includeStock;
  final Set<String> itemIds;

  /// Half-open civil range. [beforeDate] is never included.
  bool includesDate(CivilDate date) =>
      date.compareTo(fromDate) >= 0 && date.compareTo(beforeDate) < 0;

  ReportSelection copyWith({
    ReportTemplateId? template,
    String? personId,
    CivilDate? fromDate,
    CivilDate? beforeDate,
    String? displayZone,
    String? reportName,
    bool clearReportName = false,
    String? eventId,
    bool clearEventId = false,
    bool? includeNotes,
    bool? includeAttachments,
    bool? includeSupporting,
    bool? includeSkipped,
    bool? includeUnrecorded,
    bool? includeStock,
    Iterable<String>? itemIds,
  }) => ReportSelection(
    template: template ?? this.template,
    personId: personId ?? this.personId,
    fromDate: fromDate ?? this.fromDate,
    beforeDate: beforeDate ?? this.beforeDate,
    displayZone: displayZone ?? this.displayZone,
    reportName: clearReportName ? null : reportName ?? this.reportName,
    eventId: clearEventId ? null : eventId ?? this.eventId,
    includeNotes: includeNotes ?? this.includeNotes,
    includeAttachments: includeAttachments ?? this.includeAttachments,
    includeSupporting: includeSupporting ?? this.includeSupporting,
    includeSkipped: includeSkipped ?? this.includeSkipped,
    includeUnrecorded: includeUnrecorded ?? this.includeUnrecorded,
    includeStock: includeStock ?? this.includeStock,
    itemIds: itemIds ?? this.itemIds,
  );

  Map<String, Object?> toJson() => {
    'version': 2,
    'template': template.id,
    'person': personId,
    'from': fromDate.toString(),
    'before': beforeDate.toString(),
    'zone': displayZone,
    'reportName': reportName,
    'event': eventId,
    'notes': includeNotes,
    'attachments': includeAttachments,
    'supporting': includeSupporting,
    'skipped': includeSkipped,
    'unrecorded': includeUnrecorded,
    // Off keeps the previous JSON shape, so a stored selection that predates
    // stock details keeps its identity and still decodes as false.
    if (includeStock) 'stock': true,
    'items': itemIds.toList()..sort(),
  };

  factory ReportSelection.fromJson(Map<String, dynamic> json) =>
      ReportSelection(
        template: ReportTemplateId.values.firstWhere(
          (value) => value.id == json['template'],
          orElse: () => throw const ReportSelectionFailure('report_template'),
        ),
        personId: json['person'] as String,
        fromDate: CivilDate.parse(json['from'] as String),
        beforeDate: CivilDate.parse(json['before'] as String),
        displayZone: json['zone'] as String,
        reportName: json['reportName'] as String?,
        eventId: json['event'] as String?,
        includeNotes: json['notes'] as bool? ?? false,
        includeAttachments: json['attachments'] as bool? ?? false,
        includeSupporting: json['supporting'] as bool? ?? false,
        includeSkipped: json['skipped'] as bool? ?? true,
        includeUnrecorded: json['unrecorded'] as bool? ?? true,
        includeStock: json['stock'] as bool? ?? false,
        itemIds: (json['items'] as List? ?? const []).cast<String>(),
      );

  String get identity =>
      sha256.convert(utf8.encode(jsonEncode(toJson()))).toString();

  @override
  bool operator ==(Object other) =>
      other is ReportSelection && other.identity == identity;

  @override
  int get hashCode => identity.hashCode;
}

/// Captured at the moment the reviewed document is built.
///
/// The document is not a live feed: the same captured snapshot and template
/// version produce the same artifact.
final class ReportCutoff {
  ReportCutoff({
    required this.generatedAt,
    required this.datasetGeneration,
    required this.personRevision,
    required this.schemaVersion,
  }) {
    if (!generatedAt.isUtc ||
        datasetGeneration.isEmpty ||
        personRevision < 1 ||
        schemaVersion < 1) {
      throw const ReportSelectionFailure('report_cutoff');
    }
  }
  final DateTime generatedAt;
  final String datasetGeneration;
  final int personRevision, schemaVersion;

  Map<String, Object?> toJson() => {
    'generatedAt': generatedAt.toIso8601String(),
    'dataset': datasetGeneration,
    'personRevision': personRevision,
    'schemaVersion': schemaVersion,
  };
}

/// A report may be cancelled during source capture or rendering.
abstract interface class ReportCancellation {
  bool get isCancelled;
}

final class NeverCancelled implements ReportCancellation {
  const NeverCancelled();
  @override
  bool get isCancelled => false;
}

final class ReportCancelled implements Exception {
  const ReportCancelled();
}
