import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../app/display_preferences.dart';
import '../../app/storage.dart';
import '../../data/record_store.dart';
import '../../l10n/app_localizations.dart';
import '../../ui/vital_ui.dart';
import 'today_model.dart';

/// Injectable now, mirroring the history page's provider seam. Tests can fix
/// the clock; production reads the real UTC instant once per build.
final todayNowProvider = Provider<DateTime Function()>(
  (ref) =>
      () => DateTime.now().toUtc(),
);

/// The Today hero: today's date, a truthful recorded/skipped/planned summary
/// and the real next expected dose. Schedules are expectations, never proof of
/// actual use; a day with no planned doses is never shown as complete, the
/// countdown only appears when a real pending expected start exists, and a
/// day whose calculation or action history is incomplete stays visibly
/// partial instead of presenting a whole-day ratio.
class TodayHero extends ConsumerStatefulWidget {
  const TodayHero({
    super.key,
    required this.result,
    required this.next,
    required this.observedZone,
    this.onRollover,
  });
  final DailyRows result;
  final AsyncValue<DailyPlanNextRows> next;

  /// The observed device zone, used for the shown date and next-plan rows
  /// whose zone follows the device. Null stays visibly incomplete: the shown
  /// date is labelled as the UTC fallback rather than a known local date.
  final String? observedZone;

  /// Called when the display-zone day rolls over so the feed can re-read.
  final VoidCallback? onRollover;
  @override
  ConsumerState<TodayHero> createState() => _TodayHeroState();
}

class _TodayHeroState extends ConsumerState<TodayHero> {
  final display = DisplayTime();
  Timer? rolloverTimer;
  DateTime? dayEnd;

  void cancelRollover() {
    rolloverTimer?.cancel();
    rolloverTimer = null;
  }

