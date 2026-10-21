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
import '../stock/stock_widgets.dart' show stockAmountNumber, StockNotices;
import 'daily_feed.dart';
import 'dashboard_favourites.dart';
import 'dashboard_week.dart';
import 'plan_providers.dart';
import 'today_hero.dart';
import 'today_model.dart';
import 'today_plan_rows.dart';
import 'today_prn.dart';

/// Composition transcribed from Dashboard — Timeline & Velocity in Stitch.
///
/// The week strip browses real civil days, the weekly summary separates
/// planned, recorded and skipped slots, and the as-needed row has a durable
/// saved subset and order. Today keeps its one-tap Taken, Skip, Snooze, Edit
/// and Undo actions. A browsed date is inspection only; its Record action opens
/// the existing explicit-time form so a current-time command can never be
/// applied silently to another day.
class StitchDashboard extends ConsumerStatefulWidget {
  const StitchDashboard({super.key, required this.scope});
  final FeedScope scope;
  @override
  ConsumerState<StitchDashboard> createState() => _StitchDashboardState();
}

class _StitchDashboardState extends ConsumerState<StitchDashboard> {
  bool management = false;
  Timer? rollover;
  DateTime? dayEnd;
  CivilDate? selectedDay;
  bool followToday = true;

  @override
  void dispose() {
    rollover?.cancel();
    super.dispose();
  }

