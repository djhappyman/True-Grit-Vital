import '../supporting/supporting_pages.dart';
import '../../app/display_preferences.dart';
import '../../ui/vital_ui.dart';

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../app/storage.dart';
import '../../app/settings_toggle_row.dart';
import '../../app/vital_app.dart' show PageContent;
import '../../data/record_store.dart';
import '../../domain/scheduling/iana_clock.dart';
import '../../l10n/app_localizations.dart';
import '../profiles/profile_pages.dart';
import '../recording/record_pages.dart';

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

class EventsPage extends ConsumerStatefulWidget {
  const EventsPage({super.key});
  @override
  ConsumerState<EventsPage> createState() => _EventsPageState();
}

class _EventsPageState extends ConsumerState<EventsPage> {
  final selected = <String>{};
  final selectedOwners = <String, String>{};
  int offset = 0;
  FeedScope? previousScope;
  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context),
        scope = ref.watch(browsingScopeProvider);
    final people = ref.watch(profilesProvider);
    if (!scope.hasValue || !people.hasValue) {
      return PageContent(children: [Text(t.loadingRecords)]);
    }
    if (previousScope != scope.requireValue) {
      offset = 0;
      previousScope = scope.requireValue;
    }
    final query = (
      personId: scope.requireValue.isEveryone
          ? null
          : scope.requireValue.personId,
      offset: offset,
    );
    final result = ref.watch(eventPageProvider(query));
    final owners = people.requireValue.where((p) => !p.isArchived).toList();
    final visible = result.value
        ?.where(
          (e) =>
              owners.any((p) => p.id == e.personId) &&
              (scope.requireValue.isEveryone ||
                  e.personId == scope.requireValue.personId),
        )
        .toList();
    final picked = selected
        .where(
          (id) =>
              owners.any((p) => p.id == selectedOwners[id]) &&
              (scope.requireValue.isEveryone ||
                  selectedOwners[id] == scope.requireValue.personId),
        )
        .toList();
    return PageContent(
      children: [
        Heading(t.events),
        Text(
          scope.requireValue.isEveryone
              ? t.everyone
              : t.profileOwner(
                  ownerLabel(ref, t, scope.requireValue.personId!),
                ),
        ),
        Text(t.eventHelp),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            VitalButton.secondary(
              onPressed: () => context.push('/scope'),
              child: Text(t.scope),
            ),
            VitalButton(
              onPressed: () => context.push(
                '/event-create${scope.requireValue.isEveryone ? '' : '?person=${scope.requireValue.personId}'}',
              ),
              child: Text(t.create),
            ),
          ],
        ),
        const SizedBox(height: 20),
        if (result.hasError)
          LoadFailure(onRetry: () => ref.invalidate(eventPageProvider(query)))
        else if (!result.hasValue)
          Text(t.loadingRecords)
        else ...[
          if (visible!.isEmpty) Text(t.eventEmpty),
          if (visible.isNotEmpty) Text(t.eventSelectHelp),
          for (final event in visible.take(50))
            Padding(
              key: ValueKey(event.id),
              padding: const EdgeInsets.only(bottom: 16),
              child: VitalSurface(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      event.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 20,
                      ),
                    ),
                    Text(t.profileOwner(ownerLabel(ref, t, event.personId))),
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
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        Semantics(
                          label: t.eventReviewFor(
                            event.name,
                            ownerLabel(ref, t, event.personId),
                          ),
                          child: VitalButton.secondary(
                            onPressed: () => context.push('/event/${event.id}'),
                            child: Text(t.review),
                          ),
                        ),
                        Semantics(
                          label: t.eventSelectFor(
                            event.name,
                            ownerLabel(ref, t, event.personId),
                          ),
                          selected: selected.contains(event.id),
                          child: VitalButton.secondary(
                            onPressed: () => setState(() {
                              if (!selected.add(event.id)) {
                                selected.remove(event.id);
                                selectedOwners.remove(event.id);
                              } else {
                                selectedOwners[event.id] = event.personId;
                              }
                            }),
                            child: Text(
                              selected.contains(event.id)
                                  ? t.eventSelected
                                  : t.eventSelect,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              if (offset > 0)
                VitalButton.secondary(
                  onPressed: () => setState(() => offset -= 50),
                  child: Text(t.previous),
                ),
              if (result.requireValue.length > 50)
                VitalButton.secondary(
                  onPressed: () => setState(() => offset += 50),
                  child: Text(t.next),
                ),
            ],
          ),
          if (picked.isNotEmpty) ...[
            Heading(t.eventCombined),
            VitalButton.secondary(
              onPressed: () => setState(() {
                selected.clear();
                selectedOwners.clear();
              }),
              child: Text(t.eventClear),
            ),
            EventActualList(ids: (picked..sort()).join(',')),
          ],
        ],
      ],
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

