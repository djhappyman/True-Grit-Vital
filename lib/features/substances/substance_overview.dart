import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../app/device_zone.dart';
import '../../app/display_preferences.dart';
import '../../app/storage.dart';
import '../../data/record_store.dart';
import '../../l10n/app_localizations.dart';
import '../../ui/stitch_ui.dart';
import '../../ui/vital_ui.dart';
import '../catalogue/catalogue_picker.dart' show CatalogueSource;
import '../events/event_pages.dart' show eventDateLabel, eventPageProvider;
import '../plans/calendar_editor.dart' show weekdayLabel;
import '../plans/phase_editor.dart' show phaseTimingSummary;
import '../plans/plan_form.dart' show expectationLabel;
import '../plans/plan_providers.dart' show nextDailyPlansProvider;
import '../products/product_pages.dart' show ProductLabelPanel;
import '../profiles/profile_pages.dart' show ownerLabel;
import '../recording/record_pages.dart' show LoadFailure, pagedRecordsProvider;
import '../stock/stock_providers.dart' show stockContainersProvider;
import '../stock/stock_widgets.dart' show stockRecordAmountNumber;
import '../supporting/supporting_pages.dart' show supportingLocation;
import 'substance_detail_providers.dart';
import 'substance_summary.dart' show SubstanceContainerSummary;

/// This overview's own schedule stream. A scoped watch on the store keeps the
/// schedule section live while the page is mounted: paused, resumed, revised
/// and newly saved plans re-render without touching the global feed provider.
final overviewPlansProvider = StreamProvider.autoDispose
    .family<List<SavedDailyPlan>, ({String itemId, FeedScope scope})>(
      retry: (_, _) => null,
      (ref, query) async* {
        yield* (await ref.watch(recordStoreProvider.future)).watchDailyPlans(
          itemId: query.itemId,
          scope: query.scope,
          limit: 101,
        );
      },
    );

/// One reachable overview of a saved substance.
///
/// The page reuses the existing query providers and action routes. The
/// historical `/item/:id` route stays the full history surface; this overview
/// adds bounded schedule, stock and recent-record summaries with their own
/// loading, empty, partial and failure states. A missing or deleted substance
/// resolves to the shared unavailable notice instead of a stale action list.
class SubstanceOverviewPage extends ConsumerWidget {
  const SubstanceOverviewPage({super.key, required this.itemId});
  final String itemId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    return ref
        .watch(itemLookupProvider(itemId))
        .when(
          data: (item) {
            if (item == null) {
              return _StatePage(
                children: [
                  VitalNotice(
                    tone: VitalTone.danger,
                    icon: LucideIcons.circleAlert,
                    child: Text(t.noItem),
                  ),
                ],
              );
            }
            return _LoadedOverview(item: item);
          },
          error: (_, _) => _StatePage(
            children: [
              LoadFailure(
                onRetry: () => ref.invalidate(itemLookupProvider(itemId)),
              ),
            ],
          ),
          loading: () => _StatePage(children: [Text(t.loadingRecords)]),
        );
  }
}

/// Keeps the canonical secondary page chrome for unavailable and loading
/// states without introducing a second detail shell.
class _StatePage extends StatelessWidget {
  const _StatePage({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => VitalPage(
    children: [const _BackRow(), const SizedBox(height: 16), ...children],
  );
}

class _BackRow extends StatelessWidget {
  const _BackRow();

  @override
  Widget build(BuildContext context) =>
      Align(alignment: AlignmentDirectional.centerStart, child: _BackButton());
}

class _BackButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return VitalButton.secondary(
      leading: const Icon(LucideIcons.arrowLeft),
      onPressed: () =>
          context.canPop() ? context.pop() : context.go('/substances'),
      child: Text(t.back),
    );
  }
}

class _LoadedOverview extends ConsumerStatefulWidget {
  const _LoadedOverview({required this.item});

  final SubstanceItem item;

  @override
  ConsumerState<_LoadedOverview> createState() => _LoadedOverviewState();
}

