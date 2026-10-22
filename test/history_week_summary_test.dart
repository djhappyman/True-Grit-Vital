import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:true_grit_vital/app/app_lock.dart';
import 'package:true_grit_vital/app/vital_app.dart';
import 'package:true_grit_vital/data/record_store.dart';
import 'package:true_grit_vital/features/history/history_calendar.dart';
import 'package:true_grit_vital/features/history/history_pages.dart';

import 'design_system_test.dart' show host;
import 'history_mobile_ui_test.dart' show historyItem, historyRecord;
import 'vital_app_test.dart' show appTest, launch, runIo, settle;

final _selected = CivilDate(2026, 10, 7);
final _weekStart = CivilDate(2026, 10, 5);

TimelineQuery _query([TimelineStatus status = TimelineStatus.all]) =>
    TimelineQuery(
      filter: TimelineFilter(scope: const FeedScope.me(), status: status),
      displayZone: 'Europe/London',
    );

HistoryCalendar _calendar(
  TimelineQuery query, {
  int recorded = 3,
  int skipped = 2,
  int voided = 1,
}) => HistoryCalendar(
  queryIdentity: query.identity,
  generation: 'test',
  cells: [
    for (var i = 0; i < 7; i++)
      HistoryCalendarCell(
        date: _weekStart.addDays(i),
        recorded: i == 0 ? recorded : 0,
        skipped: i == 0 ? skipped : 0,
        voided: i == 0 ? voided : 0,
      ),
  ],
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

Future<void> _pumpWeek(
  WidgetTester tester, {
  required TimelineQuery query,
  required Future<HistoryCalendar?> Function(CalendarRequest) load,
  bool locked = false,
  Brightness brightness = Brightness.light,
  double width = 358,
  double textScale = 1,
  bool reduceMotion = false,
  ValueChanged<CivilDate>? onSelect,
}) async {
  tester.view.physicalSize = const Size(800, 1200);
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  tester.platformDispatcher.accessibilityFeaturesTestValue =
      FakeAccessibilityFeatures(disableAnimations: reduceMotion);
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appLockProvider.overrideWith(locked ? _Locked.new : _Unlocked.new),
        historyCalendarProvider.overrideWith((ref, request) => load(request)),
      ],
      child: host(
        SingleChildScrollView(
          child: SizedBox(
            width: width,
            child: HistoryWeekStrip(
              query: query,
              today: _selected,
              selected: _selected,
              onSelect: onSelect ?? (_) {},
            ),
          ),
        ),
        brightness: brightness,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  test('selected week follows the locale first day and crosses boundaries', () {
    for (final firstDay in [0, 1, 2, 3, 4, 5, 6]) {
      final dates = historyWeekDates(_selected, firstDay);
      expect(dates, hasLength(7));
      expect(dates, contains(_selected));
      expect(dates.first.calendarValue.weekday % 7, firstDay);
      for (var i = 1; i < dates.length; i++) {
        expect(dates[i], dates[i - 1].addDays(1));
      }
    }
    expect(
      historyWeekDates(CivilDate(2027, 1, 1), 1).first,
      CivilDate(2026, 12, 28),
    );
    expect(
      historyWeekDates(CivilDate(2026, 10, 5), 0).first,
      CivilDate(2026, 10, 4),
    );
    for (final firstDay in [0, 6]) {
      final earliest = historyWeekDates(CivilDate(1, 1, 1), firstDay);
      expect(earliest, hasLength(7));
      expect(earliest, contains(CivilDate(1, 1, 1)));
      expect(earliest.last, CivilDate(1, 1, 7));
      final latest = historyWeekDates(CivilDate(9999, 12, 31), firstDay);
      expect(latest, hasLength(7));
      expect(latest, contains(CivilDate(9999, 12, 31)));
      expect(latest.first, CivilDate(9999, 12, 25));
    }
  });

  testWidgets(
    'all statuses show exact week metrics and accessible day counts',
    (tester) async {
      final handle = tester.ensureSemantics();
      try {
        final query = _query();
        await _pumpWeek(
          tester,
          query: query,
          load: (_) async => _calendar(query),
        );
        expect(find.text('Selected week'), findsOneWidget);
        expect(find.text('From 5 Oct 2026 to 11 Oct 2026'), findsOneWidget);
        for (final (key, value) in [
          ('history-week-recorded', '3'),
          ('history-week-skipped', '2'),
          ('history-week-voided', '1'),
        ]) {
          expect(
            find.descendant(
              of: find.byKey(ValueKey(key)),
              matching: find.text(value),
            ),
            findsOneWidget,
          );
        }
        final label = tester
            .getSemantics(find.byKey(const ValueKey('history-week-2026-10-05')))
            .label;
        expect(label, contains('3 recorded, 2 skipped, 1 voided'));
        expect(label, contains('Monday, 5 October 2026'));
        expect(tester.takeException(), isNull);
      } finally {
        handle.dispose();
      }
    },
  );

  testWidgets('status filters show only statuses in scope', (tester) async {
    for (final status in TimelineStatus.values) {
      final query = _query(status);
      await _pumpWeek(
        tester,
        query: query,
        load: (_) async => _calendar(query),
      );
      expect(
        find.byKey(const ValueKey('history-week-recorded')),
        status == TimelineStatus.all || status == TimelineStatus.recorded
            ? findsOneWidget
            : findsNothing,
      );
      expect(
        find.byKey(const ValueKey('history-week-skipped')),
        status == TimelineStatus.all || status == TimelineStatus.skipped
            ? findsOneWidget
            : findsNothing,
      );
      expect(
        find.byKey(const ValueKey('history-week-voided')),
        status == TimelineStatus.all || status == TimelineStatus.voided
            ? findsOneWidget
            : findsNothing,
      );
    }
  });

  testWidgets('status-specific day labels never announce hidden statuses', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    try {
      for (final (status, text) in [
        (TimelineStatus.recorded, '3 recorded entries'),
        (TimelineStatus.skipped, '2 skipped entries'),
        (TimelineStatus.voided, '1 voided entry'),
      ]) {
        final query = _query(status);
        await _pumpWeek(
          tester,
          query: query,
          load: (_) async => _calendar(query),
        );
        final label = tester
            .getSemantics(find.byKey(const ValueKey('history-week-2026-10-05')))
            .label;
        expect(label, contains(text));
        expect(label, isNot(contains('recorded, ')));
        expect(label, isNot(contains('skipped, ')));
        expect(label, isNot(contains('voided, ')));
      }
    } finally {
      handle.dispose();
    }
  });

  testWidgets('loading never implies zero counts', (tester) async {
    final query = _query();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appLockProvider.overrideWith(_Unlocked.new),
          historyCalendarProvider.overrideWith(
            (ref, request) => Completer<HistoryCalendar?>().future,
          ),
        ],
        child: host(
          SizedBox(
            width: 358,
            child: HistoryWeekStrip(
              query: query,
              today: _selected,
              selected: _selected,
              onSelect: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Loading this week’s counts…'), findsOneWidget);
    expect(find.byKey(const ValueKey('history-week-recorded')), findsNothing);
    expect(find.byKey(const ValueKey('history-week-skipped')), findsNothing);
    expect(find.byKey(const ValueKey('history-week-voided')), findsNothing);
  });

  testWidgets('failure never implies zero counts and retry reloads', (
    tester,
  ) async {
    final query = _query();
    var calls = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appLockProvider.overrideWith(_Unlocked.new),
          historyCalendarProvider.overrideWith((ref, request) async {
            calls++;
            if (calls == 1) throw StateError('synthetic calendar failure');
            return _calendar(query);
          }),
        ],
        child: host(
          SizedBox(
            width: 358,
            child: HistoryWeekStrip(
              query: query,
              today: _selected,
              selected: _selected,
              onSelect: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Week counts unavailable. Try again.'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.byKey(const ValueKey('history-week-recorded')), findsNothing);
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(find.byKey(const ValueKey('history-week-recorded')), findsOneWidget);
    expect(find.text('Week counts unavailable. Try again.'), findsNothing);
  });

  testWidgets(
    'refreshing and failed refresh never present retained counts as current',
    (tester) async {
      final query = _query();
      var initial = true;
      final pending = Completer<HistoryCalendar?>();
      await _pumpWeek(
        tester,
        query: query,
        load: (_) => initial ? Future.value(_calendar(query)) : pending.future,
      );
      expect(
        find.byKey(const ValueKey('history-week-recorded')),
        findsOneWidget,
      );
      final container = ProviderScope.containerOf(
        tester.element(find.byType(HistoryWeekStrip)),
      );
      initial = false;
      container.invalidate(historyCalendarProvider);
      await tester.pump();
      expect(
        find.byKey(const ValueKey('history-week-loading')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('history-week-recorded')), findsNothing);
      pending.completeError(StateError('synthetic refresh failure'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('history-week-failed')), findsOneWidget);
      expect(find.byKey(const ValueKey('history-week-recorded')), findsNothing);
    },
  );

  testWidgets('locked summary hides range, counts and day targets', (
    tester,
  ) async {
    final query = _query();
    await _pumpWeek(
      tester,
      query: query,
      locked: true,
      load: (_) async => null,
    );
    expect(find.text('Selected week'), findsOneWidget);
    expect(find.text('Unlock to view week counts.'), findsOneWidget);
    expect(find.byKey(const ValueKey('history-week-range')), findsNothing);
    expect(find.byKey(const ValueKey('history-week-recorded')), findsNothing);
    expect(find.byKey(const ValueKey('history-week-2026-10-05')), findsNothing);
  });

  testWidgets('day targets stay at least 48 px at narrow and wide widths', (
    tester,
  ) async {
    final query = _query();
    for (final (width, scale) in [
      (288.0, 1.0),
      (358.0, 1.0),
      (398.0, 1.0),
      (288.0, 2.0),
    ]) {
      await _pumpWeek(
        tester,
        query: query,
        width: width,
        textScale: scale,
        load: (_) async => _calendar(query),
      );
      for (final date in historyWeekDates(_selected, 1)) {
        final rect = tester.getRect(find.byKey(ValueKey('history-week-$date')));
        expect(
          rect.width,
          greaterThanOrEqualTo(48),
          reason: '$width @ $scale: $date',
        );
        expect(
          rect.height,
          greaterThanOrEqualTo(48),
          reason: '$width @ $scale: $date',
        );
      }
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('summary renders with reduced motion enabled', (tester) async {
    final query = _query();
    await _pumpWeek(
      tester,
      query: query,
      reduceMotion: true,
      load: (_) async => _calendar(query),
    );
    expect(find.text('Selected week'), findsOneWidget);
    expect(find.byKey(const ValueKey('history-week-recorded')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  appTest('calendar day selection moves the week and keeps full indexed counts', (
    tester,
  ) async {
    final f = await launch(tester);
    final item = (await runIo(
      tester,
      () => historyItem(f.store, 'Week medicine'),
    ))!;
    // A Wednesday keeps both seeded days in the same locale week. The test
    // must not change its expected total on Mondays or across midnight.
    final day = CivilDate(2026, 10, 7);
    await runIo(tester, () async {
      for (var i = 0; i < 26; i++) {
        await historyRecord(f.store, item, day);
      }
      for (var i = 0; i < 4; i++) {
        await historyRecord(f.store, item, day.addDays(-1), amount: '2');
      }
    });
    f.container.read(routerProvider).go('/history?selected=$day');
    await settle(tester);
    expect(find.text('Selected week'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('history-week-recorded')),
        matching: find.text('30'),
      ),
      findsOneWidget,
    );
    final strip = tester.element(find.byType(HistoryWeekStrip));
    final locale = MaterialLocalizations.of(strip);
    final firstDay = locale.firstDayOfWeekIndex;
    final start = historyWeekDates(day, firstDay).first;
    final end = historyWeekDates(day, firstDay).last;
    expect(
      find.text(
        'From ${locale.formatShortDate(start.calendarValue)} to ${locale.formatShortDate(end.calendarValue)}',
      ),
      findsOneWidget,
    );

    final previousDay = day.addDays(-7);
    final previousCell = find.byKey(ValueKey('history-day-$previousDay'));
    await tester.ensureVisible(previousCell);
    await tester.tap(previousCell);
    await settle(tester);
    final previousStart = historyWeekDates(previousDay, firstDay).first;
    final previousEnd = historyWeekDates(previousDay, firstDay).last;
    expect(
      find.text(
        'From ${locale.formatShortDate(previousStart.calendarValue)} to ${locale.formatShortDate(previousEnd.calendarValue)}',
      ),
      findsOneWidget,
    );
    expect(
      tester.widget<HistoryWeekStrip>(find.byType(HistoryWeekStrip)).selected,
      previousDay,
    );
    expect(tester.takeException(), isNull);
  });
}
