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
  bool _saving = false;
  bool _changed = false;
  @override
  AppearancePreferences build() {
    final store = ref.watch(recordStoreProvider).value;
    if (store != null) {
      Future.microtask(() async {
        try {
          final raw = await store.readSetting('appearance');
          if (raw == null || !ref.mounted || _changed) return;
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
          if (ref.mounted) ref.read(appearanceErrorProvider.notifier).set(true);
        }
      });
    }
    return const AppearancePreferences();
  }

  Future<void> _save(AppearancePreferences next) async {
    if (_saving) return;
    _saving = true;
    _changed = true;
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
      if (ref.mounted) {
        state = previous;
        ref.read(appearanceErrorProvider.notifier).set(true);
      }
    } finally {
      _saving = false;
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
