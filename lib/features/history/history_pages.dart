import '../supporting/supporting_pages.dart';
import '../../ui/stitch_ui.dart';
import '../../ui/vital_ui.dart';

import 'dart:async';

import 'package:flutter/material.dart' show MaterialLocalizations;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../app/display_preferences.dart';
import '../../app/app_lock.dart';
import '../../data/record_store.dart';
import '../../app/history.dart';
import '../../app/storage.dart';
import '../../app/vital_app.dart';
import '../../l10n/app_localizations.dart';
import '../profiles/profile_pages.dart';
import '../recording/record_pages.dart';
import '../stock/stock_widgets.dart';
import 'history_calendar.dart';
import 'history_source.dart' show historySourceProvider;

final historyNowProvider = Provider<DateTime Function()>(
  (ref) =>
      () => DateTime.now().toUtc(),
);

class HistoryPage extends ConsumerStatefulWidget {
  const HistoryPage({super.key, this.location = '/history'});
  final String location;
  @override
  ConsumerState<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends ConsumerState<HistoryPage> {
  final scroll = ScrollController(),
      from = TextEditingController(),
      through = TextEditingController();
  Map<String, String> get seed => Uri.parse(widget.location).queryParameters;
  late Set<String> types = {...?seed['type']?.split(',')},
      events = {...?seed['event']?.split(',')};
  TimelineStatus status = TimelineStatus.all;
  CivilDate? selected, month;
  DateTime? appliedFrom, appliedBefore;
  bool calendar = false, filtersOpen = false, initialised = false;
  String? dateError;
  DateTime? movedAt;
  TimelineEntry? movedTarget;
  String? configuredIdentity;
  final Map<String, String> labels = {};
  final _anchorKey = GlobalKey();
  bool _anchorPositioned = false;
  Timer? _relativeTimer;
  String? _relativeDay;

  @override
  void didUpdateWidget(HistoryPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.location == widget.location) return;
    types = {...?seed['type']?.split(',')};
    events = {...?seed['event']?.split(',')};
    initialised = false;
    configuredIdentity = null;
    dateError = null;
    movedAt = null;
    movedTarget = null;
    _anchorPositioned = false;
  }

  HistoryController get controller =>
      ref.read(historyControllerProvider(widget.location).notifier);
  @override
  void initState() {
    super.initState();
    scroll.addListener(() {
      controller.atTop = scroll.offset < 32;
    });
  }

  @override
  void dispose() {
    _relativeTimer?.cancel();
    scroll.dispose();
    from.dispose();
    through.dispose();
    super.dispose();
  }

  CivilDate? parseDate(String text) {
    try {
      final d = DateTime.parse('${text.trim()}T00:00:00Z');
      if (d.toIso8601String().substring(0, 10) != text.trim()) return null;
      return CivilDate(d.year, d.month, d.day);
    } catch (_) {
      return null;
    }
  }

  TimelineFilter filter(FeedScope scope, String zone) {
    return TimelineFilter(
      scope: scope,
      itemId: seed['item'],
      actualUnit: seed['unit'],
      typeIds: types,
      eventIds: events,
      status: status,
      fromInstant: appliedFrom,
      beforeInstant: appliedBefore,
    );
  }

  String viewLocation(String personId, {TimelineEntry? entry}) => Uri(
    path: '/history',
    queryParameters: {
      ...Uri.parse(
        historyLocation(
          scope: FeedScope.person(personId),
          itemId: seed['item'],
          actualUnit: seed['unit'],
          fromInstant: appliedFrom,
          beforeInstant: appliedBefore,
          typeIds: types,
          eventIds: events,
          anchor: entry?.id.sortKey ?? seed['anchor'],
        ),
      ).queryParameters,
      'status': status.name,
      'view': calendar ? 'calendar' : 'list',
      if (month != null) 'month': month.toString(),
      if (selected != null) 'selected': selected.toString(),
      if (entry != null)
        'anchorAt': entry.occurredAt.toIso8601String()
      else if (seed['anchorAt'] != null)
        'anchorAt': seed['anchorAt']!,
    },
  ).toString();

  void selectDay(CivilDate date, String zone) {
    final bounds = DisplayTime().dayBounds(date, zone);
    setState(() {
      selected = date;
      from.text = date.toString();
      through.text = date.toString();
      appliedFrom = bounds.start;
      appliedBefore = bounds.endExclusive;
      dateError = null;
    });
  }

  String artifactLocation(
    String path,
    String personId,
    CivilDate today,
    String zone,
  ) {
    final display = DisplayTime();
    final start = appliedFrom == null
        ? CivilDate(today.year, 1, 1)
        : display.instant(appliedFrom!, zone).civilDate;
    final end = appliedBefore == null
        ? today
        : display
              .instant(
                appliedBefore!.subtract(const Duration(microseconds: 1)),
                zone,
              )
              .civilDate;
    return Uri(
      path: path,
      queryParameters: {
        if (path == '/reports') 'person': personId,
        'from': start.toString(),
        'before': end.addDays(1).toString(),
        if (path == '/exports') 'content': 'doses',
        'return': viewLocation(personId),
      },
    ).toString();
  }

