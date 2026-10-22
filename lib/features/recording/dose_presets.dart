import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_lock.dart';
import '../../app/storage.dart';
import '../../data/record_store.dart';
import '../stock/stock_providers.dart' show stockDecimal;

typedef DosePresetOwner = ({String personId, String itemId});

/// A reusable entered quantity, never a rounded strength equivalent or advice.
final class DosePreset {
  DosePreset(String text, this.unit)
    : text = ExactQuantity.parse(stockDecimal(text)).canonical {
    if (unit.trim().isEmpty) throw const FormatException('preset_unit');
  }
  final String text, unit;
  String get identity => '$text\u0000$unit';
  Map<String, String> toJson() => {'amount': text, 'unit': unit};
}

List<DosePreset> scheduleDosePresets(DailyTiming timing) {
  final amounts = switch (timing) {
    AsNeeded() => const <PlannedAmount>[],
    DailyCount(:final amount) => [amount],
    DailySlots(:final slots) => [for (final slot in slots) slot.amount],
    MixedDailyCount(:final amount, :final slots) => [
      amount,
      for (final slot in slots) slot.amount,
    ],
    DailyWindows(:final windows) => [
      for (final window in windows) window.amount,
    ],
    ElapsedInterval(:final amount) => [amount],
  };
  final seen = <String>{};
  return [
    for (final amount in amounts)
      if (seen.add('${amount.quantity.canonical}\u0000${amount.unit}'))
        DosePreset(amount.enteredText, amount.unit),
  ];
}

final dosePresetPlanProvider = StreamProvider.autoDispose
    .family<List<SavedDailyPlan>, DosePresetOwner>(retry: (_, _) => null, (
      ref,
      owner,
    ) async* {
      yield* (await ref.watch(recordStoreProvider.future)).watchDailyPlans(
        scope: FeedScope.person(owner.personId),
        itemId: owner.itemId,
        limit: 2,
      );
    });

class DosePresetState {
  const DosePresetState({
    this.values = const [],
    this.loading = false,
    this.saving = false,
    this.failed = false,
    this.readFailed = false,
  });
  final List<DosePreset> values;
  final bool loading, saving, failed, readFailed;
}

final dosePresetsProvider = NotifierProvider.autoDispose
    .family<DosePresetController, DosePresetState, DosePresetOwner>(
      DosePresetController.new,
    );

typedef DosePresetWrite = ({
  RecordStore store,
  String key,
  String value,
  bool Function() canCommit,
});
final dosePresetWriterProvider =
    Provider<Future<void> Function(DosePresetWrite)>(
      (ref) =>
          (write) => write.store.writeSetting(
            write.key,
            write.value,
            canCommit: write.canCommit,
          ),
    );

/// Settings live inside the encrypted database and its existing full backup.
/// Store replacement and locking fence delayed writes before publication.
class DosePresetController extends Notifier<DosePresetState> {
  DosePresetController(this.owner);
  final DosePresetOwner owner;
  static const limit = 8;
  String get storageKey => 'dose_presets:${owner.personId}:${owner.itemId}';
  int _epoch = 0;
  Object _authority = Object();
  Object get authority => _authority;
  bool actionCurrent(Object token) =>
      ref.mounted &&
      identical(token, _authority) &&
      !ref.read(appLockProvider).locked;
  bool _saving = false;
  Completer<void>? _settled;