class _LoadedOverviewState extends ConsumerState<_LoadedOverview> {
  int _section = 0;
  @override
  Widget build(BuildContext context) {
    final item = widget.item, t = AppLocalizations.of(context);
    final labels = [
      t.screenOverviewSectionOverview,
      t.schedule,
      t.stock,
      t.history,
    ];
    return SafeArea(
      child: Scaffold(
        headers: [
          VitalPageBody(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _BackRow(),
                const SizedBox(height: 12),
                if (_section != 0) Text(item.name, style: VitalType.record),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: VitalButton(
                        onPressed: () => context.push('/record/${item.id}'),
                        child: Text(t.record),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _HeroSecondaryActions(item: item),
                  ],
                ),
                const SizedBox(height: 12),
                VitalSegments<int>(
                  values: const [0, 1, 2, 3],
                  selected: _section,
                  onChanged: (index) => setState(() => _section = index),
                  label: (index) => labels[index],
                ),
              ],
            ),
          ),
        ],
        child: VitalPager(
          index: _section,
          itemCount: 4,
          onChanged: (index) => setState(() => _section = index),
          itemBuilder: (_, index) => VitalScrollBody(
            children: switch (index) {
              0 => [
                _SubstanceHero(item: item),
                const SizedBox(height: 16),
                _OverviewStockAlert(item: item),
                const SizedBox(height: 16),
                _OverviewSetup(item: item),
                const SizedBox(height: 16),
                _OverviewDetails(item: item),
                const SizedBox(height: 16),
                _OverviewContext(item: item),
              ],
              1 => [_OverviewSchedule(item: item)],
              2 => [
                _OverviewStockAlert(item: item),
                const SizedBox(height: 16),
                _OverviewStock(item: item),
              ],
              _ => [_OverviewHistory(item: item)],
            },
          ),
        ),
      ),
    );
  }
}

/// Identity and the real commands that start from this substance. No inferred
/// active state, identity editor or refill order is shown.
class _SubstanceHero extends StatelessWidget {
  const _SubstanceHero({required this.item});

  final SubstanceItem item;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final muted = Theme.of(context).colorScheme.mutedForeground;
    return StitchSurface(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              StitchIcon(LucideIcons.pill, size: 56),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [VitalBadge(item.type)],
                    ),
                    const SizedBox(height: 8),
                    Semantics(
                      header: true,
                      child: Text(item.name, style: VitalType.detailTitle),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      t.screenOverviewFormUnit(item.form, item.unit),
                      style: VitalType.body.copyWith(color: muted),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Two compact destinations where they fit; a deliberate stack when the width
/// or text scale would otherwise squeeze the labels.
class _HeroSecondaryActions extends StatelessWidget {
  const _HeroSecondaryActions({required this.item});

  final SubstanceItem item;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return VitalOverflow(
      label: t.more,
      actions: [
        VitalMenuAction(
          label: t.combinedAction,
          icon: LucideIcons.packagePlus,
          onPressed: () =>
              context.push('/combined/${item.personId}?item=${item.id}'),
        ),
        VitalMenuAction(
          label: t.stock,
          icon: LucideIcons.boxes,
          onPressed: () =>
              context.push('/stock/${item.personId}?item=${item.id}'),
        ),
      ],
    );
  }
}

/// A real low/refill/deficit container notice. It names the container and its
/// exact balance; no percentage, run-out estimate or on-time judgement.
class _OverviewStockAlert extends ConsumerWidget {
  const _OverviewStockAlert({required this.item});

