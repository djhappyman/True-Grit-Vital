import '../../ui/stitch_ui.dart';
import '../../ui/vital_ui.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../app/app_lock.dart';
import '../../app/display_preferences.dart';
import '../../app/storage.dart';
import '../../data/record_store.dart';
import '../../l10n/app_localizations.dart';
import '../profiles/profile_pages.dart';
import '../plans/interval_review.dart';
import '../recording/record_pages.dart';

typedef HistorySourceKey = ({String id, String personId});
final historySourceProvider = StreamProvider.autoDispose
    .family<TimelineEntry?, HistorySourceKey>(retry: (_, _) => null, (
      ref,
      key,
    ) async* {
      if (ref.watch(appLockProvider.select((s) => s.locked))) {
        yield null;
        return;
      }
      final store = await ref.watch(recordStoreProvider.future);
      await for (final _ in store.watchTimeline(
        TimelineQuery(
          filter: TimelineFilter(scope: FeedScope.person(key.personId)),
          displayZone: 'UTC',
          limit: 1,
        ),
      )) {
        yield await store.historyEntry(
          TimelineEntryId.parse(key.id),
          personId: key.personId,
        );
      }
    });
final historySkipSourceProvider = FutureProvider.autoDispose
    .family<DailyActionSource?, HistorySourceKey>(retry: (_, _) => null, (
      ref,
      key,
    ) async {
      if (ref.watch(appLockProvider.select((s) => s.locked))) return null;
      return (await ref.watch(recordStoreProvider.future)).dailyActionSource(
        TimelineEntryId.parse(key.id).value,
        personId: key.personId,
      );
    });
final historySkipAuditProvider = FutureProvider.autoDispose
    .family<List<Map<String, Object?>>, String>(retry: (_, _) => null, (
      ref,
      id,
    ) async {
      if (ref.watch(appLockProvider.select((s) => s.locked))) return [];
      return (await ref.watch(recordStoreProvider.future)).dailyActionAudit(id);
    });

