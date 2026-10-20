import '../supporting/supporting_pages.dart';
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
  bool calendar = false,
      filtersOpen = false,
      initialised = false,
      peopleOpen = false;
  String? dateError;
  DateTime? movedAt;
  String? configuredIdentity;
  FeedScope? localScope;
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
    localScope = null;
    dateError = null;
    movedAt = null;
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
    if (latest != null && latest.occurredAt != entry.occurredAt) {
      setState(() => movedAt = latest.occurredAt);
    }
    // The live first page is reattached; older windows stay anchored until Refresh.
    controller.visible(true);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context),
        zone = ref.watch(displayZoneProvider),
        preferences = ref.watch(displayPreferencesProvider),
        scopeValue = ref.watch(browsingScopeProvider),
        people = ref.watch(profilesProvider),
        state = ref.watch(historyControllerProvider(widget.location));
    if (!scopeValue.hasValue || !people.hasValue) {
      return PageContent(children: [Text(t.loadingRecords)]);
    }
    final requested = seed['scope'];
    // History always has one adult; the combined management view stays in Today.
    final candidate =
        localScope?.personId ??
        (requested != null && requested != 'everyone'
            ? requested
            : scopeValue.requireValue.personId);
    final personId = people.requireValue.any((p) => p.id == candidate)
        ? candidate!
        : meId;
    final scope = FeedScope.person(personId);
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
    final owner = ownerLabel(ref, t, personId);
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
    return ListView(
      controller: scroll,
      padding: const EdgeInsets.all(20),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: VitalLayout.contentWidth,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Heading(t.history),
                Text(t.shownInZone(display.resolveZone(zone).zoneId)),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    MergeSemantics(
                      child: Semantics(
                        key: const ValueKey('history-person-toggle'),
                        expanded: peopleOpen,
                        child: VitalButton.secondary(
                          multiline: true,
                          trailing: const Icon(LucideIcons.chevronDown),
                          onPressed: () =>
                              setState(() => peopleOpen = !peopleOpen),
                          child: Text(owner),
                        ),
                      ),
                    ),
                    MergeSemantics(
                      child: Semantics(
                        key: const ValueKey('history-filters-toggle'),
                        expanded: filtersOpen,
                        child: VitalButton.secondary(
                          onPressed: () =>
                              setState(() => filtersOpen = !filtersOpen),
                          child: Text(t.historyFilters),
                        ),
                      ),
                    ),
                    VitalButton.secondary(
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
                      child: Text(t.chartsTitle),
                    ),
                    VitalButton.secondary(
                      onPressed: () => context.push(
                        supportingLocation(
                          personId,
                          item: seed['item'],
                          back: viewLocation(personId),
                        ),
                      ),
                      child: Text(t.supportingTitle),
                    ),
                    VitalButton.secondary(
                      onPressed: () {
                        final start = parseDate(from.text);
                        final end = parseDate(through.text);
                        context.push(
                          Uri(
                            path: '/reports',
                            queryParameters: {
                              'person': personId,
                              'from': (start ?? CivilDate(today.year, 1, 1))
                                  .toString(),
                              'before': (end ?? today).addDays(1).toString(),
                              'return': viewLocation(personId),
                            },
                          ).toString(),
                        );
                      },
                      child: Text(t.reportsTitle),
                    ),
                  ],
                ),
                if (peopleOpen)
                  VitalSurface(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final person in people.requireValue)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: VitalButton.secondary(
                              multiline: true,
                              onPressed: () => setState(() {
                                localScope = FeedScope.person(person.id);
                                peopleOpen = false;
                              }),
                              child: Text(
                                personLabel(t, people.requireValue, person.id),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                const SizedBox(height: 16),
                VitalSegments<bool>(
                  values: const [false, true],
                  selected: calendar,
                  label: (value) =>
                      value ? t.historyCalendar : t.historyTimeline,
                  onChanged: (value) => setState(() {
                    calendar = value;
                    if (calendar && selected == null) {
                      selected = display
                          .instant(DateTime.now().toUtc(), zone)
                          .civilDate;
                      from.text = selected.toString();
                      through.text = selected.toString();
                      appliedFrom = display.dayBounds(selected!, zone).start;
                      appliedBefore = display
                          .dayBounds(selected!, zone)
                          .endExclusive;
                    }
                  }),
                ),
                if (filtersOpen) ...[
                  Heading(t.historyFilters),
                  VitalSegments<TimelineStatus>(
                    key: const ValueKey('history-status'),
                    values: TimelineStatus.values,
                    selected: status,
                    label: (value) => switch (value) {
                      TimelineStatus.all => t.statusAll,
                      TimelineStatus.recorded => t.statusRecorded,
                      TimelineStatus.skipped => t.statusSkipped,
                      TimelineStatus.voided => t.statusVoided,
                    },
                    onChanged: (value) => setState(() => status = value),
                  ),
                  LabelledInput(
                    label: t.historyFrom,
                    controller: from,
                    error: dateError,
                  ),
                  LabelledInput(label: t.historyThrough, controller: through),
                  Text(t.historyDateHelp),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      VitalButton.secondary(
                        onPressed: () {
                          final a = parseDate(from.text),
                              b = parseDate(through.text);
                          setState(() {
                            dateError =
                                (from.text.isNotEmpty && a == null) ||
                                    (through.text.isNotEmpty && b == null) ||
                                    (a != null &&
                                        b != null &&
                                        a.compareTo(b) > 0)
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
                  HistoryFilterChoices(
                    scope: scope,
                    kind: 'type',
                    selected: types,
                    labels: labels,
                    onChanged: (values) => setState(() => types = values),
                  ),
                  HistoryFilterChoices(
                    scope: scope,
                    kind: 'event',
                    selected: events,
                    labels: labels,
                    onChanged: (values) => setState(() => events = values),
                  ),
                ],
                if (!filtersOpen &&
                    (status != TimelineStatus.all ||
                        types.isNotEmpty ||
                        events.isNotEmpty ||
                        appliedFrom != null ||
                        appliedBefore != null))
                  VitalSurface(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(t.historyFilters),
                        if (status != TimelineStatus.all)
                          Text(switch (status) {
                            TimelineStatus.recorded => t.statusRecorded,
                            TimelineStatus.skipped => t.statusSkipped,
                            TimelineStatus.voided => t.statusVoided,
                            TimelineStatus.all => t.statusAll,
                          }),
                        if (types.isNotEmpty)
                          Text(t.historySelectedTypes(types.length)),
                        if (events.isNotEmpty)
                          Text(t.historySelectedEvents(events.length)),
                        if (appliedFrom != null || appliedBefore != null)
                          Text(
                            t.historyDateFilter(
                              from.text.isEmpty ? t.historyAnyDate : from.text,
                              through.text.isEmpty
                                  ? t.historyAnyDate
                                  : through.text,
                            ),
                          ),
                      ],
                    ),
                  ),
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
                    onSelect: (date) => setState(() {
                      selected = date;
                      from.text = date.toString();
                      through.text = date.toString();
                      appliedFrom = display.dayBounds(date, zone).start;
                      appliedBefore = display
                          .dayBounds(date, zone)
                          .endExclusive;
                    }),
                  ),
                if (state.stale) ...[
                  Semantics(liveRegion: true, child: Text(t.historyNewEntries)),
                  VitalButton.secondary(
                    onPressed: controller.refresh,
                    child: Text(t.refresh),
                  ),
                ],
                if (state.refreshed || (!state.loading && anchor != null))
                  Semantics(liveRegion: true, child: Text(t.historyRefreshed)),
                if (effectiveMovedAt != null)
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      t.historyMoved(
                        formatter.format(
                          display.instant(effectiveMovedAt, zone),
                        ),
                      ),
                    ),
                  ),
                if (state.loading) Text(t.loadingRecords),
                if (state.error != null) ...[
                  Text(
                    state.error is TimelineQueryException
                        ? t.historyRangeTooBroadBody
                        : t.historyLoadFailed,
                  ),
                  VitalButton.secondary(
                    onPressed: controller.refresh,
                    child: Text(t.retry),
                  ),
                ],
                if (!state.loading &&
                    state.error == null &&
                    state.entries.isEmpty) ...[
                  Heading(t.historyNoEntries),
                  Text(t.historyNoEntriesBody),
                  Heading(t.historyNoCapturedPlan),
                  Text(t.historyNoCapturedPlanBody),
                ],
                if (selected != null && calendar)
                  Heading(
                    MaterialLocalizations.of(context)
                        .formatFullDate(selected!.calendarValue),
                  ),
                for (final entry in state.entries)
                  HistoryEntryCard(
                    key: entry.id.sortKey == anchor
                        ? _anchorKey
                        : ValueKey(entry.id.sortKey),
                    entry: entry,
                    formatter: formatter,
                    zone: zone,
                    onInspect: () => inspect(entry),
                  ),
                if (!state.loading &&
                    state.error == null &&
                    state.entries.isNotEmpty)
                  Text(t.historyShowing(state.entries.length)),
                if (state.olderLoading) Text(t.loadingRecords),
                if (state.next != null)
                  VitalButton.secondary(
                    onPressed: state.olderLoading ? null : controller.older,
                    child: Text(t.more),
                  ),
                if (state.pages >= HistoryController.maxWindowPages)
                  Text(t.historyWindow),
              ],
            ),
          ),
        ),
      ],
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
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context),
        instant = DisplayTime().instant(
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
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: VitalSurface(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(t.profileOwner(ownerLabel(ref, t, entry.personId))),
            Text(switch (entry.status) {
              TimelineEntryStatus.recorded => t.statusRecorded,
              TimelineEntryStatus.skipped => t.statusSkipped,
              TimelineEntryStatus.voided => t.statusVoided,
            }),
            if (entry is SkippedTimelineEntry) ...[
              Text(
                (entry as SkippedTimelineEntry).context.itemName ??
                    t.historyInspection,
              ),
              Text(
                t.historyPlannedAmount(
                  (entry as SkippedTimelineEntry).amount.enteredText,
                  (entry as SkippedTimelineEntry).amount.unit,
                ),
              ),
              Text(
                t.historyPlannedDate(
                  (entry as SkippedTimelineEntry).savedDate.toString(),
                ),
              ),
              Text(t.plannedInZone(entry.planZone!)),
              if (entry.dateOnly) Text(t.dateOnly),
              if ((entry as SkippedTimelineEntry).timeNeedsReview)
                Text(t.timeNeedsReview),
              Text(t.historySkippedHelp),
            ] else ...[
              if (entry is CombinedTimelineEntry) Text(t.historyGroupContext),
              for (final component in switch (entry) {
                RecordTimelineEntry() => [
                  CombinedTimelineComponent(
                    position: 0,
                    record: (entry as RecordTimelineEntry).record,
                  ),
                ],
                CombinedTimelineEntry() =>
                  (entry as CombinedTimelineEntry).components,
                _ => <CombinedTimelineComponent>[],
              }) ...[
                Text(component.record.name),
                Text(
                  t.ownerAmount(
                    ownerLabel(ref, t, entry.personId),
                    stockRecordAmountNumber(t, component.record),
                    component.record.actualUnit,
                  ),
                ),
                if (component.matched) Text(t.historyMatched),
              ],
            ],
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
                children: [Text(relative), if (!entry.dateOnly) Text(exact)],
              ),
            ),
            VitalButton.secondary(onPressed: onInspect, child: Text(t.view)),
          ],
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
