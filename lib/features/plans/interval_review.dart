import '../../app/display_preferences.dart';
import '../../ui/vital_ui.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../app/device_zone.dart';
import '../../app/storage.dart';
import '../../app/reminders.dart';
import '../../data/record_store.dart';
import '../../l10n/app_localizations.dart';
import '../profiles/profile_pages.dart';
import '../recording/record_pages.dart';
import '../stock/stock_widgets.dart';
import 'plan_providers.dart';
import 'interval_editor.dart';
import 'interval_clock.dart';

/// The repository resolves both sides and guards the exact reviewed source set.
/// Cancelling this dialog performs no durable command.
Future<bool> showIntervalReview(
  BuildContext context,
  WidgetRef ref,
  UseRecord record,
  List<IntervalChangeReview> reviews, {
  String? proposedAmount,
}) async {
  if (reviews.isEmpty) return true;
  final t = AppLocalizations.of(context);
  return await showVitalDialog<bool>(
        context: context,
        builder: (context) => VitalDialog(
          title: Text(t.intervalReview),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(t.profileOwner(ownerLabel(ref, t, record.personId))),
                Text(record.name),
                Text(
                  t.stockQuantity(
                    stockRecordAmountNumber(t, record),
                    record.actualUnit,
                  ),
                ),
                Text(
                  t.intervalRecordedTime(
                    displayStamp(context, ref, record.actualAt),
                  ),
                ),
                if (proposedAmount != null)
                  Text(
                    t.intervalProposedAmount(proposedAmount, record.actualUnit),
                  ),
                for (final review in reviews) ...[
                  const SizedBox(height: 12),
                  Text(
                    t.intervalPlan(
                      review.plan.plan.start.toString(),
                      (review.plan.plan.timing as ElapsedInterval)
                          .duration
                          .hoursText,
                    ),
                  ),
                  Text(t.intervalSourceRevision(review.expectedRecordRevision)),
                  if (review.before?.identity.sourceActualRevision
                      case final int revision)
                    Text(t.intervalAnchorRevision(revision)),
                  Text(
                    t.intervalBefore(
                      (review.before?.instant == null
                              ? null
                              : displayStamp(
                                  context,
                                  ref,
                                  review.before!.instant!,
                                )) ??
                          t.intervalNoAnchor,
                    ),
                  ),
                  Text(
                    t.intervalAfter(
                      (review.after?.instant == null
                              ? null
                              : displayStamp(
                                  context,
                                  ref,
                                  review.after!.instant!,
                                )) ??
                          t.intervalNoAnchor,
                    ),
                  ),
                  if (review.after?.identity.sourceActualRevision
                      case final int revision)
                    Text(t.intervalAnchorRevision(revision)),
                ],
              ],
            ),
          ),
          actions: [
            VitalButton.secondary(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(t.cancel),
            ),
            VitalButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(t.save),
            ),
          ],
        ),
      ) ??
      false;
}

Future<List<IntervalChangeReview>?> reviewIntervalMutation(
  BuildContext context,
  WidgetRef ref,
  UseRecord record, {
  DateTime? actualAt,
  bool voided = false,
  String? proposedAmount,
  ReminderClockSample? intervalClockSample,
  bool captureClockIfMissing = true,
}) async {
  final store = await ref.read(recordStoreProvider.future);
  final plans = await store.dailyPlans(itemId: record.itemId);
  if (!plans.any(
    (p) =>
        p.plan.timing is ElapsedInterval &&
        (p.plan.timing as ElapsedInterval).mode ==
            IntervalMode.qualifyingActual,
  )) {
    return [];
  }
  final zone = ref.read(observedDeviceZoneProvider).value?.zoneId;
  if (zone == null) throw const CommandConflict('observed_zone');
  final sample =
      intervalClockSample ??
      (captureClockIfMissing ? await captureIntervalClock(ref) : null);
  final reviews = await store.previewIntervalChanges(
    recordId: record.id,
    personId: record.personId,
    expectedRevision: record.revision,
    actualAt: actualAt,
    voided: voided,
    now: sample?.utc ?? DateTime.now().toUtc(),
    observedZone: zone,
    intervalClockSample: sample,
  );
  if (!context.mounted) return null;
  return await showIntervalReview(
        context,
        ref,
        record,
        reviews,
        proposedAmount: proposedAmount,
      )
      ? reviews
      : null;
}

