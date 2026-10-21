import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../data/record_store.dart';
import '../../l10n/app_localizations.dart';
import '../../ui/vital_ui.dart';
import '../recording/record_pages.dart';
import 'plan_providers.dart';
import 'today_plan_rows.dart';

/// Compact as-needed entry points.
///
/// As-needed plans have no expected times or doses, so no countdown, progress
/// or history inference is shown here: each plan offers its existing pause,
/// phase review and record actions on the current routes. The bounded plan
/// limit stays visible when it could hide a plan, and a paused plan stays
/// labelled with the plain state text between actions.
class TodayPrnPanel extends ConsumerWidget {
  const TodayPrnPanel({super.key, required this.plans, required this.scope});
  final AsyncValue<List<SavedDailyPlan>> plans;
  final FeedScope scope;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    return plans.when(
      data: (saved) {
        final prn = [
          for (final entry in saved.take(100))
            if (entry.plan.timing is AsNeeded) entry,
        ];
        if (prn.isEmpty) return const SizedBox.shrink();
        return VitalSection(
          title: Text(t.planAsNeeded),
          children: [
            Text(t.planPrnHelp),
            for (final entry in prn) ...[
              const SizedBox(height: VitalLayout.gap),
              VitalSurface(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    PlanItemContext(plan: entry.plan),
                    if (entry.plan.pauses.any(
                      (pause) => pause.contains(DateTime.now().toUtc()),
                    ))
                      Text(t.pauseState),
                    const SizedBox(height: VitalLayout.gap),
                    Wrap(
                      spacing: VitalLayout.gap,
                      runSpacing: VitalLayout.gap,
                      children: [
                        VitalButton.secondary(
                          onPressed: () => context.push(
                            '/pause/${entry.plan.itemId}?plan=${entry.plan.planId}',
                          ),
                          child: Text(
                            entry.plan.pauses.any(
                                  (pause) =>
                                      pause.contains(DateTime.now().toUtc()),
                                )
                                ? t.resume
                                : t.pauseAction,
                          ),
                        ),
                        VitalButton.secondary(
                          onPressed: () => context.push(
                            '/phases/${entry.plan.itemId}?plan=${entry.plan.planId}',
                          ),
                          child: Text(t.phaseHeading),
                        ),
                        VitalButton.secondary(
                          onPressed: () =>
                              context.push('/record/${entry.plan.itemId}'),
                          child: Text(t.record),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
            if (saved.length > 100) Text(t.planIncomplete),
          ],
        );
      },
      error: (_, _) =>
          LoadFailure(onRetry: () => ref.invalidate(scopePlansProvider(scope))),
      loading: () => const SizedBox.shrink(),
    );
  }
}
