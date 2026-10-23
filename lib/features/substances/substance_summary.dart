import 'package:flutter/material.dart' show MaterialLocalizations;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../app/device_zone.dart';
import '../../app/display_preferences.dart';
import '../../data/record_store.dart';
import '../../l10n/app_localizations.dart';
import '../../ui/vital_ui.dart';
import '../plans/plan_providers.dart';
import '../plans/plan_requirement_badges.dart';
import '../products/product_widgets.dart' show ProductLabelView;
import '../stock/stock_widgets.dart'
    show
        stockAmountNumber,
        StockCapacityProgress,
        StockForecastLine,
        StockPackFacts;
import 'substance_summary_providers.dart';

/// Reusable live summary for one stored substance.
///
/// The collection and overview mount it below their identity header. It
/// renders stored schedule, labelled strength, stock balance and next
/// expectation facts from bounded live reads. Paused, as-needed, ended,
/// incomplete, mixed and unknown states stay explicit; the store keeps one
/// routine per substance, so plan replacements arrive as new versions. It
/// never derives recurrence: the existing resolver owns expectation truth.
/// Separate containers keep their own units and are never added together,
/// and no dose equivalence is invented.
class SubstanceSummary extends ConsumerWidget {
  const SubstanceSummary({
    super.key,
    required this.item,
    this.detailed = false,
  });

  final SubstanceItem item;
  final bool detailed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final anchor = (personId: item.personId, itemId: item.id);
    final zone = ref.watch(observedDeviceZoneProvider).value?.zoneId;
    final plans = ref.watch(summaryPlansProvider(anchor));
    final stock = ref.watch(summaryStockProvider(anchor));
    final next = ref.watch(
      nextDailyPlansProvider(FeedScope.person(item.personId)),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (plans.hasError || stock.hasError || next.hasError)
          _SummaryFailure(
            onRetry: () {
              ref.invalidate(summaryPlansProvider(anchor));
              ref.invalidate(summaryStockProvider(anchor));
              ref.invalidate(nextDailyPlansProvider);
            },
          ),
        _Schedules(
          plans: plans,
          next: next,
          zone: zone,
          detailed: detailed,
          onZoneRetry: () => ref.invalidate(observedDeviceZoneProvider),
        ),
        _Containers(containers: stock, detailed: detailed),
      ],
    );
  }
}

/// Failure keeps the current content and offers the bounded retry itself.
class _SummaryFailure extends StatelessWidget {
  const _SummaryFailure({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return VitalNotice(
      tone: VitalTone.danger,
      icon: LucideIcons.circleAlert,
      action: Align(
        alignment: AlignmentDirectional.centerStart,
        child: VitalButton.secondary(onPressed: onRetry, child: Text(t.retry)),
      ),
      child: Text(t.designSubstancesSummaryUnavailable),
    );
  }
}

class _Schedules extends ConsumerWidget {
  const _Schedules({
    required this.plans,
    required this.next,
    required this.zone,
    required this.detailed,
    required this.onZoneRetry,
  });

  final AsyncValue<List<SavedDailyPlan>> plans;
  final AsyncValue<DailyPlanNextRows> next;
  final String? zone;
  final bool detailed;
  final VoidCallback onZoneRetry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final savedPlans = plans.hasValue ? plans.requireValue : null;
    if (savedPlans == null) {
      // A mounted failure keeps any previous content visible above.
      if (plans.hasError) return const SizedBox.shrink();
      return Text(t.loadingRecords);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (detailed) _Heading(text: t.designSubstancesSchedulesHeading),
        if (savedPlans.isEmpty)
          Text(t.designSubstancesNoSchedule)
        else ...[
          for (final saved in savedPlans)
            _PlanLine(
              key: ValueKey('summary-${saved.plan.planId}'),
              saved: saved,
              next: next,
              zone: zone,
              detailed: detailed,
              onZoneRetry: onZoneRetry,
            ),
          // The store keeps one routine per substance, so this list stays
          // short; a truncated scope still discloses through the next rows.
          if (savedPlans.length > summaryPlanLimit - 1) Text(t.planIncomplete),
        ],
      ],
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 16),
      child: Semantics(
        header: true,
        child: Text(text, style: VitalType.section),
      ),
    );
  }
}

class _PlanLine extends ConsumerWidget {
  const _PlanLine({
    super.key,
    required this.saved,
    required this.next,
    required this.zone,
    required this.detailed,
    required this.onZoneRetry,
  });

  final SavedDailyPlan saved;
  final AsyncValue<DailyPlanNextRows> next;
  final String? zone;
  final bool detailed;
  final VoidCallback onZoneRetry;