  Future<void> inspect(TimelineEntry entry) async {
    await context.push(
      Uri(
        path: '/history-source/${entry.id.kind.name}/${entry.id.value}',
        queryParameters: {
          'person': entry.personId,
          'return': viewLocation(entry.personId, entry: entry),
        },
      ).toString(),
      extra: entry,
    );
    if (!mounted) return;
    final latest = await (await ref.read(recordStoreProvider.future))
        .historyEntry(entry.id, personId: entry.personId);
    if (!mounted) return;
    if (latest == null) {
      // The browsed entry no longer resolves; drop its row and keep the
      // window and position it had.
      controller.withdrawEntry(entry.id);
    } else if (latest.occurredAt == entry.occurredAt) {
      // Unmoved correction: replace the row in place, without resetting the
      // loaded pages or the scroll position. The store re-validates the row
      // against the current filtered snapshot first.
      await controller.spliceEntry(latest);
    } else {
      // The entry changed its position. Its old row cannot stand for the
      // corrected one, so remove it and offer the new position instead.
      controller.withdrawEntry(entry.id);
      setState(() {
        movedAt = latest.occurredAt;
        movedTarget = latest;
      });
    }
    // The live first page is reattached; older windows stay anchored until Refresh.
    controller.visible(true);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context),
        zone = ref.watch(displayZoneProvider),
        preferences = ref.watch(displayPreferencesProvider),
        people = ref.watch(profilesProvider),
        state = ref.watch(historyControllerProvider(widget.location));
    if (!people.hasValue) {
      return PageContent(children: [Text(t.loadingRecords)]);
    }
    const personId = meId;
    const scope = FeedScope.me();
    final anchor = seed['anchor'];
    final originalAnchorTime = DateTime.tryParse(seed['anchorAt'] ?? '');
    final anchorEntry = anchor == null || originalAnchorTime == null
        ? null
        : ref
              .watch(historySourceProvider((id: anchor, personId: personId)))
              .value;
    final effectiveMovedAt =
        movedAt ??
        (anchorEntry != null && anchorEntry.occurredAt != originalAnchorTime
            ? anchorEntry.occurredAt
            : null);
    final jumped = effectiveMovedAt == null ? null : movedTarget ?? anchorEntry;
    final display = DisplayTime(),
        formatter = displayFormatter(context, preferences.timeFormat);
    final now = ref.watch(historyNowProvider)();
    final today = display.instant(now, zone).civilDate;
    final relativeDates = {
      for (final shownZone in {
        zone,
        for (final entry in state.entries)
          if (entry.dateOnly) entry.planZone ?? zone,
      })
        shownZone: display.instant(now, shownZone).civilDate,
    };
    final dayIdentity = relativeDates.entries
        .map((entry) => '${entry.key}:${entry.value}')
        .join('|');
    if (_relativeDay != dayIdentity) {
      _relativeTimer?.cancel();
      _relativeDay = dayIdentity;
      final delay = relativeDates.entries
          .map(
            (entry) => display
                .dayBounds(entry.value, entry.key)
                .endExclusive
                .difference(now),
          )
          .reduce((first, second) => first < second ? first : second);
      _relativeTimer = Timer(delay + const Duration(milliseconds: 1), () {
        if (mounted) setState(() => _relativeDay = null);
      });
    }
    if (!initialised) {
      initialised = true;
      status =
          TimelineStatus.values
              .where((value) => value.name == seed['status'])
              .firstOrNull ??
          TimelineStatus.all;
      calendar = seed['view'] == 'calendar';
      selected = seed['selected'] == null ? null : parseDate(seed['selected']!);
      final start = DateTime.tryParse(seed['from'] ?? ''),
          end = DateTime.tryParse(seed['before'] ?? '');
      appliedFrom = start?.toUtc();
      appliedBefore = end?.toUtc();
      if (start != null) from.text = display.instant(start, zone).dateText;
      if (end != null) {
        through.text = display
            .instant(end.subtract(const Duration(microseconds: 1)), zone)
            .dateText;
      }
      month = seed['month'] == null ? null : parseDate(seed['month']!);
      month ??= CivilDate(today.year, today.month, 1);
    }
    final query = TimelineQuery(
      filter: filter(scope, zone),
      displayZone: zone,
      anchorId: seed['anchor'],
    );
    if (configuredIdentity != query.identity || state.query == null) {
      configuredIdentity = query.identity;
      scheduleMicrotask(() => controller.configure(query));
    }
    final visible = ModalRoute.of(context)?.isCurrent != false;
    scheduleMicrotask(() => controller.visible(visible));
    if (!_anchorPositioned &&
        anchor != null &&
        state.entries.any((entry) => entry.id.sortKey == anchor)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final target = _anchorKey.currentContext;
        if (!mounted || target == null) return;
        _anchorPositioned = true;
        Scrollable.ensureVisible(target, alignment: 0.1);
      });
    }
    final c = StitchColors(context);
    final locale = MaterialLocalizations.of(context);
    final groups = <String, _HistoryDayGroup>{};
    for (final entry in state.entries) {
      final entryZone = entry.dateOnly ? entry.planZone ?? zone : zone;
      final date = display.instant(entry.occurredAt, entryZone).civilDate;
      groups
          .putIfAbsent(date.toString(), () => _HistoryDayGroup(date))
          .entries
          .add(entry);
    }
    final stripQuery = query.restart(
      filter: query.filter.restart(clearFrom: true, clearBefore: true),
    );
    final activeFilters =
        status != TimelineStatus.all ||
        types.isNotEmpty ||
        events.isNotEmpty ||
        appliedFrom != null ||
        appliedBefore != null;
    final page = <Widget>[
      _HistoryTitleBlock(
        subtitle: t.screenHistorySubtitle,
        zone: display.resolveZone(zone).zoneId,
        onExport: () =>
            context.push(artifactLocation('/exports', personId, today, zone)),
      ),
      const SizedBox(height: 16),
      HistoryWeekStrip(
        query: stripQuery,
        today: today,
        selected: selected,
        onSelect: (date) => selectDay(date, zone),
      ),
      const SizedBox(height: 16),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _HistoryStatusChips(
            status: status,
            onChanged: (value) => setState(() => status = value),
          ),
          MergeSemantics(
            child: Semantics(
              key: const ValueKey('history-filters-toggle'),
              expanded: filtersOpen,
              child: VitalButton.secondary(
                leading: const Icon(LucideIcons.slidersHorizontal),
                onPressed: () => setState(() => filtersOpen = !filtersOpen),
                child: Text(t.historyFilters),
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: 12),
      VitalSegments<bool>(
        values: const [false, true],
        selected: calendar,
        label: (value) => value ? t.historyCalendar : t.historyTimeline,
        onChanged: (value) => setState(() {
          calendar = value;
          if (calendar && selected == null) {
            selectDay(
              display.instant(DateTime.now().toUtc(), zone).civilDate,
              zone,
            );
          }
        }),
      ),
      if (filtersOpen) ...[
        const SizedBox(height: 12),
        StitchSurface(
          radius: VitalLayout.sectionRadius,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                t.historyFilters,
                style: StitchType.name.copyWith(color: c.ink),
              ),
              const SizedBox(height: 12),
              LabelledInput(
                label: t.historyFrom,
                controller: from,
                error: dateError,
              ),
              LabelledInput(label: t.historyThrough, controller: through),
              Text(
                t.historyDateHelp,
                style: StitchType.caption.copyWith(color: c.muted),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  VitalButton.secondary(
                    onPressed: () {
                      final a = parseDate(from.text),
                          b = parseDate(through.text);
                      setState(() {
                        dateError =
                            (from.text.isNotEmpty && a == null) ||
                                (through.text.isNotEmpty && b == null) ||
                                (a != null && b != null && a.compareTo(b) > 0)
                            ? t.historyDateError
                            : null;
                        if (dateError == null) {
                          appliedFrom = a == null
                              ? null
                              : display.dayBounds(a, zone).start;
                          appliedBefore = b == null
                              ? null
                              : display.dayBounds(b, zone).endExclusive;
                        }
                        selected = null;
                      });
                    },
                    child: Text(t.apply),
                  ),
                  VitalButton.secondary(
                    onPressed: () => setState(() {
                      from.clear();
                      through.clear();
                      appliedFrom = null;
                      appliedBefore = null;
                      types.clear();
                      events.clear();
                      status = TimelineStatus.all;
                      selected = null;
                      dateError = null;
                    }),
                    child: Text(t.clear),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              HistoryFilterChoices(
                scope: scope,
                kind: 'type',
                selected: types,
                labels: labels,
                onChanged: (values) => setState(() => types = values),
              ),
              const SizedBox(height: 12),
              HistoryFilterChoices(
                scope: scope,
                kind: 'event',
                selected: events,
                labels: labels,
                onChanged: (values) => setState(() => events = values),
              ),
            ],
          ),
        ),
      ],
      if (!filtersOpen && activeFilters) ...[
        const SizedBox(height: 12),
        StitchSurface(
          radius: VitalLayout.sectionRadius,
          inset: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                t.historyFilters,
                style: StitchType.name.copyWith(color: c.ink),
              ),
              if (status != TimelineStatus.all) ...[
                const SizedBox(height: 4),
                Text(switch (status) {
                  TimelineStatus.recorded => t.statusRecorded,
                  TimelineStatus.skipped => t.statusSkipped,
                  TimelineStatus.voided => t.statusVoided,
                  TimelineStatus.all => t.statusAll,
                }, style: StitchType.caption.copyWith(color: c.muted)),
              ],
              if (types.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  t.historySelectedTypes(types.length),
                  style: StitchType.caption.copyWith(color: c.muted),
                ),
              ],
              if (events.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  t.historySelectedEvents(events.length),
                  style: StitchType.caption.copyWith(color: c.muted),
                ),
              ],
              if (appliedFrom != null || appliedBefore != null) ...[
                const SizedBox(height: 4),
                Text(
                  t.historyDateFilter(
                    from.text.isEmpty ? t.historyAnyDate : from.text,
                    through.text.isEmpty ? t.historyAnyDate : through.text,
                  ),
                  style: StitchType.caption.copyWith(color: c.muted),
                ),
              ],
            ],
          ),
        ),
      ],
      const SizedBox(height: 20),
      if (calendar)
        HistoryCalendarSection(
          query: selected == null
              ? query
              : query.restart(
                  filter: query.filter.restart(
                    clearFrom: true,
                    clearBefore: true,
                  ),
                ),
          month: month!,
          selected: selected,
          onMonth: (date) => setState(() => month = date),
          onSelect: (date) => selectDay(date, zone),
        ),
      if (calendar) const SizedBox(height: 16),
      if (state.stale) ...[
        Semantics(liveRegion: true, child: Text(t.historyNewEntries)),
        const SizedBox(height: 8),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: VitalButton.secondary(
            onPressed: controller.refresh,
            child: Text(t.refresh),
          ),
        ),
      ],
      if (state.refreshed || (!state.loading && anchor != null))
        Semantics(liveRegion: true, child: Text(t.historyRefreshed)),
      // An anchor that no longer resolves inside the filtered snapshot shows
      // only the stale refresh path; its stored row no longer stands for the
      // entry, so no moved banner or View offer is built on it.
      if (effectiveMovedAt != null && !state.anchorUnavailable) ...[
        Semantics(
          liveRegion: true,
          child: Text(
            t.historyMoved(
              formatter.format(display.instant(effectiveMovedAt, zone)),
            ),
          ),
        ),
        if (jumped != null && !state.loading)
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: VitalButton.secondary(
              onPressed: () {
                setState(() => _anchorPositioned = false);
                controller.seek(jumped);
              },
              child: Text(t.view),
            ),
          ),
      ],
      if (state.loading) Text(t.loadingRecords),
      if (state.error != null) ...[
        Text(
          state.error is TimelineQueryException
              ? t.historyRangeTooBroadBody
              : t.historyLoadFailed,
        ),
        const SizedBox(height: 8),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: VitalButton.secondary(
            onPressed: controller.refresh,
            child: Text(t.retry),
          ),
        ),
      ],
      if (!state.loading && state.error == null && state.entries.isEmpty)
        StitchSurface(
          radius: VitalLayout.sectionRadius,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              StitchIcon(LucideIcons.history, size: 44),
              const SizedBox(height: 12),
              Text(
                t.historyNoEntries,
                style: StitchType.name.copyWith(color: c.ink),
              ),
              const SizedBox(height: 4),
              Text(
                t.historyNoEntriesBody,
                style: StitchType.caption.copyWith(color: c.muted),
              ),
              const SizedBox(height: 12),
              Text(
                t.historyNoCapturedPlan,
                style: StitchType.label.copyWith(
                  color: c.ink,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                t.historyNoCapturedPlanBody,
                style: StitchType.caption.copyWith(color: c.muted),
              ),
            ],
          ),
        ),
      for (final group in groups.values) ...[
        _HistoryDayHeader(
          date: group.date,
          entries: group.entries.length,
          today: today,
          locale: locale,
        ),
        const SizedBox(height: 8),
        for (final entry in group.entries)
          HistoryEntryCard(
            key: entry.id.sortKey == anchor
                ? _anchorKey
                : ValueKey(entry.id.sortKey),
            entry: entry,
            formatter: formatter,
            zone: zone,
            onInspect: () => inspect(entry),
          ),
        const SizedBox(height: 12),
      ],
      if (!state.loading && state.error == null && state.entries.isNotEmpty)
        Text(
          t.historyShowing(state.entries.length),
          style: StitchType.caption.copyWith(color: c.muted),
        ),
      if (state.olderLoading) Text(t.loadingRecords),
      if (state.next != null) ...[
        const SizedBox(height: 8),
        VitalButton.secondary(
          onPressed: state.olderLoading ? null : controller.older,
          child: Text(t.more),
        ),
      ],
      if (state.pages >= HistoryController.maxWindowPages)
        Text(
          t.historyWindow,
          style: StitchType.caption.copyWith(color: c.muted),
        ),
      const SizedBox(height: 24),
      _HistoryReportsPanel(
        onReports: () =>
            context.push(artifactLocation('/reports', personId, today, zone)),
        onCharts: () => context.push(
          Uri(
            path: '/charts',
            queryParameters: {
              'scope': personId,
              if (seed['item'] != null) 'item': seed['item']!,
              if (appliedFrom != null) 'from': appliedFrom!.toIso8601String(),
              if (appliedBefore != null)
                'before': appliedBefore!.toIso8601String(),
              'return': viewLocation(personId),
            },
          ).toString(),
        ),
        onSupporting: () => context.push(
          supportingLocation(
            personId,
            item: seed['item'],
            back: viewLocation(personId),
          ),
        ),
      ),
      const SizedBox(height: 12),
      const _HistoryAuditPreview(),
    ];
    return ListView(
      controller: scroll,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: VitalLayout.contentWidth,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: page,
            ),
          ),
        ),
      ],
    );
  }
}

