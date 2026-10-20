import 'package:flutter_test/flutter_test.dart';
import 'package:true_grit_vital/domain/privacy/diagnostics.dart';

void main() {
  test('known events round-trip with only coarse technical fields', () {
    final event = DiagnosticEvent(
      code: DiagnosticCode.profileDelete,
      at: DateTime.utc(2026, 10, 20, 12, 30),
      platform: DiagnosticPlatform.linux,
    );
    final json = event.toJson();
    expect(json.keys, unorderedEquals(['code', 'at', 'platform']));
    expect(json.values, isNot(contains('Alex')));
    final decoded = decodeDiagnosticLog(encodeDiagnosticLog([event]));
    expect(decoded, hasLength(1));
    expect(decoded.single.code, DiagnosticCode.profileDelete);
    expect(decoded.single.platform, DiagnosticPlatform.linux);
    expect(decoded.single.at, DateTime.utc(2026, 10, 20, 12, 30));
  });

  test('non-UTC event time is stored as UTC', () {
    final event = DiagnosticEvent(
      code: DiagnosticCode.dataLoad,
      at: DateTime.utc(2026, 10, 20, 12).toLocal(),
      platform: DiagnosticPlatform.android,
    );
    expect(event.toJson()['at'], '2026-10-20T12:00:00.000Z');
  });

  test('unknown, wrong-typed and malformed entries are dropped', () {
    final raw =
        '[{"code":"profile_delete","at":"2026-10-20T12:00:00Z","platform":"linux"},'
        '{"code":"unknown_future","at":"2026-10-20T12:00:00Z","platform":"linux"},'
        '{"code":"profile_delete","at":12,"platform":"linux"},'
        '{"code":"profile_delete","at":"not-a-date","platform":"linux"},'
        '{"code":"profile_delete","at":"2026-10-20T12:00:00Z","platform":"device-123"},'
        '"free text",'
        '{"code":123,"at":"2026-10-20T12:00:00Z","platform":"linux"}]';
    final decoded = decodeDiagnosticLog(raw);
    expect(decoded, hasLength(1));
    expect(decoded.single.code, DiagnosticCode.profileDelete);
  });

  test('invalid stored JSON never throws and decodes as empty', () {
    for (final raw in ['', 'not json', '{"code":"x"}', 'null', '[1,2]']) {
      expect(decodeDiagnosticLog(raw), isEmpty);
    }
  });

  test('oversized stored input is rejected before decoding', () {
    final event = DiagnosticEvent(
      code: DiagnosticCode.dataLoad,
      at: DateTime.utc(2026),
      platform: DiagnosticPlatform.linux,
    );
    final valid = encodeDiagnosticLog([event]);
    expect(
      decodeDiagnosticLog('$valid${' ' * maxDiagnosticLogBytes}'),
      isEmpty,
    );
  });

  test('retention is bounded by count and encoded size', () {
    final start = DateTime.utc(2026, 1, 1);
    final many = [
      for (var index = 0; index < 200; index++)
        DiagnosticEvent(
          code: DiagnosticCode.values[index % DiagnosticCode.values.length],
          at: start.add(Duration(minutes: index)),
          platform: DiagnosticPlatform.linux,
        ),
    ];
    final encoded = encodeDiagnosticLog(many);
    final decoded = decodeDiagnosticLog(encoded);
    expect(decoded.length, lessThanOrEqualTo(maxDiagnosticEvents));
    expect(encoded.length, lessThanOrEqualTo(maxDiagnosticLogBytes));
    // Newest entries survive, oldest are dropped first.
    expect(decoded.last.at, many.last.at);
  });

  test('maximum count is enforced before encoding too', () {
    final events = [
      for (var index = 0; index < maxDiagnosticEvents + 5; index++)
        DiagnosticEvent(
          code: DiagnosticCode.licenceNotice,
          at: DateTime.utc(2026, 1, 1).add(Duration(seconds: index)),
          platform: DiagnosticPlatform.other,
        ),
    ];
    final decoded = decodeDiagnosticLog(encodeDiagnosticLog(events));
    expect(decoded, hasLength(maxDiagnosticEvents));
  });
}
