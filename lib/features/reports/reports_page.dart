import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../app/app_lock.dart';
import '../../app/display_preferences.dart';
import '../../app/device_zone.dart';
import '../../app/reports.dart';
import '../../app/settings_toggle_row.dart';
import '../../app/storage.dart';
import '../../app/vital_app.dart';
import '../../data/record_store.dart';
import '../../l10n/app_localizations.dart';
import '../events/event_pages.dart'
    show eventDateLabel, eventLookupProvider, eventPageProvider;
import '../events/event_report_location.dart';
import '../plans/today_hero.dart' show todayNowProvider;
import '../../ui/vital_ui.dart';
import '../profiles/profile_pages.dart';
import '../recording/record_pages.dart';
import 'report_item_seed.dart';
import 'report_dates.dart';

/// Stable entry point for the current report template.
const reportsLocation = eventReportsLocation;
const reportPreviewLocation = '/reports/preview';

class ReportsPage extends ConsumerStatefulWidget {
  const ReportsPage({
    super.key,
    this.from,
    this.before,
    this.returnLocation,
    this.event,
    this.template,
    this.item,
  });
  final String? from, before, returnLocation, event, template, item;
  @override
  ConsumerState<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends ConsumerState<ReportsPage> {
  final from = TextEditingController(),
      through = TextEditingController(),
      reportName = TextEditingController();
  String? dateError;
  bool initialised = false, openedPreview = false;
  ReportSelection? _requestedSeed, _pendingSelection;
  bool _seedBlocked = false, _seedScheduled = false;
  bool _seedDatesUnavailable = false, _applyingSelection = false;
  bool _syncingInput = false;
  int _seedGeneration = 0;

  @override
  void initState() {
    super.initState();
    from.addListener(_syncDates);
    through.addListener(_syncDates);
    reportName.addListener(_syncReportName);
  }

  @override
  void dispose() {
    from.dispose();
    through.dispose();
    reportName.dispose();
    super.dispose();
  }

  void _syncDates() {
    if (!mounted || _applyingSelection) return;
    final state = ref.read(reportControllerProvider);
    final selection = state.selection;
    if (selection == null || state.busy || state.handoffBusy) return;
    final range = reportThroughRange(from.text, through.text);
    if (range == null) return;
    final next = selection.copyWith(
      fromDate: range.from,
      beforeDate: range.before,
    );
    if (next == selection) return;
    if (dateError != null) setState(() => dateError = null);
    _syncingInput = true;
    try {
      ref.read(reportControllerProvider.notifier).select(next);
    } finally {
      _syncingInput = false;
    }
  }

  void _syncReportName() {
    if (!mounted || _applyingSelection) return;
    final state = ref.read(reportControllerProvider);
    final selection = state.selection;
    if (selection == null || state.busy || state.handoffBusy) return;
    final value = reportName.text.trim();
    if (value.length > 120) return;
    if ((value.isEmpty ? null : value) ==
        (selection.reportName?.trim().isEmpty ?? true
            ? null
            : selection.reportName?.trim())) {
      return;
    }
    _syncingInput = true;
    try {
      ref
          .read(reportControllerProvider.notifier)
          .setReportName(value.isEmpty ? null : value);
    } finally {
      _syncingInput = false;
    }
  }

  ReportTemplateId _requestedTemplate() {
    if (widget.item != null) return ReportTemplateId.r01SubstanceSummary;
    final requested = widget.template?.trim().toLowerCase();
    return switch (requested) {
      'event' || 'r03' || 'r03eventreview' => ReportTemplateId.r03EventReview,
      'history' ||
      'r02' ||
      'r02detailedhistory' => ReportTemplateId.r02DetailedHistory,
      'summary' ||
      'r01' ||
      'r01substancesummary' => ReportTemplateId.r01SubstanceSummary,
      _ =>
        widget.event == null
            ? ReportTemplateId.r01SubstanceSummary
            : ReportTemplateId.r03EventReview,
    };
  }

  ReportSelection? _requestedSelection(
    DateTime now,
    String personId,
    ReportTemplateId template, {
    String? itemId,
  }) {
    try {
      final displayZone = ref.read(displayZoneProvider);
      final range = reportSeedRange(
        now: now,
        displayZone: displayZone,
        from: widget.from,
        before: widget.before,
      );
      if (range == null) return null;
      final event = widget.event;
      return ReportSelection(
        template: itemId == null
            ? template
            : ReportTemplateId.r01SubstanceSummary,
        personId: personId,
        fromDate: range.from,
        beforeDate: range.before,
        displayZone: displayZone,
        eventId:
            itemId == null &&
                template.requiresEvent &&
                event != null &&
                RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(event)
            ? event
            : null,
        itemIds: itemId == null ? const [] : [itemId],
      );
    } on ReportSelectionFailure {
      return null;
    } catch (_) {
      return null;
    }
  }

  void _applySelection(ReportSelection selection) {
    _applyingSelection = true;
    try {
      from.text = selection.fromDate.toString();
      through.text = selection.beforeDate.addDays(-1).toString();
      reportName.text = selection.reportName ?? '';
    } finally {
      _applyingSelection = false;
    }
  }

  void _replaceSeed(
    ReportState expected,
    ReportSelection seed,
    int generation,
  ) {
    if (!mounted ||
        generation != _seedGeneration ||
        !identical(seed, _requestedSeed) ||
        !ref
            .read(reportControllerProvider.notifier)
            .selectIfCurrent(seed, expected: expected)) {
      return;
    }
    setState(() {
      _seedBlocked = false;
      _requestedSeed = null;
    });
    _applySelection(seed);
  }

  @override
  void didUpdateWidget(ReportsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.from != widget.from ||
        oldWidget.before != widget.before ||
        oldWidget.item != widget.item ||
        oldWidget.event != widget.event ||
        oldWidget.template != widget.template) {
      _seedGeneration++;
      initialised = false;
      _seedDatesUnavailable = false;
      _seedBlocked = false;
      _seedScheduled = false;
      _pendingSelection = _requestedSeed = null;
      dateError = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final people = ref.watch(profilesProvider);
    final state = ref.watch(reportControllerProvider);
    final zoneObservation = ref.watch(observedDeviceZoneProvider);
    final editingEnabled = !state.busy && !state.handoffBusy;
    final preferences = ref.watch(displayPreferencesProvider);
    final use24Hour = displayFormatter(
      context,
      preferences.timeFormat,
    ).use24Hour;
    ref.listen(reportControllerProvider, (previous, next) {
      if (!mounted) return;
      final prior = previous?.selection, selected = next.selection;
      if (!_syncingInput &&
          prior != null &&
          selected != null &&
          (prior.fromDate != selected.fromDate ||
              prior.beforeDate != selected.beforeDate ||
              prior.reportName != selected.reportName)) {
        _applySelection(selected);
      }
      if (openedPreview) return;
      if (next.phase == ReportPhase.ready && next.artifact != null) {
        openedPreview = true;
        context
            .push(reportPreviewLocation)
            .whenComplete(() => openedPreview = false);
      }
    });
    return VitalScaffold(
      headers: [
        SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                VitalButton.secondary(
                  onPressed: () {
                    final back = widget.returnLocation;
                    if (widget.item != null && context.canPop()) {
                      // The overview stays mounted beneath a pushed item
                      // report, so popping retains its selected section.
                      context.pop();
                    } else if (back != null) {
                      context.go(back);
                    } else if (context.canPop()) {
                      context.pop();
                    } else {
                      context.go('/history');
                    }
                  },
                  child: Text(t.back),
                ),
                VitalButton.secondary(
                  onPressed: () => context.push('/appearance'),
                  child: Text(t.appearance),
                ),
              ],
            ),
          ),
        ),
      ],
      child: people.when(
        loading: () =>
            PageContent(panelled: true, children: [Text(t.loadingRecords)]),
        error: (_, _) =>
            PageContent(panelled: true, children: [Text(t.profileUnavailable)]),
        data: (profiles) {
          if (profiles.isEmpty) {
            return PageContent(
              panelled: true,
              children: [Text(t.profileUnavailable)],
            );
          }
          const requested = meId;
          if (!profiles.any((profile) => profile.id == requested)) {
            return PageContent(
              panelled: true,
              children: [Text(t.profileUnavailable)],
            );
          }
          const selected = meId;
          final requestedItemId = widget.item == null
              ? null
              : reportItemId(widget.item);
          final itemLookup = requestedItemId == null
              ? null
              : ref.watch(itemLookupProvider(requestedItemId));
          final requestedItem = itemLookup?.value;
          if (widget.item != null && requestedItemId == null) {
            return _ReportItemRecovery(message: t.reportItemInvalid);
          }
          if (itemLookup != null &&
              !itemLookup.hasValue &&
              !itemLookup.hasError) {
            return PageContent(
              panelled: true,
              children: [Text(t.loadingRecords)],
            );
          }
          if (itemLookup?.hasError ?? false) {
            return PageContent(
              panelled: true,
              children: [
                Heading(t.reportItemUnavailableTitle),
                const SizedBox(height: 16),
                LoadFailure(
                  onRetry: () =>
                      ref.invalidate(itemLookupProvider(requestedItemId!)),
                ),
              ],
            );
          }
          if (requestedItemId != null &&
              !reportItemOwnedBy(requestedItem, selected)) {
            return _ReportItemRecovery(message: t.reportItemMissing);
          }
          if (_seedDatesUnavailable) {
            return _ReportItemRecovery(message: t.reportItemDates);
          }
          if (!initialised) {
            if (zoneObservation.isLoading) {
              return PageContent(
                panelled: true,
                children: [Text(t.loadingRecords)],
              );
            }
            if (zoneObservation.hasError ||
                zoneObservation.value?.zoneId == null) {
              return _ReportItemRecovery(message: t.reportZoneUnavailable);
            }
            initialised = true;
            final requestedSelection = _requestedSelection(
              ref.read(todayNowProvider)(),
              selected,
              _requestedTemplate(),
              itemId: requestedItemId,
            );
            if (requestedSelection == null) {
              _seedDatesUnavailable = true;
              return _ReportItemRecovery(message: t.reportItemDates);
            } else {
              final active = ref.read(reportControllerProvider).selection;
              if (active != null &&
                  active.identity != requestedSelection.identity) {
                _seedBlocked = true;
                _requestedSeed = requestedSelection;
                _applySelection(active);
              } else {
                _applySelection(requestedSelection);
                if (active == null) {
                  _pendingSelection = requestedSelection;
                }
              }
            }
          }
          final current = state.selection;
          if (current == null && _pendingSelection != null && !_seedScheduled) {
            _seedScheduled = true;
            final pending = _pendingSelection!;
            final expected = state;
            final generation = _seedGeneration;
            final lock = ref.read(appLockProvider);
            final zone = ref.read(displayZoneProvider);
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted || generation != _seedGeneration) return;
              _seedScheduled = false;
              final controller = ref.read(reportControllerProvider.notifier);
              final applied =
                  identical(lock, ref.read(appLockProvider)) &&
                  zone == ref.read(observedDeviceZoneProvider).value?.zoneId &&
                  controller.selectIfCurrent(pending, expected: expected);
              final active = ref.read(reportControllerProvider).selection;
              setState(() {
                _pendingSelection = null;
                if (!applied) {
                  if (active == null) {
                    _seedDatesUnavailable = true;
                  } else {
                    _seedBlocked = true;
                    _requestedSeed = pending;
                  }
                }
              });
              if (!applied && active != null) _applySelection(active);
            });
          }
          final effective = current ?? _pendingSelection;
          if (effective == null) {
            return _ReportItemRecovery(message: t.reportItemDates);
          }
          final eventLookup =
              effective.template.requiresEvent && effective.eventId != null
              ? ref.watch(eventLookupProvider(effective.eventId!))
              : null;
          final selectedEvent = eventLookup?.value;
          final eventGuidance = selectedEvent == null
              ? null
              : eventReportRange(selectedEvent, effective);
          final selectedEventMissing =
              eventLookup != null &&
              eventLookup.hasValue &&
              eventLookup.value == null;
          final items =
              ref.watch(reportItemsProvider(effective.personId)).value ??
              const <SubstanceItem>[];
          final person = profiles
              .where((profile) => profile.id == effective.personId)
              .firstOrNull;
          final requestedSeed = _requestedSeed;
          final seedGeneration = _seedGeneration;
          return PageContent(
            panelled: true,
            children: [
              if (_seedBlocked) ...[
                VitalNotice(
                  action: VitalButton.secondary(
                    onPressed:
                        state.busy || state.handoffBusy || requestedSeed == null
                        ? null
                        : () => _replaceSeed(
                            state,
                            requestedSeed,
                            seedGeneration,
                          ),
                    child: Text(t.replace),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        t.reportSelectedTitle,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 4),
                      if (requestedItem != null)
                        Text(t.reportItemRequested(requestedItem.name)),
                      Text(t.batch15T03ReplaceBody),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],
              Heading(t.reportsTitle),
              Text(t.reportScopeHelp),
              if (requestedItem != null &&
                  !_seedBlocked &&
                  effective.itemIds.length == 1 &&
                  effective.itemIds.contains(requestedItem.id)) ...[
                const SizedBox(height: 16),
                VitalNotice(
                  key: const ValueKey('report-item-selected'),
                  icon: LucideIcons.pill,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        t.reportItemHeading,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 4),
                      Text(requestedItem.name, style: VitalType.record),
                      const SizedBox(height: 4),
                      Text(t.reportItemOnly),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 16),
              VitalSegments<ReportTemplateId>(
                values: ReportTemplateId.values,
                selected: effective.template,
                label: (template) => switch (template) {
                  ReportTemplateId.r01SubstanceSummary =>
                    t.reportSummaryTemplate,
                  ReportTemplateId.r02DetailedHistory =>
                    t.reportHistoryTemplate,
                  ReportTemplateId.r03EventReview => t.reportEventTemplate,
                },
                onChanged: !editingEnabled
                    ? (_) {}
                    : (template) => ref
                          .read(reportControllerProvider.notifier)
                          .select(
                            effective.copyWith(
                              template: template,
                              clearEventId: true,
                            ),
                          ),
              ),
              if (effective.template.requiresEvent) ...[
                const SizedBox(height: 16),
                _EventSelection(
                  key: ValueKey(effective.personId),
                  personId: effective.personId,
                  selected: effective.eventId,
                  enabled: editingEnabled,
                  onChanged: (eventId) => ref
                      .read(reportControllerProvider.notifier)
                      .select(effective.copyWith(eventId: eventId)),
                ),
                if (eventLookup != null) ...[
                  const SizedBox(height: 16),
                  _SelectedEventReview(
                    lookup: eventLookup,
                    guidance: eventGuidance,
                    enabled: editingEnabled,
                    onApplyDates: eventGuidance == null
                        ? null
                        : () => _applyEventDates(eventGuidance),
                    onRetry: () =>
                        ref.invalidate(eventLookupProvider(effective.eventId!)),
                  ),
                ],
              ],
              if (effective.template ==
                  ReportTemplateId.r02DetailedHistory) ...[
                const SizedBox(height: 16),
                SettingsToggleRow(
                  label: t.reportSkippedRows,
                  description: t.reportSkippedRowsHelp,
                  value: effective.includeSkipped,
                  enabled: editingEnabled,
                  reduceMotion: MediaQuery.disableAnimationsOf(context),
                  onChanged: (value) => ref
                      .read(reportControllerProvider.notifier)
                      .select(effective.copyWith(includeSkipped: value)),
                ),
                SettingsToggleRow(
                  label: t.reportUnrecordedRows,
                  description: t.reportUnrecordedRowsHelp,
                  value: effective.includeUnrecorded,
                  enabled: editingEnabled,
                  reduceMotion: MediaQuery.disableAnimationsOf(context),
                  onChanged: (value) => ref
                      .read(reportControllerProvider.notifier)
                      .select(effective.copyWith(includeUnrecorded: value)),
                ),
              ],
              const SizedBox(height: 20),
              LabelledInput(
                label: t.reportFrom,
                controller: from,
                helper: t.reportDateHelp,
                error: dateError,
                enabled: editingEnabled,
              ),
              LabelledInput(
                label: t.reportThrough,
                controller: through,
                helper: t.reportThroughHelp,
                enabled: editingEnabled,
              ),
              LabelledInput(
                label: t.reportIdentity,
                controller: reportName,
                helper: t.reportNameHelp,
                enabled: editingEnabled,
              ),
              const SizedBox(height: 4),
              _ItemSelection(
                items: items,
                selected: effective.itemIds,
                enabled: editingEnabled,
                onChanged: _setItems,
              ),
              const SizedBox(height: 16),
              SettingsToggleRow(
                label: t.reportContext,
                description: t.reportContextHelp,
                value: effective.includeSupporting,
                enabled: editingEnabled,
                reduceMotion: MediaQuery.disableAnimationsOf(context),
                onChanged: (value) {
                  ref
                      .read(reportControllerProvider.notifier)
                      .setIncludeSupporting(value);
                },
              ),
              SettingsToggleRow(
                label: t.reportNotes,
                description: t.reportNotesHelp,
                value: effective.includeNotes,
                enabled: editingEnabled,
                reduceMotion: MediaQuery.disableAnimationsOf(context),
                onChanged: (value) => ref
                    .read(reportControllerProvider.notifier)
                    .setIncludeNotes(value),
              ),
              SettingsToggleRow(
                label: t.reportSources,
                description: t.reportSourcesHelp,
                value: effective.includeAttachments,
                enabled: editingEnabled,
                reduceMotion: MediaQuery.disableAnimationsOf(context),
                onChanged: (value) => ref
                    .read(reportControllerProvider.notifier)
                    .setIncludeAttachments(value),
              ),
              SettingsToggleRow(
                label: t.featureReportStock,
                description: t.featureReportStockHelp,
                value: effective.includeStock,
                enabled: editingEnabled,
                reduceMotion: MediaQuery.disableAnimationsOf(context),
                onChanged: (value) => ref
                    .read(reportControllerProvider.notifier)
                    .setIncludeStock(value),
              ),
              const SizedBox(height: 16),
              VitalSurface(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      t.reportReview,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 6),
                    Text(t.reportPersonValue(person?.name ?? '')),
                    Text(
                      t.reportPeriodValue(
                        effective.fromDate.toString(),
                        effective.beforeDate.addDays(-1).toString(),
                        effective.displayZone,
                      ),
                    ),
                    Text(
                      effective.itemIds.isEmpty
                          ? t.reportAllItems
                          : t.reportItemCount(effective.itemIds.length),
                    ),
                    Text(
                      t.reportTemplateValue(
                        effective.template.id,
                        reportTemplateVersion(effective.template),
                      ),
                    ),
                    Text(
                      effective.includeStock
                          ? t.featureReportStockIncluded
                          : t.featureReportStockNotIncluded,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              if (state.phase == ReportPhase.capturing ||
                  state.phase == ReportPhase.rendering)
                Semantics(
                  liveRegion: true,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        state.phase == ReportPhase.capturing
                            ? t.reportCapturing
                            : t.reportRendering,
                      ),
                      const SizedBox(height: 8),
                      LinearProgressIndicator(
                        value: state.progress.clamp(0, 1),
                        minHeight: 8,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      const SizedBox(height: 12),
                      VitalButton.secondary(
                        onPressed: () => ref
                            .read(reportControllerProvider.notifier)
                            .cancel(),
                        child: Text(t.cancel),
                      ),
                    ],
                  ),
                )
              else
                VitalButton(
                  onPressed:
                      !editingEnabled ||
                          selectedEventMissing ||
                          (eventGuidance != null && !eventGuidance.covers)
                      ? null
                      : () => _generate(use24Hour),
                  child: Text(t.reportPreview),
                ),
              if (state.phase == ReportPhase.cancelled)
                Semantics(liveRegion: true, child: Text(t.reportCancelled)),
              if (state.phase == ReportPhase.failed)
                Semantics(
                  liveRegion: true,
                  child: Text(_failure(t, state.errorCode)),
                ),
              if (state.artifact != null && state.phase == ReportPhase.ready)
                Text(t.reportGenerated),
            ],
          );
        },
      ),
    );
  }

  void _setItems(Iterable<String> ids) {
    ref.read(reportControllerProvider.notifier).setItems(ids);
  }

  void _applyEventDates(EventReportRange guidance) {
    from.text = guidance.fromDate.toString();
    through.text = guidance.throughDate.toString();
  }

  void _generate(bool use24Hour) {
    final state = ref.read(reportControllerProvider);
    final selection = state.selection;
    if (selection == null ||
        state.busy ||
        state.handoffBusy ||
        ref.read(appLockProvider).locked) {
      return;
    }
    final t = AppLocalizations.of(context);
    final range = reportThroughRange(from.text, through.text);
    if (range == null) {
      setState(() => dateError = t.historyDateError);
      return;
    }
    if (reportName.text.trim().length > 120) {
      setState(() => dateError = t.reportNameLimit);
      return;
    }
    if (selection.template.requiresEvent && selection.eventId == null) {
      setState(() => dateError = t.reportEventRequired);
      return;
    }
    final next = selection.copyWith(
      personId: selection.personId,
      fromDate: range.from,
      beforeDate: range.before,
      displayZone: selection.displayZone,
      reportName: reportName.text.trim().isEmpty
          ? null
          : reportName.text.trim(),
      includeNotes: selection.includeNotes,
      includeAttachments: selection.includeAttachments,
      includeSupporting: selection.includeSupporting,
      itemIds: selection.itemIds,
    );
    if (next.template.requiresEvent && next.eventId != null) {
      final lookup = ref.read(eventLookupProvider(next.eventId!));
      final event = lookup.value;
      if (lookup.hasValue && event == null) {
        setState(() => dateError = t.reportEventMissing);
        return;
      }
      if (event != null) {
        final guidance = eventReportRange(event, next);
        if (!guidance.covers) {
          setState(() => dateError = _eventRangeMessage(t, guidance));
          return;
        }
      }
    }
    setState(() => dateError = null);
    ref.read(reportControllerProvider.notifier).select(next);
    ref.read(reportControllerProvider.notifier).generate(use24Hour: use24Hour);
  }
}

