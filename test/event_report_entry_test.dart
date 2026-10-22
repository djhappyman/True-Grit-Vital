import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:true_grit_vital/app/app_lock.dart';
import 'package:true_grit_vital/app/appearance.dart';
import 'package:true_grit_vital/app/reports.dart';
import 'package:true_grit_vital/app/vital_app.dart';
import 'package:true_grit_vital/data/record_store.dart';
import 'package:true_grit_vital/features/events/event_report_location.dart';
import 'package:true_grit_vital/ui/stitch_ui.dart';

import 'private_drafts_ui_test.dart' show FakeAuth;
import 'vital_app_test.dart'
    show appTest, launch, runIo, settle, tap, waitForText;

const captureDirectory = String.fromEnvironment('VITAL_EVENT_REPORT_CAPTURE');

DateTime _now() => DateTime.utc(2026, 10, 20, 12);

Future<EventRecord> _saveEvent(
  WidgetTester tester,
  RecordStore store, {
  required String id,
  required String name,
  EventDate? plannedStart,
  EventDate? plannedEnd,
  EventDate? actualStart,
  EventDate? actualEnd,
  bool completed = false,
  String zoneId = 'Europe/London',
}) async {
  final event = EventRecord(
    id: id,
    personId: meId,
    name: name,
    eventType: 'cycle',
    zoneId: zoneId,
    revision: 1,
    plannedStart: plannedStart,
    plannedEnd: plannedEnd,
    actualStart: actualStart,
    actualEnd: actualEnd,
    completed: completed,
  );
  final saved = await runIo(tester, () async {
    final person = (await store.profileById(meId))!;
    final command = SaveEventCommand(
      commandId: 'save-$id',
      generation: store.generation,
      expectedRevision: null,
      expectedPersonRevision: person.revision,
      event: event,
    );
    return store.saveEvent(
      command,
      membershipReview: await store.previewEventMembership(command),
    );
  });
  return saved!;
}

EventDate _day(int month, int day) =>
    EventDate.day(CivilDate(2026, month, day));