  void selectDay(CivilDate day, CivilDate today) {
    setState(() {
      selectedDay = day;
      followToday = day == today;
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context), c = StitchColors(context);
    final scope = widget.scope;
    final displayZone = ref.watch(displayZoneProvider);
    final now = ref.watch(todayNowProvider)();
    final today = DisplayTime().instant(now, displayZone).civilDate;
    if (selectedDay == null || followToday) selectedDay = today;
    final selected = selectedDay!;
    final selectedIsToday = selected == today;
    final weekStart = dashboardWeekStart(selected);
    // Keep Today's established now-based read (including overdue interval
    // rows and its capture rules) and use the dated read only for a browsed day.
    final daily = selectedIsToday
        ? ref.watch(dailyFeedProvider(scope))
        : ref.watch(dailyDayFeedProvider((scope: scope, day: selected)));
    final week = ref.watch(
      dailyWeekFeedProvider((scope: scope, weekStart: weekStart)),
    );

    final plans = ref.watch(scopePlansProvider(scope));
    final next = ref.watch(nextDailyPlansProvider(scope));
    final zone = ref.watch(observedDeviceZoneProvider).value?.zoneId;
    final rows = daily.value?.rows ?? const <DailyRow>[];
    final summary = week.value == null
        ? null
        : dashboardWeekSummary(week.value!);
    final count = todayUseCount(rows);
    final known =
        daily.hasValue &&
        daily.value!.complete &&
        rows.every((r) => r.actionsComplete);
    final end = DisplayTime().dayBounds(today, displayZone).endExclusive;
    if (dayEnd != end) {
      dayEnd = end;
      rollover?.cancel();
      rollover = Timer(
        end.difference(now) + const Duration(milliseconds: 1),
        () {
          if (!mounted) return;
          setState(() {
            dayEnd = null;
            if (followToday) {
              selectedDay = DisplayTime()
                  .instant(
                    ref.read(todayNowProvider)(),
                    ref.read(displayZoneProvider),
                  )
                  .civilDate;
            }
          });
          ref.invalidate(dailyFeedProvider(scope));
          ref.invalidate(nextDailyPlansProvider(scope));
        },
      );
    }
    final pending = selectedIsToday
        ? todayNextPendingRow(rows)?.$1 ??
              rows.where((r) => !r.isResolved).firstOrNull
        : null;
    final groups = groupTodayRows(
      rows,
      timeLabel: (row, start) {
        final time = DisplayTime().instant(start, row.expectation.zoneId);
        return TodayTimeLabel(
          key: '${row.expectation.zoneId}|${time.time24}',
          title: displayWallTime(
            context,
            ref,
            WallTime(time.hour, time.minute),
          ),
        );
      },
      untimedTitle: t.todayDue,
    );
    return DefaultTextStyle.merge(
      style: StitchType.body.copyWith(color: c.ink),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(LucideIcons.badgeCheck, size: 18, color: c.accent),
              const SizedBox(width: 5),
              Expanded(
                child: Text(t.stitchDailyProgress, style: StitchType.label),
              ),
              if (known && count.planned > 0) ...[
                Text(
                  '${(count.recorded / count.planned * 100).round()}%',
                  style: StitchType.label.copyWith(
                    color: c.accent,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 5),
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    value: (count.recorded / count.planned).clamp(0, 1),
                  ),
                ),
              ] else
                Text(
                  known ? t.stitchGroupCount(0) : t.stitchPartial,
                  style: StitchType.small.copyWith(color: c.muted),
                ),
            ],
          ),
          const SizedBox(height: 8),
          _DashboardWeekBar(
            today: today,
            selected: selected,
            zoneKnown: zone != null,
            onSelect: (day) => selectDay(day, today),
            onPrevious: () => selectDay(selected.addDays(-7), today),
            onNext: () => selectDay(selected.addDays(7), today),
            onToday: () => selectDay(today, today),
          ),
          const SizedBox(height: 12),
          _DashboardWeekSummaryCard(
            result: week,
            summary: summary,
            onRetry: () => ref.invalidate(
              dailyWeekFeedProvider((scope: scope, weekStart: weekStart)),
            ),
          ),
          const SizedBox(height: 16),
          if (!selectedIsToday) ...[
            _BrowsingNotice(day: selected),
            const SizedBox(height: 12),
          ],
          if (daily.hasError)
            LoadFailure(
              onRetry: () => selectedIsToday
                  ? ref.invalidate(dailyFeedProvider(scope))
                  : ref.invalidate(
                      dailyDayFeedProvider((scope: scope, day: selected)),
                    ),
            )
          else if (selectedIsToday && pending != null)
            DailyRowCard(
              key: ValueKey(('hero', pending.expectation.identity)),
              row: pending,
              presentation: DailyCardPresentation.hero,
            )
          else if (selectedIsToday)
            StitchSurface(
              radius: 16,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  StitchBadge(t.stitchNextDose, dot: true),
                  const SizedBox(height: 14),
                  Text(
                    daily.isLoading ? t.loadingRecords : t.stitchNoNext,
                    style: StitchType.heading,
                  ),
                  const SizedBox(height: 8),
                  // The existing future resolver supplies the next expectation
                  // even when today's rows are empty or resolved.
                  if (next.value?.rows.any((r) => r.result.next != null) ??
                      false)
                    TodayFutureDose(next: next, zone: zone, now: now)
                  else
                    Text(
                      t.stitchNextHelp,
                      style: StitchType.body.copyWith(color: c.muted),
                    ),
                  const SizedBox(height: 16),
                  StitchButton(
                    primary: true,
                    icon: LucideIcons.plus,
                    onPressed: () => context.push('/create'),
                    child: Text(t.create),
                  ),
                ],
              ),
            ),
          if (daily.hasValue && !known) ...[
            const SizedBox(height: 8),
            Text(
              daily.value!.issue ==
                      DailyCalculationIssue.observedZoneUnavailable
                  ? t.planZoneUnavailable
                  : t.planIncomplete,
              style: StitchType.caption.copyWith(color: c.amber),
            ),
          ],
          if (known)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Semantics(
                liveRegion: true,
                child: Text(
                  count.planned == 0
                      ? (selectedIsToday
                            ? t.designTodayNothingPlanned
                            : t.featureWeekNothingPlanned)
                      : t.designTodayRecorded(
                          count.recorded,
                          count.planned,
                          count.skipped,
                        ),
                  style: StitchType.small.copyWith(color: c.muted),
                ),
              ),
            ),
          const SizedBox(height: 24),
          DashboardQuickRecord(scope: scope),
          const SizedBox(height: 24),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text(
                  selectedIsToday ? t.stitchSequence : t.featureWeekDaySequence,
                  style: StitchType.heading,
                ),
              ),
              if (daily.hasValue)
                Text(
                  t.stitchSubstanceCount(
                    rows.map((r) => r.expectation.itemId).toSet().length,
                  ),
                  style: StitchType.small.copyWith(color: c.muted),
                ),
            ],
          ),
          const SizedBox(height: 16),
          for (final group in groups)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: StitchSurface(
                radius: 16,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 9,
                          height: 9,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: group.rows.every((r) => r.isResolved)
                                ? c.accent
                                : c.amber,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(group.title, style: StitchType.heading),
                        ),
                        StitchBadge(
                          t.stitchGroupCount(
                            group.rows.fold<int>(
                              0,
                              (n, r) => n + r.plannedCount,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    for (final row in group.rows)
                      if (selectedIsToday)
                        DailyRowCard(
                          key: ValueKey(row.expectation.identity),
                          row: row,
                          presentation: DailyCardPresentation.timeline,
                        )
                      else
                        _BrowsedDayRow(
                          key: ValueKey(row.expectation.identity),
                          row: row,
                        ),
                  ],
                ),
              ),
            ),
          if (daily.hasValue && rows.isEmpty)
            StitchSurface(
              radius: 16,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    selectedIsToday
                        ? t.planNothingToday
                        : t.featureWeekNothingPlanned,
                    style: StitchType.body.copyWith(color: c.muted),
                  ),
                  const SizedBox(height: 12),
                  StitchButton(
                    icon: LucideIcons.plus,
                    onPressed: () => context.push('/create'),
                    child: Text(t.create),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 8),
          const _ContextCards(),
          const SizedBox(height: 16),
          StitchButton(
            quiet: true,
            compact: true,
            onPressed: () => setState(() => management = !management),
            icon: management ? LucideIcons.chevronUp : LucideIcons.chevronDown,
            child: Text(t.stitchScheduleManage),
          ),
          if (management) ...[
            StockNotices(scope: scope),
            TodayPrnPanel(plans: plans, scope: scope),
            TodayPlanRows(scope: scope, next: next),
          ],
          if (!selectedIsToday) ...[
            const SizedBox(height: 16),
            DashboardDayRecorded(
              key: ValueKey(('recorded', selected)),
              scope: scope,
              day: selected,
            ),
          ],
        ],
      ),
    );
  }
}

