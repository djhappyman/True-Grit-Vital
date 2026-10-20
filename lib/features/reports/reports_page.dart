import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../app/display_preferences.dart';
import '../../app/reports.dart';
import '../../app/settings_toggle_row.dart';
import '../../app/vital_app.dart';
import '../../data/record_store.dart';
import '../../l10n/app_localizations.dart';
import '../events/event_pages.dart' show eventPageProvider;
import '../../ui/vital_ui.dart';
import '../profiles/profile_pages.dart';
import '../recording/record_pages.dart';

/// Stable entry point for the current report template.
const reportsLocation = '/reports';
const reportPreviewLocation = '/reports/preview';

class ReportsPage extends ConsumerStatefulWidget {
  const ReportsPage({super.key, this.from, this.before, this.returnLocation});
  final String? from, before, returnLocation;
  @override
  ConsumerState<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends ConsumerState<ReportsPage> {
  final from = TextEditingController(),
      through = TextEditingController(),
      reportName = TextEditingController();
  String? dateError;
  bool initialised = false, openedPreview = false;

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
    if (!mounted) return;
    final selection = ref.read(reportControllerProvider).selection;
    if (selection == null || ref.read(reportControllerProvider).busy) return;
    final start = parseDate(from.text), end = parseDate(through.text);
    if (start == null || end == null || end.compareTo(start) < 0) return;
    final next = selection.copyWith(
      fromDate: start,
      beforeDate: end.addDays(1),
    );
    if (next == selection) return;
    if (dateError != null) setState(() => dateError = null);
    ref.read(reportControllerProvider.notifier).select(next);
  }

  void _syncReportName() {
    if (!mounted) return;
    final selection = ref.read(reportControllerProvider).selection;
    if (selection == null || ref.read(reportControllerProvider).busy) return;
    final value = reportName.text.trim();
    if (value.length > 120) return;
    if ((value.isEmpty ? null : value) ==
        (selection.reportName?.trim().isEmpty ?? true
            ? null
            : selection.reportName?.trim())) {
      return;
    }
    ref
        .read(reportControllerProvider.notifier)
        .setReportName(value.isEmpty ? null : value);
  }