/// Display-only timing. It never changes membership, plans, stock or doses.
/// Civil dates count calendar days in the saved zone, including the final day.
/// Exact boundaries use completed elapsed and started remaining 24-hour periods.
({int? elapsed, int? remaining, int? startsIn}) cycleTiming(
  EventRecord event,
  DateTime now,
) {
  const unavailable = (elapsed: null, remaining: null, startsIn: null);
  if (event.completed && event.actualEnd == null) return unavailable;
  final clock = IanaClock();
  final startDate = event.actualStart ?? event.plannedStart;
  final endDate = event.actualEnd ?? event.plannedEnd;
  try {
    final start = startDate?.resolve(clock, event.zoneId);
    final end = endDate?.resolve(clock, event.zoneId, inclusiveEnd: true);
    if (startDate != null && start == null || endDate != null && end == null) {
      return unavailable;
    }
    int civilDays(DateTime a, DateTime b) {
      final first = clock.dateAt(a, event.zoneId);
      final last = clock.dateAt(b, event.zoneId);
      return DateTime.utc(
        last.year,
        last.month,
        last.day,
      ).difference(DateTime.utc(first.year, first.month, first.day)).inDays;
    }

    if (start != null && now.isBefore(start)) {
      return (
        elapsed: null,
        remaining: null,
        startsIn: startDate!.precision == EventDatePrecision.day
            ? civilDays(now, start)
            : (start.difference(now).inMicroseconds /
                      Duration.microsecondsPerDay)
                  .ceil(),
      );
    }
    final until = end != null && now.isAfter(end) ? end : now;
    final elapsed = start == null
        ? null
        : startDate!.precision == EventDatePrecision.day
        ? civilDays(start, until)
        : until.difference(start).inDays;
    final remaining = end == null
        ? null
        : !now.isBefore(end)
        ? 0
        : endDate!.precision == EventDatePrecision.day
        ? civilDays(now, end)
        : (end.difference(now).inMicroseconds / Duration.microsecondsPerDay)
              .ceil();
    return (elapsed: elapsed, remaining: remaining, startsIn: null);
  } catch (_) {
    // Partial/unknown boundaries and zones needing review never acquire a date.
    return unavailable;
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
    final timing = cycleTiming(event, DateTime.now().toUtc());
    return EntryPage(
      children: [
        Heading(t.events),
        Text(
          event.name,
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
        ),
        Text(t.profileOwner(ownerLabel(ref, t, event.personId))),
        VitalButton.secondary(
          onPressed: () => context.push(
            supportingLocation(
              event.personId,
              event: event.id,
              back: '/event/${event.id}',
            ),
          ),
          child: Text(t.supportingTitle),
        ),
        Text(
          event.eventType == 'cycle'
              ? t.eventCycle
              : event.eventType == 'prescription'
              ? t.eventPrescription
              : event.eventType,
        ),
        const SizedBox(height: 16),
        VitalSurface(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                t.eventPlannedLabel(
                  eventDateLabel(t, event.plannedStart),
                  eventDateLabel(t, event.plannedEnd, open: true),
                ),
              ),
              if (event.actualStart != null || event.actualEnd != null) ...[
                const SizedBox(height: 8),
                Text(
                  t.eventActualLabel(
                    eventDateLabel(t, event.actualStart),
                    eventDateLabel(t, event.actualEnd, open: true),
                  ),
                ),
              ],
              const SizedBox(height: 8),
              Text(event.zoneId),
              Text(t.eventInclusive),
              if (timing.startsIn case final days?) Text(t.cycleStartsIn(days)),
              if (timing.elapsed case final days?) Text(t.cycleElapsed(days)),
              if (timing.remaining case final days?)
                Text(t.cycleRemaining(days)),
              if (event.completed) Text(t.eventCompleted),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            VitalButton.secondary(
              onPressed: () => context.push('/event/${event.id}/edit'),
              child: Text(t.edit),
            ),
            VitalButton.secondary(
              onPressed: () => context.push('/event/${event.id}/revisions'),
              child: Text(t.eventRevisions),
            ),
            VitalButton.secondary(
              onPressed: () => context.push('/event/${event.id}/review'),
              child: Text(t.review),
            ),
          ],
        ),
        const SizedBox(height: 24),
        Heading(t.eventMembers),
        if (event.memberships.isEmpty) Text(t.eventNoMembers),
        for (final m in event.memberships)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: MembershipIdentity(
              membership: m,
              zoneId: event.zoneId,
              peerIds: event.memberships.map((row) => row.itemId),
            ),
          ),
        const SizedBox(height: 24),
        Heading(t.history),
        EventActualList(ids: event.id),
      ],
    );
  }
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
  const EventForm({super.key, this.personId, this.eventId});
  final String? personId, eventId;
  @override
  ConsumerState<EventForm> createState() => _EventFormState();
}

class _EventFormState extends DurableFormState<EventForm> {
  final name = TextEditingController(),
      zone = TextEditingController(text: 'Europe/London');
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
  DraftKind get entryKind => DraftKind.event;
  @override
  String? get entryPerson => owner?.id ?? widget.personId;
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
      final person = current?.personId ?? widget.personId;
      if (person == null) {
        return EntryPage(
          children: [
            Heading(t.choosePerson),
            for (final p in people.requireValue.where((p) => !p.isArchived))
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: VitalButton.secondary(
                  multiline: true,
                  onPressed: () =>
                      context.pushReplacement('/event-create?person=${p.id}'),
                  child: Text(personLabel(t, people.requireValue, p.id)),
                ),
              ),
          ],
        );
      }
      owner = people.requireValue.where((p) => p.id == person).firstOrNull;
    }
    if (owner == null) return EntryPage(children: [Text(t.profileUnavailable)]);
    if (!initialised) {
      initialised = true;
      original = current;
      if (current != null) {
        id = current.id;
        name.text = current.name;
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
      if (detailsOpen) ...[
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
