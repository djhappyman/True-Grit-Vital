import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'picker_adapters.dart';
import '../vital_motion.dart';

class VitalDatePickerMonthPager extends StatelessWidget {
  const VitalDatePickerMonthPager({
    super.key,
    required this.controller,
    required this.firstYear,
    required this.yearCount,
    required this.selectedMonth,
    required this.firstDate,
    required this.lastDate,
    required this.currentDate,
    required this.onYearChanged,
    required this.onMonthSelected,
  });

  final PageController controller;
  final int firstYear;
  final int yearCount;
  final DateTime selectedMonth;
  final DateTime firstDate;
  final DateTime lastDate;
  final DateTime currentDate;
  final ValueChanged<int> onYearChanged;
  final ValueChanged<DateTime> onMonthSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 224,
      child: PageView.builder(
        key: const ValueKey('vital_date_picker_month_picker_pages'),
        controller: controller,
        itemCount: yearCount,
        onPageChanged: (page) => onYearChanged(firstYear + page),
        itemBuilder: (context, page) {
          final year = firstYear + page;
          return Column(
            children: [
              for (var row = 0; row < 4; row++)
                Expanded(
                  child: Row(
                    children: [
                      for (var column = 0; column < 3; column++)
                        Expanded(
                          child: _MonthCell(
                            month: DateTime(year, (row * 3) + column + 1),
                            selectedMonth: selectedMonth,
                            firstDate: firstDate,
                            lastDate: lastDate,
                            currentDate: currentDate,
                            onSelected: onMonthSelected,
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class VitalDatePickerYearPager extends StatelessWidget {
  const VitalDatePickerYearPager({
    super.key,
    required this.controller,
    required this.firstYear,
    required this.lastYear,
    required this.yearsPerPage,
    required this.selectedYear,
    required this.currentYear,
    required this.onPageChanged,
    required this.onYearSelected,
  });

  final PageController controller;
  final int firstYear;
  final int lastYear;
  final int yearsPerPage;
  final int selectedYear;
  final int currentYear;
  final ValueChanged<int> onPageChanged;
  final ValueChanged<int> onYearSelected;

  int get _pageCount => ((lastYear - firstYear + 1) / yearsPerPage).ceil();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 224,
      child: PageView.builder(
        key: const ValueKey('vital_date_picker_year_picker_pages'),
        controller: controller,
        itemCount: _pageCount,
        onPageChanged: onPageChanged,
        itemBuilder: (context, page) {
          final pageStart = firstYear + (page * yearsPerPage);
          return Column(
            children: [
              for (var row = 0; row < 4; row++)
                Expanded(
                  child: Row(
                    children: [
                      for (var column = 0; column < 3; column++)
                        Expanded(
                          child: _YearCell(
                            year: pageStart + (row * 3) + column,
                            selectedYear: selectedYear,
                            currentYear: currentYear,
                            enabled: pageStart + (row * 3) + column <= lastYear,
                            onSelected: onYearSelected,
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _MonthCell extends StatelessWidget {
  const _MonthCell({
    required this.month,
    required this.selectedMonth,
    required this.firstDate,
    required this.lastDate,
    required this.currentDate,
    required this.onSelected,
  });

  final DateTime month;
  final DateTime selectedMonth;
  final DateTime firstDate;
  final DateTime lastDate;
  final DateTime currentDate;
  final ValueChanged<DateTime> onSelected;

  @override
  Widget build(BuildContext context) {
    final scheme = VitalPickerTheme.of(context).colorScheme;
    final locale = Localizations.localeOf(context).toString();
    final monthEnd = DateTime(month.year, month.month + 1, 0);
    final enabled = !monthEnd.isBefore(firstDate) && !month.isAfter(lastDate);
    final selected =
        month.year == selectedMonth.year && month.month == selectedMonth.month;
    final current =
        month.year == currentDate.year && month.month == currentDate.month;
    final reduceMotion = VitalMotion.reduced(context);
    final shortLabel = DateFormat.MMM(locale).format(month);
    final fullLabel = DateFormat.MMMM(locale).format(month);

    return Semantics(
      button: true,
      enabled: enabled,
      selected: selected,
      label: '$fullLabel ${month.year}',
      child: VitalPickerTap(
        key: ValueKey(
          'vital_date_picker_month_${month.year}-${month.month.toString().padLeft(2, '0')}',
        ),
        borderRadius: BorderRadius.circular(18),
        onTap: enabled ? () => onSelected(month) : null,
        child: Center(
          child: AnimatedContainer(
            duration: reduceMotion
                ? Duration.zero
                : VitalMotion.duration(context, VitalMotion.choice),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              color: selected ? scheme.primary : Colors.transparent,
              borderRadius: BorderRadius.circular(18),
              border: current && !selected
                  ? Border.all(color: scheme.primary.withValues(alpha: 0.72))
                  : null,
            ),
            child: Text(
              shortLabel,
              style: VitalPickerTheme.of(context).textTheme.labelLarge
                  ?.copyWith(
                    color: !enabled
                        ? scheme.onSurface.withValues(alpha: 0.30)
                        : selected
                        ? scheme.onPrimary
                        : current
                        ? scheme.primary
                        : scheme.onSurface,
                    fontWeight: selected || current
                        ? FontWeight.w800
                        : FontWeight.w600,
                  ),
            ),
          ),
        ),
      ),
    );
  }
}

class _YearCell extends StatelessWidget {
  const _YearCell({
    required this.year,
    required this.selectedYear,
    required this.currentYear,
    required this.enabled,
    required this.onSelected,
  });

  final int year;
  final int selectedYear;
  final int currentYear;
  final bool enabled;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final scheme = VitalPickerTheme.of(context).colorScheme;
    final selected = enabled && year == selectedYear;
    final current = enabled && year == currentYear;
    final reduceMotion = VitalMotion.reduced(context);

    return Semantics(
      button: true,
      enabled: enabled,
      selected: selected,
      label: enabled ? '$year' : null,
      child: VitalPickerTap(
        key: enabled ? ValueKey('vital_date_picker_year_$year') : null,
        borderRadius: BorderRadius.circular(18),
        onTap: enabled ? () => onSelected(year) : null,
        child: Center(
          child: AnimatedContainer(
            duration: reduceMotion
                ? Duration.zero
                : VitalMotion.duration(context, VitalMotion.choice),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              color: selected ? scheme.primary : Colors.transparent,
              borderRadius: BorderRadius.circular(18),
              border: current && !selected
                  ? Border.all(color: scheme.primary.withValues(alpha: 0.72))
                  : null,
            ),
            child: Text(
              enabled ? '$year' : '',
              style: VitalPickerTheme.of(context).textTheme.labelLarge
                  ?.copyWith(
                    color: selected
                        ? scheme.onPrimary
                        : current
                        ? scheme.primary
                        : scheme.onSurface,
                    fontWeight: selected || current
                        ? FontWeight.w800
                        : FontWeight.w600,
                  ),
            ),
          ),
        ),
      ),
    );
  }
}
