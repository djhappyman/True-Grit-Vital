import 'dart:async';
import 'dart:convert';

import 'storage.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

class AppearancePreferences {
  const AppearancePreferences({
    this.mode = ThemeMode.system,
    this.opaque = false,
    this.reduceMotion = false,
  });

  final ThemeMode mode;
  final bool opaque;
  final bool reduceMotion;

  AppearancePreferences copyWith({
    ThemeMode? mode,
    bool? opaque,
    bool? reduceMotion,
  }) => AppearancePreferences(
    mode: mode ?? this.mode,
    opaque: opaque ?? this.opaque,
    reduceMotion: reduceMotion ?? this.reduceMotion,
  );

  /// Throws when the persisted value is not a decodable appearance record;
  /// the controller surfaces that as a load failure instead of defaults.
  factory AppearancePreferences.decode(String raw) {
    final data = jsonDecode(raw) as Map<String, dynamic>;
    return AppearancePreferences(
      mode: ThemeMode.values.firstWhere(
        (m) => m.name == data['mode'],
        orElse: () => ThemeMode.system,
      ),
      opaque: data['opaque'] == true,
      reduceMotion: data['reduceMotion'] == true,
    );
  }
}

final appearanceProvider =
    NotifierProvider<AppearanceController, AppearancePreferences>(
      AppearanceController.new,
    );

final appearanceErrorProvider = NotifierProvider<AppearanceError, bool>(
  AppearanceError.new,
);

class AppearanceError extends Notifier<bool> {
  @override
  bool build() => false;
  void set(bool value) => state = value;
}

final appearanceWriterProvider = Provider<Future<void> Function(String)>(
  (ref) => (value) async {
    final store = await ref.read(recordStoreProvider.future);
    await store.writeSetting('appearance', value);
  },
);
final appearanceBusyProvider = NotifierProvider<AppearanceError, bool>(
  AppearanceError.new,
);

class AppearanceController extends Notifier<AppearancePreferences> {
  // The notifier instance survives a record-store replacement (restore or
  // dataset switch re-invalidates recordStoreProvider and re-runs build()),
  // so completion of any delayed work from the old store must be fenced by
  // an epoch bump; only the newest generation may change preference state,
  // error state or busy state. Saves still serialise on the shared notifier.
  int _epoch = 0;
  bool _saving = false;
  Completer<void>? _saveSettled;

  @override
  AppearancePreferences build() {
    // Gate on the record surface's settled state, not on isReloading:
    // riverpod 3.4.3 (src/core/async_value.dart:86,97) reports isRefreshing
    // for a manual Ref.invalidate/refresh — the actual dataset-swap path
    // (lib/app/restore.dart) — and isReloading only for watch-driven
    // rebuilds. Both pending forms, and a rebuild that ends in an error,
    // retain the previously surfaced store in .value even though the
    // provider's onDispose has already retired it; reading the retained
    // store races against close. Only a settled, healthy store is read;
    // a settled rebuild follows when the surface resolves.
    final record = ref.watch(recordStoreProvider);
    final store = (record.isLoading || record.hasError) ? null : record.value;
    final epoch = ++_epoch;
    if (store != null) {
      Future.microtask(() async {
        try {
          // A read issued while a publication is still in flight would
          // return the value that write is about to replace (or, on
          // failure, the one a rollback restores), and its epoch is the
          // newest one, so the fence alone could not stop it overriding
          // the user edit. Wait for the in-flight publication first, then
          // draw freshly from the store.
          while (_saving && ref.mounted && epoch == _epoch) {
            final settled = _saveSettled;
            if (settled == null) break;
            await settled.future;
          }
          if (!ref.mounted || epoch != _epoch) return;
          final raw = await store.readSetting('appearance');
          if (!ref.mounted || epoch != _epoch) return;
          final next = raw == null
              ? const AppearancePreferences()
              : AppearancePreferences.decode(raw);
          // This load belongs to the current epoch, so any banner left by
          // the store this dataset replaced (a prior failed save, for
          // instance) is retired now that the current dataset supplied its
          // own data, defaulted or persisted. A decodable failure below
          // reaches catch and re-raises its own banner instead.
          ref.read(appearanceErrorProvider.notifier).set(false);
          state = next;
        } catch (_) {
          // A load failure at the current epoch surfaces truthfully; any
          // superseded generation's result stays silent behind the fence.
          if (ref.mounted && epoch == _epoch) {
            ref.read(appearanceErrorProvider.notifier).set(true);
          }
        }
      });
    }
    return const AppearancePreferences();
  }

  Future<void> _save(AppearancePreferences next) async {
    if (_saving) return;
    final settled = Completer<void>();
    _saveSettled = settled;
    _saving = true;
    final epoch = ++_epoch;
    ref.read(appearanceBusyProvider.notifier).set(true);
    final previous = state;
    state = next;
    ref.read(appearanceErrorProvider.notifier).set(false);
    try {
      await ref.read(appearanceWriterProvider)(
        jsonEncode({
          'mode': next.mode.name,
          'opaque': next.opaque,
          'reduceMotion': next.reduceMotion,
        }),
      );
    } catch (_) {
      // A write from a replaced/store-generation edit must not silently
      // discard whatever the current dataset loaded: only the latest
      // generation may roll state back.
      if (ref.mounted && epoch == _epoch) {
        state = previous;
        ref.read(appearanceErrorProvider.notifier).set(true);
      }
    } finally {
      _saving = false;
      _saveSettled = null;
      // While this write is in flight no newer write can start because
      // _saving serialises publications on the shared notifier instance, so
      // clearing busy here retires this generation's own indicator.
      if (ref.mounted) ref.read(appearanceBusyProvider.notifier).set(false);
      settled.complete();
    }
  }

  void setMode(ThemeMode value) => _save(state.copyWith(mode: value));
  void setOpaque(bool value) => _save(state.copyWith(opaque: value));
  void setReduceMotion(bool value) =>
      _save(state.copyWith(reduceMotion: value));
}

// Keep false until G06 supplies measured device/renderer evidence. A package's
// fallback support alone does not validate the application's composed surface.
final glassValidatedProvider = Provider<bool>((ref) => false);

class EffectiveAppearance {
  const EffectiveAppearance({required this.opaque, required this.reduceMotion});
  factory EffectiveAppearance.compose({
    required AppearancePreferences preferences,
    required bool systemReduceMotion,
    required bool systemReduceTransparency,
    required bool glassValidated,
  }) => EffectiveAppearance(
    opaque: preferences.opaque || systemReduceTransparency || !glassValidated,
    reduceMotion: preferences.reduceMotion || systemReduceMotion,
  );

  final bool opaque;
  final bool reduceMotion;
}
