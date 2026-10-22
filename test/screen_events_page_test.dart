import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:true_grit_vital/app/vital_app.dart';
import 'package:true_grit_vital/data/record_store.dart';
import 'package:true_grit_vital/ui/vital_ui.dart';

import 'screen_events_support.dart';
import 'vital_app_test.dart'
    show appTest, launch, runIo, settle, tap, waitForText;

void main() {
  appTest('Events shows recorded statuses, full names and date progress', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final f = await launch(tester, todayClock: screenEventsNow);
    await seedScreenEvents(tester, f.store);
    f.container.read(routerProvider).go('/events');
    await settle(tester);
    await waitForText(tester, 'Autumn Immunity & Recovery Cycle');
    expect(find.text('2 active · 1 upcoming · 1 completed'), findsOneWidget);
    expect(find.text('Hypertension Management 2026'), findsOneWidget);
    expect(find.text('Winter Joint Protocol'), findsOneWidget);
    expect(find.text('Summer Endurance Prep'), findsOneWidget);
    expect(find.text('Active (2)'), findsOneWidget);
    expect(find.text('Upcoming (1)'), findsOneWidget);
    expect(find.text('Completed (1)'), findsOneWidget);
    expect(
      find.text('1 Oct 2026 to 30 Nov 2026 · Day 24 of 61'),
      findsOneWidget,
    );
    expect(find.text('38% elapsed'), findsOneWidget);
    expect(find.text('Telmisartan'), findsOneWidget);
    expect(find.text('Vitamin D3 + K2'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  appTest('Events status filters narrow the loaded collection truthfully', (
    tester,
  ) async {
    final f = await launch(tester, todayClock: screenEventsNow);
    await seedScreenEvents(tester, f.store);
    f.container.read(routerProvider).go('/events');
    await settle(tester);
    await waitForText(tester, 'Hypertension Management 2026');
    expect(find.text('No matching events'), findsNothing);
    await tap(tester, 'Active (2)');
    expect(find.text('Hypertension Management 2026'), findsOneWidget);
    expect(find.text('Autumn Immunity & Recovery Cycle'), findsOneWidget);
    expect(find.text('Winter Joint Protocol'), findsNothing);
    expect(find.text('Summer Endurance Prep'), findsNothing);
    await tap(tester, 'Completed (1)');
    expect(find.text('Summer Endurance Prep'), findsOneWidget);
    expect(find.text('Hypertension Management 2026'), findsNothing);
    await tap(tester, 'Upcoming (1)');
    expect(find.text('Winter Joint Protocol'), findsOneWidget);
    expect(find.text('Summer Endurance Prep'), findsNothing);
    await tap(tester, 'All');
    expect(find.text('Hypertension Management 2026'), findsOneWidget);
    expect(find.text('Summer Endurance Prep'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  appTest('Events More opens canonical notes and revisions', (tester) async {
    final f = await launch(tester, todayClock: screenEventsNow);
    await seedScreenEvents(tester, f.store);
    final before = (await runIo(tester, f.store.events))!.length;
    f.container.read(routerProvider).go('/events');
    await settle(tester);
    await waitForText(tester, 'Hypertension Management 2026');
    final more = find.byKey(const ValueKey('screen-events-more-b-autumn'));
    await tester.ensureVisible(more);
    await settle(tester);
    await tester.tap(more);
    await settle(tester);
    final autumn = find.byKey(const ValueKey('screen-events-card-b-autumn'));
    expect(
      find.descendant(of: autumn, matching: find.text('Note')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: autumn, matching: find.text('Revisions')),
      findsOneWidget,
    );
    await tap(tester, 'Note');
    await waitForText(tester, 'Notes');
    expect(
      f.container.read(routerProvider).routerDelegate.state.uri.path,
      '/event/b-autumn/edit',
    );
    expect(
      find.text(
        'Private event notes. Included in event reports only when notes are selected.',
      ),
      findsOneWidget,
    );
    expect((await runIo(tester, f.store.events))!.length, before);
    expect(tester.takeException(), isNull);
  });

  appTest('Events exposes end review only when an event end is due', (
    tester,
  ) async {
    final f = await launch(tester, todayClock: screenEventsNow);
    await seedEndedScreenEvent(tester, f.store);
    f.container.read(routerProvider).go('/events');
    await settle(tester);
    await waitForText(tester, 'Ended Review Course');
    expect(find.text('End review due'), findsOneWidget);
    expect(find.textContaining('Day '), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    await tap(tester, 'Review');
    await waitForText(tester, 'End review');
    expect(
      f.container.read(routerProvider).routerDelegate.state.uri.path,
      '/event/ended-review/review',
    );
    expect(find.text('Taken'), findsNothing);
    expect(find.text('Snooze'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  appTest('Events completed cards offer revisions and no due review', (
    tester,
  ) async {
    final f = await launch(tester, todayClock: screenEventsNow);
    await seedScreenEvents(tester, f.store);
    f.container.read(routerProvider).go('/events');
    await settle(tester);
    await waitForText(tester, 'Summer Endurance Prep');
    expect(find.text('End review due'), findsNothing);
    final card = find.byKey(const ValueKey('screen-events-card-d-summer'));
    expect(
      find.descendant(of: card, matching: find.text('Revisions')),
      findsOneWidget,
    );
    final primary = find.byKey(
      const ValueKey('screen-events-primary-d-summer'),
    );
    await tester.ensureVisible(primary);
    await settle(tester);
    await tester.tap(primary);
    await waitForText(tester, 'Revisions');
    expect(
      f.container.read(routerProvider).routerDelegate.state.uri.path,
      '/event/d-summer/revisions',
    );
    expect(tester.takeException(), isNull);
  });

  appTest('Events counts the whole collection and filters before paging', (
    tester,
  ) async {
    final f = await launch(tester, todayClock: screenEventsNow);
    for (var index = 0; index < 51; index++) {
      await screenEvent(
        tester,
        f.store,
        id: 'bulk-${index.toString().padLeft(2, '0')}',
        name: 'Bulk event ${index + 1}',
        type: 'cycle',
        start: screenEventDay(2026, 10, 1),
      );
    }
    f.container.read(routerProvider).go('/events');
    await settle(tester);
    await waitForText(tester, '51 active · 0 upcoming · 0 completed');
    expect(find.text('51 active · 0 upcoming · 0 completed'), findsOneWidget);
    expect(
      find.text(
        'Counts and filters cover every saved event, not only this page.',
      ),
      findsOneWidget,
    );
    expect(find.text('1–50 of 51'), findsOneWidget);
    expect(find.text('50 shown'), findsNothing);
    expect(find.text('Filters only cover the events shown.'), findsNothing);
    expect(find.text('Next'), findsOneWidget);
    await tap(tester, 'Next');
    await waitForText(tester, 'Bulk event 51');
    expect(find.text('51–51 of 51'), findsOneWidget);
    expect(find.text('Previous'), findsOneWidget);
    expect(find.text('Next'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  appTest('Events warns when a recorded date cannot resolve timing', (
    tester,
  ) async {
    final f = await launch(tester, todayClock: screenEventsNow);
    await screenEvent(
      tester,
      f.store,
      id: 'partial-date',
      name: 'Partial Date Course',
      type: 'prescription',
      start: EventDate(precision: EventDatePrecision.month, value: '2026-10'),
    );
    f.container.read(routerProvider).go('/events');
    await settle(tester);
    await waitForText(tester, 'Partial Date Course');
    expect(find.text('Dates need review'), findsOneWidget);
    expect(find.text('Active (1)'), findsNothing);
    expect(find.text('Review (1)'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  appTest('Events labels end-only dates and never assumes an active phase', (
    tester,
  ) async {
    final f = await launch(tester, todayClock: screenEventsNow);
    await screenEvent(
      tester,
      f.store,
      id: 'end-only',
      name: 'End-only course',
      type: 'prescription',
      start: null,
      end: screenEventDay(2026, 11, 30),
    );
    f.container.read(routerProvider).go('/events');
    await settle(tester);
    await waitForText(tester, 'End-only course');
    expect(find.text('Ends 30 Nov 2026'), findsOneWidget);
    expect(find.text('Review (1)'), findsOneWidget);
    expect(find.text('Active (1)'), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });

  appTest('Events refreshes time-based status while left open', (tester) async {
    var now = DateTime.utc(2026, 10, 23, 22, 59);
    final f = await launch(tester, todayClock: () => now);
    await screenEvent(
      tester,
      f.store,
      id: 'rollover',
      name: 'Rollover course',
      type: 'cycle',
      start: screenEventDay(2026, 10, 24),
    );
    f.container.read(routerProvider).go('/events');
    await settle(tester);
    await waitForText(tester, 'Upcoming (1)');
    now = now.add(const Duration(minutes: 1));
    await tester.pump(const Duration(minutes: 1));
    await settle(tester);
    expect(find.text('Active (1)'), findsOneWidget);
    expect(find.text('Upcoming (1)'), findsNothing);
  });

  appTest('Events keeps full names and 48px targets at 320px double text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 740);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(() {
      tester.view.reset();
      tester.platformDispatcher.clearTextScaleFactorTestValue();
    });
    final f = await launch(tester, todayClock: screenEventsNow);
    await seedScreenEvents(tester, f.store);
    f.container.read(routerProvider).go('/events');
    await settle(tester);
    await waitForText(tester, 'Autumn Immunity & Recovery Cycle');
    expect(find.text('Autumn Immunity & Recovery Cycle'), findsOneWidget);
    expect(find.text('Hypertension Management 2026'), findsOneWidget);
    for (final key in const [
      'screen-events-more-b-autumn',
      'screen-events-select-b-autumn',
      'screen-events-primary-b-autumn',
    ]) {
      final target = find.byKey(ValueKey(key));
      expect(target, findsOneWidget);
      final size = tester.getSize(target);
      expect(size.width, greaterThanOrEqualTo(48));
      expect(size.height, greaterThanOrEqualTo(48));
    }
    expect(tester.takeException(), isNull);
  });

  appTest('Event detail keeps full names and actions at 320px double text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 740);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(() {
      tester.view.reset();
      tester.platformDispatcher.clearTextScaleFactorTestValue();
    });
    final f = await launch(tester, todayClock: screenEventsNow);
    await seedScreenEvents(tester, f.store);
    f.container.read(routerProvider).go('/event/b-autumn');
    await settle(tester);
    await waitForText(tester, 'Autumn Immunity & Recovery Cycle');
    expect(find.text('Autumn Immunity & Recovery Cycle'), findsOneWidget);
    expect(find.text('Back'), findsOneWidget);
    expect(
      tester.getSize(find.widgetWithText(VitalButton, 'Back')).height,
      greaterThanOrEqualTo(48),
    );
    expect(find.text('Dates'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  appTest(
    'Event detail keeps dates, items and history with a safe back route',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final f = await launch(tester, todayClock: screenEventsNow);
      await seedScreenEvents(tester, f.store);
      f.container.read(routerProvider).go('/event/b-autumn');
      await settle(tester);
      await waitForText(tester, 'Autumn Immunity & Recovery Cycle');
      expect(find.text('Dates'), findsOneWidget);
      expect(find.textContaining('1 Oct 2026 to 30 Nov 2026'), findsWidgets);
      expect(find.text('Europe/London'), findsWidgets);
      expect(find.textContaining('Day 24 of 61'), findsOneWidget);
      expect(find.text('Event items'), findsOneWidget);
      expect(find.text('History'), findsOneWidget);
      expect(find.textContaining('Membership:'), findsNWidgets(3));
      expect(find.text('Me'), findsNothing);
      expect(find.text('Back'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