  final SubstanceItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final query = (personId: item.personId, itemId: item.id, offset: 0);
    final containers = ref.watch(stockContainersProvider(query));
    final container = containers.value
        ?.where(
          (candidate) =>
              candidate.isLow ||
              candidate.needsRefill ||
              candidate.balance.isDeficit,
        )
        .firstOrNull;
    if (container == null) return const SizedBox.shrink();
    final deficit = container.balance.isDeficit;
    final heading = deficit
        ? t.stockDeficit
        : container.isLow
        ? t.stockLow
        : t.stockRefillDue;
    final balance = SubstanceContainerSummary(
      container: container,
      detailed: true,
    ).shortBalance(t);
    return VitalNotice(
      tone: deficit ? VitalTone.danger : VitalTone.warning,
      icon: LucideIcons.triangleAlert,
      action: Align(
        alignment: AlignmentDirectional.centerStart,
        child: Semantics(
          label: t.designOverviewStockReview(item.name),
          child: VitalButton.secondary(
            key: const ValueKey('overview-stock-alert-review'),
            onPressed: () =>
                context.push('/stock/${item.personId}?item=${item.id}'),
            child: Text(t.review),
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(heading, style: VitalType.record),
          const SizedBox(height: 4),
          Text(t.designSubstancesContainerEntry(container.label, balance)),
        ],
      ),
    );
  }
}

String _calendarLine(AppLocalizations t, CalendarPattern pattern) =>
    switch (pattern) {
      EveryDay() => t.calendarDaily,
      SelectedWeekdays(:final weekdays) => t.designOverviewWeekdays(
        weekdays.map((day) => weekdayLabel(t, day)).join(', '),
      ),
      EveryNDays(:final interval) => t.designOverviewEveryDays(interval),
      EveryNWeeks(:final interval) => t.designOverviewEveryWeeks(interval),
      EveryNMonths(:final interval) => t.designOverviewEveryMonths(interval),
      UnsupportedCalendarPattern() => t.calendarUnsupported,
    };

/// The one saved plan version per substance, described with the existing
/// schedule vocabulary. Pauses are expectations too; a paused plan shows its
/// state instead of pretending there is no next planned date of its own.
class _OverviewSchedule extends ConsumerWidget {
  const _OverviewSchedule({required this.item});
  final SubstanceItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final query = (itemId: item.id, scope: FeedScope.person(item.personId));
    final add = VitalButton.secondary(
      onPressed: () => context.push('/schedule/${item.id}'),
      child: Text(t.add),
    );
    return ref
        .watch(overviewPlansProvider(query))
        .when(
          data: (saved) => VitalPanel(
            title: t.schedule,
            icon: LucideIcons.alarmClock,
            action: add,
            children: [
              if (saved.isEmpty)
                _OverviewEmpty(
                  icon: LucideIcons.calendarClock,
                  title: t.designOverviewNoPlan,
                  description: t.designOverviewNoPlanHelp,
                )
              else ...[
                for (final plan in saved.take(50))
                  VitalSurface(
                    key: ValueKey(
                      'plan-${plan.plan.planId}-${plan.plan.versionId}',
                    ),
                    role: VitalSurfaceRole.inset,
                    child: _PlanRows(
                      saved: plan,
                      item: item,
                      // Per-plan edit targets the displayed plan's own version,
                      // not just the first saved plan for this substance.
                      onEdit: () => context.push(
                        '/schedule/${item.id}?plan=${plan.plan.planId}',
                      ),
                    ),
                  ),
                if (saved.length > 50) Text(t.designOverviewPlansBound),
              ],
            ],
          ),
          error: (_, _) => VitalPanel(
            title: t.schedule,
            icon: LucideIcons.alarmClock,
            action: add,
            children: [
              LoadFailure(
                onRetry: () => ref.invalidate(overviewPlansProvider(query)),
              ),
            ],
          ),
          loading: () => VitalPanel(
            title: t.schedule,
            icon: LucideIcons.alarmClock,
            action: add,
            children: [Text(t.loadingRecords)],
          ),
        );
  }
}