class _ReportItemRecovery extends StatelessWidget {
  const _ReportItemRecovery({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return PageContent(
      panelled: true,
      children: [
        Heading(t.reportsTitle),
        const SizedBox(height: 12),
        VitalNotice(
          key: const ValueKey('report-item-recovery'),
          tone: VitalTone.danger,
          icon: LucideIcons.circleAlert,
          child: Text(message),
        ),
      ],
    );
  }
}

class _ItemSelection extends StatelessWidget {
  const _ItemSelection({
    required this.items,
    required this.selected,
    required this.enabled,
    required this.onChanged,
  });
  final List<SubstanceItem> items;
  final Set<String> selected;
  final bool enabled;
  final ValueChanged<Iterable<String>> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text(
            t.reportContent,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        const SizedBox(height: 4),
        Text(t.reportContentHelp),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            MergeSemantics(
              child: Semantics(
                selected: selected.isEmpty,
                child: selected.isEmpty
                    ? VitalButton(
                        onPressed: enabled ? () => onChanged(const []) : null,
                        child: Text(t.reportAllItems),
                      )
                    : VitalButton.secondary(
                        onPressed: enabled ? () => onChanged(const []) : null,
                        child: Text(t.reportAllItems),
                      ),
              ),
            ),
            for (final item in items)
              MergeSemantics(
                child: Semantics(
                  selected: selected.contains(item.id),
                  child: selected.contains(item.id)
                      ? VitalButton(
                          onPressed: enabled ? () => _toggle(item.id) : null,
                          child: Text(item.name),
                        )
                      : VitalButton.secondary(
                          onPressed: enabled ? () => _toggle(item.id) : null,
                          child: Text(item.name),
                        ),
                ),
              ),
          ],
        ),
        if (items.isEmpty) Text(t.reportNoItems),
      ],
    );
  }

  void _toggle(String id) {
    final next = {...selected};
    if (selected.isEmpty) {
      next
        ..clear()
        ..add(id);
    } else if (!next.remove(id)) {
      next.add(id);
    }
    onChanged(next);
  }
}

