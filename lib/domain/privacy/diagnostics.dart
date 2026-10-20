/// Coarse, redacted technical diagnostics for local recovery.
///
/// Events deliberately contain no free text, names, record identifiers,
/// quantities, file paths or payloads. Unknown or malformed stored entries are
/// discarded rather than repaired into a different meaning.
library;

import 'dart:convert';

/// Maximum number of retained events. Older events are removed first.
const int maxDiagnosticEvents = 40;

/// Maximum encoded size of the retained log.
const int maxDiagnosticLogBytes = 12 * 1024;

/// Known technical events. Adding a value is an append-only change so an older
/// installation never mislabels a newer event it cannot decode.
enum DiagnosticCode {
  dataLoad('data_load'),
  licenceNotice('licence_notice'),
  profileArchive('profile_archive'),
  profileDelete('profile_delete');

  const DiagnosticCode(this.code);

  /// Stable storage value, never a user-facing label.
  final String code;

  static DiagnosticCode? fromCode(String? value) {
    for (final code in values) {
      if (code.code == value) return code;
    }
    return null;
  }
}

/// Non-identifying host family retained with an event.
enum DiagnosticPlatform {
  android('android'),
  linux('linux'),
  other('other');

  const DiagnosticPlatform(this.code);

  final String code;

  static DiagnosticPlatform? fromCode(String? value) {
    for (final platform in values) {
      if (platform.code == value) return platform;
    }
    return null;
  }
}

/// One redacted diagnostic entry.
final class DiagnosticEvent {
  const DiagnosticEvent({
    required this.code,
    required this.at,
    required this.platform,
  });

  final DiagnosticCode code;
  final DateTime at;
  final DiagnosticPlatform platform;

  Map<String, Object> toJson() => {
    'code': code.code,
    'at': at.toUtc().toIso8601String(),
    'platform': platform.code,
  };

  /// Returns null for anything outside the fixed event vocabulary or with an
  /// unusable time. No stored string is exposed as UI or log text.
  static DiagnosticEvent? tryParse(Object? value) {
    if (value is! Map) return null;
    final rawCode = value['code'], rawPlatform = value['platform'];
    final rawAt = value['at'];
    if (rawCode is! String || rawPlatform is! String || rawAt is! String) {
      return null;
    }
    final code = DiagnosticCode.fromCode(rawCode);
    final platform = DiagnosticPlatform.fromCode(rawPlatform);
    final at = DateTime.tryParse(rawAt);
    if (code == null || platform == null || at == null) return null;
    return DiagnosticEvent(code: code, at: at.toUtc(), platform: platform);
  }
}

/// Decode a bounded log, dropping malformed or unknown entries. Never throws.
List<DiagnosticEvent> decodeDiagnosticLog(String? raw) {
  if (raw == null || raw.isEmpty || raw.length > maxDiagnosticLogBytes) {
    return const [];
  }
  final Object? decoded;
  try {
    decoded = jsonDecode(raw);
  } on FormatException {
    return const [];
  }
  if (decoded is! List) return const [];
  final events = <DiagnosticEvent>[];
  for (final value in decoded) {
    final event = DiagnosticEvent.tryParse(value);
    if (event != null) events.add(event);
  }
  return _bounded(events);
}

/// Encode the retained log. Also used to bound an in-memory list before write.
String encodeDiagnosticLog(Iterable<DiagnosticEvent> events) => jsonEncode(
  _bounded(events.toList()).map((event) => event.toJson()).toList(),
);

List<DiagnosticEvent> _bounded(List<DiagnosticEvent> events) {
  // Keep event order: oldest first, newest last.
  var start = events.length > maxDiagnosticEvents
      ? events.length - maxDiagnosticEvents
      : 0;
  while (start < events.length) {
    final encoded = jsonEncode(
      events.skip(start).map((event) => event.toJson()).toList(),
    );
    if (encoded.length <= maxDiagnosticLogBytes) break;
    start++;
  }
  return events.sublist(start);
}