class HistorySourcePage extends ConsumerWidget {
  const HistorySourcePage({
    super.key,
    required this.id,
    required this.personId,
    this.returnLocation = '/history',
  });
  final TimelineEntryId id;
  final String personId, returnLocation;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context),
        key = (id: id.sortKey, personId: personId);
    final result = ref.watch(historySourceProvider(key)),
        preference = ref.watch(displayPreferencesProvider),
        zone = ref.watch(displayZoneProvider),
        people = ref.watch(profilesProvider);
    final formatter = displayFormatter(context, preference.timeFormat);
    final owner = people.value?.where((p) => p.id == personId).firstOrNull;
    final entry = result.value;
    return EntryPage(
      children: [
        Heading(t.historyInspection),
        Text(t.profileOwner(ownerLabel(ref, t, personId))),
        if (result.isLoading) Text(t.loadingRecords),
        if (result.hasError) ...[
          Text(t.historyLoadFailed),
          VitalButton.secondary(
            onPressed: () => ref.invalidate(historySourceProvider(key)),
            child: Text(t.retry),
          ),
        ],
        if (entry != null) ...[
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: VitalBadge(
              switch (entry.status) {
                TimelineEntryStatus.recorded => t.statusRecorded,
                TimelineEntryStatus.skipped => t.statusSkipped,
                TimelineEntryStatus.voided => t.statusVoided,
              },
              tone: entry.status == TimelineEntryStatus.recorded
                  ? VitalTone.positive
                  : entry.status == TimelineEntryStatus.skipped
                  ? VitalTone.warning
                  : VitalTone.neutral,
              compact: true,
            ),
          ),
          const SizedBox(height: 8),
          StitchSurface(
            inset: true,
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (entry.dateOnly)
                  Text(
                    t.historyDateZone(
                      formatter.date(
                        DisplayTime().instant(
                          entry.occurredAt,
                          entry.planZone ?? zone,
                        ),
                        full: true,
                      ),
                      entry.planZone ?? zone,
                    ),
                  )
                else ...[
                  Text(
                    formatter.format(
                      DisplayTime().instant(entry.occurredAt, zone),
                      includeSeconds: true,
                      includeOffset: true,
                    ),
                  ),
                  Text(
                    t.shownInZone(
                      DisplayTime().instant(entry.occurredAt, zone).zoneId,
                    ),
                  ),
                  Text(
                    t.historyExactInstant(entry.occurredAt.toIso8601String()),
                  ),
                ],
              ],
            ),
          ),
          if (entry is RecordTimelineEntry) ...[
            RecordCard(record: entry.record, showActions: false),
            if (owner != null && !owner.isArchived && !entry.record.isVoided)
              IntervalRecordChoices(record: entry.record),
            if (entry.planContext != null)
              Text(
                entry.planContext!.planName != null ||
                        entry.planContext!.itemName != null
                    ? t.historyPlanCaptured(
                        entry.planContext!.planName ??
                            entry.planContext!.itemName!,
                      )
                    : t.historyCapturedPlan,
              )
            else ...[
              Heading(t.historyNoCapturedPlan),
              Text(t.historyDoseNoPlanBody),
            ],
          ],
          if (entry is CombinedTimelineEntry) ...[
            Text(t.combinedHistoryHelp),
            for (final component in entry.components) ...[
              RecordCard(record: component.record, showActions: false),
              if (owner != null &&
                  !owner.isArchived &&
                  !component.record.isVoided)
                IntervalRecordChoices(record: component.record),
            ],
          ],
          if (entry is! SkippedTimelineEntry &&
              owner != null &&
              !owner.isArchived)
            VitalButton.secondary(
              onPressed: () => context.push(
                Uri(
                  path: entry is CombinedTimelineEntry
                      ? '/combined/$personId/edit/${entry.actionId}'
                      : '/correct/${(entry as RecordTimelineEntry).record.id}',
                  queryParameters: {
                    'person': personId,
                    'return': returnLocation,
                  },
                ).toString(),
              ),
              child: Text(t.correct),
            ),
          if (entry is RecordTimelineEntry)
            VitalButton.secondary(
              onPressed: () => context.push(
                '/revisions/${entry.record.id}?person=$personId',
              ),
              child: Text(t.history),
            ),
          if (entry is CombinedTimelineEntry)
            for (final component in entry.components)
              VitalButton.secondary(
                multiline: true,
                onPressed: () => context.push(
                  '/revisions/${component.record.id}?person=$personId',
                ),
                child: Text(component.record.name),
              ),
        ],
        if (id.kind == TimelineEntryKind.skipped)
          ref
              .watch(historySkipSourceProvider(key))
              .when(
                data: (source) {
                  if (source == null) return Text(t.historyUnknownSource);
                  final expectation = source.context.expectation;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(source.context.itemName ?? t.historyInspection),
                      Text(t.historySkippedHelp),
                      Text(
                        t.historyPlannedAmount(
                          expectation.amount.enteredText,
                          expectation.amount.unit,
                        ),
                      ),
                      Text(
                        t.historyPlannedDate(
                          (expectation.effectiveDate ??
                                  expectation.identity.originalDate)
                              .toString(),
                        ),
                      ),
                      Text(t.plannedInZone(expectation.zoneId)),
                      if (expectation.instant == null) Text(t.dateOnly),
                      if (source.action.isUndone) Text(t.undone),
                      if (source.action.reason != null)
                        Text(
                          t.featureContextSkipReasonValue(
                            source.action.reason!,
                          ),
                        ),
                      Text(
                        t.historyPlanCaptured(
                          source.context.planName ?? t.historyNoCapturedPlan,
                        ),
                      ),
                      Heading(t.historySkipAudit),
                      ref
                          .watch(historySkipAuditProvider(id.value))
                          .when(
                            data: (rows) => Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                for (final row in rows)
                                  Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        t.historyActionRevision(
                                          (row['revision'] as int?) ?? 0,
                                          row['kind'] == 'skip'
                                              ? t.statusSkipped
                                              : row['kind'] == 'take'
                                              ? t.statusRecorded
                                              : t.undone,
                                          formatter.format(
                                            DisplayTime().instant(
                                              DateTime.fromMicrosecondsSinceEpoch(
                                                (row['recorded_at'] as int?) ??
                                                    0,
                                                isUtc: true,
                                              ),
                                              zone,
                                            ),
                                            includeSeconds: true,
                                            includeOffset: true,
                                          ),
                                        ),
                                      ),
                                      if (row['reason']
                                          case final String reason)
                                        Text(
                                          t.featureContextSkipReasonValue(
                                            reason,
                                          ),
                                        ),
                                    ],
                                  ),
                              ],
                            ),
                            error: (_, _) => Text(t.historyLoadFailed),
                            loading: () => Text(t.loadingRecords),
                          ),
                    ],
                  );
                },
                error: (_, _) => Text(t.historyLoadFailed),
                loading: () => Text(t.loadingRecords),
              ),
        if (entry == null &&
            !result.isLoading &&
            id.kind != TimelineEntryKind.skipped)
          Text(t.historyUnknownSource),
      ],
    );
  }
}
