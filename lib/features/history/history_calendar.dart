import '../../ui/vital_ui.dart';

import 'dart:math' as math;

import 'package:flutter/material.dart' show MaterialLocalizations;
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../domain/scheduling/daily_plan.dart' show CivilDate;
import '../../l10n/app_localizations.dart';

class HistoryDayCounts {
  const HistoryDayCounts({
    this.recorded = 0,
    this.skipped = 0,
    this.voided = 0,
  });
  final int recorded, skipped, voided;
}

List<CivilDate> historyCalendarDates(CivilDate month, int firstDayOfWeek) {
  final first = DateTime.utc(month.year, month.month, 1);
  final padding = (first.weekday % 7 - firstDayOfWeek + 7) % 7;
  final count =
      ((padding + DateTime.utc(month.year, month.month + 1, 0).day) / 7)
          .ceil() *
      7;
  return List.generate(count, (i) {
    final date = first.add(Duration(days: i - padding));
    return CivilDate(date.year, date.month, date.day);
  });
}

class HistoryMonthGrid extends StatelessWidget {
  const HistoryMonthGrid({
    super.key,
    required this.month,
    required this.selected,
    required this.zone,
    required this.counts,
    required this.onSelect,
    required this.onMonth,
  });
  final CivilDate month;
  final CivilDate? selected;
  final String zone;
  final Map<CivilDate, HistoryDayCounts> counts;
  final ValueChanged<CivilDate> onSelect, onMonth;
  @override
  Widget build(BuildContext context) {
    final locale = Localizations.of<MaterialLocalizations>(
          context,
          MaterialLocalizations,
        )!,
        t = AppLocalizations.of(context);
    final dates = historyCalendarDates(month, locale.firstDayOfWeekIndex);
    final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
    final cell = math.max(48.0, 48.0 * scale);
    void move(int delta) {
      final date = DateTime.utc(month.year, month.month + delta, 1);
      if (date.year >= 1 && date.year <= 9999) {
        onMonth(CivilDate(date.year, date.month, 1));
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Semantics(
              label: t.previousMonth,
              child: VitalButton.secondary(
                onPressed: month.year == 1 && month.month == 1
                    ? null
                    : () => move(-1),
                child: const Icon(LucideIcons.chevronLeft),
              ),
            ),
            Expanded(
              child: Semantics(
                header: true,
                child: Text(
                  locale.formatMonthYear(month.calendarValue),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
            Semantics(
              label: t.nextMonth,
              child: VitalButton.secondary(
                onPressed: month.year == 9999 && month.month == 12
                    ? null
                    : () => move(1),
                child: const Icon(LucideIcons.chevronRight),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: math.max(constraints.maxWidth, cell * 7),
              child: Column(
                children: [
                  Row(
                    children: [
                      for (var i = 0; i < 7; i++)
                        Expanded(
                          child: Semantics(
                            header: true,
                            child: Center(
                              child: Text(
                                locale.narrowWeekdays[(i +
                                        locale.firstDayOfWeekIndex) %
                                    7],
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  for (var row = 0; row < dates.length ~/ 7; row++)
                    Row(
                      children: [
                        for (var col = 0; col < 7; col++)
                          Expanded(
                            child: Builder(
                              builder: (context) {
                                final date = dates[row * 7 + col],
                                    marker =
                                        counts[dates[row * 7 + col]] ??
                                        const HistoryDayCounts();
                                final isSelected = date == selected;
                                return Semantics(
                                  key: ValueKey('history-day-$date'),
                                  button: true,
                                  selected: isSelected,
                                  label: t.historyDaySummary(
                                    locale.formatFullDate(date.calendarValue),
                                    marker.recorded,
                                    marker.skipped,
                                    marker.voided,
                                  ),
                                  excludeSemantics: true,
                                  onTap: () => onSelect(date),
                                  child: CalendarItem(
                                    type: isSelected
                                        ? CalendarItemType.selected
                                        : CalendarItemType.none,
                                    indexAtRow: col,
                                    rowCount: 7,
                                    state: DateState.enabled,
                                    width: cell,
                                    height: cell,
                                    onTap: () => onSelect(date),
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Text(
                                          '${date.day}',
                                          style: TextStyle(
                                            fontWeight:
                                                date.month == month.month
                                                ? FontWeight.w600
                                                : FontWeight.normal,
                                          ),
                                        ),
                                        if (marker.recorded +
                                                marker.skipped +
                                                marker.voided >
                                            0)
                                          Text(
                                            '${marker.recorded > 0 ? '●' : ''}${marker.skipped > 0 ? '−' : ''}${marker.voided > 0 ? '×' : ''}',
                                            style: const TextStyle(
                                              fontSize: 12,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ),
        Text(t.historyMarkerLegend),
      ],
    );
  }
}
