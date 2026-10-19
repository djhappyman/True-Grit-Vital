import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../platform/device_zone.dart';

final deviceZoneGatewayProvider = Provider<DeviceZoneGateway>((ref) {
  if (Platform.isAndroid) return const AndroidDeviceZone();
  if (Platform.isLinux) return LinuxDeviceZone();
  return const UnsupportedDeviceZone();
});

/// A minute pulse bounds foreground day/clock refresh, including fixed-home
/// dates. Native changes and resume refresh immediately. No background timer
/// scheduling or reminder-delivery claim is made by this UI observation stream.
final observedDeviceZoneProvider =
    StreamProvider.autoDispose<DeviceZoneObservation>((ref) {
      final observer = DeviceZoneObserver(ref.watch(deviceZoneGatewayProvider));
      ref.onDispose(observer.dispose);
      return observer.stream;
    });

final class DeviceZoneObserver with WidgetsBindingObserver {
  DeviceZoneObserver(
    this.gateway, {
    this.refreshInterval = const Duration(minutes: 1),
  }) {
    WidgetsBinding.instance.addObserver(this);
    _foreground =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    _subscription = gateway.changes.listen(
      (_) => refresh(),
      onError: (Object _) => refresh(),
    );
    _timer = Timer.periodic(refreshInterval, (_) {
      if (_foreground) refresh();
    });
    // Wait until the StreamProvider has attached its listener.
    scheduleMicrotask(refresh);
  }
  final DeviceZoneGateway gateway;
  final Duration refreshInterval;
  final _controller = StreamController<DeviceZoneObservation>();
  Stream<DeviceZoneObservation> get stream => _controller.stream;
  late final StreamSubscription<void> _subscription;
  late final Timer _timer;
  bool _disposed = false, _reading = false, _again = false, _foreground = true;

  Future<void> refresh() async {
    if (_disposed) return;
    if (_reading) {
      _again = true;
      return;
    }
    _reading = true;
    try {
      do {
        _again = false;
        DeviceZoneObservation observation;
        try {
          observation = await gateway.read();
        } catch (_) {
          observation = const DeviceZoneObservation.unavailable();
        }
        // A newer clock/zone event supersedes the in-flight observation.
        if (!_disposed && !_again) _controller.add(observation);
      } while (!_disposed && _again);
    } finally {
      _reading = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) unawaited(refresh());
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _timer.cancel();
    unawaited(_subscription.cancel());
    unawaited(_controller.close());
  }
}
