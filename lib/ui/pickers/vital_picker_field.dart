import 'package:flutter/material.dart'
    as m
    show TimeOfDay, MaterialLocalizations;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../app/app_lock.dart';
import '../../app/device_zone.dart';
import '../../app/display_preferences.dart';
import '../../app/storage.dart';
import '../../domain/scheduling/iana_clock.dart';
import '../../domain/scheduling/daily_plan.dart';
import '../../domain/history/display_time.dart';
import '../../l10n/app_localizations.dart';
import '../vital_ui.dart';

enum VitalPickerKind {
  date,
  week,
  month,
  time,
  instant,
  flexibleDate,
  partialDate,
}

/// A civil date, wall time or explicit instant using the canonical pickers.
/// Controller values retain the editor's existing validation/storage format.
class VitalPickerField extends ConsumerStatefulWidget {
  const VitalPickerField({
    super.key,
    required this.controller,
    required this.label,
    required this.kind,
    this.enabled = true,
    this.zoneId,
    this.focusNode,
  });
  final TextEditingController controller;
  final String label;
  final VitalPickerKind kind;
  final bool enabled;
  final String? zoneId;
  final FocusNode? focusNode;
  @override
  ConsumerState<VitalPickerField> createState() => _VitalPickerFieldState();
}

class _VitalPickerFieldState extends ConsumerState<VitalPickerField> {
  String? failure;
  bool opening = false;
  Future<void> _pick({String? precision}) async {
    if (!widget.enabled || opening) return;
    final t = AppLocalizations.of(context);
    final controller = widget.controller, previous = widget.controller.text;
    final lock = ref.read(appLockProvider);
    final generation = ref.read(recordStoreProvider).value?.generation;
    if (lock.locked) return;
    final zone =
        widget.zoneId ?? ref.read(observedDeviceZoneProvider).value?.zoneId;
    setState(() {
      opening = true;
      failure = null;
    });
    String? result;
    try {
      if (widget.kind == VitalPickerKind.partialDate &&
          precision == 'unknown') {
        result = 'unknown';
      } else {
        switch (widget.kind) {
          case VitalPickerKind.week:
            DateTime? anchor;
            try {
              anchor = CivilDate.parse(previous).calendarValue;
            } catch (_) {}
            final range = await showVitalDateRangePicker(
              context: context,
              title: widget.label,
              weekSelection: true,
              initialDisplayDate: anchor,
              firstDate: DateTime(1),
              lastDate: DateTime(9999, 12, 31),
            );
            if (range != null) {
              result = CivilDate.fromDateTime(range.start).toString();
            }
          case VitalPickerKind.date:
          case VitalPickerKind.month:
          case VitalPickerKind.partialDate:
            DateTime? initial;
            final selectedPrecision = widget.kind == VitalPickerKind.month
                ? 'month'
                : precision ?? _precision(previous);
            final sourceDate = previous.length == 4
                ? '$previous-01-01'
                : previous.length == 7
                ? '$previous-01'
                : previous;
            try {
              initial = CivilDate.parse(sourceDate).calendarValue;
            } catch (_) {
              /* Invalid drafts remain editable. */
            }
            final selected = await showVitalDatePicker(
              context: context,
              title: widget.label,
              initialDate: initial,
              firstDate: DateTime(1),
              lastDate: DateTime(9999, 12, 31),
              granularity: selectedPrecision == 'year'
                  ? VitalDatePickerGranularity.year
                  : selectedPrecision == 'month'
                  ? VitalDatePickerGranularity.month
                  : VitalDatePickerGranularity.day,
            );
            if (selected != null) {
              final raw = CivilDate.fromDateTime(selected).toString();
              result = widget.kind == VitalPickerKind.month
                  ? '${raw.substring(0, 7)}-01'
                  : selectedPrecision == 'year'
                  ? raw.substring(0, 4)
                  : selectedPrecision == 'month'
                  ? raw.substring(0, 7)
                  : raw;
            }
          case VitalPickerKind.time:
            final match = RegExp(r'^(\d{2}):(\d{2})$').firstMatch(previous);
            final initial =
                match != null &&
                    int.parse(match[1]!) < 24 &&
                    int.parse(match[2]!) < 60
                ? m.TimeOfDay(
                    hour: int.parse(match[1]!),
                    minute: int.parse(match[2]!),
                  )
                : null;
            final selected = await showVitalTimePicker(
              context: context,
              title: widget.label,
              initialTime: initial,
            );
            if (selected != null) {
              result =
                  '${selected.hour.toString().padLeft(2, '0')}:${selected.minute.toString().padLeft(2, '0')}';
            }
          case VitalPickerKind.instant:
          case VitalPickerKind.flexibleDate:
            if (zone == null && widget.kind == VitalPickerKind.instant) {
              throw const FormatException('zone');
            }
            DateTime? initial;
            try {
              if (!RegExp(r'(Z|[+-]\d{2}:\d{2})$').hasMatch(previous)) {
                throw const FormatException();
              }
              final existing = DateTime.parse(previous).toUtc();
              initial = zone == null
                  ? null
                  : DisplayTime().instant(existing, zone).wallValue;
            } catch (_) {
              /* No implicit timezone is assigned to a draft. */
            }
            DateTime? selected;
            if (widget.kind == VitalPickerKind.flexibleDate) {
              if (initial == null) {
                try {
                  initial = CivilDate.parse(previous).calendarValue;
                } catch (_) {}
              }
              final selection = await showVitalDateTimeSelectionPicker(
                context: context,
                title: widget.label,
                initialDateTime: initial,
                initialHasTime: previous.contains('T'),
                firstDate: DateTime(1),
                lastDate: DateTime(9999, 12, 31),
              );
              if (selection == null) break;
              if (selection.time == null) {
                result = CivilDate.fromDateTime(selection.date).toString();
                break;
              }
              selected = selection.dateTime;
            } else {
              selected = await showVitalDateTimePicker(
                context: context,
                title: widget.label,
                initialDateTime: initial,
                firstDate: DateTime(1),
                lastDate: DateTime(9999, 12, 31),
              );
            }
            if (selected == null) break;
            if (zone == null) throw const FormatException('zone');
            final candidates = IanaClock().candidates(
              CivilDate.fromDateTime(selected),
              WallTime(selected.hour, selected.minute),
              zone,
            );
            if (candidates.isEmpty) throw const FormatException('missing_time');
            if (candidates.length == 1) {
              result = candidates.single.toIso8601String();
            } else if (mounted) {
              final chosen = await showVitalDialog<DateTime>(
                context: context,
                builder: (dialogContext) => VitalDialog(
                  title: Text(t.pickerDateTime),
                  content: Text(t.ambiguousTime),
                  actions: [
                    for (final candidate in candidates)
                      VitalButton.secondary(
                        onPressed: () =>
                            Navigator.of(dialogContext).pop(candidate),
                        child: Text(
                          displayFormatter(
                            context,
                            ref.read(displayPreferencesProvider).timeFormat,
                          ).format(
                            DisplayTime().instant(candidate, zone),
                            includeOffset: true,
                          ),
                        ),
                      ),
                    VitalButton.secondary(
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      child: Text(t.cancel),
                    ),
                  ],
                ),
              );
              if (chosen != null) result = chosen.toIso8601String();
            }
            // Keeping the same minute retains the existing seconds and offset.
            if (result != null &&
                candidates.length == 1 &&
                initial != null &&
                selected.year == initial.year &&
                selected.month == initial.month &&
                selected.day == initial.day &&
                selected.hour == initial.hour &&
                selected.minute == initial.minute) {
              result = previous;
            }
        }
      }
      if (result != null &&
          mounted &&
          widget.enabled &&
          identical(widget.controller, controller) &&
          (widget.kind != VitalPickerKind.instant &&
                  widget.kind != VitalPickerKind.flexibleDate ||
              (widget.zoneId ??
                      ref.read(observedDeviceZoneProvider).value?.zoneId) ==
                  zone) &&
          controller.text == previous &&
          identical(ref.read(appLockProvider), lock) &&
          !ref.read(appLockProvider).locked &&
          ref.read(recordStoreProvider).value?.generation == generation) {
        controller.text = result;
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => failure = widget.kind == VitalPickerKind.instant && zone == null
              ? t.planZoneUnavailable
              : t.timeInvalid,
        );
      }
    } finally {
      if (mounted) setState(() => opening = false);
    }
  }

  String _display(BuildContext context) {
    final raw = widget.controller.text;
    final t = AppLocalizations.of(context);
    if (widget.kind == VitalPickerKind.partialDate &&
        raw.toLowerCase() == 'unknown') {
      return t.supportingUnknown;
    }
    if (raw.isEmpty) {
      return widget.kind == VitalPickerKind.time
          ? t.pickerTime
          : widget.kind == VitalPickerKind.instant
          ? t.pickerDateTime
          : t.pickerDate;
    }
    try {
      if (widget.kind == VitalPickerKind.date ||
          widget.kind == VitalPickerKind.month ||
          widget.kind == VitalPickerKind.week ||
          widget.kind == VitalPickerKind.flexibleDate && !raw.contains('T')) {
        final date = CivilDate.parse(raw);
        final local = Localizations.of<m.MaterialLocalizations>(
          context,
          m.MaterialLocalizations,
        )!;
        return widget.kind == VitalPickerKind.month
            ? local.formatMonthYear(date.calendarValue)
            : local.formatMediumDate(date.calendarValue);
      }
      if (widget.kind == VitalPickerKind.time) {
        final match = RegExp(r'^(\d{2}):(\d{2})$').firstMatch(raw)!;
        return displayWallTime(
          context,
          ref,
          WallTime(int.parse(match[1]!), int.parse(match[2]!)),
        );
      }
      return displayStamp(
        context,
        ref,
        DateTime.parse(raw).toUtc(),
        zoneId: widget.zoneId,
      );
    } catch (_) {
      return raw;
    }
  }

  String _precision(String raw) => raw.toLowerCase() == 'unknown'
      ? 'unknown'
      : raw.length == 4
      ? 'year'
      : raw.length == 7
      ? 'month'
      : 'day';

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (widget.kind == VitalPickerKind.partialDate) ...[
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: widget.controller,
          builder: (context, _, _) => VitalSelect<String>(
            label: widget.label,
            value: _precision(widget.controller.text),
            values: const ['day', 'month', 'year', 'unknown'],
            labelOf: (v) => switch (v) {
              'month' => AppLocalizations.of(context).pickerMonth,
              'year' => AppLocalizations.of(context).pickerYearUnit,
              'unknown' => AppLocalizations.of(context).supportingUnknown,
              _ => AppLocalizations.of(context).supportingDay,
            },
            onChanged: (v) => _pick(precision: v),
            enabled: widget.enabled && !opening,
          ),
        ),
        const SizedBox(height: 8),
      ],
      ValueListenableBuilder<TextEditingValue>(
        valueListenable: widget.controller,
        builder: (context, _, _) => Row(
          children: [
            Expanded(
              child: VitalButton.secondary(
                focusNode: widget.focusNode,
                alignment: AlignmentDirectional.centerStart,
                multiline: true,
                leading: Icon(
                  widget.kind == VitalPickerKind.time
                      ? LucideIcons.clock3
                      : LucideIcons.calendarDays,
                ),
                onPressed: widget.enabled && !opening ? _pick : null,
                child: Text(_display(context)),
              ),
            ),
            if (widget.controller.text.isNotEmpty)
              VitalIconButton(
                label: AppLocalizations.of(context).clear,
                icon: LucideIcons.x,
                onPressed: widget.enabled && !opening
                    ? () {
                        widget.controller.clear();
                        setState(() => failure = null);
                      }
                    : null,
              ),
          ],
        ),
      ),
      if (failure != null)
        Semantics(
          liveRegion: true,
          child: Text(failure!, style: VitalType.metadata),
        ),
    ],
  );
}
