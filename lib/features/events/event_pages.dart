import '../supporting/supporting_pages.dart';
import '../../app/display_preferences.dart';
import '../../ui/vital_ui.dart';

import 'dart:convert';
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../app/storage.dart';
import '../../app/settings_toggle_row.dart';
import '../../app/app_lock.dart';
import '../../data/record_store.dart';
import '../../domain/scheduling/iana_clock.dart';
import '../../l10n/app_localizations.dart';
import '../../ui/stitch_ui.dart';
import '../plans/today_hero.dart' show todayNowProvider;
import '../profiles/profile_pages.dart';
import '../recording/record_pages.dart';
import 'event_summary_widgets.dart';

export '../../domain/events/event_collection.dart' show cycleTiming;

typedef EventWriter = Future<void> Function(
  SaveEventCommand command,
  EventMembershipReview review,
);
final eventWriterProvider = Provider<EventWriter>(
  (ref) => (command, review) async {
    await (await ref.read(recordStoreProvider.future))
        .saveEvent(command, membershipReview: review);
  },
);

final eventsProvider = StreamProvider.autoDispose<List<EventRecord>>(
  retry: (_, _) => null,
  (ref) async* {
    yield* (await ref.watch(recordStoreProvider.future)).watchEvents();
  },
);
final eventLookupProvider = StreamProvider.autoDispose
    .family<EventRecord?, String>(retry: (_, _) => null, (ref, id) async* {
      yield* (await ref.watch(recordStoreProvider.future)).watchEventById(id);
    });
final eventPageProvider = StreamProvider.autoDispose
    .family<List<EventRecord>, ({String? personId, int offset})>(
      retry: (_, _) => null,
      (ref, q) async* {
        yield* (await ref.watch(recordStoreProvider.future))
            .watchEvents(personId: q.personId, limit: 51, offset: q.offset);
      },
    );

/// Whole-collection Events counts and one filtered page under the same instant.
/// Locked reads never emit prior records; the page treats a reload as loading
/// rather than presenting the previous page as current.
typedef EventCollectionQuery = ({
  DateTime asOf,
  EventCollectionFilter filter,
  int offset,
});
final eventCollectionProvider = StreamProvider.autoDispose
    .family<EventCollectionSnapshot, EventCollectionQuery>(
      retry: (_, _) => null,
      (ref, query) async* {
        if (ref.watch(appLockProvider.select((state) => state.locked))) {
          return;
        }
        yield* (await ref.watch(recordStoreProvider.future))
            .watchEventCollection(
              filter: query.filter,
              now: query.asOf,
              offset: query.offset,
            );
      },
    );
final eventActualsProvider = FutureProvider.autoDispose
    .family<List<UseRecord>, ({String ids, int offset})>(
      retry: (_, _) => null,
      (ref, q) async {
        // Event edits and actual corrections invalidate the captured selection.
        ref.watch(eventsProvider);
        ref.watch(recordsProvider);
        return (await ref.watch(recordStoreProvider.future))
            .eventActuals(q.ids.split(','), limit: 51, offset: q.offset);
      },
    );
final usePeriodsProvider = StreamProvider.autoDispose
    .family<List<RecordedUsePeriod>, ({String personId, String itemId})>(
      retry: (_, _) => null,
      (ref, q) async* {
        yield* (await ref.watch(recordStoreProvider.future))
            .watchUsePeriods(personId: q.personId, itemId: q.itemId);
      },
    );

String eventDateLabel(
  AppLocalizations t,
  EventDate? date, {
  bool open = false,
}) => date == null
    ? (open ? t.eventOpen : t.eventNotRecorded)
    : date.precision == EventDatePrecision.unknown
    ? t.useUnknown
    : date.value!;

String eventHumanReference(String id, Iterable<String> peerIds) {
  var length = id.length < 6 ? id.length : 6;
  while (length < id.length &&
      peerIds.any(
        (other) =>
            other != id &&
            other.toUpperCase().startsWith(
              id.substring(0, length).toUpperCase(),
            ),
      )) {
    length++;
  }
  return id.substring(0, length).toUpperCase();
}

String eventItemLabel(
  AppLocalizations t,
  SubstanceItem item, {
  Iterable<String> peerIds = const [],
}) => t.eventItemIdentity(
  item.name,
  t.itemDetails(item.form, item.type, item.unit),
  eventHumanReference(item.id, peerIds),
);

String eventMembershipLabel(
  BuildContext context,
  WidgetRef ref,
  DateTime from,
  DateTime? until,
  String zone,
) {
  final t = AppLocalizations.of(context);
  String boundary(DateTime value) {
    // Preserve the existing review state for unsupported membership boundaries.
    IanaClock().dateAt(value, zone);
    return displayStamp(context, ref, value, zoneId: zone);
  }

  try {
    IanaClock().validateZone(zone);
    return t.eventMemberRange(
      boundary(from),
      until == null ? t.eventOpen : boundary(until),
      zone,
    );
  } catch (_) {
    return t.eventBoundaryReview;
  }
}

String? eventMembershipEntryLabel(
  BuildContext context,
  WidgetRef ref,
  MembershipFields fields,
  String zone,
) {
  try {
    return eventMembershipLabel(
      context,
      ref,
      parseMembershipInstant(fields.from.text),
      fields.until.text.trim().isEmpty
          ? null
          : parseMembershipInstant(fields.until.text),
      zone,
    );
  } catch (_) {
    return null;
  }
}

/// Text parsing never rewrites the raw draft. Exact times require a supplied zone.
EventDate? parseEventDate(
  String raw, {
  bool partial = false,
  bool required = false,
}) {
  final v = raw.trim();
  if (v.isEmpty) {
    if (required) throw const FormatException('date_required');
    return null;
  }
  if (partial && v.toLowerCase() == 'unknown') return EventDate.unknown();
  if (partial && RegExp(r'^\d{4}$').hasMatch(v)) {
    return EventDate(precision: EventDatePrecision.year, value: v);
  }
  if (partial && RegExp(r'^\d{4}-\d{2}$').hasMatch(v)) {
    return EventDate(precision: EventDatePrecision.month, value: v);
  }
  if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(v)) {
    return EventDate.day(CivilDate.parse(v));
  }
  if (!RegExp(r'(Z|[+-]\d{2}:\d{2})$').hasMatch(v)) {
    throw const FormatException('date_zone');
  }
  if (v.length < 16 || v[10] != 'T') throw const FormatException('exact_date');
  CivilDate.parse(v.substring(0, 10));
  final hours = int.parse(v.substring(11, 13)),
      minutes = int.parse(v.substring(14, 16));
  if (hours > 23 || minutes > 59) throw const FormatException('exact_time');
  final validated = EventDate(precision: EventDatePrecision.exact, value: v);
  return EventDate.exact(DateTime.parse(validated.value!).toUtc());
}

DateTime parseMembershipInstant(String raw) {
  final value = parseEventDate(raw, required: true)!;
  if (value.precision != EventDatePrecision.exact) {
    throw const FormatException('membership_instant');
  }
  return DateTime.parse(value.value!);
}

enum _EventFilter { all, active, upcoming, completed, review }

enum _EventPhase { active, upcoming, completed, review }

EventCollectionFilter _collectionFilter(_EventFilter filter) =>
    switch (filter) {
      _EventFilter.all => EventCollectionFilter.all,
      _EventFilter.active => EventCollectionFilter.active,
      _EventFilter.upcoming => EventCollectionFilter.upcoming,
      _EventFilter.completed => EventCollectionFilter.completed,
      _EventFilter.review => EventCollectionFilter.review,
    };

_EventPhase _eventPhase(EventRecord event, DateTime now) =>
    switch (eventCollectionPhase(event, now)) {
      EventCollectionPhase.active => _EventPhase.active,
      EventCollectionPhase.upcoming => _EventPhase.upcoming,
      EventCollectionPhase.completed => _EventPhase.completed,
      EventCollectionPhase.review => _EventPhase.review,
    };

bool _eventReviewDue(EventRecord event, DateTime now) {
  if (event.completed || event.endReviewDismissed) return false;
  try {
    final at = event.endReviewAt(IanaClock());
    return at != null && !now.isBefore(at);
  } catch (_) {
    return false;
  }
}

