import '../../ui/stitch_ui.dart';

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

/// The seven civil dates of the locale week containing [selected].
///
/// [firstDayOfWeek] is [MaterialLocalizations.firstDayOfWeekIndex], where
/// 0 is Sunday. The same index positions both the month grid and this week,
/// so changing the selected date moves the week without a second week rule.
List<CivilDate> historyWeekDates(CivilDate selected, int firstDayOfWeek) {
  final offset = (selected.calendarValue.weekday % 7 - firstDayOfWeek + 7) % 7;
  var start = selected.calendarValue.subtract(Duration(days: offset));
  // CivilDate only represents years 1 through 9999. At either edge the week
  // cannot be represented in full, so keep seven contiguous representable
  // days around the selected date instead of throwing.
  if (start.year < 1) start = DateTime.utc(1, 1, 1);
  if (start.add(const Duration(days: 6)).year > 9999) {
    start = DateTime.utc(9999, 12, 31).subtract(const Duration(days: 6));
  }
  return [
    for (var i = 0; i < 7; i++)
      CivilDate.fromDateTime(start.add(Duration(days: i))),
  ];
}

List<CivilDate?> historyCalendarCells(CivilDate month, int firstDayOfWeek) {
  final first = DateTime.utc(month.year, month.month, 1);
  final padding = (first.weekday % 7 - firstDayOfWeek + 7) % 7;
  return List.generate(42, (i) {
    final date = first.add(Duration(days: i - padding));
    return date.year < 1 || date.year > 9999
        ? null
        : CivilDate(date.year, date.month, date.day);
  });
}

List<CivilDate> historyCalendarDates(CivilDate month, int firstDayOfWeek) =>
    historyCalendarCells(month, firstDayOfWeek).whereType<CivilDate>().toList();

