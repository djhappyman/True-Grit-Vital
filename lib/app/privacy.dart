import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, immutable;
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/diagnostic_log.dart';
import '../data/record_store.dart';
import '../domain/privacy/diagnostics.dart';
import '../domain/privacy/licences.dart';
import '../domain/privacy/settings_capabilities.dart';
import 'app_lock.dart';
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

/// The owner revision and dataset generation one delete confirmation belongs
/// to. A replaced dataset can reuse the same person ID and revision, so the
/// generation is part of the captured authority rather than a display detail.
@immutable
final class ProfileDeleteAuthority {
  const ProfileDeleteAuthority({
    required this.generation,
    required this.personRevision,
  });

  final String generation;
  final int personRevision;

  bool matches({required String? generation, required int? personRevision}) =>
      generation == this.generation && personRevision == this.personRevision;
}

/// Small injectable boundary for the destructive data-management actions so a
/// failed write can be tested honestly without faking a successful store.
abstract interface class ProfilePrivacyActions {
  Future<void> delete({
    required String commandId,
    required String personId,
    required int expectedRevision,
    required String expectedGeneration,
    bool Function()? actionCurrent,
  });
}

final class StoreProfilePrivacyActions implements ProfilePrivacyActions {
  StoreProfilePrivacyActions(
    this._store, {
    this.beforeDelete,
    this.canCommit,
    this.captureGuard,
  });

  final Future<RecordStore> Function() _store;
  final Future<void> Function()? beforeDelete;
  final bool Function()? canCommit;
  final bool Function() Function()? captureGuard;

  void _requireOpen() {
    if (canCommit != null && !canCommit!()) {
      throw const CommandConflict('app_locked');
    }
  }

  void _requireSameDataset(RecordStore store, String expectedGeneration) {
    // The store's own command transaction also binds to its generation. This
    // earlier check stops a confirmation captured from an older dataset before
    // any generated-copy cleanup starts.
    if (store.generation != expectedGeneration) {
      throw const CommandConflict('generation');
    }
  }

  @override
  Future<void> delete({
    required String commandId,
    required String personId,
    required int expectedRevision,
    required String expectedGeneration,
    bool Function()? actionCurrent,
  }) async {
    final captured = captureGuard?.call();
    bool current() =>
        (captured?.call() ?? true) &&
        (actionCurrent?.call() ?? true) &&
        (canCommit?.call() ?? true);
    void requireCurrent() {
      _requireOpen();
      if (!current()) throw const CommandConflict('app_locked');
    }

    requireCurrent();
    final store = await _store();
    _requireSameDataset(store, expectedGeneration);
    // The store rechecks the owner revision inside its command transaction,
    // after its idempotent replay check. Keeping that ordering lets an exact
    // retry of a committed command replay instead of looking like a conflict.
    requireCurrent();
    await beforeDelete?.call();
    requireCurrent();
    // Cleanup can await. Resolve the live store again so a replacement during
    // it cannot pass the captured generation into the writer.
    final live = await _store();
    if (!identical(live, store)) {
      throw const CommandConflict('generation');
    }
    _requireSameDataset(live, expectedGeneration);
    requireCurrent();
    await live.deleteProfile(
      commandId: commandId,
      personId: personId,
      expectedRevision: expectedRevision,
      canCommit: current,
    );
  }
}

final profilePrivacyActionsProvider = Provider<ProfilePrivacyActions>(
  (ref) => StoreProfilePrivacyActions(
    () => ref.read(recordStoreProvider.future),
    beforeDelete: () => prepareGeneratedArtifactsForDataChange(ref),
    canCommit: () => ref.mounted && !ref.read(appLockProvider).locked,
    captureGuard: () {
      final lock = ref.read(appLockProvider);
      final store = ref.read(recordStoreProvider).value;
      return () =>
          ref.mounted &&
          !ref.read(appLockProvider).locked &&
          identical(ref.read(appLockProvider), lock) &&
          identical(ref.read(recordStoreProvider).value, store);
    },
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
