import '../scheduling/daily_plan.dart';

/// Portable structured export formats owned by this feature.
enum ExportFormat { json, csv }

extension ExportFormatFile on ExportFormat {
  String get extension => switch (this) {
    ExportFormat.json => 'json',
    ExportFormat.csv => 'csv',
  };
  String get mimeType => switch (this) {
    ExportFormat.json => 'application/json',
    ExportFormat.csv => 'text/csv',
  };
}

/// Content families a person may deliberately include.
enum ExportContent { doses, supporting }

/// Hard bounds. A reached bound is a typed failure, never a silent cut.
final class ExportLimits {
  const ExportLimits({
    this.maxDays = 3660,
    this.maxDoseRecords = 10000,
    this.maxDoseRevisions = 20000,
    this.maxSkippedRecords = 5000,
    this.maxSupportingRecords = 2000,
    this.maxSupportingResults = 10000,
    this.maxBytes = 24 * 1024 * 1024,
    this.chunk = 300,
    this.previewCharacters = 4000,
  });

  /// Ten years keeps one export deliberate without suggesting a full archive.
  final int maxDays,
      maxDoseRecords,
      maxDoseRevisions,
      maxSkippedRecords,
      maxSupportingRecords,
      maxSupportingResults,
      maxBytes,
      chunk,
      previewCharacters;

  static const standard = ExportLimits();

  void check() {
    if (maxDays < 1 ||
        maxDoseRecords < 1 ||
        maxDoseRevisions < 1 ||
        maxSkippedRecords < 1 ||
        maxSupportingRecords < 1 ||
        maxSupportingResults < 1 ||
        maxBytes < 1024 ||
        chunk < 1 ||
        chunk > 500 ||
        previewCharacters < 0) {
      throw ArgumentError('export_limits');
    }
  }
}

/// Stable failure codes for the UI. Raw SQL or exception text is never shown.
final class ExportLimitException implements Exception {
  const ExportLimitException(this.code);
  final String code;
  @override
  String toString() => 'ExportLimitException($code)';
}

/// The selected operation stopped at an explicit checkpoint.
final class ExportCancelled implements Exception {
  const ExportCancelled();
  @override
  String toString() => 'ExportCancelled';
}

/// The app lock or another lifecycle boundary stopped the read.
final class ExportUnavailable implements Exception {
  const ExportUnavailable(this.code);
  final String code;
  @override
  String toString() => 'ExportUnavailable($code)';
}

/// One cooperative cancellation token shared by capture, encoding and handoff.
final class ExportCancellation {
  bool _cancelled = false;
  final _listeners = <void Function()>{};
  bool get isCancelled => _cancelled;
  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    final listeners = _listeners.toList();
    _listeners.clear();
    for (final listener in listeners) {
      listener();
    }
  }

  void addCancelListener(void Function() listener) {
    if (_cancelled) {
      listener();
    } else {
      _listeners.add(listener);
    }
  }

  void removeCancelListener(void Function() listener) =>
      _listeners.remove(listener);
  void throwIfCancelled() {
    if (_cancelled) throw const ExportCancelled();
  }
}

/// An immutable, single-person export selection.
///
/// [fromDay] is inclusive and [beforeDay] exclusive in [zoneId]. Only the
/// selected adult's records are read; there is no Everyone export.
final class ExportSelection {
  ExportSelection({
    required this.personId,
    required this.fromDay,
    required this.beforeDay,
    required this.zoneId,
    required Iterable<ExportContent> contents,
    this.format = ExportFormat.json,
    this.includeNotes = false,
    this.limits = ExportLimits.standard,
  }) : contents = Set.unmodifiable(contents) {
    limits.check();
    if (personId.trim().isEmpty || personId.length > 512) {
      throw ArgumentError('export_person');
    }
    if (zoneId.trim().isEmpty || zoneId.length > 256) {
      throw ArgumentError('export_zone');
    }
    if (beforeDay.compareTo(fromDay) <= 0) {
      throw ArgumentError('export_range');
    }
    if (this.contents.isEmpty) throw ArgumentError('export_content');
    final days = beforeDay.calendarValue
        .difference(fromDay.calendarValue)
        .inDays;
    if (days > limits.maxDays) {
      throw ExportLimitException('export_days');
    }
  }

  final String personId, zoneId;
  final CivilDate fromDay, beforeDay;
  final Set<ExportContent> contents;
  final ExportFormat format;
  final bool includeNotes;
  final ExportLimits limits;

  bool includes(ExportContent content) => contents.contains(content);

  ExportSelection copyWith({
    String? personId,
    CivilDate? fromDay,
    CivilDate? beforeDay,
    String? zoneId,
    Iterable<ExportContent>? contents,
    ExportFormat? format,
    bool? includeNotes,
  }) => ExportSelection(
    personId: personId ?? this.personId,
    fromDay: fromDay ?? this.fromDay,
    beforeDay: beforeDay ?? this.beforeDay,
    zoneId: zoneId ?? this.zoneId,
    contents: contents ?? this.contents,
    format: format ?? this.format,
    includeNotes: includeNotes ?? this.includeNotes,
    limits: limits,
  );

  /// Stable identity used to invalidate a reviewed preview after any change.
  String get identity => [
    personId,
    zoneId,
    fromDay.toString(),
    beforeDay.toString(),
    format.name,
    includeNotes ? 'notes' : 'private',
    (contents.map((value) => value.name).toList()..sort()).join(','),
  ].join('|');
}
