import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:true_grit_vital/app/app_lock.dart';
import 'package:true_grit_vital/app/appearance.dart';
import 'package:true_grit_vital/app/history.dart';
import 'package:true_grit_vital/app/vital_app.dart';
import 'package:true_grit_vital/domain/scheduling/daily_plan.dart'
    show CivilDate;
import 'package:true_grit_vital/features/history/history_calendar.dart';
import 'package:true_grit_vital/features/history/history_date_jump.dart';
import 'package:true_grit_vital/features/reports/reports_page.dart';
import 'package:true_grit_vital/ui/stitch_ui.dart' show StitchButton;
import 'package:true_grit_vital/ui/vital_ui.dart';

import 'history_mobile_ui_test.dart' show historyItem, historyRecord, today;
import 'private_drafts_ui_test.dart' show fixture;
import 'design_system_test.dart' show host;
import 'vital_app_test.dart' show appTest, launch, runIo, settle, tap;

const captureDirectory = String.fromEnvironment(
  'VITAL_HISTORY_DATE_JUMP_CAPTURE',
);
const dialogKey = ValueKey('history-date-jump-dialog');

Finder jumpTrigger() => find.byKey(const ValueKey('history-date-jump'));

Future<void> openJump(WidgetTester tester) async {
  final trigger = jumpTrigger();
  await tester.ensureVisible(trigger);
  await settle(tester);
  await tester.tap(trigger);
  await settle(tester);
  expect(find.byKey(dialogKey), findsOneWidget);
}

Future<void> enterJump(WidgetTester tester, String value) async {
  await tester.enterText(
    find.byKey(const ValueKey('history-date-jump-field')),
    value,
  );
  await settle(tester);
}

Future<void> confirmJump(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(VitalButton, 'Go'));
  await settle(tester);
  expect(find.byKey(dialogKey), findsNothing);
}

Future<void> confirmJumpExpectingError(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(VitalButton, 'Go'));
  await settle(tester);
  expect(find.byKey(dialogKey), findsOneWidget);
}

Future<void> closeJump(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(VitalButton, 'Cancel'));
  await settle(tester);
  expect(find.byKey(dialogKey), findsNothing);
}

Future<void> expectDay(
  WidgetTester tester,
  ProviderContainer container,
  String location,
  CivilDate date,
) async {
  final grid = tester.widget<HistoryMonthGrid>(find.byType(HistoryMonthGrid));
  expect(grid.month, CivilDate(date.year, date.month, 1));
  expect(grid.selected, date);
  final query = container.read(historyControllerProvider(location)).query!;
  final bounds = DisplayTime().dayBounds(date, 'Europe/London');
  expect(query.filter.fromInstant, bounds.start);
  expect(query.filter.beforeInstant, bounds.endExclusive);
}