class _HistoryDayGroup {
  _HistoryDayGroup(this.date);
  final CivilDate date;
  final List<TimelineEntry> entries = [];
}

class _HistoryTitleBlock extends StatelessWidget {
  const _HistoryTitleBlock({
    required this.subtitle,
    required this.zone,
    required this.onExport,
  });
  final String subtitle, zone;
  final VoidCallback onExport;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context), c = StitchColors(context);
    final largeText = MediaQuery.textScalerOf(context).scale(14) > 21;
    final heading = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          header: true,
          child: Text(
            t.history,
            style: StitchType.title.copyWith(color: c.ink),
          ),
        ),
        const SizedBox(height: 4),
        Text(subtitle, style: StitchType.body.copyWith(color: c.muted)),
      ],
    );
    final export = VitalButton(
      leading: const Icon(LucideIcons.package),
      onPressed: onExport,
      child: Text(t.exportTitle),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (largeText) ...[
          heading,
          const SizedBox(height: 12),
          Align(alignment: AlignmentDirectional.centerStart, child: export),
        ] else
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: heading),
              const SizedBox(width: 12),
              export,
            ],
          ),
        const SizedBox(height: 10),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: StitchBadge(t.shownInZone(zone)),
        ),
      ],
    );
  }
}

class _HistoryStatusChips extends StatelessWidget {
  const _HistoryStatusChips({required this.status, required this.onChanged});
  final TimelineStatus status;
  final ValueChanged<TimelineStatus> onChanged;