class HistoryMonthGrid extends StatelessWidget {
  const HistoryMonthGrid({
    super.key,
    required this.month,
    required this.selected,
    required this.zone,
    required this.counts,
    required this.onSelect,
    required this.onMonth,
    this.available = true,
    this.unavailableLabel,
    this.tools,
  });
  final CivilDate month;
  final CivilDate? selected;
  final String zone;
  final Widget? tools;
  final bool available;
  final String? unavailableLabel;
  final Map<CivilDate, HistoryDayCounts> counts;
  final ValueChanged<CivilDate> onSelect, onMonth;
  @override
  Widget build(BuildContext context) {
    final locale = Localizations.of<MaterialLocalizations>(
          context,
          MaterialLocalizations,
        )!,
        t = AppLocalizations.of(context),
        c = StitchColors(context);
    final dates = historyCalendarCells(month, locale.firstDayOfWeekIndex);
    final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
    final cell = math.max(48.0, 48.0 * scale);
    void move(int delta) {
      final date = DateTime.utc(month.year, month.month + delta, 1);
      if (date.year >= 1 && date.year <= 9999) {
        onMonth(CivilDate(date.year, date.month, 1));
      }
    }

    final previous = Semantics(
      label: t.previousMonth,
      child: StitchButton(
        quiet: true,
        compact: true,
        onPressed: month.year == 1 && month.month == 1 ? null : () => move(-1),
        child: const Icon(LucideIcons.chevronLeft),
      ),
    );
    final next = Semantics(
      label: t.nextMonth,
      child: StitchButton(
        quiet: true,
        compact: true,
        onPressed: month.year == 9999 && month.month == 12
            ? null
            : () => move(1),
        child: const Icon(LucideIcons.chevronRight),
      ),
    );
    final heading = Semantics(
      header: true,
      child: Text(
        locale.formatMonthYear(month.calendarValue),
        textAlign: TextAlign.center,
        style: VitalType.detailTitle.copyWith(color: c.ink),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (scale > 1.3) ...[
          heading,
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [previous, next, ?tools],
          ),
        ] else
          Row(
            children: [
              previous,
              Expanded(child: heading),
              next,
              ?tools,
            ],
          ),
        if (available) ...[
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              t.calendarRecordedDays(
                counts.entries
                    .where(
                      (entry) =>
                          entry.key.year == month.year &&
                          entry.key.month == month.month &&
                          entry.value.recorded > 0,
                    )
                    .length,
              ),
              style: StitchType.body.copyWith(color: c.muted),
            ),
          ),
        ],
        const SizedBox(height: 20),
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
                                style: StitchType.small.copyWith(
                                  color: c.muted,
                                  fontWeight: FontWeight.w600,
                                ),
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
                                final date = dates[row * 7 + col];
                                if (date == null) return SizedBox(height: cell);
                                final marker =
                                    counts[dates[row * 7 + col]] ??
                                    const HistoryDayCounts();
                                final isSelected = date == selected;
                                return Semantics(
                                  key: ValueKey('history-day-$date'),
                                  button: true,
                                  selected: isSelected,
                                  label: available
                                      ? t.historyDaySummary(
                                          locale.formatFullDate(
                                            date.calendarValue,
                                          ),
                                          marker.recorded,
                                          marker.skipped,
                                          marker.voided,
                                        )
                                      : t.screenHistoryDayUnavailable(
                                          locale.formatFullDate(
                                            date.calendarValue,
                                          ),
                                          unavailableLabel ??
                                              t.historyMonthLoading,
                                        ),
                                  excludeSemantics: true,
                                  onTap: () => onSelect(date),
                                  child: CalendarItem(
                                    type: CalendarItemType.none,
                                    indexAtRow: col,
                                    rowCount: 7,
                                    state: DateState.enabled,
                                    width: cell,
                                    height: cell,
                                    onTap: () => onSelect(date),
                                    child: Container(
                                      constraints: BoxConstraints(
                                        minHeight: cell,
                                        minWidth: cell,
                                      ),
                                      decoration: BoxDecoration(
                                        color: isSelected
                                            ? c.accent
                                            : Colors.transparent,
                                        shape: BoxShape.circle,
                                      ),
                                      child: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Text(
                                            '${date.day}',
                                            style: StitchType.label.copyWith(
                                              color: isSelected
                                                  ? c.accentInk
                                                  : date.month == month.month
                                                  ? c.ink
                                                  : c.muted,
                                              fontWeight:
                                                  date.month == month.month
                                                  ? FontWeight.w600
                                                  : FontWeight.w400,
                                            ),
                                          ),
                                          if (available &&
                                              marker.recorded +
                                                      marker.skipped +
                                                      marker.voided >
                                                  0)
                                            ExcludeSemantics(
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                mainAxisAlignment:
                                                    MainAxisAlignment.center,
                                                children: [
                                                  if (marker.recorded > 0)
                                                    Container(
                                                      width: 6,
                                                      height: 6,
                                                      decoration: BoxDecoration(
                                                        shape: BoxShape.circle,
                                                        color: isSelected
                                                            ? c.accentInk
                                                            : c.accent,
                                                      ),
                                                    ),
                                                  if (marker.skipped > 0)
                                                    Icon(
                                                      LucideIcons.minus,
                                                      size: 10,
                                                      color: isSelected
                                                          ? c.accentInk
                                                          : c.amber,
                                                    ),
                                                  if (marker.voided > 0)
                                                    Icon(
                                                      LucideIcons.x,
                                                      size: 10,
                                                      color: isSelected
                                                          ? c.accentInk
                                                          : c.muted,
                                                    ),
                                                ],
                                              ),
                                            ),
                                        ],
                                      ),
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
        const SizedBox(height: 16),
        Container(height: 1, color: c.line),
        const SizedBox(height: 16),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 12,
          runSpacing: 8,
          children: [
            for (final marker in [
              (LucideIcons.circle, t.statusRecorded, c.accent),
              (LucideIcons.minus, t.statusSkipped, c.amber),
              (LucideIcons.x, t.statusVoided, c.muted),
            ])
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ExcludeSemantics(
                    child: Icon(marker.$1, size: 10, color: marker.$3),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    marker.$2,
                    style: StitchType.small.copyWith(color: c.muted),
                  ),
                ],
              ),
          ],
        ),
      ],
    );
  }
}