/// Week navigation and the Monday-based day strip.
class _DashboardWeekBar extends StatelessWidget {
  const _DashboardWeekBar({
    required this.today,
    required this.selected,
    required this.zoneKnown,
    required this.onSelect,
    required this.onPrevious,
    required this.onNext,
    required this.onToday,
  });
  final CivilDate today, selected;
  final bool zoneKnown;
  final ValueChanged<CivilDate> onSelect;
  final VoidCallback onPrevious, onNext, onToday;

  @override
  Widget build(BuildContext context) {
    final c = StitchColors(context), t = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).toLanguageTag();
    final start = dashboardWeekStart(selected);
    final end = start.addDays(6);
    final sameYear = start.year == end.year;
    final pattern = sameYear ? 'd MMM' : 'd MMM y';
    final range = t.featureWeekRange(
      DateFormat(pattern, locale).format(start.calendarValue),
      DateFormat(pattern, locale).format(end.calendarValue),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            _WeekArrow(
              icon: LucideIcons.chevronLeft,
              label: t.featureWeekPrevious,
              onPressed: onPrevious,
            ),
            Expanded(
              child: Text(
                range,
                textAlign: TextAlign.center,
                style: StitchType.small.copyWith(color: c.muted),
              ),
            ),
            _WeekArrow(
              icon: LucideIcons.chevronRight,
              label: t.featureWeekNext,
              onPressed: onNext,
            ),
            if (selected != today)
              StitchButton(
                quiet: true,
                compact: true,
                onPressed: onToday,
                child: Text(
                  t.today,
                  style: StitchType.small.copyWith(color: c.accent),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final day in dashboardWeekDays(start))
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: _DayPill(
                    day: day,
                    active: day == selected,
                    onPressed: () => onSelect(day),
                  ),
                ),
              Semantics(
                label: t.history,
                button: true,
                onTap: () => context.go('/history'),
                child: ExcludeSemantics(
                  child: StitchButton(
                    onPressed: () => context.go('/history'),
                    child: Icon(
                      LucideIcons.calendarDays,
                      color: c.muted,
                      size: 20,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (!zoneKnown) ...[
          const SizedBox(height: 6),
          Text(
            t.featureWeekUtc,
            style: StitchType.caption.copyWith(color: c.amber),
          ),
        ],
      ],
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
    final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
    final width = (active ? 56.0 : 48.0) * (scale > 1 ? scale : 1);
    final label = DateFormat.yMMMMEEEEd(locale).format(day.calendarValue);
    return Semantics(
      button: true,
      selected: active,
      label: label,
      onTap: onPressed,
      child: ExcludeSemantics(
        child: Clickable(
          onPressed: onPressed,
          child: Container(
            width: width,
            constraints: const BoxConstraints(minWidth: 48, minHeight: 64),
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
            decoration: BoxDecoration(
              color: active
                  ? (c.dark ? const Color(0xff1a5c52) : c.accent)
                  : (c.dark ? c.surface : c.inset),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Column(
              children: [
                Text(
                  DateFormat.E(locale).format(day.calendarValue),
                  textAlign: TextAlign.center,
                  style: StitchType.small.copyWith(
                    color: active
                        ? (c.dark ? c.accent : Colors.white)
                        : c.muted,
                  ),
                ),
                Text(
                  '${day.day}',
                  style: StitchType.name.copyWith(
                    color: active && !c.dark ? Colors.white : c.ink,
                  ),
                ),
                const SizedBox(height: 3),
                Container(
                  width: active ? 6 : 5,
                  height: active ? 6 : 5,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: active
                        ? (c.dark ? c.accent : Colors.white)
                        : c.muted.withValues(alpha: .3),
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

/// Factual weekly totals. A bounded, zone-blocked or incomplete action history
/// keeps the card labelled partial and never draws a whole-week ratio.
class _DashboardWeekSummaryCard extends StatelessWidget {
  const _DashboardWeekSummaryCard({
    required this.result,
    required this.summary,
    required this.onRetry,
  });
  final AsyncValue<DailyRows> result;
  final DashboardWeekSummary? summary;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context), c = StitchColors(context);
    if (result.hasError) return LoadFailure(onRetry: onRetry);
    final summary = this.summary;
    return StitchSurface(
      radius: 16,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(t.featureWeekSummary, style: StitchType.heading),
              ),
              if (summary != null && !summary.complete)
                StitchBadge(t.stitchPartial, warning: true),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            t.featureWeekSummaryHelp,
            style: StitchType.caption.copyWith(color: c.muted),
          ),
          if (summary == null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                t.loadingRecords,
                style: StitchType.caption.copyWith(color: c.muted),
              ),
            )
          else ...[
            if (!summary.complete) ...[
              const SizedBox(height: 6),
              Text(
                result.value?.issue ==
                        DailyCalculationIssue.observedZoneUnavailable
                    ? t.planZoneUnavailable
                    : t.featureWeekIncomplete,
                style: StitchType.caption.copyWith(color: c.amber),
              ),
            ],
            const SizedBox(height: 6),
            if (!summary.hasPlans)
              Text(
                t.featureWeekNoPlans,
                style: StitchType.body.copyWith(color: c.muted),
              )
            else
              Wrap(
                spacing: VitalLayout.gap,
                runSpacing: VitalLayout.gap,
                children: [
                  VitalMetric(
                    label: t.featureWeekPlanned,
                    value: '${summary.planned}',
                  ),
                  VitalMetric(
                    label: t.featureWeekRecorded,
                    value: '${summary.recorded}',
                  ),
                  VitalMetric(
                    label: t.featureWeekSkipped,
                    value: '${summary.skipped}',
                  ),
                ],
              ),
          ],
        ],
      ),
    );
  }
}

class _BrowsingNotice extends StatelessWidget {
  const _BrowsingNotice({required this.day});
  final CivilDate day;
  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context), c = StitchColors(context);
    final locale = Localizations.localeOf(context).toLanguageTag();
    return StitchSurface(
      inset: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              StitchBadge(t.featureWeekViewing, warning: true),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  DateFormat.yMMMMEEEEd(locale).format(day.calendarValue),
                  style: StitchType.name,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            t.featureWeekViewingHelp,
            style: StitchType.caption.copyWith(color: c.muted),
          ),
        ],
      ),
    );
  }
}

/// A read-only expectation for a browsed date. Record opens the existing
/// explicit-time form; no Taken, Skip or Snooze command is offered for a date
/// that is not today.
class _BrowsedDayRow extends StatelessWidget {
  const _BrowsedDayRow({super.key, required this.row});
  final DailyRow row;
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
              onPressed: () =>
                  context.push('/record/${row.expectation.itemId}'),
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
    final quantity = container?.balance.value;
    final cards = [
      StitchSurface(
        radius: 16,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    t.stitchBloodPressure.toUpperCase(),
                    style: StitchType.small.copyWith(color: c.muted),
                  ),
                ),
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: c.accent,
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '…',
              style: StitchType.heading.copyWith(fontWeight: FontWeight.w700),
            ),
            Text(
              t.stitchPreview,
              style: StitchType.caption.copyWith(color: c.muted),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 28,
              width: double.infinity,
              child: CustomPaint(
                painter: _PlaceholderSparkline(c.accent.withValues(alpha: .4)),
              ),
            ),
            StitchButton(
              quiet: true,
              compact: true,
              onPressed: () => context.push('/supporting'),
              child: Text(t.review),
            ),
          ],
        ),
      ),
      StitchSurface(
        radius: 16,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    t.stitchRefillBuffer.toUpperCase(),
                    style: StitchType.small.copyWith(color: c.muted),
                  ),
                ),
                Icon(LucideIcons.triangleAlert, size: 16, color: c.amber),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              quantity == null
                  ? container == null
                        ? '…'
                        : container.balance.limitReached
                        ? t.stockLimit
                        : t.stockUnknownValue
                  : t.stockQuantity(
                      stockAmountNumber(t, quantity),
                      container!.unit,
                    ),
              style: StitchType.heading.copyWith(
                color: c.amber,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (container != null)
              StitchBadge(
                container.balance.value == null ? t.stockUnknown : t.stockLow,
                warning: true,
              ),
            Text(
              itemName ?? t.stitchForecastPending,
              style: StitchType.caption.copyWith(color: c.muted),
            ),
            const SizedBox(height: 12),
            StitchButton(
              compact: true,
              onPressed: notices.hasError
                  ? () => ref.invalidate(
                      stockNoticeProvider((
                        scope: const FeedScope.me(),
                        offset: 0,
                      )),
                    )
                  : () => context.push('/stock/$meId'),
              icon: LucideIcons.packagePlus,
              primary: true,
              child: Text(notices.hasError ? t.retry : t.stock),
            ),
          ],
        ),
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) =>
          constraints.maxWidth < 300 ||
              MediaQuery.textScalerOf(context).scale(14) > 21
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [cards[0], const SizedBox(height: 8), cards[1]],
            )
          : IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: cards[0]),
                  const SizedBox(width: 8),
                  Expanded(child: cards[1]),
                ],
              ),
            ),
    );
  }
}

class _PlaceholderSparkline extends CustomPainter {
  const _PlaceholderSparkline(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, size.height * .8)
      ..cubicTo(
        size.width * .3,
        0,
        size.width * .35,
        size.height,
        size.width * .6,
        size.height * .3,
      )
      ..cubicTo(
        size.width * .85,
        -8,
        size.width * .85,
        size.height,
        size.width,
        size.height * .25,
      );
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_PlaceholderSparkline oldDelegate) =>
      color != oldDelegate.color;
}
