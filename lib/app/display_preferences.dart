import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart' show MaterialLocalizations;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../domain/history/history.dart';
import '../domain/scheduling/daily_plan.dart' show WallTime;
import '../l10n/app_localizations.dart';
import '../ui/vital_ui.dart';
import 'app_lock.dart';
import 'device_zone.dart';
import 'storage.dart';

class DisplayPreferences {
  const DisplayPreferences({
    this.timeFormat = TimeFormat.system,
    this.busy = false,
    this.failed = false,
  });
  final TimeFormat timeFormat;
  final bool busy, failed;
}

final displayPreferencesProvider =
    NotifierProvider<DisplayPreferencesController, DisplayPreferences>(
      DisplayPreferencesController.new,
    );

/// Writes the persisted display preference through the current record store;
/// tests override this seam for deterministic write outcomes.
final displayPreferenceWriterProvider = Provider<Future<void> Function(String)>(
  (ref) => (value) async {
    final store = await ref.read(recordStoreProvider.future);
    await store.writeSetting('display', value);
  },
);

class DisplayPreferencesController extends Notifier<DisplayPreferences> {
  // The notifier instance survives a record-store replacement (restore),
  // so delayed work from a replaced dataset is fenced by epoch and writes
  // serialise on the shared notifier: a mid-flight rebuild resets state.busy
  // without retiring the store the in-flight write already touches.
  int _epoch = 0;
  bool _saving = false;
  Completer<void>? _saveSettled;

  @override
  DisplayPreferences build() {
    // Only a settled, healthy record store is read: pending rebuilds and
    // failed swaps still surface the previously retired store in .value, and
    // reading it races store close (see AppearanceController). A settled
    // rebuild follows when the record surface resolves.
    final record = ref.watch(recordStoreProvider);
    final store = (record.isLoading || record.hasError) ? null : record.value;
    final epoch = ++_epoch;
    if (store != null) {
      scheduleMicrotask(() async {
        try {
          // A read issued while a publication is still in flight would
          // return the value that write is about to replace; wait for it,
          // then draw freshly from the store.
          while (_saving && ref.mounted && epoch == _epoch) {
            final settled = _saveSettled;
            if (settled == null) break;
            await settled.future;
          }
          if (!ref.mounted || epoch != _epoch) return;
          final raw = await store.readSetting('display');
          if (!ref.mounted || epoch != _epoch) return;
          state = raw == null
              ? const DisplayPreferences()
              : DisplayPreferences(
                  timeFormat: timeFormatFromStorage(
                    (jsonDecode(raw) as Map<String, dynamic>)['timeFormat']
                        as String?,
                  ),
                );
        } catch (_) {
          if (ref.mounted && epoch == _epoch) {
            state = const DisplayPreferences(failed: true);
          }
        }
      });
    }
    return DisplayPreferences(busy: _saving);
  }

  Future<void> setTimeFormat(TimeFormat value) async {
    if (_saving || ref.read(appLockProvider).locked) return;
    final previous = state.timeFormat, epoch = ++_epoch;
    final settled = _saveSettled = Completer<void>();
    _saving = true;
    state = DisplayPreferences(timeFormat: value, busy: true);
    try {
      await ref.read(displayPreferenceWriterProvider)(
        jsonEncode({'timeFormat': value.storageValue}),
      );
      if (ref.mounted && epoch == _epoch) {
        state = DisplayPreferences(timeFormat: value);
      }
    } catch (_) {
      if (ref.mounted && epoch == _epoch) {
        state = DisplayPreferences(timeFormat: previous, failed: true);
      }
    } finally {
      _saving = false;
      _saveSettled = null;
      // This is the only in-flight write. Retire its busy indicator even when
      // a rebuild changed the epoch, preserving the current value and error.
      if (ref.mounted && state.busy) {
        state = DisplayPreferences(
          timeFormat: state.timeFormat,
          failed: state.failed,
        );
      }
      settled.complete();
    }
  }
}

final displayZoneProvider = Provider<String>(
  (ref) => ref.watch(observedDeviceZoneProvider).value?.zoneId ?? 'UTC',
);
DisplayTimeFormatter displayFormatter(
  BuildContext context,
  TimeFormat preference,
) => DisplayTimeFormatter(
  localizations: Localizations.of<MaterialLocalizations>(
    context,
    MaterialLocalizations,
  )!,
  preference: preference,
  systemUses24Hour: MediaQuery.alwaysUse24HourFormatOf(context),
);

/// Formats a displayed instant using the shared preference and the shown zone.
/// This never changes date/time entry, a saved UTC value or a schedule anchor.
String displayStamp(
  BuildContext context,
  WidgetRef ref,
  DateTime instant, {
  String? zoneId,
  bool includeSeconds = false,
}) {
  final preference = ref.watch(displayPreferencesProvider).timeFormat;
  final zone = zoneId ?? ref.watch<String>(displayZoneProvider);
  return displayFormatter(context, preference).format(
    DisplayTime().instant(instant, zone),
    includeSeconds: includeSeconds,
    includeOffset: true,
  );
}

/// Display-only wall time; schedule and actual-time inputs retain HH:MM.
String displayWallTime(BuildContext context, WidgetRef ref, WallTime time) =>
    displayFormatter(
      context,
      ref.watch(displayPreferencesProvider).timeFormat,
    ).wallTime(time.hour, time.minute);

class TimeFormatSettings extends ConsumerWidget {
  const TimeFormatSettings({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context),
        state = ref.watch(displayPreferencesProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text(
            t.timeFormat,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        Text(t.timeFormatHelp),
        if (state.failed)
          Semantics(liveRegion: true, child: Text(t.displaySaveFailure)),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final (value, label) in [
              (TimeFormat.system, t.timeSystem),
              (TimeFormat.h12, t.time12),
              (TimeFormat.h24, t.time24),
            ])
              MergeSemantics(
                child: Semantics(
                  selected: state.timeFormat == value,
                  child: state.timeFormat == value
                      ? VitalButton(
                          onPressed: state.busy
                              ? null
                              : () => ref
                                    .read(displayPreferencesProvider.notifier)
                                    .setTimeFormat(value),
                          child: Text(label),
                        )
                      : VitalButton.secondary(
                          onPressed: state.busy
                              ? null
                              : () => ref
                                    .read(displayPreferencesProvider.notifier)
                                    .setTimeFormat(value),
                          child: Text(label),
                        ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
