import '../../ui/vital_ui.dart';

import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../data/record_store.dart';
import '../../l10n/app_localizations.dart';
import '../recording/record_pages.dart';

/// Raw fields stay separate from the validated selector so invalid entries and
/// unchosen missing-date policies survive the encrypted ordinary draft.
class CalendarFormFields {
  CalendarFormFields({required CivilDate initialDate})
    : anchor = TextEditingController(text: initialDate.toString());
  String pattern = 'daily', selector = 'date', missing = '';
  final weekdays = <int>{};
  int weekday = 1, ordinal = 1;
  String? error;
  final TextEditingController anchor;
  final interval = TextEditingController(text: '1');
  final day = TextEditingController(text: '1');
  List<TextEditingController> get controllers => [anchor, interval, day];
  Map<String, String> capture() => {
    'calendarPattern': pattern,
    'calendarSelector': selector,
    'calendarMissing': missing,
    'calendarWeekdays': (weekdays.toList()..sort()).join(','),
    'calendarWeekday': '$weekday',
    'calendarOrdinal': '$ordinal',
    'calendarAnchor': anchor.text,
    'calendarInterval': interval.text,
    'calendarDay': day.text,
    'calendarError': error ?? '',
  };
  void restore(Map<String, String> fields) {
    pattern = fields['calendarPattern'] ?? 'daily';
    selector = fields['calendarSelector'] ?? 'date';
    missing = fields['calendarMissing'] ?? '';
    weekdays
      ..clear()
      ..addAll(
        (fields['calendarWeekdays'] ?? '')
            .split(',')
            .map(int.tryParse)
            .whereType<int>(),
      );
    weekday = int.tryParse(fields['calendarWeekday'] ?? '') ?? 1;
    ordinal = int.tryParse(fields['calendarOrdinal'] ?? '') ?? 1;
    anchor.text = fields['calendarAnchor'] ?? anchor.text;
    interval.text = fields['calendarInterval'] ?? '1';
    day.text = fields['calendarDay'] ?? '1';
    error = fields['calendarError'];
    if (error == '') error = null;
  }

  void load(CalendarPattern value) {
    switch (value) {
      case EveryDay():
        pattern = 'daily';
      case SelectedWeekdays(:final weekdays):
        pattern = 'weekdays';
        this.weekdays
          ..clear()
          ..addAll(weekdays);
      case EveryNDays(:final anchor, :final interval):
        pattern = 'days';
        this.anchor.text = anchor.toString();
        this.interval.text = '$interval';
      case EveryNWeeks(
        :final anchorWeekStart,
        :final interval,
        :final weekdays,
      ):
        pattern = 'weeks';
        anchor.text = anchorWeekStart.toString();
        this.interval.text = '$interval';
        this.weekdays
          ..clear()
          ..addAll(weekdays);
      case EveryNMonths(:final anchorMonth, :final interval, :final selector):
        pattern = interval % 12 == 0 ? 'years' : 'months';
        anchor.text = anchorMonth.toString();
        this.interval.text =
            '${pattern == 'years' ? interval ~/ 12 : interval}';
        switch (selector) {
          case DayOfMonth(:final day, :final missingDatePolicy):
            this.selector =
                day == 31 && missingDatePolicy == MissingDatePolicy.lastValid
                ? 'lastDay'
                : 'date';
            this.day.text = '$day';
            missing = missingDatePolicy?.name ?? '';
          case OrdinalWeekday(
            :final ordinal,
            :final weekday,
            :final missingDatePolicy,
          ):
            this.selector = 'ordinal';
            this.ordinal = ordinal;
            this.weekday = weekday;
            missing = missingDatePolicy?.name ?? '';
          case LastWeekday(:final weekday):
            this.selector = 'last';
            this.weekday = weekday;
        }
      case UnsupportedCalendarPattern():
        pattern = 'unsupported';
    }
  }

