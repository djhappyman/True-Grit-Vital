import '../../ui/vital_ui.dart';

import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../app/device_zone.dart';
import '../../app/reminders.dart';
import '../../app/storage.dart';
import '../../data/daily_codec.dart';
import '../../data/record_store.dart';
import '../../l10n/app_localizations.dart';
import '../plans/interval_clock.dart';
import '../plans/plan_form.dart' show expectationLabel;
import '../plans/phase_editor.dart' show phaseTimingSummary;
import '../profiles/profile_pages.dart';
import '../recording/record_pages.dart';
import 'event_pages.dart' show eventItemLabel;

Map<String, Object?> encodeEventReview(EventEndReview review) => {
  'event': review.event.toJson(),
  'person': review.personRevision,
  'generation': review.generation,
  'items': [
    for (final row in review.items)
      {
        'id': row.item.id,
        'person': row.item.personId,
        'name': row.item.name,
        'form': row.item.form,
        'unit': row.item.unit,
        'type': row.item.type,
        'revision': row.item.revision,
        'decision': row.decision,
        'decisionSequence': row.decisionSequence,
        'plans': [
          for (final p in row.plans)
            {'plan': encodeDailyPlan(p.plan), 'revision': p.revision},
        ],
      },
  ],
};
EventEndReview decodeEventReview(Map<String, dynamic> json) => EventEndReview(
  event: EventRecord.fromJson(Map<String, Object?>.from(json['event'] as Map)),
  personRevision: json['person'] as int,
  generation: json['generation'] as String,
  items: [
    for (final raw in json['items'] as List)
      EventEndItem(
        item: SubstanceItem(
          id: raw['id'] as String,
          personId: raw['person'] as String,
          name: raw['name'] as String,
          form: raw['form'] as String,
          unit: raw['unit'] as String,
          type: raw['type'] as String,
          revision: raw['revision'] as int,
        ),
        decision: raw['decision'] as String?,
        decisionSequence: raw['decisionSequence'] as int? ?? 0,
        plans: [
          for (final p in raw['plans'] as List)
            SavedDailyPlan(
              plan: decodeDailyPlan(
                Map<String, dynamic>.from(p['plan'] as Map),
              ),
              revision: p['revision'] as int,
            ),
        ],
      ),
  ],
);
Map<String, Object?> encodeEndPhaseReview(PhaseChangeReview r) => {
  'plan': encodeDailyPlan(r.plan.plan),
  'revision': r.plan.revision,
  'proposed': encodePhasePlan(r.proposed),
  'person': r.personRevision,
  'generation': r.generation,
  'guard': r.sourceGuard,
  'now': r.now.toIso8601String(),
  'zone': r.observedZone,
  'before': r.before == null ? null : encodeDailyExpectation(r.before!),
  'after': r.after == null ? null : encodeDailyExpectation(r.after!),
};
PhaseChangeReview decodeEndPhaseReview(
  Map<String, dynamic> json,
) => PhaseChangeReview(
  plan: SavedDailyPlan(
    plan: decodeDailyPlan(Map<String, dynamic>.from(json['plan'] as Map)),
    revision: json['revision'] as int,
  ),
  proposed: decodePhasePlan(Map<String, dynamic>.from(json['proposed'] as Map)),
  personRevision: json['person'] as int,
  generation: json['generation'] as String,
  sourceGuard: json['guard'] as String,
  now: DateTime.parse(json['now'] as String),
  observedZone: json['zone'] as String,
  before: json['before'] == null
      ? null
      : decodeDailyExpectation(
          Map<String, dynamic>.from(json['before'] as Map),
        ),
  after: json['after'] == null
      ? null
      : decodeDailyExpectation(Map<String, dynamic>.from(json['after'] as Map)),
);

final eventEndReviewProvider = FutureProvider.autoDispose
    .family<EventEndReview, String>(retry: (_, _) => null, (ref, id) async {
      return (await ref.watch(recordStoreProvider.future)).eventEndReview(id);
    });

