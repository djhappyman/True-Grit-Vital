import 'package:true_grit_vital/ui/stitch_ui.dart';

import 'fixtures/single_user.dart';

import 'package:go_router/go_router.dart';
import 'package:true_grit_vital/features/charts/chart_pages.dart';

import 'dart:async';
import 'dart:ui' show SemanticsAction, SemanticsActionEvent, Tristate;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart' show MaterialLocalizations;
import 'package:true_grit_vital/app/storage.dart';
import 'package:true_grit_vital/app/device_zone.dart';
import 'package:true_grit_vital/platform/device_zone.dart';
import 'package:true_grit_vital/features/history/history_source.dart';

import 'domain/history/history_test_data.dart' show testRecord;
import 'stock_ui_test.dart' show enter;

import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:true_grit_vital/app/history.dart';
import 'package:true_grit_vital/app/vital_app.dart';
import 'package:true_grit_vital/data/record_store.dart';
import 'package:true_grit_vital/features/history/history_calendar.dart';
import 'package:true_grit_vital/features/history/history_pages.dart';
import 'package:true_grit_vital/ui/vital_ui.dart';

import 'vital_app_test.dart'
    show appTest, launch, runIo, settle, tap, waitForText;

CivilDate today() =>
    DisplayTime().instant(DateTime.now().toUtc(), 'Europe/London').civilDate;

Future<SubstanceItem> historyItem(
  RecordStore store,
  String name, {
  String type = 'Medicine',
}) => store.createItem(
  commandId: newCommandId(),
  expectedPersonRevision: 2,
  name: name,
  form: 'Tablet',
  unit: 'mg',
  type: type,
);

Future<UseRecord> historyRecord(
  RecordStore store,
  SubstanceItem item,
  CivilDate date, {
  String amount = '1',
}) => store.record(
  commandId: newCommandId(),
  itemId: item.id,
  personId: item.personId,
  expectedPersonRevision: 2,
  amount: amount,
  actualAt: DisplayTime()
      .dayBounds(date, 'Europe/London')
      .start
      .add(const Duration(hours: 12)),
);

Finder choices(String kind) => find.byWidgetPredicate(
  (widget) => widget is HistoryFilterChoices && widget.kind == kind,
);
Future<void> openChoices(WidgetTester tester, String kind) async {
  final button = find.descendant(
    of: choices(kind),
    matching: find.text('Choose'),
  );
  await tester.ensureVisible(button);
  await tester.tap(button);
  await settle(tester);
}

Future<void> toggleFilters(WidgetTester tester) async {
  final done = find.text('Done').hitTestable();
  if (done.evaluate().isNotEmpty) {
    await tester.tap(done);
    await settle(tester);
    return;
  }
  final target = find.byKey(const ValueKey('history-filters-toggle'));
  await tester.ensureVisible(target);
  await settle(tester);
  await tester.tap(target);
  await settle(tester);
}

