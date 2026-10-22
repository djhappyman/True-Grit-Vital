import '../recording/quick_record_sheet.dart';

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../app/device_zone.dart';
import '../../app/display_preferences.dart';
import '../../app/storage.dart';
import '../../data/record_store.dart';
import '../../l10n/app_localizations.dart';
import '../../ui/stitch_ui.dart';
import '../../ui/vital_ui.dart';
import '../recording/record_pages.dart' show LoadFailure, PagedRecordList;
import '../stock/stock_providers.dart';
import 'daily_feed.dart';
import 'dashboard_week.dart';
import 'plan_providers.dart';
import 'today_hero.dart';
import 'today_model.dart';

/// The owner's focused Today layout, using the shared Stitch surfaces.
/// Calendar browsing and selected-day identity are deliberately independent.
class StitchDashboard extends ConsumerStatefulWidget {
  const StitchDashboard({super.key, required this.scope});
  final FeedScope scope;
  @override
  ConsumerState<StitchDashboard> createState() => _StitchDashboardState();
}

class _StitchDashboardState extends ConsumerState<StitchDashboard> {
  CivilDate? selectedDay;
  bool followToday = true;
  Timer? rollover;
  DateTime? dayEnd;
  @override
  void dispose() {
    rollover?.cancel();
    super.dispose();
  }