  String _label(AppLocalizations t, TimelineStatus value) => switch (value) {
    TimelineStatus.all => t.statusAll,
    TimelineStatus.recorded => t.statusRecorded,
    TimelineStatus.skipped => t.statusSkipped,
    TimelineStatus.voided => t.statusVoided,
  };

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Wrap(
      key: const ValueKey('history-status'),
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final value in TimelineStatus.values)
          MergeSemantics(
            child: Semantics(
              selected: value == status,
              inMutuallyExclusiveGroup: true,
              child: value == status
                  ? VitalButton(
                      onPressed: () => onChanged(value),
                      child: Text(_label(t, value)),
                    )
                  : VitalButton.secondary(
                      onPressed: () => onChanged(value),
                      child: Text(_label(t, value)),
                    ),
            ),
          ),
      ],
    );
  }
}

/// Seven real days ending today, using the bounded calendar counts.
///
/// The strip is a browsing aid only: it never invents adherence, a completion
/// percentage or a due dose. Selecting a day applies the same exact-day filter
/// as the month grid and is reflected in the history URL.
class HistoryWeekStrip extends ConsumerStatefulWidget {
  const HistoryWeekStrip({
    super.key,
    required this.query,
    required this.today,
    required this.selected,
    required this.onSelect,
  });
  final TimelineQuery query;
  final CivilDate today;
  final CivilDate? selected;
  final ValueChanged<CivilDate> onSelect;