class _PlanRows extends ConsumerWidget {
  const _PlanRows({
    required this.saved,
    required this.item,
    required this.onEdit,
  });
  final SavedDailyPlan saved;
  final SubstanceItem item;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final plan = saved.plan;
    final paused = plan.pauses.any(
      (pause) => pause.contains(DateTime.now().toUtc()),
    );
    // A locally following plan shows the actually observed device zone. When
    // no zone has been observed yet, saying so beats implying a UTC plan; an
    // explicitly stored home zone stays what it is.
    final observedZone = ref.watch(observedDeviceZoneProvider).value?.zoneId;
    final shownZone = switch (plan.zoneBasis) {
      FixedHome home => home.zoneId,
      FollowingLocal() => observedZone,
    };
    final facts = <Widget>[
      Text(t.designOverviewStart(plan.start.toString())),
      if (plan.endExclusive != null)
        Text(t.planEnds(plan.endExclusive!.addDays(-1).toString())),
      Text(t.planObserved(shownZone ?? t.planZoneUnknown)),
      Text(_calendarLine(t, plan.calendar)),
      if (plan.onOff case final blocks?) ...[
        Text(
          t.pauseBlockSummary(
            blocks.onDays,
            blocks.offDays,
            blocks.anchor.toString(),
          ),
        ),
        Text(t.pauseIntersection),
      ],
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (plan.timing is AsNeeded) VitalBadge(t.planAsNeeded),
            if (paused) VitalBadge(t.pauseState),
          ],
        ),
        if (plan.timing is AsNeeded || paused) const SizedBox(height: 12),
        if (plan.timing case DailyCount(:final count, :final amount))
          Text(
            t.designSubstancesScheduleCount(
              count,
              amount.enteredText,
              amount.unit,
            ),
            style: VitalType.record,
          )
        else
          DefaultTextStyle.merge(
            style: VitalType.body,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: phaseTimingSummary(context, ref, t, plan),
            ),
          ),
        const SizedBox(height: 12),
        _PlanNext(item: item, planId: plan.planId, paused: paused),
        const SizedBox(height: 12),
        DefaultTextStyle.merge(
          style: VitalType.metadata.copyWith(
            color: Theme.of(context).colorScheme.mutedForeground,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: facts,
          ),
        ),
        if (plan.instructions.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(t.featurePlanInstructionsHeading, style: VitalType.label),
          Text(plan.instructions, style: VitalType.body),
        ],
        const SizedBox(height: 12),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: VitalButton.secondary(
            key: ValueKey('overview-plan-edit-${plan.planId}'),
            onPressed: onEdit,
            child: Text(t.edit),
          ),
        ),
      ],
    );
  }
}

/// Bounded live next-dose context from the shared next-plan provider. A
/// calculation limit or timezone issue reports the machine's actual wording;
/// nothing here invents dates or doses. A plan outside this provider's bounded
/// row set is named as such, never read as having no next dose, and the
/// working schedule editor stays reachable through the per-plan edit action.
class _PlanNext extends ConsumerWidget {
  const _PlanNext({
    required this.item,
    required this.planId,
    required this.paused,
  });
  final SubstanceItem item;
  final String planId;
  final bool paused;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final rows = ref.watch(
      nextDailyPlansProvider(FeedScope.person(item.personId)),
    );
    return rows.when(
      data: (page) {
        final row = page.rows
            .where((row) => row.plan.planId == planId)
            .firstOrNull;
        final lines = <Widget>[
          if (row case final row?) ...[
            if (!row.result.complete)
              Text(
                row.result.issue == null
                    ? t.planIncomplete
                    : t.planCalculationIssue,
              ),
            if (row.result.next case final next?)
              Text(expectationLabel(context, ref, t, next))
            else if (!paused && row.result.complete)
              Text(t.planNoNext),
            for (final review in row.result.needsReview.take(3))
              Text(expectationLabel(context, ref, t, review)),
          ] else
            Text(t.designOverviewNextMissing),
        ];
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ExcludeSemantics(
              child: Icon(
                LucideIcons.clock3,
                size: 18,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: DefaultTextStyle.merge(
                style: VitalType.body,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: lines,
                ),
              ),
            ),
          ],
        );
      },
      error: (_, _) => LoadFailure(
        onRetry: () => ref.invalidate(
          nextDailyPlansProvider(FeedScope.person(item.personId)),
        ),
      ),
      loading: () => const SizedBox.shrink(),
    );
  }
}

