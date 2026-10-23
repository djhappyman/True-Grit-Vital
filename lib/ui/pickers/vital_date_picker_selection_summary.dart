part of 'vital_date_picker.dart';

class _SelectionSummary extends StatelessWidget {
  const _SelectionSummary({
    required this.mode,
    required this.title,
    required this.selectedDate,
    required this.selectedTime,
    required this.rangeStart,
    required this.rangeEnd,
    required this.onClear,
    required this.valueBuilder,
  });

  final _VitalDatePickerMode mode;
  final String title;
  final DateTime? selectedDate;
  final TimeOfDay? selectedTime;
  final DateTime? rangeStart;
  final DateTime? rangeEnd;
  final VoidCallback? onClear;
  final String? Function(DateTime? date)? valueBuilder;

  @override
  Widget build(BuildContext context) {
    final scheme = VitalPickerTheme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.onSurface.withValues(alpha: 0.045),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: VitalPickerTheme.of(context).textTheme.labelMedium
                        ?.copyWith(
                          color: scheme.onSurfaceVariant,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    _value(context),
                    key: const ValueKey('vital_date_picker_summary_value'),
                    style: VitalPickerTheme.of(context).textTheme.bodyMedium
                        ?.copyWith(
                          color: _hasSelection
                              ? scheme.primary
                              : scheme.onSurface,
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                ],
              ),
            ),
            VitalPickerIconButton(
              key: const ValueKey('vital_date_picker_clear'),
              tooltip: AppLocalizations.of(context).clear,
              visualDensity: VisualDensity.compact,
              onPressed: onClear,
              icon: const Icon(LucideIcons.x, size: 18),
            ),
          ],
        ),
      ),
    );
  }

  bool get _hasSelection => switch (mode) {
    _VitalDatePickerMode.single ||
    _VitalDatePickerMode.dateTime => selectedDate != null,
    _VitalDatePickerMode.range => rangeStart != null,
  };

  String _value(BuildContext context) {
    if (mode == _VitalDatePickerMode.single && valueBuilder != null) {
      final custom = valueBuilder!(selectedDate);
      if (custom != null) return custom;
    }
    final localizations = MaterialLocalizations.of(context);
    return switch (mode) {
      _VitalDatePickerMode.single =>
        selectedDate == null
            ? AppLocalizations.of(context).pickerDate
            : localizations.formatMediumDate(selectedDate!),
      _VitalDatePickerMode.dateTime =>
        selectedDate == null
            ? AppLocalizations.of(context).pickerDate
            : selectedTime == null
            ? AppLocalizations.of(context).pickerDateTimeValue(
                localizations.formatMediumDate(selectedDate!),
                AppLocalizations.of(context).pickerTime,
              )
            : AppLocalizations.of(context).pickerDateTimeValue(
                localizations.formatMediumDate(selectedDate!),
                localizations.formatTimeOfDay(
                  selectedTime!,
                  alwaysUse24HourFormat: vitalPickerUses24Hour(context),
                ),
              ),
      _VitalDatePickerMode.range => switch ((rangeStart, rangeEnd)) {
        (null, _) => AppLocalizations.of(context).pickerRangeStart,
        (final start?, null) => AppLocalizations.of(
          context,
        ).pickerRangePending(localizations.formatMediumDate(start)),
        (final start?, final end?) =>
          AppLocalizations.of(context).pickerRangeValue(
            localizations.formatMediumDate(start),
            localizations.formatMediumDate(end),
          ),
      },
    };
  }
}

class _DatePickerTimeAction extends StatelessWidget {
  const _DatePickerTimeAction({required this.value, required this.onPressed});

  final TimeOfDay? value;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = VitalPickerTheme.of(context);
    final scheme = theme.colorScheme;
    final formattedTime = value == null
        ? AppLocalizations.of(context).pickerTime
        : MaterialLocalizations.of(context).formatTimeOfDay(
            value!,
            alwaysUse24HourFormat: vitalPickerUses24Hour(context),
          );
    return Semantics(
      button: true,
      enabled: onPressed != null,
      label: AppLocalizations.of(context).pickerTimeValue(formattedTime),
      child: VitalPickerTap(
        key: const ValueKey('vital_date_picker_time_button'),
        borderRadius: BorderRadius.circular(18),
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Icon(
                LucideIcons.clock3,
                size: 20,
                color: onPressed == null
                    ? scheme.onSurfaceVariant.withValues(alpha: 0.42)
                    : scheme.primary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  AppLocalizations.of(context).pickerTime,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                formattedTime,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: onPressed == null
                      ? scheme.onSurfaceVariant.withValues(alpha: 0.42)
                      : scheme.primary,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: 4),
              const Icon(LucideIcons.chevronRight, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}
