import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/device_zone.dart';
import '../../app/storage.dart';
import '../../data/record_store.dart';
import 'dashboard_week.dart';

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

/// One selected civil day. Day bounds are resolved by the store from the
/// display zone, so browsing never shifts a date through local-midnight
/// arithmetic and daylight-saving days keep their real length.
final dailyDayFeedProvider = StreamProvider.autoDispose
    .family<DailyRows, ({FeedScope scope, CivilDate day})>(
      retry: (_, _) => null,
      (ref, query) async* {
        final zone = ref.watch(observedDeviceZoneProvider).value?.zoneId;
        final store = await ref.watch(recordStoreProvider.future);
        yield* store.watchDailyRows(
          scope: query.scope,
          from: query.day,
          toExclusive: query.day.addDays(1),
          observedZone: zone,
          maxPlans: 100,
          maxRows: 1000,
        );
      },
    );

/// The Monday-based week containing the browsed day. Counts stay a projection
/// of real expectations and actions; a bounded result keeps [DailyRows.complete]
/// false instead of presenting a partial week as whole.
final dailyWeekFeedProvider = StreamProvider.autoDispose
    .family<DailyRows, ({FeedScope scope, CivilDate weekStart})>(
      retry: (_, _) => null,
      (ref, query) async* {
        final zone = ref.watch(observedDeviceZoneProvider).value?.zoneId;
        final store = await ref.watch(recordStoreProvider.future);
        yield* store.watchDailyRows(
          scope: query.scope,
          from: query.weekStart,
          toExclusive: query.weekStart.addDays(7),
          observedZone: zone,
          maxPlans: 100,
          maxRows: 1000,
        );
      },
    );

/// Every saved plan for the current scope, paged to the store's limit rather
/// than the bounded dashboard card query. Quick-record configuration uses the
/// complete collection and reports a capped read as incomplete.
final allScopePlansProvider = FutureProvider.autoDispose
    .family<DashboardPlanCollection, FeedScope>((ref, scope) async {
      // Any plan commit refreshes this projection, including changes beyond
      // the dashboard's first bounded page.
      ref.watch(scopePlansProvider(scope));
      final store = await ref.watch(recordStoreProvider.future);
      const pageSize = 500, maxPlans = 5000;
      final plans = <SavedDailyPlan>[];
      for (var offset = 0; offset < maxPlans; offset += pageSize) {
        final page = await store.dailyPlans(
          scope: scope,
          limit: pageSize,
          offset: offset,
        );
        plans.addAll(page);
        if (page.length < pageSize) {
          return DashboardPlanCollection(
            plans: List.unmodifiable(plans),
            complete: true,
          );
        }
      }
      return DashboardPlanCollection(
        plans: List.unmodifiable(plans),
        complete: false,
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
