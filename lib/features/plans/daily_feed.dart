import '../../app/display_preferences.dart';
import '../../ui/vital_ui.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../app/device_zone.dart';
import '../../app/storage.dart';
import '../../data/record_store.dart';
import '../../l10n/app_localizations.dart';
import '../recording/record_pages.dart';
import '../stock/stock_widgets.dart';
import '../products/product_widgets.dart';
import '../profiles/profile_pages.dart';
import 'plan_form.dart';
import 'interval_review.dart';
import 'interval_editor.dart';
import 'interval_clock.dart';
import 'plan_providers.dart';
import '../reminders/reminder_pages.dart';

class DailyFeed extends ConsumerStatefulWidget {
  const DailyFeed({super.key, required this.scope});
  final FeedScope scope;
  @override
  ConsumerState<DailyFeed> createState() => _DailyFeedState();
}

class _DailyFeedState extends ConsumerState<DailyFeed> {
  final _upcoming = <DailyIdentity, bool>{};

  @override
  void didUpdateWidget(DailyFeed oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scope != widget.scope) _upcoming.clear();
  }

  @override
  Widget build(BuildContext context) {
    final scope = widget.scope;
    final t = AppLocalizations.of(context);
    final zone = ref.watch(observedDeviceZoneProvider);
    final rows = ref.watch(dailyFeedProvider(scope));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (zone.value?.zoneId == null) ...[
          Text(t.planZoneUnavailable),
          VitalButton.secondary(
            onPressed: () => ref.invalidate(observedDeviceZoneProvider),
            child: Text(t.retry),
          ),
        ],
        rows.when(
          data: (result) {
            final now = DateTime.now().toUtc();
            final due = <DailyRow>[], upcoming = <DailyRow>[];
            for (final row in result.rows) {
              final id = row.expectation.identity;
              final starts =
                  row.expectation.windowStart ?? row.expectation.instant;
              final isUpcoming = row.isResolved
                  ? _upcoming[id] ?? (starts?.isAfter(now) ?? false)
                  : starts?.isAfter(now) ?? false;
              // Keep a just-recorded row in place so its Undo stays under the finger.
              _upcoming[id] = isUpcoming;
              (isUpcoming ? upcoming : due).add(row);
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (result.rows.isEmpty && result.complete)
                  Text(t.planNothingToday),
                if (due.isNotEmpty)
                  VitalSection(
                    title: Text(t.todayDue),
                    children: [
                      for (final row in due)
                        DailyRowCard(
                          key: ValueKey(row.expectation.identity),
                          row: row,
                        ),
                    ],
                  ),
                if (upcoming.isNotEmpty)
                  VitalSection(
                    title: Text(t.todayUpcoming),
                    children: [
                      for (final row in upcoming)
                        DailyRowCard(
                          key: ValueKey(row.expectation.identity),
                          row: row,
                        ),
                    ],
                  ),
                if (!result.complete)
                  Text(
                    result.issue == null
                        ? t.planIncomplete
                        : result.issue ==
                              DailyCalculationIssue.observedZoneUnavailable
                        ? t.planZoneUnavailable
                        : t.planCalculationIssue,
                  ),
              ],
            );
          },
          error: (_, _) => LoadFailure(
            onRetry: () => ref.invalidate(dailyFeedProvider(scope)),
          ),
          loading: () => Text(t.loadingRecords),
        ),
        ref
            .watch(scopePlansProvider(scope))
            .when(
              data: (plans) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final saved
                      in plans
                          .take(100)
                          .where((p) => p.plan.timing is AsNeeded))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(t.planAsNeeded),
                          Text(t.planPrnHelp),
                          if (saved.plan.pauses.any(
                            (p) => p.contains(DateTime.now().toUtc()),
                          ))
                            Text(t.pauseState),
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
                          PlanItemContext(plan: saved.plan),
                          VitalButton.secondary(
                            onPressed: () => context.push(
                              '/phases/${saved.plan.itemId}?plan=${saved.plan.planId}',
                            ),
                            child: Text(t.phaseHeading),
                          ),
                          VitalButton.secondary(
                            onPressed: () =>
                                context.push('/record/${saved.plan.itemId}'),
                            child: Text(t.record),
                          ),
                        ],
                      ),
                    ),
                  if (plans.length > 100) Text(t.planIncomplete),
                ],
              ),
              error: (_, _) => LoadFailure(
                onRetry: () => ref.invalidate(scopePlansProvider(scope)),
              ),
              loading: () => const SizedBox.shrink(),
            ),
        ref
            .watch(nextDailyPlansProvider(scope))
            .when(
              data: (plans) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final summary in plans.rows.where(
                    (p) => p.result.next != null || p.plan.timing is! AsNeeded,
                  ))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          PlanItemContext(plan: summary.plan),
                          if (summary.plan.pauses.any(
                            (p) => p.contains(DateTime.now().toUtc()),
                          )) ...[
                            Text(t.pauseState),
                            Text(t.pauseRecordHelp),
                            VitalButton.secondary(
                              onPressed: () => context.push(
                                '/record/${summary.plan.itemId}',
                              ),
                              child: Text(t.record),
                            ),
                          ],
                          if (summary.plan.timing is ElapsedInterval)
                            (zone.value?.zoneId == null &&
                                    summary.plan.zoneBasis is! FixedHome
                                ? Text(t.planZoneUnavailable)
                                : IntervalPlanPreview(
                                    plan: summary.plan,
                                    observedZone:
                                        summary.plan.zoneBasis is FixedHome
                                        ? (summary.plan.zoneBasis as FixedHome)
                                              .zoneId
                                        : zone.value!.zoneId!,
                                  ))
                          else if (!(summary.plan.timing is DailyCount &&
                              summary.plan.pauses.any(
                                (pause) =>
                                    pause.contains(DateTime.now().toUtc()),
                              )))
                            Text(
                              !summary.result.complete
                                  ? t.planNextReview
                                  : summary.result.next == null
                                  ? t.planNoNext
                                  : t.planNext(
                                      summary.result.next!.identity.originalDate
                                          .toString(),
                                    ),
                            ),
                          if (!summary.result.complete &&
                              summary.result.calendarDate != null)
                            Text(
                              t.calendarKnownDate(
                                summary.result.calendarDate.toString(),
                              ),
                            ),
                          for (final review in summary.result.needsReview)
                            Text(expectationLabel(context, ref, t, review)),
                          if (ref
                                  .watch(scopePlansProvider(scope))
                                  .value
                                  ?.where(
                                    (s) => s.plan.planId == summary.plan.planId,
                                  )
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
                                    saved.plan.pauses.any(
                                          (p) => p.resume == null,
                                        )
                                        ? t.resume
                                        : t.pauseAction,
                                  ),
                                ),
                              ],
                            ),
                          Text(t.phaseSavedHelp),
                          VitalButton.secondary(
                            onPressed: () => context.push(
                              '/phases/${summary.plan.itemId}?plan=${summary.plan.planId}',
                            ),
                            child: Text(t.phaseHeading),
                          ),
                          VitalButton.secondary(
                            onPressed: () => context.push(
                              '/schedule/${summary.plan.itemId}?plan=${summary.plan.planId}',
                            ),
                            child: Text(t.edit),
                          ),
                        ],
                      ),
                    ),
                  if (!plans.complete) Text(t.planIncomplete),
                ],
              ),
              error: (_, _) => LoadFailure(
                onRetry: () => ref.invalidate(nextDailyPlansProvider(scope)),
              ),
              loading: () => const SizedBox.shrink(),
            ),
        const SizedBox(height: 20),
      ],
    );
  }
}

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

