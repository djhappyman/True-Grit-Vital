import 'dart:async';
import 'dart:ui' show SemanticsAction, SemanticsActionEvent;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:true_grit_vital/features/history/history_source.dart';
import 'package:true_grit_vital/features/recording/record_pages.dart';

import 'design_system_test.dart' show host;

import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:true_grit_vital/app/history.dart';
import 'package:true_grit_vital/app/vital_app.dart';
import 'package:true_grit_vital/data/record_store.dart';
import 'package:true_grit_vital/features/exports/export_pages.dart';
import 'package:true_grit_vital/features/history/history_pages.dart';
import 'package:true_grit_vital/features/history/history_calendar.dart';
import 'package:true_grit_vital/ui/stitch_ui.dart';
import 'package:true_grit_vital/features/reports/reports_page.dart';

import 'history_mobile_ui_test.dart' show historyItem, historyRecord, today;
import 'vital_app_test.dart'
    show appTest, launch, runIo, settle, tap, waitForText;

void main() {
  appTest(
    'calendar opens on today with compact cards and hidden secondary tools',
    (tester) async {
      final f = await launch(tester);
      await runIo(tester, () async {
        final item = await historyItem(f.store, 'Complete medicine name');
        await historyRecord(f.store, item, today());
        await historyRecord(f.store, item, today().addDays(-1), amount: '2');
      });
      f.container.read(routerProvider).go('/history');
      await settle(tester);
      expect(
        tester.widget<HistoryMonthGrid>(find.byType(HistoryMonthGrid)).selected,
        today(),
      );
      expect(find.byType(HistoryEntryCard), findsOneWidget);
      expect(find.textContaining('1 mg · Tablet'), findsOneWidget);
      expect(find.textContaining('2 mg · Tablet'), findsNothing);
      for (final hidden in [
        'Charts',
        'Reports',
        'Development preview',
        'Timeline',
        'All',
        'View',
      ]) {
        expect(find.text(hidden), findsNothing);
      }
      final yesterday = today().addDays(-1);
      final cell = find.byKey(ValueKey('history-day-$yesterday'));
      await tester.ensureVisible(cell);
      await tester.tap(cell);
      await settle(tester);
      final query = f.container
          .read(historyControllerProvider('/history'))
          .query!;
      final bounds = DisplayTime().dayBounds(yesterday, query.displayZone);
      expect(query.filter.fromInstant, bounds.start);
      expect(query.filter.beforeInstant, bounds.endExclusive);
      expect(find.textContaining('2 mg · Tablet'), findsOneWidget);
      expect(find.textContaining('1 mg · Tablet'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  appTest(
    'month navigation and monthly PDF selection use the displayed month',
    (tester) async {
      final f = await launch(tester);
      f.container.read(routerProvider).go('/history');
      await settle(tester);
      tester
          .widget<HistoryMonthGrid>(find.byType(HistoryMonthGrid))
          .onMonth(CivilDate(2026, 12, 1));
      await settle(tester);
      expect(
        tester.widget<HistoryMonthGrid>(find.byType(HistoryMonthGrid)).selected,
        CivilDate(2026, 12, 1),
      );
      final bounds = DisplayTime().dayBounds(
        CivilDate(2026, 12, 1),
        'Europe/London',
      );
      expect(
        f.container
            .read(historyControllerProvider('/history'))
            .query!
            .filter
            .fromInstant,
        bounds.start,
      );
      await tap(tester, 'Export');
      final uri = GoRouterState.of(tester.element(find.byType(ReportsPage)))
          .uri;
      expect(uri.queryParameters['from'], '2026-12-01');
      expect(uri.queryParameters['before'], '2027-01-01');
      final back = Uri.parse(uri.queryParameters['return']!);
      expect(back.queryParameters['selected'], '2026-12-01');
      f.container.read(routerProvider).pop();
      await settle(tester);
      expect(
        tester.widget<HistoryMonthGrid>(find.byType(HistoryMonthGrid)).month,
        CivilDate(2026, 12, 1),
      );
    },
  );

  appTest('history export and reports carry the shown range and return link', (
    tester,
  ) async {
    final f = await launch(tester);
    f.container.read(routerProvider).go('/history');
    await settle(tester);
    await tap(tester, 'More');
    await tap(tester, 'Export');
    final export = GoRouterState.of(tester.element(find.byType(ExportPage)))
        .uri;
    expect(export.path, '/exports');
    expect(export.queryParameters['from'], isNotNull);
    expect(export.queryParameters['before'], isNotNull);
    expect(export.queryParameters['content'], 'doses');
    expect(Uri.parse(export.queryParameters['return']!).path, '/history');
    f.container.read(routerProvider).pop();
    await settle(tester);
    await tap(tester, 'More');
    await tap(tester, 'Reports');
    final reports = GoRouterState.of(tester.element(find.byType(ReportsPage)))
        .uri;
    expect(reports.path, '/reports');
    expect(reports.queryParameters['person'], meId);
    expect(reports.queryParameters['from'], isNotNull);
    expect(reports.queryParameters['before'], isNotNull);
    final back = Uri.parse(reports.queryParameters['return']!).queryParameters;
    expect(back['status'], 'all');
    expect(back['view'], 'calendar');
    expect(tester.takeException(), isNull);
  });

  appTest('artifact drafts ignore unapplied date edits', (tester) async {
    final f = await launch(tester);
    final day = today().addDays(-7);
    final bounds = DisplayTime().dayBounds(day, 'Europe/London');
    f.container
        .read(routerProvider)
        .go(
          Uri(
            path: '/history',
            queryParameters: {
              'from': bounds.start.toIso8601String(),
              'before': bounds.endExclusive.toIso8601String(),
            },
          ).toString(),
        );
    await settle(tester);
    if (find.widgetWithText(LabelledInput, 'From').evaluate().isEmpty) {
      final toggle = find.byKey(const ValueKey('history-filters-toggle'));
      await tester.ensureVisible(toggle);
      await tester.tap(
        find.descendant(of: toggle, matching: find.byType(Button)).first,
      );
      await settle(tester);
    }
    await waitForText(tester, 'From');
    final field = find.descendant(
      of: find.widgetWithText(LabelledInput, 'From'),
      matching: find.byType(TextField),
    );
    await tester.ensureVisible(field);
    await tester.enterText(field, '1999-01-01');
    await settle(tester);
    await tester.tapAt(const Offset(2, 2));
    await settle(tester);
    for (final action in ['Export', 'Reports']) {
      await tap(tester, 'More');
      await tap(tester, action);
      final uri = GoRouterState.of(
        tester.element(
          action == 'Export'
              ? find.byType(ExportPage)
              : find.byType(ReportsPage),
        ),
      ).uri;
      expect(uri.queryParameters['from'], day.toString());
      expect(uri.queryParameters['before'], day.addDays(1).toString());
      f.container.read(routerProvider).pop();
      await settle(tester);
    }
  });

  appTest('View can be activated through its accessible action', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    try {
      final f = await launch(tester);
      await runIo(tester, () async {
        final item = await historyItem(f.store, 'Accessible history item');
        await historyRecord(f.store, item, today());
      });
      f.container.read(routerProvider).go('/history');
      await settle(tester);
      final target = find.descendant(
        of: find.byType(HistoryEntryCard),
        matching: find.byType(StitchButton),
      );
      await tester.ensureVisible(target);
      await settle(tester);
      final node = tester.getSemantics(target);
      expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
      tester.binding.performSemanticsAction(
        SemanticsActionEvent(
          type: SemanticsAction.tap,
          nodeId: node.id,
          viewId: tester.view.viewId,
        ),
      );
      await settle(tester);
      expect(find.byType(HistorySourcePage), findsOneWidget);
    } finally {
      handle.dispose();
    }
  });

  testWidgets('unavailable month counts never announce zero records', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    try {
      final pending = Completer<HistoryCalendar?>();
      final day = today();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            historyCalendarProvider.overrideWith(
              (ref, request) => pending.future,
            ),
          ],
          child: host(
            HistoryCalendarSection(
              query: TimelineQuery(
                filter: TimelineFilter(scope: const FeedScope.me()),
                displayZone: 'Europe/London',
              ),
              month: CivilDate(day.year, day.month, 1),
              selected: day,
              onMonth: (_) {},
              onSelect: (_) {},
            ),
          ),
        ),
      );
      await tester.pump();
      final cell = find.byKey(ValueKey('history-day-$day'));
      expect(
        tester.getSemantics(cell).getSemanticsData().label,
        contains('Loading day counts'),
      );
      expect(
        tester.getSemantics(cell).getSemanticsData().label,
        isNot(contains('0 recorded')),
      );
      pending.completeError(StateError('unavailable'));
      await tester.pumpAndSettle();
      expect(
        tester.getSemantics(cell).getSemanticsData().label,
        contains('Unable to load history'),
      );
      expect(
        tester.getSemantics(cell).getSemanticsData().label,
        isNot(contains('0 recorded')),
      );
    } finally {
      handle.dispose();
    }
  });

  appTest('skipped use stays truthful and never claims PRN or adherence', (
    tester,
  ) async {
    final f = await launch(tester);
    await runIo(tester, () async {
      final item = await historyItem(f.store, 'Skipped complete medicine');
      await f.store.saveDailyPlan(
        commandId: newCommandId(),
        expectedPersonRevision: 2,
        expectedGeneration: f.store.generation,
        plan: DailyPlanVersion(
          personId: meId,
          planId: 'screen-history-plan',
          itemId: item.id,
          versionId: 'screen-history-version',
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
    expect(find.textContaining('Skipped'), findsWidgets);
    expect(
      find.text(
        'This is a skipped planned occurrence. It is not recorded use.',
      ),
      findsNothing,
    );
    expect(find.textContaining('PRN'), findsNothing);
    expect(find.textContaining('As-Needed'), findsNothing);
    expect(find.textContaining('On Track'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final width in [320.0, 430.0]) {
    appTest('history keeps every day and action reachable at $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 844);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(() {
        tester.view.reset();
        tester.platformDispatcher.clearTextScaleFactorTestValue();
      });
      final f = await launch(tester);
      await runIo(tester, () async {
        final item = await historyItem(
          f.store,
          'Long complete medicine name that wraps without truncation',
        );
        await historyRecord(f.store, item, today());
      });
      f.container.read(routerProvider).go('/history');
      await settle(tester);
      final grid = tester.widget<HistoryMonthGrid>(
        find.byType(HistoryMonthGrid),
      );
      expect(find.byKey(ValueKey('history-day-${grid.month}')), findsOneWidget);
      expect(find.text('All'), findsNothing);
      final action = find.descendant(
        of: find.byType(HistoryEntryCard),
        matching: find.byType(StitchIcon),
      );
      await tester.ensureVisible(action);
      await settle(tester);
      expect(action.hitTestable(), findsOneWidget);
      expect(
        tester
            .getSize(find.byKey(const ValueKey('history-filters-toggle')))
            .height,
        greaterThanOrEqualTo(48),
      );
      expect(tester.takeException(), isNull);
    });
  }
}
