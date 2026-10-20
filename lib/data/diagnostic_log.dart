import '../domain/privacy/diagnostics.dart';
import 'record_store.dart';

/// Storage seam for the bounded diagnostic log. The production adapter uses
/// the encrypted database's existing settings table, so no schema migration is
/// required. Tests supply an in-memory adapter.
abstract interface class DiagnosticSettings {
  Future<String?> read();
  Future<void> write(String value);
}

/// The log lives in the same encrypted dataset as the records but is limited to
/// coarse technical events. It is not an export, report or remote telemetry.
final class RecordStoreDiagnosticSettings implements DiagnosticSettings {
  RecordStoreDiagnosticSettings(this._store);

  static const key = 'privacy_diagnostics_v1';

  final RecordStore _store;

  @override
  Future<String?> read() => _store.readSetting(key);

  @override
  Future<void> write(String value) => _store.writeSetting(key, value);
}

/// Serializes read-modify-write updates so two near-simultaneous failures cannot
/// drop or duplicate each other's bounded entries.
final class DiagnosticLog {
  DiagnosticLog(this._settings);

  final DiagnosticSettings _settings;
  Future<void> _tail = Future<void>.value();

  /// Appends one redacted event. Returns false when the local log could not be
  /// written; the caller's primary operation has already failed or succeeded
  /// independently and must not be reported differently because of logging.
  Future<bool> record(
    DiagnosticCode code, {
    required DiagnosticPlatform platform,
    DateTime? at,
  }) => _exclusive(() async {
    try {
      final events = [...decodeDiagnosticLog(await _settings.read())];
      events.add(
        DiagnosticEvent(
          code: code,
          at: (at ?? DateTime.now()).toUtc(),
          platform: platform,
        ),
      );
      await _settings.write(encodeDiagnosticLog(events));
      return true;
    } catch (_) {
      return false;
    }
  });

  Future<List<DiagnosticEvent>> read() =>
      _exclusive(() async => decodeDiagnosticLog(await _settings.read()));

  /// Clears the retained log. Throws when the write fails so the page can show
  /// an honest failure rather than claiming the entries are gone.
  Future<void> clear() =>
      _exclusive(() => _settings.write(encodeDiagnosticLog(const [])));

  Future<T> _exclusive<T>(Future<T> Function() action) {
    final result = _tail.then((_) => action());
    // A failed operation must not poison later operations in the queue.
    _tail = result.then<void>((_) {}, onError: (_, _) {});
    return result;
  }
}