class DailyRowCard extends ConsumerStatefulWidget {
  const DailyRowCard({
    super.key,
    required this.row,
    this.showActions = true,
    this.historyMode = false,
    this.reminderTarget,
  });
  final DailyRow row;
  final bool showActions, historyMode;
  final ReminderTarget? reminderTarget;
  @override
  ConsumerState<DailyRowCard> createState() => _DailyRowCardState();
}

class _DailyRowCardState extends ConsumerState<DailyRowCard> {
  bool busy = false,
      actionConflict = false,
      loadingOlder = false,
      intervalReviewNeeded = false;
  final olderActions = <DailyAction>[];
  bool olderComplete = false;
  String? error;
  Future<void> Function()? pending;
  StoredStockContainer? stockSource;
  bool showSources = false;
  Future<void> run(Future<void> Function() operation) async {
    if (busy) return;
    pending ??= operation;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await pending!();
      pending = null;
      actionConflict = false;
    } catch (e) {
      actionConflict = e is CommandConflict;
      intervalReviewNeeded =
          e is CommandConflict && e.code == 'interval_actual_review';
      if (intervalReviewNeeded) pending = null;
      if (mounted) {
        setState(
          () => error = intervalReviewNeeded
              ? AppLocalizations.of(context).intervalEarlierReview
              : e is CommandConflict
              ? AppLocalizations.of(context).conflictFailure
              : AppLocalizations.of(context).saveFailure,
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void act(DailyActionKind kind) {
    final row = widget.row,
        reminderTarget = widget.reminderTarget,
        command = newCommandId(),
        actual = DateTime.now().toUtc();
    final stockUse =
        kind == DailyActionKind.taken &&
            stockSource != null &&
            row.productLabel == null
        ? StockUseInput(
            expectedGeneration: row.generation,
            containerId: stockSource!.id,
            expectedContainerRevision: stockSource!.revision,
            entered: EnteredStockAmount(
              row.expectation.amount.enteredText,
              row.expectation.amount.unit,
            ),
          )
        : null;
    final productUse = kind == DailyActionKind.taken && row.productLabel != null
        ? ProductUseInput(
            expectedGeneration: row.generation,
            label: row.productLabel!,
            expectedItemRevision: row.itemRevision,
            enteredVolume: EnteredStockAmount(
              row.expectation.amount.enteredText,
              'ml',
            ),
            containerId: stockSource?.id,
            expectedContainerRevision: stockSource?.revision,
            sourceLabel: stockSource?.productLabel,
          )
        : null;
    ReminderClockSample? intervalClockSample;
    run(() async {
      if (row.expectation.identity.intervalSegmentId != null) {
        intervalClockSample ??= await captureIntervalClock(ref);
      }
      await (await ref.read(recordStoreProvider.future)).actDaily(
        commandId: command,
        row: row,
        kind: kind,
        reminderTarget: reminderTarget,
        reminderObservedZone: ref
            .read(observedDeviceZoneProvider)
            .value
            ?.zoneId,
        stockUse: stockUse,
        productUse: productUse,
        actualAt: kind == DailyActionKind.taken ? actual : null,
        intervalClockSample: intervalClockSample,
      );
    });
  }

  Future<void> undo(DailyAction action) async {
    final row = widget.row, command = newCommandId();
    PhysicalCorrection? choice;
    List<IntervalChangeReview>? reviews;
    await run(() async {
      final store = await ref.read(recordStoreProvider.future);
      if (action.recordId != null && reviews == null) {
        final record = await store.recordById(
          action.recordId!,
          personId: row.expectation.identity.personId,
        );
        if (!mounted || record == null) return;
        reviews = await reviewIntervalMutation(
          context,
          ref,
          record,
          voided: true,
        );
        if (reviews == null || !mounted) return;
      }
      if (action.recordId != null && choice == null) {
        final movement = await store.stockUseForRecord(
          personId: row.expectation.identity.personId,
          recordId: action.recordId!,
        );
        if (!mounted) return;
        if (movement != null) {
          final c = await store.stockContainerById(
            personId: row.expectation.identity.personId,
            containerId: movement.containerId,
          );
          if (!mounted) return;
          final t = AppLocalizations.of(context);
          choice = await choosePhysicalCorrection(
            context,
            movement,
            personName: ownerLabel(ref, t, row.expectation.identity.personId),
            itemName: row.itemName,
            quantity: t.stockQuantity(
              row.expectation.amount.enteredText,
              row.expectation.amount.unit,
            ),
            containerLabel: c?.label ?? t.stockUnavailable,
          );
          if (choice == null || !mounted) return;
        }
      }
      await store.undoDaily(
        commandId: command,
        row: row,
        action: action,
        stockCorrection: choice,
        intervalReviews: reviews,
      );
    });
  }

  void windowClock(DailyExpectation endpoint, ClockDecision choice) {
    final row = widget.row, command = newCommandId();
    run(() async {
      await (await ref.read(recordStoreProvider.future)).chooseWindowClock(
        commandId: command,
        row: row,
        endpoint: endpoint,
        decision: choice,
      );
    });
  }

  void clock(ClockDecision choice) {
    final row = widget.row, command = newCommandId();
    run(() async {
      await (await ref.read(recordStoreProvider.future))
          .chooseDailyClock(commandId: command, row: row, decision: choice);
    });
  }

  @override
  void didUpdateWidget(covariant DailyRowCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.row.revision != widget.row.revision ||
        oldWidget.row.expectation.identity != widget.row.expectation.identity) {
      olderActions.clear();
      olderComplete = false;
    }
  }

  Future<void> moreActions() async {
    if (loadingOlder) return;
    final row = widget.row;
    setState(() => loadingOlder = true);
    try {
      final actions = await (await ref.read(recordStoreProvider.future))
          .dailyActions(
            row.expectation.identity,
            limit: 100,
            offset: 100 + olderActions.length,
          );
      if (mounted &&
          row.revision == widget.row.revision &&
          row.expectation.identity == widget.row.expectation.identity) {
        setState(() {
          olderActions.addAll(actions);
          olderComplete = actions.length < 100;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => error = AppLocalizations.of(context).historyUnavailable);
      }
    } finally {
      if (mounted) setState(() => loadingOlder = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context), r = widget.row, e = r.expectation;
    final currentlyPaused =
        !widget.historyMode &&
        (ref
                .watch(itemPlansProvider(e.itemId))
                .value
                ?.where(
                  (p) =>
                      p.plan.planId == e.identity.planId &&
                      p.plan.personId == e.identity.personId,
                )
                .any(
                  (p) => p.plan.pauses.any(
                    (pause) => pause.contains(DateTime.now().toUtc()),
                  ),
                ) ??
            false);
    final boundaryBlocked = e.eligibilityConflict != null;
    final resolved = r.takenCount + r.skippedCount >= (e.plannedCount ?? 1);
    final undoAction = r.actions.where((a) => !a.isUndone).firstOrNull;
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: VitalSurface(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              r.itemName,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            Text(t.profileOwner(ownerLabel(ref, t, e.identity.personId))),
            Text(expectationLabel(context, ref, t, e)),
            if (boundaryBlocked) ...[
              Text(t.phaseReviewIssue),
              VitalButton.secondary(
                onPressed: busy
                    ? null
                    : () => context.push(
                        '/phases/${e.itemId}?plan=${e.identity.planId}',
                      ),
                child: Text(t.review),
              ),
              VitalButton.secondary(
                onPressed: busy
                    ? null
                    : () => context.push('/record/${e.itemId}'),
                child: Text(t.record),
              ),
            ],
            if (r.productLabel != null) ...[
              if (stockSource != null) ...[
                Text(t.productFixedVolume),
                Heading(t.productOldLabel),
                ProductLabelView(
                  label: r.productLabel!,
                  volume: ExactAmount.parseEntry(e.amount.enteredText),
                ),
                Heading(t.productNewLabel),
              ],
              ProductLabelView(
                label: stockSource?.productLabel ?? r.productLabel!,
                volume: ExactAmount.parseEntry(e.amount.enteredText),
              ),
            ],
            Semantics(
              liveRegion: true,
              child: Text(
                t.planProgress(
                  r.takenCount,
                  r.skippedCount,
                  e.plannedCount ?? 1,
                ),
              ),
            ),
            if (error != null) Semantics(liveRegion: true, child: Text(error!)),
            if (widget.showActions) ...[
              if (intervalReviewNeeded)
                VitalButton.secondary(
                  onPressed: busy
                      ? null
                      : () => context.push('/record/${e.itemId}'),
                  child: Text(t.record),
                ),
              if (!r.actionsComplete) ...[
                Text(t.planOlderActions),
                for (final action in olderActions.where((a) => !a.isUndone))
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        t.planActionEntry(
                          action.kind == DailyActionKind.taken
                              ? t.taken
                              : t.skip,
                          displayStamp(context, ref, action.recordedAt),
                        ),
                      ),
                      VitalButton.secondary(
                        onPressed: busy || pending != null
                            ? null
                            : () => undo(action),
                        child: Text(t.undo),
                      ),
                    ],
                  ),
                if (!olderComplete)
                  VitalButton.secondary(
                    onPressed: loadingOlder ? null : moreActions,
                    child: Text(t.more),
                  ),
              ],
              if (actionConflict)
                VitalButton.secondary(
                  onPressed: busy
                      ? null
                      : () => setState(() {
                          pending = null;
                          actionConflict = false;
                          error = null;
                          ref.invalidate(dailyFeedProvider);
                          ref.invalidate(capturedDailyProvider);
                        }),
                  child: Text(t.review),
                ),
              if (currentlyPaused) ...[
                Text(t.pauseState),
                Text(t.pauseRecordHelp),
                VitalButton.secondary(
                  onPressed: busy
                      ? null
                      : () => context.push('/record/${e.itemId}'),
                  child: Text(t.record),
                ),
              ],
              if (!widget.historyMode && !currentlyPaused) Text(t.planTakenNow),
              if (!widget.historyMode && e.identity.sourceActualId != null)
                Text(t.intervalTakenHelp),
              if (!widget.historyMode &&
                  !resolved &&
                  !currentlyPaused &&
                  !boundaryBlocked) ...[
                VitalButton.secondary(
                  onPressed: busy || pending != null
                      ? null
                      : () => setState(() => showSources = !showSources),
                  child: Text(t.stockSourceAction),
                ),
                if (showSources)
                  StockSourcePicker(
                    personId: e.identity.personId,
                    itemId: e.itemId,
                    selectedId: stockSource?.id,
                    productOnly: r.productLabel != null,
                    enabled: !busy && pending == null,
                    onSelected: (c) => setState(() => stockSource = c),
                  ),
              ],
              if (undoAction?.recordId != null)
                ref
                    .watch(
                      recordLookupProvider((
                        personId: e.identity.personId,
                        recordId: undoAction!.recordId!,
                      )),
                    )
                    .maybeWhen(
                      data: (record) => record == null
                          ? const SizedBox.shrink()
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                ProductRecordDetails(record: record),
                                StockRecordEffect(record: record),
                              ],
                            ),
                      orElse: () => const SizedBox.shrink(),
                    ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  if (pending != null)
                    VitalButton.secondary(
                      onPressed: busy ? null : () => run(pending!),
                      child: Text(t.retry),
                    )
                  else ...[
                    if (!widget.historyMode &&
                        !resolved &&
                        !currentlyPaused &&
                        !boundaryBlocked)
                      DailySnoozeButton(row: r),
                    if (!widget.historyMode)
                      PlanCommand(
                        row: r,
                        label: t.taken,
                        primary: true,
                        onPressed:
                            busy ||
                                resolved ||
                                currentlyPaused ||
                                boundaryBlocked
                            ? null
                            : () => act(DailyActionKind.taken),
                      ),
                    if (!widget.historyMode)
                      PlanCommand(
                        row: r,
                        label: t.skip,
                        primary: false,
                        onPressed:
                            busy ||
                                resolved ||
                                currentlyPaused ||
                                boundaryBlocked
                            ? null
                            : () => act(DailyActionKind.skip),
                      ),
                    if (undoAction != null)
                      PlanCommand(
                        row: r,
                        label: t.undo,
                        primary: false,
                        onPressed: busy ? null : () => undo(undoAction),
                      ),
                    if (!widget.historyMode)
                      PlanCommand(
                        row: r,
                        label: t.extra,
                        primary: false,
                        onPressed: busy
                            ? null
                            : () => context.push('/record/${e.itemId}'),
                      ),
                    if (!widget.historyMode)
                      PlanCommand(
                        row: r,
                        label: t.edit,
                        primary: false,
                        onPressed: busy
                            ? null
                            : () => context.push(
                                '/schedule/${e.itemId}?plan=${e.identity.planId}',
                              ),
                      ),
                  ],
                ],
              ),
              if (!widget.historyMode)
                for (final endpoint in e.windowEndpoints.where(
                  (r) =>
                      r.resolution == DailyResolution.missingClock ||
                      r.resolution == DailyResolution.repeatedClock,
                )) ...[
                  Heading(t.planClockReview),
                  Text(
                    t.phaseEndpointLabel(
                      endpoint.identity.slotId?.endsWith(':start') == true
                          ? t.phaseWindowStart
                          : endpoint.identity.slotId?.endsWith(':end') == true
                          ? t.phaseWindowEnd
                          : t.phaseWindowAnchor,
                      endpoint.identity.originalDate.toString(),
                      displayWallTime(context, ref, endpoint.originalTime!),
                      endpoint.zoneId,
                    ),
                  ),
                  for (var i = 0; i < endpoint.clockCandidates.length; i++) ...[
                    Text(
                      t.planClockInstant(
                        displayStamp(
                          context,
                          ref,
                          endpoint.clockCandidates[i],
                          zoneId: endpoint.zoneId,
                        ),
                      ),
                    ),
                    VitalButton.secondary(
                      multiline: true,
                      onPressed: busy || pending != null
                          ? null
                          : () => windowClock(endpoint, ChooseClockInstance(i)),
                      child: Text(i == 0 ? t.earlier : t.later),
                    ),
                  ],
                  if (endpoint.resolution == DailyResolution.missingClock)
                    ClockReplacement(
                      expectation: endpoint,
                      enabled: !busy && pending == null,
                      onChoice: (choice) => windowClock(endpoint, choice),
                    ),
                ],
              if (!widget.historyMode &&
                  e.windowEndpoints.isEmpty &&
                  e.resolution == DailyResolution.repeatedClock) ...[
                const SizedBox(height: 12),
                Heading(t.planClockReview),
                for (var i = 0; i < e.clockCandidates.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          t.planClockInstant(
                            displayStamp(
                              context,
                              ref,
                              e.clockCandidates[i],
                              zoneId: e.zoneId,
                            ),
                          ),
                        ),
                        VitalButton.secondary(
                          multiline: true,
                          onPressed: busy || pending != null
                              ? null
                              : () => clock(ChooseClockInstance(i)),
                          child: Text(i == 0 ? t.earlier : t.later),
                        ),
                      ],
                    ),
                  ),
              ],
              if (!widget.historyMode &&
                  e.windowEndpoints.isEmpty &&
                  e.resolution == DailyResolution.missingClock) ...[
                const SizedBox(height: 12),
                Heading(t.planClockReview),
                Text(t.planNoAlertHelp),
                VitalButton.secondary(
                  onPressed: busy || pending != null
                      ? null
                      : () => clock(const NoAlert()),
                  child: Text(t.keep),
                ),
                ClockReplacement(
                  expectation: e,
                  enabled: !busy && pending == null,
                  onChoice: clock,
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class ClockReplacement extends ConsumerStatefulWidget {
  const ClockReplacement({
    super.key,
    required this.expectation,
    required this.enabled,
    required this.onChoice,
  });
  final DailyExpectation expectation;
  final bool enabled;
  final ValueChanged<ClockDecision> onChoice;
  @override
  ConsumerState<ClockReplacement> createState() => _ClockReplacementState();
}

class _ClockReplacementState extends ConsumerState<ClockReplacement> {
  final time = TextEditingController();
  String? error;
  WallTime? replacement;
  List<DateTime> candidates = [];
  @override
  void initState() {
    super.initState();
    time.addListener(clearChoice);
  }

  void clearChoice() {
    if (mounted) {
      setState(() {
        replacement = null;
        candidates = [];
        error = null;
      });
    }
  }

  @override
  void didUpdateWidget(covariant ClockReplacement oldWidget) {
    super.didUpdateWidget(oldWidget);
    final a = oldWidget.expectation, b = widget.expectation;
    if (a.identity != b.identity ||
        a.versionId != b.versionId ||
        a.zoneId != b.zoneId ||
        a.originalTime != b.originalTime) {
      replacement = null;
      candidates = [];
      error = null;
      time.clear();
    }
  }

  @override
  void dispose() {
    time.dispose();
    super.dispose();
  }

  void resolve() {
    try {
      final m = RegExp(r'^(\d{2}):(\d{2})$').firstMatch(time.text.trim());
      if (m == null) throw const FormatException();
      final at = WallTime(int.parse(m[1]!), int.parse(m[2]!));
      final options = DailyResolver().clock.candidates(
        widget.expectation.identity.originalDate,
        at,
        widget.expectation.zoneId,
      );
      if (options.isEmpty) throw const FormatException();
      setState(() {
        error = null;
        replacement = at;
        candidates = options;
      });
      if (options.length == 1) widget.onChoice(ReplaceClockTime(at));
    } catch (_) {
      setState(() => error = AppLocalizations.of(context).timeInvalid);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LabelledInput(
          label: t.planReplacementTime,
          controller: time,
          helper: t.timeExample,
          error: error,
          enabled: widget.enabled,
          keyboardType: TextInputType.datetime,
        ),
        VitalButton.secondary(
          onPressed: widget.enabled ? resolve : null,
          child: Text(t.replace),
        ),
        if (candidates.length > 1) ...[
          Text(t.planRepeatedClock),
          for (var i = 0; i < candidates.length; i++)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t.planClockInstant(
                    displayStamp(
                      context,
                      ref,
                      candidates[i],
                      zoneId: widget.expectation.zoneId,
                    ),
                  ),
                ),
                VitalButton.secondary(
                  multiline: true,
                  onPressed: widget.enabled
                      ? () => widget.onChoice(
                          ReplaceClockTime(replacement!, instanceIndex: i),
                        )
                      : null,
                  child: Text(i == 0 ? t.earlier : t.later),
                ),
              ],
            ),
        ],
      ],
    );
  }
}

