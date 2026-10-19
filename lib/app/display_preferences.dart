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

class DisplayPreferencesController extends Notifier<DisplayPreferences> {
  int _epoch = 0;
  @override
  DisplayPreferences build() {
    final store = ref.watch(recordStoreProvider).value;
    final epoch = ++_epoch;
    scheduleMicrotask(() async {
      if (store == null) return;
      try {
        final raw = await store.readSetting('display');
        if (!ref.mounted || epoch != _epoch || raw == null) return;
        final parsed = jsonDecode(raw) as Map<String, dynamic>;
        state = DisplayPreferences(
          timeFormat: timeFormatFromStorage(parsed['timeFormat'] as String?),
        );
      } catch (_) {
        if (ref.mounted && epoch == _epoch) {
          state = const DisplayPreferences(failed: true);
        }
      }
    });
    return const DisplayPreferences();
  }

  Future<void> setTimeFormat(TimeFormat value) async {
    if (state.busy || ref.read(appLockProvider).locked) return;
    final previous = state.timeFormat, epoch = ++_epoch;
    state = DisplayPreferences(timeFormat: value, busy: true);
    try {
      await (await ref.read(recordStoreProvider.future)).writeSetting(
        'display',
        jsonEncode({'timeFormat': value.storageValue}),
      );
      if (ref.mounted && epoch == _epoch) {
        state = DisplayPreferences(timeFormat: value);
      }
    } catch (_) {
      if (ref.mounted && epoch == _epoch) {
        state = DisplayPreferences(timeFormat: previous, failed: true);
      }
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
