import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../app/display_preferences.dart';
import '../../app/device_zone.dart';
import '../../data/record_store.dart';
import '../../l10n/app_localizations.dart';
import '../../ui/stitch_ui.dart';
import '../plans/plan_providers.dart';
import '../stock/stock_widgets.dart' show stockAmountNumber;
import 'substance_summary_providers.dart';

/// The card composition in the current Stitch Substances export. Stored
/// values drive every label; the overview retains the complete source detail.
class StitchSubstanceCard extends ConsumerWidget {
  const StitchSubstanceCard({super.key, required this.item});
  final SubstanceItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context), c = StitchColors(context);
    final anchor = (personId: item.personId, itemId: item.id);
    final plans = ref.watch(summaryPlansProvider(anchor));
    final stock = ref.watch(summaryStockProvider(anchor));
    final next = ref.watch(
      nextDailyPlansProvider(FeedScope.person(item.personId)),
    );
    // Observations also refresh time-dependent pause state in the foreground.
    final zone = ref.watch(observedDeviceZoneProvider).value?.zoneId;
    final plan = plans.value?.firstOrNull?.plan;
    final paused =
        plan?.pauses.any((p) => p.contains(DateTime.now().toUtc())) ?? false;
    final timing = plan?.timing;
    final amount = switch (timing) {
      DailyCount(:final amount) => amount,
      DailySlots(:final slots) => slots.firstOrNull?.amount,
      ElapsedInterval(:final amount) => amount,
      MixedDailyCount(:final amount) => amount,
      DailyWindows(:final windows) => windows.firstOrNull?.amount,
      _ => null,
    };
    final summary = next.value?.rows
        .where((p) => p.plan.planId == plan?.planId)
        .firstOrNull;
    final expectation = summary?.result.next;
    final stockRow = stock.value?.firstOrNull;
    final balance = stockRow?.balance;
    final warning =
        stockRow?.notice == StockNoticeState.low ||
        stockRow?.notice == StockNoticeState.refill ||
        (balance?.isDeficit ?? false);
    final nextInstant = expectation?.instant ?? expectation?.windowStart;
    String? nextLabel;
    if (nextInstant != null && summary?.result.complete == true) {
      final shown = DisplayTime().instant(nextInstant, expectation!.zoneId);
      final current = DisplayTime().instant(
        DateTime.now().toUtc(),
        expectation.zoneId,
      );
      nextLabel = shown.civilDate == current.civilDate
          ? displayWallTime(context, ref, WallTime(shown.hour, shown.minute))
          : displayFormatter(
              context,
              ref.watch(displayPreferencesProvider).timeFormat,
            ).date(shown);
      if (expectation.zoneId != zone) {
        nextLabel = '$nextLabel (${expectation.zoneId})';
      }
    }
    String schedule;
    if (plans.hasError) {
      schedule = t.designSubstancesSummaryUnavailable;
    } else if (plans.isLoading && !plans.hasValue) {
      schedule = t.loadingRecords;
    } else if (plan == null) {
      schedule = t.designSubstancesNoSchedule;
    } else if (paused) {
      schedule = t.pauseState;
    } else if (timing is DailySlots && timing.slots.isNotEmpty) {
      schedule = t.stitchDailyAt(
        displayWallTime(context, ref, timing.slots.first.time),
      );
      if (timing.slots.length > 1) {
        schedule =
            '$schedule · ${t.designSubstancesMoreSlots(timing.slots.length - 1)}';
      }
    } else if (timing is AsNeeded) {
      schedule = t.stitchPrn;
    } else if (timing is DailyCount) {
      schedule = t.designSubstancesScheduleCount(
        timing.count,
        timing.amount.enteredText,
        timing.amount.unit,
      );
    } else if (timing is ElapsedInterval) {
      schedule = t.designSubstancesIntervalSchedule(
        timing.duration.hoursText,
        timing.amount.enteredText,
        timing.amount.unit,
      );
    } else if (timing is MixedDailyCount) {
      schedule = t.designSubstancesScheduleCount(
        timing.count,
        timing.amount.enteredText,
        timing.amount.unit,
      );
    } else if (timing is DailyWindows) {
      schedule = t.designSubstancesScheduleWindows(
        [
          for (final window in timing.windows)
            t.designSubstancesScheduleWindow(
              displayWallTime(context, ref, window.start),
              displayWallTime(context, ref, window.end),
              window.amount.enteredText,
              window.amount.unit,
            ),
        ].join(', '),
      );
    } else {
      schedule = t.planNextReview;
    }
    final stockText = stock.hasError
        ? t.designSubstancesSummaryUnavailable
        : stock.isLoading && !stock.hasValue
        ? t.loadingRecords
        : stockRow == null
        ? t.designSubstancesNoStock
        : balance!.limitReached
        ? t.stockLimit
        : balance.value == null
        ? t.stockUnknownValue
        : t.stitchStockRemaining(
            stockAmountNumber(t, balance.value!),
            stockRow.unit,
          );
    final uncertain =
        plans.hasError ||
        next.hasError ||
        (plan != null &&
            next.hasValue &&
            (summary == null || !summary.result.complete));
    final icon = paused
        ? LucideIcons.circlePause
        : timing is AsNeeded
        ? LucideIcons.cross
        : item.unit == 'ml'
        ? LucideIcons.droplet
        : LucideIcons.pill;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Clickable(
        onPressed: () => context.push('/substance/${item.id}'),
        disableTransition: MediaQuery.disableAnimationsOf(context),
        child: StitchSurface(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  StitchIcon(icon),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 5,
                          runSpacing: 3,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(item.name, style: StitchType.name),
                            StitchBadge(
                              paused
                                  ? t.stitchPaused
                                  : timing is AsNeeded
                                  ? t.stitchPrn
                                  : item.type,
                              warning: timing is AsNeeded,
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          amount == null
                              ? item.form
                              : t.stitchAmountForm(
                                  amount.enteredText,
                                  amount.unit,
                                  item.form,
                                ),
                          style: StitchType.body.copyWith(color: c.muted),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  ExcludeSemantics(
                    child: Icon(
                      LucideIcons.chevronRight,
                      size: 20,
                      color: c.muted,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    timing is AsNeeded
                        ? LucideIcons.asterisk
                        : LucideIcons.clock3,
                    size: 14,
                    color: c.accent,
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      schedule,
                      style: StitchType.caption.copyWith(color: c.muted),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 6,
                children: [
                  StitchBadge(stockText, warning: warning, dot: true),
                  if (nextLabel != null)
                    Text(
                      t.stitchNextAt(nextLabel),
                      style: StitchType.small.copyWith(color: c.muted),
                    )
                  else if (timing is AsNeeded)
                    Text(
                      t.stitchUntimed,
                      style: StitchType.small.copyWith(color: c.muted),
                    ),
                ],
              ),
              if ((stock.value?.length ?? 0) > 1) ...[
                const SizedBox(height: 4),
                Text(
                  t.designSubstancesMoreStock(stock.value!.length - 1),
                  style: StitchType.small.copyWith(color: c.muted),
                ),
              ],
              if ((stock.value?.length ?? 0) >= summaryStockLimit ||
                  (plans.value?.length ?? 0) >= summaryPlanLimit)
                Text(
                  t.planIncomplete,
                  style: StitchType.small.copyWith(color: c.amber),
                ),
              if (uncertain ||
                  (zone == null &&
                      plan?.zoneBasis is! FixedHome &&
                      plan != null)) ...[
                const SizedBox(height: 5),
                Text(
                  zone == null && plan?.zoneBasis is! FixedHome
                      ? t.planZoneUnavailable
                      : t.planIncomplete,
                  style: StitchType.small.copyWith(color: c.amber),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
