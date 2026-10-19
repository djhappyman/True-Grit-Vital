import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/device_zone.dart';
import '../../app/storage.dart';
import '../../data/record_store.dart';

final itemPlansProvider = FutureProvider.autoDispose
    .family<List<SavedDailyPlan>, String>(retry: (_, _) => null, (
      ref,
      id,
    ) async {
      return (await ref.watch(recordStoreProvider.future))
          .dailyPlans(itemId: id, limit: 101);
    });

final scopePlansProvider = StreamProvider.autoDispose
    .family<List<SavedDailyPlan>, FeedScope>(retry: (_, _) => null, (
      ref,
      scope,
    ) async* {
      yield* (await ref.watch(recordStoreProvider.future))
          .watchDailyPlans(scope: scope, limit: 101);
    });

final dailyFeedProvider = StreamProvider.autoDispose
    .family<DailyRows, FeedScope>(retry: (_, _) => null, (ref, scope) async* {
      final zone = ref.watch(observedDeviceZoneProvider).value?.zoneId;
      final store = await ref.watch(recordStoreProvider.future);
      yield* store.watchTodayDailyRows(
        scope: scope,
        now: DateTime.now().toUtc(),
        observedZone: zone,
        maxPlans: 100,
        maxRows: 1000,
      );
    });

final nextDailyPlansProvider = StreamProvider.autoDispose
    .family<DailyPlanNextRows, FeedScope>(retry: (_, _) => null, (
      ref,
      scope,
    ) async* {
      final zone = ref.watch(observedDeviceZoneProvider).value?.zoneId;
      yield* (await ref.watch(recordStoreProvider.future)).watchNextDailyPlans(
        scope: scope,
        now: DateTime.now().toUtc(),
        observedZone: zone,
        maxPlans: 100,
        maxVersions: 100,
        maxDates: 366,
      );
    });

final capturedDailyProvider = StreamProvider.autoDispose
    .family<DailyRows, ({FeedScope scope, int offset})>(retry: (_, _) => null, (
      ref,
      query,
    ) async* {
      yield* (await ref.watch(recordStoreProvider.future))
          .watchCapturedDailyRows(
            scope: query.scope,
            limit: 51,
            offset: query.offset,
          );
    });

final phaseDetailsProvider = FutureProvider.autoDispose
    .family<PhasePlan?, ({String plan, String person})>(
      (ref, key) async =>
          (await ref.watch(recordStoreProvider.future))
              .phasePlan(planId: key.plan, personId: key.person),
    );