/// Container balances for this substance only. The stock screen keeps every
/// restock, reconcile and notice control; balances here stay read-only and
/// keep their exact unit.
class _OverviewStock extends ConsumerWidget {
  const _OverviewStock({required this.item});
  final SubstanceItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final query = (personId: item.personId, itemId: item.id, offset: 0);
    Widget add() => VitalButton.secondary(
      expand: true,
      onPressed: () =>
          context.push('/stock/${item.personId}/create?item=${item.id}'),
      child: Text(t.add),
    );
    return ref
        .watch(stockContainersProvider(query))
        .when(
          data: (containers) => VitalPanel(
            title: t.stock,
            icon: LucideIcons.boxes,
            action: containers.isEmpty
                ? null
                : Semantics(
                    key: const ValueKey('overview-stock-review'),
                    label: t.designOverviewStockReview(item.name),
                    child: VitalButton.secondary(
                      onPressed: () => context.push(
                        '/stock/${item.personId}?item=${item.id}',
                      ),
                      child: Text(t.review),
                    ),
                  ),
            children: [
              if (containers.isEmpty)
                _OverviewEmpty(
                  icon: LucideIcons.box,
                  title: t.designOverviewStockEmpty,
                  description: t.designOverviewStockHelp,
                  action: add(),
                )
              else ...[
                for (final container in containers.take(50))
                  VitalSurface(
                    key: ValueKey('container-${container.id}'),
                    role: VitalSurfaceRole.inset,
                    child: SubstanceContainerSummary(
                      container: container,
                      detailed: true,
                    ),
                  ),
                if (containers.length > 50) Text(t.stockMore),
              ],
            ],
          ),
          error: (_, _) => VitalPanel(
            title: t.stock,
            icon: LucideIcons.boxes,
            children: [
              LoadFailure(
                onRetry: () => ref.invalidate(stockContainersProvider(query)),
              ),
            ],
          ),
          loading: () => VitalPanel(
            title: t.stock,
            icon: LucideIcons.boxes,
            children: [Text(t.loadingRecords)],
          ),
        );
  }
}

/// A bounded recent-record summary. Editing, Undo and the complete list stay
/// in their existing routes: the full page button in the section header and
/// each record's own history entry.
class _OverviewHistory extends ConsumerWidget {
  const _OverviewHistory({required this.item});
  final SubstanceItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final query = (
      itemId: item.id,
      actualFrom: null,
      actualBefore: null,
      limit: 21,
      offset: 0,
      scope: FeedScope.person(item.personId),
    );
    return ref
        .watch(pagedRecordsProvider(query))
        .when(
          data: (rows) => VitalPanel(
            title: t.history,
            icon: LucideIcons.history,
            action: rows.isEmpty
                ? null
                : Semantics(
                    key: const ValueKey('overview-history-review'),
                    label: t.designOverviewHistoryReview(item.name),
                    child: VitalButton.secondary(
                      onPressed: () => context.push('/item/${item.id}'),
                      child: Text(t.review),
                    ),
                  ),
            children: [
              if (rows.isEmpty)
                _OverviewEmpty(
                  icon: LucideIcons.history,
                  title: t.noRecords,
                  description: t.historyReady,
                )
              else ...[
                for (final record in rows.take(20))
                  _RecentRecordRow(
                    key: ValueKey('recent-${record.id}'),
                    record: record,
                  ),
                if (rows.length > 20) Text(t.designOverviewHistoryHint),
              ],
            ],
          ),
          error: (_, _) => VitalPanel(
            title: t.history,
            icon: LucideIcons.history,
            children: [
              LoadFailure(
                onRetry: () => ref.invalidate(pagedRecordsProvider(query)),
              ),
            ],
          ),
          loading: () => VitalPanel(
            title: t.history,
            icon: LucideIcons.history,
            children: [Text(t.loadingRecords)],
          ),
        );
  }
}

class _RecentRecordRow extends ConsumerWidget {
  const _RecentRecordRow({super.key, required this.record});