Future<void> capture(
  WidgetTester tester,
  GlobalKey boundaryKey,
  String name,
) async {
  if (captureDirectory.isEmpty) return;
  final boundary =
      boundaryKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
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
  group('parseHistoryJumpDate', () {
    test(
      'accepts real leap days and rejects malformed or impossible values',
      () {
        expect(parseHistoryJumpDate('2028-02-29'), CivilDate(2028, 2, 29));
        expect(parseHistoryJumpDate(' 2028-02-29 '), CivilDate(2028, 2, 29));
        expect(parseHistoryJumpDate('2026-10-22'), CivilDate(2026, 10, 22));
        expect(parseHistoryJumpDate('0001-01-01'), CivilDate(1, 1, 1));
        expect(parseHistoryJumpDate('9999-12-30'), CivilDate(9999, 12, 30));
        for (final value in [
          '',
          '2026-2-3',
          '2026-02-30',
          '2025-02-29',
          '2026-13-01',
          '2026-04-31',
          '0000-01-01',
          '10000-01-01',
          '9999-12-31',
          'not-a-date',
        ]) {
          expect(parseHistoryJumpDate(value), isNull, reason: value);
        }
      },
    );
  });

  setUpAll(() async {
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

  appTest(
    'exact leap day and distant year keep filters, query bounds and return location',
    (tester) async {
      final f = await launch(tester);
      final item = (await runIo(
        tester,
        () => historyItem(f.store, 'Jump fixture medicine'),
      ))!;
      final generation = f.store.generation;
      final location = Uri(
        path: '/history',
        queryParameters: {
          'type': 'Medicine',
          'event': 'selected-course',
          'status': 'recorded',
          'item': item.id,
          'unit': 'mg',
          'view': 'calendar',
        },
      ).toString();
      f.container.read(routerProvider).go(location);
      await settle(tester);
      final original = f.container
          .read(historyControllerProvider(location))
          .query!;
      expect(original.filter.scope.personId, item.personId);

      for (final date in [
        CivilDate(1, 1, 1),
        CivilDate(2028, 2, 29),
        CivilDate(2031, 12, 31),
      ]) {
        await openJump(tester);
        await enterJump(tester, date.toString());
        if (date.year == 1) {
          expect(
            find.text('Use YYYY-MM-DD. The day uses UTC.'),
            findsOneWidget,
          );
        }
        await confirmJump(tester);
        await expectDay(tester, f.container, location, date);
        final query = f.container
            .read(historyControllerProvider(location))
            .query!;
        expect(query.filter.typeIds, {'Medicine'});
        expect(query.filter.eventIds, {'selected-course'});
        expect(query.filter.status, TimelineStatus.recorded);
        expect(query.filter.itemId, item.id);
        expect(query.filter.actualUnit, 'mg');
        expect(query.filter.scope.personId, item.personId);
        expect(f.store.generation, generation);
      }

      await tap(tester, 'More');
      await tap(tester, 'Reports');
      final uri = GoRouterState.of(tester.element(find.byType(ReportsPage)))
          .uri;
      final back = Uri.parse(uri.queryParameters['return']!).queryParameters;
      expect(back['month'], '2031-12-01');
      expect(back['selected'], '2031-12-31');
      expect(back['status'], 'recorded');
      expect(back['view'], 'calendar');
      expect(back['type'], 'Medicine');
      expect(back['event'], 'selected-course');
      expect(back['item'], item.id);
      expect(back['unit'], 'mg');
      f.container.read(routerProvider).pop();
      await settle(tester);

      await tester.ensureVisible(find.widgetWithText(StitchButton, 'Today'));
      await settle(tester);
      await tester.tap(find.widgetWithText(StitchButton, 'Today'));
      await settle(tester);
      final todayDate = today();
      expect(
        tester.widget<HistoryMonthGrid>(find.byType(HistoryMonthGrid)).selected,
        todayDate,
      );
      expect(tester.takeException(), isNull);
    },
  );

  appTest(
    'malformed, impossible and out-of-range dates stay in the dialog and change nothing',
    (tester) async {
      final f = await launch(tester);
      f.container.read(routerProvider).go('/history');
      await settle(tester);
      final original = f.container
          .read(historyControllerProvider('/history'))
          .query!;
      final grid = tester.widget<HistoryMonthGrid>(
        find.byType(HistoryMonthGrid),
      );
      final month = grid.month, selected = grid.selected;
      for (final value in [
        '',
        '2026-2-3',
        '2026-02-30',
        '2025-02-29',
        '2026-13-01',
        '2026-04-31',
        '0000-01-01',
        '10000-01-01',
        '9999-12-31',
        'not-a-date',
      ]) {
        await openJump(tester);
        await enterJump(tester, value);
        await confirmJumpExpectingError(tester);
        expect(
          find.text('Use YYYY-MM-DD, from 0001-01-01 to 9999-12-30.'),
          findsOneWidget,
          reason: value,
        );
        expect(find.byKey(dialogKey), findsOneWidget);
        expect(
          tester.widget<HistoryMonthGrid>(find.byType(HistoryMonthGrid)).month,
          month,
        );
        expect(
          tester
              .widget<HistoryMonthGrid>(find.byType(HistoryMonthGrid))
              .selected,
          selected,
        );
        await closeJump(tester);
      }
      expect(
        f.container.read(historyControllerProvider('/history')).query!.identity,
        original.identity,
      );
      expect(tester.takeException(), isNull);
    },
  );

  appTest(
    'existing zone bounds survive the spring and autumn daylight changes',
    (tester) async {
      final f = await launch(tester);
      f.container.read(routerProvider).go('/history');
      await settle(tester);
      for (final entry in [
        (CivilDate(2026, 3, 29), const Duration(hours: 23)),
        (CivilDate(2026, 10, 25), const Duration(hours: 25)),
      ]) {
        await openJump(tester);
        await enterJump(tester, entry.$1.toString());
        await confirmJump(tester);
        await expectDay(tester, f.container, '/history', entry.$1);
        final bounds = DisplayTime().dayBounds(entry.$1, 'Europe/London');
        expect(bounds.duration, entry.$2);
        final query = f.container
            .read(historyControllerProvider('/history'))
            .query!;
        expect(query.filter.fromInstant, bounds.start);
        expect(query.filter.beforeInstant, bounds.endExclusive);
      }
      expect(tester.takeException(), isNull);
    },
  );

  appTest('cancel, Escape and Back leave the day unchanged and return focus', (
    tester,
  ) async {
    final f = await launch(tester);
    f.container.read(routerProvider).go('/history');
    await settle(tester);
    final selected = tester
        .widget<HistoryMonthGrid>(find.byType(HistoryMonthGrid))
        .selected;

    await openJump(tester);
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'history-date-jump-field',
    );
    await enterJump(tester, '2029-01-15');
    await closeJump(tester);
    expect(
      tester.widget<HistoryMonthGrid>(find.byType(HistoryMonthGrid)).selected,
      selected,
    );
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'history-date-jump');

    await openJump(tester);
    await enterJump(tester, '2029-01-15');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settle(tester);
    expect(find.byKey(dialogKey), findsNothing);
    expect(
      tester.widget<HistoryMonthGrid>(find.byType(HistoryMonthGrid)).selected,
      selected,
    );
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'history-date-jump');

    await openJump(tester);
    await enterJump(tester, '2029-01-15');
    await tester.binding.handlePopRoute();
    await settle(tester);
    expect(find.byKey(dialogKey), findsNothing);
    expect(
      tester.widget<HistoryMonthGrid>(find.byType(HistoryMonthGrid)).selected,
      selected,
    );
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'history-date-jump');

    await openJump(tester);
    await enterJump(tester, '2029-01-15');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await settle(tester);
    expect(find.byKey(dialogKey), findsNothing);
    await expectDay(tester, f.container, '/history', CivilDate(2029, 1, 15));
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'history-date-jump');
    expect(tester.takeException(), isNull);
  });

  appTest('privacy lock closes an open date jump without changing the day', (
    tester,
  ) async {
    final f = await fixture(tester, enabled: true);
    await runIo(
      tester,
      () => f.container.read(appLockProvider.notifier).unlock(),
    );
    await settle(tester);
    f.container.read(routerProvider).go('/history');
    await settle(tester);
    final selected = tester
        .widget<HistoryMonthGrid>(find.byType(HistoryMonthGrid))
        .selected;

    await openJump(tester);
    await enterJump(tester, '2029-02-14');
    f.container.read(appLockProvider.notifier).lock();
    await settle(tester);
    expect(find.byKey(dialogKey), findsNothing);
    expect(find.text('Unlock'), findsWidgets);

    await runIo(
      tester,
      () => f.container.read(appLockProvider.notifier).unlock(),
    );
    await settle(tester);
    expect(
      tester.widget<HistoryMonthGrid>(find.byType(HistoryMonthGrid)).selected,
      selected,
    );
    expect(tester.takeException(), isNull);
  });

  appTest('a changed zone cancels confirmation of the earlier displayed zone', (
    tester,
  ) async {
    final f = await launch(tester);
    final zone = ValueNotifier('Europe/London');
    addTearDown(zone.dispose);
    CivilDate? selected;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: f.container,
        child: host(
          ValueListenableBuilder<String>(
            valueListenable: zone,
            builder: (_, value, _) => HistoryDateJumpButton(
              zone: value,
              selected: null,
              onSelected: (date) => selected = date,
            ),
          ),
        ),
      ),
    );
    await settle(tester);
    await openJump(tester);
    await enterJump(tester, '2029-01-15');
    zone.value = 'UTC';
    await settle(tester);
    expect(
      find.text('Use YYYY-MM-DD. The day uses Europe/London.'),
      findsOneWidget,
    );
    await confirmJump(tester);
    expect(selected, isNull);
    expect(tester.takeException(), isNull);
  });

  for (final theme in [ThemeMode.light, ThemeMode.dark]) {
    appTest(
      'date jump stays usable at 320 px and double text in ${theme.name}',
      (tester) async {
        tester.view.physicalSize = const Size(320, 900);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        addTearDown(tester.view.reset);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final semantics = tester.ensureSemantics();
        try {
          final f = await launch(tester);
          f.container.read(appearanceProvider.notifier).setMode(theme);
          f.container.read(routerProvider).go('/history');
          await settle(tester);

          final trigger = jumpTrigger();
          await tester.ensureVisible(trigger);
          await settle(tester);
          expect(tester.getSize(trigger).height, greaterThanOrEqualTo(48));
          final data = tester.getSemantics(trigger).getSemanticsData();
          expect(data.label, 'Go to date');
          expect(data.hasAction(SemanticsAction.tap), isTrue);
          expect(trigger.hitTestable(), findsOneWidget);

          await openJump(tester);
          expect(find.byKey(dialogKey), findsOneWidget);
          final field = find.byKey(const ValueKey('history-date-jump-field'));
          expect(tester.getRect(field).height, greaterThanOrEqualTo(48));
          expect(find.widgetWithText(VitalButton, 'Cancel'), findsOneWidget);
          expect(find.widgetWithText(VitalButton, 'Go'), findsOneWidget);
          expect(tester.takeException(), isNull);

          await enterJump(tester, '2030-06-15');
          await confirmJump(tester);
          await expectDay(
            tester,
            f.container,
            '/history',
            CivilDate(2030, 6, 15),
          );
          expect(tester.takeException(), isNull);
        } finally {
          semantics.dispose();
        }
      },
    );
  }

  if (captureDirectory.isNotEmpty) {
    for (final theme in [ThemeMode.light, ThemeMode.dark]) {
      appTest('capture canonical History date jump in ${theme.name}', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        tester.view.padding = const FakeViewPadding(top: 28, bottom: 24);
        tester.view.viewPadding = const FakeViewPadding(top: 28, bottom: 24);
        addTearDown(tester.view.reset);
        final f = await launch(tester);
        final item = (await runIo(
          tester,
          () => historyItem(f.store, 'Synthetic jump medicine'),
        ))!;
        await runIo(tester, () async {
          await historyRecord(f.store, item, today());
          await historyRecord(f.store, item, today().addDays(-1));
        });
        f.container.read(appearanceProvider.notifier).setMode(theme);
        final boundaryKey = GlobalKey();
        f.container.read(routerProvider).go('/history');
        await settle(tester);
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: f.container,
            child: RepaintBoundary(key: boundaryKey, child: const VitalApp()),
          ),
        );
        await settle(tester);
        await openJump(tester);
        await enterJump(tester, '2028-02-29');
        expect(tester.takeException(), isNull);
        await capture(tester, boundaryKey, '${theme.name}-history-date-jump');

        if (theme == ThemeMode.dark) {
          tester.platformDispatcher.textScaleFactorTestValue = 2;
          tester.view.physicalSize = const Size(320, 740);
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          await settle(tester);
          expect(tester.takeException(), isNull);
          await capture(
            tester,
            boundaryKey,
            'dark-history-date-jump-narrow-double-text',
          );
        }
      });
    }
  }
}
