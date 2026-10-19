import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

enum AppAuthAvailability {
  available,
  setupRequired,
  unsupported,
  temporarilyUnavailable,
}

enum AppAuthResult { authenticated, cancelled, unavailable, failed, busy }

/// Device authentication is a UI access boundary, independent of file encryption.
abstract interface class AppAuthGateway {
  Future<AppAuthAvailability> availability();
  Future<AppAuthResult> authenticate();

  /// Apply before showing records. Unsupported hosts cannot enable protection.
  Future<void> setPrivacyEnabled(bool enabled);
}

final class AppPrivacyException implements Exception {
  const AppPrivacyException(this.code);
  final String code;

  @override
  String toString() => 'AppPrivacyException($code)';
}

/// Android framework authentication; other hosts truthfully report unsupported.
final class MethodChannelAppAuth implements AppAuthGateway {
  const MethodChannelAppAuth();

  static const _channel = MethodChannel('true_grit_vital/app_auth');
  bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
  Future<AppAuthAvailability> availability() async {
    if (!_isAndroid) return AppAuthAvailability.unsupported;
    try {
      return switch (await _channel.invokeMethod<Object?>('availability')) {
        'available' => AppAuthAvailability.available,
        'setupRequired' => AppAuthAvailability.setupRequired,
        'unsupported' => AppAuthAvailability.unsupported,
        _ => AppAuthAvailability.temporarilyUnavailable,
      };
    } on MissingPluginException {
      return AppAuthAvailability.unsupported;
    } on PlatformException {
      return AppAuthAvailability.temporarilyUnavailable;
    }
  }

  @override
  Future<AppAuthResult> authenticate() async {
    if (!_isAndroid) return AppAuthResult.unavailable;
    try {
      return switch (await _channel.invokeMethod<Object?>('authenticate')) {
        'authenticated' => AppAuthResult.authenticated,
        'cancelled' => AppAuthResult.cancelled,
        'unavailable' => AppAuthResult.unavailable,
        'busy' => AppAuthResult.busy,
        _ => AppAuthResult.failed,
      };
    } on MissingPluginException {
      return AppAuthResult.unavailable;
    } on PlatformException {
      return AppAuthResult.failed;
    }
  }

  @override
  Future<void> setPrivacyEnabled(bool enabled) async {
    if (!_isAndroid) {
      if (enabled) throw const AppPrivacyException('unsupported_host');
      // Disabling an unsupported, never-enabled feature needs no OS operation.
      return;
    }
    try {
      final applied = await _channel.invokeMethod<Object?>(
        'setPrivacyEnabled',
        {'enabled': enabled},
      );
      if (applied != true) {
        throw const AppPrivacyException('privacy_unavailable');
      }
    } on MissingPluginException {
      throw const AppPrivacyException('unsupported_host');
    } on PlatformException {
      throw const AppPrivacyException('privacy_unavailable');
    }
  }
}