  final UseRecord record;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    return VitalSurface(
      role: VitalSurfaceRole.inset,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          StitchIcon(
            record.isVoided ? LucideIcons.circleAlert : LucideIcons.check,
            size: 36,
            selected: !record.isVoided,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t.stockQuantity(
                    stockRecordAmountNumber(t, record),
                    record.actualUnit,
                  ),
                  style: VitalType.record,
                ),
                Text(
                  t.actualStamp(displayStamp(context, ref, record.actualAt)),
                  style: VitalType.metadata.copyWith(
                    color: Theme.of(context).colorScheme.mutedForeground,
                  ),
                ),
                if (record.isVoided)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: VitalBadge(t.voided, tone: VitalTone.warning),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A resumable invitation to the optional steps after identity creation. The
/// marker is local progress only; completed steps are read from the real plan,
/// stock and detail records.
class _OverviewSetup extends ConsumerWidget {
  const _OverviewSetup({required this.item});
  final SubstanceItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final setup = ref.watch(itemSetupProvider(item.id)).value;
    if (setup == null || setup.isComplete) return const SizedBox.shrink();
    return VitalPanel(
      title: t.featureSetupTitle,
      icon: LucideIcons.listChecks,
      children: [
        Text(
          t.featureSetupContinueHelp,
          style: VitalType.metadata.copyWith(
            color: Theme.of(context).colorScheme.mutedForeground,
          ),
        ),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: VitalButton.secondary(
            onPressed: () => context.push('/substance/${item.id}/setup'),
            child: Text(t.featureSetupContinue),
          ),
        ),
      ],
    );
  }
}

/// Concise, full-text details. Instructions and private notes are shown exactly
/// as authored; the app adds no dosing advice or interpretation.
class _OverviewDetails extends ConsumerWidget {
  const _OverviewDetails({required this.item});
  final SubstanceItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final muted = Theme.of(context).colorScheme.mutedForeground;
    final detail = ref.watch(itemDetailProvider(item.id)).value;
    final hasInstructions = detail?.instructions.isNotEmpty == true;
    final hasNotes = detail?.notes.isNotEmpty == true;
    return VitalPanel(
      title: t.featureSetupDetails,
      icon: LucideIcons.notebookPen,
      action: detail == null
          ? null
          : VitalButton.secondary(
              onPressed: () => context.push('/substance/${item.id}/details'),
              child: Text(t.edit),
            ),
      children: [
        if (!hasInstructions && !hasNotes)
          _OverviewEmpty(
            icon: LucideIcons.notebookPen,
            title: t.featureSetupNoDetails,
            description: t.featureSetupNoDetailsHelp,
            action: VitalButton.secondary(
              onPressed: () => context.push('/substance/${item.id}/details'),
              child: Text(t.add),
            ),
          )
        else ...[
          if (hasInstructions) ...[
            Text(
              t.featureSetupInstructions,
              style: VitalType.label.copyWith(color: muted),
            ),
            Text(detail!.instructions, style: VitalType.body),
          ],
          if (hasInstructions && hasNotes) const SizedBox(height: 12),
          if (hasNotes) ...[
            Text(
              t.featureSetupNotes,
              style: VitalType.label.copyWith(color: muted),
            ),
            Text(detail!.notes, style: VitalType.body),
            const SizedBox(height: 6),
            Text(
              t.featureSetupNotesHelp,
              style: VitalType.metadata.copyWith(color: muted),
            ),
          ],
        ],
      ],
    );
  }
}

/// Linked context, product label, source provenance and events. Clinical notes
/// are not stored by this app and are not fabricated here.
class _OverviewContext extends StatelessWidget {
  const _OverviewContext({required this.item});

