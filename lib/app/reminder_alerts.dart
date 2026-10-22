import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/record_store.dart';
import '../platform/reminders.dart';
import 'app_lock.dart';
import 'reminder_gateway.dart';
import 'storage.dart';

/// Encrypted settings key. The device-side channel preference is applied from
/// this value; the native reminder journal is not portable backup truth.
const reminderAlertsSettingKey = 'reminder_alerts';

final class ReminderAlerts {
  const ReminderAlerts({
    this.preferences = ReminderAlertPreferences.legacy,
    this.loaded = false,
    this.busy = false,
    this.loadFailed = false,
    this.saveFailed = false,
    this.applyFailed = false,
    this.revision = 0,
  });
  final ReminderAlertPreferences preferences;
  final bool loaded, busy, loadFailed, saveFailed, applyFailed;

  /// Advances only after the adapter accepted a choice. The reminder runtime
  /// watches it and re-reads channel capability without importing this file's
  /// owner back into the controller.
  final int revision;
}

typedef ReminderAlertsWriter = Future<void> Function(
  RecordStore store,
  String value,
  bool Function() canCommit,
);

/// Writes through the exact captured store and commit fence, so a queued write
/// cannot land in a restored dataset or publish across a lock cycle.
final reminderAlertsWriterProvider = Provider<ReminderAlertsWriter>(
  (ref) =>
      (store, value, canCommit) => store.writeSetting(
        reminderAlertsSettingKey,
        value,
        canCommit: canCommit,
      ),
);

/// Prefers the live reminder adapter. Test or desktop adapters that do not
/// implement the alert contract remain honest: the choice is not applied.
final reminderAlertGatewayProvider = Provider<ReminderAlertGateway>((ref) {
  return switch (ref.watch(reminderGatewayProvider)) {
    final ReminderAlertGateway gateway => gateway,
    _ => const UnsupportedReminders(),
  };
});

final reminderAlertsProvider =
    NotifierProvider<ReminderAlertsController, ReminderAlerts>(
      ReminderAlertsController.new,
    );

/// Persists optional sound/vibration choices and applies them to the adapter.
///
/// The stored choice is the durable intent. A failed native apply keeps that
/// intent and reports it as pending, so the screen never claims an effect the
/// adapter has not accepted. The operating system remains authoritative.
class ReminderAlertsController extends Notifier<ReminderAlerts> {
  // The notifier survives a record-store replacement (restore), so delayed
  // reads and writes are fenced by both the dataset and lock epoch.
  int _epoch = 0, _lockEpoch = 0, _revision = 0;
  bool _saving = false;
  Completer<void>? _saveSettled;
  ReminderAlertPreferences? _applied;
  bool _applyAccepted = false;
  RecordStore? _captureStore;
  ReminderAlertGateway? _captureGateway;

  @override
  ReminderAlerts build() {
    final gateway = ref.watch(reminderAlertGatewayProvider);
    ref.listen(appLockProvider.select((state) => state.locked), (
      previous,
      next,
    ) {
      if (previous == next) return;
      _lockEpoch++;
      // A choice read while the device or app was locked could not reach the
      // native journal. Retry it once the protected store becomes usable.
      if (previous == true &&
          next == false &&
          ref.mounted &&
          state.loaded &&
          state.applyFailed) {
        unawaited(retryApply());
      }
    });
    final record = ref.watch(recordStoreProvider);
    final store = (record.isLoading || record.hasError) ? null : record.value;
    final epoch = ++_epoch;
    if (!identical(store, _captureStore) ||
        !identical(gateway, _captureGateway)) {
      // A restore, a native journal reset or a replacement adapter invalidates
      // the "already applied" cache. Re-apply even an identical choice so a
      // reset device cannot silently keep the previous channel.
      _captureStore = store;
      _captureGateway = gateway;
      _applied = null;
      _applyAccepted = false;
    }
    if (store != null) {
      scheduleMicrotask(() async {
        try {
          // A read issued during an in-flight publication would return the
          // value that write is about to replace. Wait, then read freshly.
          while (_saving && ref.mounted && epoch == _epoch) {
            final settled = _saveSettled;
            if (settled == null) break;
            await settled.future;
          }
          if (!ref.mounted || epoch != _epoch) return;
          final raw = await store.readSetting(reminderAlertsSettingKey);
          if (!ref.mounted || epoch != _epoch) return;
          final preferences = raw == null
              ? ReminderAlertPreferences.legacy
              : ReminderAlertPreferences.decode(raw);
          state = ReminderAlerts(
            preferences: preferences,
            loaded: true,
            revision: _revision,
          );
          await _apply(preferences, epoch: epoch);
        } catch (_) {
          if (ref.mounted && epoch == _epoch) {
            state = ReminderAlerts(
              loaded: true,
              loadFailed: true,
              revision: _revision,
            );
          }
        }
      });
    }
    return ReminderAlerts(busy: _saving, revision: _revision);
  }