  bool get needsMissingChoice =>
      (pattern == 'months' || pattern == 'years') &&
      (selector == 'date' && (int.tryParse(day.text.trim()) ?? 0) > 28 ||
          selector == 'ordinal' && ordinal == 5);
  CalendarPattern candidate() {
    error = null;
    try {
      if (needsMissingChoice && missing.isEmpty) {
        error = 'missing';
        throw const FormatException('calendar_missing');
      }
      final policy = missing.isEmpty
          ? null
          : MissingDatePolicy.values.byName(missing);
      return switch (pattern) {
        'daily' => const EveryDay(),
        'weekdays' => SelectedWeekdays(weekdays),
        'days' => EveryNDays(
          anchor: CivilDate.parse(anchor.text.trim()),
          interval: int.parse(interval.text.trim()),
        ),
        'weeks' => EveryNWeeks(
          anchorWeekStart: CivilDate.parse(anchor.text.trim()),
          interval: int.parse(interval.text.trim()),
          weekdays: weekdays,
        ),
        'months' || 'years' => EveryNMonths(
          anchorMonth: CivilDate.parse(anchor.text.trim()),
          interval:
              int.parse(interval.text.trim()) * (pattern == 'years' ? 12 : 1),
          selector: switch (selector) {
            'lastDay' => DayOfMonth(
              31,
              missingDatePolicy: MissingDatePolicy.lastValid,
            ),
            'date' => DayOfMonth(
              int.parse(day.text.trim()),
              missingDatePolicy: policy,
            ),
            'ordinal' => OrdinalWeekday(
              ordinal,
              weekday,
              missingDatePolicy: policy,
            ),
            'last' => LastWeekday(weekday),
            _ => throw const FormatException('calendar_selector'),
          },
        ),
        _ => throw const FormatException('calendar_unsupported'),
      };
    } catch (_) {
      error ??= pattern == 'unsupported' ? 'unsupported' : 'invalid';
      rethrow;
    }
  }

  void choosePattern(String value) {
    final previous = pattern;
    pattern = value;
    try {
      final date = CivilDate.parse(anchor.text);
      if (value == 'weeks') {
        anchor.text = date.addDays(1 - date.calendarValue.weekday).toString();
      }
      if (value == 'months' || value == 'years') {
        if (previous != 'months' && previous != 'years') {
          day.text = '${date.day}';
          weekday = date.calendarValue.weekday;
          ordinal = (date.day - 1) ~/ 7 + 1;
        }
        anchor.text = CivilDate(date.year, date.month, 1).toString();
      }
      if ((value == 'weeks' || value == 'weekdays') && weekdays.isEmpty) {
        weekdays.add(date.calendarValue.weekday);
      }
    } catch (_) {
      /* Retain an invalid draft for explicit repair. */
    }
  }

  void dispose() {
    for (final c in controllers) {
      c.dispose();
    }
  }
}

String weekdayLabel(AppLocalizations t, int day) => switch (day) {
  1 => t.calendarMonday,
  2 => t.calendarTuesday,
  3 => t.calendarWednesday,
  4 => t.calendarThursday,
  5 => t.calendarFriday,
  6 => t.calendarSaturday,
  _ => t.calendarSunday,
};