typedef IntervalQualificationInput = ({
  String commandId,
  IntervalChangeReview review,
});
final intervalQualificationWriterProvider =
    Provider<Future<void> Function(IntervalQualificationInput)>(
      (ref) => (input) async {
        await (await ref.read(recordStoreProvider.future))
            .qualifyInterval(commandId: input.commandId, review: input.review);
      },
    );

class IntervalRecordChoices extends ConsumerStatefulWidget {
  const IntervalRecordChoices({super.key, required this.record});
  final UseRecord record;
  @override
  ConsumerState<IntervalRecordChoices> createState() =>
      _IntervalRecordChoicesState();
}

class _IntervalRecordChoicesState extends ConsumerState<IntervalRecordChoices> {
  bool expanded = false, busy = false;
  String? error, command;
  IntervalChangeReview? pending;
  Future<void> select(SavedDailyPlan plan, bool qualifies) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final store = await ref.read(recordStoreProvider.future);
      if (!mounted) return;
      if (qualifies && widget.record.actualAt.isAfter(DateTime.now().toUtc())) {
        setState(() => error = AppLocalizations.of(context).intervalFuture);
        return;
      }
      final zone = ref.read(observedDeviceZoneProvider).value?.zoneId;
      if (zone == null) throw const CommandConflict('observed_zone');
      final sample = pending == null
          ? await captureIntervalClock(ref)
          : pending!.intervalClockSample;
      pending ??= await store.previewIntervalChange(
        plan: plan,
        recordId: widget.record.id,
        expectedRecordRevision: widget.record.revision,
        qualifies: qualifies,
        now: sample?.utc ?? DateTime.now().toUtc(),
        observedZone: zone,
        intervalClockSample: sample,
      );
      if (!mounted) return;
      if (command == null) {
        if (!await showIntervalReview(context, ref, widget.record, [
          pending!,
        ])) {
          pending = null;
          return;
        }
        command = newCommandId();
      }
      await ref.read(intervalQualificationWriterProvider)((
        commandId: command!,
        review: pending!,
      ));
      pending = null;
      command = null;
      ref.invalidate(intervalSourcesProvider);
      ref.invalidate(dailyFeedProvider);
      ref.invalidate(nextDailyPlansProvider);
    } catch (e) {
      if (mounted) {
        setState(() {
          error = e is CommandConflict
              ? AppLocalizations.of(context).conflictFailure
              : AppLocalizations.of(context).saveFailure;
          if (e is CommandConflict) {
            pending = null;
            command = null;
          }
        });
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context), r = widget.record;
    final plans = ref.watch(itemPlansProvider(r.itemId));
    if (!plans.hasValue) {
      return plans.hasError
          ? LoadFailure(
              onRetry: () => ref.invalidate(itemPlansProvider(r.itemId)),
            )
          : const SizedBox.shrink();
    }
    final intervals = plans.requireValue
        .where(
          (p) =>
              p.plan.personId == r.personId &&
              p.plan.timing is ElapsedInterval &&
              (p.plan.timing as ElapsedInterval).mode ==
                  IntervalMode.qualifyingActual,
        )
        .toList();
    if (intervals.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!expanded)
          VitalButton.secondary(
            onPressed: () => setState(() => expanded = true),
            child: Text(t.review),
          ),
        if (expanded) ...[
          Heading(t.intervalReview),
          Text(t.intervalQualifyHelp),
          if (error != null) Semantics(liveRegion: true, child: Text(error!)),
          for (final plan in intervals)
            ref
                .watch(
                  intervalSourcesProvider((
                    planId: plan.plan.planId,
                    personId: r.personId,
                  )),
                )
                .when(
                  loading: () => Text(t.loadingRecords),
                  error: (_, _) => LoadFailure(
                    onRetry: () => ref.invalidate(intervalSourcesProvider),
                  ),
                  data: (sources) {
                    final qualifies = sources.any(
                      (s) =>
                          s.actualId == r.id &&
                          s.segmentId ==
                              (plan.plan.timing as ElapsedInterval).segmentId &&
                          s.qualifies &&
                          !s.isVoid,
                    );
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          t.intervalPlan(
                            plan.plan.start.toString(),
                            (plan.plan.timing as ElapsedInterval)
                                .duration
                                .hoursText,
                          ),
                        ),
                        Text(
                          qualifies ? t.intervalQualified : t.intervalExtraHelp,
                        ),
                        VitalButton.secondary(
                          onPressed: busy
                              ? null
                              : () => select(plan, !qualifies),
                          child: Text(
                            pending == null
                                ? (qualifies ? t.remove : t.select)
                                : t.retry,
                          ),
                        ),
                      ],
                    );
                  },
                ),
        ],
      ],
    );
  }
}

