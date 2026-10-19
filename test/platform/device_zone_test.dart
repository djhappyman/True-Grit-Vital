import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:true_grit_vital/app/device_zone.dart';
import 'package:true_grit_vital/platform/device_zone.dart';

class _Gateway implements DeviceZoneGateway {
  final events = StreamController<void>.broadcast();
  DeviceZoneObservation value = DeviceZoneObservation.fromId('Europe/London');
  int reads = 0;
  Completer<DeviceZoneObservation>? pending;
  @override
  Stream<void> get changes => events.stream;
  @override
  Future<DeviceZoneObservation> read() async {
    reads++;
    return pending?.future ?? value;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'exact IANA IDs and aliases are admitted, unknown/display values refused',
    () {
      for (final id in ['Europe/London', 'US/Eastern', 'UTC', 'Etc/UTC']) {
        expect(DeviceZoneObservation.fromId(id).zoneId, id);
      }
      for (final id in [
        'BST',
        'UTC+01:00',
        'Europe/Unknown',
        '',
        '../Europe/London',
        ' Europe/London',
        42,
        null,
      ]) {
        expect(
          DeviceZoneObservation.fromId(id).status,
          DeviceZoneStatus.unavailable,
        );
      }
    },
  );
  test(
    'Linux honours explicit valid TZ and never masks malformed overrides',
    () async {
      final zone = LinuxDeviceZone(
        environment: {'TZ': ':Europe/London'},
        localtimeTarget: () async => throw StateError('must not read'),
      );
      expect((await zone.read()).zoneId, 'Europe/London');
      expect(
        (await LinuxDeviceZone(
          environment: {'TZ': 'GMT0BST,M3.5.0,M10.5.0'},
          localtimeTarget: () async => '/usr/share/zoneinfo/Europe/London',
        ).read()).zoneId,
        isNull,
      );
    },
  );
  test(
    'Linux accepts system symlink and refuses copied/unknown/alternate trees',
    () async {
      for (final target in [
        '/usr/share/zoneinfo/Europe/London',
        '../usr/share/zoneinfo/Europe/London',
      ]) {
        expect(
          (await LinuxDeviceZone(
            environment: {},
            localtimeTarget: () async => target,
          ).read()).zoneId,
          'Europe/London',
        );
      }
      for (final target in [
        '/tmp/Europe/London',
        '/usr/share/zoneinfo/right/Europe/London',
        '/usr/share/zoneinfo/../Europe/London',
        '/usr/share/zoneinfo/Unknown',
      ]) {
        expect(
          (await LinuxDeviceZone(
            environment: {},
            localtimeTarget: () async => target,
          ).read()).zoneId,
          isNull,
        );
      }
      expect(
        (await LinuxDeviceZone(
          environment: {},
          localtimeTarget: () async => throw const FileSystemExceptionForTest(),
        ).read()).zoneId,
        isNull,
      );
    },
  );
  test(
    'Android channel validates replies and reports unsupported/errors',
    () async {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      addTearDown(
        () =>
            messenger.setMockMethodCallHandler(AndroidDeviceZone.channel, null),
      );
      messenger.setMockMethodCallHandler(AndroidDeviceZone.channel, (
        call,
      ) async {
        expect(call.method, 'read');
        return 'Pacific/Auckland';
      });
      expect(
        (await const AndroidDeviceZone().read()).zoneId,
        'Pacific/Auckland',
      );
      messenger.setMockMethodCallHandler(
        AndroidDeviceZone.channel,
        (_) async => 'BST',
      );
      expect(
        (await const AndroidDeviceZone().read()).status,
        DeviceZoneStatus.unavailable,
      );
      messenger.setMockMethodCallHandler(
        AndroidDeviceZone.channel,
        (_) async => throw PlatformException(code: 'no_zone'),
      );
      expect(
        (await const AndroidDeviceZone().read()).status,
        DeviceZoneStatus.unavailable,
      );
      messenger.setMockMethodCallHandler(AndroidDeviceZone.channel, null);
      expect(
        (await const AndroidDeviceZone().read()).status,
        DeviceZoneStatus.unsupported,
      );
    },
  );
  testWidgets(
    'zone change, foreground minute pulse and resume refresh; disposal stops work',
    (tester) async {
      final gateway = _Gateway();
      final observer = DeviceZoneObserver(gateway);
      final seen = <DeviceZoneObservation>[];
      final subscription = observer.stream.listen(seen.add);
      await tester.pump();
      expect(seen.last.zoneId, 'Europe/London');
      gateway.value = DeviceZoneObservation.fromId('Pacific/Auckland');
      gateway.events.add(null);
      await tester.pump();
      expect(seen.last.zoneId, 'Pacific/Auckland');
      final before = gateway.reads;
      await tester.pump(const Duration(minutes: 1));
      expect(gateway.reads, before + 1);
      observer.didChangeAppLifecycleState(AppLifecycleState.paused);
      await tester.pump(const Duration(minutes: 1));
      expect(gateway.reads, before + 1);
      observer.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await tester.pump();
      expect(gateway.reads, before + 2);
      observer.dispose();
      gateway.events.add(null);
      await tester.pump(const Duration(minutes: 2));
      expect(gateway.reads, before + 2);
      unawaited(subscription.cancel());
      unawaited(gateway.events.close());
      await tester.pump();
    },
  );
  testWidgets('in-flight stale zone and disposed replies do not publish', (
    tester,
  ) async {
    final gateway = _Gateway()..pending = Completer<DeviceZoneObservation>();
    final observer = DeviceZoneObserver(gateway);
    final seen = <DeviceZoneObservation>[];
    final subscription = observer.stream.listen(seen.add);
    await tester.pump();
    gateway.events.add(null);
    await tester.pump();
    final pending = gateway.pending!;
    gateway.pending = null;
    gateway.value = DeviceZoneObservation.fromId('Asia/Tokyo');
    pending.complete(DeviceZoneObservation.fromId('Europe/London'));
    await tester.pump();
    expect(seen.map((o) => o.zoneId), ['Asia/Tokyo']);
    gateway.pending = Completer<DeviceZoneObservation>();
    unawaited(observer.refresh());
    observer.dispose();
    gateway.pending!.complete(DeviceZoneObservation.fromId('Europe/London'));
    await tester.pump();
    expect(seen.length, 1);
    unawaited(subscription.cancel());
    unawaited(gateway.events.close());
    await tester.pump();
  });
}

class FileSystemExceptionForTest implements Exception {
  const FileSystemExceptionForTest();
}