class CalendarEditor extends StatelessWidget {
  const CalendarEditor({
    super.key,
    required this.fields,
    required this.enabled,
    required this.onChanged,
  });
  final CalendarFormFields fields;
  final bool enabled;
  final VoidCallback onChanged;
  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final labels = {
      'daily': t.simpleScheduleDaily,
      'weekdays': t.simpleScheduleWeekdays,
      'days': t.simpleScheduleDays,
      'weeks': t.repeatWeeks,
      'months': t.repeatMonths,
      'years': t.repeatYears,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(t.simpleScheduleRepeat, style: VitalType.label),
        const SizedBox(height: 8),
        VitalSelect<String>(
          label: t.simpleScheduleRepeat,
          value: fields.pattern,
          values: [
            ...labels.keys,
            if (!labels.containsKey(fields.pattern)) fields.pattern,
          ],
          labelOf: (key) => labels[key] ?? t.calendarUnsupported,
          enabled: enabled,
          onChanged: (key) {
            fields.choosePattern(key);
            onChanged();
          },
        ),
        CalendarRepeatDetails(
          fields: fields,
          enabled: enabled,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

/// The shared Workout-style repeat controls, mapped to Vital's existing rules.
class CalendarRepeatDetails extends StatelessWidget {
  const CalendarRepeatDetails({
    super.key,
    required this.fields,
    required this.enabled,
    required this.onChanged,
  });
  final CalendarFormFields fields;
  final bool enabled;
  final VoidCallback onChanged;
  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context), f = fields;
    return VitalRepeatTransition(
      value: f.pattern,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (f.pattern == 'days' ||
              f.pattern == 'weeks' ||
              (f.pattern == 'months' || f.pattern == 'years')) ...[
            VitalRepeatStepper(
              label: switch (f.pattern) {
                'days' => t.simpleScheduleEveryDays,
                'weeks' => t.repeatWeekInterval,
                'years' => t.repeatYearInterval,
                _ => t.repeatMonthInterval,
              },
              controller: f.interval,
              enabled: enabled,
              max: 9999,
            ),
            LabelledInput(
              picker: f.pattern == 'weeks'
                  ? VitalPickerKind.week
                  : f.pattern == 'months' || f.pattern == 'years'
                  ? VitalPickerKind.month
                  : VitalPickerKind.date,
              label: t.simpleScheduleStarts,
              controller: f.anchor,
              enabled: enabled,
            ),
          ],
          if (f.pattern == 'weekdays' || f.pattern == 'weeks')
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: VitalWeekdayPicker(
                selected: f.weekdays,
                enabled: enabled,
                onChanged: (days) {
                  f.weekdays
                    ..clear()
                    ..addAll(days);
                  onChanged();
                },
              ),
            ),
          if ((f.pattern == 'months' || f.pattern == 'years')) ...[
            VitalSelect<String>(
              label: t.calendarMonthRule,
              value: f.selector,
              values: const ['date', 'lastDay', 'ordinal', 'last'],
              labelOf: (key) => switch (key) {
                'date' => t.calendarDate,
                'lastDay' => t.repeatLastDay,
                'ordinal' => t.calendarOrdinal,
                _ => t.calendarLast,
              },
              enabled: enabled,
              onChanged: (key) {
                f.selector = key;
                onChanged();
              },
            ),
            if (f.selector == 'date')
              VitalRepeatStepper(
                label: t.calendarNominalDay,
                controller: f.day,
                enabled: enabled,
                max: 31,
              ),
            if (f.selector == 'ordinal')
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: VitalSelect<int>(
                  label: t.calendarOrdinalNumber,
                  value: f.ordinal,
                  values: const [1, 2, 3, 4, 5],
                  labelOf: (n) => '$n',
                  enabled: enabled,
                  onChanged: (n) {
                    f.ordinal = n;
                    onChanged();
                  },
                ),
              ),
            if (f.selector == 'ordinal' || f.selector == 'last')
              VitalSelect<int>(
                label: t.calendarWeekday,
                value: f.weekday,
                values: const [1, 2, 3, 4, 5, 6, 7],
                labelOf: (day) => weekdayLabel(t, day),
                enabled: enabled,
                onChanged: (day) {
                  f.weekday = day;
                  onChanged();
                },
              ),
            if (f.needsMissingChoice) ...[
              const SizedBox(height: 12),
              Text(
                f.selector == 'date'
                    ? t.calendarMissingDayHelp
                    : t.calendarMissingWeekHelp,
                style: VitalType.metadata,
              ),
              VitalSelect<String>(
                label: t.calendarMissing,
                value: f.missing,
                values: const ['', 'omit', 'lastValid'],
                labelOf: (key) => switch (key) {
                  'omit' => t.calendarOmit,
                  'lastValid' => t.calendarUse,
                  _ => t.simpleScheduleChoose,
                },
                enabled: enabled,
                onChanged: (key) {
                  f.missing = key;
                  onChanged();
                },
              ),
            ],
          ],
          if (f.error != null)
            Semantics(
              liveRegion: true,
              child: Text(switch (f.error) {
                'missing' => t.calendarMissingRequired,
                'unsupported' => t.calendarUnsupported,
                _ => t.calendarInvalid,
              }),
            ),
        ],
      ),
    );
  }
}

class CalendarChoices extends StatelessWidget {
  const CalendarChoices({
    super.key,
    required this.value,
    required this.enabled,
    required this.choices,
    required this.onSelected,
  });
  final String value;
  final bool enabled;
  final List<(String, String)> choices;
  final ValueChanged<String> onSelected;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        for (final (v, label) in choices)
          CalendarChoice(
            label: label,
            selected: value == v,
            onPressed: enabled ? () => onSelected(v) : null,
          ),
      ],
    ),
  );
}