  CivilDate? parseDate(String text) {
    try {
      final date = CivilDate.parse(text.trim());
      return date;
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final people = ref.watch(profilesProvider);
    final state = ref.watch(reportControllerProvider);
    final preferences = ref.watch(displayPreferencesProvider);
    final use24Hour = displayFormatter(
      context,
      preferences.timeFormat,
    ).use24Hour;
    ref.listen(reportControllerProvider, (previous, next) {
      if (!mounted || openedPreview) return;
      if (next.phase == ReportPhase.ready && next.artifact != null) {
        openedPreview = true;
        context
            .push(reportPreviewLocation)
            .whenComplete(() => openedPreview = false);
      }
    });
    return Scaffold(
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
                    if (back != null) {
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
          if (!initialised) {
            initialised = true;
            final now = DateTime.now();
            from.text = widget.from ?? '${now.year}-01-01';
            through.text =
                (widget.before == null
                    ? null
                    : parseDate(widget.before!)?.addDays(-1).toString()) ??
                '${now.year}-${now.month.toString().padLeft(2, '0')}-'
                    '${now.day.toString().padLeft(2, '0')}';
            final selection = ReportSelection(
              personId: selected,
              fromDate: parseDate(from.text) ?? CivilDate(now.year, 1, 1),
              beforeDate:
                  (parseDate(through.text) ??
                          CivilDate(now.year, now.month, now.day))
                      .addDays(1),
              displayZone: ref.read(displayZoneProvider),
            );
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                ref.read(reportControllerProvider.notifier).select(selection);
              }
            });
          }
          final current = state.selection;
          final effective =
              current ??
              ReportSelection(
                personId: selected,
                fromDate: parseDate(from.text) ?? CivilDate(2000, 1, 1),
                beforeDate: (parseDate(through.text) ?? CivilDate(2100, 1, 1))
                    .addDays(1),
                displayZone: ref.read(displayZoneProvider),
              );
          final items =
              ref.watch(reportItemsProvider(effective.personId)).value ??
              const <SubstanceItem>[];
          final person = profiles
              .where((profile) => profile.id == effective.personId)
              .firstOrNull;
          return PageContent(
            panelled: true,
            children: [
              Heading(t.reportsTitle),
              Text(t.reportScopeHelp),
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
                onChanged: state.busy
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
                  enabled: !state.busy,
                  onChanged: (eventId) => ref
                      .read(reportControllerProvider.notifier)
                      .select(effective.copyWith(eventId: eventId)),
                ),
              ],
              if (effective.template ==
                  ReportTemplateId.r02DetailedHistory) ...[
                const SizedBox(height: 16),
                SettingsToggleRow(
                  label: t.reportSkippedRows,
                  description: t.reportSkippedRowsHelp,
                  value: effective.includeSkipped,
                  enabled: !state.busy,
                  reduceMotion: MediaQuery.disableAnimationsOf(context),
                  onChanged: (value) => ref
                      .read(reportControllerProvider.notifier)
                      .select(effective.copyWith(includeSkipped: value)),
                ),
                SettingsToggleRow(
                  label: t.reportUnrecordedRows,
                  description: t.reportUnrecordedRowsHelp,
                  value: effective.includeUnrecorded,
                  enabled: !state.busy,
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
                enabled: !state.busy,
              ),
              LabelledInput(
                label: t.reportThrough,
                controller: through,
                helper: t.reportThroughHelp,
                enabled: !state.busy,
              ),
              LabelledInput(
                label: t.reportIdentity,
                controller: reportName,
                helper: t.reportNameHelp,
                enabled: !state.busy,
              ),
              const SizedBox(height: 4),
              _ItemSelection(
                items: items,
                selected: effective.itemIds,
                enabled: !state.busy,
                onChanged: _setItems,
              ),
              const SizedBox(height: 16),
              SettingsToggleRow(
                label: t.reportContext,
                description: t.reportContextHelp,
                value: effective.includeSupporting,
                enabled: !state.busy,
                reduceMotion: MediaQuery.disableAnimationsOf(context),
                onChanged: (value) {
                  ref
                      .read(reportControllerProvider.notifier)
                      .setIncludeSupporting(value);
                  if (!value) {
                    ref
                        .read(reportControllerProvider.notifier)
                        .setIncludeNotes(false);
                  }
                },
              ),
              SettingsToggleRow(
                label: t.reportNotes,
                description: t.reportNotesHelp,
                value: effective.includeNotes,
                enabled: !state.busy && effective.includeSupporting,
                reduceMotion: MediaQuery.disableAnimationsOf(context),
                onChanged: (value) => ref
                    .read(reportControllerProvider.notifier)
                    .setIncludeNotes(value),
              ),
              SettingsToggleRow(
                label: t.reportSources,
                description: t.reportSourcesHelp,
                value: effective.includeAttachments,
                enabled: !state.busy,
                reduceMotion: MediaQuery.disableAnimationsOf(context),
                onChanged: (value) => ref
                    .read(reportControllerProvider.notifier)
                    .setIncludeAttachments(value),
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
                  onPressed: state.busy ? null : () => _generate(use24Hour),
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

  void _generate(bool use24Hour) {
    final selection = ref.read(reportControllerProvider).selection;
    if (selection == null) return;
    final start = parseDate(from.text), before = parseDate(through.text);
    if (start == null || before == null) {
      setState(() => dateError = AppLocalizations.of(context).historyDateError);
      return;
    }
    if (before.compareTo(start) < 0) {
      setState(() => dateError = AppLocalizations.of(context).historyDateError);
      return;
    }
    if (reportName.text.trim().length > 120) {
      setState(() => dateError = AppLocalizations.of(context).reportNameLimit);
      return;
    }
    if (selection.template.requiresEvent && selection.eventId == null) {
      setState(
        () => dateError = AppLocalizations.of(context).reportEventRequired,
      );
      return;
    }
    final exclusive = before.addDays(1);
    setState(() => dateError = null);
    ref
        .read(reportControllerProvider.notifier)
        .select(
          selection.copyWith(
            personId: selection.personId,
            fromDate: start,
            beforeDate: exclusive,
            displayZone: ref.read(displayZoneProvider),
            reportName: reportName.text.trim().isEmpty
                ? null
                : reportName.text.trim(),
            includeNotes: selection.includeNotes,
            includeAttachments: selection.includeAttachments,
            includeSupporting: selection.includeSupporting,
            itemIds: selection.itemIds,
          ),
        );
    ref.read(reportControllerProvider.notifier).generate(use24Hour: use24Hour);
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