  @override
  void dispose() {
    cancelRollover();
    dayEnd = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final zone = ref.watch(displayZoneProvider);
    final formatter = displayFormatter(
      context,
      ref.watch(displayPreferencesProvider).timeFormat,
    );
    final now = ref.watch(todayNowProvider)();
    final shownDay = display.instant(now, zone).civilDate;
    final endExclusive = display.dayBounds(shownDay, zone).endExclusive;
    if (dayEnd != endExclusive) {
      dayEnd = endExclusive;
      cancelRollover();
      // One-shot at the displayed day boundary, matching the history page
      // pattern; no periodic frames, and dispose cancels it.
      rolloverTimer = Timer(
        endExclusive.difference(now) + const Duration(milliseconds: 1),
        () {
          if (!mounted) return;
          setState(() => dayEnd = null);
          widget.onRollover?.call();
        },
      );
    }
    // Without an observed device zone the day above is the UTC fallback, and
    // the local date line must not pretend it is a known local date.
    final zoneKnown = widget.observedZone != null;
    final shownDate = formatter.date(display.instant(now, zone), full: true);
    final count = todayUseCount(widget.result.rows);
    final dayKnown =
        widget.result.complete &&
        widget.result.rows.every((row) => row.actionsComplete);
    return VitalSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  zoneKnown
                      ? shownDate
                      // Explicitly labelled UTC fallback; never a claimed
                      // local day when no zone was observed.
                      : t.designTodayUtcDate(shownDate),
                  style: VitalType.metadata.copyWith(
                    color: Theme.of(context).colorScheme.mutedForeground,
                  ),
                ),
              ),
              // The remaining count is only a whole-day figure when the row
              // set and every action history are complete.
              if (dayKnown && count.unresolved > 0)
                VitalBadge(t.designTodayRemaining(count.unresolved)),
            ],
          ),
          const SizedBox(height: VitalLayout.gap),
          Semantics(
            header: true,
            child: Text(t.designTodayHeading, style: VitalType.title),
          ),
          const SizedBox(height: 4),
          daySummary(context, t, count, dayKnown),
          const SizedBox(height: VitalLayout.gap),
          Semantics(
            header: true,
            child: Text(t.designTodayNext, style: VitalType.label),
          ),
          const SizedBox(height: 6),
          nextLines(context, ref, t, now),
        ],
      ),
    );
  }

  Widget daySummary(
    BuildContext context,
    AppLocalizations t,
    TodayUseCount count,
    bool dayKnown,
  ) {
    final result = widget.result;
    if (dayKnown) {
      if (count.planned == 0) {
        // Zero planned doses are never a complete day; the bar is hidden
        // instead of showing a fabricated ratio.
        return Text(t.designTodayNothingPlanned);
      }
      // The measured summary: the row set and every shown action history are
      // complete, so the recorded share of planned doses is factual. Skips
      // stay distinct from recorded use and the widget clamps the bar only.
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            t.designTodayRecorded(count.recorded, count.planned, count.skipped),
          ),
          VitalProgress(
            label: t.designTodayProgressLabel,
            valueText: t.designTodayRecordedCount(count.recorded),
            totalText: t.designTodayPlannedTotal(count.planned),
            fraction: count.recorded / count.planned,
            annotation: count.skipped > 0
                ? t.designTodaySkippedCount(count.skipped)
                : null,
          ),
        ],
      );
    }
    // Partial day: the shown counts are still factual for the rows that are
    // present, but no ratio or remaining total may claim the whole day. The
    // reason stays explicit: bounded calculation, unavailable zone or an
    // incomplete action history.
    final issue = !result.complete
        ? result.issue == DailyCalculationIssue.observedZoneUnavailable
              ? t.planZoneUnavailable
              : result.issue == null
              ? t.planIncomplete
              : t.planCalculationIssue
        : t.designTodayActionsIncomplete;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (count.planned > 0)
          Text(t.designTodayRecordedSoFar(count.recorded, count.skipped)),
        VitalProgress.noTotal(
          label: t.designTodayProgressLabel,
          annotation: issue,
        ),
      ],
    );
  }

  Widget nextLines(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations t,
    DateTime now,
  ) {
    final pending = todayNextPendingRow(widget.result.rows);
    if (pending != null) {
      final row = pending.$1;
      final start = pending.$2;
      final needsClockReview =
          row.expectation.resolution == DailyResolution.missingClock ||
          row.expectation.resolution == DailyResolution.repeatedClock;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            t.designTodayNextPlanNamed(
              row.itemName,
              row.expectation.amount.enteredText,
              row.expectation.amount.unit,
              displayStamp(context, ref, start, zoneId: row.expectation.zoneId),
            ),
          ),
          if (needsClockReview) Text(t.planNextReview),
          TodayCountdown(target: start),
        ],
      );
    }
    if (todayHasPendingUntimed(widget.result.rows)) {
      return Text(t.designTodayNextUntimed);
    }
    // Even with no shown rows today, a real future planned start is worth
    // showing. Loading or missing values stay unclaimed instead of guessed.
    final next = widget.next.value;
    if (next == null) {
      return Text(widget.next.hasError ? t.planNextReview : t.loadingRecords);
    }
    final candidate = todayNextFutureRow(next.rows, now);
    if (candidate != null) {
      final (summary, start) = candidate;
      final basis = summary.plan.zoneBasis;
      final rowZone = basis is FixedHome ? basis.zoneId : widget.observedZone;
      if (rowZone == null) {
        return Text(t.planZoneUnavailable);
      }
      final item = ref
          .watch<AsyncValue<SubstanceItem?>>(
            itemLookupProvider(summary.plan.itemId),
          )
          .value;
      final expectation = summary.result.next!;
      // Anonymous future plans include the substance and planned amount only
      // when they are really known; nothing about the dose is invented.
      final name = item?.name;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            name == null
                ? t.designTodayNextPlanUnnamed(
                    expectation.amount.enteredText,
                    expectation.amount.unit,
                    displayStamp(context, ref, start, zoneId: rowZone),
                  )
                : t.designTodayNextPlanNamed(
                    name,
                    expectation.amount.enteredText,
                    expectation.amount.unit,
                    displayStamp(context, ref, start, zoneId: rowZone),
                  ),
          ),
          if (!next.complete || !summary.result.complete)
            Text(t.planIncomplete),
        ],
      );
    }
    if (!next.complete) return Text(t.planIncomplete);
    // Decided rows without a timed next start belong to the plan rows below,
    // which show the real next planned date.
    return const SizedBox.shrink();
  }
}

/// The minute countdown under the next dose. One-shot timers re-arm only while
/// a countdown is honest; reaching the expected start shows a due state and
/// the timer stops. A dose under a minute away is not due: its remaining
/// interval is stated explicitly until the start instant. This is display
/// only: no dose decision is claimed.
class TodayCountdown extends ConsumerStatefulWidget {
  const TodayCountdown({super.key, required this.target});
  final DateTime target;
  @override
  ConsumerState<TodayCountdown> createState() => _TodayCountdownState();
}

class _TodayCountdownState extends ConsumerState<TodayCountdown> {
  Timer? timer;

  void arm() {
    timer?.cancel();
    timer = null;
    final delay = todayCountdownTick(
      ref.read(todayNowProvider)(),
      widget.target,
    );
    if (delay == null) return;
    timer = Timer(delay, () {
      if (mounted) setState(() {});
      arm();
    });
  }

  @override
  void initState() {
    super.initState();
    arm();
  }

  @override
  void didUpdateWidget(covariant TodayCountdown oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.target != widget.target) arm();
  }

  @override
  void dispose() {
    timer?.cancel();
    timer = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final now = ref.watch(todayNowProvider)();
    final remaining = widget.target.difference(now);
    if (remaining <= Duration.zero) {
      return Text(t.designTodayNextDue);
    }
    if (remaining < const Duration(minutes: 1)) {
      // A future dose under a minute away is not due; the remaining interval
      // is stated until the expected start arrives.
      return Text(t.designTodayUnderMinute);
    }
    final minutes = todayCountdownMinutes(now, widget.target);
    if (minutes == null) return const SizedBox.shrink();
    return Text(t.designTodayNextInMinutes(minutes));
  }
}
