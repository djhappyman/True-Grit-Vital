import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../app/app_lock.dart';
import '../../app/storage.dart';
import '../../data/record_store.dart';
import '../../l10n/app_localizations.dart';
import '../../ui/vital_ui.dart';

final eventUseSummaryProvider = StreamProvider.autoDispose
    .family<EventUseSummary?, String>(retry: (_, _) => null, (ref, id) async* {
      if (ref.watch(appLockProvider.select((s) => s.locked))) {
        yield null;
        return;
      }
      yield* (await ref.watch(recordStoreProvider.future))
          .watchEventUseSummary(id);
    });

class EventSummaryFacts extends ConsumerWidget {
  const EventSummaryFacts({
    super.key,
    required this.event,
    this.compact = false,
  });
  final EventRecord event;
  final bool compact;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    return ref
        .watch(eventUseSummaryProvider(event.id))
        .when(
          skipLoadingOnReload: false,
          data: (summary) {
            if (summary == null) {
              return const SizedBox.shrink();
            }
            if (summary.eventRevision != event.revision) {
              return Text(t.loadingRecords);
            }
            if (summary.boundsNeedReview) {
              return Text(t.featureEventsCountsReview);
            }
            if (compact) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    t.featureEventsCounts(summary.recorded!, summary.skipped!),
                    style: VitalType.metadata,
                  ),
                  if (summary.skippedTimesNeedReview)
                    Text(
                      t.featureEventsSkippedReview,
                      style: VitalType.metadata,
                    ),
                ],
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: 24,
                  runSpacing: 12,
                  children: [
                    VitalMetric(
                      label: t.featureEventsRecorded,
                      value: '${summary.recorded}',
                    ),
                    VitalMetric(
                      label: t.featureEventsSkipped,
                      value: '${summary.skipped}',
                    ),
                    VitalMetric(
                      label: t.featureEventsLinked,
                      value: '${summary.substances}',
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(t.featureEventsCountsHelp, style: VitalType.metadata),
                if (summary.skippedTimesNeedReview)
                  Text(t.featureEventsSkippedReview, style: VitalType.metadata),
              ],
            );
          },
          loading: () => Text(t.loadingRecords, style: VitalType.metadata),
          error: (_, _) => Wrap(
            spacing: 8,
            children: [
              Text(t.featureEventsCountsFailed),
              VitalButton.secondary(
                onPressed: () =>
                    ref.invalidate(eventUseSummaryProvider(event.id)),
                child: Text(t.retry),
              ),
            ],
          ),
        );
  }
}

class EventNotes extends StatefulWidget {
  const EventNotes({super.key, required this.notes});
  final String notes;
  @override
  State<EventNotes> createState() => _EventNotesState();
}

class _EventNotesState extends State<EventNotes> {
  bool open = false;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: Semantics(
          expanded: open,
          child: VitalButton.secondary(
            onPressed: () => setState(() => open = !open),
            child: Text(AppLocalizations.of(context).featureEventsNotes),
          ),
        ),
      ),
      VitalReveal(
        expanded: open,
        child: VitalPanel(
          title: AppLocalizations.of(context).featureEventsNotes,
          children: [Text(widget.notes)],
        ),
      ),
    ],
  );
}