  DailyPlanVersion get plan => saved.plan;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final now = DateTime.now().toUtc();
    final paused = plan.pauses.any((p) => p.contains(now));
    final prn = plan.timing is AsNeeded;
    final today = _planToday(plan, zone);
    final ended =
        plan.endExclusive != null &&
        today != null &&
        today.compareTo(plan.endExclusive!) >= 0;
    final notStarted = today != null && plan.start.compareTo(today) > 0;
    final badges = <Widget>[
      if (paused) VitalBadge(t.pauseState),
      if (prn) VitalBadge(t.planAsNeeded, tone: VitalTone.warning),
      if (notStarted) VitalBadge(t.designSubstancesNotStarted),
      if (ended) VitalBadge(t.designSubstancesEnded),
      if (plan.instructions.isNotEmpty && !detailed)
        VitalBadge(t.featurePlanInstructionsHeading),
      for (final label in planRequirementLabels(t, plan.requirements))
        VitalBadge(label),
    ];
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(_timingText(context, ref, t)),
          Text(t.designSubstancesZone(_zoneName(plan, zone, t))),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              ...badges,
              ..._nextLines(context, ref, t),
              if (detailed && paused)
                Text(t.pauseRecordHelp, style: VitalType.metadata),
            ],
          ),
          // As-needed guidance belongs to the plan; no invented run-out date.
          if (prn) Text(t.planPrnHelp, style: VitalType.metadata),
          if (detailed && plan.instructions.isNotEmpty) ...[
            Text(t.featurePlanInstructionsHeading, style: VitalType.label),
            Text(plan.instructions, style: VitalType.body),
          ],
          if (detailed) _detailLines(context, ref, t),
        ],
      ),
    );
  }

  /// Restates stored timing; the resolver stays the occurrence authority.
  String _timingText(BuildContext context, WidgetRef ref, AppLocalizations t) {
    final value = plan.timing;
    if (value is DailyCount) {
      return t.designSubstancesScheduleCount(
        value.count,
        value.amount.enteredText,
        value.amount.unit,
      );
    }
    if (value is DailySlots) {
      return t.designSubstancesScheduleSlots(
        _slotSummary(context, ref, t, value.slots, 0),
      );
    }
    if (value is DailyWindows) {
      return t.designSubstancesScheduleWindows(
        [
          for (final window in value.windows)
            t.designSubstancesScheduleWindow(
              displayWallTime(context, ref, window.start),
              displayWallTime(context, ref, window.end),
              window.amount.enteredText,
              window.amount.unit,
            ),
        ].join(', '),
      );
    }
    if (value is MixedDailyCount) {
      final untimed = value.count - value.slots.length;
      return t.designSubstancesMixedSchedule(
        _slotSummary(context, ref, t, value.slots, untimed),
        untimed,
        value.amount.enteredText,
        value.amount.unit,
      );
    }
    if (value is ElapsedInterval) {
      return t.designSubstancesIntervalSchedule(
        value.duration.hoursText,
        value.amount.enteredText,
        value.amount.unit,
      );
    }
    return t.planAsNeeded;
  }

  /// Names each stored slot with its exact amount; overflow stays disclosed.
  String _slotSummary(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations t,
    List<DailySlot> slots,
    int untimed,
  ) {
    const shown = 8;
    final entries = [
      for (final slot in slots.take(shown))
        t.designSubstancesScheduleSlot(
          displayWallTime(context, ref, slot.time),
          slot.amount.enteredText,
          slot.amount.unit,
        ),
    ];
    final overhang = slots.length > shown ? slots.length - shown : untimed;
    if (overhang > 0) entries.add(t.designSubstancesMoreSlots(overhang));
    return entries.join(', ');
  }

  /// The plan zone basis; an observation absence is not a plan-zone change.
  String _zoneName(
    DailyPlanVersion value,
    String? observed,
    AppLocalizations t,
  ) {
    final basis = value.zoneBasis;
    return basis is FixedHome ? basis.zoneId : (observed ?? t.planLocal);
  }

  /// Today in the plan's real zone, or null when conversion stays incomplete.
  CivilDate? _planToday(DailyPlanVersion value, String? observed) {
    try {
      return DailyResolver().currentDate(
        value,
        now: DateTime.now().toUtc(),
        observedZone: observed ?? '',
      );
    } catch (_) {
      return null;
    }
  }

  /// The bounded resolver row for this exact plan.
  DailyPlanNextRow? _rowFor(AsyncValue<DailyPlanNextRows> value) {
    if (!value.hasValue) return null;
    for (final row in value.requireValue.rows) {
      if (row.plan.planId == plan.planId &&
          row.plan.personId == plan.personId) {
        return row;
      }
    }
    return null;
  }

  /// The resolver's own next facts with their real partial/issue disclosure.
  List<Widget> _nextLines(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations t,
  ) {
    if (plan.timing is AsNeeded) return const [];
    if (next.hasError) {
      // Without previous rows the top-level failure notice owns the retry;
      // with previous rows they stay visible while the stream recovers.
      if (next.hasValue) return _nextRows(context, ref, t);
      return const [];
    }
    if (!next.hasValue) {
      return [Text(t.loadingRecords, style: VitalType.metadata)];
    }
    return _nextRows(context, ref, t);
  }

  List<Widget> _nextRows(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations t,
  ) {
    final row = _rowFor(next);
    if (row == null) {
      // Past the scope's 100-plan budget no row may exist for this plan.
      return [Text(t.planIncomplete, style: VitalType.metadata)];
    }
    return _resultLines(context, ref, t, row.result);
  }

  List<Widget> _resultLines(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations t,
    DailyNext result,
  ) {
    final lines = <Widget>[];
    void addExpectation(DailyExpectation e) {
      if (e.instant case final instant?) {
        lines.add(
          Text(
            t.designSubstancesNextDose(
              e.amount.enteredText,
              e.amount.unit,
              displayStamp(context, ref, instant, zoneId: e.zoneId),
              e.zoneId,
            ),
            style: VitalType.metadata,
          ),
        );
      } else {
        lines.add(
          Text(
            t.designSubstancesNextUntimed(
              e.amount.enteredText,
              e.amount.unit,
              e.identity.originalDate.toString(),
              e.zoneId,
            ),
            style: VitalType.metadata,
          ),
        );
      }
    }

    if (result.complete) {
      if (result.next case final expectation?) addExpectation(expectation);
      if (result.next == null) {
        lines.add(Text(t.planNoNext, style: VitalType.metadata));
      }
    } else {
      if (result.issue == DailyCalculationIssue.observedZoneUnavailable) {
        // The explanation stays text; Retry is a one-word button beside it.
        // The zone observation itself stays uncertain until a fresh one.
        lines.add(Text(t.planZoneUnavailable, style: VitalType.metadata));
        lines.add(
          VitalButton.secondary(onPressed: onZoneRetry, child: Text(t.retry)),
        );
      } else {
        lines.add(
          Text(
            result.issue == null ? t.planIncomplete : t.planCalculationIssue,
            style: VitalType.metadata,
          ),
        );
      }
      if (result.calendarDate case final known?) {
        lines.add(
          Text(
            t.calendarKnownDate(known.toString()),
            style: VitalType.metadata,
          ),
        );
      }
      if (result.next case final partial?) addExpectation(partial);
    }
    return lines;
  }

  Widget _detailLines(BuildContext context, WidgetRef ref, AppLocalizations t) {
    final children = <Widget>[];
    final endExclusive = plan.endExclusive;
    children.add(
      Text(
        endExclusive == null
            ? t.designSubstancesPlanStart(plan.start.toString())
            : t.designSubstancesPlanBounds(
                plan.start.toString(),
                endExclusive.addDays(-1).toString(),
              ),
        style: VitalType.metadata,
      ),
    );
    final calendar = plan.calendar;
    if (calendar is SelectedWeekdays) {
      final material = Localizations.of<MaterialLocalizations>(
        context,
        MaterialLocalizations,
      );
      if (material != null) {
        final narrow = material.narrowWeekdays;
        children.add(
          Text(
            t.designSubstancesCalendarWeekdays(
              [for (final weekday in calendar.weekdays) narrow[weekday % 7]]
                  .join(', '),
            ),
          ),
        );
      }
    } else if (calendar is EveryNDays) {
      children.add(
        Text(
          t.designSubstancesCalendarDays(
            calendar.interval,
            calendar.anchor.toString(),
          ),
        ),
      );
    } else if (calendar is EveryNWeeks) {
      children.add(
        Text(
          t.designSubstancesCalendarWeeks(
            calendar.interval,
            calendar.anchorWeekStart.toString(),
          ),
        ),
      );
    } else if (calendar is EveryNMonths) {
      final selectorText = calendar.selector is DayOfMonth
          ? t.designSubstancesMonthDay((calendar.selector as DayOfMonth).day)
          : t.designSubstancesMonthWeekday;
      children.add(
        Text(
          t.designSubstancesCalendarMonths(
            calendar.interval,
            selectorText,
            calendar.anchorMonth.toString(),
          ),
        ),
      );
    }
    if (plan.timing case DailySlots(:final slots)) {
      for (final slot in slots) {
        children.add(
          Text(
            t.designSubstancesScheduleSlot(
              displayWallTime(context, ref, slot.time),
              slot.amount.enteredText,
              slot.amount.unit,
            ),
            style: VitalType.metadata,
          ),
        );
      }
    }
    if (next.value case final rows?) {
      for (final row in rows.rows) {
        if (row.plan.planId != plan.planId ||
            row.plan.personId != plan.personId) {
          continue;
        }
        for (final review in row.result.needsReview) {
          if (review.originalTime case final original?) {
            children.add(
              Text(
                t.designSubstancesReviewClock(
                  review.identity.originalDate.toString(),
                  displayWallTime(context, ref, original),
                  review.zoneId,
                ),
                style: VitalType.metadata,
              ),
            );
          }
        }
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }
}

/// A tracked container with its own labelled strength, unit and balance.
///
/// Reused by list summaries and the substance overview without combining
/// incompatible containers or duplicating their surrounding sections.
class _Containers extends ConsumerWidget {
  const _Containers({required this.containers, required this.detailed});

  final AsyncValue<List<StoredStockContainer>> containers;
  final bool detailed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final all = containers.hasValue ? containers.requireValue : null;
    if (all == null) {
      // A mounted failure keeps any previous content visible above.
      if (containers.hasError) return const SizedBox.shrink();
      return Text(t.loadingRecords);
    }
    // Compact keeps a short disclosed page; detailed grows to the streamed
    // budget so the same container never disappears without disclosure. Both
    // modes name every container in its own unit, never a sum.
    final shown = detailed ? summaryStockLimit - 1 : summaryStockLines;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (detailed) _Heading(text: t.stock),
        if (all.isEmpty)
          Text(t.designSubstancesNoStock)
        else ...[
          for (final container in all.take(shown))
            SubstanceContainerSummary(
              key: ValueKey('summary-stock-${container.id}'),
              container: container,
              detailed: detailed,
            ),
          if (!detailed && all.length > shown)
            Text(t.designSubstancesMoreStock(all.length - shown)),
          // The read is bounded at the store budget; the existing Stock
          // destination is the recovery seam when that budget is reached.
          if (all.length > summaryStockLimit - 1) Text(t.stockMore),
        ],
      ],
    );
  }
}