/// True once the saved end boundary has passed. Elapsed day counts are then
/// complete, so a card must not present a day beyond the inclusive total.
bool _eventRangeEnded(EventRecord event, DateTime now) {
  if (event.completed) return false;
  final endDate = event.actualEnd ?? event.plannedEnd;
  if (endDate == null) return false;
  try {
    final end = endDate.resolve(IanaClock(), event.zoneId, inclusiveEnd: true);
    return end != null && !now.isBefore(end);
  } catch (_) {
    return false;
  }
}

String _eventTypeLabel(AppLocalizations t, EventRecord event) =>
    event.eventType == 'cycle'
    ? t.eventCycle
    : event.eventType == 'prescription'
    ? t.eventPrescription
    : event.eventType;

/// Recorded precision is preserved. Day and month values are formatted for
/// reading; exact boundaries keep their saved zone and offset.
String _eventDateText(
  BuildContext context,
  WidgetRef ref,
  AppLocalizations t,
  EventDate? date,
  String zone, {
  bool open = false,
}) {
  if (date == null) return open ? t.eventOpen : t.eventNotRecorded;
  switch (date.precision) {
    case EventDatePrecision.unknown:
      return t.useUnknown;
    case EventDatePrecision.year:
      return date.value!;
    case EventDatePrecision.month:
      final parts = date.value!.split('-');
      return DateFormat.yMMM(Localizations.localeOf(context).toLanguageTag())
          .format(DateTime(int.parse(parts[0]), int.parse(parts[1])));
    case EventDatePrecision.day:
      final value = CivilDate.parse(date.value!);
      return DateFormat(
        'd MMM yyyy',
        Localizations.localeOf(context).toLanguageTag(),
      ).format(DateTime(value.year, value.month, value.day));
    case EventDatePrecision.exact:
      return displayStamp(
        context,
        ref,
        DateTime.parse(date.value!),
        zoneId: zone,
      );
  }
}

String _eventRangeText(
  BuildContext context,
  WidgetRef ref,
  AppLocalizations t,
  EventRecord event,
) {
  final start = _eventDateText(
    context,
    ref,
    t,
    event.actualStart ?? event.plannedStart,
    event.zoneId,
  );
  final end = _eventDateText(
    context,
    ref,
    t,
    event.actualEnd ?? event.plannedEnd,
    event.zoneId,
    open: true,
  );
  final hasStart = (event.actualStart ?? event.plannedStart) != null;
  final hasEnd = (event.actualEnd ?? event.plannedEnd) != null;
  if (!hasStart && !hasEnd) return t.screenEventsNoDates;
  if (!hasStart) return t.screenEventsEnds(end);
  if (!hasEnd) return t.screenEventsStarted(start);
  return t.screenEventsRange(start, end);
}

String _eventSpanText(
  BuildContext context,
  WidgetRef ref,
  AppLocalizations t,
  EventDate? start,
  EventDate? end,
  String zone,
) {
  if (start == null && end == null) return t.screenEventsNoDates;
  return t.screenEventsRange(
    _eventDateText(context, ref, t, start, zone),
    _eventDateText(context, ref, t, end, zone, open: true),
  );
}

String _eventMetaText(
  BuildContext context,
  WidgetRef ref,
  AppLocalizations t,
  EventRecord event,
  DateTime now,
) {
  final timing = cycleTiming(event, now);
  final ended = _eventRangeEnded(event, now);
  final parts = [_eventRangeText(context, ref, t, event)];
  if (event.completed) {
    parts.add(t.eventCompleted);
  } else if (timing.startsIn case final days?) {
    parts.add(t.cycleStartsIn(days));
  } else if (!ended && timing.elapsed != null && timing.remaining != null) {
    parts.add(
      t.screenEventsDayOf(
        timing.elapsed! + 1,
        timing.elapsed! + timing.remaining!,
      ),
    );
  } else if (timing.elapsed case final elapsed?) {
    parts.add(t.cycleElapsed(elapsed));
  }
  return parts.join(' · ');
}

class EventsPage extends ConsumerStatefulWidget {
  const EventsPage({super.key});
  @override
  ConsumerState<EventsPage> createState() => _EventsPageState();
}

class _EventsPageState extends ConsumerState<EventsPage> {
  final selected = <String>{};
  final _filterKeys = {
    for (final choice in _EventFilter.values) choice: GlobalKey(),
  };
  int offset = 0;
  _EventFilter filter = _EventFilter.all;
  Timer? _clockTimer;
  @override
  void initState() {
    super.initState();
    _clockTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    super.dispose();
  }

  /// Minute granularity keeps the query stable while status labels rerender.
  DateTime _collectionAsOf(DateTime now) {
    final utc = now.toUtc();
    return DateTime.utc(utc.year, utc.month, utc.day, utc.hour, utc.minute);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context), c = StitchColors(context);
    final now = ref.watch(todayNowProvider)();
    final query = (
      asOf: _collectionAsOf(now),
      filter: _collectionFilter(filter),
      offset: offset,
    );
    final result = ref.watch(eventCollectionProvider(query));
    final loaded = result.hasValue && !result.isLoading && !result.hasError
        ? result.requireValue
        : null;
    final counts = loaded?.counts ?? const EventCollectionCounts.empty();
    final picked = selected.toList();
    return StitchScrollBody(
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 16,
          runSpacing: 12,
          children: [
            Semantics(
              header: true,
              child: Text(t.events, style: StitchType.title),
            ),
            StitchButton(
              primary: true,
              icon: LucideIcons.plus,
              onPressed: () => context.push('/event-create'),
              child: Text(t.create),
            ),
          ],
        ),
        if (loaded != null && loaded.total > 0) ...[
          const SizedBox(height: 8),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: StitchBadge(
              [
                t.screenEventsActiveCount(loaded.counts.active),
                t.screenEventsUpcomingCount(loaded.counts.upcoming),
                t.screenEventsCompletedCount(loaded.counts.completed),
                if (loaded.counts.review > 0)
                  t.screenEventsReviewCount(loaded.counts.review),
              ].join(' · '),
              dot: true,
            ),
          ),
        ],
        const SizedBox(height: 12),
        Text(
          t.screenEventsDescription,
          style: StitchType.body.copyWith(color: c.muted),
        ),
        const SizedBox(height: 16),
        if (loaded != null && loaded.total > 0) ...[
          Semantics(
            container: true,
            label: t.screenEventsFilterLabel,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final choice in _EventFilter.values)
                    Padding(
                      key: _filterKeys[choice],
                      padding: const EdgeInsets.only(right: 8),
                      child: Semantics(
                        selected: filter == choice,
                        child: StitchButton(
                          compact: true,
                          onPressed: () {
                            setState(() {
                              filter = choice;
                              offset = 0;
                            });
                            // Keep the chosen status visible in the scrolled
                            // chip row, so its selected state stays apparent.
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              final chip = _filterKeys[choice]?.currentContext;
                              if (chip != null) {
                                Scrollable.ensureVisible(chip, alignment: 0.5);
                              }
                            });
                          },
                          primary: filter == choice,
                          child: Text(_filterLabel(t, choice, counts)),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            t.featureEventCollectionCountsHelp,
            style: StitchType.caption.copyWith(color: c.muted),
          ),
          const SizedBox(height: 16),
        ],
        if (result.hasError)
          LoadFailure(
            onRetry: () => ref.invalidate(eventCollectionProvider(query)),
          )
        else if (loaded == null)
          StitchSurface(
            radius: VitalLayout.sectionRadius,
            child: Semantics(
              liveRegion: true,
              child: Text(t.loadingRecords, style: StitchType.body),
            ),
          )
        else if (loaded.total == 0)
          VitalEmptyState(
            title: t.events,
            description: t.eventEmpty,
            icon: LucideIcons.calendarRange,
          )
        else if (loaded.events.isEmpty)
          VitalEmptyState(
            title: t.featureEventCollectionNoMatches,
            description: t.featureEventCollectionNoMatchesHelp,
            icon: LucideIcons.calendarRange,
            action: VitalButton.secondary(
              onPressed: () => setState(() {
                filter = _EventFilter.all;
                offset = 0;
              }),
              child: Text(t.clear),
            ),
          )
        else
          for (final event in loaded.events)
            Padding(
              key: ValueKey(event.id),
              padding: const EdgeInsets.only(bottom: 12),
              child: _EventCard(
                key: ValueKey('screen-events-card-${event.id}'),
                event: event,
                now: loaded.asOf,
                selected: selected.contains(event.id),
                onToggleSelected: () => setState(() {
                  if (!selected.add(event.id)) selected.remove(event.id);
                }),
              ),
            ),
        if (loaded != null && loaded.filteredTotal > loaded.pageSize) ...[
          const SizedBox(height: 6),
          Text(
            t.featureEventCollectionPageRange(
              loaded.offset + 1,
              loaded.offset + loaded.events.length,
              loaded.filteredTotal,
            ),
            style: StitchType.caption.copyWith(color: c.muted),
          ),
        ],
        if (loaded != null && (loaded.hasPrevious || loaded.hasNext))
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              if (loaded.hasPrevious)
                VitalButton.secondary(
                  onPressed: () =>
                      setState(() => offset = loaded.offset - loaded.pageSize),
                  child: Text(t.previous),
                ),
              if (loaded.hasNext)
                VitalButton.secondary(
                  onPressed: () =>
                      setState(() => offset = loaded.offset + loaded.pageSize),
                  child: Text(t.next),
                ),
            ],
          ),
        if (picked.isNotEmpty) ...[
          const SizedBox(height: 24),
          Semantics(
            header: true,
            child: Text(t.eventCombined, style: StitchType.heading),
          ),
          const SizedBox(height: 12),
          VitalButton.secondary(
            onPressed: () => setState(selected.clear),
            child: Text(t.eventClear),
          ),
          const SizedBox(height: 12),
          EventActualList(ids: (picked..sort()).join(',')),
        ],
        if (loaded != null && loaded.total > 0) ...[
          const SizedBox(height: 24),
          const _EventContextNotice(),
        ],
      ],
    );
  }

  String _filterLabel(
    AppLocalizations t,
    _EventFilter choice,
    EventCollectionCounts counts,
  ) {
    final (label, filter) = switch (choice) {
      _EventFilter.all => (t.screenEventsAll, null),
      _EventFilter.active => (
        t.screenEventsActive,
        EventCollectionFilter.active,
      ),
      _EventFilter.upcoming => (
        t.screenEventsUpcoming,
        EventCollectionFilter.upcoming,
      ),
      _EventFilter.completed => (
        t.eventCompleted,
        EventCollectionFilter.completed,
      ),
      _EventFilter.review => (t.review, EventCollectionFilter.review),
    };
    // "All" stays uncounted so it remains the plain reset target.
    return filter == null
        ? label
        : t.stitchFilterCount(label, counts.count(filter));
  }
}