String _failure(AppLocalizations t, String? code) => switch (code) {
  'report_source_limit' => t.reportSourceLimit,
  'report_attachment_limit' => t.reportAttachmentLimit,
  'report_page_limit' => t.reportPageLimit,
  'report_event' => t.reportEventRequired,
  'report_event_missing' => t.reportEventMissing,
  'report_event_range' => t.reportEventRange,
  'report_history_limit' ||
  'report_skip_limit' ||
  'report_plan_limit' ||
  'report_item_limit' => t.reportSourceLimit,
  'report_person_missing' => t.reportPersonMissing,
  'report_person_archived' => t.reportPersonArchived,
  'report_zone_unavailable' => t.reportZoneUnavailable,
  'report_locked' => t.reportLocked,
  'report_source_changed' => t.reportSourceChanged,
  'report_cancelled' => t.reportCancelled,
  _ => t.reportFailure,
};

class _EventSelection extends ConsumerStatefulWidget {
  const _EventSelection({
    super.key,
    required this.personId,
    required this.selected,
    required this.enabled,
    required this.onChanged,
  });
  final String personId;
  final String? selected;
  final bool enabled;
  final ValueChanged<String> onChanged;
  @override
  ConsumerState<_EventSelection> createState() => _EventSelectionState();
}

class _EventSelectionState extends ConsumerState<_EventSelection> {
  int _page = 0;
  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final query = (personId: widget.personId, offset: _page * 50);
    final events = ref.watch(eventPageProvider(query));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          t.reportEventTemplate,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Text(t.reportEventRangeHelp),
        const SizedBox(height: 8),
        events.when(
          data: (items) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (items.isEmpty) Text(t.reportNoEvents),
              for (final event in items.take(50))
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Semantics(
                    selected: event.id == widget.selected,
                    child: event.id == widget.selected
                        ? VitalButton(
                            onPressed: widget.enabled
                                ? () => widget.onChanged(event.id)
                                : null,
                            child: Text(event.name),
                          )
                        : VitalButton.secondary(
                            onPressed: widget.enabled
                                ? () => widget.onChanged(event.id)
                                : null,
                            child: Text(event.name),
                          ),
                  ),
                ),
              Wrap(
                spacing: 8,
                children: [
                  if (_page > 0)
                    VitalButton.secondary(
                      onPressed: widget.enabled
                          ? () => setState(() => _page--)
                          : null,
                      child: Text(t.previous),
                    ),
                  if (items.length > 50)
                    VitalButton.secondary(
                      onPressed: widget.enabled
                          ? () => setState(() => _page++)
                          : null,
                      child: Text(t.next),
                    ),
                ],
              ),
            ],
          ),
          error: (_, _) => LoadFailure(
            onRetry: () => ref.invalidate(eventPageProvider(query)),
          ),
          loading: () => Text(t.loadingRecords),
        ),
      ],
    );
  }
}

