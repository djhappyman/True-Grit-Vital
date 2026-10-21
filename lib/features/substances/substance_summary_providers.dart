import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/storage.dart';
import '../../data/record_store.dart';

/// Anchors live summary reads on one person's one substance.
typedef SubstanceSummaryAnchor = ({String personId, String itemId});

/// Plan budget shared with the plan lists. A truncated scope is disclosed as
/// incomplete instead of silently dropping schedule facts.
const summaryPlanLimit = 101;

/// Container budget shared with the stock lists; more containers stay
/// disclosed. This is a page, never a per-row history scan.
const summaryStockLimit = 51;

/// Compact summaries show the first few containers; detailed summaries grow
/// to the streamed [summaryStockLimit] page and still disclose anything
/// beyond it, so no container silently disappears.
const summaryStockLines = 4;

/// Live plans for one substance: edits, versions, pauses and resumes re-emit.
final summaryPlansProvider = StreamProvider.autoDispose
    .family<List<SavedDailyPlan>, SubstanceSummaryAnchor>(
      retry: (_, _) => null,
      (ref, anchor) async* {
        yield* (await ref.watch(recordStoreProvider.future)).watchDailyPlans(
          scope: FeedScope.person(anchor.personId),
          itemId: anchor.itemId,
          limit: summaryPlanLimit,
        );
      },
    );

/// Live stock containers for one substance: recording, measuring and restock
/// re-emit with the exact per-container balance.
final summaryStockProvider = StreamProvider.autoDispose
    .family<List<StoredStockContainer>, SubstanceSummaryAnchor>(
      retry: (_, _) => null,
      (ref, anchor) async* {
        yield* (await ref.watch(recordStoreProvider.future))
            .watchStockContainers(
              personId: anchor.personId,
              itemId: anchor.itemId,
              limit: summaryStockLimit,
            );
      },
    );
