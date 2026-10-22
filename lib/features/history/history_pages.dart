import '../supporting/supporting_pages.dart';
import '../../ui/stitch_ui.dart';
import '../../ui/vital_ui.dart';

import 'dart:async';

import 'package:intl/intl.dart';

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
import 'history_date_jump.dart';
import 'history_source.dart' show historySourceProvider;
import 'routine_activity_summary.dart';

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
  bool calendar = true, filtersOpen = false, initialised = false;
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
    ref.invalidate(historyCalendarProvider);
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
      calendar = seed['view'] != 'list';
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
      if (calendar &&
          appliedFrom == null &&
          appliedBefore == null &&
          seed['anchor'] == null &&
          seed['item'] == null &&
          seed['unit'] == null &&
          seed['status'] == null &&
          seed['type'] == null &&
          seed['event'] == null) {
        selected ??= today;
        final bounds = display.dayBounds(selected!, zone);
        appliedFrom = bounds.start;
        appliedBefore = bounds.endExclusive;
        from.text = selected.toString();
        through.text = selected.toString();
        month = CivilDate(selected!.year, selected!.month, 1);
      }
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
    final activeFilters =
        status != TimelineStatus.all ||
        types.isNotEmpty ||
        events.isNotEmpty ||
        appliedFrom != null ||
        appliedBefore != null;
    final calendarQuery = selected == null
        ? query
        : query.restart(
            filter: query.filter.restart(clearFrom: true, clearBefore: true),
          );
    void selectCalendarDay(CivilDate date) {
      setState(() => month = CivilDate(date.year, date.month, 1));
      selectDay(date, zone);
    }

    final filtersToggle = VitalLocalOptions(
      key: const ValueKey('history-filters-toggle'),
      label: t.historyFilters,
      content: StitchSurface(
        radius: VitalLayout.sectionRadius,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              t.historyFilters,
              style: StitchType.name.copyWith(color: c.ink),
            ),
            const SizedBox(height: 12),
            _HistoryStatusChips(
              status: status,
              onChanged: (value) => setState(() => status = value),
            ),
            const SizedBox(height: 12),
            VitalSegments<bool>(
              values: const [true, false],
              selected: calendar,
              label: (value) => value ? t.historyCalendar : t.historyTimeline,
              onChanged: (value) => setState(() => calendar = value),
            ),
            const SizedBox(height: 12),
            Text(
              t.shownInZone(display.resolveZone(zone).zoneId),
              style: StitchType.caption,
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
                    final a = parseDate(from.text), b = parseDate(through.text);
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
    );
    final calendarTools = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        HistoryDateJumpButton(
          zone: zone,
          selected: selected,
          onSelected: selectCalendarDay,
        ),
        const SizedBox(width: 4),
        filtersToggle,
      ],
    );
    final page = <Widget>[
      if (calendar)
        HistoryCalendarSection(
          query: calendarQuery,
          tools: calendarTools,
          month: month!,
          selected: selected,
          onMonth: (date) {
            setState(() => month = date);
            selectDay(
              date.year == today.year && date.month == today.month
                  ? today
                  : date,
              zone,
            );
          },
          onSelect: selectCalendarDay,
        ),
      if (calendar) ...[
        const SizedBox(height: 12),
        HistoryRoutineActivity(query: calendarQuery, month: month!),
      ],
      if (calendar && selected != null) ...[
        const SizedBox(height: 12),
        HistoryWeekStrip(
          query: calendarQuery,
          today: today,
          selected: selected,
          onSelect: selectCalendarDay,
        ),
      ],
      if (calendar) const SizedBox(height: 16),
      if (!calendar)
        Align(alignment: AlignmentDirectional.centerEnd, child: filtersToggle),
      if (!filtersOpen &&
          (status != TimelineStatus.all ||
              types.isNotEmpty ||
              events.isNotEmpty ||
              (selected == null && activeFilters))) ...[
        const SizedBox(height: 8),
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: VitalBadge(t.calendarFiltered, compact: true),
        ),
      ],
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
      if (selected != null) ...[
        LayoutBuilder(
          builder: (context, constraints) {
            final heading = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  header: true,
                  child: Text(
                    DateFormat(
                      'EEEE, MMM d',
                      Localizations.localeOf(context).toString(),
                    ).format(selected!.calendarValue),
                    style: VitalType.section,
                  ),
                ),
                if (!state.loading && state.error == null)
                  Text(
                    state.next != null
                        ? t.historyShowing(state.entries.length)
                        : t.screenHistoryEntryCount(state.entries.length),
                    style: StitchType.caption.copyWith(color: c.muted),
                  ),
              ],
            );
            final todayAction = StitchButton(
              compact: true,
              icon: LucideIcons.calendarDays,
              onPressed: () {
                setState(() => month = CivilDate(today.year, today.month, 1));
                selectDay(today, zone);
              },
              child: Text(t.today),
            );
            if (constraints.maxWidth < 340 ||
                MediaQuery.textScalerOf(context).scale(16) > 21) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  heading,
                  const SizedBox(height: 8),
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: todayAction,
                  ),
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: heading),
                const SizedBox(width: 8),
                todayAction,
              ],
            );
          },
        ),
        const SizedBox(height: 16),
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
            ],
          ),
        ),
      for (final group in groups.values) ...[
        if (selected == null)
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
      Text(
        t.calendarMonthlySummary,
        style: StitchType.caption.copyWith(color: c.muted),
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: 8),
      Semantics(
        label: t.calendarExportMonth(
          locale.formatMonthYear(month!.calendarValue),
        ),
        child: VitalButton.secondary(
          expand: true,
          leading: const Icon(LucideIcons.download),
          onPressed: () {
            final start = CivilDate(month!.year, month!.month, 1);
            final next = DateTime.utc(start.year, start.month + 1, 1);
            context.push(
              Uri(
                path: '/reports',
                queryParameters: {
                  'person': personId,
                  'from': start.toString(),
                  'before': CivilDate(
                    next.year,
                    next.month,
                    next.day,
                  ).toString(),
                  'return': viewLocation(personId),
                },
              ).toString(),
            );
          },
          child: Text(t.exportTitle),
        ),
      ),
      const SizedBox(height: 8),
      Align(
        alignment: AlignmentDirectional.center,
        child: StitchButton(
          quiet: true,
          compact: true,
          icon: LucideIcons.pill,
          onPressed: () => context.go('/substances'),
          child: Text(t.substances),
        ),
      ),
      Align(
        alignment: AlignmentDirectional.centerEnd,
        child: VitalOverflow(
          label: t.more,
          actions: [
            VitalMenuAction(
              label: t.reportsTitle,
              icon: LucideIcons.fileText,
              onPressed: () => context.push(
                artifactLocation('/reports', personId, today, zone),
              ),
            ),
            VitalMenuAction(
              label: t.exportTitle,
              icon: LucideIcons.download,
              onPressed: () => context.push(
                artifactLocation('/exports', personId, today, zone),
              ),
            ),
            VitalMenuAction(
              label: t.chartsTitle,
              icon: LucideIcons.chartLine,
              onPressed: () => context.push(
                Uri(
                  path: '/charts',
                  queryParameters: {
                    'scope': personId,
                    if (seed['item'] != null) 'item': seed['item']!,
                    if (appliedFrom != null)
                      'from': appliedFrom!.toIso8601String(),
                    if (appliedBefore != null)
                      'before': appliedBefore!.toIso8601String(),
                    'return': viewLocation(personId),
                  },
                ).toString(),
              ),
            ),
            VitalMenuAction(
              label: t.supportingTitle,
              icon: LucideIcons.activity,
              onPressed: () => context.push(
                supportingLocation(
                  personId,
                  item: seed['item'],
                  back: viewLocation(personId),
                ),
              ),
            ),
          ],
        ),
      ),
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

/// Collapsed factual counts for the browsed month.
///
/// The month, the current filter scope and a Show command stay visible while
/// the counts are collapsed. Counts come from [routineActivityProvider], whose
/// stream follows record, correction, void, Undo and skip changes. Only the
/// representable days of [month] are aggregated, never the surrounding 42-cell
/// grid or the visible selected-day page. There is no adherence percentage,
/// streak, planned denominator or timing judgement.
class HistoryRoutineActivity extends ConsumerStatefulWidget {
  const HistoryRoutineActivity({
    super.key,
    required this.query,
    required this.month,
  });

  final TimelineQuery query;

  /// First day of the browsed month.
  final CivilDate month;

  @override
  ConsumerState<HistoryRoutineActivity> createState() =>
      _HistoryRoutineActivityState();
}

class _HistoryRoutineActivityState
    extends ConsumerState<HistoryRoutineActivity> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.of<MaterialLocalizations>(
      context,
      MaterialLocalizations,
    )!;
    final t = AppLocalizations.of(context), c = StitchColors(context);
    final locked = ref.watch(appLockProvider.select((state) => state.locked));
    final request = RoutineActivityRequest(
      query: widget.query,
      month: widget.month,
    );
    final result = _expanded
        ? ref.watch(routineActivityProvider(request))
        : const AsyncData<RoutineActivitySummary?>(null);
    // A retained event from a replaced query, a restore or a different
    // generation must never stand in for the current month.
    final generation = ref.watch(routineActivityGenerationProvider);
    final value = result.value;
    final summary =
        locked ||
            result.isLoading ||
            result.hasError ||
            generation == null ||
            value == null ||
            value.generation != generation ||
            value.queryIdentity != widget.query.identity ||
            value.month != request.month
        ? null
        : value;
    final available = summary != null;
    final status = widget.query.filter.status;
    final range = locale.formatMonthYear(widget.month.calendarValue);
    final scope = widget.query.filter.isUnfiltered
        ? t.routineActivityScopeAll
        : t.routineActivityScopeFiltered;
    final metrics = <Widget>[
      if (summary != null &&
          (status == TimelineStatus.all ||
              status == TimelineStatus.recorded)) ...[
        VitalMetric(
          key: const ValueKey('routine-activity-recorded-days'),
          label: t.routineActivityRecordedDays,
          value: '${summary.recordedDays}',
        ),
        VitalMetric(
          key: const ValueKey('routine-activity-recorded-entries'),
          label: t.routineActivityEntries,
          value: '${summary.recordedEntries}',
        ),
      ],
      if (summary != null &&
          (status == TimelineStatus.all || status == TimelineStatus.skipped))
        VitalMetric(
          key: const ValueKey('routine-activity-skipped-entries'),
          label: t.routineActivitySkippedEntries,
          value: '${summary.skippedEntries}',
        ),
      if (summary != null &&
          (status == TimelineStatus.all || status == TimelineStatus.voided))
        VitalMetric(
          key: const ValueKey('routine-activity-voided-entries'),
          label: t.routineActivityVoidedEntries,
          value: '${summary.voidedEntries}',
        ),
    ];
    return StitchSurface(
      key: const ValueKey('routine-activity-summary'),
      radius: VitalLayout.sectionRadius,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              StitchIcon(LucideIcons.activity, size: 32),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Semantics(
                      header: true,
                      child: Text(
                        t.routineActivityTitle,
                        style: StitchType.name.copyWith(
                          color: c.ink,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      range,
                      key: const ValueKey('routine-activity-range'),
                      style: StitchType.caption.copyWith(color: c.muted),
                    ),
                    Text(
                      scope,
                      key: const ValueKey('routine-activity-scope'),
                      style: StitchType.caption.copyWith(color: c.muted),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Semantics(
            expanded: _expanded,
            child: VitalButton.secondary(
              leading: Icon(
                _expanded ? LucideIcons.chevronUp : LucideIcons.chevronDown,
              ),
              onPressed: () => setState(() => _expanded = !_expanded),
              expand: true,
              child: Text(
                _expanded ? t.routineActivityHide : t.routineActivityShow,
              ),
            ),
          ),
          VitalReveal(
            expanded: _expanded,
            child: Padding(
              padding: const EdgeInsets.only(top: 12),
              child: locked
                  ? _HistorySummaryMessage(
                      key: const ValueKey('routine-activity-locked'),
                      text: t.routineActivityLocked,
                    )
                  : result.hasError
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Semantics(
                          liveRegion: true,
                          child: Text(
                            t.routineActivityFailed,
                            key: const ValueKey('routine-activity-failed'),
                            style: StitchType.caption.copyWith(color: c.muted),
                          ),
                        ),
                        StitchButton(
                          compact: true,
                          onPressed: () =>
                              ref.invalidate(routineActivityProvider(request)),
                          child: Text(t.retry),
                        ),
                      ],
                    )
                  : !available
                  ? _HistorySummaryMessage(
                      key: const ValueKey('routine-activity-loading'),
                      text: t.routineActivityLoading,
                    )
                  : !summary.hasEntries
                  ? _HistorySummaryMessage(
                      key: const ValueKey('routine-activity-empty'),
                      text: t.routineActivityEmpty,
                    )
                  : _HistoryMetrics(metrics: metrics),
            ),
          ),
        ],
      ),
    );
  }
}

