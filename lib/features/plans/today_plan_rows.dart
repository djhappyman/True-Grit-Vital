import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../app/device_zone.dart';
import '../../app/storage.dart';
import '../../data/record_store.dart';
import '../../l10n/app_localizations.dart';
import '../../ui/vital_ui.dart';
import '../profiles/profile_pages.dart';
import '../recording/record_pages.dart';
import '../reminders/reminder_pages.dart';
import 'interval_editor.dart';
import 'plan_form.dart';
import 'plan_providers.dart';

/// Owner and item context for one plan, shown with its feed entry points.
class PlanItemContext extends ConsumerWidget {
  const PlanItemContext({super.key, required this.plan});
  final DailyPlanVersion plan;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context),
        item = ref.watch(itemLookupProvider(plan.itemId)).value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(t.profileOwner(ownerLabel(ref, t, plan.personId))),
        if (item != null) Text(item.name),
      ],
    );
  }
}

/// Compact schedule rows for the saved timed plans.
///
/// Each plan keeps its existing preview, review, reminder, pause, phase and
/// schedule entry points on the current routes. Elapsed-interval previews
/// still require a usable zone: an unavailable observed zone shows the plan
/// zone message instead of a guessed instant, and incomplete plan expansions
/// keep their visible limit note.
class TodayPlanRows extends ConsumerWidget {
  const TodayPlanRows({super.key, required this.scope, required this.next});
  final FeedScope scope;
  final AsyncValue<DailyPlanNextRows> next;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    return next.when(
      data: (plans) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final summary in plans.rows.where(
            (p) => p.result.next != null || p.plan.timing is! AsNeeded,
          ))
            _TodayPlanRow(
              key: ValueKey(summary.plan.planId),
              summary: summary,
              scope: scope,
            ),
          if (!plans.complete) Text(t.planIncomplete),
        ],
      ),
      error: (_, _) => LoadFailure(
        onRetry: () => ref.invalidate(nextDailyPlansProvider(scope)),
      ),
      loading: () => const SizedBox.shrink(),
    );
  }
}

class _TodayPlanRow extends ConsumerWidget {
  const _TodayPlanRow({super.key, required this.summary, required this.scope});
  final DailyPlanNextRow summary;
  final FeedScope scope;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context),
        zone = ref.watch(observedDeviceZoneProvider),
        plan = summary.plan;
    final now = DateTime.now().toUtc();
    final paused = plan.pauses.any((pause) => pause.contains(now));
    return VitalSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PlanItemContext(plan: plan),
          if (plan.instructions.isNotEmpty) ...[
            const SizedBox(height: VitalLayout.gap),
            Text(t.featurePlanInstructionsHeading, style: VitalType.label),
            Text(plan.instructions),
          ],
          if (paused) ...[
            const SizedBox(height: VitalLayout.gap),
            Text(t.pauseState),
            Text(t.pauseRecordHelp),
            VitalButton.secondary(
              onPressed: () => context.push('/record/${plan.itemId}'),
              child: Text(t.record),
            ),
          ],
          if (plan.timing is ElapsedInterval)
            (zone.value?.zoneId == null && plan.zoneBasis is! FixedHome
                ? Text(t.planZoneUnavailable)
                : IntervalPlanPreview(
                    plan: plan,
                    observedZone: plan.zoneBasis is FixedHome
                        ? (plan.zoneBasis as FixedHome).zoneId
                        : zone.value!.zoneId!,
                  ))
          else if (!(plan.timing is DailyCount && paused))
            Text(
              !summary.result.complete
                  ? t.planNextReview
                  : summary.result.next == null
                  ? t.planNoNext
                  : t.planNext(
                      summary.result.next!.identity.originalDate.toString(),
                    ),
            ),
          if (!summary.result.complete && summary.result.calendarDate != null)
            Text(t.calendarKnownDate(summary.result.calendarDate.toString())),
          for (final review in summary.result.needsReview)
            Text(expectationLabel(context, ref, t, review)),
          if (ref
                  .watch(scopePlansProvider(scope))
                  .value
                  ?.where((s) => s.plan.planId == plan.planId)
                  .firstOrNull
              case final SavedDailyPlan saved)
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                PlanReminderControl(saved: saved),
                VitalButton.secondary(
                  onPressed: () => context.push(
                    '/pause/${saved.plan.itemId}?plan=${saved.plan.planId}',
                  ),
                  child: Text(
                    saved.plan.pauses.any((p) => p.resume == null)
                        ? t.resume
                        : t.pauseAction,
                  ),
                ),
              ],
            ),
          Text(t.phaseSavedHelp),
          const SizedBox(height: VitalLayout.gap),
          Wrap(
            spacing: VitalLayout.gap,
            runSpacing: VitalLayout.gap,
            children: [
              VitalButton.secondary(
                onPressed: () =>
                    context.push('/phases/${plan.itemId}?plan=${plan.planId}'),
                child: Text(t.phaseHeading),
              ),
              VitalButton.secondary(
                onPressed: () => context.push(
                  '/schedule/${plan.itemId}?plan=${plan.planId}',
                ),
                child: Text(t.edit),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