class EventEndReviewPage extends ConsumerWidget {
  const EventEndReviewPage({super.key, required this.eventId, this.envelopeId});
  final String eventId;
  final String? envelopeId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    return ref
        .watch(eventEndReviewProvider(eventId))
        .when(
          data: (review) => EntryPage(
            children: [
              Heading(t.eventEndReview),
              Text(review.event.name),
              Text(t.profileOwner(ownerLabel(ref, t, review.event.personId))),
              Text(t.eventEndHelp),
              Text(t.eventReviewRemaining),
              const SizedBox(height: 16),
              for (final row in review.items)
                Padding(
                  key: ValueKey(row.item.id),
                  padding: const EdgeInsets.only(bottom: 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        eventItemLabel(
                          t,
                          row.item,
                          peerIds: review.items.map((i) => i.item.id),
                        ),
                      ),
                      if (row.plans.isEmpty) Text(t.eventNoPlan),
                      for (final plan in row.plans)
                        ...phaseTimingSummary(context, ref, t, plan.plan),
                      if (row.decision != null) Text(t.eventDecisionSaved),
                      VitalButton.secondary(
                        onPressed: review.event.endReviewDismissed
                            ? null
                            : () => context.push(
                                '/event/$eventId/decision?item=${row.item.id}${envelopeId == null ? '' : '&envelope=${Uri.encodeComponent(envelopeId!)}'}',
                              ),
                        child: Text(t.review),
                      ),
                    ],
                  ),
                ),
              VitalButton.secondary(
                onPressed: review.event.endReviewDismissed
                    ? null
                    : () => context.push(
                        '/event/$eventId/decision${envelopeId == null ? '' : '?envelope=${Uri.encodeComponent(envelopeId!)}'}',
                      ),
                child: Text(t.eventDismiss),
              ),
            ],
          ),
          error: (_, _) => EntryPage(
            children: [
              LoadFailure(
                onRetry: () => ref.invalidate(eventEndReviewProvider(eventId)),
              ),
            ],
          ),
          loading: () => EntryPage(children: [Text(t.loadingRecords)]),
        );
  }
}

class EventDecisionForm extends ConsumerStatefulWidget {
  const EventDecisionForm({
    super.key,
    required this.eventId,
    this.itemId,
    this.envelopeId,
  });
  final String eventId;
  final String? itemId, envelopeId;
  @override
  ConsumerState<EventDecisionForm> createState() => _EventDecisionFormState();
}

class _EventDecisionFormState extends DurableFormState<EventDecisionForm> {
  EventEndReview? review;
  List<PhaseChangeReview> previews = [];
  String? choice;
  String clock = '', zone = '';
  DateTime? reviewedAt;
  bool initialised = false, preparing = false, currentStarted = false;
  @override
  DraftKind get entryKind => DraftKind.eventReview;
  @override
  String? get entryPerson => review?.event.personId;
  @override
  int? get entryPersonRevision => review?.personRevision;
  @override
  String get entryTarget => widget.eventId;
  @override
  int? get entryTargetRevision => review?.event.revision;
  @override
  Map<String, String> captureEntry() => {
    'review': jsonEncode(encodeEventReview(review!)),
    'item': widget.itemId ?? '',
    'decision': choice ?? '',
    'clock': clock,
    'reviewedAt': reviewedAt?.toIso8601String() ?? '',
    'frozen': zone,
    'stopReview': jsonEncode(previews.map(encodeEndPhaseReview).toList()),
  };
  @override
  void restoreEntry(Map<String, String> fields) {
    // One interrupted item decision owns the event draft until resolved.
    if (fields['item'] != (widget.itemId ?? '')) {
      conflict = true;
      error = AppLocalizations.of(context).eventReviewRemaining;
      return;
    }
    review = decodeEventReview(
      Map<String, dynamic>.from(jsonDecode(fields['review']!) as Map),
    );
    choice = fields['decision']!.isEmpty ? null : fields['decision'];
    clock = fields['clock'] ?? '';
    zone = fields['frozen'] ?? '';
    reviewedAt = DateTime.tryParse(fields['reviewedAt'] ?? '');
    previews = [
      for (final value in jsonDecode(fields['stopReview'] ?? '[]') as List)
        decodeEndPhaseReview(Map<String, dynamic>.from(value as Map)),
    ];
  }

  EventEndItem? get row =>
      review?.items.where((i) => i.item.id == widget.itemId).firstOrNull;
  Future<void> choose(String value) async {
    if (preparing || busy || uncertain) return;
    setState(() {
      preparing = true;
      error = null;
    });
    try {
      final store = await ref.read(recordStoreProvider.future);
      reviewedAt = DateTime.now().toUtc();
      zone =
          ref.read(observedDeviceZoneProvider).value?.zoneId ??
          review!.event.zoneId;
      clock = encodeIntervalClock(await captureIntervalClock(ref));
      final next = <PhaseChangeReview>[];
      for (final plan in row?.plans ?? <SavedDailyPlan>[]) {
        final current =
            await store.phasePlan(
              planId: plan.plan.planId,
              personId: plan.plan.personId,
            ) ??
            PhasePlan(phases: [plan.plan]);
        final end = value == 'stop'
            ? PlanEnd(
                zoneId: zone,
                exclusiveInstant:
                    current.end != null &&
                        current.end!.exclusiveInstant.isBefore(reviewedAt!)
                    ? current.end!.exclusiveInstant
                    : reviewedAt!,
              )
            : current.end;
        final proposed = PhasePlan(
          phases: current.phases,
          originPhases: current.originPhases,
          overrides: current.overrides,
          end: end,
        );
        next.add(
          await store.previewPhasePlan(
            plan: plan,
            proposed: proposed,
            now: reviewedAt!,
            observedZone: zone,
          ),
        );
      }
      if (mounted) {
        setState(() {
          if (value != 'preview') choice = value;
          previews = next;
          preparing = false;
        });
      }
      entryChanged();
    } catch (_) {
      if (mounted) {
        setState(() {
          error = AppLocalizations.of(context).conflictFailure;
          preparing = false;
        });
      }
    }
  }

