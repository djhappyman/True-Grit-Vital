import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:true_grit_vital/app/app_lock.dart';
import 'package:true_grit_vital/app/storage.dart';
import 'package:true_grit_vital/app/vital_app.dart';
import 'package:true_grit_vital/data/record_store.dart';
import 'package:true_grit_vital/features/events/event_pages.dart';

import 'screen_events_support.dart';
import 'vital_app_test.dart'
    show appTest, launch, settle, tap, waitForText;

final class _TestLock extends AppLockController {
  @override
  AppLockState build() => const AppLockState(ready: true, locked: false);
  void setLocked(bool locked) => state = state.copy(locked: locked);
}

void main() {
  appTest('Events filters the whole collection before paging one status', (
    tester,
  ) async {
    final f = await launch(tester, todayClock: screenEventsNow);
    for (var index = 0; index < 60; index++) {
      final upcoming = index >= 50;
      await screenEvent(
        tester,
        f.store,
        id: 'bulk-${index.toString().padLeft(3, '0')}',
        name: 'Bulk event ${index + 1}',
        type: 'course',
        start: screenEventDay(2026, upcoming ? 12 : 10, 1),
      );
    }
    f.container.read(routerProvider).go('/events');
    await settle(tester);
    await waitForText(tester, '50 active · 10 upcoming · 0 completed');
    expect(find.text('1–50 of 60'), findsOneWidget);
    expect(find.text('Bulk event 1'), findsOneWidget);
    expect(find.text('Bulk event 51'), findsNothing);
    expect(find.text('Next'), findsOneWidget);
    expect(find.text('Upcoming (10)'), findsOneWidget);
    expect(find.text('All (60)'), findsNothing);

    await tap(tester, 'Upcoming (10)');
    await waitForText(tester, 'Bulk event 51');
    expect(find.text('50 active · 10 upcoming · 0 completed'), findsOneWidget);
    expect(find.text('Bulk event 1'), findsNothing);
    expect(find.text('Bulk event 60'), findsOneWidget);
    expect(find.text('1–50 of 60'), findsNothing);
    expect(find.text('Next'), findsNothing);
    expect(find.text('Upcoming (10)'), findsOneWidget);

    await tap(tester, 'All');
    await waitForText(tester, 'Bulk event 1');
    expect(find.text('1–50 of 60'), findsOneWidget);
    expect(find.text('Bulk event 60'), findsNothing);
    expect(find.text('Next'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  appTest('Events keeps an empty filtered page selected and recoverable', (
    tester,
  ) async {
    final f = await launch(tester, todayClock: screenEventsNow);
    await seedScreenEvents(tester, f.store);
    f.container.read(routerProvider).go('/events');
    await settle(tester);
    await waitForText(tester, '2 active · 1 upcoming · 1 completed');

    await tap(tester, 'Review (0)');
    await waitForText(tester, 'No matching events');
    expect(find.text('2 active · 1 upcoming · 1 completed'), findsOneWidget);
    expect(
      find.text('Clear the filter to see the other statuses.'),
      findsOneWidget,
    );
    expect(find.text('Clear'), findsOneWidget);
    expect(find.text('Review (0)'), findsWidgets);
    expect(find.text('All'), findsOneWidget);
    expect(find.textContaining('50 of'), findsNothing);
    expect(
      find.text(
        'Counts and filters cover every saved event, not only this page.',
      ),
      findsOneWidget,
    );

    await tap(tester, 'Clear');
    await waitForText(tester, 'Autumn Immunity & Recovery Cycle');
    expect(find.text('No matching events'), findsNothing);
    expect(find.text('2 active · 1 upcoming · 1 completed'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  appTest('Events updates whole counts after a save while open', (
    tester,
  ) async {
    final f = await launch(tester, todayClock: screenEventsNow);
    await screenEvent(
      tester,
      f.store,
      id: 'live-active',
      name: 'Live active course',
      type: 'course',
      start: screenEventDay(2026, 10, 1),
    );
    f.container.read(routerProvider).go('/events');
    await settle(tester);
    await waitForText(tester, '1 active · 0 upcoming · 0 completed');

    await screenEvent(
      tester,
      f.store,
      id: 'live-upcoming',
      name: 'Live upcoming course',
      type: 'course',
      start: screenEventDay(2026, 12, 1),
    );
    await settle(tester);
    await waitForText(tester, '1 active · 1 upcoming · 0 completed');
    expect(find.text('Live upcoming course'), findsOneWidget);
    expect(find.text('Upcoming (1)'), findsOneWidget);

    await screenEvent(
      tester,
      f.store,
      id: 'live-completed',
      name: 'Live completed course',
      type: 'course',
      start: screenEventDay(2026, 10, 1),
      completed: true,
    );
    await settle(tester);
    await waitForText(tester, '1 active · 1 upcoming · 1 completed');
    expect(find.text('Live completed course'), findsOneWidget);
    expect(find.text('Completed (1)'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('the collection provider stops offering data while locked', () async {
    final dir = await Directory.systemTemp.createTemp('vital-event-lock-');
    final store = await RecordStore.open(
      path: '${dir.path}/lock.db',
      key: List.generate(32, (i) => i + 1),
      isNew: true,
    );
    addTearDown(() async {
      await store.close();
      await dir.delete(recursive: true);
    });
    final command = SaveEventCommand(
      commandId: 'save-locked',
      generation: store.generation,
      expectedRevision: null,
      event: EventRecord(
        id: 'locked-event',
        personId: meId,
        name: 'Locked event',
        eventType: 'course',
        zoneId: 'Europe/London',
        revision: 1,
        plannedStart: screenEventDay(2026, 10, 1),
      ),
    );
    await store.saveEvent(
      command,
      membershipReview: await store.previewEventMembership(command),
    );

    final container = ProviderContainer(
      overrides: [
        recordStoreProvider.overrideWithValue(AsyncData(store)),
        appLockProvider.overrideWith(_TestLock.new),
      ],
    );
    addTearDown(container.dispose);
    final provider = eventCollectionProvider((
      asOf: screenEventsNow(),
      filter: EventCollectionFilter.all,
      offset: 0,
    ));
    final subscription = container.listen(provider, (_, _) {});
    addTearDown(subscription.close);

    final first = await container.read(provider.future);
    expect(first.counts.all, 1);
    final lock = container.read(appLockProvider.notifier) as _TestLock;
    lock.setLocked(true);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    final locked = container.read(provider);
    expect(locked.isLoading, isTrue);
    expect(locked.hasValue && !locked.isLoading, isFalse);

    lock.setLocked(false);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    final unlocked = await container.read(provider.future);
    expect(unlocked.counts.all, 1);
  });
}