class PlannedHistory extends ConsumerStatefulWidget {
  const PlannedHistory({super.key, required this.scope});
  final FeedScope scope;
  @override
  ConsumerState<PlannedHistory> createState() => _PlannedHistoryState();
}

class _PlannedHistoryState extends ConsumerState<PlannedHistory> {
  int pages = 1;
  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final results = [
      for (var page = 0; page < pages; page++)
        ref.watch(
          capturedDailyProvider((scope: widget.scope, offset: page * 50)),
        ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Heading(t.planHistory),
        Text(t.planHistoryHelp),
        for (var page = 0; page < results.length; page++)
          results[page].when(
            data: (result) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final row in result.rows.take(50))
                  DailyRowCard(
                    key: ValueKey(row.expectation.identity),
                    row: row,
                    historyMode: true,
                  ),
                if (!result.complete && result.rows.length < 51)
                  Text(t.planIncomplete),
              ],
            ),
            error: (_, _) => LoadFailure(
              onRetry: () => ref.invalidate(
                capturedDailyProvider((scope: widget.scope, offset: page * 50)),
              ),
            ),
            loading: () => Text(t.loadingRecords),
          ),
        if ((results.last.value?.rows.length ?? 0) > 50)
          VitalButton.secondary(
            onPressed: () => setState(() => pages++),
            child: Text(t.more),
          ),
      ],
    );
  }
}

class PlanCommand extends ConsumerWidget {
  const PlanCommand({
    super.key,
    required this.row,
    required this.label,
    required this.onPressed,
    this.primary = false,
  });
  final DailyRow row;
  final String label;
  final VoidCallback? onPressed;
  final bool primary;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final e = row.expectation;
    final name = AppLocalizations.of(context).planActionContext(
      label,
      ownerLabel(
        ref,
        AppLocalizations.of(context),
        row.expectation.identity.personId,
      ),
      row.itemName,
      e.amount.enteredText,
      e.amount.unit,
      e.identity.originalDate.toString(),
    );
    return Semantics(
      button: true,
      enabled: onPressed != null,
      onTap: onPressed,
      label: name,
      child: ExcludeSemantics(
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: primary
              ? VitalButton(onPressed: onPressed, child: Text(label))
              : VitalButton.secondary(onPressed: onPressed, child: Text(label)),
        ),
      ),
    );
  }
}