  void selectDay(CivilDate day, CivilDate today) => setState(() {
    selectedDay = day;
    followToday = day == today;
  });
  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context), c = StitchColors(context);
    final zone = ref.watch(displayZoneProvider);
    final now = ref.watch(todayNowProvider)();
    final today = DisplayTime().instant(now, zone).civilDate;
    if (selectedDay == null || followToday) selectedDay = today;
    final selected = selectedDay!;
    final end = DisplayTime().dayBounds(today, zone).endExclusive;
    if (dayEnd != end) {
      dayEnd = end;
      rollover?.cancel();
      rollover = Timer(
        end.difference(now) + const Duration(milliseconds: 1),
        () {
          if (!mounted) return;
          setState(() => dayEnd = null);
          ref.invalidate(dailyFeedProvider(widget.scope));
        },
      );
    }
    final daily = selected == today
        ? ref.watch(dailyFeedProvider(widget.scope))
        : ref.watch(dailyDayFeedProvider((scope: widget.scope, day: selected)));
    // Warm only the neighbouring dates. Week browsing itself changes no dose
    // query or selected date; background arrivals do not rebuild this widget.
    for (final delta in [-1, 1]) {
      final date = selected.calendarValue.add(Duration(days: delta));
      if (date.year >= 1 && date.year <= 9999) {
        ref.listen(
          dailyDayFeedProvider((
            scope: widget.scope,
            day: CivilDate.fromDateTime(date),
          )),
          (_, _) {},
        );
      }
    }
    final rows = daily.isLoading || daily.hasError
        ? <DailyRow>[]
        : daily.value?.rows ?? <DailyRow>[];
    final groups = <int, List<DailyRow>>{};
    for (final row in rows) {
      final start = todayRowStart(row);
      final hour = start == null
          ? null
          : DisplayTime().instant(start, row.expectation.zoneId).hour;
      final part = hour == null
          ? 4
          : hour < 6
          ? 0
          : hour < 12
          ? 1
          : hour < 18
          ? 2
          : 3;
      (groups[part] ??= []).add(row);
    }
    String title(int part) => switch (part) {
      0 => t.dashboardNightTitle,
      1 => t.dashboardMorningTitle,
      2 => t.dashboardAfternoonTitle,
      3 => t.dashboardEveningTitle,
      _ => t.dashboardUntimedTitle,
    };
    Widget status(int part) {
      final entries = groups[part] ?? <DailyRow>[];
      if (entries.isEmpty) return VitalBadge(t.dashboardEmpty, compact: true);
      if (!daily.requireValue.complete ||
          entries.any((row) => !row.actionsComplete)) {
        return VitalBadge(t.stitchPartial, compact: true);
      }
      final taken = entries.fold<int>(0, (sum, row) => sum + row.takenCount);
      final planned = entries.fold<int>(
        0,
        (sum, row) => sum + row.plannedCount,
      );
      return VitalBadge(
        t.dashboardTakenCount(taken, planned),
        compact: true,
        tone: taken > 0 ? VitalTone.positive : VitalTone.neutral,
      );
    }

    final empty =
        daily.hasValue && !daily.isLoading && !daily.hasError && rows.isEmpty;
    return DefaultTextStyle.merge(
      style: StitchType.body.copyWith(color: c.ink),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _DashboardWeekBar(
            today: today,
            selected: selected,
            zoneKnown:
                ref.watch(observedDeviceZoneProvider).value?.zoneId != null,
            onSelect: (day) => selectDay(day, today),
            onToday: () => selectDay(today, today),
          ),
          const SizedBox(height: 24),
          Semantics(
            header: true,
            child: Text(
              t.dashboardSchedule.toUpperCase(),
              style: StitchType.label.copyWith(
                color: c.muted,
                letterSpacing: .6,
              ),
            ),
          ),
          const SizedBox(height: 14),
          if (daily.hasError)
            LoadFailure(
              onRetry: () => selected == today
                  ? ref.invalidate(dailyFeedProvider(widget.scope))
                  : ref.invalidate(
                      dailyDayFeedProvider((
                        scope: widget.scope,
                        day: selected,
                      )),
                    ),
            )
          else if (daily.isLoading || !daily.hasValue)
            SizedBox(
              height: 180,
              child: Align(
                alignment: AlignmentDirectional.topStart,
                child: Text(t.loadingRecords, style: StitchType.caption),
              ),
            )
          else ...[
            if (!daily.requireValue.complete ||
                rows.any((row) => !row.actionsComplete))
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  t.planIncomplete,
                  style: StitchType.caption.copyWith(color: c.amber),
                ),
              ),
            for (final part
                in empty ? [1, 2, 3] : (groups.keys.toList()..sort())) ...[
              StitchSectionCard(
                key: ValueKey('schedule-part-$part'),
                title: title(part),
                trailing: status(part),
                icon: switch (part) {
                  0 => LucideIcons.moon,
                  1 => LucideIcons.sunrise,
                  2 => LucideIcons.sun,
                  3 => LucideIcons.moon,
                  _ => LucideIcons.clock,
                },
                subtitle: part == 4
                    ? null
                    : t.dashboardPeriodRange(
                        displayWallTime(
                          context,
                          ref,
                          WallTime(switch (part) {
                            0 => 0,
                            1 => 6,
                            2 => 12,
                            _ => 18,
                          }, 0),
                        ),
                        displayWallTime(
                          context,
                          ref,
                          WallTime(switch (part) {
                            0 => 6,
                            1 => 12,
                            2 => 18,
                            _ => 0,
                          }, 0),
                        ),
                      ),
                child: empty
                    ? StitchEmptySlot(
                        label: t.dashboardPlanPeriod(title(part)),
                        onPressed: () => context.push(
                          '/unplanned?plan=1&day=$selected&time=${switch (part) {
                            1 => '08:00',
                            2 => '14:00',
                            _ => '20:00',
                          }}',
                        ),
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final row in groups[part]!)
                            if (selected == today)
                              DailyRowCard(
                                key: ValueKey(row.expectation.identity),
                                row: row,
                                presentation: DailyCardPresentation.timeline,
                              )
                            else
                              _BrowsedDayRow(
                                key: ValueKey(row.expectation.identity),
                                row: row,
                                day: selected,
                              ),
                        ],
                      ),
              ),
              const SizedBox(height: 16),
            ],
            StitchButton(
              outlined: true,
              icon: LucideIcons.calendarPlus,
              onPressed: () => context.push('/unplanned?plan=1&day=$selected'),
              child: Text(t.dashboardPlanAction),
            ),
          ],
          const SizedBox(height: 8),
          UnplannedMedication(day: selected, today: today),
          const SizedBox(height: 20),
          const _ContextCards(),
          StitchSectionCard(
            icon: LucideIcons.activity,
            title: t.dashboardObservations,
            subtitle: t.dashboardObservationsHelp,
            trailing: StitchBadge(t.dashboardComingSoon),
          ),
        ],
      ),
    );
  }
}

