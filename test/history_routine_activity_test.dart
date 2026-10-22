import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:true_grit_vital/app/app_lock.dart';
import 'package:true_grit_vital/app/storage.dart';
import 'package:true_grit_vital/app/vital_app.dart';
import 'package:true_grit_vital/data/record_store.dart';
import 'package:true_grit_vital/features/history/history_pages.dart';
import 'package:true_grit_vital/features/history/routine_activity_summary.dart';
import 'package:true_grit_vital/ui/vital_ui.dart';

import 'design_system_test.dart' show host;
import 'history_mobile_ui_test.dart' show historyItem, historyRecord;
import 'vital_app_test.dart' show appTest, launch, runIo, settle, tap;

final _month = CivilDate(2026, 10, 1);

TimelineQuery _query({
  TimelineStatus status = TimelineStatus.all,
  TimelineFilter? filter,
  String zone = 'Europe/London',
}) => TimelineQuery(
  filter: (filter ?? TimelineFilter()).restart(status: status),
  displayZone: zone,
);

RoutineActivityRequest _request([TimelineQuery? query, CivilDate? month]) =>
    RoutineActivityRequest(query: query ?? _query(), month: month ?? _month);

HistoryCalendar _calendar(
  TimelineQuery query, {
  String generation = 'generation',
  List<HistoryCalendarCell>? cells,
}) => HistoryCalendar(
  queryIdentity: query.identity,
  generation: generation,
  cells:
      cells ??
      [
        HistoryCalendarCell(
          date: CivilDate(2026, 10, 1),
          recorded: 2,
          skipped: 3,
          voided: 1,
        ),
      ],
);

RoutineActivitySummary _summary(
  TimelineQuery query, {
  int recordedDays = 3,
  int recordedEntries = 5,
  int skippedEntries = 2,
  int voidedEntries = 1,
  String generation = 'generation',
}) => RoutineActivitySummary(
  month: _month,
  queryIdentity: query.identity,
  generation: generation,
  status: query.filter.status,
  recordedDays: recordedDays,
  recordedEntries: recordedEntries,
  skippedEntries: skippedEntries,
  voidedEntries: voidedEntries,
);

class _Unlocked extends AppLockController {
  @override
  AppLockState build() =>
      const AppLockState(ready: true, enabled: false, locked: false);
}

class _Locked extends AppLockController {
  @override
  AppLockState build() =>
      const AppLockState(ready: true, enabled: true, locked: true);
}