void main() {
  appTest(
    'History disclosures expose one activation with expanded and collapsed semantics',
    (tester) async {
      final handle = tester.ensureSemantics();
      try {
        final f = await launch(tester);
        f.container.read(routerProvider).go('/history');
        await settle(tester);
        Future<void> toggle(String key) async {
          final target = find.byKey(ValueKey(key));
          await tester.ensureVisible(target);
          await settle(tester);
          final before = tester.getSemantics(target);
          expect(
            before.getSemanticsData().flagsCollection.isExpanded,
            Tristate.isFalse,
          );
          expect(
            before.getSemanticsData().hasAction(SemanticsAction.tap),
            isTrue,
          );
          tester.binding.performSemanticsAction(
            SemanticsActionEvent(
              type: SemanticsAction.tap,
              nodeId: before.id,
              viewId: tester.view.viewId,
            ),
          );
          await settle(tester);
          expect(
            tester
                .getSemantics(target)
                .getSemanticsData()
                .flagsCollection
                .isExpanded,
            Tristate.isTrue,
          );
        }

        expect(
          find.byKey(const ValueKey('history-person-toggle')),
          findsNothing,
        );
        await toggle('history-filters-toggle');
        await toggle('history-type-toggle');
        await toggle('history-event-toggle');
        expect(tester.takeException(), isNull);
      } finally {
        handle.dispose();
      }
    },
  );
  appTest(
    'History Charts action carries one adult and exact range and returns to the selected calendar day',
    (tester) async {
      final f = await launch(tester);
      final adult = (await runIo(
        tester,
        () => f.store.configureOwnProfile(
          commandId: newCommandId(),
          name: 'Sam chart owner',
          adultConfirmed: true,
        ),
      ))!;
      await runIo(
        tester,
        () => f.store.saveBrowsingScope(const FeedScope.everyone()),
      );
      final bounds = DisplayTime().dayBounds(today(), 'Europe/London');
      final location = Uri(
        path: '/history',
        queryParameters: {
          'scope': adult.id,
          'from': bounds.start.toIso8601String(),
          'before': bounds.endExclusive.toIso8601String(),
          'status': 'recorded',
          'view': 'calendar',
          'selected': today().toString(),
        },
      ).toString();
      f.container.read(routerProvider).go(location);
      await settle(tester);
      await tap(tester, 'More');
      await tap(tester, 'Charts');
      expect(find.byType(ChartsPage), findsOneWidget);
      final uri = GoRouterState.of(tester.element(find.byType(ChartsPage))).uri;
      expect(uri.path, '/charts');
      expect(uri.queryParameters['scope'], adult.id);
      expect(uri.queryParameters['from'], bounds.start.toIso8601String());
      expect(
        uri.queryParameters['before'],
        bounds.endExclusive.toIso8601String(),
      );
      final back = Uri.parse(uri.queryParameters['return']!).queryParameters;
      expect(back['scope'], adult.id);
      expect(back['status'], 'recorded');
      expect(back['view'], 'calendar');
      expect(back['selected'], today().toString());
      expect(find.text('Person: Sam chart owner'), findsOneWidget);
      await tap(tester, 'Back');
      expect(find.byType(ChartsPage), findsNothing);
      expect(
        f.container.read(routerProvider).routeInformationProvider.value.uri,
        Uri.parse(location),
      );
      expect(
        tester.widget<HistoryMonthGrid>(find.byType(HistoryMonthGrid)).selected,
        today(),
      );
      expect(
        (await runIo(tester, f.store.readBrowsingScope))!.isEveryone,
        isTrue,
      );
      expect(tester.takeException(), isNull);
    },
  );

  appTest(
    'relative dates retain exact semantics and an unlinked dose never implies missed use',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        final f = await launch(tester);
        final records = (await runIo(tester, () async {
          final item = await historyItem(
            f.store,
            'Complete original medicine name',
          );
          return [
            for (final days in [0, 1, 3])
              await historyRecord(f.store, item, today().addDays(-days)),
          ];
        }))!;
        f.container.read(routerProvider).go('/history?view=list');
        await settle(tester);
        expect(find.widgetWithText(VitalButton, 'Charts'), findsNothing);
        expect(find.text('Yesterday'), findsOneWidget);
        expect(find.text('3 days ago'), findsOneWidget);
        final exact = find.byKey(ValueKey('history-time-r:${records[1].id}'));
        await tester.ensureVisible(exact);
        await settle(tester);
        expect(
          tester.getSemantics(exact).getSemanticsData().label,
          contains('Europe/London'),
        );
        expect(
          tester.getSemantics(exact).getSemanticsData().label,
          contains('Yesterday'),
        );
        final card = find.byWidgetPredicate(
          (widget) =>
              widget is HistoryEntryCard &&
              widget.entry.id.value == records.first.id,
        );
        final view = find.descendant(
          of: card,
          matching: find.byType(StitchIcon),
        );
        await tester.ensureVisible(view);
        await settle(tester);
        await tester.tap(view);
        await settle(tester);
        expect(find.text('No plan captured'), findsOneWidget);
        expect(
          find.text(
            'This dose has no captured plan. This does not show missed use.',
          ),
          findsOneWidget,
        );
        expect(find.byType(HistorySourcePage), findsOneWidget);
      } finally {
        semantics.dispose();
      }
    },
  );

  appTest(
    'date errors preserve the query and type event status filters combine without changing the adult',
    (tester) async {
      final f = await launch(tester);
      final item = (await runIo(tester, () async {
        final a = await historyItem(
          f.store,
          'Included medicine',
          type: 'Medicine',
        );
        final b = await historyItem(
          f.store,
          'Other supplement',
          type: 'Supplement',
        );
        await historyRecord(f.store, a, today());
        await historyRecord(f.store, b, today());
        final event = EventRecord(
          id: 'history-event',
          personId: meId,
          name: 'Selected course',
          eventType: 'course',
          zoneId: 'Europe/London',
          revision: 1,
          memberships: [
            EventMembership(
              id: 'history-member',
              itemId: a.id,
              personId: meId,
              effectiveFrom: DateTime.utc(2020),
              revision: 1,
            ),
          ],
        );
        final command = SaveEventCommand(
          commandId: newCommandId(),
          generation: f.store.generation,
          expectedRevision: null,
          expectedPersonRevision: 2,
          event: event,
        );
        await f.store.saveEvent(
          command,
          membershipReview: await f.store.previewEventMembership(command),
        );
        return a;
      }))!;
      f.container.read(routerProvider).go('/history');
      await settle(tester);
      final original = f.container
          .read(historyControllerProvider('/history'))
          .query!;
      await toggleFilters(tester);
      await enter(tester, 'From', '2026-02-30');
      await tap(tester, 'Apply');
      expect(
        find.text('Enter valid dates with the end on or after the start.'),
        findsOneWidget,
      );
      expect(
        f.container.read(historyControllerProvider('/history')).query!.identity,
        original.identity,
      );
      await tap(tester, 'Clear');
      await openChoices(tester, 'type');
      final typeButton = find.descendant(
        of: choices('type'),
        matching: find.text('Medicine'),
      );
      await tester.ensureVisible(typeButton);
      await tester.tap(typeButton);
      await settle(tester);
      await openChoices(tester, 'event');
      await tap(tester, 'Selected course');
      final status = find.descendant(
        of: find.byKey(const ValueKey('history-status')),
        matching: find.text('Recorded'),
      );
      await tester.ensureVisible(status);
      await settle(tester);
      await tester.tap(status);
      await settle(tester);
      final query = f.container
          .read(historyControllerProvider('/history'))
          .query!;
      expect(query.filter.scope.personId, meId);
      expect(query.filter.typeIds, isNotEmpty);
      expect(query.filter.eventIds, ['history-event']);
      expect(query.filter.status, TimelineStatus.recorded);
      final cards = tester.widgetList<HistoryEntryCard>(
        find.byType(HistoryEntryCard),
      );
      expect(cards.length, 1);
      expect(
        (cards.single.entry as RecordTimelineEntry).record.itemId,
        item.id,
      );
      await toggleFilters(tester);
      expect(find.text('Filtered'), findsOneWidget);
      await toggleFilters(tester);
      expect(find.text('Selected course'), findsWidgets);
    },
  );

  appTest(
    'calendar markers select exact day details at 320 pixels and double text with semantic activation',
    (tester) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final semantics = tester.ensureSemantics();
      try {
        final f = await launch(tester);
        await runIo(tester, () async {
          final item = await historyItem(
            f.store,
            'Calendar full medicine name',
          );
          await historyRecord(f.store, item, today());
          final record = await historyRecord(
            f.store,
            item,
            today(),
            amount: '2',
          );
          await f.store.voidRecord(
            commandId: newCommandId(),
            recordId: record.id,
            expectedRevision: record.revision,
            personId: meId,
            expectedPersonRevision: 2,
          );
          await f.store.saveDailyPlan(
            commandId: newCommandId(),
            expectedPersonRevision: 2,
            expectedGeneration: f.store.generation,
            plan: DailyPlanVersion(
              personId: meId,
              planId: 'calendar-plan',
              itemId: item.id,
              versionId: 'calendar-version',
              start: today(),
              timing: DailyCount(
                2,
                PlannedAmount(quantity: ExactQuantity.parse('1'), unit: 'mg'),
              ),
              zoneBasis: FixedHome('Europe/London'),
            ),
          );
          final rows = await f.store.dailyRows(
            from: today(),
            toExclusive: today().addDays(1),
            observedZone: 'Europe/London',
          );
          await f.store.actDaily(
            commandId: newCommandId(),
            row: rows.rows.single,
            kind: DailyActionKind.taken,
            actualAt: DateTime.now().toUtc(),
          );
          final updated = await f.store.dailyRows(
            from: today(),
            toExclusive: today().addDays(1),
            observedZone: 'Europe/London',
          );
          await f.store.actDaily(
            commandId: newCommandId(),
            row: updated.rows.single,
            kind: DailyActionKind.skip,
          );
        });
        f.container.read(routerProvider).go('/history');
        await settle(tester);
        await settle(tester);
        final section = tester.widget<HistoryCalendarSection>(
          find.byType(HistoryCalendarSection),
        );
        final currentGrid = tester.widget<HistoryMonthGrid>(
          find.byType(HistoryMonthGrid),
        );
        final locale = MaterialLocalizations.of(
          tester.element(find.byType(HistoryMonthGrid)),
        );
        await runIo(
          tester,
          () => f.container.read(
            historyCalendarProvider(
              CalendarRequest(
                section.query,
                historyCalendarDates(
                  currentGrid.month,
                  locale.firstDayOfWeekIndex,
                ),
              ),
            ).future,
          ),
        );
        await settle(tester);
        final grid = tester.widget<HistoryMonthGrid>(
          find.byType(HistoryMonthGrid),
        );
        final counts = grid.counts[today()]!;
        expect(counts.recorded, 2);
        expect(counts.voided, 1);
        expect(counts.skipped, 1);
        final cell = find.byKey(ValueKey('history-day-${today()}'));
        await tester.ensureVisible(cell);
        await settle(tester);
        final data = tester.getSemantics(cell).getSemanticsData();
        expect(data.hasAction(SemanticsAction.tap), isTrue);
        expect(data.label, contains('2 recorded'));
        expect(data.label, contains('1 skipped'));
        expect(data.label, contains('1 voided'));
        await tester.tap(cell);
        await settle(tester);
        expect(
          tester
              .widget<HistoryMonthGrid>(find.byType(HistoryMonthGrid))
              .selected,
          today(),
        );
        expect(find.text('4 entries'), findsOneWidget);
        expect(find.byType(HistoryEntryCard), findsNWidgets(4));
        expect(find.textContaining('Date only'), findsOneWidget);
        final planned = find.byWidgetPredicate(
          (widget) =>
              widget is HistoryEntryCard &&
              widget.entry is RecordTimelineEntry &&
              (widget.entry as RecordTimelineEntry).planContext != null,
        );
        final view = find.descendant(
          of: planned,
          matching: find.byType(StitchIcon),
        );
        await tester.ensureVisible(view);
        await settle(tester);
        await tester.tap(view);
        await settle(tester);
        expect(
          find.text('Saved plan: Calendar full medicine name'),
          findsOneWidget,
        );
        expect(find.text('No plan captured'), findsNothing);
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
      }
    },
  );

  appTest(
    'source Back preserves filters and scroll while a moved record receives explicit feedback',
    (tester) async {
      final f = await launch(tester);
      final record = (await runIo(tester, () async {
        final item = await historyItem(f.store, 'Moved original record');
        return historyRecord(f.store, item, today());
      }))!;
      f.container.read(routerProvider).go('/history');
      await settle(tester);
      await toggleFilters(tester);
      await enter(tester, 'From', today().toString());
      await enter(tester, 'Through', today().toString());
      await tap(tester, 'Apply');
      final query = f.container
          .read(historyControllerProvider('/history'))
          .query!;
      await toggleFilters(tester);
      final cardAction = find.descendant(
        of: find.byType(HistoryEntryCard).first,
        matching: find.byType(StitchIcon),
      );
      await tester.ensureVisible(cardAction);
      await settle(tester);
      await tester.tap(cardAction);
      await settle(tester);
      await runIo(
        tester,
        () => f.store.correct(
          commandId: newCommandId(),
          recordId: record.id,
          expectedRevision: record.revision,
          personId: meId,
          expectedPersonRevision: 2,
          amount: null,
          actualAt: record.actualAt.subtract(const Duration(days: 1)),
        ),
      );
      await settle(tester);
      await tester.binding.handlePopRoute();
      await settle(tester);
      expect(
        f.container.read(historyControllerProvider('/history')).query!.identity,
        query.identity,
      );
      final feedback = Stopwatch()..start();
      while (find.textContaining('This entry moved to').evaluate().isEmpty &&
          feedback.elapsed.inSeconds < 30) {
        await settle(tester);
      }
      expect(find.textContaining('This entry moved to'), findsOneWidget);
      expect(find.text('Filtered'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  appTest(
    'calendar source correction restores its day filters and reports a moved anchor',
    (tester) async {
      final f = await launch(tester);
      final record = (await runIo(tester, () async {
        final item = await historyItem(
          f.store,
          'Anchored complete medicine name',
        );
        final rows = [
          for (var i = 0; i < 30; i++)
            await historyRecord(f.store, item, today(), amount: '${i + 1}'),
        ];
        return rows[6];
      }))!;
      f.container.read(routerProvider).go('/history');
      await settle(tester);
      await tap(tester, 'More');
      await waitForText(tester, '30 entries');
      final originalQuery = f.container
          .read(historyControllerProvider('/history'))
          .query!;
      final target = find.byWidgetPredicate(
        (widget) =>
            widget is HistoryEntryCard && widget.entry.id.value == record.id,
      );
      Future<void> inspectTarget() async {
        final view = find.descendant(
          of: target,
          matching: find.byType(StitchIcon),
        );
        await tester.ensureVisible(view);
        await settle(tester);
        await tester.tap(view);
        await settle(tester);
      }

      final view = find.descendant(
        of: target,
        matching: find.byType(StitchIcon),
      );
      await tester.ensureVisible(view);
      await settle(tester);
      final list = tester.widget<ListView>(
        find
            .descendant(
              of: find.byType(HistoryPage),
              matching: find.byType(ListView),
            )
            .first,
      );
      final offset = list.controller!.offset;
      expect(offset, greaterThan(0));
      await tester.tap(view);
      await settle(tester);
      await tester.binding.handlePopRoute();
      await settle(tester);
      final restoredList = tester.widget<ListView>(
        find
            .descendant(
              of: find.byType(HistoryPage),
              matching: find.byType(ListView),
            )
            .first,
      );
      expect(restoredList.controller!.offset, closeTo(offset, 1));
      expect(f.container.read(historyControllerProvider('/history')).pages, 2);
      expect(
        f.container.read(historyControllerProvider('/history')).entries.length,
        30,
      );
      await inspectTarget();
      await tap(tester, 'Correct');
      await tap(tester, 'Edit');
      await enter(tester, 'Actual date', today().addDays(-1).toString());
      await tap(tester, 'Save');
      final location = f.container
          .read(routerProvider)
          .routeInformationProvider
          .value
          .uri
          .toString();
      expect(Uri.parse(location).queryParameters['scope'], meId);
      expect(Uri.parse(location).queryParameters['view'], 'calendar');
      expect(Uri.parse(location).queryParameters['anchor'], 'r:${record.id}');
      await runIo(
        tester,
        () => f.container.read(
          historySourceProvider((id: 'r:${record.id}', personId: meId)).future,
        ),
      );
      await settle(tester);
      final restored = f.container.read(historyControllerProvider(location));
      expect(restored.query!.identity, originalQuery.identity);
      expect(
        restored.entries.any((entry) => entry.id.value == record.id),
        isFalse,
      );
      expect(
        tester.widget<HistoryMonthGrid>(find.byType(HistoryMonthGrid)).selected,
        today(),
      );
      expect(find.textContaining('This entry moved to'), findsOneWidget);
      expect(
        find.text('History refreshed. Your filters are retained.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  for (final expired in [false, true]) {
    appTest(
      expired
          ? 'expired cursor refreshes the bounded window with visible feedback'
          : 'stale live results retain the old anchor until an explicit refresh',
      (tester) async {
        final f = await launch(tester);
        final changes = StreamController<TimelinePage>.broadcast();
        var reads = 0, subscriptions = 0;
        TimelineQuery? active;
        var clock = DateTime.utc(2026, 10, 20, 12);
        final first = RecordTimelineEntry(
          record: testRecord(id: 'first', person: meId),
        );
        final added = RecordTimelineEntry(
          record: testRecord(
            id: 'added',
            person: meId,
            actualAt: first.occurredAt.add(const Duration(hours: 1)),
          ),
        );
        final container = ProviderContainer(
          overrides: [
            storeLoaderProvider.overrideWithValue(() async => f.store),
            historyNowProvider.overrideWithValue(() => clock),
            observedDeviceZoneProvider.overrideWith(
              (ref) =>
                  Stream.value(DeviceZoneObservation.fromId('Europe/London')),
            ),
            historyReaderProvider.overrideWithValue((query) async {
              reads++;
              throw const TimelineCursorException('cursor_expired');
            }),
            historyWatcherProvider.overrideWithValue((query) {
              active = query;
              subscriptions++;
              if (expired) {
                return Stream.value(
                  TimelinePage(
                    query: query,
                    schemaVersion: 17,
                    datasetGeneration: f.store.generation,
                    entries: [first],
                    hasMore: true,
                  ),
                );
              }
              return changes.stream;
            }),
          ],
        );
        addTearDown(container.dispose);
        addTearDown(changes.close);
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const VitalApp(),
          ),
        );
        await settle(tester);
        container.read(routerProvider).go('/history?view=list');
        await settle(tester);
        if (expired) {
          await tap(tester, 'More');
          expect(reads, 1);
          expect(subscriptions, greaterThanOrEqualTo(2));
          expect(
            find.text('History refreshed. Your filters are retained.'),
            findsOneWidget,
          );
          expect(find.text('Yesterday'), findsOneWidget);
          clock = DateTime.utc(2026, 10, 21);
          await tester.pump(const Duration(hours: 12, milliseconds: 2));
          await settle(tester);
          expect(find.text('2 days ago'), findsOneWidget);
        } else {
          changes.add(
            TimelinePage(
              query: active!,
              schemaVersion: 17,
              datasetGeneration: f.store.generation,
              entries: [first],
            ),
          );
          await settle(tester);
          container
                  .read(
                    historyControllerProvider('/history?view=list').notifier,
                  )
                  .atTop =
              false;
          changes.add(
            TimelinePage(
              query: active!,
              schemaVersion: 17,
              datasetGeneration: f.store.generation,
              entries: [added, first],
            ),
          );
          await settle(tester);
          expect(find.byType(HistoryEntryCard), findsOneWidget);
          expect(
            find.text('History changed. Refresh to show the latest entries.'),
            findsOneWidget,
          );
          await tap(tester, 'Refresh');
          changes.add(
            TimelinePage(
              query: active!,
              schemaVersion: 17,
              datasetGeneration: f.store.generation,
              entries: [added, first],
            ),
          );
          await settle(tester);
          expect(find.byType(HistoryEntryCard), findsNWidgets(2));
          expect(
            find.text('History refreshed. Your filters are retained.'),
            findsOneWidget,
          );
        }
        expect(
          container
              .read(historyControllerProvider('/history?view=list'))
              .query!
              .filter
              .scope
              .personId,
          meId,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  appTest('wide windows retain anchored horizontal root navigation', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await launch(tester);
    final navigation = tester.widget<ShellNavigation>(
      find.byType(ShellNavigation),
    );
    expect(navigation.vertical, isFalse);
    expect(tester.getRect(find.byType(ShellNavigation)).width, 1200);
    expect(find.byType(VitalComponentThemes), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