/// A new boot needs an explicit review of today's onward native timing basis.
/// It does not requalify records or replay earlier consumed expectations.
class IntervalClockRecovery extends ConsumerStatefulWidget {
  const IntervalClockRecovery({super.key, required this.saved});
  final SavedDailyPlan saved;
  @override
  ConsumerState<IntervalClockRecovery> createState() =>
      _IntervalClockRecoveryState();
}

class _IntervalClockRecoveryState extends ConsumerState<IntervalClockRecovery> {
  bool busy = false;
  String? error, command;
  IntervalClockReview? pending;
  Future<void> recover() async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final store = await ref.read(recordStoreProvider.future);
      final sample = pending?.sample ?? await captureIntervalClock(ref);
      if (!mounted) return;
      final t = AppLocalizations.of(context);
      if (sample == null) {
        setState(() => error = t.reminderUnsupported);
        return;
      }
      final p = widget.saved.plan;
      final zone = p.zoneBasis is FixedHome
          ? (p.zoneBasis as FixedHome).zoneId
          : ref.read(observedDeviceZoneProvider).value?.zoneId;
      if (zone == null) {
        setState(() => error = t.planZoneUnavailable);
        return;
      }
      final date = DailyResolver().currentDate(
        p,
        now: sample.utc,
        observedZone: zone,
      );
      pending ??= await store.previewIntervalClockRecovery(
        observedZone: zone,
        plan: widget.saved,
        sample: sample,
        reviewedFrom: date.compareTo(p.start) < 0 ? p.start : date,
      );
      if (!mounted) return;
      if (command == null) {
        final item = await store.itemById(p.itemId);
        if (!mounted) return;
        final approved = await showVitalDialog<bool>(
          context: context,
          builder: (context) => VitalDialog(
            title: Text(t.intervalClockHeading),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(t.profileOwner(ownerLabel(ref, t, p.personId))),
                  if (item != null) Text(item.name),
                  Text(
                    t.stockQuantity(
                      (p.timing as ElapsedInterval).amount.enteredText,
                      (p.timing as ElapsedInterval).amount.unit,
                    ),
                  ),
                  Text(t.intervalClockReview(pending!.reviewedFrom.toString())),
                  Text(t.intervalBefore(t.intervalClockStopped)),
                  Text(
                    t.intervalAfter(
                      (pending!.next?.instant == null
                              ? null
                              : displayStamp(
                                  context,
                                  ref,
                                  pending!.next!.instant!,
                                )) ??
                          t.intervalNoAnchor,
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              VitalButton.secondary(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(t.cancel),
              ),
              VitalButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(t.save),
              ),
            ],
          ),
        );
        if (approved != true) {
          pending = null;
          return;
        }
        command = newCommandId();
      }
      await store.resetIntervalClock(commandId: command!, review: pending!);
      command = null;
      pending = null;
      ref.invalidate(intervalSourcesProvider);
      ref.invalidate(dailyFeedProvider);
      ref.invalidate(nextDailyPlansProvider);
      ref.read(remindersProvider.notifier).refresh();
    } catch (e) {
      if (mounted) {
        setState(() {
          error = e is CommandConflict
              ? AppLocalizations.of(context).conflictFailure
              : AppLocalizations.of(context).saveFailure;
          if (e is CommandConflict) {
            pending = null;
            command = null;
          }
        });
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(t.intervalClockHelp),
        if (error != null) Semantics(liveRegion: true, child: Text(error!)),
        VitalButton.secondary(
          onPressed: busy ? null : recover,
          child: Text(pending == null ? t.review : t.retry),
        ),
      ],
    );
  }
}