  @override
  DosePresetState build() {
    _authority = Object();
    final locked = ref.watch(appLockProvider.select((state) => state.locked));
    final record = ref.watch(recordStoreProvider);
    final store = record.isLoading || record.hasError ? null : record.value;
    final epoch = ++_epoch;
    if (store != null && !locked) {
      scheduleMicrotask(() async {
        try {
          while (_saving && ref.mounted && epoch == _epoch) {
            await _settled!.future;
          }
          if (!ref.mounted || epoch != _epoch) return;
          final raw = await store.readSetting(storageKey);
          final values = <DosePreset>[];
          if (raw != null) {
            final decoded = jsonDecode(raw) as List<dynamic>;
            if (decoded.length > limit) throw const FormatException('presets');
            final seen = <String>{};
            for (final entry in decoded) {
              final map = entry as Map<String, dynamic>;
              final preset = DosePreset(
                map['amount'] as String,
                map['unit'] as String,
              );
              if (!seen.add(preset.identity)) {
                throw const FormatException('presets');
              }
              values.add(preset);
            }
          }
          if (ref.mounted && epoch == _epoch) {
            state = DosePresetState(values: List.unmodifiable(values));
          }
        } catch (_) {
          if (ref.mounted && epoch == _epoch) {
            state = const DosePresetState(failed: true, readFailed: true);
          }
        }
      });
    }
    return DosePresetState(loading: true, saving: _saving);
  }

  Future<void> add(DosePreset preset) async {
    if (state.values.length >= limit ||
        state.values.any((p) => p.identity == preset.identity)) {
      return;
    }
    await _save([...state.values, preset]);
  }

  Future<void> remove(DosePreset preset) => _save([
    for (final value in state.values)
      if (value.identity != preset.identity) value,
  ]);

  /// Replaces one saved amount in place. The order and the eight-preset bound
  /// stay unchanged. An unsupported unit, a different preset with the same
  /// exact identity, a locked app or a replaced dataset never reaches storage.
  Future<bool> replace(
    DosePreset previous,
    DosePreset next, {
    required Set<String> allowedUnits,
    bool Function()? canCommit,
  }) async {
    if (_saving ||
        state.loading ||
        ref.read(appLockProvider).locked ||
        canCommit?.call() == false) {
      return false;
    }
    final index = state.values.indexWhere(
      (value) => value.identity == previous.identity,
    );
    if (index < 0 || !allowedUnits.contains(next.unit)) return false;
    for (var i = 0; i < state.values.length; i++) {
      if (i != index && state.values[i].identity == next.identity) return false;
    }
    if (next.identity == previous.identity) return true;
    // A failed write left the previous stored list intact. Let the edit dialog
    // retry the same replacement without forcing a full settings reload.
    if (state.failed && !state.readFailed) {
      state = DosePresetState(values: state.values);
    }
    final values = [...state.values]..[index] = next;
    return _save(values, canCommit: canCommit);
  }

  Future<bool> _save(
    List<DosePreset> values, {
    bool Function()? canCommit,
  }) async {
    if (_saving ||
        state.loading ||
        state.failed ||
        ref.read(appLockProvider).locked ||
        canCommit?.call() == false) {
      return false;
    }
    final record = ref.read(recordStoreProvider);
    final store = record.isLoading || record.hasError ? null : record.value;
    if (store == null) return false;
    final previous = state.values, epoch = ++_epoch;
    final settled = _settled = Completer<void>();
    final lease = ref.keepAlive();
    _saving = true;
    state = DosePresetState(values: previous, saving: true);
    try {
      await ref.read(dosePresetWriterProvider)((
        store: store,
        key: storageKey,
        value: jsonEncode([for (final value in values) value.toJson()]),
        canCommit: () {
          if (!ref.mounted ||
              epoch != _epoch ||
              ref.read(appLockProvider).locked ||
              canCommit?.call() == false) {
            return false;
          }
          final current = ref.read(recordStoreProvider);
          return !current.isLoading &&
              !current.hasError &&
              identical(current.value, store);
        },
      ));
      if (ref.mounted && epoch == _epoch) {
        state = DosePresetState(values: List.unmodifiable(values));
      }
      return true;
    } catch (_) {
      if (ref.mounted && epoch == _epoch) {
        state = DosePresetState(values: previous, failed: true);
      }
      return false;
    } finally {
      _saving = false;
      _settled = null;
      if (ref.mounted && epoch == _epoch && state.saving) {
        state = DosePresetState(values: state.values, failed: state.failed);
      }
      settled.complete();
      lease.close();
    }
  }
}