Future<void> _until(bool Function() condition, {String? reason}) async {
  final watch = Stopwatch()..start();
  while (!condition()) {
    if (watch.elapsed > const Duration(seconds: 10)) {
      fail(reason ?? 'condition was not met before the timeout');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

var _pumpCount = 0;

Future<void> _pumpActivity(
  WidgetTester tester, {
  required Stream<RoutineActivitySummary?> stream,
  TimelineQuery? query,
  bool locked = false,
  String generation = 'generation',
  double width = 390,
  double textScale = 1,
  Brightness brightness = Brightness.light,
  bool reduceMotion = false,
}) async {
  tester.view.physicalSize = const Size(900, 1600);
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  tester.platformDispatcher.accessibilityFeaturesTestValue =
      FakeAccessibilityFeatures(disableAnimations: reduceMotion);
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
  // A fresh scope per pump prevents a previous scenario's provider state from
  // surviving into the next width, theme or failure case.
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  final effectiveQuery = query ?? _query();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appLockProvider.overrideWith(locked ? _Locked.new : _Unlocked.new),
        routineActivityGenerationProvider.overrideWithValue(generation),
        routineActivityProvider.overrideWith((ref, request) => stream),
      ],
      child: host(
        SingleChildScrollView(
          child: SizedBox(
            width: width,
            child: HistoryRoutineActivity(
              key: ValueKey('routine-activity-pump-${_pumpCount++}'),
              query: effectiveQuery,
              month: _month,
            ),
          ),
        ),
        brightness: brightness,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _expand(WidgetTester tester) async {
  await tester.tap(find.text('Show'));
  await tester.pumpAndSettle();
}

void main() {
  group('month dates', () {
    test(
      'cover every representable day, including leap and boundary years',
      () {
        expect(routineActivityMonthDates(CivilDate(2024, 2, 1)), hasLength(29));
        expect(routineActivityMonthDates(CivilDate(2026, 2, 1)), hasLength(28));
        expect(routineActivityMonthDates(CivilDate(2026, 4, 1)), hasLength(30));
        expect(routineActivityMonthDates(CivilDate(2026, 7, 1)), hasLength(31));
        final december = routineActivityMonthDates(CivilDate(2026, 12, 10));
        expect(december.first, CivilDate(2026, 12, 1));
        expect(december.last, CivilDate(2026, 12, 31));
        expect(routineActivityMonthDates(CivilDate(1, 1, 1)), hasLength(31));
        final latest = routineActivityMonthDates(CivilDate(9999, 12, 1));
        expect(latest, hasLength(31));
        expect(latest.last, CivilDate(9999, 12, 31));
      },
    );

    test('request normalises the month and tracks the query identity', () {
      final query = _query();
      final request = _request(query, CivilDate(2026, 10, 23));
      expect(request.month, _month);
      expect(request.dates, hasLength(31));
      expect(_request(query, CivilDate(2026, 10, 9)), request);
      expect(
        _request(
          _query(status: TimelineStatus.recorded),
          CivilDate(2026, 10, 1),
        ),
        isNot(request),
      );
      expect(_request(query, CivilDate(2026, 11, 1)), isNot(request));
    });
  });

  group('monthly summary', () {
    test('ignores surrounding-month cells and keeps facts separate', () {
      final query = _query();
      final summary = routineActivitySummary(
        calendar: _calendar(
          query,
          cells: [
            HistoryCalendarCell(
              date: CivilDate(2026, 9, 30),
              recorded: 9,
              skipped: 9,
              voided: 9,
            ),
            HistoryCalendarCell(
              date: CivilDate(2026, 10, 1),
              recorded: 2,
              skipped: 3,
              voided: 1,
            ),
            HistoryCalendarCell(
              date: CivilDate(2026, 10, 2),
              recorded: 0,
              skipped: 4,
              voided: 0,
            ),
            HistoryCalendarCell(
              date: CivilDate(2026, 10, 3),
              recorded: 1,
              skipped: 0,
              voided: 2,
            ),
            HistoryCalendarCell(
              date: CivilDate(2026, 11, 1),
              recorded: 7,
              skipped: 7,
              voided: 7,
            ),
          ],
        ),
        request: _request(query),
      );
      expect(summary.recordedDays, 2);
      expect(summary.recordedEntries, 3);
      expect(summary.skippedEntries, 7);
      expect(summary.voidedEntries, 3);
      expect(summary.totalEntries, 13);
      expect(summary.showsRecorded, isTrue);
      expect(summary.showsSkipped, isTrue);
      expect(summary.showsVoided, isTrue);
    });

    test('status scope exposes only the facts that status includes', () {
      for (final status in TimelineStatus.values) {
        final query = _query(status: status);
        final summary = routineActivitySummary(
          calendar: _calendar(query),
          request: _request(query),
        );
        expect(
          summary.showsRecorded,
          status != TimelineStatus.skipped && status != TimelineStatus.voided,
        );
        expect(
          summary.showsSkipped,
          status != TimelineStatus.recorded && status != TimelineStatus.voided,
        );
        expect(
          summary.showsVoided,
          status != TimelineStatus.recorded && status != TimelineStatus.skipped,
        );
      }
      final empty = routineActivitySummary(
        calendar: _calendar(_query(), cells: const []),
        request: _request(),
      );
      expect(empty.recordedDays, 0);
      expect(empty.hasEntries, isFalse);
    });

    test('drops a calendar from another query or dataset generation', () {
      final query = _query();
      final request = _request(query);
      expect(
        routineActivityFor(
          calendar: _calendar(query),
          request: request,
          generation: 'generation',
        ),
        isNotNull,
      );
      expect(
        routineActivityFor(
          calendar: _calendar(_query(status: TimelineStatus.recorded)),
          request: request,
          generation: 'generation',
        ),
        isNull,
      );
      expect(
        routineActivityFor(
          calendar: _calendar(query),
          request: request,
          generation: 'restored',
        ),
        isNull,
      );
    });
  });

  group('store-backed provider', () {
    late Directory dir;
    late RecordStore store;
    late SubstanceItem item;
    late ProviderContainer container;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('vital-routine-activity-');
      store = await RecordStore.open(
        path: '${dir.path}/test.db',
        key: List.generate(32, (i) => i + 1),
        isNew: true,
      );
      item = await store.createItem(
        commandId: 'item',
        name: 'Recorded medicine',
        form: 'tablet',
        unit: 'mg',
        type: 'medicine',
      );
      container = ProviderContainer(
        overrides: [
          appLockProvider.overrideWith(_Unlocked.new),
          recordStoreProvider.overrideWith((ref) async => store),
        ],
      );
    });

    tearDown(() async {
      container.dispose();
      await store.close();
      await dir.delete(recursive: true);
    });

    Future<UseRecord> record(String id, DateTime at, {String amount = '1'}) =>
        store.record(
          commandId: id,
          itemId: item.id,
          amount: amount,
          actualAt: at,
        );

    Future<void> waitFor(
      List<RoutineActivitySummary?> values,
      bool Function(RoutineActivitySummary) condition, {
      String? reason,
    }) => _until(
      () => values.isNotEmpty && values.last != null && condition(values.last!),
      reason: reason,
    );

    test(
      'counts the whole month beyond the page and refreshes on every change',
      () async {
        final first = await record('first', DateTime.utc(2026, 10, 1, 12));
        await record('second', DateTime.utc(2026, 10, 2, 12));
        await record('third', DateTime.utc(2026, 10, 2, 13));
        for (var i = 0; i < 60; i++) {
          await record(
            'page-$i',
            DateTime.utc(2026, 10, 3, 12).add(Duration(minutes: i)),
          );
        }
        final query = _query();
        final values = <RoutineActivitySummary?>[];
        final subscription = container.listen(
          routineActivityProvider(_request(query)),
          (_, next) {
            if (next.hasValue) values.add(next.value);
          },
          fireImmediately: true,
        );
        addTearDown(subscription.close);

        await waitFor(values, (summary) => summary.recordedEntries == 63);
        expect(values.last!.recordedDays, 3);
        expect(values.last!.recordedEntries, 63);

        final beforeCorrect = values.length;
        await store.correct(
          commandId: 'correct',
          recordId: first.id,
          expectedRevision: 1,
          amount: '2',
          actualAt: first.actualAt,
        );
        await _until(
          () => values.length > beforeCorrect,
          reason: 'correction did not refresh the monthly summary',
        );
        expect(values.last!.recordedEntries, 63);

        await store.voidRecord(
          commandId: 'void',
          recordId: first.id,
          expectedRevision: 2,
        );
        await waitFor(
          values,
          (summary) =>
              summary.recordedEntries == 62 && summary.voidedEntries == 1,
          reason: 'void did not refresh the monthly summary',
        );

        final latest = values.last!;
        expect(latest.recordedDays, 2);
        expect(latest.skippedEntries, 0);

        final skipDay = CivilDate(2026, 10, 4);
        await store.saveDailyPlan(
          commandId: 'plan',
          plan: DailyPlanVersion(
            personId: meId,
            planId: 'plan',
            itemId: item.id,
            versionId: 'v1',
            start: skipDay,
            timing: DailyCount(
              1,
              PlannedAmount(
                quantity: ExactQuantity.parse('1'),
                enteredText: '1',
                unit: 'mg',
              ),
            ),
            zoneBasis: FixedHome('Europe/London'),
          ),
          expectedPersonRevision: 1,
          expectedGeneration: store.generation,
        );
        final skipRows = await store.dailyRows(
          from: skipDay,
          toExclusive: skipDay.addDays(1),
          observedZone: 'Europe/London',
        );
        final skipped = await store.actDaily(
          commandId: 'skip',
          row: skipRows.rows.single,
          kind: DailyActionKind.skip,
        );
        await waitFor(
          values,
          (summary) => summary.skippedEntries == 1,
          reason: 'skip did not refresh the monthly summary',
        );
        expect(values.last!.recordedEntries, 62);
        final refreshedRows = await store.dailyRows(
          from: skipDay,
          toExclusive: skipDay.addDays(1),
          observedZone: 'Europe/London',
        );
        await store.undoDaily(
          commandId: 'undo-skip',
          row: refreshedRows.rows.single,
          action: skipped,
        );
        await waitFor(
          values,
          (summary) => summary.skippedEntries == 0,
          reason: 'Undo did not refresh the monthly summary',
        );

        final statusRequest = _request(_query(status: TimelineStatus.voided));
        final voidedValues = <RoutineActivitySummary?>[];
        final voided = container.listen(
          routineActivityProvider(statusRequest),
          (_, next) {
            if (next.hasValue) voidedValues.add(next.value);
          },
          fireImmediately: true,
        );
        addTearDown(voided.close);
        await waitFor(
          voidedValues,
          (summary) =>
              summary.voidedEntries == 1 && summary.recordedEntries == 0,
        );
        expect(voidedValues.last!.showsRecorded, isFalse);
        expect(voidedValues.last!.showsVoided, isTrue);
      },
    );

    test(
      'combined entries count once and a partial range clips daily cells',
      () async {
        final other = await store.createItem(
          commandId: 'other',
          name: 'Recorded supplement',
          form: 'tablet',
          unit: 'mg',
          type: 'supplement',
        );
        await store.recordCombined(
          CombinedUseCommand(
            commandId: 'combined',
            expectedGeneration: store.generation,
            personId: meId,
            expectedPersonRevision: 1,
            actualAt: DateTime.utc(2026, 10, 25, 12),
            components: [
              for (final source in [item, other])
                CombinedUseComponent(
                  itemId: source.id,
                  expectedItemRevision: 1,
                  enteredAmount: '1',
                ),
            ],
          ),
        );
        await record('before-range', DateTime.utc(2026, 10, 25, 0, 30));
        await record('after-range', DateTime.utc(2026, 10, 26, 12));

        final ranged = _query(
          filter: TimelineFilter(
            fromInstant: DateTime.utc(2026, 10, 25, 6),
            beforeInstant: DateTime.utc(2026, 10, 26),
          ),
        );
        final values = <RoutineActivitySummary?>[];
        final subscription = container.listen(
          routineActivityProvider(_request(ranged)),
          (_, next) {
            if (next.hasValue) values.add(next.value);
          },
          fireImmediately: true,
        );
        addTearDown(subscription.close);
        await waitFor(values, (summary) => summary.recordedEntries == 1);
        expect(values.last!.recordedDays, 1);

        final wholeMonth = <RoutineActivitySummary?>[];
        final monthSub = container.listen(routineActivityProvider(_request()), (
          _,
          next,
        ) {
          if (next.hasValue) wholeMonth.add(next.value);
        }, fireImmediately: true);
        addTearDown(monthSub.close);
        await waitFor(wholeMonth, (summary) => summary.recordedEntries == 3);
        expect(wholeMonth.last!.recordedDays, 2);
      },
    );

    test('a locked app yields no summary at all', () async {
      await record('locked', DateTime.utc(2026, 10, 1, 12));
      final locked = ProviderContainer(
        overrides: [
          appLockProvider.overrideWith(_Locked.new),
          recordStoreProvider.overrideWith((ref) async => store),
        ],
      );
      addTearDown(locked.dispose);
      final values = <RoutineActivitySummary?>[];
      final subscription = locked.listen(routineActivityProvider(_request()), (
        _,
        next,
      ) {
        if (next.hasValue) values.add(next.value);
      }, fireImmediately: true);
      addTearDown(subscription.close);
      await _until(() => values.isNotEmpty);
      expect(values, [null]);
    });
  });

  group('monthly disclosure', () {
    testWidgets('starts collapsed with explicit month and scope', (
      tester,
    ) async {
      final query = _query();
      await _pumpActivity(
        tester,
        stream: Stream.value(_summary(query)),
        query: query,
      );
      expect(find.text('Routine activity'), findsOneWidget);
      expect(find.text('October 2026'), findsOneWidget);
      expect(find.text('All entries'), findsOneWidget);
      expect(find.text('Show'), findsOneWidget);
      expect(
        find
            .byKey(const ValueKey('routine-activity-recorded-days'))
            .hitTestable(),
        findsNothing,
      );
      final disclosure = tester.widget<Semantics>(
        find.byWidgetPredicate(
          (widget) => widget is Semantics && widget.properties.expanded != null,
        ),
      );
      expect(disclosure.properties.expanded, isFalse);
      final excluded = tester
          .widgetList<ExcludeFocus>(find.byType(ExcludeFocus))
          .where((widget) => widget.excluding);
      expect(excluded, isNotEmpty);
    });

    testWidgets('Show reveals factual entry counts and Hide collapses them', (
      tester,
    ) async {
      final query = _query();
      await _pumpActivity(
        tester,
        stream: Stream.value(_summary(query)),
        query: query,
      );
      await _expand(tester);
      expect(find.text('Hide'), findsOneWidget);
      expect(find.text('Show'), findsNothing);
      expect(
        tester
            .widget<VitalMetric>(
              find.byKey(const ValueKey('routine-activity-recorded-days')),
            )
            .value,
        '3',
      );
      expect(
        tester
            .widget<VitalMetric>(
              find.byKey(const ValueKey('routine-activity-recorded-entries')),
            )
            .value,
        '5',
      );
      expect(
        tester
            .widget<VitalMetric>(
              find.byKey(const ValueKey('routine-activity-skipped-entries')),
            )
            .value,
        '2',
      );
      expect(
        tester
            .widget<VitalMetric>(
              find.byKey(const ValueKey('routine-activity-voided-entries')),
            )
            .value,
        '1',
      );
      expect(find.text('Entries'), findsOneWidget);
      expect(find.textContaining('Doses'), findsNothing);
      final disclosure = tester.widget<Semantics>(
        find.byWidgetPredicate(
          (widget) => widget is Semantics && widget.properties.expanded != null,
        ),
      );
      expect(disclosure.properties.expanded, isTrue);
      await tester.tap(find.text('Hide'));
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byType(VitalReveal)).height, 0);
      expect(
        find
            .byKey(const ValueKey('routine-activity-recorded-days'))
            .hitTestable(),
        findsNothing,
      );
    });

    testWidgets('filtered scope shows only the selected status facts', (
      tester,
    ) async {
      final query = _query(status: TimelineStatus.skipped);
      await _pumpActivity(
        tester,
        stream: Stream.value(_summary(query)),
        query: query,
      );
      expect(find.text('Filtered entries'), findsOneWidget);
      await _expand(tester);
      expect(
        find.byKey(const ValueKey('routine-activity-recorded-days')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('routine-activity-recorded-entries')),
        findsNothing,
      );
      expect(
        tester
            .widget<VitalMetric>(
              find.byKey(const ValueKey('routine-activity-skipped-entries')),
            )
            .value,
        '2',
      );
      expect(
        find.byKey(const ValueKey('routine-activity-voided-entries')),
        findsNothing,
      );
    });

    testWidgets('locked hides counts immediately even with retained data', (
      tester,
    ) async {
      final query = _query();
      await _pumpActivity(
        tester,
        stream: Stream.value(_summary(query)),
        query: query,
        locked: true,
      );
      expect(find.text('October 2026'), findsOneWidget);
      expect(find.text('All entries'), findsOneWidget);
      await _expand(tester);
      expect(find.text('Unlock to view routine activity.'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('routine-activity-recorded-days')),
        findsNothing,
      );
    });

    testWidgets('loading, failure and retained generations never show counts', (
      tester,
    ) async {
      final controller = StreamController<RoutineActivitySummary?>();
      addTearDown(controller.close);
      await _pumpActivity(tester, stream: controller.stream);
      await _expand(tester);
      expect(find.text('Loading routine activity…'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('routine-activity-recorded-days')),
        findsNothing,
      );

      final query = _query();
      await _pumpActivity(
        tester,
        stream: Stream.error(StateError('read failed')),
        query: query,
      );
      await _expand(tester);
      expect(
        find.text('Routine activity unavailable. Try again.'),
        findsOneWidget,
      );
      expect(find.text('Retry'), findsOneWidget);

      await _pumpActivity(
        tester,
        stream: Stream.value(_summary(query, generation: 'restored')),
        query: query,
        generation: 'current',
      );
      await _expand(tester);
      expect(find.text('Loading routine activity…'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('routine-activity-recorded-days')),
        findsNothing,
      );
    });

    testWidgets('empty month states that there are no entries', (tester) async {
      final query = _query();
      await _pumpActivity(
        tester,
        stream: Stream.value(
          _summary(
            query,
            recordedDays: 0,
            recordedEntries: 0,
            skippedEntries: 0,
            voidedEntries: 0,
          ),
        ),
        query: query,
      );
      await _expand(tester);
      expect(find.text('No entries this month.'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('routine-activity-recorded-days')),
        findsNothing,
      );
    });

    testWidgets('fits 320, 390 and 430 widths at 2x text in both themes', (
      tester,
    ) async {
      final query = _query();
      for (final brightness in Brightness.values) {
        for (final width in [320.0, 390.0, 430.0]) {
          await _pumpActivity(
            tester,
            stream: Stream.value(_summary(query)),
            query: query,
            width: width,
            textScale: 2,
            brightness: brightness,
            reduceMotion: true,
          );
          await _expand(tester);
          expect(
            find.byKey(const ValueKey('routine-activity-recorded-days')),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
        }
      }
    });

    testWidgets('the Show command remains keyboard reachable', (tester) async {
      final query = _query();
      await _pumpActivity(
        tester,
        stream: Stream.value(_summary(query)),
        query: query,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.text('Hide'), findsOneWidget);
      // The shared disclosure button exposes a button role and expanded state.
      final semantics = tester.getSemantics(find.text('Hide'));
      expect(
        semantics,
        isSemantics(isButton: true, hasExpandedState: true, isExpanded: true),
      );
    });
  });

  appTest('monthly summary counts the whole month, not the selected day page', (
    tester,
  ) async {
    final fixture = await launch(tester);
    final item = (await runIo(
      tester,
      () => historyItem(fixture.store, 'Monthly summary fixture'),
    ))!;
    await runIo(tester, () async {
      for (var day = 1; day <= 9; day++) {
        for (var copy = 0; copy < 2; copy++) {
          await historyRecord(fixture.store, item, CivilDate(2026, 10, day));
        }
      }
      for (var i = 0; i < 60; i++) {
        await historyRecord(fixture.store, item, CivilDate(2026, 10, 10));
      }
    });
    fixture.container
        .read(routerProvider)
        .go('/history?month=2026-10-01&selected=2026-10-10');
    await settle(tester);
    expect(find.text('Routine activity'), findsOneWidget);
    await tap(tester, 'Show');
    expect(
      tester
          .widget<VitalMetric>(
            find.byKey(const ValueKey('routine-activity-recorded-days')),
          )
          .value,
      '10',
    );
    expect(
      tester
          .widget<VitalMetric>(
            find.byKey(const ValueKey('routine-activity-recorded-entries')),
          )
          .value,
      '78',
    );
  });
}