class CalendarChoice extends StatelessWidget {
  const CalendarChoice({
    super.key,
    required this.label,
    required this.selected,
    required this.onPressed,
  });
  final String label;
  final bool selected;
  final VoidCallback? onPressed;
  @override
  Widget build(BuildContext context) => Semantics(
    selected: selected,
    child: ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48),
      child: selected
          ? VitalButton(
              multiline: true,
              onPressed: onPressed,
              child: Text(label),
            )
          : VitalButton.secondary(
              multiline: true,
              onPressed: onPressed,
              child: Text(label),
            ),
    ),
  );
}

/// The first missing nominal date and the following selected date, independent
/// of clock conversion and the shorter list of visible occurrences.
class CalendarBoundaryPreview extends StatelessWidget {
  const CalendarBoundaryPreview({
    super.key,
    required this.plan,
    required this.from,
  });
  final DailyPlanVersion plan;
  final CivilDate from;
  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context), pattern = plan.calendar;
    if (pattern case EveryNWeeks(:final anchorWeekStart)) {
      return Text(
        t.calendarAnchorPreview(
          anchorWeekStart.toString(),
          (anchorWeekStart.calendarValue.add(const Duration(days: 6)).year >
                      9999
                  ? CivilDate(9999, 12, 31)
                  : anchorWeekStart.addDays(6))
              .toString(),
        ),
      );
    }
    if (pattern is! EveryNMonths) return const SizedBox.shrink();
    final selector = pattern.selector;
    if (selector is LastWeekday ||
        selector is DayOfMonth && selector.day <= 28 ||
        selector is OrdinalWeekday && selector.ordinal < 5) {
      return const SizedBox.shrink();
    }
    final first =
        (pattern.anchorMonth.year - 1) * 12 + pattern.anchorMonth.month - 1;
    final current = (from.year - 1) * 12 + from.month - 1;
    final delta = current - first;
    var index =
        first +
        (delta <= 0 ? 0 : (delta + pattern.interval - 1) ~/ pattern.interval) *
            pattern.interval;
    for (
      var work = 0;
      work < 4800 && index < 9999 * 12;
      work++, index += pattern.interval
    ) {
      final year = index ~/ 12 + 1, month = index % 12 + 1;
      final monthStart = CivilDate(year, month, 1);
      if (plan.endExclusive != null &&
          monthStart.compareTo(plan.endExclusive!) >= 0) {
        return const SizedBox.shrink();
      }
      final last = DateTime.utc(year, month + 1, 0).day;
      final nominal = switch (selector) {
        DayOfMonth(:final day) => day,
        OrdinalWeekday(:final ordinal, :final weekday) =>
          1 +
              (weekday - monthStart.calendarValue.weekday + 7) % 7 +
              (ordinal - 1) * 7,
        _ => 1,
      };
      if (nominal <= last) continue;
      final policy = switch (selector) {
        DayOfMonth(:final missingDatePolicy) => missingDatePolicy,
        OrdinalWeekday(:final missingDatePolicy) => missingDatePolicy,
        _ => null,
      };
      final result = const CalendarSelector().onOrAfter(
        pattern,
        monthStart,
        endExclusive: plan.endExclusive,
      );
      final selected = result.date;
      // A last-day fallback earlier in the current month is already past.
      if (policy == MissingDatePolicy.lastValid &&
          selected != null &&
          selected.compareTo(from) < 0) {
        continue;
      }
      final next =
          selected == null ||
              selected.year == 9999 &&
                  selected.month == 12 &&
                  selected.day == 31
          ? null
          : const CalendarSelector()
                .onOrAfter(
                  pattern,
                  selected.addDays(1),
                  endExclusive: plan.endExclusive,
                )
                .date;
      final monthLabel =
          '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}';
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Heading(t.planBoundary),
          Text(switch (selector) {
            DayOfMonth(:final day) => t.calendarBoundaryDay(monthLabel, day),
            OrdinalWeekday(:final ordinal, :final weekday) =>
              t.calendarBoundaryWeekday(
                monthLabel,
                ordinal,
                weekdayLabel(t, weekday),
              ),
            _ => '',
          }),
          Text(
            policy == MissingDatePolicy.omit
                ? t.calendarBoundaryOmitted
                : selected == null
                ? t.planNoNext
                : t.calendarBoundaryUse(selected.toString()),
          ),
          if (policy == MissingDatePolicy.omit && selected != null)
            Text(t.calendarBoundaryNext(selected.toString()))
          else if (next != null)
            Text(t.calendarBoundaryNext(next.toString())),
        ],
      );
    }
    return Text(t.calendarBoundaryLimit);
  }
}