  final SubstanceItem item;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return VitalPanel(
      title: t.designOverviewContext,
      icon: LucideIcons.tags,
      children: [
        VitalActions(
          children: [
            VitalButton.secondary(
              multiline: true,
              onPressed: () => context.push(
                supportingLocation(
                  item.personId,
                  item: item.id,
                  back: '/substance/${item.id}',
                ),
              ),
              child: Text(t.supportingTitle),
            ),
            VitalButton.secondary(
              onPressed: () =>
                  context.push('/files/${item.personId}/item/${item.id}'),
              child: Text(t.attachments),
            ),
            VitalButton.secondary(
              multiline: true,
              onPressed: () => context.push('/use/${item.personId}/${item.id}'),
              child: Text(t.screenOverviewPeriods),
            ),
          ],
        ),
        if (item.catalogueSnapshot != null) ...[
          const SizedBox(height: 4),
          Text(
            t.catalogue,
            style: VitalType.label.copyWith(
              color: Theme.of(context).colorScheme.mutedForeground,
            ),
          ),
          VitalSurface(
            role: VitalSurfaceRole.inset,
            padding: const EdgeInsets.all(12),
            child: CatalogueSource(snapshot: item.catalogueSnapshot!),
          ),
        ],
        ProductLabelPanel(item: item),
        _OverviewEvents(item: item),
      ],
    );
  }
}

/// Linked cycle and prescription events that include this substance, from the
/// shared bounded event page. Truncation is reported whichever side cuts the
/// results: more matched events than can be shown, or a full reachable page
/// that may hold further matches. The Events screen stays reachable here even
/// though this secondary page has no navigation dock.
class _OverviewEvents extends ConsumerWidget {
  const _OverviewEvents({required this.item});
  final SubstanceItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final query = (personId: item.personId, offset: 0);
    return ref
        .watch(eventPageProvider(query))
        .when(
          data: (page) {
            final matches = [
              for (final event in page)
                if (event.memberships.any((member) => member.itemId == item.id))
                  event,
            ];
            final full = page.length > 50;
            final truncated = matches.length > 20 || full;
            if (matches.isEmpty && !truncated) return const SizedBox.shrink();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 16),
                for (final event in matches.take(20))
                  Padding(
                    key: ValueKey('event-${event.id}'),
                    padding: const EdgeInsets.only(bottom: 12),
                    child: VitalSurface(
                      role: VitalSurfaceRole.inset,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(event.name, style: VitalType.record),
                          Text(
                            event.eventType == 'cycle'
                                ? t.eventCycle
                                : event.eventType == 'prescription'
                                ? t.eventPrescription
                                : event.eventType,
                          ),
                          Text(
                            t.eventPlannedLabel(
                              eventDateLabel(t, event.plannedStart),
                              eventDateLabel(t, event.plannedEnd, open: true),
                            ),
                          ),
                          if (event.completed) Text(t.eventCompleted),
                          Align(
                            alignment: AlignmentDirectional.centerStart,
                            child: Semantics(
                              label: t.eventReviewFor(
                                event.name,
                                ownerLabel(ref, t, event.personId),
                              ),
                              child: VitalButton.secondary(
                                onPressed: () =>
                                    context.push('/event/${event.id}'),
                                child: Text(t.review),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (truncated) Text(t.designOverviewEventsHint),
                // The Events screen is a dock destination; dock-level
                // navigation matches the shell's own command behaviour.
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: VitalButton.secondary(
                    key: const ValueKey('overview-events-review'),
                    onPressed: () => context.go('/events'),
                    child: Text(t.events),
                  ),
                ),
              ],
            );
          },
          error: (_, _) => LoadFailure(
            onRetry: () => ref.invalidate(eventPageProvider(query)),
          ),
          loading: () => const SizedBox.shrink(),
        );
  }
}

/// A compact local empty block; the section itself already owns the card and
/// the heading, so this does not nest a second surface.
class _OverviewEmpty extends StatelessWidget {
  const _OverviewEmpty({
    required this.icon,
    required this.title,
    this.description,
    this.action,
  });

  final IconData icon;
  final String title;
  final String? description;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.mutedForeground;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            StitchIcon(icon, size: 44),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: VitalType.record),
                  if (description != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      description!,
                      style: VitalType.metadata.copyWith(color: muted),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        if (action != null) ...[
          const SizedBox(height: 12),
          Align(alignment: AlignmentDirectional.centerStart, child: action),
        ],
      ],
    );
  }
}