/// One selected locale week of exact calendar counts.
///
/// The week follows the canonical selected calendar date and starts on the
/// same locale first day as the month grid. Counts come from the bounded
/// indexed calendar aggregate, not the loaded record page, so a full week
/// remains factual when the selected-day list is paged. It never invents
/// adherence, a completion percentage, planned doses or timing judgements.
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
    )!;
    final t = AppLocalizations.of(context), c = StitchColors(context);
    final locked = ref.watch(appLockProvider.select((state) => state.locked));
    final selected = widget.selected ?? widget.today;
    final dates = historyWeekDates(selected, locale.firstDayOfWeekIndex);
    final request = CalendarRequest(widget.query, dates);
    final result = ref.watch(historyCalendarProvider(request));
    final calendar = locked || result.isLoading || result.hasError
        ? null
        : result.value;
    final available = calendar != null;
    final cells = {
      for (final cell in calendar?.cells ?? <HistoryCalendarCell>[])
        cell.date: cell,
    };
    final recorded = cells.values.fold(0, (sum, cell) => sum + cell.recorded);
    final skipped = cells.values.fold(0, (sum, cell) => sum + cell.skipped);
    final voided = cells.values.fold(0, (sum, cell) => sum + cell.voided);
    final status = widget.query.filter.status;
    final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
    final range = t.featureHistoryWeekRange(
      locale.formatShortDate(dates.first.calendarValue),
      locale.formatShortDate(dates.last.calendarValue),
    );
    final metrics = <Widget>[
      if (status == TimelineStatus.all || status == TimelineStatus.recorded)
        VitalMetric(
          key: const ValueKey('history-week-recorded'),
          label: t.statusRecorded,
          value: '$recorded',
        ),
      if (status == TimelineStatus.all || status == TimelineStatus.skipped)
        VitalMetric(
          key: const ValueKey('history-week-skipped'),
          label: t.statusSkipped,
          value: '$skipped',
        ),
      if (status == TimelineStatus.all || status == TimelineStatus.voided)
        VitalMetric(
          key: const ValueKey('history-week-voided'),
          label: t.statusVoided,
          value: '$voided',
        ),
    ];
    final unavailable = locked
        ? t.featureHistoryWeekLocked
        : result.hasError
        ? t.featureHistoryWeekFailed
        : t.featureHistoryWeekLoading;
    return StitchSurface(
      key: const ValueKey('history-week-summary'),
      radius: VitalLayout.sectionRadius,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                StitchIcon(LucideIcons.calendarDays, size: 32),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Semantics(
                        header: true,
                        child: Text(
                          t.featureHistoryWeekTitle,
                          style: StitchType.name.copyWith(
                            color: c.ink,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (!locked) ...[
                        const SizedBox(height: 2),
                        Text(
                          range,
                          key: const ValueKey('history-week-range'),
                          style: StitchType.caption.copyWith(color: c.muted),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (locked)
            _HistorySummaryMessage(
              key: const ValueKey('history-week-locked'),
              text: t.featureHistoryWeekLocked,
            )
          else ...[
            if (result.hasError)
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        t.featureHistoryWeekFailed,
                        key: const ValueKey('history-week-failed'),
                        style: StitchType.caption.copyWith(color: c.muted),
                      ),
                    ),
                    StitchButton(
                      compact: true,
                      onPressed: () =>
                          ref.invalidate(historyCalendarProvider(request)),
                      child: Text(t.retry),
                    ),
                  ],
                ),
              )
            else if (!available)
              _HistorySummaryMessage(
                key: const ValueKey('history-week-loading'),
                text: t.featureHistoryWeekLoading,
              ),
            if (available) ...[
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: _HistoryMetrics(metrics: metrics),
              ),
            ],
            const SizedBox(height: 8),
            LayoutBuilder(
              builder: (context, constraints) {
                Widget cell(CivilDate date) {
                  final marker = cells[date];
                  final isSelected = date == selected;
                  final isToday = date == widget.today;
                  final label = available
                      ? switch (status) {
                          TimelineStatus.all => t.historyDaySummary(
                            locale.formatFullDate(date.calendarValue),
                            marker?.recorded ?? 0,
                            marker?.skipped ?? 0,
                            marker?.voided ?? 0,
                          ),
                          TimelineStatus.recorded =>
                            t.featureHistoryWeekDayRecorded(
                              locale.formatFullDate(date.calendarValue),
                              marker?.recorded ?? 0,
                            ),
                          TimelineStatus.skipped =>
                            t.featureHistoryWeekDaySkipped(
                              locale.formatFullDate(date.calendarValue),
                              marker?.skipped ?? 0,
                            ),
                          TimelineStatus.voided =>
                            t.featureHistoryWeekDayVoided(
                              locale.formatFullDate(date.calendarValue),
                              marker?.voided ?? 0,
                            ),
                        }
                      : t.screenHistoryDayUnavailable(
                          locale.formatFullDate(date.calendarValue),
                          unavailable,
                        );
                  return Semantics(
                    key: ValueKey('history-week-$date'),
                    button: true,
                    selected: isSelected,
                    label: label,
                    excludeSemantics: true,
                    onTap: () => widget.onSelect(date),
                    child: _HistoryWeekCell(
                      available: available,
                      weekday:
                          locale.narrowWeekdays[date.calendarValue.weekday % 7],
                      day: date.day,
                      selected: isSelected,
                      today: isToday,
                      recorded: marker?.recorded ?? 0,
                      skipped: marker?.skipped ?? 0,
                      voided: marker?.voided ?? 0,
                      onTap: () => widget.onSelect(date),
                    ),
                  );
                }

                // Seven 48 px targets fit from 336 px upward. Narrower windows
                // and larger text use two deliberate rows instead of hiding a
                // day behind a scroll edge.
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
                              Expanded(child: cell(date)),
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
        ],
      ),
    );
  }
}

