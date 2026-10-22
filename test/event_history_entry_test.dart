import 'dart:io';
import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:true_grit_vital/app/app_lock.dart';
import 'package:true_grit_vital/app/appearance.dart';
import 'package:true_grit_vital/app/history.dart';
import 'package:true_grit_vital/app/vital_app.dart';
import 'package:true_grit_vital/data/record_store.dart';
import 'package:true_grit_vital/features/events/event_history_location.dart';
import 'package:true_grit_vital/features/events/event_pages.dart'
    show eventLookupProvider;
import 'package:true_grit_vital/features/history/history_pages.dart';
import 'package:true_grit_vital/features/recording/record_pages.dart';

import 'private_drafts_ui_test.dart' show FakeAuth;
import 'vital_app_test.dart'
    show appTest, launch, runIo, settle, tap, waitForText;

const captureDirectory = String.fromEnvironment('VITAL_EVENT_HISTORY_CAPTURE');

DateTime _now() => DateTime.utc(2026, 10, 22, 12);

EventDate _day(int month, int day) =>
    EventDate.day(CivilDate(2026, month, day));

Future<SubstanceItem> _item(
  WidgetTester tester,
  RecordStore store,
  String name, {
  String unit = 'mg',
}) async => (await runIo(
  tester,
  () => store.createItem(
    commandId: newCommandId(),
    expectedPersonRevision: 2,
    name: name,
    form: 'Tablet',
    unit: unit,
    type: 'Medicine',
  ),
))!;

Future<EventRecord> _event(
  WidgetTester tester,
  RecordStore store, {
  required String id,
  required String name,
  required SubstanceItem item,
  EventDate? plannedStart,
  EventDate? plannedEnd,
  EventDate? actualStart,
  EventDate? actualEnd,
  bool completed = false,
  DateTime? membershipFrom,
}) async {
  final event = EventRecord(
    id: id,
    personId: meId,
    name: name,
    eventType: 'cycle',
    zoneId: 'Europe/London',
    revision: 1,
    plannedStart: plannedStart,
    plannedEnd: plannedEnd,
    actualStart: actualStart,
    actualEnd: actualEnd,
    completed: completed,
    memberships: [
      EventMembership(
        id: 'member-$id',
        itemId: item.id,
        personId: meId,
        effectiveFrom: membershipFrom ?? DateTime.utc(2026, 1, 1),
        revision: 1,
      ),
    ],
  );
  return (await runIo(tester, () async {
    final command = SaveEventCommand(
      commandId: newCommandId(),
      generation: store.generation,
      expectedRevision: null,
      expectedPersonRevision: (await store.profileById(meId))!.revision,
      event: event,
    );
    return store.saveEvent(
      command,
      membershipReview: await store.previewEventMembership(command),
    );
  }))!;
}

Future<UseRecord> _record(
  WidgetTester tester,
  RecordStore store,
  SubstanceItem item,
  DateTime actualAt,
) async => (await runIo(
  tester,
  () => store.record(
    commandId: newCommandId(),
    itemId: item.id,
    expectedPersonRevision: 2,
    amount: '1',
    actualAt: actualAt,
  ),
))!;

Future<UseRecord> _void(
  WidgetTester tester,
  RecordStore store,
  UseRecord record,
) async => (await runIo(
  tester,
  () => store.voidRecord(
    commandId: newCommandId(),
    recordId: record.id,
    expectedRevision: record.revision,
    expectedPersonRevision: 2,
  ),
))!;

Future<void> _skip(
  WidgetTester tester,
  RecordStore store,
  SubstanceItem item,
  CivilDate day,
) async {
  await runIo(tester, () async {
    await store.saveDailyPlan(
      commandId: newCommandId(),
      expectedPersonRevision: 2,
      expectedGeneration: store.generation,
      plan: DailyPlanVersion(
        personId: meId,
        planId: 'plan-${item.id}',
        itemId: item.id,
        versionId: 'version-${item.id}',
        start: CivilDate(2026, 9, 1),
        timing: DailyCount(
          1,
          PlannedAmount(quantity: ExactQuantity.parse('1'), unit: item.unit),
        ),
        zoneBasis: FixedHome('Europe/London'),
      ),
    );
    final rows = await store.dailyRows(
      from: day,
      toExclusive: day.addDays(1),
      observedZone: 'Europe/London',
    );
    await store.actDaily(
      commandId: newCommandId(),
      row: rows.rows.single,
      kind: DailyActionKind.skip,
    );
  });
}