  @override
  ConsumerState<HistoryWeekStrip> createState() => _HistoryWeekStripState();
}

class _HistoryWeekStripState extends ConsumerState<HistoryWeekStrip> {
  @override
  Widget build(BuildContext context) {
    final locale = Localizations.of<MaterialLocalizations>(
          context,
          MaterialLocalizations,
        )!,
        t = AppLocalizations.of(context),
        c = StitchColors(context);
    final dates = [for (var i = 6; i >= 0; i--) widget.today.addDays(-i)];
    final request = CalendarRequest(widget.query, dates);
    final result = ref.watch(historyCalendarProvider(request));
    final available = result.value != null;
    final unavailable = result.hasError
        ? t.historyLoadFailed
        : t.loadingRecords;
    final cells = {
      for (final cell in result.value?.cells ?? <HistoryCalendarCell>[])
        cell.date: cell,
    };
    final recorded = cells.values.fold(0, (sum, cell) => sum + cell.recorded);
    final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
    return StitchSurface(
      radius: VitalLayout.sectionRadius,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Builder(
              builder: (context) {
                final heading = Row(
                  children: [
                    StitchIcon(LucideIcons.calendarDays, size: 32),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        t.screenHistoryLastSevenDays,
                        style: StitchType.label.copyWith(
                          color: c.ink,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                );
                if (!available) return heading;
                final badge = VitalBadge(
                  t.screenHistoryRecordedCount(recorded),
                  compact: true,
                );
                if (MediaQuery.textScalerOf(context).scale(13) > 19) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [heading, const SizedBox(height: 6), badge],
                  );
                }
                return Row(
                  children: [
                    Expanded(child: heading),
                    const SizedBox(width: 8),
                    Flexible(child: badge),
                  ],
                );
              },
            ),
          ),
          if (!available && !result.hasError)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
              child: Text(
                unavailable,
                style: StitchType.caption.copyWith(color: c.muted),
              ),
            ),
          if (result.hasError)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    t.historyLoadFailed,
                    style: StitchType.caption.copyWith(color: c.muted),
                  ),
                  StitchButton(
                    compact: true,
                    onPressed: () =>
                        ref.invalidate(historyCalendarProvider(request)),
                    child: Text(t.retry),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 8),
          LayoutBuilder(
            builder: (context, constraints) {
              Widget cell(CivilDate date) {
                final marker = cells[date];
                final isSelected = date == widget.selected;
                final isToday = date == widget.today;
                final recorded = marker?.recorded ?? 0,
                    skipped = marker?.skipped ?? 0,
                    voided = marker?.voided ?? 0;
                return Semantics(
                  key: ValueKey('history-week-$date'),
                  button: true,
                  selected: isSelected,
                  label: available
                      ? t.historyDaySummary(
                          locale.formatFullDate(date.calendarValue),
                          recorded,
                          skipped,
                          voided,
                        )
                      : t.screenHistoryDayUnavailable(
                          locale.formatFullDate(date.calendarValue),
                          unavailable,
                        ),
                  excludeSemantics: true,
                  onTap: () => widget.onSelect(date),
                  child: _HistoryWeekCell(
                    available: available,
                    weekday:
                        locale.narrowWeekdays[date.calendarValue.weekday % 7],
                    day: date.day,
                    selected: isSelected,
                    today: isToday,
                    recorded: recorded,
                    skipped: skipped,
                    voided: voided,
                    onTap: () => widget.onSelect(date),
                  ),
                );
              }

              // Seven 48 px targets fit from 390 px upward with the strip's
              // compact gutters. Narrower windows and larger text use two
              // deliberate rows instead of hiding a day behind a scroll edge.
              final singleRow = constraints.maxWidth >= 336 && scale <= 1.3;
              final rows = singleRow
                  ? [dates]
                  : [dates.sublist(0, 4), dates.sublist(4)];
              return Column(
                children: [
                  for (var row = 0; row < rows.length; row++)
                    Padding(
                      padding: EdgeInsets.only(top: row == 0 ? 0 : 4),
                      child: Row(
                        children: [
                          for (final date in rows[row])
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: .5,
                                ),
                                child: cell(date),
                              ),
                            ),
                          for (var i = rows[row].length; i < 4; i++)
                            const Expanded(child: SizedBox()),
                        ],
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _HistoryWeekCell extends StatelessWidget {
  const _HistoryWeekCell({
    required this.weekday,
    required this.available,
    required this.day,
    required this.selected,
    required this.today,
    required this.recorded,
    required this.skipped,
    required this.voided,
    required this.onTap,
  });
  final String weekday;
  final bool available;
  final int day, recorded, skipped, voided;
  final bool selected, today;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = StitchColors(context);
    final marker = !available
        ? (icon: LucideIcons.circleHelp, colour: c.muted, fill: c.inset)
        : recorded > 0
        ? (icon: LucideIcons.check, colour: c.accent, fill: c.accentSurface)
        : skipped > 0
        ? (
            icon: LucideIcons.cross,
            colour: c.amber,
            fill: c.amber.withValues(alpha: .14),
          )
        : voided > 0
        ? (icon: LucideIcons.circleDot, colour: c.muted, fill: c.inset)
        : (
            icon: LucideIcons.circle,
            colour: c.muted.withValues(alpha: .45),
            fill: Colors.transparent,
          );
    return ButtonStyleOverride(
      padding: (_, _, _) => EdgeInsets.zero,
      decoration: (_, _, decoration) => decoration is BoxDecoration
          ? decoration.copyWith(
              color: Colors.transparent,
              border: Border.all(color: Colors.transparent),
              boxShadow: const [],
            )
          : decoration,
      child: Button(
        style: ButtonVariance.ghost,
        onPressed: onTap,
        disableTransition: MediaQuery.disableAnimationsOf(context),
        child: Container(
          width: double.infinity,
          constraints: const BoxConstraints(minHeight: 68),
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            color: selected
                ? c.accentSurface
                : today
                ? c.inset
                : Colors.transparent,
            border: Border.all(color: selected ? c.accent : Colors.transparent),
            borderRadius: BorderRadius.circular(VitalLayout.sectionRadius),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                weekday,
                style: StitchType.small.copyWith(
                  color: selected ? c.accent : c.muted,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '$day',
                style: StitchType.label.copyWith(
                  color: c.ink,
                  fontWeight: selected || today
                      ? FontWeight.w700
                      : FontWeight.w500,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(height: 4),
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: marker.fill,
                  shape: BoxShape.circle,
                ),
                child: Icon(marker.icon, size: 14, color: marker.colour),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HistoryDayHeader extends StatelessWidget {
  const _HistoryDayHeader({
    required this.date,
    required this.entries,
    required this.today,
    required this.locale,
  });
  final CivilDate date;
  final int entries;
  final CivilDate today;
  final MaterialLocalizations locale;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context), c = StitchColors(context);
    final days = today.calendarValue.difference(date.calendarValue).inDays;
    final relative = switch (days) {
      0 => t.today,
      1 => t.historyYesterday,
      >= 2 && <= 6 => t.historyDaysAgo(days),
      _ => null,
    };
    final fullDate = locale.formatFullDate(date.calendarValue);
    final shortDate = locale.formatMediumDate(date.calendarValue);
    final counts = t.screenHistoryEntryCount(entries);
    final largeText = MediaQuery.textScalerOf(context).scale(13) > 19;
    final title = relative == null
        ? Text(fullDate, style: StitchType.name.copyWith(color: c.ink))
        : Wrap(
            spacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(relative, style: StitchType.name.copyWith(color: c.ink)),
              Text(
                shortDate,
                style: StitchType.caption.copyWith(color: c.muted),
              ),
            ],
          );
    final heading = Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: days == 0 ? c.accent : c.line,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 8),
        Flexible(child: title),
      ],
    );
    final badge = VitalBadge(counts, compact: true);
    return Semantics(
      header: true,
      label: '${relative ?? fullDate}. $fullDate. $counts.',
      child: ExcludeSemantics(
        child: largeText
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [heading, const SizedBox(height: 6), badge],
              )
            : Row(
                children: [
                  Expanded(child: heading),
                  const SizedBox(width: 8),
                  badge,
                ],
              ),
      ),
    );
  }
}

class HistoryEntryCard extends ConsumerWidget {
  const HistoryEntryCard({
    super.key,
    required this.entry,
    required this.formatter,
    required this.zone,
    required this.onInspect,
  });
  final TimelineEntry entry;
  final DisplayTimeFormatter formatter;
  final String zone;
  final VoidCallback onInspect;

  IconData _icon(UseRecord record) =>
      record.actualUnit == 'ml' ? LucideIcons.droplets : LucideIcons.pill;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entry = this.entry;
    final t = AppLocalizations.of(context), c = StitchColors(context);
    final instant = DisplayTime().instant(
      entry.occurredAt,
      entry.dateOnly ? entry.planZone ?? zone : zone,
    );
    final exact = formatter.format(instant, includeOffset: true);
    final now = DisplayTime().instant(
      ref.watch(historyNowProvider)(),
      instant.zoneId,
    );
    final days = now.civilDate.calendarValue
        .difference(instant.civilDate.calendarValue)
        .inDays;
    final relative = switch (days) {
      0 => t.today,
      1 => t.historyYesterday,
      >= 2 && <= 6 => t.historyDaysAgo(days),
      _ => formatter.date(instant, full: true),
    };
    final statusLabel = switch (entry.status) {
      TimelineEntryStatus.recorded => t.statusRecorded,
      TimelineEntryStatus.skipped => t.statusSkipped,
      TimelineEntryStatus.voided => t.statusVoided,
    };
    final tone = switch (entry.status) {
      TimelineEntryStatus.recorded => VitalTone.positive,
      TimelineEntryStatus.skipped => VitalTone.warning,
      TimelineEntryStatus.voided => VitalTone.neutral,
    };

    late final IconData icon;
    late final String title, meta, timeText;
    final notes = <String>[];
    final combined = entry is CombinedTimelineEntry ? entry : null;
    final record = entry is RecordTimelineEntry ? entry.record : null;
    final skipped = entry is SkippedTimelineEntry ? entry : null;
    if (combined != null) {
      icon = LucideIcons.box;
      title = t.combinedHistory;
      meta = t.historyGroupContext;
      timeText = t.screenHistoryRecordedAt(formatter.time(instant));
    } else if (record != null) {
      icon = _icon(record);
      title = record.name;
      meta =
          '${stockRecordAmountNumber(t, record)} ${record.actualUnit} · ${record.form}';
      timeText = t.screenHistoryRecordedAt(formatter.time(instant));
      if (record.isVoided) notes.add(statusLabel);
    } else if (skipped != null) {
      icon = LucideIcons.calendarClock;
      title = skipped.context.itemName ?? t.historyInspection;
      meta = t.historyPlannedAmount(
        skipped.amount.enteredText,
        skipped.amount.unit,
      );
      timeText = skipped.dateOnly
          ? formatter.date(instant, full: true)
          : t.screenHistoryScheduledAt(formatter.time(instant));
      notes.add(t.historyPlannedDate(skipped.savedDate.toString()));
      notes.add(t.plannedInZone(skipped.planZone));
      if (skipped.dateOnly) notes.add(t.dateOnly);
      if (skipped.timeNeedsReview) notes.add(t.timeNeedsReview);
      notes.add(t.historySkippedHelp);
    } else {
      icon = LucideIcons.history;
      title = t.historyInspection;
      meta = statusLabel;
      timeText = formatter.format(instant, includeOffset: true);
    }

    final details = <Widget>[];
    if (combined != null) {
      for (final component in combined.components) {
        details.add(
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                StitchIcon(_icon(component.record), size: 32),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        component.record.name,
                        style: StitchType.label.copyWith(
                          color: c.ink,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        '${stockRecordAmountNumber(t, component.record)} '
                        '${component.record.actualUnit} · '
                        '${component.record.form}',
                        style: StitchType.caption.copyWith(color: c.muted),
                      ),
                      if (component.matched)
                        Text(
                          t.historyMatched,
                          style: StitchType.caption.copyWith(color: c.accent),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      }
    }
    if (notes.isNotEmpty) {
      details.add(
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: StitchSurface(
            radius: VitalLayout.sectionRadius,
            inset: true,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(LucideIcons.info, size: 16, color: c.muted),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final note in notes)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 2),
                          child: Text(
                            note,
                            style: StitchType.caption.copyWith(color: c.muted),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(title, style: StitchType.name.copyWith(color: c.ink)),
            VitalBadge(statusLabel, tone: tone, compact: true),
          ],
        ),
        const SizedBox(height: 4),
        Text(meta, style: StitchType.body.copyWith(color: c.muted)),
        const SizedBox(height: 6),
        Semantics(
          key: ValueKey('history-time-${entry.id.sortKey}'),
          label: entry.dateOnly
              ? t.historyDateZone(
                  formatter.date(instant, full: true),
                  entry.planZone ?? instant.zoneId,
                )
              : t.historyRelativeExact(relative, exact),
          excludeSemantics: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(timeText, style: StitchType.label.copyWith(color: c.muted)),
            ],
          ),
        ),
        ...details,
      ],
    );
    final action = Semantics(
      label: t.screenHistoryViewEntry(title),
      button: true,
      onTap: onInspect,
      child: ExcludeSemantics(
        child: StitchButton(
          compact: true,
          onPressed: onInspect,
          child: Text(t.view),
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: StitchSurface(
        radius: VitalLayout.sectionRadius,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final stack =
                constraints.maxWidth < 300 ||
                MediaQuery.textScalerOf(context).scale(13) > 19;
            final header = Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                StitchIcon(icon, size: 40),
                const SizedBox(width: 12),
                Expanded(child: content),
              ],
            );
            if (stack) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  header,
                  const SizedBox(height: 8),
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: action,
                  ),
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: header),
                const SizedBox(width: 8),
                action,
              ],
            );
          },
        ),
      ),
    );
  }
}

