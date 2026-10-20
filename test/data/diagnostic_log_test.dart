import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:true_grit_vital/data/diagnostic_log.dart';
import 'package:true_grit_vital/data/record_store.dart';
import 'package:true_grit_vital/domain/privacy/diagnostics.dart';

final class _MemorySettings implements DiagnosticSettings {
  String? raw;
  bool failWrites = false;
  int writes = 0;

  @override
  Future<String?> read() async => raw;

  @override
  Future<void> write(String value) async {
    writes++;
    if (failWrites) throw StateError('synthetic_write_failure');
    raw = value;
  }
}

void main() {
  test('records, reads and clears one bounded local log', () async {
    final settings = _MemorySettings();
    final log = DiagnosticLog(settings);
    expect(await log.read(), isEmpty);
    expect(
      await log.record(
        DiagnosticCode.profileArchive,
        platform: DiagnosticPlatform.linux,
        at: DateTime.utc(2026, 10, 20, 9),
      ),
      true,
    );
    expect(
      await log.record(
        DiagnosticCode.licenceNotice,
        platform: DiagnosticPlatform.linux,
        at: DateTime.utc(2026, 10, 20, 10),
      ),
      true,
    );
    final events = await log.read();
    expect(events.map((event) => event.code), [
      DiagnosticCode.profileArchive,
      DiagnosticCode.licenceNotice,
    ]);
    await log.clear();
    expect(await log.read(), isEmpty);
    expect(settings.writes, 3);
  });

  test('concurrent appends are serialized without losing entries', () async {
    final log = DiagnosticLog(_MemorySettings());
    await Future.wait([
      for (var index = 0; index < 20; index++)
        log.record(
          DiagnosticCode.dataLoad,
          platform: DiagnosticPlatform.android,
          at: DateTime.utc(2026, 10, 20).add(Duration(seconds: index)),
        ),
    ]);
    expect(await log.read(), hasLength(20));
  });

  test(
    'a write failure is reported without changing the primary result',
    () async {
      final settings = _MemorySettings()..failWrites = true;
      final log = DiagnosticLog(settings);
      expect(
        await log.record(
          DiagnosticCode.profileDelete,
          platform: DiagnosticPlatform.linux,
        ),
        false,
      );
      await expectLater(log.clear(), throwsA(isA<StateError>()));
    },
  );

  test('retained log survives a real encrypted dataset restart', () async {
    final directory = await Directory.systemTemp.createTemp(
      'vital-diagnostics-test-',
    );
    final path = '${directory.path}/records.db';
    final key = List.generate(32, (index) => index + 1);
    var store = await RecordStore.open(path: path, key: key, isNew: true);
    addTearDown(() async {
      await store.close();
      await directory.delete(recursive: true);
    });
    await DiagnosticLog(RecordStoreDiagnosticSettings(store)).record(
      DiagnosticCode.profileDelete,
      platform: DiagnosticPlatform.linux,
      at: DateTime.utc(2026, 10, 20, 11),
    );
    expect(
      await store.readSetting(RecordStoreDiagnosticSettings.key),
      contains('profile_delete'),
    );
    await store.close();
    store = await RecordStore.open(path: path, key: key, isNew: false);
    final events = await DiagnosticLog(RecordStoreDiagnosticSettings(store))
        .read();
    expect(events.single.code, DiagnosticCode.profileDelete);
    expect(events.single.at, DateTime.utc(2026, 10, 20, 11));
  });
}