class _HistorySummaryMessage extends StatelessWidget {
  const _HistorySummaryMessage({super.key, required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = StitchColors(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      child: Text(text, style: StitchType.caption.copyWith(color: c.muted)),
    );
  }
}

class _HistoryMetrics extends StatelessWidget {
  const _HistoryMetrics({required this.metrics});
  final List<Widget> metrics;

  @override
  Widget build(BuildContext context) {
    if (metrics.isEmpty) return const SizedBox.shrink();
    final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
    return LayoutBuilder(
      builder: (context, constraints) {
        final inline = constraints.maxWidth >= 240 && scale <= 1.3;
        if (!inline) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: metrics,
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < metrics.length; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              Expanded(child: metrics[i]),
            ],
          ],
        );
      },
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
    final markers = <Widget>[
      if (recorded > 0)
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(shape: BoxShape.circle, color: c.accent),
        ),
      if (skipped > 0) Icon(LucideIcons.minus, size: 14, color: c.amber),
      if (voided > 0) Icon(LucideIcons.x, size: 14, color: c.muted),
    ];
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
              SizedBox(
                height: 24,
                child: ExcludeSemantics(
                  child: !available
                      ? Icon(LucideIcons.circleHelp, size: 14, color: c.muted)
                      : Row(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: markers.isEmpty
                              ? [
                                  Icon(
                                    LucideIcons.circle,
                                    size: 10,
                                    color: c.muted.withValues(alpha: .45),
                                  ),
                                ]
                              : markers,
                        ),
                ),
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
    } else if (skipped != null) {
      icon = LucideIcons.calendarClock;
      title = skipped.context.itemName ?? t.historyInspection;
      meta = t.historyPlannedAmount(
        skipped.amount.enteredText,
        skipped.amount.unit,
      );
      timeText = skipped.dateOnly
          ? t.dateOnly
          : t.screenHistoryScheduledAt(formatter.time(instant));
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
    if (skipped?.timeNeedsReview == true) {
      details.add(
        Text(
          t.timeNeedsReview,
          style: StitchType.caption.copyWith(color: c.amber),
        ),
      );
    }

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: StitchType.name.copyWith(color: c.ink)),
        const SizedBox(height: 4),
        Text(meta, style: StitchType.body.copyWith(color: c.muted)),
        const SizedBox(height: 6),
        Semantics(
          key: ValueKey('history-time-${entry.id.sortKey}'),
          label: t.calendarEntryState(
            statusLabel,
            entry.dateOnly
                ? t.historyDateZone(
                    formatter.date(instant, full: true),
                    entry.planZone ?? instant.zoneId,
                  )
                : t.historyRelativeExact(relative, exact),
          ),
          excludeSemantics: true,
          child: VitalBadge(
            entry.status == TimelineEntryStatus.recorded
                ? timeText
                : t.calendarEntryState(statusLabel, timeText),
            tone: tone,
            compact: true,
          ),
        ),
        ...details,
      ],
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: StitchSurface(
        padding: EdgeInsets.zero,
        child: Semantics(
          key: ValueKey('history-open-${entry.id.sortKey}'),
          label: t.screenHistoryViewEntry(title),
          child: StitchButton(
            quiet: true,
            onPressed: onInspect,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                StitchIcon(icon, size: 44),
                const SizedBox(width: 12),
                Expanded(child: content),
              ],
            ),
          ),
        ),
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