class _HistoryReportsPanel extends StatelessWidget {
  const _HistoryReportsPanel({
    required this.onReports,
    required this.onCharts,
    required this.onSupporting,
  });
  final VoidCallback onReports, onCharts, onSupporting;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context), c = StitchColors(context);
    return StitchSurface(
      radius: VitalLayout.sectionRadius,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              StitchIcon(LucideIcons.notebookPen, size: 40),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  t.reportsTitle,
                  style: StitchType.name.copyWith(color: c.ink),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            t.screenHistoryReportsHelp,
            style: StitchType.caption.copyWith(color: c.muted),
          ),
          const SizedBox(height: 12),
          VitalButton(
            expand: true,
            leading: const Icon(LucideIcons.notebookPen),
            onPressed: onReports,
            child: Text(t.reportsTitle),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              VitalButton.secondary(
                leading: const Icon(LucideIcons.activity),
                onPressed: onCharts,
                child: Text(t.chartsTitle),
              ),
              VitalButton.secondary(
                leading: const Icon(LucideIcons.flaskConical),
                onPressed: onSupporting,
                child: Text(t.supportingTitle),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HistoryAuditPreview extends StatelessWidget {
  const _HistoryAuditPreview();

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context), c = StitchColors(context);
    return StitchSurface(
      radius: VitalLayout.surfaceRadius,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  StitchIcon(LucideIcons.shieldCheck, size: 40),
                  const SizedBox(width: 12),
                  Text(
                    t.screenHistoryAudit,
                    style: StitchType.name.copyWith(color: c.ink),
                  ),
                ],
              ),
              StitchBadge(t.preview, warning: true),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            t.screenHistoryAuditPreview,
            style: StitchType.caption.copyWith(color: c.muted),
          ),
        ],
      ),
    );
  }
}

