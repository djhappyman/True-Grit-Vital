import 'package:flutter/material.dart'
    as m
    show DateTimeRange, MaterialLocalizations;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../app/app_lock.dart';
import '../../app/storage.dart';
import '../../domain/scheduling/daily_plan.dart' show CivilDate;
import '../../l10n/app_localizations.dart';
import '../vital_ui.dart';

/// Two civil endpoints edited together with the canonical range calendar.
/// Exclusive upper bounds are converted using civil days, never 24-hour spans.
/// Each endpoint can still be cleared independently for open-ended filters.
class VitalDateRangeField extends ConsumerStatefulWidget {
  const VitalDateRangeField({
    super.key,
    required this.start,
    required this.end,
    required this.startLabel,
    required this.endLabel,
    this.enabled = true,
    this.endExclusive = false,
    this.textOnly = false,
    this.error,
  });
  final TextEditingController start, end;
  final String startLabel, endLabel;
  final bool enabled, endExclusive, textOnly;
  final String? error;
  @override
  ConsumerState<VitalDateRangeField> createState() =>
      _VitalDateRangeFieldState();
}

class _VitalDateRangeFieldState extends ConsumerState<VitalDateRangeField> {
  bool opening = false;
  Future<void> _pick(VitalDatePickerRangeEndpoint endpoint) async {
    if (!widget.enabled || opening || ref.read(appLockProvider).locked) return;
    final lock = ref.read(appLockProvider);
    final generation = ref.read(recordStoreProvider).value?.generation;
    final start = widget.start, end = widget.end;
    final oldStart = start.text, oldEnd = end.text;
    CivilDate? first, last;
    try {
      first = CivilDate.parse(oldStart);
    } catch (_) {}
    try {
      last = CivilDate.parse(oldEnd);
      if (widget.endExclusive) last = last.addDays(-1);
    } catch (_) {}
    final initial = first != null && last != null && first.compareTo(last) <= 0
        ? m.DateTimeRange(start: first.calendarValue, end: last.calendarValue)
        : null;
    setState(() => opening = true);
    try {
      final range = await showVitalDateRangePicker(
        context: context,
        initialRange: initial,
        initialDisplayDate: endpoint == VitalDatePickerRangeEndpoint.start
            ? first?.calendarValue ?? last?.calendarValue
            : last?.calendarValue ?? first?.calendarValue,
        firstDate: DateTime(1),
        lastDate: DateTime(9999, 12, widget.endExclusive ? 30 : 31),
        selectionBehavior:
            VitalDatePickerRangeSelectionBehavior.editActiveEndpoint,
        activeEndpoint: endpoint,
      );
      if (!mounted ||
          range == null ||
          !widget.enabled ||
          !identical(widget.start, start) ||
          !identical(widget.end, end) ||
          start.text != oldStart ||
          end.text != oldEnd ||
          !identical(ref.read(appLockProvider), lock) ||
          ref.read(appLockProvider).locked ||
          ref.read(recordStoreProvider).value?.generation != generation) {
        return;
      }
      final from = CivilDate.fromDateTime(range.start);
      final through = CivilDate.fromDateTime(range.end);
      // Validate both values before publishing either controller change.
      final upper = widget.endExclusive ? through.addDays(1) : through;
      start.text = from.toString();
      end.text = upper.toString();
    } finally {
      if (mounted) setState(() => opening = false);
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.textOnly)
          for (final endpoint in VitalDatePickerRangeEndpoint.values)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: Text(
                      endpoint == VitalDatePickerRangeEndpoint.start
                          ? widget.startLabel
                          : widget.endLabel,
                      style: VitalType.body,
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 3,
                    child: ValueListenableBuilder<TextEditingValue>(
                      valueListenable:
                          endpoint == VitalDatePickerRangeEndpoint.start
                          ? widget.start
                          : widget.end,
                      builder: (context, value, _) => VitalControlStyle(
                        quiet: true,
                        child: Button(
                          style: ButtonVariance.ghost,
                          onPressed: widget.enabled && !opening
                              ? () => _pick(endpoint)
                              : null,
                          child: DefaultTextStyle.merge(
                            style: VitalType.body,
                            child: Text(
                              _label(context, value.text),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            )
        else ...[
          for (final endpoint in VitalDatePickerRangeEndpoint.values) ...[
            Text(
              endpoint == VitalDatePickerRangeEndpoint.start
                  ? widget.startLabel
                  : widget.endLabel,
              style: VitalType.label,
            ),
            const SizedBox(height: 8),
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: endpoint == VitalDatePickerRangeEndpoint.start
                  ? widget.start
                  : widget.end,
              builder: (context, value, _) => Row(
                children: [
                  Expanded(
                    child: VitalButton.secondary(
                      alignment: AlignmentDirectional.centerStart,
                      multiline: true,
                      leading: const Icon(LucideIcons.calendarRange),
                      onPressed: widget.enabled && !opening
                          ? () => _pick(endpoint)
                          : null,
                      child: Text(_label(context, value.text)),
                    ),
                  ),
                  if (value.text.isNotEmpty)
                    VitalIconButton(
                      label: AppLocalizations.of(context).clear,
                      icon: LucideIcons.x,
                      onPressed:
                          widget.enabled &&
                              !opening &&
                              !ref.read(appLockProvider).locked
                          ? () =>
                                (endpoint == VitalDatePickerRangeEndpoint.start
                                        ? widget.start
                                        : widget.end)
                                    .clear()
                          : null,
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
        ],
        if (widget.error != null)
          Semantics(
            liveRegion: true,
            child: Text(widget.error!, style: VitalType.metadata),
          ),
      ],
    ),
  );

  String _label(BuildContext context, String raw) {
    if (raw.isEmpty) return AppLocalizations.of(context).pickerDate;
    try {
      return widget.textOnly
          ? DateFormat.yMMMd(Localizations.localeOf(context).toString())
                .format(CivilDate.parse(raw).calendarValue)
          : m.MaterialLocalizations.of(context)
                .formatMediumDate(CivilDate.parse(raw).calendarValue);
    } catch (_) {
      return raw;
    }
  }
}
