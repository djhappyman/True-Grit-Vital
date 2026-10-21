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
import 'package:true_grit_vital/features/reports/reports_page.dart';
import 'package:true_grit_vital/ui/vital_ui.dart';

import 'history_mobile_ui_test.dart' show historyItem, historyRecord, today;
import 'vital_app_test.dart' show appTest, launch, runIo, settle, tap;

void main() {
  appTest('history groups real days and keeps complete names and amounts', (
    tester,
  ) async {
    final f = await launch(tester);
    await runIo(tester, () async {
      final item = await historyItem(
        f.store,
        'Complete original medicine name that stays whole',
      );
      await historyRecord(f.store, item, today());
      await historyRecord(f.store, item, today().addDays(-1), amount: '2');
    });
    f.container.read(routerProvider).go('/history');
    await settle(tester);

    expect(
      find.text('Complete original medicine name that stays whole'),
      findsWidgets,
    );
    expect(find.textContaining('1 mg · Tablet'), findsOneWidget);
    expect(find.textContaining('2 mg · Tablet'), findsOneWidget);
    expect(find.text('Today'), findsWidgets);
    expect(find.text('Yesterday'), findsOneWidget);
    expect(find.text('Recorded'), findsWidgets);
    for (final hidden in ['PRN', 'As-Needed', 'Integrity', 'On Track']) {
      expect(find.textContaining(hidden), findsNothing, reason: hidden);
    }
    // The audit section is an explicit preview, never invented data.
    final audit = find.text(
      'Adherence and integrity measures are not available yet. '
      'Your records are unchanged.',
    );
    await tester.ensureVisible(audit);
    expect(audit, findsOneWidget);
    expect(find.text('Development preview'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  appTest('week strip selects one real day and reflects its counts', (
    tester,
  ) async {
    final f = await launch(tester);
    final item = (await runIo(
      tester,
      () => historyItem(f.store, 'Week strip medicine'),
    ))!;
    await runIo(tester, () async {
      await historyRecord(f.store, item, today());
      await historyRecord(f.store, item, today().addDays(-1));
    });
    f.container.read(routerProvider).go('/history');
    await settle(tester);
    final yesterday = today().addDays(-1);
    final cell = find.byKey(ValueKey('history-week-$yesterday'));
    await tester.ensureVisible(cell);
    await settle(tester);
    await tester.tap(cell);
    await settle(tester);
    final query = f.container
        .read(historyControllerProvider('/history'))
        .query!;
    final bounds = DisplayTime().dayBounds(yesterday, query.displayZone);
    expect(query.filter.fromInstant, bounds.start);
    expect(query.filter.beforeInstant, bounds.endExclusive);
    expect(
      tester.widget<HistoryWeekStrip>(find.byType(HistoryWeekStrip)).selected,
      yesterday,
    );
    expect(find.byType(HistoryEntryCard), findsOneWidget);
    expect(find.text('Showing 1 entry.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  appTest('history export and reports carry the shown range and return link', (
    tester,
  ) async {
    final f = await launch(tester);
    f.container.read(routerProvider).go('/history');
    await settle(tester);
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
    await tap(tester, 'Reports');
    final reports = GoRouterState.of(tester.element(find.byType(ReportsPage)))
        .uri;
    expect(reports.path, '/reports');
    expect(reports.queryParameters['person'], meId);
    expect(reports.queryParameters['from'], isNotNull);
    expect(reports.queryParameters['before'], isNotNull);
    final back = Uri.parse(reports.queryParameters['return']!).queryParameters;
    expect(back['status'], 'all');
    expect(back['view'], 'list');
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
      final toggle = find.widgetWithText(VitalButton, 'Filters');
      await tester.ensureVisible(toggle);
      await tester.tap(toggle);
      await settle(tester);
    }
    final field = find.descendant(
      of: find.widgetWithText(LabelledInput, 'From'),
      matching: find.byType(TextField),
    );
    await tester.ensureVisible(field);
    await tester.enterText(field, '1999-01-01');
    await settle(tester);
    for (final action in ['Export', 'Reports']) {
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
      final target = find.bySemanticsLabel('View Accessible history item');
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

  testWidgets('unavailable week counts never announce zero records', (
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
            HistoryWeekStrip(
              query: TimelineQuery(
                filter: TimelineFilter(scope: const FeedScope.me()),
                displayZone: 'Europe/London',
              ),
              today: day,
              selected: null,
              onSelect: (_) {},
            ),
          ),
        ),
      );
      await tester.pump();
      final cell = find.byKey(ValueKey('history-week-$day'));
      expect(
        tester.getSemantics(cell).getSemanticsData().label,
        contains('Opening records'),
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
    expect(find.text('Skipped'), findsWidgets);
    expect(
      find.text(
        'This is a skipped planned occurrence. It is not recorded use.',
      ),
      findsOneWidget,
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
      for (var i = 0; i < 7; i++) {
        expect(
          find.byKey(ValueKey('history-week-${today().addDays(-i)}')),
          findsOneWidget,
          reason: 'day $i',
        );
      }
      for (final label in ['All', 'Recorded', 'Skipped', 'Voided', 'Filters']) {
        expect(find.text(label), findsWidgets, reason: label);
      }
      final view = find.text('View');
      await tester.ensureVisible(view);
      await settle(tester);
      expect(view.hitTestable(), findsOneWidget);
      expect(
        tester.getSize(find.widgetWithText(VitalButton, 'Filters')).height,
        greaterThanOrEqualTo(48),
      );
      expect(tester.takeException(), isNull);
    });
  }
}