class CalendarRequest {
  CalendarRequest(this.query, this.dates);
  final TimelineQuery query;
  final List<CivilDate> dates;
  @override
  bool operator ==(Object other) =>
      other is CalendarRequest &&
      other.query.identity == query.identity &&
      other.dates.join(',') == dates.join(',');
  @override
  int get hashCode => Object.hash(query.identity, dates.join(','));
}

final historyCalendarProvider = FutureProvider.autoDispose
    .family<HistoryCalendar?, CalendarRequest>(retry: (_, _) => null, (
      ref,
      request,
    ) async {
      if (ref.watch(appLockProvider.select((s) => s.locked))) return null;
      return (await ref.watch(recordStoreProvider.future))
          .calendar(request.query, dates: request.dates);
    });

class HistoryCalendarSection extends ConsumerWidget {
  const HistoryCalendarSection({
    super.key,
    required this.query,
    required this.month,
    required this.selected,
    required this.onMonth,
    required this.onSelect,
  });
  final TimelineQuery query;
  final CivilDate month;
  final CivilDate? selected;
  final ValueChanged<CivilDate> onMonth, onSelect;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = Localizations.of<MaterialLocalizations>(
          context,
          MaterialLocalizations,
        )!,
        t = AppLocalizations.of(context);
    final request = CalendarRequest(
      query,
      historyCalendarDates(month, locale.firstDayOfWeekIndex),
    );
    final result = ref.watch(historyCalendarProvider(request));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (result.isLoading) Text(t.historyMonthLoading),
        if (result.hasError) ...[
          Text(t.historyLoadFailed),
          VitalButton.secondary(
            onPressed: () => ref.invalidate(historyCalendarProvider(request)),
            child: Text(t.retry),
          ),
        ],
        HistoryMonthGrid(
          month: month,
          selected: selected,
          zone: DisplayTime().resolveZone(query.displayZone).zoneId,
          counts: {
            for (final cell in result.value?.cells ?? <HistoryCalendarCell>[])
              cell.date: HistoryDayCounts(
                recorded: cell.recorded,
                skipped: cell.skipped,
                voided: cell.voided,
              ),
          },
          onMonth: onMonth,
          onSelect: onSelect,
        ),
        if (selected != null && result.hasValue && result.value != null)
          Builder(
            builder: (context) {
              final cell = result.value!.cells
                  .where((c) => c.date == selected)
                  .firstOrNull;
              return Text(
                t.historyDayCounts(
                  cell?.recorded ?? 0,
                  cell?.skipped ?? 0,
                  cell?.voided ?? 0,
                ),
              );
            },
          ),
      ],
    );
  }
}