class _EventCard extends ConsumerStatefulWidget {
  const _EventCard({
    super.key,
    required this.event,
    required this.now,
    required this.selected,
    required this.onToggleSelected,
  });
  final EventRecord event;
  final DateTime now;
  final bool selected;
  final VoidCallback onToggleSelected;
  @override
  ConsumerState<_EventCard> createState() => _EventCardState();
}

class _EventCardState extends ConsumerState<_EventCard> {
  bool expanded = false;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context), c = StitchColors(context);
    final event = widget.event;
    final phase = _eventPhase(event, widget.now);
    final reviewDue = _eventReviewDue(event, widget.now);
    final timing = cycleTiming(event, widget.now);
    final completed = phase == _EventPhase.completed;
    final selected = widget.selected;
    final hasDates =
        event.plannedStart != null ||
        event.plannedEnd != null ||
        event.actualStart != null ||
        event.actualEnd != null;
    final datesReview =
        !completed &&
        hasDates &&
        timing.startsIn == null &&
        timing.elapsed == null &&
        timing.remaining == null;
    final primary = switch (phase) {
      _ when reviewDue => (
        label: t.review,
        route: '/event/${event.id}/review',
        semantics: t.screenEventsReviewFor(event.name),
        details: false,
      ),
      _EventPhase.completed => (
        label: t.eventRevisions,
        route: '/event/${event.id}/revisions',
        semantics: t.screenEventsRevisionsFor(event.name),
        details: false,
      ),
      _EventPhase.upcoming => (
        label: t.stitchConfigure,
        route: '/event/${event.id}/edit',
        semantics: t.screenEventsConfigureFor(event.name),
        details: false,
      ),
      _EventPhase.active || _EventPhase.review => (
        label: t.details,
        route: '/event/${event.id}',
        semantics: t.screenEventsDetailsFor(event.name),
        details: true,
      ),
    };
    final progress =
        !completed &&
        !_eventRangeEnded(event, widget.now) &&
        timing.startsIn == null &&
        timing.elapsed != null &&
        timing.remaining != null &&
        (timing.elapsed! + timing.remaining!) > 0;
    final total = progress ? timing.elapsed! + timing.remaining! : 0;
    final percent = progress
        ? ((timing.elapsed! / total) * 100).round().clamp(0, 100)
        : 0;
    return StitchSurface(
      radius: VitalLayout.surfaceRadius,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        StitchBadge(
                          switch (phase) {
                            _EventPhase.active => t.screenEventsActive,
                            _EventPhase.upcoming => t.screenEventsUpcoming,
                            _EventPhase.completed => t.eventCompleted,
                            _EventPhase.review => t.screenEventsDatesReview,
                          },
                          dot:
                              phase == _EventPhase.active ||
                              phase == _EventPhase.upcoming,
                          warning: phase == _EventPhase.review,
                        ),
                        if (reviewDue)
                          StitchBadge(t.screenEventsReviewDue, warning: true),
                        if (datesReview && phase != _EventPhase.review)
                          StitchBadge(t.screenEventsDatesReview, warning: true),
                        Text(
                          _eventTypeLabel(t, event),
                          style: StitchType.small.copyWith(color: c.muted),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Semantics(
                label: t.screenEventsMoreFor(event.name),
                button: true,
                expanded: expanded,
                child: StitchButton(
                  key: ValueKey('screen-events-more-${event.id}'),
                  quiet: true,
                  compact: true,
                  icon: expanded ? LucideIcons.chevronUp : LucideIcons.ellipsis,
                  onPressed: () => setState(() => expanded = !expanded),
                  child: const SizedBox.shrink(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(event.name, style: StitchType.name.copyWith(color: c.ink)),
          const SizedBox(height: 4),
          Text(
            _eventMetaText(context, ref, t, event, widget.now),
            style: StitchType.caption.copyWith(color: c.muted),
          ),
          const SizedBox(height: 12),
          EventSummaryFacts(event: event, compact: true),
          if (progress) ...[
            const SizedBox(height: 12),
            MergeSemantics(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      Text(
                        t.screenEventsHorizon,
                        style: StitchType.small.copyWith(color: c.muted),
                      ),
                      Text(
                        t.screenEventsPercentElapsed(percent),
                        style: StitchType.small.copyWith(
                          color: c.accent,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ExcludeSemantics(
                    child: LinearProgressIndicator(
                      value: percent / 100,
                      theme: LinearProgressIndicatorTheme(
                        color: c.accent,
                        backgroundColor: c.dark ? c.canvas : c.inset,
                        minHeight: 8,
                        borderRadius: BorderRadius.circular(
                          VitalLayout.pillRadius,
                        ),
                        disableAnimation: MediaQuery.disableAnimationsOf(
                          context,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (event.memberships.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              phase == _EventPhase.upcoming
                  ? t.screenEventsPlannedItems
                  : t.screenEventsLinkedItems,
              style: StitchType.small.copyWith(
                color: c.muted,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final membership in event.memberships)
                  _EventItemChip(itemId: membership.itemId),
              ],
            ),
          ],
          if (completed) ...[
            const SizedBox(height: 12),
            StitchSurface(
              inset: true,
              radius: VitalLayout.sectionRadius,
              padding: const EdgeInsets.all(12),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  ExcludeSemantics(
                    child: Icon(
                      LucideIcons.circleCheck,
                      size: 20,
                      color: c.accent,
                    ),
                  ),
                  Text(
                    t.screenEventsCompletedNote,
                    style: StitchType.small.copyWith(color: c.muted),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            runSpacing: 8,
            children: [
              Semantics(
                selected: selected,
                label: selected
                    ? t.screenEventsSelectedFor(event.name)
                    : t.screenEventsSelectFor(event.name),
                child: StitchButton(
                  key: ValueKey('screen-events-select-${event.id}'),
                  icon: selected ? LucideIcons.check : null,
                  onPressed: widget.onToggleSelected,
                  child: Text(selected ? t.eventSelected : t.eventSelect),
                ),
              ),
              Semantics(
                label: primary.semantics,
                button: true,
                child: StitchButton(
                  key: ValueKey('screen-events-primary-${event.id}'),
                  primary: primary.details || reviewDue,
                  onPressed: () => context.push(primary.route),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(primary.label),
                      if (primary.details) ...[
                        const SizedBox(width: 6),
                        ExcludeSemantics(
                          child: Icon(
                            LucideIcons.arrowRight,
                            size: 16,
                            color: c.accentInk,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
          if (expanded) ...[
            const SizedBox(height: 8),
            StitchSurface(
              inset: true,
              radius: VitalLayout.sectionRadius,
              padding: const EdgeInsets.all(12),
              child: Wrap(
                spacing: 4,
                runSpacing: 4,
                children: [
                  if (!primary.details)
                    _EventMoreCommand(
                      label: t.details,
                      semantics: t.screenEventsDetailsFor(event.name),
                      onPressed: () => context.push('/event/${event.id}'),
                    ),
                  if (primary.label != t.eventRevisions)
                    _EventMoreCommand(
                      label: t.eventRevisions,
                      semantics: t.screenEventsRevisionsFor(event.name),
                      onPressed: () =>
                          context.push('/event/${event.id}/revisions'),
                    ),
                  _EventMoreCommand(
                    label: t.screenEventsNote,
                    semantics: t.screenEventsNoteFor(event.name),
                    onPressed: () =>
                        context.push('/event/${event.id}/edit?notes=true'),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _EventMoreCommand extends StatelessWidget {
  const _EventMoreCommand({
    required this.label,
    required this.semantics,
    required this.onPressed,
  });
  final String label, semantics;
  final VoidCallback onPressed;
  @override
  Widget build(BuildContext context) => Semantics(
    label: semantics,
    button: true,
    child: StitchButton(
      quiet: true,
      compact: true,
      onPressed: onPressed,
      child: Text(label),
    ),
  );
}

class _EventItemChip extends ConsumerWidget {
  const _EventItemChip({required this.itemId});
  final String itemId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final result = ref.watch(itemLookupProvider(itemId));
    return VitalBadge(
      result.value?.name ??
          (result.hasError || result.hasValue
              ? t.screenEventsItemUnavailable
              : t.loadingRecords),
      compact: true,
    );
  }
}

class _EventContextNotice extends StatelessWidget {
  const _EventContextNotice();
  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return StitchSurface(
      radius: VitalLayout.sectionRadius,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          StitchIcon(LucideIcons.info, size: 40),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t.screenEventsContext, style: StitchType.name),
                const SizedBox(height: 4),
                Text(
                  t.eventHelp,
                  style: StitchType.caption.copyWith(
                    color: StitchColors(context).muted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class EventActualList extends ConsumerStatefulWidget {
  const EventActualList({super.key, required this.ids});
  final String ids;
  @override
  ConsumerState<EventActualList> createState() => _EventActualListState();
}

class _EventActualListState extends ConsumerState<EventActualList> {
  int pages = 1;
  @override
  void didUpdateWidget(EventActualList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.ids != widget.ids) pages = 1;
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final results = [
      for (var i = 0; i < pages; i++)
        ref.watch(eventActualsProvider((ids: widget.ids, offset: i * 50))),
    ];
    final rows = [for (final result in results) ...?result.value?.take(50)];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(t.eventHistoryHelp),
        if (results.any((r) => r.hasError))
          LoadFailure(
            onRetry: () {
              for (var i = 0; i < pages; i++) {
                ref.invalidate(
                  eventActualsProvider((ids: widget.ids, offset: i * 50)),
                );
              }
            },
          )
        else if (results.any((r) => !r.hasValue))
          Text(t.loadingRecords)
        else if (rows.isEmpty)
          Text(t.eventNoActuals),
        for (final record in rows)
          RecordCard(key: ValueKey(record.id), record: record),
        if ((results.last.value?.length ?? 0) > 50)
          VitalButton.secondary(
            onPressed: () => setState(() => pages++),
            child: Text(t.more),
          ),
      ],
    );
  }
}

class EventDetailPage extends ConsumerWidget {
  const EventDetailPage({super.key, required this.eventId});
  final String eventId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context),
        result = ref.watch(eventLookupProvider(eventId));
    if (result.hasError) {
      return EntryPage(
        children: [
          LoadFailure(
            onRetry: () => ref.invalidate(eventLookupProvider(eventId)),
          ),
        ],
      );
    }
    if (!result.hasValue) return EntryPage(children: [Text(t.loadingRecords)]);
    final event = result.requireValue;
    if (event == null) return EntryPage(children: [Text(t.draftUnavailable)]);
    final now = ref.watch(todayNowProvider)();
    final timing = cycleTiming(event, now);
    final phase = _eventPhase(event, now);
    final completed = phase == _EventPhase.completed;
    final reviewDue = _eventReviewDue(event, now);
    final c = StitchColors(context);
    final hasDates =
        event.plannedStart != null ||
        event.plannedEnd != null ||
        event.actualStart != null ||
        event.actualEnd != null;
    final timingUnavailable =
        hasDates &&
        !completed &&
        timing.startsIn == null &&
        timing.elapsed == null &&
        timing.remaining == null;
    return EntryPage(
      panelled: false,
      children: [
        Heading(t.events),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            StitchBadge(
              switch (phase) {
                _EventPhase.active => t.screenEventsActive,
                _EventPhase.upcoming => t.screenEventsUpcoming,
                _EventPhase.completed => t.eventCompleted,
                _EventPhase.review => t.screenEventsDatesReview,
              },
              dot: phase == _EventPhase.active || phase == _EventPhase.upcoming,
              warning: phase == _EventPhase.review,
            ),
            if (reviewDue) StitchBadge(t.screenEventsReviewDue, warning: true),
            if (timingUnavailable && phase != _EventPhase.review)
              StitchBadge(t.screenEventsDatesReview, warning: true),
            Text(
              _eventTypeLabel(t, event),
              style: StitchType.small.copyWith(color: c.muted),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Semantics(
          header: true,
          child: Text(event.name, style: VitalType.detailTitle),
        ),
        const SizedBox(height: 6),
        Text(
          _eventMetaText(context, ref, t, event, now),
          style: StitchType.body.copyWith(color: c.muted),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            Semantics(
              label: t.screenEventsEditFor(event.name),
              button: true,
              child: StitchButton(
                primary: true,
                onPressed: () => context.push('/event/${event.id}/edit'),
                child: Text(t.edit),
              ),
            ),
            Semantics(
              label: t.screenEventsRevisionsFor(event.name),
              button: true,
              child: StitchButton(
                onPressed: () => context.push('/event/${event.id}/revisions'),
                child: Text(t.eventRevisions),
              ),
            ),
            if (!completed)
              Semantics(
                label: t.screenEventsReviewFor(event.name),
                button: true,
                child: StitchButton(
                  onPressed: () => context.push('/event/${event.id}/review'),
                  child: Text(t.review),
                ),
              ),
            StitchButton(
              onPressed: () => context.push(
                supportingLocation(
                  event.personId,
                  event: event.id,
                  back: '/event/${event.id}',
                ),
              ),
              child: Text(t.supportingTitle),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Semantics(
          header: true,
          child: Text(t.screenEventsDates, style: StitchType.heading),
        ),
        const SizedBox(height: 12),
        StitchSurface(
          radius: VitalLayout.sectionRadius,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _EventFact(
                label: t.screenEventsPlanned,
                value: _eventSpanText(
                  context,
                  ref,
                  t,
                  event.plannedStart,
                  event.plannedEnd,
                  event.zoneId,
                ),
              ),
              if (event.actualStart != null || event.actualEnd != null) ...[
                const SizedBox(height: 12),
                _EventFact(
                  label: t.screenEventsActual,
                  value: _eventSpanText(
                    context,
                    ref,
                    t,
                    event.actualStart,
                    event.actualEnd,
                    event.zoneId,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              _EventFact(label: t.eventZone, value: event.zoneId),
              const SizedBox(height: 10),
              Text(
                t.eventInclusive,
                style: StitchType.caption.copyWith(color: c.muted),
              ),
              if (timing.startsIn case final days?) ...[
                const SizedBox(height: 10),
                _TimingRow(
                  icon: LucideIcons.calendarClock,
                  text: t.cycleStartsIn(days),
                ),
              ],
              if (timing.elapsed case final days?) ...[
                const SizedBox(height: 10),
                _TimingRow(
                  icon: LucideIcons.clock3,
                  text: t.cycleElapsed(days),
                ),
              ],
              if (timing.remaining case final days?) ...[
                const SizedBox(height: 10),
                _TimingRow(
                  icon: LucideIcons.clock3,
                  text: t.cycleRemaining(days),
                ),
              ],
              if (timingUnavailable) ...[
                const SizedBox(height: 10),
                Text(
                  t.eventBoundaryReview,
                  style: StitchType.caption.copyWith(color: c.amber),
                ),
              ],
              if (completed) ...[
                const SizedBox(height: 12),
                StitchBadge(t.eventCompleted, dot: false),
              ],
            ],
          ),
        ),
        const SizedBox(height: 20),
        VitalPanel(
          title: t.featureEventsTotals,
          children: [EventSummaryFacts(event: event)],
        ),
        if (event.notes.isNotEmpty) ...[
          const SizedBox(height: 12),
          EventNotes(notes: event.notes),
        ],
        const SizedBox(height: 20),
        Semantics(
          header: true,
          child: Text(t.eventMembers, style: StitchType.heading),
        ),
        const SizedBox(height: 12),
        if (event.memberships.isEmpty)
          Text(
            t.eventNoMembers,
            style: StitchType.body.copyWith(color: c.muted),
          ),
        for (final m in event.memberships)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: StitchSurface(
              inset: true,
              radius: VitalLayout.sectionRadius,
              padding: const EdgeInsets.all(12),
              child: MembershipIdentity(
                membership: m,
                zoneId: event.zoneId,
                peerIds: event.memberships.map((row) => row.itemId),
              ),
            ),
          ),
        const SizedBox(height: 12),
        Semantics(
          header: true,
          child: Text(t.history, style: StitchType.heading),
        ),
        const SizedBox(height: 12),
        EventActualList(ids: event.id),
      ],
    );
  }
}

class _EventFact extends StatelessWidget {
  const _EventFact({required this.label, required this.value});
  final String label, value;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: StitchType.small.copyWith(
          color: StitchColors(context).muted,
          fontWeight: FontWeight.w600,
        ),
      ),
      const SizedBox(height: 4),
      Text(value, style: StitchType.body),
    ],
  );
}

class _TimingRow extends StatelessWidget {
  const _TimingRow({required this.icon, required this.text});
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      ExcludeSemantics(
        child: Icon(icon, size: 16, color: StitchColors(context).accent),
      ),
      const SizedBox(width: 8),
      Expanded(child: Text(text, style: StitchType.body)),
    ],
  );
}

class MembershipIdentity extends ConsumerWidget {
  const MembershipIdentity({
    super.key,
    required this.membership,
    required this.zoneId,
    this.peerIds = const [],
  });
  final Iterable<String> peerIds;
  final String zoneId;
  final EventMembership membership;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context),
        item = ref.watch(itemLookupProvider(membership.itemId)).value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          item == null ? t.noItem : eventItemLabel(t, item, peerIds: peerIds),
        ),
        Text(
          eventMembershipLabel(
            context,
            ref,
            membership.effectiveFrom,
            membership.effectiveUntil,
            zoneId,
          ),
        ),
      ],
    );
  }
}

final class MembershipFields {
  MembershipFields({
    required this.id,
    required this.itemId,
    required this.revision,
    String from = '',
    String until = '',
  }) : from = TextEditingController(text: from),
       until = TextEditingController(text: until);
  final String id, itemId;
  final int revision;
  final TextEditingController from, until;
  Map<String, Object?> toJson() => {
    'id': id,
    'item': itemId,
    'revision': revision,
    'from': from.text,
    'until': until.text,
  };
  factory MembershipFields.fromJson(Map<String, Object?> json) =>
      MembershipFields(
        id: json['id']! as String,
        itemId: json['item']! as String,
        revision: json['revision']! as int,
        from: json['from']! as String,
        until: json['until']! as String,
      );
  void dispose() {
    from.dispose();
    until.dispose();
  }
}

class EventForm extends ConsumerStatefulWidget {
  const EventForm({super.key, this.eventId, this.initialDetails = false});
  final String? eventId;
  final bool initialDetails;
  @override
  ConsumerState<EventForm> createState() => _EventFormState();
}

class _EventFormState extends DurableFormState<EventForm> {
  final name = TextEditingController(),
      zone = TextEditingController(text: 'Europe/London');
  final notes = TextEditingController();
  final plannedStart = TextEditingController(),
      plannedEnd = TextEditingController();
  final actualStart = TextEditingController(),
      actualEnd = TextEditingController();
  final memberships = <MembershipFields>[];
  AdultProfile? owner;
  EventRecord? original;
  String id = newCommandId(), type = 'cycle';
  bool completed = false, initialised = false, detailsOpen = false;
  int itemOffset = 0;
  EventRecord? frozen;
  String? reviewedFingerprint, reviewGuard;
  List<UseRecord>? entering, leaving;
  bool restoringPreview = false;
  @override
  String get entryFallback =>
      widget.eventId == null ? '/events' : '/event/${widget.eventId}';
  @override
  DraftKind get entryKind => DraftKind.event;
  @override
  String? get entryPerson => owner?.id ?? meId;
  @override
  int? get entryPersonRevision => owner?.revision;
  @override
  String? get entryTarget => widget.eventId;
  @override
  int? get entryTargetRevision => original?.revision;
  @override
  Map<String, String> captureEntry() => {
    'id': id,
    'name': name.text,
    'notes': notes.text,
    'zone': zone.text,
    'type': type,
    'plannedStart': plannedStart.text,
    'plannedEnd': plannedEnd.text,
    'actualStart': actualStart.text,
    'actualEnd': actualEnd.text,
    'completed': '$completed',
    'memberships': jsonEncode(memberships.map((m) => m.toJson()).toList()),
    'frozen': frozen == null ? '' : jsonEncode(frozen!.toJson()),
    'reviewedFingerprint': reviewedFingerprint ?? '',
    'reviewGuard': reviewGuard ?? '',
  };
  @override
  void restoreEntry(Map<String, String> f) {
    id = f['id']!;
    name.text = f['name'] ?? '';
    if (f.containsKey('notes')) notes.text = f['notes']!;
    zone.text = f['zone'] ?? '';
    type = f['type'] ?? 'cycle';
    plannedStart.text = f['plannedStart'] ?? '';
    plannedEnd.text = f['plannedEnd'] ?? '';
    actualStart.text = f['actualStart'] ?? '';
    actualEnd.text = f['actualEnd'] ?? '';
    completed = f['completed'] == 'true';
    for (final m in memberships) {
      m.dispose();
    }
    memberships.clear();
    for (final m in jsonDecode(f['memberships'] ?? '[]') as List) {
      addMembership(
        MembershipFields.fromJson(Map<String, Object?>.from(m as Map)),
      );
    }
    if ((f['frozen'] ?? '').isNotEmpty) {
      frozen = EventRecord.fromJson(
        Map<String, Object?>.from(jsonDecode(f['frozen']!) as Map),
      );
    }
    reviewedFingerprint = f['reviewedFingerprint'];
    reviewGuard = f['reviewGuard'];
  }

  @override
  void initState() {
    super.initState();
    for (final c in [
      name,
      notes,
      zone,
      plannedStart,
      plannedEnd,
      actualStart,
      actualEnd,
    ]) {
      c.addListener(changed);
    }
  }

  void changed() {
    if (draftReady && !busy && !uncertain) {
      frozen = null;
      reviewedFingerprint = null;
      entering = null;
      leaving = null;
    }
    entryChanged();
    if (mounted && draftReady) setState(() {});
  }

  void addMembership(MembershipFields m) {
    memberships.add(m);
    m.from.addListener(changed);
    m.until.addListener(changed);
  }

  @override
  void dispose() {
    for (final c in [
      name,
      notes,
      zone,
      plannedStart,
      plannedEnd,
      actualStart,
      actualEnd,
    ]) {
      c.dispose();
    }
    for (final m in memberships) {
      m.dispose();
    }
    super.dispose();
  }

  EventRecord proposal() => EventRecord(
    id: id,
    personId: owner!.id,
    name: name.text.trim(),
    notes: notes.text,
    eventType: type,
    zoneId: zone.text.trim(),
    revision: (original?.revision ?? 0) + 1,
    plannedStart: parseEventDate(plannedStart.text),
    plannedEnd: parseEventDate(plannedEnd.text),
    actualStart: parseEventDate(actualStart.text),
    actualEnd: parseEventDate(actualEnd.text),
    completed: completed,
    endReviewDismissed: original?.endReviewDismissed ?? false,
    memberships: memberships.map(
      (m) => EventMembership(
        id: m.id,
        itemId: m.itemId,
        personId: owner!.id,
        effectiveFrom: parseMembershipInstant(m.from.text),
        effectiveUntil: m.until.text.trim().isEmpty
            ? null
            : parseMembershipInstant(m.until.text),
        revision:
            original?.memberships.any(
                  (old) =>
                      old.id == m.id &&
                      (old.effectiveFrom !=
                              parseMembershipInstant(m.from.text) ||
                          old.effectiveUntil !=
                              (m.until.text.trim().isEmpty
                                  ? null
                                  : parseMembershipInstant(m.until.text))),
                ) ==
                true
            ? m.revision + 1
            : m.revision,
      ),
    ),
  );
  SaveEventCommand command(EventRecord event, String operation) =>
      SaveEventCommand(
        commandId: operation,
        generation: capturedGeneration!,
        expectedRevision: capturedTargetRevision,
        expectedPersonRevision: capturedPersonRevision!,
        event: event,
      );
  Future<void> preview() async {
    final t = AppLocalizations.of(context);
    if (notes.text.length > 8000) {
      setState(() => error = t.featureEventsNotesLong);
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final next = proposal();
      final store = await ref.read(recordStoreProvider.future);
      final preview = await store.previewEventMembership(
        command(next, commandId ??= newCommandId()),
      );
      if (!mounted) return;
      setState(() {
        frozen = next;
        reviewedFingerprint = jsonEncode(next.toJson());
        entering = preview.entering;
        leaving = preview.leaving;
        reviewGuard = preview.sourceGuard;
        busy = false;
      });
      entryChanged();
    } catch (failure) {
      if (mounted) {
        setState(() {
          busy = false;
          error =
              failure is CommandConflict && failure.code == 'event_zone_review'
              ? t.eventZoneError
              : failure is CommandConflict &&
                    failure.code == 'event_boundary_review'
              ? t.eventBoundaryReview
              : t.eventInvalid;
        });
      }
    }
  }

  Future<void> restorePreview() async {
    if (restoringPreview || frozen == null || commandId == null) return;
    restoringPreview = true;
    final captured = frozen!, guard = reviewGuard;
    try {
      final store = await ref.read(recordStoreProvider.future);
      final restored = await store.previewEventMembership(
        command(captured, commandId!),
      );
      if (frozen != captured || reviewGuard != guard) {
        restoringPreview = false;
        return;
      }
      if (restored.sourceGuard != guard) {
        throw const CommandConflict('membership_review');
      }
      if (mounted) {
        setState(() {
          entering = restored.entering;
          leaving = restored.leaving;
          restoringPreview = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          restoringPreview = false;
          error = AppLocalizations.of(context).eventPreviewChanged;
          if (uncertain) {
            conflict = true;
          } else {
            frozen = null;
            reviewedFingerprint = null;
            reviewGuard = null;
          }
        });
      }
    }
  }

  Future<void> save() async {
    if (!uncertain &&
        (frozen == null ||
            jsonEncode(proposal().toJson()) != reviewedFingerprint)) {
      setState(() => error = AppLocalizations.of(context).eventPreviewChanged);
      return;
    }
    if (entering == null || leaving == null) return;
    final next = frozen!;
    await commit(
      (operation) async {
        await ref.read(eventWriterProvider)(
          command(next, operation),
          EventMembershipReview(
            command: command(next, operation),
            personRevision: capturedPersonRevision!,
            sourceGuard: reviewGuard!,
            entering: entering!,
            leaving: leaving!,
          ),
        );
      },
      successPath: next.completed || next.actualEnd != null
          ? '/event/$id/review'
          : '/event/$id',
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context),
        people = ref.watch(profilesProvider);
    final events = widget.eventId == null
        ? const AsyncData<EventRecord?>(null)
        : ref.watch(eventLookupProvider(widget.eventId!));
    if (!people.hasValue || !events.hasValue) {
      return EntryPage(children: [Text(t.loadingRecords)]);
    }
    final current = events.requireValue;
    if (widget.eventId != null && current == null) {
      return EntryPage(children: [Text(t.draftUnavailable)]);
    }
    if (owner == null) {
      final person = current?.personId ?? meId;
      owner = people.requireValue.where((p) => p.id == person).firstOrNull;
    }
    if (owner == null) return EntryPage(children: [Text(t.profileUnavailable)]);
    if (!initialised) {
      initialised = true;
      detailsOpen = widget.initialDetails;
      original = current;
      if (current != null) {
        id = current.id;
        name.text = current.name;
        notes.text = current.notes;
        zone.text = current.zoneId;
        type = current.eventType;
        completed = current.completed;
        plannedStart.text = current.plannedStart?.value ?? '';
        plannedEnd.text = current.plannedEnd?.value ?? '';
        actualStart.text = current.actualStart?.value ?? '';
        actualEnd.text = current.actualEnd?.value ?? '';
        for (final m in current.memberships) {
          addMembership(
            MembershipFields(
              id: m.id,
              itemId: m.itemId,
              revision: m.revision,
              from: m.effectiveFrom.toIso8601String(),
              until: m.effectiveUntil?.toIso8601String() ?? '',
            ),
          );
        }
      }
    }
    if (!prepareDraft()) return EntryPage(children: [Text(t.loadingRecords)]);
    if (frozen != null && entering == null && !restoringPreview && !conflict) {
      Future.microtask(restorePreview);
    }
    final valid =
        people.requireValue.any(
          (p) =>
              p.id == owner!.id &&
              !p.isArchived &&
              p.revision == capturedPersonRevision,
        ) &&
        (current == null || current.revision == capturedTargetRevision);
    final enabled = valid && !busy && !uncertain && !conflict;
    return wrap([
      Heading(widget.eventId == null ? t.eventNew : t.eventEdit),
      Text(t.profileOwner(ownerLabel(ref, t, owner!.id))),
      Text(t.eventHelp),
      if (!valid) Text(t.conflictFailure),
      const SizedBox(height: 16),
      LabelledInput(label: t.eventName, controller: name, enabled: enabled),
      Text(t.eventType),
      Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          for (final option in [
            ('cycle', t.eventCycle),
            ('prescription', t.eventPrescription),
          ])
            Semantics(
              selected: type == option.$1,
              child: VitalButton.secondary(
                onPressed: !enabled
                    ? null
                    : () {
                        setState(() => type = option.$1);
                        changed();
                      },
                child: Text(option.$2),
              ),
            ),
        ],
      ),
      LabelledInput(
        label: t.eventPlannedStart,
        controller: plannedStart,
        helper: t.eventDateHelp,
        enabled: enabled,
      ),
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: VitalButton.secondary(
          onPressed: () => setState(() => detailsOpen = !detailsOpen),
          child: Text(t.details),
        ),
      ),
      VitalReveal(
        expanded: detailsOpen,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LabelledInput(
              label: t.featureEventsNotes,
              helper: t.featureEventsNotesHelp,
              controller: notes,
              maxLines: 4,
              enabled: enabled,
            ),
            LabelledInput(
              label: t.eventZone,
              controller: zone,
              enabled: enabled,
              error: error == t.eventZoneError ? error : null,
            ),
            for (final field in [
              (t.eventPlannedEnd, plannedEnd),
              (t.eventActualStart, actualStart),
              (t.eventActualEnd, actualEnd),
            ])
              LabelledInput(
                label: field.$1,
                controller: field.$2,
                helper: t.eventDateHelp,
                enabled: enabled,
              ),
            SettingsToggleRow(
              label: t.eventCompleted,
              description: t.eventCompletedHelp,
              value: completed,
              enabled: enabled,
              onChanged: (v) {
                setState(() => completed = v);
                changed();
              },
              reduceMotion: MediaQuery.disableAnimationsOf(context),
            ),
          ],
        ),
      ),
      const SizedBox(height: 24),
      Heading(t.eventMembers),
      Text(t.eventMemberHelp),
      for (final m in memberships)
        Padding(
          key: ValueKey(m.id),
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(switch (ref.watch(itemLookupProvider(m.itemId)).value) {
                final item? => eventItemLabel(
                  t,
                  item,
                  peerIds: memberships.map((row) => row.itemId),
                ),
                _ => t.loadingRecords,
              }),
              LabelledInput(
                label: t.eventMemberStart,
                controller: m.from,
                enabled: enabled,
                semanticLabel: t.eventMemberStartFor(
                  ref.watch(itemLookupProvider(m.itemId)).value?.name ??
                      t.noItem,
                ),
              ),
              LabelledInput(
                label: t.eventMemberEnd,
                controller: m.until,
                enabled: enabled,
                helper: t.eventMemberOpen,
                semanticLabel: t.eventMemberEndFor(
                  ref.watch(itemLookupProvider(m.itemId)).value?.name ??
                      t.noItem,
                ),
              ),
              if (eventMembershipEntryLabel(context, ref, m, zone.text.trim())
                  case final label?)
                Text(label),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: VitalButton.secondary(
                  onPressed: !enabled
                      ? null
                      : () {
                          if (original?.memberships.any(
                                (old) => old.id == m.id,
                              ) ==
                              true) {
                            m.until.text = DateTime.now()
                                .toUtc()
                                .toIso8601String();
                          } else {
                            setState(() => memberships.remove(m));
                            m.dispose();
                            changed();
                          }
                        },
                  child: Text(t.eventRemove),
                ),
              ),
            ],
          ),
        ),
      Text(t.eventChoose),
      ref
          .watch(
            scopedItemsPageProvider((
              scope: FeedScope.person(owner!.id),
              offset: itemOffset,
            )),
          )
          .when(
            data: (items) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    for (final item in items.take(50))
                      VitalButton.secondary(
                        multiline: true,
                        onPressed: !enabled
                            ? null
                            : () {
                                setState(
                                  () => addMembership(
                                    MembershipFields(
                                      id: newCommandId(),
                                      itemId: item.id,
                                      revision: 1,
                                      from: DateTime.now()
                                          .toUtc()
                                          .toIso8601String(),
                                    ),
                                  ),
                                );
                                changed();
                              },
                        child: Text(
                          eventItemLabel(
                            t,
                            item,
                            peerIds: [
                              ...memberships.map((row) => row.itemId),
                              ...items.map((row) => row.id),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    if (itemOffset > 0)
                      VitalButton.secondary(
                        onPressed: () => setState(() => itemOffset -= 50),
                        child: Text(t.previous),
                      ),
                    if (items.length > 50)
                      VitalButton.secondary(
                        onPressed: () => setState(() => itemOffset += 50),
                        child: Text(t.next),
                      ),
                  ],
                ),
              ],
            ),
            error: (_, _) => LoadFailure(
              onRetry: () => ref.invalidate(
                scopedItemsPageProvider((
                  scope: FeedScope.person(owner!.id),
                  offset: itemOffset,
                )),
              ),
            ),
            loading: () => Text(t.loadingRecords),
          ),
      const SizedBox(height: 24),
      ?failure(),
      if (frozen != null) ...[
        Heading(t.eventReview),
        Text(t.eventPreviewHelp),
        if (entering == null || leaving == null) Text(t.loadingRecords),
        if (entering != null) Text(t.eventPreviewEnter(entering!.length)),
        for (final r in entering ?? <UseRecord>[])
          RecordCard(record: r, showActions: false),
        if (leaving != null) Text(t.eventPreviewLeave(leaving!.length)),
        for (final r in leaving ?? <UseRecord>[])
          RecordCard(record: r, showActions: false),
        const SizedBox(height: 16),
        VitalButton(
          onPressed:
              busy ||
                  conflict ||
                  entering == null ||
                  leaving == null ||
                  (!valid && !uncertain)
              ? null
              : save,
          child: Text(
            busy
                ? t.saving
                : uncertain
                ? t.retry
                : t.save,
          ),
        ),
      ] else
        VitalButton.secondary(
          onPressed: enabled ? preview : null,
          child: Text(t.review),
        ),
    ]);
  }
}

class UseHistoryPage extends ConsumerWidget {
  const UseHistoryPage({
    super.key,
    required this.personId,
    required this.itemId,
  });
  final String personId, itemId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context),
        query = (personId: personId, itemId: itemId);
    final item = ref.watch(itemLookupProvider(itemId)).value;
    return EntryPage(
      children: [
        Heading(t.useHistory),
        Text(t.profileOwner(ownerLabel(ref, t, personId))),
        if (item == null || item.personId != personId)
          Text(t.noItem)
        else ...[
          Text(eventItemLabel(t, item)),
          Text(t.useHelp),
          const SizedBox(height: 16),
          VitalButton(
            onPressed: () => context.push('/use/$personId/$itemId/edit'),
            child: Text(t.create),
          ),
          const SizedBox(height: 24),
          ref
              .watch(usePeriodsProvider(query))
              .when(
                data: (periods) => Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (periods.isEmpty) Text(t.useEmpty),
                    for (final period in periods)
                      Padding(
                        key: ValueKey(period.id),
                        padding: const EdgeInsets.only(bottom: 24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              period.kind == UsePeriodKind.use
                                  ? t.useTaking
                                  : t.useBreak,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              t.usePeriodLabel(
                                eventDateLabel(t, period.start),
                                eventDateLabel(t, period.end, open: true),
                              ),
                            ),
                            if (period.start.precision ==
                                    EventDatePrecision.day &&
                                period.end?.precision == EventDatePrecision.day)
                              Text(
                                t.useDays(
                                  CivilDate.parse(period.end!.value!)
                                          .calendarValue
                                          .difference(
                                            CivilDate.parse(period.start.value!)
                                                .calendarValue,
                                          )
                                          .inDays +
                                      1,
                                ),
                              ),
                            if (period.firstEver)
                              Text(
                                t.useFirstLabel(
                                  eventDateLabel(t, period.start),
                                ),
                              ),
                            VitalButton.secondary(
                              onPressed: () => context.push(
                                '/use/$personId/$itemId/edit?period=${period.id}',
                              ),
                              child: Text(t.edit),
                            ),
                            VitalButton.secondary(
                              onPressed: () => context.push(
                                '/period-revisions/${period.id}',
                              ),
                              child: Text(t.eventRevisions),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
                error: (_, _) => LoadFailure(
                  onRetry: () => ref.invalidate(usePeriodsProvider(query)),
                ),
                loading: () => Text(t.loadingRecords),
              ),
        ],
      ],
    );
  }
}

class UsePeriodForm extends ConsumerStatefulWidget {
  const UsePeriodForm({
    super.key,
    required this.personId,
    required this.itemId,
    this.periodId,
  });
  final String personId, itemId;
  final String? periodId;
  @override
  ConsumerState<UsePeriodForm> createState() => _UsePeriodFormState();
}

class _UsePeriodFormState extends DurableFormState<UsePeriodForm> {
  final start = TextEditingController(), end = TextEditingController();
  AdultProfile? owner;
  RecordedUsePeriod? original, frozen;
  bool firstEver = false, initialised = false;
  UsePeriodKind kind = UsePeriodKind.use;
  String id = newCommandId();
  @override
  DraftKind get entryKind => DraftKind.usePeriod;
  @override
  String get entryPerson => widget.personId;
  @override
  int? get entryPersonRevision => owner?.revision;
  @override
  String? get entryTarget => widget.periodId;
  @override
  int? get entryTargetRevision => original?.revision;
  @override
  Map<String, String> captureEntry() => {
    'id': id,
    'item': widget.itemId,
    'start': start.text,
    'end': end.text,
    'kind': kind.name,
    'firstEver': '$firstEver',
    'frozen': frozen == null ? '' : jsonEncode(frozen!.toJson()),
  };
  @override
  void restoreEntry(Map<String, String> fields) {
    id = fields['id']!;
    start.text = fields['start'] ?? '';
    end.text = fields['end'] ?? '';
    kind = UsePeriodKind.values.byName(fields['kind'] ?? 'use');
    firstEver = fields['firstEver'] == 'true';
    if ((fields['frozen'] ?? '').isNotEmpty) {
      frozen = RecordedUsePeriod.fromJson(
        Map<String, Object?>.from(jsonDecode(fields['frozen']!) as Map),
      );
    }
  }

  @override
  void initState() {
    super.initState();
    start.addListener(entryChanged);
    end.addListener(entryChanged);
  }

  @override
  void dispose() {
    start.dispose();
    end.dispose();
    super.dispose();
  }

  Future<void> save() async {
    try {
      if (!uncertain) {
        frozen = RecordedUsePeriod(
          id: id,
          personId: widget.personId,
          itemId: widget.itemId,
          revision: (capturedTargetRevision ?? 0) + 1,
          start: parseEventDate(start.text, partial: true, required: true)!,
          end: parseEventDate(end.text, partial: true),
          kind: kind,
          firstEver: firstEver,
        );
      }
    } catch (_) {
      setState(() => error = AppLocalizations.of(context).useDateError);
      return;
    }
    await commit((command) async {
      await (await ref.read(recordStoreProvider.future)).saveUsePeriod(
        SaveUsePeriodCommand(
          commandId: command,
          generation: capturedGeneration!,
          expectedRevision: capturedTargetRevision,
          expectedPersonRevision: capturedPersonRevision!,
          period: frozen!,
        ),
      );
      ref.invalidate(
        usePeriodsProvider((personId: widget.personId, itemId: widget.itemId)),
      );
    }, successPath: '/use/${widget.personId}/${widget.itemId}');
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context),
        people = ref.watch(profilesProvider);
    final result = ref.watch(
      usePeriodsProvider((personId: widget.personId, itemId: widget.itemId)),
    );
    final item = ref.watch(itemLookupProvider(widget.itemId)).value;
    if (!people.hasValue || !result.hasValue) {
      return EntryPage(children: [Text(t.loadingRecords)]);
    }
    owner ??= people.requireValue
        .where((p) => p.id == widget.personId)
        .firstOrNull;
    final current = result.requireValue
        .where((p) => p.id == widget.periodId)
        .firstOrNull;
    if (owner == null ||
        item == null ||
        item.personId != widget.personId ||
        widget.periodId != null && current == null) {
      return EntryPage(children: [Text(t.draftUnavailable)]);
    }
    if (!initialised) {
      initialised = true;
      original = current;
      if (current != null) {
        id = current.id;
        start.text = current.start.value ?? t.useUnknown;
        end.text = current.end == null
            ? ''
            : current.end!.value ?? t.useUnknown;
        kind = current.kind;
        firstEver = current.firstEver;
      }
    }
    if (!prepareDraft()) return EntryPage(children: [Text(t.loadingRecords)]);
    final valid =
        people.requireValue.any(
          (p) =>
              p.id == owner!.id &&
              !p.isArchived &&
              p.revision == capturedPersonRevision,
        ) &&
        (current == null || current.revision == capturedTargetRevision);
    final enabled = valid && !busy && !uncertain && !conflict;
    return wrap([
      Heading(widget.periodId == null ? t.useNew : t.useEdit),
      Text(t.profileOwner(ownerLabel(ref, t, widget.personId))),
      Text(eventItemLabel(t, item)),
      Text(t.useHelp),
      if (!valid) Text(t.conflictFailure),
      const SizedBox(height: 16),
      LabelledInput(
        label: t.useStart,
        controller: start,
        enabled: enabled,
        helper: t.useDateHelp,
        error: error == t.useDateError ? error : null,
      ),
      LabelledInput(
        label: t.useEnd,
        controller: end,
        enabled: enabled,
        helper: t.useDateHelp,
      ),
      Text(t.useKind),
      Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          for (final choice in [
            (UsePeriodKind.use, t.useTaking),
            (UsePeriodKind.breakPeriod, t.useBreak),
          ])
            Semantics(
              selected: kind == choice.$1,
              child: VitalButton.secondary(
                onPressed: !enabled
                    ? null
                    : () {
                        setState(() {
                          kind = choice.$1;
                          if (kind == UsePeriodKind.breakPeriod) {
                            firstEver = false;
                          }
                        });
                        entryChanged();
                      },
                child: Text(choice.$2),
              ),
            ),
        ],
      ),
      SettingsToggleRow(
        label: t.useFirstEver,
        description: t.useFirstEverHelp,
        value: firstEver,
        enabled: enabled && kind == UsePeriodKind.use,
        onChanged: (v) {
          setState(() => firstEver = v);
          entryChanged();
        },
        reduceMotion: MediaQuery.disableAnimationsOf(context),
      ),
      ?failure(),
      VitalButton(
        onPressed: busy || conflict || (!valid && !uncertain) ? null : save,
        child: Text(
          busy
              ? t.saving
              : uncertain
              ? t.retry
              : t.save,
        ),
      ),
    ]);
  }
}

final eventHistoryProvider = FutureProvider.autoDispose
    .family<List<EventRecord>, String>(retry: (_, _) => null, (ref, id) async {
      ref.watch(eventLookupProvider(id));
      return (await ref.watch(recordStoreProvider.future)).eventHistory(id);
    });
final periodHistoryProvider = FutureProvider.autoDispose
    .family<List<RecordedUsePeriod>, String>(
      retry: (_, _) => null,
      (ref, id) async =>
          (await ref.watch(recordStoreProvider.future)).usePeriodHistory(id),
    );

class EventRevisionsPage extends ConsumerStatefulWidget {
  const EventRevisionsPage({super.key, required this.eventId});
  final String eventId;
  @override
  ConsumerState<EventRevisionsPage> createState() => _EventRevisionsPageState();
}

class _EventRevisionsPageState extends ConsumerState<EventRevisionsPage> {
  int count = 50;
  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return EntryPage(
      children: [
        Heading(t.eventRevisions),
        ref
            .watch(eventHistoryProvider(widget.eventId))
            .when(
              data: (events) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final event in events.take(count))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(t.eventRevision(event.revision)),
                          Text(event.name),
                          Text(
                            t.profileOwner(ownerLabel(ref, t, event.personId)),
                          ),
                          Text(event.zoneId),
                          Text(
                            t.eventPlannedLabel(
                              eventDateLabel(t, event.plannedStart),
                              eventDateLabel(t, event.plannedEnd, open: true),
                            ),
                          ),
                          Text(
                            t.eventActualLabel(
                              eventDateLabel(t, event.actualStart),
                              eventDateLabel(t, event.actualEnd, open: true),
                            ),
                          ),
                          if (event.completed) Text(t.eventCompleted),
                          for (final m in event.memberships)
                            MembershipIdentity(
                              membership: m,
                              zoneId: event.zoneId,
                              peerIds: event.memberships.map(
                                (row) => row.itemId,
                              ),
                            ),
                        ],
                      ),
                    ),
                  if (events.length > count)
                    VitalButton.secondary(
                      onPressed: () => setState(() => count += 50),
                      child: Text(t.more),
                    ),
                ],
              ),
              error: (_, _) => LoadFailure(
                onRetry: () =>
                    ref.invalidate(eventHistoryProvider(widget.eventId)),
              ),
              loading: () => Text(t.loadingRecords),
            ),
      ],
    );
  }
}

class UsePeriodRevisionsPage extends ConsumerWidget {
  const UsePeriodRevisionsPage({super.key, required this.periodId});
  final String periodId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    return EntryPage(
      children: [
        Heading(t.eventRevisions),
        ref
            .watch(periodHistoryProvider(periodId))
            .when(
              data: (periods) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final period in periods)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(t.eventRevision(period.revision)),
                          Text(
                            t.profileOwner(ownerLabel(ref, t, period.personId)),
                          ),
                          Text(
                            period.kind == UsePeriodKind.use
                                ? t.useTaking
                                : t.useBreak,
                          ),
                          Text(
                            t.usePeriodLabel(
                              eventDateLabel(t, period.start),
                              eventDateLabel(t, period.end, open: true),
                            ),
                          ),
                          if (period.firstEver)
                            Text(
                              t.useFirstLabel(eventDateLabel(t, period.start)),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
              error: (_, _) => LoadFailure(
                onRetry: () => ref.invalidate(periodHistoryProvider(periodId)),
              ),
              loading: () => Text(t.loadingRecords),
            ),
      ],
    );
  }
}
