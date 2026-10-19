import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import '../domain/scheduling/iana_clock.dart';

enum DeviceZoneStatus { available, unavailable, unsupported }

/// A validated observation, never an abbreviation inferred from a UTC offset.
final class DeviceZoneObservation {
  const DeviceZoneObservation._(this.status, this.zoneId);
  const DeviceZoneObservation.unavailable()
    : this._(DeviceZoneStatus.unavailable, null);
  const DeviceZoneObservation.unsupported()
    : this._(DeviceZoneStatus.unsupported, null);

  final DeviceZoneStatus status;
  final String? zoneId;

  static DeviceZoneObservation fromId(Object? value) {
    if (value is! String ||
        value.isEmpty ||
        value.length > 128 ||
        value != value.trim() ||
        value.contains('..') ||
        !RegExp(r'^[A-Za-z0-9_+\-/]+$').hasMatch(value)) {
      return const DeviceZoneObservation.unavailable();
    }
    // Names without a slash are accepted only as exact admitted identifiers;
    // no offset, display abbreviation, or POSIX rule is translated into a zone.
    try {
      IanaClock().validateZone(value);
      return DeviceZoneObservation._(DeviceZoneStatus.available, value);
    } catch (_) {
      return const DeviceZoneObservation.unavailable();
    }
  }
}

abstract interface class DeviceZoneGateway {
  Future<DeviceZoneObservation> read();
  Stream<void> get changes;
}

final class AndroidDeviceZone implements DeviceZoneGateway {
  const AndroidDeviceZone();
  static const channel = MethodChannel('true_grit_vital/device_zone');
  static const events = EventChannel('true_grit_vital/device_zone_changes');

  @override
  Future<DeviceZoneObservation> read() async {
    try {
      return DeviceZoneObservation.fromId(
        await channel
            .invokeMethod<Object?>('read')
            .timeout(const Duration(seconds: 2)),
      );
    } on MissingPluginException {
      return const DeviceZoneObservation.unsupported();
    } catch (_) {
      return const DeviceZoneObservation.unavailable();
    }
  }

  @override
  Stream<void> get changes => events.receiveBroadcastStream().map((_) {});
}

/// Linux's TZ override or the system localtime symlink. No host mutation or
/// external process is needed. A copied localtime file has no recoverable name.
final class LinuxDeviceZone implements DeviceZoneGateway {
  LinuxDeviceZone({
    Map<String, String>? environment,
    Future<String> Function()? localtimeTarget,
  }) : _environment = environment ?? Platform.environment,
       _localtimeTarget =
           localtimeTarget ?? (() => Link('/etc/localtime').target());
  final Map<String, String> _environment;
  final Future<String> Function() _localtimeTarget;

  static DeviceZoneObservation parse(String raw) {
    var value = raw;
    if (value.startsWith(':')) value = value.substring(1);
    const root = '/usr/share/zoneinfo/';
    if (value.startsWith(root)) value = value.substring(root.length);
    if (value.startsWith('../usr/share/zoneinfo/')) {
      value = value.substring('../usr/share/zoneinfo/'.length);
    }
    // Reject alternate trees with potentially different leap-second semantics.
    if (value.startsWith('posix/') || value.startsWith('right/')) {
      return const DeviceZoneObservation.unavailable();
    }
    return DeviceZoneObservation.fromId(value);
  }

  @override
  Future<DeviceZoneObservation> read() async {
    if (_environment.containsKey('TZ')) return parse(_environment['TZ']!);
    try {
      final target = await _localtimeTarget().timeout(
        const Duration(seconds: 2),
      );
      // Only the documented system zoneinfo tree establishes this observation.
      if (!target.startsWith('/usr/share/zoneinfo/') &&
          !target.startsWith('../usr/share/zoneinfo/')) {
        return const DeviceZoneObservation.unavailable();
      }
      return parse(target);
    } catch (_) {
      return const DeviceZoneObservation.unavailable();
    }
  }

  @override
  Stream<void> get changes => const Stream.empty();
}

final class UnsupportedDeviceZone implements DeviceZoneGateway {
  const UnsupportedDeviceZone();
  @override
  Future<DeviceZoneObservation> read() async =>
      const DeviceZoneObservation.unsupported();
  @override
  Stream<void> get changes => const Stream.empty();
}