/// Keeps the chosen event visible and explains a date window that would make
/// capture fail, without changing the entered range until the user applies it.
class _SelectedEventReview extends StatelessWidget {
  const _SelectedEventReview({
    required this.lookup,
    required this.guidance,
    required this.enabled,
    required this.onApplyDates,
    required this.onRetry,
  });
  final AsyncValue<EventRecord?> lookup;
  final EventReportRange? guidance;
  final bool enabled;
  final VoidCallback? onApplyDates;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final event = lookup.value;
    return VitalSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (event != null) ...[
            Text(
              t.reportEventSelected(event.name),
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              t.eventPlannedLabel(
                eventDateLabel(t, event.plannedStart),
                eventDateLabel(t, event.plannedEnd, open: true),
              ),
            ),
            if (event.actualStart != null || event.actualEnd != null)
              Text(
                t.eventActualLabel(
                  eventDateLabel(t, event.actualStart),
                  eventDateLabel(t, event.actualEnd, open: !event.completed),
                ),
              ),
            Text(t.reportEventZoneValue(event.zoneId)),
            if (event.actualEnd == null && !event.completed)
              Text(t.reportEventOngoing),
            if (event.completed) Text(t.eventCompleted),
            if (guidance != null && !guidance!.covers) ...[
              const SizedBox(height: 8),
              Semantics(
                liveRegion: true,
                child: Text(_eventRangeMessage(t, guidance!)),
              ),
              const SizedBox(height: 8),
              Semantics(
                button: true,
                label: t.reportEventApplyRangeLabel(
                  guidance!.fromDate.toString(),
                  guidance!.throughDate.toString(),
                ),
                child: VitalButton.secondary(
                  onPressed: enabled ? onApplyDates : null,
                  child: Text(t.apply),
                ),
              ),
            ],
          ] else if (lookup.hasError)
            LoadFailure(onRetry: onRetry)
          else if (lookup.hasValue)
            Text(t.reportEventMissing)
          else
            Text(t.loadingRecords),
        ],
      ),
    );
  }
}

String _eventRangeMessage(AppLocalizations t, EventReportRange guidance) =>
    guidance.startKnown && guidance.endKnown
    ? t.reportEventRangeAction(
        guidance.fromDate.toString(),
        guidance.throughDate.toString(),
      )
    : t.reportEventRangePartialAction(
        guidance.fromDate.toString(),
        guidance.throughDate.toString(),
      );