  Future<bool> setSound(bool value) =>
      _save(state.preferences.copyWith(sound: value));

  Future<bool> setVibration(bool value) =>
      _save(state.preferences.copyWith(vibration: value));

  /// Re-applies the saved intent after a native failure. Uses the same stored
  /// choice; it never invents a different preference.
  Future<bool> retryApply() {
    if (!ref.mounted || _saving) return Future.value(false);
    return _apply(state.preferences, epoch: _epoch, force: true);
  }

  Future<bool> _save(ReminderAlertPreferences next) async {
    if (_saving || ref.read(appLockProvider).locked) return false;
    final record = ref.read(recordStoreProvider);
    final store = (record.isLoading || record.hasError) ? null : record.value;
    if (store == null) return false;
    final previous = state.preferences;
    final epoch = ++_epoch, lockEpoch = _lockEpoch;
    final settled = _saveSettled = Completer<void>();
    _saving = true;
    state = ReminderAlerts(
      preferences: next,
      loaded: true,
      busy: true,
      revision: _revision,
    );
    bool current() =>
        ref.mounted &&
        epoch == _epoch &&
        lockEpoch == _lockEpoch &&
        !ref.read(appLockProvider).locked;
    var saved = false;
    try {
      await ref.read(reminderAlertsWriterProvider)(
        store,
        next.encode(),
        current,
      );
      if (current()) {
        await _apply(next, epoch: epoch);
        if (current()) {
          state = ReminderAlerts(
            preferences: next,
            loaded: true,
            applyFailed: state.applyFailed,
            revision: _revision,
          );
        }
        saved = true;
      } else if (ref.mounted && epoch == _epoch) {
        // The durable write committed, but a lock or a newer choice arrived
        // before the adapter call. Keep the stored intent and say it is not
        // applied yet rather than claiming the change took effect.
        state = ReminderAlerts(
          preferences: next,
          loaded: true,
          applyFailed: true,
          revision: _revision,
        );
      }
    } catch (_) {
      if (ref.mounted && epoch == _epoch) {
        state = ReminderAlerts(
          preferences: previous,
          loaded: true,
          saveFailed: true,
          revision: _revision,
        );
      }
    } finally {
      _saving = false;
      _saveSettled = null;
      if (ref.mounted && state.busy) {
        state = ReminderAlerts(
          preferences: state.preferences,
          loaded: state.loaded,
          loadFailed: state.loadFailed,
          saveFailed: state.saveFailed,
          applyFailed: state.applyFailed,
          revision: _revision,
        );
      }
      settled.complete();
    }
    return saved;
  }

  Future<bool> _apply(
    ReminderAlertPreferences preferences, {
    required int epoch,
    bool force = false,
  }) async {
    if (!force && _applied == preferences && _applyAccepted) return true;
    try {
      final accepted = await ref
          .read(reminderAlertGatewayProvider)
          .applyAlertPreferences(preferences)
          .timeout(const Duration(seconds: 5));
      if (!ref.mounted || epoch != _epoch) return accepted;
      _applied = preferences;
      _applyAccepted = accepted;
      if (accepted) _revision++;
      state = ReminderAlerts(
        preferences: state.preferences,
        loaded: true,
        saveFailed: state.saveFailed,
        applyFailed: !accepted,
        revision: _revision,
      );
      return accepted;
    } catch (_) {
      if (ref.mounted && epoch == _epoch) {
        _applied = preferences;
        _applyAccepted = false;
        state = ReminderAlerts(
          preferences: state.preferences,
          loaded: true,
          saveFailed: state.saveFailed,
          applyFailed: true,
          revision: _revision,
        );
      }
      return false;
    }
  }
}