class HistoryCalendarSection extends StatelessWidget {
  const HistoryCalendarSection({
    super.key,
    required this.query,
    required this.month,
    required this.selected,
    required this.onMonth,
    required this.onSelect,
    this.tools,
  });
  final TimelineQuery query;
  final CivilDate month;
  final CivilDate? selected;
  final ValueChanged<CivilDate> onMonth, onSelect;
  final Widget? tools;
  @override
  Widget build(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (tools != null)
          Align(alignment: AlignmentDirectional.centerEnd, child: tools!),
        SizedBox(
          height: (260 + 6 * 48) * scale,
          child: VitalPager(
            index: (month.year - 1) * 12 + month.month - 1,
            itemCount: 9999 * 12,
            duration: VitalMotion.calendar,
            retainPages: false,
            onChanged: (index) =>
                onMonth(CivilDate(index ~/ 12 + 1, index % 12 + 1, 1)),
            itemBuilder: (_, index) => _HistoryMonthPage(
              query: query,
              month: CivilDate(index ~/ 12 + 1, index % 12 + 1, 1),
              selected: selected,
              onMonth: onMonth,
              onSelect: onSelect,
              tools: null,
            ),
          ),
        ),
      ],
    );
  }
}

class _HistoryMonthPage extends ConsumerWidget {
  const _HistoryMonthPage({
    required this.query,
    required this.month,
    required this.selected,
    required this.onMonth,
    required this.onSelect,
    this.tools,
  });
  final Widget? tools;
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
    return StitchSurface(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 20),
      child: Column(
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
            tools: tools,
            available:
                !result.hasError && result.hasValue && result.value != null,
            unavailableLabel: result.hasError
                ? t.historyLoadFailed
                : t.historyMonthLoading,
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
        ],
      ),
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
