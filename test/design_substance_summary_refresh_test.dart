import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:true_grit_vital/data/record_store.dart';
import 'package:true_grit_vital/features/plans/plan_providers.dart';
import 'package:true_grit_vital/platform/device_zone.dart';

import 'design_substance_summary_fixture.dart';
import 'vital_app_test.dart' show appTest, settle;

CivilDate daysFromNow(int offset) =>
    CivilDate.fromDateTime(DateTime.now().toUtc().add(Duration(days: offset)));

void main() {
  appTest('stock recording and restock refresh the exact balance', (
    tester,
  ) async {
    final fixture = await openSummaryFixture(tester);
    await fixture.plan('main', DailyCount(2, dose('1', 'mg')));
    final container = await fixture.stock(opening: '8');
    await fixture.mount();
    await fixture.waitText('Synthetic vial · 8 mg');

    final restocked = await fixture.restock(container, '2');
    await fixture.waitText('Synthetic vial · 10 mg');
    expect(find.text('Synthetic vial · 8 mg'), findsNothing);

    await fixture.take(restocked, '1');
    await fixture.waitText('Synthetic vial · 9 mg');
    expect(find.text('Synthetic vial · 10 mg'), findsNothing);
    expect(find.text('Planned 2 times a day, 1 mg each'), findsOneWidget);
  });

  appTest('plan edits refresh the stated schedule and next expectation', (
    tester,
  ) async {
    final fixture = await openSummaryFixture(tester);
    final saved = await fixture.plan('main', DailyCount(2, dose('1', 'mg')));
    await fixture.mount();
    await fixture.waitText('Planned 2 times a day, 1 mg each');

    await fixture.plan(
      'main',
      DailyCount(3, dose('2', 'mg')),
      expectedPlanRevision: saved.revision,
    );
    await fixture.waitText('Planned 3 times a day, 2 mg each');
    expect(find.text('Planned 2 times a day, 1 mg each'), findsNothing);
  });

  appTest('pauses render live and resume clears the paused state', (
    tester,
  ) async {
    final fixture = await openSummaryFixture(tester);
    await fixture.plan('main', DailyCount(1, dose('1', 'mg')));
    await fixture.mount();
    await fixture.waitTextContaining('Next planned dose:');
    expect(find.text('Paused'), findsNothing);

    final paused = await fixture.pause('main');
    await fixture.waitText('Paused');
    expect(find.text('Paused'), findsOneWidget);

    await fixture.plan(
      'main',
      DailyCount(1, dose('1', 'mg')),
      expectedPlanRevision: paused.revision,
    );
    await fixture.waitDisappear('Paused');
    expect(find.text('Paused'), findsNothing);
  });

  appTest('successive same-zone observations refresh the resolved rows', (
    tester,
  ) async {
    final zone = StreamController<DeviceZoneObservation>.broadcast();
    addTearDown(zone.close);
    final fixture = await openSummaryFixture(tester, zone: zone.stream);
    await fixture.plan('main', DailyCount(2, dose('1', 'mg')));
    await fixture.mount();
    // Without an observation the follows-local plan stays partial.
    await fixture.waitText('Time zone: Follow local');
    // The first of two same-zone observations resolves the plan.
    zone.add(DeviceZoneObservation.fromId('Europe/London'));
    await fixture.waitText('Time zone: Europe/London');
    await fixture.waitTextContaining('Next planned dose:');

    final scope = FeedScope.person(meId);
    final resolvedBefore = fixture.container
        .read(nextDailyPlansProvider(scope))
        .value;
    expect(resolvedBefore, isNotNull);

    // A fresh observation with the unchanged zone id still makes the plan
    // scheme recompute: the measured evidence that no duplicate timer is
    // needed for foreground minute pulses and resume events (D01 owns those).
    zone.add(DeviceZoneObservation.fromId('Europe/London'));
    final elapsed = Stopwatch()..start();
    DailyPlanNextRows? resolvedAfter;
    while (true) {
      resolvedAfter = fixture.container
          .read(nextDailyPlansProvider(scope))
          .value;
      if (resolvedAfter != null && !identical(resolvedAfter, resolvedBefore)) {
        break;
      }
      if (elapsed.elapsed > const Duration(seconds: 10)) {
        throw TestFailure('The same-zone observation did not refresh rows.');
      }
      await settle(tester);
    }
    await fixture.waitTextContaining('Next planned dose:');
    expect(
      find.textContaining(
        'The device time zone is unavailable. Retry or choose a named home zone.',
      ),
      findsNothing,
    );
  });

  appTest('zone recovery passes through the one-word retry and a real '
      'observation', (tester) async {
    final zone = StreamController<DeviceZoneObservation>.broadcast();
    addTearDown(zone.close);
    var zoneSubscriptions = 0;
    final fixture = await openSummaryFixture(
      tester,
      zone: zone.stream,
      onZoneObserve: () => zoneSubscriptions++,
    );
    await fixture.plan('main', DailyCount(1, dose('1', 'mg')));
    await fixture.mount();
    await fixture.waitText('Time zone: Follow local');
    await fixture.waitTextContaining('The device time zone is unavailable.');
    expect(find.textContaining('Next planned dose:'), findsNothing);
    expect(zoneSubscriptions, 1);

    // The Retry button invalidates the observation stream and re-subscribes;
    // the plan stays partial while the zone remains uncertain.
    await tester.tap(find.text('Retry'));
    final elapsed = Stopwatch()..start();
    while (zoneSubscriptions < 2) {
      if (elapsed.elapsed > const Duration(seconds: 10)) {
        throw TestFailure('The retry did not re-subscribe the observation.');
      }
      await settle(tester);
    }
    await fixture.waitTextContaining('The device time zone is unavailable.');

    // Only a fresh observation resolves the partial rows.
    zone.add(DeviceZoneObservation.fromId('Europe/London'));
    await fixture.waitText('Time zone: Europe/London');
    await fixture.waitTextContaining('Next planned dose:');
    await fixture.waitDisappear(
      'The device time zone is unavailable. Retry or choose a named home zone.',
    );
    expect(zoneSubscriptions, 2);
  });
}
