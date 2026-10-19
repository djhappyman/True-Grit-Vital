import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/record_store.dart';
import '../platform/app_auth.dart';
import 'storage.dart';

final appAuthGatewayProvider = Provider<AppAuthGateway>(
  (ref) => const MethodChannelAppAuth(),
);
final appLockWriterProvider =
    Provider<Future<void> Function(RecordStore, bool, bool Function())>(
      (ref) =>
          (store, enabled, canCommit) => store.writeSetting(
            'app_lock',
            enabled.toString(),
            canCommit: canCommit,
          ),
    );

class AppLockState {
  const AppLockState({
    this.ready = false,
    this.enabled = false,
    this.locked = true,
    this.busy = false,
    this.availability = AppAuthAvailability.unsupported,
    this.failed = false,
  });
  final bool ready, enabled, locked, busy, failed;
  final AppAuthAvailability availability;
  AppLockState copy({
    bool? ready,
    bool? enabled,
    bool? locked,
    bool? busy,
    bool? failed,
    AppAuthAvailability? availability,
  }) => AppLockState(
    ready: ready ?? this.ready,
    enabled: enabled ?? this.enabled,
    locked: locked ?? this.locked,
    busy: busy ?? this.busy,
    failed: failed ?? this.failed,
    availability: availability ?? this.availability,
  );
}

final appLockProvider = NotifierProvider<AppLockController, AppLockState>(
  AppLockController.new,
);

class AppLockController extends Notifier<AppLockState> {
  RecordStore? _store;
  bool _foreground = true;
  int _session = 0, _lifecycleEpoch = 0;
  @override
  AppLockState build() {
    final store = ref.watch(recordStoreProvider).value;
    _session++;
    _store = store;
    if (store != null) {
      store.suspendWrites(true);
      final session = _session;
      Future.microtask(() => _initialise(store, session));
    }
    return const AppLockState();
  }

  bool _current(RecordStore store, int session) =>
      ref.mounted && _store == store && _session == session;
  Future<void> _initialise(RecordStore store, int session) async {
    try {
      final enabled = await store.readSetting('app_lock') == 'true';
      if (!_current(store, session)) return;
      final auth = ref.read(appAuthGatewayProvider);
      final available = await auth.availability();
      if (!_current(store, session)) return;
      if (enabled || available != AppAuthAvailability.unsupported) {
        await auth.setPrivacyEnabled(enabled);
      }
      if (!_current(store, session)) return;
      final locked = enabled || !_foreground;
      store.suspendWrites(locked);
      state = AppLockState(
        ready: true,
        enabled: enabled,
        locked: locked,
        availability: available,
      );
    } catch (_) {
      if (_current(store, session)) state = state.copy(failed: true);
    }
  }

  void lifecycle(AppLifecycleState lifecycle) {
    _lifecycleEpoch++;
    _foreground = lifecycle == AppLifecycleState.resumed;
    if (_foreground) {
      if (state.ready && !state.enabled && !state.busy) {
        _store?.suspendWrites(false);
        state = state.copy(locked: false);
      }
      return;
    }
    if (!state.enabled && !state.busy) return;
    _store?.suspendWrites(true);
    state = state.copy(locked: true);
  }

  Future<void> unlock() async {
    final store = _store;
    if (store == null ||
        !state.ready ||
        !state.locked ||
        state.busy ||
        !_foreground) {
      return;
    }
    final session = _session;
    state = state.copy(busy: true, failed: false);
    try {
      final result = await ref.read(appAuthGatewayProvider).authenticate();
      if (!_current(store, session)) return;
      // Native credential UI can itself pause the host. Only a completed auth
      // returned to this same foreground dataset opens the covered session.
      if (result == AppAuthResult.authenticated && _foreground) {
        store.suspendWrites(false);
        state = state.copy(locked: false);
      } else if (result != AppAuthResult.cancelled) {
        state = state.copy(failed: true);
      }
    } catch (_) {
      if (_current(store, session)) state = state.copy(failed: true);
    } finally {
      if (_current(store, session)) state = state.copy(busy: false);
    }
  }

  Future<void> setEnabled(bool enabled) async {
    final store = _store;
    if (store == null ||
        !state.ready ||
        state.locked ||
        state.busy ||
        enabled == state.enabled) {
      return;
    }
    final session = _session, previousEnabled = state.enabled;
    state = state.copy(busy: true, failed: false);
    final auth = ref.read(appAuthGatewayProvider);
    var preferenceCommitted = false;
    try {
      final availability = await auth.availability();
      if (!_current(store, session)) return;
      if (enabled && availability != AppAuthAvailability.available) {
        state = state.copy(availability: availability);
        return;
      }
      final result = await auth.authenticate();
      if (!_current(store, session) || !_foreground) return;
      if (result != AppAuthResult.authenticated) {
        if (result != AppAuthResult.cancelled) state = state.copy(failed: true);
        return;
      }
      final epoch = _lifecycleEpoch;
      bool canCommit() =>
          _current(store, session) && _foreground && epoch == _lifecycleEpoch;
      store.suspendWrites(false);
      // Enabling first protects previews. Disabling removes protection only
      // after the preference durably commits and the host is still foreground.
      if (enabled) await auth.setPrivacyEnabled(true);
      if (!canCommit()) throw const CommandConflict('app_locked');
      await ref.read(appLockWriterProvider)(store, enabled, canCommit);
      preferenceCommitted = true;
      if (!_current(store, session)) return;
      final foreground = canCommit();
      state = state.copy(
        enabled: enabled,
        locked: !foreground && enabled,
        availability: availability,
      );
      store.suspendWrites(state.locked);
      if (!enabled && foreground) {
        await auth.setPrivacyEnabled(false);
        if (!_current(store, session)) return;
        if (!canCommit()) {
          await auth.setPrivacyEnabled(true);
          if (_current(store, session)) {
            store.suspendWrites(true);
            state = state.copy(locked: true);
          }
        }
      }
    } catch (_) {
      if (_current(store, session)) {
        try {
          await auth.setPrivacyEnabled(
            preferenceCommitted ? enabled : previousEnabled,
          );
        } catch (_) {
          if (_current(store, session)) {
            store.suspendWrites(true);
            state = state.copy(locked: true);
          }
        }
        if (_current(store, session)) {
          final effectiveEnabled = preferenceCommitted
              ? enabled
              : previousEnabled;
          final locked = effectiveEnabled && (!_foreground || state.locked);
          store.suspendWrites(locked);
          state = state.copy(
            enabled: effectiveEnabled,
            locked: locked,
            failed: true,
          );
        }
      }
    } finally {
      if (_current(store, session)) {
        final restoreOpen = !state.enabled && _foreground;
        if (restoreOpen) store.suspendWrites(false);
        state = state.copy(
          busy: false,
          locked: restoreOpen ? false : state.locked,
        );
      }
    }
  }

  Future<void> refreshAvailability() async {
    final store = _store;
    if (store == null || state.busy) return;
    final session = _session;
    try {
      final availability = await ref
          .read(appAuthGatewayProvider)
          .availability();
      if (_current(store, session)) {
        state = state.copy(availability: availability, failed: false);
      }
    } catch (_) {
      if (_current(store, session)) {
        state = state.copy(
          availability: AppAuthAvailability.temporarilyUnavailable,
          failed: true,
        );
      }
    }
  }

  void lock() {
    if (!state.enabled) return;
    _session++;
    _store?.suspendWrites(true);
    state = state.copy(locked: true, busy: false);
  }
}
