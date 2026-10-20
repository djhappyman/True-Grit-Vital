import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/diagnostic_log.dart';
import '../data/record_store.dart';
import '../domain/privacy/diagnostics.dart';
import '../domain/privacy/licences.dart';
import '../domain/privacy/settings_capabilities.dart';
import 'storage.dart';
import 'generated_artifacts.dart';

/// Explicit capability injection for tests or a host that wants to hide a
/// route it does not expose. The default is none; Settings also detects routes
/// registered by the integrated build.
final settingsCapabilitiesProvider = Provider<SettingsCapabilities>(
  (ref) => const SettingsCapabilities.none(),
);

/// Combines explicit injection with the routes actually registered by the
/// integrated build. A dependency merged later becomes visible without a second
/// hand-maintained flag, and an absent route never produces a dead control.
SettingsCapabilities settingsCapabilitiesFor(
  GoRouter router, {
  SettingsCapabilities configured = const SettingsCapabilities.none(),
}) => SettingsCapabilities(
  reportsPath: _pick(configured.reportsPath, router, '/reports'),
  exportsPath: _pick(configured.exportsPath, router, '/exports'),
  backupPath: _pick(configured.backupPath, router, '/backup'),
  restorePath: _pick(configured.restorePath, router, '/restore'),
);

String? _pick(String? configured, GoRouter router, String candidate) =>
    configured ??
    (_routeExists(router.configuration.routes, candidate) ? candidate : null);

bool _routeExists(Iterable<RouteBase> routes, String path) {
  for (final route in routes) {
    switch (route) {
      case GoRoute():
        if (route.path == path || _routeExists(route.routes, path)) return true;
      case ShellRoute():
        if (_routeExists(route.routes, path)) return true;
      default:
        break;
    }
  }
  return false;
}

/// Retains the host family without identifying the device or person.
final diagnosticPlatformProvider = Provider<DiagnosticPlatform>((ref) {
  return switch (defaultTargetPlatform) {
    TargetPlatform.android => DiagnosticPlatform.android,
    TargetPlatform.linux => DiagnosticPlatform.linux,
    _ => DiagnosticPlatform.other,
  };
});

final diagnosticLogProvider = FutureProvider<DiagnosticLog>((ref) async {
  final store = await ref.watch(recordStoreProvider.future);
  return DiagnosticLog(RecordStoreDiagnosticSettings(store));
});

final diagnosticEventsProvider = FutureProvider<List<DiagnosticEvent>>(
  retry: (_, _) => null,
  (ref) async {
    final log = await ref.watch(diagnosticLogProvider.future);
    return log.read();
  },
);

/// Small injectable boundary for the destructive data-management actions so a
/// failed write can be tested honestly without faking a successful store.
abstract interface class ProfilePrivacyActions {
  Future<void> delete({
    required String commandId,
    required String personId,
    required int expectedRevision,
  });
}

final class StoreProfilePrivacyActions implements ProfilePrivacyActions {
  StoreProfilePrivacyActions(this._store, {this.beforeDelete});

  final Future<RecordStore> Function() _store;
  final Future<void> Function()? beforeDelete;

  @override
  Future<void> delete({
    required String commandId,
    required String personId,
    required int expectedRevision,
  }) async {
    await beforeDelete?.call();
    await (await _store()).deleteProfile(
      commandId: commandId,
      personId: personId,
      expectedRevision: expectedRevision,
    );
  }
}

final profilePrivacyActionsProvider = Provider<ProfilePrivacyActions>(
  (ref) => StoreProfilePrivacyActions(
    () => ref.read(recordStoreProvider.future),
    beforeDelete: () => prepareGeneratedArtifactsForDataChange(ref),
  ),
);

const adoptedNoticesAsset = 'assets/legal/notices.txt';
const applicationLicenceAsset = 'LICENSE';

/// Injected so tests and future bundled notice locations do not need the real
/// asset bundle, while production reads only shipped assets.
final licenceTextLoaderProvider =
    Provider<Future<String> Function(String asset)>(
      (ref) =>
          (asset) => rootBundle.loadString(asset),
    );

final licenceNoticesProvider = FutureProvider<List<LicenceNotice>>(
  retry: (_, _) => null,
  (ref) async {
    final load = ref.watch(licenceTextLoaderProvider);
    return decodeLicenceNotices(await load(adoptedNoticesAsset));
  },
);

final applicationLicenceProvider = FutureProvider<String>(
  retry: (_, _) => null,
  (ref) async {
    final load = ref.watch(licenceTextLoaderProvider);
    return load(applicationLicenceAsset);
  },
);