  Future<void> save() async {
    if (choice == null && widget.itemId != null) return;
    await commit(
      (operation) async {
        final store = await ref.read(recordStoreProvider.future);
        if (widget.itemId == null) {
          await store.dismissEventEndReview(
            commandId: operation,
            review: review!,
          );
        } else {
          await store.applyEventItemDecision(
            commandId: operation,
            review: review!,
            itemId: widget.itemId!,
            continuePlan: choice == 'continue',
            stopReviews: choice == 'stop' ? previews : [],
            intervalClockSample: decodeIntervalClock(clock),
          );
        }
        if (widget.envelopeId != null) {
          await store.consumePendingEventEndReview(widget.envelopeId!);
          ref
              .read(remindersProvider.notifier)
              .completeEventPending(widget.envelopeId!);
        }
        ref.invalidate(eventEndReviewProvider(widget.eventId));
      },
      successPath: widget.itemId == null
          ? '/event/${widget.eventId}'
          : '/event/${widget.eventId}/review',
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context),
        result = ref.watch(eventEndReviewProvider(widget.eventId));
    if (result.hasError) {
      return EntryPage(
        children: [
          LoadFailure(
            onRetry: () =>
                ref.invalidate(eventEndReviewProvider(widget.eventId)),
          ),
        ],
      );
    }
    if (!result.hasValue) return EntryPage(children: [Text(t.loadingRecords)]);
    if (!initialised) {
      initialised = true;
      review = result.requireValue;
    }
    if (!prepareDraft()) return EntryPage(children: [Text(t.loadingRecords)]);
    if (review == null || widget.itemId != null && row == null) {
      return EntryPage(children: [Text(t.draftUnavailable)]);
    }
    final valid =
        result.requireValue.event.revision == capturedTargetRevision &&
        result.requireValue.personRevision == capturedPersonRevision;
    if (!currentStarted &&
        !uncertain &&
        previews.isEmpty &&
        widget.itemId != null) {
      currentStarted = true;
      scheduleMicrotask(() => choose('preview'));
    }
    final enabled = valid && !busy && !uncertain && !conflict && !preparing;
    return wrap([
      Heading(t.eventEndReview),
      Text(review!.event.name),
      Text(t.profileOwner(ownerLabel(ref, t, review!.event.personId))),
      Text(t.eventEndHelp),
      if (!valid) Text(t.conflictFailure),
      if (widget.itemId != null) ...[
        Text(
          eventItemLabel(
            t,
            row!.item,
            peerIds: review!.items.map((i) => i.item.id),
          ),
        ),
        if (row!.plans.isEmpty) Text(t.eventNoPlan),
        for (final p in row!.plans)
          ...phaseTimingSummary(context, ref, t, p.plan),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final option in [
              ('continue', t.eventContinue),
              ('stop', t.eventStop),
            ])
              Semantics(
                selected: choice == option.$1,
                child: VitalButton.secondary(
                  onPressed: enabled ? () => choose(option.$1) : null,
                  child: Text(option.$2),
                ),
              ),
          ],
        ),
        if (choice != null)
          Text(choice == 'continue' ? t.eventContinueHelp : t.eventStopHelp),
        for (final p in previews) ...[
          Text(
            t.phaseBefore(
              p.before == null
                  ? t.eventNoPlan
                  : expectationLabel(context, ref, t, p.before!),
            ),
          ),
          Text(
            t.phaseAfter(
              p.after == null
                  ? t.eventNoPlan
                  : expectationLabel(context, ref, t, p.after!),
            ),
          ),
        ],
      ],
      ?failure(),
      const SizedBox(height: 16),
      VitalButton(
        onPressed:
            busy ||
                preparing ||
                conflict ||
                (!valid && !uncertain) ||
                widget.itemId != null && choice == null
            ? null
            : save,
        child: Text(
          busy
              ? t.saving
              : uncertain
              ? t.retry
              : widget.itemId == null
              ? t.eventDismiss
              : t.save,
        ),
      ),
    ]);
  }
}