typedef FilterRequest = ({
  FeedScope scope,
  String kind,
  String search,
  String? after,
});
final historyOptionsProvider = FutureProvider.autoDispose
    .family<HistoryOptionPage, FilterRequest>(retry: (_, _) => null, (
      ref,
      query,
    ) async {
      if (ref.watch(appLockProvider.select((s) => s.locked))) {
        return HistoryOptionPage(options: [], hasMore: false);
      }
      final store = await ref.watch(recordStoreProvider.future);
      return query.kind == 'type'
          ? store.historyTypeOptions(
              scope: query.scope,
              search: query.search,
              after: query.after,
            )
          : store.historyEventOptions(
              scope: query.scope,
              search: query.search,
              after: query.after,
            );
    });

class HistoryFilterChoices extends ConsumerStatefulWidget {
  const HistoryFilterChoices({
    super.key,
    required this.scope,
    required this.kind,
    required this.selected,
    required this.labels,
    required this.onChanged,
  });
  final FeedScope scope;
  final String kind;
  final Set<String> selected;
  final Map<String, String> labels;
  final ValueChanged<Set<String>> onChanged;
  @override
  ConsumerState<HistoryFilterChoices> createState() =>
      _HistoryFilterChoicesState();
}

class _HistoryFilterChoicesState extends ConsumerState<HistoryFilterChoices> {
  final search = TextEditingController();
  String applied = '', error = '';
  String? after;
  bool open = false;
  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final title = widget.kind == 'type' ? t.filterType : t.filterEvent;
    final limit = widget.kind == 'type'
        ? TimelineLimits.maxTypeIds
        : TimelineLimits.maxEventIds;
    final request = (
      scope: widget.scope,
      kind: widget.kind,
      search: applied,
      after: after,
    );
    final results = open ? ref.watch(historyOptionsProvider(request)) : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Heading(title),
        for (final id in widget.selected)
          Row(
            children: [
              Expanded(
                child: Text(
                  widget.labels[id] ??
                      (widget.kind == 'event'
                          ? t.filterEvent
                          : (id == 'legacy_unknown'
                                ? t.historyUnknownType
                                : t.filterType)),
                ),
              ),
              VitalButton.secondary(
                onPressed: () =>
                    widget.onChanged({...widget.selected}..remove(id)),
                child: Text(t.remove),
              ),
            ],
          ),
        MergeSemantics(
          child: Semantics(
            key: ValueKey('history-${widget.kind}-toggle'),
            expanded: open,
            child: VitalButton.secondary(
              onPressed: () => setState(() => open = !open),
              child: Text(t.choose),
            ),
          ),
        ),
        if (open) ...[
          LabelledInput(label: t.search, controller: search),
          VitalButton.secondary(
            onPressed: () => setState(() {
              applied = search.text.trim();
              after = null;
            }),
            child: Text(t.search),
          ),
          if (error.isNotEmpty) Text(error),
          if (results!.isLoading) Text(t.loadingRecords),
          if (results.hasError) ...[
            Text(t.historyLoadFailed),
            VitalButton.secondary(
              onPressed: () => ref.invalidate(historyOptionsProvider(request)),
              child: Text(t.retry),
            ),
          ],
          if (results.hasValue) ...[
            if (results.requireValue.options.isEmpty) Text(t.historyNoOptions),
            for (final option in results.requireValue.options)
              Semantics(
                selected: widget.selected.contains(option.id),
                child: VitalButton.secondary(
                  multiline: true,
                  onPressed: () {
                    if (widget.selected.contains(option.id)) {
                      widget.onChanged({...widget.selected}..remove(option.id));
                      return;
                    }
                    if (widget.selected.length >= limit) {
                      setState(() => error = t.historyFilterLimit(limit));
                      return;
                    }
                    widget.labels[option.id] = option.label == 'legacy_unknown'
                        ? t.historyUnknownType
                        : option.label;
                    widget.onChanged({...widget.selected, option.id});
                    setState(() => error = '');
                  },
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        option.label == 'legacy_unknown'
                            ? t.historyUnknownType
                            : option.label,
                      ),
                      if (option.personId != null)
                        Text(
                          t.profileOwner(ownerLabel(ref, t, option.personId!)),
                        ),
                    ],
                  ),
                ),
              ),
            if (results.requireValue.hasMore)
              VitalButton.secondary(
                onPressed: () =>
                    setState(() => after = results.requireValue.next),
                child: Text(t.more),
              ),
            if (after != null)
              VitalButton.secondary(
                onPressed: () => setState(() => after = null),
                child: Text(t.reset),
              ),
          ],
        ],
      ],
    );
  }
}