EventRecord _event({
  EventDate? plannedStart,
  EventDate? plannedEnd,
  EventDate? actualStart,
  EventDate? actualEnd,
  bool completed = false,
  String zoneId = 'Europe/London',
}) => EventRecord(
  id: 'event-report',
  personId: meId,
  name: 'Synthetic course',
  eventType: 'cycle',
  zoneId: zoneId,
  revision: 1,
  plannedStart: plannedStart,
  plannedEnd: plannedEnd,
  actualStart: actualStart,
  actualEnd: actualEnd,
  completed: completed,
);

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

  group('event report window', () {
    test('a date-only end includes the whole final day', () {
      final plan = eventReportPlan(
        _event(
          plannedStart: _day(10, 1),
          actualStart: _day(10, 1),
          actualEnd: _day(10, 25),
          completed: true,
        ),
        displayZone: 'Europe/London',
        now: _now(),
      ) as EventReportReady;
      expect(plan.fromDate, CivilDate(2026, 10, 1));
      expect(plan.throughDate, CivilDate(2026, 10, 25));
      expect(plan.beforeDate, CivilDate(2026, 10, 26));
      final lastDay = DisplayTime().dayBounds(
        plan.throughDate,
        'Europe/London',
      );
      final lateEvening = DateTime.utc(2026, 10, 25, 22, 30);
      expect(lastDay.contains(lateEvening), isTrue);
      expect(
        DisplayTime()
            .dayBounds(plan.beforeDate, 'Europe/London')
            .start
            .isAfter(lateEvening),
        isTrue,
      );
    });

    test('an exact start is projected through the display zone and DST', () {
      final plan = eventReportPlan(
        _event(
          actualStart: EventDate.exact(DateTime.utc(2026, 3, 29, 0, 30)),
          actualEnd: _day(3, 29),
          completed: true,
        ),
        displayZone: 'America/New_York',
        now: _now(),
      ) as EventReportReady;
      expect(plan.fromDate, CivilDate(2026, 3, 28));
      expect(plan.throughDate, CivilDate(2026, 3, 29));
      expect(plan.beforeDate, CivilDate(2026, 3, 30));
    });

    test('a date-only boundary follows the event zone across DST', () {
      final plan = eventReportPlan(
        _event(
          actualStart: _day(10, 24),
          actualEnd: _day(10, 25),
          completed: true,
        ),
        displayZone: 'Europe/London',
        now: _now(),
      ) as EventReportReady;
      final lastDay = DisplayTime().dayBounds(
        plan.throughDate,
        'Europe/London',
      );
      expect(lastDay.duration, const Duration(hours: 25));
      expect(plan.beforeDate, CivilDate(2026, 10, 26));
    });

    test('missing start stays unresolved', () {
      final plan = eventReportPlan(
        _event(plannedEnd: _day(10, 25)),
        displayZone: 'Europe/London',
        now: _now(),
      );
      expect(plan, isA<EventReportBlocked>());
      expect(
        (plan as EventReportBlocked).reason,
        EventReportBlock.startUnavailable,
      );
    });

    test('partial dates stay unresolved instead of becoming a range', () {
      final plan = eventReportPlan(
        _event(
          plannedStart: EventDate(
            precision: EventDatePrecision.month,
            value: '2026-10',
          ),
        ),
        displayZone: 'Europe/London',
        now: _now(),
      );
      expect(plan, isA<EventReportBlocked>());
      expect(
        (plan as EventReportBlocked).reason,
        EventReportBlock.startUnavailable,
      );
    });

    test('a completed event without a resolvable end stays blocked', () {
      final plan = eventReportPlan(
        _event(
          actualStart: _day(10, 1),
          plannedEnd: _day(10, 25),
          completed: true,
        ),
        displayZone: 'Europe/London',
        now: _now(),
      );
      expect(plan, isA<EventReportBlocked>());
      expect(
        (plan as EventReportBlocked).reason,
        EventReportBlock.endUnavailable,
      );
    });

    test(
      'an entered partial end is not silently treated as an ongoing event',
      () {
        final plan = eventReportPlan(
          _event(
            actualStart: _day(10, 1),
            actualEnd: EventDate(
              precision: EventDatePrecision.month,
              value: '2026-10',
            ),
          ),
          displayZone: 'Europe/London',
          now: _now(),
        );
        expect(plan, isA<EventReportBlocked>());
      },
    );

    test('an ongoing event ends at the current display day, not its plan', () {
      final plan = eventReportPlan(
        _event(plannedStart: _day(10, 1), plannedEnd: _day(10, 10)),
        displayZone: 'Europe/London',
        now: _now(),
      ) as EventReportReady;
      expect(plan.ongoing, isTrue);
      expect(plan.fromDate, CivilDate(2026, 10, 1));
      expect(plan.throughDate, CivilDate(2026, 10, 20));
      expect(plan.throughDate, isNot(CivilDate(2026, 10, 10)));
    });

    test('an unavailable event zone stays blocked', () {
      final plan = eventReportPlan(
        _event(
          actualStart: _day(10, 1),
          actualEnd: _day(10, 2),
          completed: true,
          zoneId: 'Nowhere/Synthetic',
        ),
        displayZone: 'Europe/London',
        now: _now(),
      );
      expect(plan, isA<EventReportBlocked>());
      expect(
        (plan as EventReportBlocked).reason,
        EventReportBlock.datesUnavailable,
      );
    });

    test('the seeded selection covers the derived inclusive range', () {
      final event = _event(
        actualStart: _day(10, 1),
        actualEnd: _day(10, 25),
        completed: true,
      );
      final plan = eventReportPlan(
        event,
        displayZone: 'Europe/London',
        now: _now(),
      ) as EventReportReady;
      final selection = eventReportSelection(
        event,
        plan,
        displayZone: 'Europe/London',
      );
      expect(selection.template, ReportTemplateId.r03EventReview);
      expect(selection.fromDate, plan.fromDate);
      expect(selection.beforeDate, plan.beforeDate);
      expect(eventSelectionCovers(event, selection), isTrue);
    });
  });

  appTest('event Report opens one named event and Back returns to it', (
    tester,
  ) async {
    final f = await launch(tester, todayClock: _now);
    final event = await _saveEvent(
      tester,
      f.store,
      id: 'course-2026',
      name: 'Autumn Recovery Course',
      plannedStart: _day(10, 1),
      plannedEnd: _day(10, 25),
      actualStart: _day(10, 1),
      actualEnd: _day(10, 25),
      completed: true,
    );
    f.container.read(routerProvider).go('/event/${event.id}');
    await settle(tester);
    await waitForText(tester, event.name);
    await tap(tester, 'Report');
    await settle(tester);

    expect(
      f.container.read(routerProvider).routerDelegate.state.uri.path,
      '/reports',
    );
    final selection = f.container.read(reportControllerProvider).selection!;
    expect(selection.template, ReportTemplateId.r03EventReview);
    expect(selection.eventId, event.id);
    expect(selection.fromDate, CivilDate(2026, 10, 1));
    expect(selection.beforeDate, CivilDate(2026, 10, 26));
    expect(selection.displayZone, 'Europe/London');
    expect(find.text('Event: ${event.name}'), findsOneWidget);
    expect(find.text('Event zone: Europe/London'), findsOneWidget);
    expect(
      find.text(
        'Period: 2026-10-01 to 2026-10-25. Times shown in Europe/London.',
      ),
      findsOneWidget,
    );
    expect(find.text('Event review'), findsWidgets);

    await tap(tester, 'Back');
    await settle(tester);
    expect(
      f.container.read(routerProvider).routerDelegate.state.uri.path,
      '/event/${event.id}',
    );
    await waitForText(tester, event.name);
    expect(find.widgetWithText(StitchButton, 'Report'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  appTest('an ongoing event report ends today without inventing an end', (
    tester,
  ) async {
    final f = await launch(tester, todayClock: _now);
    final event = await _saveEvent(
      tester,
      f.store,
      id: 'open-course',
      name: 'Ongoing Course',
      plannedStart: _day(10, 1),
      plannedEnd: _day(10, 10),
    );
    f.container.read(routerProvider).go('/event/${event.id}');
    await settle(tester);
    await waitForText(tester, event.name);
    await tap(tester, 'Report');
    await settle(tester);

    final selection = f.container.read(reportControllerProvider).selection!;
    expect(selection.fromDate, CivilDate(2026, 10, 1));
    expect(selection.beforeDate, CivilDate(2026, 10, 21));
    expect(find.text('Planned: 2026-10-01 to 2026-10-10'), findsOneWidget);
    expect(find.text('No event end is recorded.'), findsOneWidget);
    expect(find.text('Event: Ongoing Course'), findsOneWidget);
    expect(find.text('Completed'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  appTest('unresolved or missing events do not offer a report', (tester) async {
    final f = await launch(tester, todayClock: _now);
    final event = await _saveEvent(
      tester,
      f.store,
      id: 'no-start',
      name: 'Undated Course',
      plannedEnd: _day(10, 25),
    );
    f.container.read(routerProvider).go('/event/${event.id}');
    await settle(tester);
    await waitForText(tester, event.name);
    expect(
      tester
          .widget<StitchButton>(find.widgetWithText(StitchButton, 'Report'))
          .onPressed,
      isNull,
    );
    expect(
      find.text(
        'A start date is needed before preparing a report for this event.',
      ),
      findsOneWidget,
    );

    f.container.read(routerProvider).go('/event/missing-event');
    await settle(tester);
    expect(find.widgetWithText(StitchButton, 'Report'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  appTest('the event report action stays behind the app lock', (tester) async {
    final f = await launch(tester, auth: FakeAuth(), todayClock: _now);
    final event = await _saveEvent(
      tester,
      f.store,
      id: 'locked-course',
      name: 'Locked Course',
      plannedStart: _day(10, 1),
      plannedEnd: _day(10, 25),
      actualStart: _day(10, 1),
      actualEnd: _day(10, 25),
      completed: true,
    );
    f.container.read(routerProvider).go('/event/${event.id}');
    await settle(tester);
    await waitForText(tester, event.name);
    expect(find.widgetWithText(StitchButton, 'Report'), findsOneWidget);

    await runIo(tester, () async {
      await f.container.read(appLockProvider.notifier).setEnabled(true);
    });
    f.container
        .read(appLockProvider.notifier)
        .lifecycle(AppLifecycleState.inactive);
    await settle(tester);
    expect(find.text('Unlock'), findsWidgets);
    expect(find.text('Report'), findsNothing);

    f.container
        .read(appLockProvider.notifier)
        .lifecycle(AppLifecycleState.resumed);
    await tap(tester, 'Unlock');
    await settle(tester);
    await waitForText(tester, event.name);
    expect(find.widgetWithText(StitchButton, 'Report'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  appTest('another report selection is not replaced by the event action', (
    tester,
  ) async {
    final f = await launch(tester, todayClock: _now);
    final event = await _saveEvent(
      tester,
      f.store,
      id: 'replace-course',
      name: 'Replacement Course',
      plannedStart: _day(10, 1),
      plannedEnd: _day(10, 25),
      actualStart: _day(10, 1),
      actualEnd: _day(10, 25),
      completed: true,
    );
    final router = f.container.read(routerProvider);
    router.push('/reports?from=2025-01-01&before=2025-02-01');
    await settle(tester);
    final controller = f.container.read(reportControllerProvider.notifier);
    controller.setIncludeNotes(true);
    controller.setIncludeAttachments(true);
    controller.setIncludeSupporting(true);
    final existing = f.container.read(reportControllerProvider).selection!;
    expect(existing.fromDate, CivilDate(2025, 1, 1));

    router.push('/event/${event.id}');
    await settle(tester);
    await waitForText(tester, event.name);
    await tap(tester, 'Report');
    await settle(tester);
    expect(find.text('Replace report?'), findsOneWidget);
    expect(
      find.text(
        'Replacing starts a new report. Private notes, source files and supporting records will be off.',
      ),
      findsOneWidget,
    );
    await tap(tester, 'Cancel');
    await settle(tester);
    expect(
      f.container.read(routerProvider).routerDelegate.state.uri.path,
      '/event/${event.id}',
    );
    expect(
      f.container.read(reportControllerProvider).selection!.identity,
      existing.identity,
    );

    f.container.read(reportControllerProvider.notifier).cancel();
    expect(
      f.container.read(reportControllerProvider).phase,
      ReportPhase.cancelled,
    );
    await tap(tester, 'Report');
    await settle(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settle(tester);
    expect(find.text('Replace report?'), findsNothing);
    expect(f.container.read(reportControllerProvider).selection, existing);
    await tap(tester, 'Report');
    await tap(tester, 'Replace');
    await settle(tester);
    final replaced = f.container.read(reportControllerProvider);
    expect(replaced.selection!.eventId, event.id);
    expect(replaced.selection!.fromDate, CivilDate(2026, 10, 1));
    expect(replaced.selection!.includeNotes, isFalse);
    expect(replaced.selection!.includeAttachments, isFalse);
    expect(replaced.selection!.includeSupporting, isFalse);
    expect(replaced.phase, ReportPhase.idle);
    expect(replaced.artifact, isNull);
    expect(
      f.container.read(routerProvider).routerDelegate.state.uri.path,
      '/reports',
    );
    expect(tester.takeException(), isNull);
  });

  appTest(
    'event Replace approval cannot overwrite a draft changed during the dialog',
    (tester) async {
      final f = await launch(tester, todayClock: _now);
      final event = await _saveEvent(
        tester,
        f.store,
        id: 'race-event',
        name: 'Race course',
        actualStart: _day(10, 1),
        actualEnd: _day(10, 20),
      );
      final router = f.container.read(routerProvider);
      router.push('/reports?from=2025-01-01&before=2025-02-01');
      await settle(tester);
      final controller = f.container.read(reportControllerProvider.notifier);
      final original = f.container.read(reportControllerProvider).selection!;
      router.push('/event/${event.id}');
      await settle(tester);
      await waitForText(tester, event.name);
      await tap(tester, 'Report');
      expect(find.text('Replace report?'), findsOneWidget);
      final newer = original.copyWith(
        itemIds: ['another-exact-item'],
        includeNotes: true,
        includeAttachments: true,
        includeSupporting: true,
      );
      controller.select(newer);
      await tap(tester, 'Replace');
      expect(f.container.read(reportControllerProvider).selection, newer);
      expect(router.routerDelegate.state.uri.path, '/event/${event.id}');
      expect(tester.takeException(), isNull);
    },
  );

  appTest(
    'locking during report replacement closes the decision without applying it',
    (tester) async {
      final f = await launch(tester, auth: FakeAuth(), todayClock: _now);
      final event = await _saveEvent(
        tester,
        f.store,
        id: 'replace-lock',
        name: 'Replacement lock course',
        actualStart: _day(10, 1),
        actualEnd: _day(10, 25),
        completed: true,
      );
      await runIo(
        tester,
        () => f.container.read(appLockProvider.notifier).setEnabled(true),
      );
      final router = f.container.read(routerProvider);
      router.push('/reports?from=2025-01-01&before=2025-02-01');
      await settle(tester);
      router.push('/event/${event.id}');
      await waitForText(tester, event.name);
      expect(f.container.read(appLockProvider).locked, isFalse);
      expect(
        f.container.read(reportControllerProvider).selection!.fromDate,
        CivilDate(2025, 1, 1),
      );
      await tap(tester, 'Report');
      await settle(tester);
      expect(find.text('Replace report?'), findsOneWidget);
      f.container.read(appLockProvider.notifier).lock();
      await settle(tester);
      expect(find.text('Replace report?'), findsNothing);
      expect(find.text('Unlock').hitTestable(), findsWidgets);
      expect(f.container.read(reportControllerProvider).selection, isNull);
      expect(tester.takeException(), isNull);
    },
  );

  appTest('a direct event report link keeps an existing draft until Replace', (
    tester,
  ) async {
    final f = await launch(tester, todayClock: _now);
    final event = await _saveEvent(
      tester,
      f.store,
      id: 'direct-course',
      name: 'Direct Course',
      plannedStart: _day(10, 1),
      plannedEnd: _day(10, 25),
      actualStart: _day(10, 1),
      actualEnd: _day(10, 25),
      completed: true,
    );
    final router = f.container.read(routerProvider);
    router.push('/reports?from=2025-01-01&before=2025-02-01');
    await settle(tester);
    final existing = f.container.read(reportControllerProvider).selection!;
    router.push(
      '/reports?event=${event.id}&template=event&from=2026-10-01&before=2026-10-26',
    );
    await settle(tester);

    expect(find.text('Report selected'), findsOneWidget);
    expect(
      f.container.read(reportControllerProvider).selection!.identity,
      existing.identity,
    );
    await tap(tester, 'Replace');
    await settle(tester);
    expect(
      f.container.read(reportControllerProvider).selection!.eventId,
      event.id,
    );
    expect(tester.takeException(), isNull);
  });

  appTest(
    'a changed event report URL preserves a mounted selection until Replace',
    (tester) async {
      final f = await launch(tester, todayClock: _now);
      final event = await _saveEvent(
        tester,
        f.store,
        id: 'changed-link',
        name: 'Changed link course',
        actualStart: _day(10, 1),
        actualEnd: _day(10, 25),
        completed: true,
      );
      final router = f.container.read(routerProvider);
      router.go('/reports?from=2025-01-01&before=2025-02-01');
      await settle(tester);
      final existing = f.container.read(reportControllerProvider).selection!;
      router.go(
        '/reports?event=${event.id}&template=event&from=2026-10-01&before=2026-10-26',
      );
      await settle(tester);
      expect(find.text('Report selected'), findsOneWidget);
      expect(
        f.container.read(reportControllerProvider).selection!.identity,
        existing.identity,
      );
      await tap(tester, 'Replace');
      await settle(tester);
      expect(
        f.container.read(reportControllerProvider).selection!.eventId,
        event.id,
      );
      expect(tester.takeException(), isNull);
    },
  );

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    appTest(
      'event report action stays readable in ${mode.name} at 320px and 2x text',
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
        final event = await _saveEvent(
          tester,
          f.store,
          id: 'narrow-${mode.name}',
          name: 'Long Autumn Recovery Course Name',
          plannedStart: _day(10, 1),
          plannedEnd: _day(10, 25),
          actualStart: _day(10, 1),
          actualEnd: _day(10, 25),
          completed: true,
        );
        f.container.read(appearanceProvider.notifier).setMode(mode);
        f.container.read(routerProvider).go('/event/${event.id}');
        await settle(tester);
        await waitForText(tester, event.name);
        await tester.ensureVisible(find.text('Report'));
        await settle(tester);
        await tap(tester, 'Report');
        await settle(tester);
        await waitForText(tester, 'Event: ${event.name}');
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    appTest('event report captures use synthetic records in ${mode.name}', (
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
      final event = await _saveEvent(
        tester,
        f.store,
        id: 'capture-${mode.name}',
        name: 'Autumn Recovery Course',
        plannedStart: _day(10, 1),
        plannedEnd: _day(10, 25),
        actualStart: _day(10, 1),
        actualEnd: _day(10, 25),
        completed: true,
      );
      final undated = await _saveEvent(
        tester,
        f.store,
        id: 'capture-undated-${mode.name}',
        name: 'Undated Course',
        plannedEnd: _day(10, 25),
      );
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
      await tester.ensureVisible(find.text('Report'));
      await settle(tester);
      await _capture(tester, boundaryKey, '${mode.name}-event-report-action');
      await tap(tester, 'Report');
      await settle(tester);
      await waitForText(tester, 'Event: ${event.name}');
      await _capture(tester, boundaryKey, '${mode.name}-event-report');
      tester.view.physicalSize = const Size(320, 740);
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      await settle(tester);
      expect(tester.takeException(), isNull);
      await _capture(tester, boundaryKey, '${mode.name}-event-report-narrow');
      tester.platformDispatcher.clearTextScaleFactorTestValue();
      tester.view.physicalSize = const Size(390, 844);
      f.container.read(routerProvider).go('/event/${undated.id}');
      await settle(tester);
      await waitForText(tester, undated.name);
      await tester.ensureVisible(find.text('Report'));
      await settle(tester);
      expect(
        find.text(
          'A start date is needed before preparing a report for this event.',
        ),
        findsOneWidget,
      );
      await _capture(tester, boundaryKey, '${mode.name}-event-report-disabled');
    });
  }
}