Future<void> _revealHistoryCommand(WidgetTester tester) async {
  final command = find.byKey(const ValueKey('event-history-open'));
  final heading = find.text('History');
  if (heading.evaluate().isNotEmpty) {
    await Scrollable.ensureVisible(
      tester.element(heading.first),
      alignment: 0.1,
    );
    await settle(tester);
  }
  for (var attempt = 0; attempt < 3; attempt++) {
    if (command.hitTestable().evaluate().isNotEmpty) return;
    await Scrollable.ensureVisible(tester.element(command), alignment: 0.5);
    await settle(tester);
  }
  expect(command.hitTestable(), findsOneWidget);
}

Future<void> _openHistory(
  WidgetTester tester,
  ProviderContainer container,
  String eventName,
) async {
  final command = find.byKey(const ValueKey('event-history-open'));
  await _revealHistoryCommand(tester);
  await tester.tap(command);
  await settle(tester);
  if (container.read(routerProvider).routerDelegate.state.uri.path !=
      '/history') {
    await _revealHistoryCommand(tester);
    await tester.tap(command);
    await settle(tester);
  }
  expect(
    container.read(routerProvider).routerDelegate.state.uri.path,
    '/history',
  );
  await waitForText(tester, eventName);
}

Future<void> _toggleFilters(WidgetTester tester) async {
  final done = find.text('Done');
  if (done.evaluate().isNotEmpty) {
    await tester.ensureVisible(done.last);
    await settle(tester);
    await tester.tap(done.last);
    await settle(tester);
    return;
  }
  final target = find.byKey(const ValueKey('history-filters-toggle'));
  await tester.ensureVisible(target);
  await settle(tester);
  await tester.tap(target);
  await settle(tester);
}

Future<void> _selectStatus(WidgetTester tester, String label) async {
  final status = find.descendant(
    of: find.byKey(const ValueKey('history-status')),
    matching: find.text(label),
  );
  await tester.ensureVisible(status);
  await settle(tester);
  await tester.tap(status);
  await settle(tester);
}

HistoryController _history(ProviderContainer container) {
  final location = container
      .read(routerProvider)
      .routerDelegate
      .state
      .uri
      .toString();
  return container.read(historyControllerProvider(location).notifier);
}

List<TimelineEntryStatus> _entryStatuses(WidgetTester tester) => [
  for (final card in tester.widgetList<HistoryEntryCard>(
    find.byType(HistoryEntryCard),
  ))
    card.entry.status,
];

