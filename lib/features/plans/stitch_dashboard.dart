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
import '../recording/record_pages.dart' show LoadFailure;
import '../stock/stock_providers.dart';
import '../stock/stock_widgets.dart' show stockAmountNumber, StockNotices;
import 'daily_feed.dart';
import 'plan_providers.dart';
import 'today_hero.dart';
import 'today_model.dart';
import 'today_plan_rows.dart';
import 'today_prn.dart';

/// Composition transcribed from Dashboard — Timeline & Velocity in Stitch.
/// Weekly browsing, favourites and the two context metrics retain their visual
/// places while unavailable capabilities remain explicit placeholders.
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

  @override
  void dispose() {
    rollover?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context), c = StitchColors(context);
    final scope = widget.scope;
    final daily = ref.watch(dailyFeedProvider(scope));
    final plans = ref.watch(scopePlansProvider(scope));
    final next = ref.watch(nextDailyPlansProvider(scope));
    final zone = ref.watch(observedDeviceZoneProvider).value?.zoneId;
    final rows = daily.value?.rows ?? const <DailyRow>[];
    final count = todayUseCount(rows);
    final known =
        daily.hasValue &&
        daily.value!.complete &&
        rows.every((r) => r.actionsComplete);
    final now = ref.watch(todayNowProvider)();
    final day = DisplayTime()
        .instant(now, ref.watch(displayZoneProvider))
        .civilDate;
    final end = DisplayTime()
        .dayBounds(day, ref.watch(displayZoneProvider))
        .endExclusive;
    if (dayEnd != end) {
      dayEnd = end;
      rollover?.cancel();
      rollover = Timer(
        end.difference(now) + const Duration(milliseconds: 1),
        () {
          if (!mounted) return;
          setState(() => dayEnd = null);
          ref.invalidate(dailyFeedProvider(scope));
          ref.invalidate(nextDailyPlansProvider(scope));
        },
      );
    }
    final pending =
        todayNextPendingRow(rows)?.$1 ??
        rows.where((r) => !r.isResolved).firstOrNull;
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
          _WeekStrip(day: day),
          const SizedBox(height: 24),
          if (daily.hasError)
            LoadFailure(onRetry: () => ref.invalidate(dailyFeedProvider(scope)))
          else if (pending != null)
            DailyRowCard(
              key: ValueKey(('hero', pending.expectation.identity)),
              row: pending,
              presentation: DailyCardPresentation.hero,
            )
          else
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
                  // The existing future resolver supplies the next expectation even
                  // when today's rows are empty or resolved.
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
                      ? t.designTodayNothingPlanned
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
          Row(
            children: [
              Expanded(
                child: Text(
                  t.planAsNeeded,
                  style: StitchType.small.copyWith(
                    color: c.muted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              StitchButton(
                quiet: true,
                compact: true,
                onPressed: () =>
                    showStitchPlaceholder(context, t.stitchConfigure),
                child: Text(
                  t.stitchConfigure,
                  style: StitchType.small.copyWith(color: c.accent),
                ),
              ),
            ],
          ),
          _QuickLog(plans: plans),
          const SizedBox(height: 24),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text(t.stitchSequence, style: StitchType.heading),
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
                      DailyRowCard(
                        key: ValueKey(row.expectation.identity),
                        row: row,
                        presentation: DailyCardPresentation.timeline,
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
                    t.planNothingToday,
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
        ],
      ),
    );
  }
}

class _WeekStrip extends StatelessWidget {
  const _WeekStrip({required this.day});
  final CivilDate day;
  @override
  Widget build(BuildContext context) {
    final c = StitchColors(context), t = AppLocalizations.of(context);
    final today = DateTime(day.year, day.month, day.day);
    final first = today.subtract(Duration(days: today.weekday - 1));
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var i = 0; i < 7; i++)
            Builder(
              builder: (context) {
                final date = first.add(Duration(days: i)),
                    active = date.day == day.day && date.month == day.month;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Semantics(
                    selected: active,
                    label: DateFormat.yMMMMEEEEd(
                      Localizations.localeOf(context).toLanguageTag(),
                    ).format(date),
                    child: Clickable(
                      onPressed: () => active
                          ? null
                          : showStitchPlaceholder(context, t.stitchWeek),
                      child: Container(
                        width: active ? 56 : 48,
                        constraints: const BoxConstraints(minHeight: 64),
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(
                          color: active
                              ? (c.dark ? const Color(0xff1a5c52) : c.accent)
                              : (c.dark ? c.surface : c.inset),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Column(
                          children: [
                            Text(
                              DateFormat.E(
                                Localizations.localeOf(context).toLanguageTag(),
                              ).format(date),
                              style: StitchType.small.copyWith(
                                color: active
                                    ? (c.dark ? c.accent : Colors.white)
                                    : c.muted,
                              ),
                            ),
                            Text(
                              '${date.day}',
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
              },
            ),
          Semantics(
            label: t.history,
            child: StitchButton(
              onPressed: () => context.go('/history'),
              child: Icon(LucideIcons.calendarDays, color: c.muted, size: 20),
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickLog extends ConsumerWidget {
  const _QuickLog({required this.plans});
  final AsyncValue<List<SavedDailyPlan>> plans;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final prn =
        plans.value
            ?.where((p) => p.plan.timing is AsNeeded)
            .take(100)
            .toList() ??
        [];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final saved in prn)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: StitchButton(
                icon: LucideIcons.plus,
                compact: true,
                onPressed: () => context.push('/record/${saved.plan.itemId}'),
                child: Text(
                  ref
                          .watch(itemLookupProvider(saved.plan.itemId))
                          .value
                          ?.name ??
                      t.record,
                ),
              ),
            ),
          if (prn.isEmpty)
            StitchButton(
              icon: LucideIcons.plus,
              compact: true,
              onPressed: () => context.go('/substances'),
              child: Text(t.record),
            ),
          const SizedBox(width: 8),
          StitchButton(
            icon: LucideIcons.activity,
            compact: true,
            onPressed: () => context.push('/supporting'),
            child: Text(t.stitchObservation),
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
