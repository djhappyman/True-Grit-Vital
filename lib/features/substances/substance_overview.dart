import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../app/device_zone.dart';
import '../../app/display_preferences.dart';
import '../../app/storage.dart';
import '../../data/record_store.dart';
import '../../l10n/app_localizations.dart';
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
import '../stock/stock_widgets.dart'
    show StockBalanceText, stockRecordAmountNumber;
import '../supporting/supporting_pages.dart' show supportingLocation;

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
    final back = _BackButton();
    return ref
        .watch(itemLookupProvider(itemId))
        .when(
          data: (item) {
            if (item == null) {
              return VitalPage(
                title: t.substances,
                leading: back,
                children: [
                  VitalNotice(
                    tone: VitalTone.danger,
                    icon: LucideIcons.circleAlert,
                    child: Text(t.noItem),
                  ),
                ],
              );
            }
            return _LoadedOverview(item: item, back: back);
          },
          error: (_, _) => VitalPage(
            title: t.substances,
            leading: back,
            children: [
              LoadFailure(
                onRetry: () => ref.invalidate(itemLookupProvider(itemId)),
              ),
            ],
          ),
          loading: () => VitalPage(
            title: t.substances,
            leading: back,
            children: [Text(t.loadingRecords)],
          ),
        );
  }
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

class _LoadedOverview extends ConsumerWidget {
  const _LoadedOverview({required this.item, required this.back});

  final SubstanceItem item;
  final _BackButton back;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    return VitalPage(
      title: t.substances,
      leading: back,
      children: [
        VitalSurface(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              VitalRecordHeader(
                title: item.name,
                subtitle: t.itemDetails(item.form, item.type, item.unit),
              ),
              Text(t.profileOwner(ownerLabel(ref, t, item.personId))),
              if (item.catalogueSnapshot != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: CatalogueSource(snapshot: item.catalogueSnapshot!),
                ),
              const SizedBox(height: 16),
              VitalButton(
                expand: true,
                onPressed: () => context.push('/record/${item.id}'),
                child: Text(t.record),
              ),
              const SizedBox(height: 12),
              VitalActions(
                children: [
                  VitalButton.secondary(
                    multiline: true,
                    onPressed: () => context.push(
                      '/combined/${item.personId}?item=${item.id}',
                    ),
                    child: Text(t.combinedAction),
                  ),
                ],
              ),
              ProductLabelPanel(item: item),
            ],
          ),
        ),
        const SizedBox(height: VitalLayout.sectionGap),
        _OverviewSchedule(item: item),
        const SizedBox(height: VitalLayout.sectionGap),
        _OverviewStock(item: item),
        const SizedBox(height: VitalLayout.sectionGap),
        _OverviewHistory(item: item),
        const SizedBox(height: VitalLayout.sectionGap),
        VitalPanel(
          title: t.designOverviewContext,
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
                  onPressed: () =>
                      context.push('/use/${item.personId}/${item.id}'),
                  child: Text(t.useHistory),
                ),
              ],
            ),
            _OverviewEvents(item: item),
          ],
        ),
      ],
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
    final plans = ref.watch(
      overviewPlansProvider((
        itemId: item.id,
        scope: FeedScope.person(item.personId),
      )),
    );
    return plans.when(
      data: (saved) => VitalSection(
        title: Text(t.schedule),
        action: saved.isEmpty
            ? VitalButton.secondary(
                onPressed: () => context.push('/schedule/${item.id}'),
                child: Text(t.add),
              )
            : null,
        children: [
          if (saved.isEmpty)
            VitalEmptyState(
              title: t.designOverviewNoPlan,
              description: t.designOverviewNoPlanHelp,
              icon: LucideIcons.calendarClock,
            )
          else ...[
            for (final plan in saved.take(50))
              Padding(
                key: ValueKey(
                  'plan-${plan.plan.planId}-${plan.plan.versionId}',
                ),
                padding: const EdgeInsets.only(bottom: 16),
                child: VitalSurface(
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
              ),
            if (saved.length > 50) Text(t.designOverviewPlansBound),
          ],
        ],
      ),
      error: (_, _) => VitalSection(
        title: Text(t.schedule),
        children: [
          LoadFailure(
            onRetry: () => ref.invalidate(
              overviewPlansProvider((
                itemId: item.id,
                scope: FeedScope.person(item.personId),
              )),
            ),
          ),
        ],
      ),
      loading: () => VitalSection(
        title: Text(t.schedule),
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
    final shownZone = switch (plan.zoneBasis) {
      FixedHome home => home.zoneId,
      FollowingLocal() => ref.watch(observedDeviceZoneProvider).value?.zoneId,
    };
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
        ...phaseTimingSummary(context, ref, t, plan),
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
        _PlanNext(item: item, planId: plan.planId, paused: paused),
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
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [const SizedBox(height: 8), ...lines],
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
    return ref
        .watch(stockContainersProvider(query))
        .when(
          data: (containers) => VitalSection(
            title: Text(t.stock),
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
                VitalEmptyState(
                  title: t.designOverviewStockEmpty,
                  description: t.designOverviewStockHelp,
                  icon: LucideIcons.box,
                  action: VitalButton.secondary(
                    onPressed: () => context.push(
                      '/stock/${item.personId}/create?item=${item.id}',
                    ),
                    child: Text(t.add),
                  ),
                )
              else ...[
                for (final container in containers.take(50))
                  Padding(
                    key: ValueKey('container-${container.id}'),
                    padding: const EdgeInsets.only(bottom: 16),
                    child: VitalSurface(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(container.label, style: VitalType.label),
                          const SizedBox(height: 4),
                          Text(
                            t.stockStrengthValue(container.strength.label),
                            style: VitalType.metadata.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .mutedForeground,
                            ),
                          ),
                          StockBalanceText(container: container),
                        ],
                      ),
                    ),
                  ),
                if (containers.length > 50) Text(t.stockMore),
              ],
            ],
          ),
          error: (_, _) => VitalSection(
            title: Text(t.stock),
            children: [
              LoadFailure(
                onRetry: () => ref.invalidate(stockContainersProvider(query)),
              ),
            ],
          ),
          loading: () => VitalSection(
            title: Text(t.stock),
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
          data: (rows) => VitalSection(
            title: Text(t.history),
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
                VitalEmptyState(
                  title: t.noRecords,
                  description: t.historyReady,
                  icon: LucideIcons.history,
                )
              else ...[
                for (final record in rows.take(20))
                  Padding(
                    key: ValueKey('recent-${record.id}'),
                    padding: const EdgeInsets.only(bottom: 12),
                    child: VitalSurface(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            t.stockQuantity(
                              stockRecordAmountNumber(t, record),
                              record.actualUnit,
                            ),
                            style: VitalType.record,
                          ),
                          Text(
                            t.actualStamp(
                              displayStamp(context, ref, record.actualAt),
                            ),
                            style: VitalType.metadata,
                          ),
                          if (record.isVoided)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: VitalBadge(
                                t.voided,
                                tone: VitalTone.warning,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                if (rows.length > 20) Text(t.designOverviewHistoryHint),
              ],
            ],
          ),
          error: (_, _) => VitalSection(
            title: Text(t.history),
            children: [
              LoadFailure(
                onRetry: () => ref.invalidate(pagedRecordsProvider(query)),
              ),
            ],
          ),
          loading: () => VitalSection(
            title: Text(t.history),
            children: [Text(t.loadingRecords)],
          ),
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
                    padding: const EdgeInsets.only(bottom: 16),
                    child: VitalSurface(
                      padding: const EdgeInsets.all(16),
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
