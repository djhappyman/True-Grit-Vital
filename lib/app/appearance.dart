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

  @override
  AppearancePreferences build() {
    // During a record-store reload Riverpod keeps the previous AsyncValue,
    // whose store the provider has already retired: reading it races with
    // close and would raise a current-generation error spuriously. Only
    // read a settled store; a settled rebuild follows when it arrives.
    final record = ref.watch(recordStoreProvider);
    final store = record.isReloading ? null : record.value;
    final epoch = ++_epoch;
    if (store != null) {
      Future.microtask(() async {
        try {
          final raw = await store.readSetting('appearance');
          if (raw == null || !ref.mounted || epoch != _epoch) return;
          final data = jsonDecode(raw) as Map<String, dynamic>;
          state = AppearancePreferences(
            mode: ThemeMode.values.firstWhere(
              (m) => m.name == data['mode'],
              orElse: () => ThemeMode.system,
            ),
            opaque: data['opaque'] == true,
            reduceMotion: data['reduceMotion'] == true,
          );
        } catch (_) {
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
      // While this write is in flight no newer write can start because
      // _saving serialises publications on the shared notifier instance, so
      // clearing busy here retires this generation's own indicator.
      if (ref.mounted) ref.read(appearanceBusyProvider.notifier).set(false);
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