Future<void> _capture(WidgetTester tester, GlobalKey key, String name) async {
  if (captureDirectory.isEmpty) return;
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('$captureDirectory/$name.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

void main() {
  setUpAll(() async {
    if (captureDirectory.isEmpty) return;
    await (FontLoader('StitchSans')
          ..addFont(rootBundle.load('assets/fonts/StitchNotoSans-Regular.ttf'))
          ..addFont(rootBundle.load('assets/fonts/StitchNotoSans-Medium.ttf'))
          ..addFont(rootBundle.load('assets/fonts/StitchNotoSans-SemiBold.ttf'))
          ..addFont(rootBundle.load('assets/fonts/StitchNotoSans-Bold.ttf')))
        .load();
    await (FontLoader('NotoSans')
          ..addFont(rootBundle.load('assets/fonts/NotoSans-Regular.ttf'))
          ..addFont(rootBundle.load('assets/fonts/NotoSans-Bold.ttf')))
        .load();
    await (FontLoader('packages/shadcn_flutter/LucideIcons')..addFont(
          rootBundle.load('packages/shadcn_flutter/lib/icons/LucideIcons.ttf'),
        ))
        .load();
  });

  group('event History location', () {
    test('uses the single-user scope, one exact event and no date bounds', () {
      final uri = Uri.parse(eventHistoryLocation(eventId: 'event/a b?c&d#e=f'));
      expect(uri.path, '/history');
      expect(uri.queryParameters['scope'], meId);
      expect(uri.queryParameters['event'], 'event/a b?c&d#e=f');
      expect(uri.queryParameters, isNot(contains('from')));
      expect(uri.queryParameters, isNot(contains('before')));
      expect(uri.queryParameters, isNot(contains('type')));
      expect(uri.queryParameters, isNot(contains('status')));
      expect(uri.queryParameters, isNot(contains('item')));
      expect(uri.queryParameters, isNot(contains('unit')));
      expect(uri.queryParameters, isNot(contains('anchor')));
    });

    test('keeps a local return location encoded in the seed', () {
      const returnLocation = '/event/event%2Fa%20b?tab=2';
      final uri = Uri.parse(
        eventHistoryLocation(
          eventId: 'event/a b',
          returnLocation: returnLocation,
        ),
      );
      expect(uri.queryParameters['event'], 'event/a b');
      expect(uri.queryParameters['return'], returnLocation);
      expect(uri.queryParameters['scope'], meId);
      expect(uri.queryParameters, isNot(contains('from')));
      expect(uri.queryParameters, isNot(contains('before')));
    });
  });

  appTest(
    'event History opens exact linked recorded, skipped and voided entries',
    (tester) async {
      final f = await launch(tester, todayClock: _now);
      final eventItem = await _item(tester, f.store, 'Autumn medicine');
      final otherItem = await _item(tester, f.store, 'Other medicine');
      final event = await _event(
        tester,
        f.store,
        id: 'autumn-course',
        name: 'Autumn Recovery Course',
        item: eventItem,
        plannedStart: _day(10, 1),
        plannedEnd: _day(10, 10),
        actualStart: _day(9, 25),
        actualEnd: _day(10, 30),
        completed: true,
        membershipFrom: DateTime.utc(2026, 9, 1),
      );
      final other = await _event(
        tester,
        f.store,
        id: 'other-course',
        name: 'Other Course',
        item: otherItem,
        plannedStart: _day(10, 1),
        plannedEnd: _day(10, 31),
        actualStart: _day(10, 1),
        actualEnd: _day(10, 31),
        completed: true,
      );
      // Two entries sit outside the planned dates but inside the explicitly
      // recorded actual dates. Membership, not the plan, links them.
      await _record(tester, f.store, eventItem, DateTime.utc(2026, 9, 27, 12));
      await _record(tester, f.store, eventItem, DateTime.utc(2026, 10, 5, 12));
      await _record(tester, f.store, eventItem, DateTime.utc(2026, 10, 20, 12));
      await _record(tester, f.store, otherItem, DateTime.utc(2026, 10, 5, 13));
      final voided = await _record(
        tester,
        f.store,
        eventItem,
        DateTime.utc(2026, 10, 7, 12),
      );
      await _void(tester, f.store, voided);
      await _skip(tester, f.store, eventItem, CivilDate(2026, 10, 6));

      f.container.read(routerProvider).go('/event/${event.id}');
      await settle(tester);
      await waitForText(tester, event.name);
      expect(
        (await runIo(tester, () => f.store.eventActuals([event.id])))!.length,
        3,
      );
      final semantics = tester.ensureSemantics();
      await _revealHistoryCommand(tester);
      expect(find.bySemanticsLabel(RegExp('Open History for')), findsOneWidget);
      semantics.dispose();
      // The canonical preview remains the factual, non-voided event list.
      await waitForText(tester, 'Autumn medicine');
      expect(find.byType(RecordCard), findsNWidgets(3));
      expect(find.text(other.name), findsNothing);

      await _openHistory(tester, f.container, event.name);
      expect(
        f.container.read(routerProvider).routerDelegate.state.uri.path,
        '/history',
      );
      final location = f.container
          .read(routerProvider)
          .routerDelegate
          .state
          .uri
          .toString();
      expect(Uri.parse(location).queryParameters['event'], event.id);
      expect(Uri.parse(location).queryParameters['scope'], meId);
      expect(
        Uri.parse(location).queryParameters['return'],
        '/event/${event.id}',
      );
      final query = _history(f.container).state.query!;
      expect(query.filter.scope.personId, meId);
      expect(query.filter.eventIds, [event.id]);
      expect(query.filter.status, TimelineStatus.all);
      expect(query.filter.fromInstant, isNull);
      expect(query.filter.beforeInstant, isNull);
      expect(query.filter.typeIds, isEmpty);
      expect(query.filter.itemId, isNull);
      expect(find.text(event.name), findsOneWidget);
      expect(find.text('Filtered'), findsNothing);
      expect(find.text(otherItem.name), findsNothing);
      expect(
        _entryStatuses(tester),
        containsAll([
          TimelineEntryStatus.recorded,
          TimelineEntryStatus.skipped,
          TimelineEntryStatus.voided,
        ]),
      );

      // Current History status controls narrow the same event-linked set.
      await _toggleFilters(tester);
      await _selectStatus(tester, 'Skipped');
      expect(
        _history(f.container).state.query!.filter.status,
        TimelineStatus.skipped,
      );
      expect(_entryStatuses(tester), [TimelineEntryStatus.skipped]);
      await _selectStatus(tester, 'Voided');
      expect(_entryStatuses(tester), [TimelineEntryStatus.voided]);
      await _selectStatus(tester, 'All');
      expect(_entryStatuses(tester).length, 5);
      await _toggleFilters(tester);
      expect(find.text('Done').hitTestable(), findsNothing);

      final back = find.byKey(const ValueKey('history-back'));
      await tester.ensureVisible(back);
      await settle(tester);
      await tester.tap(back);
      await settle(tester);
      expect(
        f.container.read(routerProvider).routerDelegate.state.uri.path,
        '/event/${event.id}',
      );
      expect(find.text(event.name), findsOneWidget);
      expect(find.byKey(const ValueKey('event-history-open')), findsOneWidget);
      expect(tester.takeException(), isNull);
      expect(other.id, isNot(event.id));
    },
  );

  appTest(
    'event A History stays isolated beyond a full page of linked entries',
    (tester) async {
      final f = await launch(tester, todayClock: _now);
      final eventItem = await _item(tester, f.store, 'Linked medicine');
      final otherItem = await _item(tester, f.store, 'Unlinked medicine');
      final event = await _event(
        tester,
        f.store,
        id: 'large-course',
        name: 'Large Linked Course',
        item: eventItem,
        plannedStart: _day(10, 1),
        plannedEnd: _day(10, 31),
        actualStart: _day(10, 1),
        actualEnd: _day(10, 31),
        completed: true,
        membershipFrom: DateTime.utc(2026, 9, 1),
      );
      await _event(
        tester,
        f.store,
        id: 'small-course',
        name: 'Small Other Course',
        item: otherItem,
        plannedStart: _day(10, 1),
        plannedEnd: _day(10, 31),
        actualStart: _day(10, 1),
        actualEnd: _day(10, 31),
        completed: true,
      );
      await runIo(tester, () async {
        for (var index = 0; index < 52; index++) {
          await f.store.record(
            commandId: newCommandId(),
            itemId: eventItem.id,
            expectedPersonRevision: 2,
            amount: '1',
            actualAt: DateTime.utc(
              2026,
              10,
              1,
              8,
            ).add(Duration(minutes: index * 10)),
          );
        }
      });
      await _record(tester, f.store, otherItem, DateTime.utc(2026, 10, 2, 12));

      f.container.read(routerProvider).go('/event/${event.id}');
      await settle(tester);
      await waitForText(tester, event.name);
      await _openHistory(tester, f.container, event.name);
      expect(find.byType(HistoryEntryCard), findsNWidgets(25));
      await tap(tester, 'More');
      expect(find.byType(HistoryEntryCard), findsNWidgets(50));
      await tap(tester, 'More');
      expect(find.byType(HistoryEntryCard), findsNWidgets(52));
      final entries = tester
          .widgetList<HistoryEntryCard>(find.byType(HistoryEntryCard))
          .map((card) => card.entry)
          .toList();
      expect(entries.every((entry) => entry.personId == meId), isTrue);
      expect(
        entries.whereType<RecordTimelineEntry>().every(
          (entry) => entry.record.itemId == eventItem.id,
        ),
        isTrue,
      );
      expect(find.text(otherItem.name), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  appTest('event name loading and failure keep the exact History scope', (
    tester,
  ) async {
    final f = await launch(tester, todayClock: _now);
    final item = await _item(tester, f.store, 'Lookup medicine');
    final event = await _event(
      tester,
      f.store,
      id: 'lookup-event',
      name: 'Lookup Course',
      item: item,
      actualStart: _day(10, 1),
      actualEnd: _day(10, 31),
      membershipFrom: DateTime.utc(2026, 1, 1),
    );
    await _record(tester, f.store, item, DateTime.utc(2026, 10, 20));
    final streams = <StreamController<EventRecord?>>[];
    final scoped = ProviderContainer(
      parent: f.container,
      overrides: [
        eventLookupProvider.overrideWith((ref, id) {
          final stream = StreamController<EventRecord?>();
          streams.add(stream);
          ref.onDispose(stream.close);
          return stream.stream;
        }),
      ],
    );
    addTearDown(scoped.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(container: scoped, child: const VitalApp()),
    );
    final location = eventHistoryLocation(eventId: event.id);
    scoped.read(routerProvider).go(location);
    await waitForText(tester, 'Loading event.');
    await waitForText(tester, item.name);
    expect(
      scoped.read(historyControllerProvider(location)).query!.filter.eventIds,
      [event.id],
    );
    streams.last.addError(StateError('synthetic name lookup failure'));
    await waitForText(
      tester,
      'The event name could not be loaded. Retry to check it.',
    );
    expect(find.text(item.name), findsWidgets);
    await tap(tester, 'Retry');
    await waitForText(tester, 'Loading event.');
    streams.last.add(event);
    await waitForText(tester, event.name);
    expect(
      find.text('The event name could not be loaded. Retry to check it.'),
      findsNothing,
    );
    expect(
      scoped.read(historyControllerProvider(location)).query!.filter.eventIds,
      [event.id],
    );
    expect(tester.takeException(), isNull);
  });

  appTest('History ignores invalid return destinations', (tester) async {
    final f = await launch(tester, todayClock: _now);
    for (final target in [
      'https://example.com',
      '//example.com',
      '/not-a-vital-route',
      '/history',
      'relative',
    ]) {
      final location = Uri(
        path: '/history',
        queryParameters: {'return': target},
      ).toString();
      f.container.read(routerProvider).go(location);
      await settle(tester);
      expect(
        find.byKey(const ValueKey('history-back')),
        findsNothing,
        reason: target,
      );
      expect(tester.takeException(), isNull);
    }
    f.container.read(routerProvider).go('/history?return=/event/known-event');
    await settle(tester);
    expect(find.byKey(const ValueKey('history-back')), findsOneWidget);
    f.container.read(routerProvider).go('/today');
    await settle(tester);
    await tester.binding.handlePopRoute();
    await settle(tester);
    expect(
      f.container.read(routerProvider).routerDelegate.state.uri.path,
      '/today',
    );
    expect(tester.takeException(), isNull);
  });

  appTest('a retained History filter does not leak into the event seed', (
    tester,
  ) async {
    final f = await launch(tester, todayClock: _now);
    final eventItem = await _item(tester, f.store, 'Filtered medicine');
    final event = await _event(
      tester,
      f.store,
      id: 'root-filter-course',
      name: 'Root Filter Course',
      item: eventItem,
      plannedStart: _day(10, 1),
      plannedEnd: _day(10, 31),
      actualStart: _day(10, 1),
      actualEnd: _day(10, 31),
      completed: true,
      membershipFrom: DateTime.utc(2026, 9, 1),
    );
    await _record(tester, f.store, eventItem, DateTime.utc(2026, 10, 5, 12));
    await _skip(tester, f.store, eventItem, CivilDate(2026, 10, 6));

    const rootLocation = '/history?view=list&status=skipped';
    f.container.read(routerProvider).go(rootLocation);
    await settle(tester);
    await waitForText(tester, 'Filtered medicine');
    expect(
      f.container
          .read(historyControllerProvider(rootLocation))
          .query!
          .filter
          .status,
      TimelineStatus.skipped,
    );
    expect(_entryStatuses(tester), [TimelineEntryStatus.skipped]);

    f.container.read(routerProvider).push('/event/${event.id}');
    await settle(tester);
    await waitForText(tester, event.name);
    await _openHistory(tester, f.container, event.name);
    final eventHistory = _history(f.container).state.query!;
    expect(eventHistory.filter.eventIds, [event.id]);
    expect(eventHistory.filter.status, TimelineStatus.all);
    expect(eventHistory.filter.fromInstant, isNull);
    expect(eventHistory.filter.beforeInstant, isNull);
    expect(_entryStatuses(tester), contains(TimelineEntryStatus.recorded));
    expect(_entryStatuses(tester), contains(TimelineEntryStatus.skipped));

    await tester.ensureVisible(find.byKey(const ValueKey('history-back')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('history-back')));
    await settle(tester);
    await waitForText(tester, event.name);
    expect(
      f.container.read(routerProvider).routerDelegate.state.uri.path,
      '/event/${event.id}',
    );
    expect(find.byKey(const ValueKey('event-history-open')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  appTest('an event with no linked records keeps an empty History', (
    tester,
  ) async {
    final f = await launch(tester, todayClock: _now);
    final item = await _item(tester, f.store, 'Unlinked medicine');
    final event = await _event(
      tester,
      f.store,
      id: 'empty-course',
      name: 'Empty Course',
      item: item,
      plannedStart: _day(10, 1),
      plannedEnd: _day(10, 31),
      actualStart: _day(10, 1),
      actualEnd: _day(10, 31),
      completed: true,
      membershipFrom: DateTime.utc(2026, 9, 1),
    );
    await _record(tester, f.store, item, DateTime.utc(2026, 11, 5, 12));

    f.container.read(routerProvider).go('/event/${event.id}');
    await settle(tester);
    await waitForText(tester, event.name);
    await _openHistory(tester, f.container, event.name);
    expect(find.byType(HistoryEntryCard), findsNothing);
    expect(
      find.text(
        'No recorded or skipped entries match this view. Clear a filter or choose another date.',
      ),
      findsOneWidget,
    );
    expect(find.text(event.name), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('history-back')));
    await settle(tester);
    expect(
      f.container.read(routerProvider).routerDelegate.state.uri.path,
      '/event/${event.id}',
    );
    expect(tester.takeException(), isNull);
  });

  appTest('missing and locked events never offer a History destination', (
    tester,
  ) async {
    final f = await launch(tester, auth: FakeAuth(), todayClock: _now);
    f.container.read(routerProvider).go('/event/missing-event');
    await settle(tester);
    expect(
      find.text(
        'This entry is no longer available. Return to Today to review your records.',
      ),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('event-history-open')), findsNothing);

    final item = await _item(tester, f.store, 'Protected medicine');
    final event = await _event(
      tester,
      f.store,
      id: 'locked-course',
      name: 'Locked Course',
      item: item,
      plannedStart: _day(10, 1),
      plannedEnd: _day(10, 31),
      actualStart: _day(10, 1),
      actualEnd: _day(10, 31),
      completed: true,
      membershipFrom: DateTime.utc(2026, 9, 1),
    );
    await _record(tester, f.store, item, DateTime.utc(2026, 10, 5, 12));
    f.container.read(routerProvider).go('/event/${event.id}');
    await settle(tester);
    await waitForText(tester, event.name);
    expect(find.byKey(const ValueKey('event-history-open')), findsOneWidget);

    await runIo(
      tester,
      () => f.container.read(appLockProvider.notifier).setEnabled(true),
    );
    f.container
        .read(appLockProvider.notifier)
        .lifecycle(AppLifecycleState.inactive);
    await settle(tester);
    expect(find.text('Unlock'), findsWidgets);
    expect(find.byKey(const ValueKey('event-history-open')), findsNothing);

    f.container
        .read(appLockProvider.notifier)
        .lifecycle(AppLifecycleState.resumed);
    await tap(tester, 'Unlock');
    await settle(tester);
    await waitForText(tester, event.name);
    expect(find.byKey(const ValueKey('event-history-open')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  appTest('the event History command is keyboard reachable and activates', (
    tester,
  ) async {
    final f = await launch(tester, todayClock: _now);
    final item = await _item(tester, f.store, 'Keyboard medicine');
    final event = await _event(
      tester,
      f.store,
      id: 'keyboard-course',
      name: 'Keyboard Course',
      item: item,
      plannedStart: _day(10, 1),
      plannedEnd: _day(10, 31),
      actualStart: _day(10, 1),
      actualEnd: _day(10, 31),
      completed: true,
      membershipFrom: DateTime.utc(2026, 9, 1),
    );
    await _record(tester, f.store, item, DateTime.utc(2026, 10, 5, 12));
    f.container.read(routerProvider).go('/event/${event.id}');
    await settle(tester);
    await waitForText(tester, event.name);
    final command = find.byKey(const ValueKey('event-history-open'));
    await _revealHistoryCommand(tester);
    final label = find.descendant(of: command, matching: find.text('Open'));
    Focus.of(tester.element(label)).requestFocus();
    await settle(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await settle(tester);
    expect(
      f.container.read(routerProvider).routerDelegate.state.uri.path,
      '/history',
    );
    expect(
      f.container
          .read(routerProvider)
          .routerDelegate
          .state
          .uri
          .queryParameters['event'],
      event.id,
    );
    await tester.binding.handlePopRoute();
    await settle(tester);
    expect(
      f.container.read(routerProvider).routerDelegate.state.uri.path,
      '/event/${event.id}',
    );
    await waitForText(tester, event.name);
    expect(tester.takeException(), isNull);
  });

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    appTest(
      'event History stays readable in ${mode.name} at 320px and 2x text',
      (tester) async {
        tester.view.physicalSize = const Size(320, 740);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        tester.platformDispatcher.accessibilityFeaturesTestValue =
            const FakeAccessibilityFeatures(disableAnimations: true);
        addTearDown(tester.view.reset);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        addTearDown(
          tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
        );
        final f = await launch(tester, todayClock: _now);
        final item = await _item(tester, f.store, 'Narrow medicine');
        final event = await _event(
          tester,
          f.store,
          id: 'narrow-${mode.name}',
          name: 'Long Autumn Recovery Course Name',
          item: item,
          plannedStart: _day(10, 1),
          plannedEnd: _day(10, 31),
          actualStart: _day(10, 1),
          actualEnd: _day(10, 31),
          completed: true,
          membershipFrom: DateTime.utc(2026, 9, 1),
        );
        await _record(tester, f.store, item, DateTime.utc(2026, 10, 5, 12));
        f.container.read(appearanceProvider.notifier).setMode(mode);
        f.container.read(routerProvider).go('/event/${event.id}');
        await settle(tester);
        await waitForText(tester, event.name);
        final command = find.byKey(const ValueKey('event-history-open'));
        await _revealHistoryCommand(tester);
        expect(
          find.descendant(of: command, matching: find.text('Open')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        await tester.tap(command);
        await settle(tester);
        expect(
          f.container.read(routerProvider).routerDelegate.state.uri.path,
          '/history',
        );
        await waitForText(tester, event.name);
        expect(find.text(event.name), findsOneWidget);
        expect(find.text('Filtered'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    appTest('event History captures use synthetic records in ${mode.name}', (
      tester,
    ) async {
      if (captureDirectory.isEmpty) return;
      final boundaryKey = GlobalKey();
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      tester.view.padding = const FakeViewPadding(top: 28, bottom: 24);
      tester.view.viewPadding = const FakeViewPadding(top: 28, bottom: 24);
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final f = await launch(tester, todayClock: _now);
      final item = await _item(tester, f.store, 'Autumn medicine');
      final event = await _event(
        tester,
        f.store,
        id: 'capture-${mode.name}',
        name: 'Autumn Recovery Course',
        item: item,
        plannedStart: _day(10, 1),
        plannedEnd: _day(10, 10),
        actualStart: _day(9, 25),
        actualEnd: _day(10, 30),
        completed: true,
        membershipFrom: DateTime.utc(2026, 9, 1),
      );
      await _record(tester, f.store, item, DateTime.utc(2026, 9, 27, 12));
      await _record(tester, f.store, item, DateTime.utc(2026, 10, 5, 12));
      await _record(tester, f.store, item, DateTime.utc(2026, 10, 20, 12));
      await _skip(tester, f.store, item, CivilDate(2026, 10, 6));
      f.container.read(appearanceProvider.notifier).setMode(mode);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: f.container,
          child: RepaintBoundary(key: boundaryKey, child: const VitalApp()),
        ),
      );
      await settle(tester);
      f.container.read(routerProvider).go('/event/${event.id}');
      await settle(tester);
      await waitForText(tester, event.name);
      await _revealHistoryCommand(tester);
      await _capture(tester, boundaryKey, '${mode.name}-event-history-command');
      tester.view.physicalSize = const Size(320, 740);
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      await settle(tester);
      await _revealHistoryCommand(tester);
      expect(tester.takeException(), isNull);
      await _capture(
        tester,
        boundaryKey,
        '${mode.name}-event-history-command-narrow',
      );
      tester.platformDispatcher.clearTextScaleFactorTestValue();
      tester.view.physicalSize = const Size(390, 844);
      await settle(tester);
      await _openHistory(tester, f.container, event.name);
      await _capture(tester, boundaryKey, '${mode.name}-event-history');
      tester.view.physicalSize = const Size(320, 740);
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      await settle(tester);
      expect(tester.takeException(), isNull);
      await _capture(tester, boundaryKey, '${mode.name}-event-history-narrow');
      tester.platformDispatcher.clearTextScaleFactorTestValue();
      tester.view.physicalSize = const Size(390, 844);
      await settle(tester);
    });
  }
}