/// The visible week belongs to the pager, independently of the chosen day.
/// A drag never starts a day read or silently selects Monday.
class _DashboardWeekBar extends StatefulWidget {
  const _DashboardWeekBar({
    required this.today,
    required this.selected,
    required this.zoneKnown,
    required this.onSelect,
    required this.onToday,
  });
  final CivilDate today, selected;
  final bool zoneKnown;
  final ValueChanged<CivilDate> onSelect;
  final VoidCallback onToday;
  @override
  State<_DashboardWeekBar> createState() => _DashboardWeekBarState();
}

class _DashboardWeekBarState extends State<_DashboardWeekBar> {
  late CivilDate visibleWeek = dashboardWeekStart(widget.selected);
  static final lastWeek =
      DateTime.utc(9999, 12, 31).difference(DateTime.utc(1, 1, 1)).inDays ~/ 7;
  int weekIndex(CivilDate day) =>
      dashboardWeekStart(day).calendarValue
          .difference(DateTime.utc(1, 1, 1))
          .inDays ~/
      7;
  @override
  void didUpdateWidget(_DashboardWeekBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selected != widget.selected) {
      visibleWeek = dashboardWeekStart(widget.selected);
    }
  }

  void move(int delta) {
    final index = weekIndex(visibleWeek) + delta;
    if (index >= 0 && index <= lastWeek) {
      setState(() => visibleWeek = CivilDate(1, 1, 1).addDays(index * 7));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = StitchColors(context), t = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).toLanguageTag();
    final start = visibleWeek.calendarValue;
    final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
    final showToday =
        widget.selected != widget.today ||
        weekIndex(widget.today) != weekIndex(visibleWeek);
    return StitchSurface(
      key: const ValueKey('dashboard-calendar-frame'),
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SizedBox(
              key: const ValueKey('dashboard-calendar-heading'),
              height: scale > 1.35
                  ? 20 * scale + 56
                  : 48 * (scale < 1 ? 1 : scale),
              child: scale > 1.35
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          DateFormat('MMMM y', locale).format(start),
                          style: StitchType.body.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Visibility(
                              visible: showToday,
                              maintainSize: true,
                              maintainAnimation: true,
                              maintainState: true,
                              child: StitchButton(
                                quiet: true,
                                compact: true,
                                onPressed: () {
                                  setState(
                                    () => visibleWeek = dashboardWeekStart(
                                      widget.today,
                                    ),
                                  );
                                  widget.onToday();
                                },
                                child: Text(t.today),
                              ),
                            ),
                            _WeekArrow(
                              icon: LucideIcons.chevronLeft,
                              label: t.featureWeekPrevious,
                              onPressed: () => move(-1),
                            ),
                            _WeekArrow(
                              icon: LucideIcons.chevronRight,
                              label: t.featureWeekNext,
                              onPressed: () => move(1),
                            ),
                          ],
                        ),
                      ],
                    )
                  : Row(
                      children: [
                        Expanded(
                          child: Text(
                            DateFormat('MMMM y', locale).format(start),
                            style: StitchType.body.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Visibility(
                          visible: showToday,
                          maintainSize: true,
                          maintainAnimation: true,
                          maintainState: true,
                          child: StitchButton(
                            quiet: true,
                            compact: true,
                            onPressed: () {
                              setState(
                                () => visibleWeek = dashboardWeekStart(
                                  widget.today,
                                ),
                              );
                              widget.onToday();
                            },
                            child: Text(t.today),
                          ),
                        ),
                        _WeekArrow(
                          icon: LucideIcons.chevronLeft,
                          label: t.featureWeekPrevious,
                          onPressed: () => move(-1),
                        ),
                        _WeekArrow(
                          icon: LucideIcons.chevronRight,
                          label: t.featureWeekNext,
                          onPressed: () => move(1),
                        ),
                      ],
                    ),
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
                final columns =
                    (constraints.maxWidth / (48 * (scale < 1 ? 1 : scale)))
                        .floor()
                        .clamp(1, 7);
                final lineCount = (7 / columns).ceil();
                return SizedBox(
                  height:
                      lineCount * 76 * (scale < 1 ? 1 : scale) +
                      (lineCount - 1) * 4,
                  child: VitalPager(
                    key: const ValueKey('dashboard-calendar-dates'),
                    retainPages: false,
                    index: weekIndex(visibleWeek),
                    itemCount: lastWeek + 1,
                    duration: VitalMotion.calendar,
                    onChanged: (index) => setState(
                      () => visibleWeek = CivilDate(1, 1, 1).addDays(index * 7),
                    ),
                    itemBuilder: (_, index) => Column(
                      children: [
                        for (var line = 0; line < lineCount; line++)
                          Padding(
                            padding: EdgeInsets.only(top: line == 0 ? 0 : 4),
                            child: Row(
                              children: [
                                for (var col = 0; col < columns; col++)
                                  Expanded(
                                    child: Builder(
                                      builder: (_) {
                                        final offset = line * columns + col;
                                        final date = DateTime.utc(1, 1, 1).add(
                                          Duration(days: index * 7 + offset),
                                        );
                                        if (offset > 6 || date.year > 9999) {
                                          return const SizedBox.shrink();
                                        }
                                        final day = CivilDate.fromDateTime(
                                          date,
                                        );
                                        return Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 1,
                                          ),
                                          child: _DayPill(
                                            day: day,
                                            active: day == widget.selected,
                                            onPressed: () =>
                                                widget.onSelect(day),
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          if (!widget.zoneKnown)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text(
                t.featureWeekUtc,
                style: StitchType.caption.copyWith(color: c.muted),
              ),
            ),
        ],
      ),
    );
  }
}

class _WeekArrow extends StatelessWidget {
  const _WeekArrow({
    required this.icon,
    required this.label,
    required this.onPressed,
  });
  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: label,
    onTap: onPressed,
    child: ExcludeSemantics(
      child: StitchButton(
        quiet: true,
        compact: true,
        onPressed: onPressed,
        child: Icon(icon, size: 20),
      ),
    ),
  );
}

class _DayPill extends StatelessWidget {
  const _DayPill({
    required this.day,
    required this.active,
    required this.onPressed,
  });
  final CivilDate day;
  final bool active;
  final VoidCallback onPressed;
  @override
  Widget build(BuildContext context) {
    final c = StitchColors(context);
    final locale = Localizations.localeOf(context).toLanguageTag();
    final label = DateFormat.yMMMMEEEEd(locale).format(day.calendarValue);
    return Semantics(
      button: true,
      selected: active,
      label: label,
      onTap: onPressed,
      child: ExcludeSemantics(
        child: Clickable(
          onPressed: onPressed,
          child: AnimatedContainer(
            duration: VitalMotion.duration(context, VitalMotion.choice),
            curve: VitalMotion.geometry,
            margin: const EdgeInsets.symmetric(horizontal: 3),
            constraints: const BoxConstraints(minWidth: 48, minHeight: 76),
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 2),
            decoration: BoxDecoration(
              color: active ? c.accent : c.inset,
              borderRadius: BorderRadius.circular(VitalLayout.sectionRadius),
              border: Border.all(color: active ? c.accent : c.line),
            ),
            child: Column(
              children: [
                Text(
                  DateFormat.E(locale).format(day.calendarValue),
                  textAlign: TextAlign.center,
                  style: StitchType.small.copyWith(
                    color: active ? c.accentInk : c.muted,
                  ),
                ),
                Text(
                  '${day.day}',
                  style: StitchType.name.copyWith(
                    color: active ? c.accentInk : c.ink,
                  ),
                ),
                const SizedBox(height: 3),
                Container(
                  width: active ? 6 : 5,
                  height: active ? 6 : 5,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: active ? c.accentInk : Colors.transparent,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A read-only expectation for a browsed date. Record opens the existing
/// explicit-time form; no Taken, Skip or Snooze command is offered for a date
/// that is not today.
class _BrowsedDayRow extends StatelessWidget {
  const _BrowsedDayRow({super.key, required this.row, required this.day});
  final DailyRow row;
  final CivilDate day;
  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DailyRowCard(row: row, historyMode: true),
        if (!row.isResolved)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: StitchButton(
              compact: true,
              icon: LucideIcons.plus,
              onPressed: () => context.push(
                '/unplanned?item=${row.expectation.itemId}&day=$day',
              ),
              child: Text(t.record),
            ),
          ),
        const SizedBox(height: 8),
      ],
    );
  }
}

/// The recorded section for a browsed day. It reuses the existing paged record
/// surface, so correction and Undo stay the same commands as Today and History.
class DashboardDayRecorded extends ConsumerStatefulWidget {
  const DashboardDayRecorded({
    super.key,
    required this.scope,
    required this.day,
  });
  final FeedScope scope;
  final CivilDate day;
  @override
  ConsumerState<DashboardDayRecorded> createState() =>
      _DashboardDayRecordedState();
}

class _DashboardDayRecordedState extends ConsumerState<DashboardDayRecorded> {
  bool expanded = false;
  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context), c = StitchColors(context);
    final locale = Localizations.localeOf(context).toLanguageTag();
    final bounds = DisplayTime().dayBounds(
      widget.day,
      ref.watch(displayZoneProvider),
    );
    return StitchSurface(
      inset: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(LucideIcons.circleCheck, size: 18, color: c.muted),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t.statusRecorded, style: StitchType.name),
                    Text(
                      DateFormat.yMMMMEEEEd(locale)
                          .format(widget.day.calendarValue),
                      style: StitchType.caption.copyWith(color: c.muted),
                    ),
                  ],
                ),
              ),
              Semantics(
                button: true,
                label: t.statusRecorded,
                expanded: expanded,
                onTap: () => setState(() => expanded = !expanded),
                child: ExcludeSemantics(
                  child: StitchButton(
                    quiet: true,
                    compact: true,
                    onPressed: () => setState(() => expanded = !expanded),
                    child: Icon(
                      expanded
                          ? LucideIcons.chevronUp
                          : LucideIcons.chevronDown,
                      size: 18,
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (expanded)
            PagedRecordList(
              query: (
                itemId: null,
                scope: widget.scope,
                actualFrom: bounds.start,
                actualBefore: bounds.endExclusive,
                limit: 51,
                offset: 0,
              ),
              emptyBody: t.featureWeekNoRecorded,
            ),
        ],
      ),
    );
  }
}

class TodayFutureDose extends ConsumerWidget {
  const TodayFutureDose({
    super.key,
    required this.next,
    required this.zone,
    required this.now,
  });
  final AsyncValue<DailyPlanNextRows> next;
  final String? zone;
  final DateTime now;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final candidate = todayNextFutureRow(next.value?.rows ?? [], now);
    if (candidate == null) {
      return Text(
        next.hasError ? t.planNextReview : t.planIncomplete,
        style: StitchType.caption,
      );
    }
    final (summary, start) = candidate;
    final item = ref.watch(itemLookupProvider(summary.plan.itemId)).value;
    final expectation = summary.result.next!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(item?.name ?? t.stitchNextDose, style: StitchType.name),
        Text(
          '${expectation.amount.enteredText} ${expectation.amount.unit}',
          style: StitchType.body,
        ),
        Text(
          displayStamp(context, ref, start, zoneId: expectation.zoneId),
          style: StitchType.caption,
        ),
        if (!next.value!.complete || !summary.result.complete)
          Text(t.planIncomplete, style: StitchType.caption),
        if (item != null)
          StitchButton(
            onPressed: () => context.push('/record/${item.id}'),
            child: Text(t.record),
          ),
      ],
    );
  }
}

class _ContextCards extends ConsumerWidget {
  const _ContextCards();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context), c = StitchColors(context);
    final notices = ref.watch(
      stockNoticeProvider((scope: const FeedScope.me(), offset: 0)),
    );
    final container = notices.value?.rows.firstOrNull?.container;
    final itemName = notices.value?.rows.firstOrNull?.itemName;
    if (container == null) return const SizedBox.shrink();
    return StitchSurface(
      inset: true,
      radius: 16,
      child: Row(
        children: [
          Icon(LucideIcons.triangleAlert, size: 20, color: c.amber),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t.dashboardStockAttention, style: StitchType.body),
                Text(
                  itemName ?? container.label,
                  style: StitchType.caption.copyWith(color: c.muted),
                ),
              ],
            ),
          ),
          StitchButton(
            quiet: true,
            compact: true,
            onPressed: () => context.push('/stock/$meId'),
            child: Text(t.review),
          ),
        ],
      ),
    );
  }
}