class SubstanceContainerSummary extends StatelessWidget {
  const SubstanceContainerSummary({
    super.key,
    required this.container,
    required this.detailed,
  });

  final StoredStockContainer container;
  final bool detailed;

  /// Short factual balance in the container's own unit, or its known state.
  String shortBalance(AppLocalizations t) {
    final balance = container.balance;
    if (balance.limitReached) return t.stockLimit;
    if (balance.value case final value?) {
      return t.stockQuantity(stockAmountNumber(t, value), container.unit);
    }
    return t.stockUnknownValue;
  }

  List<Widget> _badges(BuildContext context) {
    final t = AppLocalizations.of(context);
    final state = switch (container.notice) {
      StockNoticeState.refill => VitalBadge(
        t.stockRefillDue,
        tone: VitalTone.warning,
      ),
      StockNoticeState.low => VitalBadge(t.stockLow, tone: VitalTone.warning),
      StockNoticeState.unknown => VitalBadge(t.stockUnknownValue),
      _ => null,
    };
    return [
      if (container.balance.isDeficit)
        VitalBadge(t.designSubstancesDeficit, tone: VitalTone.danger),
      ?state,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (detailed)
            VitalMetric(
              label: container.label,
              value:
                  container.balance.value == null ||
                      container.balance.limitReached
                  ? null
                  : shortBalance(t),
              detail: t.stockStrengthValue(container.strength.label),
            )
          else ...[
            Text(
              t.designSubstancesContainerEntry(
                container.label,
                shortBalance(t),
              ),
            ),
            Text(t.stockStrengthValue(container.strength.label)),
          ],
          Wrap(spacing: 12, runSpacing: 8, children: _badges(context)),
          if (container.capacity != null || detailed)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: StockCapacityProgress(
                container: container,
                detailed: detailed,
              ),
            ),
          StockPackFacts(container: container, detailed: detailed),
          if (detailed && !container.balance.limitReached)
            StockForecastLine(container: container, detailed: true),
          if (detailed && container.productLabel != null)
            ProductLabelView(label: container.productLabel!),
          if (detailed && container.balance.limitReached) Text(t.stockLimit),
          if (detailed && container.balance.isDeficit) Text(t.stockDeficit),
        ],
      ),
    );
  }
}
