import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:true_grit_vital/app/appearance.dart';
import 'package:true_grit_vital/app/vital_app.dart';
import 'package:true_grit_vital/data/record_store.dart';
import 'package:true_grit_vital/features/plans/stitch_dashboard.dart';
import 'package:true_grit_vital/ui/stitch_ui.dart';
import 'package:true_grit_vital/features/recording/quick_record_sheet.dart';
import 'package:true_grit_vital/features/recording/record_pages.dart';

import 'screen_settings_hub_test.dart' show loadFonts;
import 'vital_app_test.dart'
    show appTest, launch, runIo, settle, tap, waitForText;

final day = CivilDate(2026, 10, 22);
Future<void> fill(WidgetTester tester, String label, String value) async {
  final field = find
      .descendant(
        of: find.widgetWithText(LabelledInput, label),
        matching: find.byType(TextField),
      )
      .first;
  await tester.ensureVisible(field);
  await tester.enterText(field, value);
  await settle(tester);
}

Future<void> add(WidgetTester tester) async {
  final button = find.descendant(
    of: find.byType(UnplannedMedication),
    matching: find.text('Add'),
  );
  await tester.ensureVisible(button);
  await settle(tester);
  await tester.tap(button);
  await settle(tester);
}

void main() {
  setUpAll(loadFonts);
  appTest(
    'named greeting, empty timeline and calendar browsing retain the selected day',
    (tester) async {
      final f = await launch(
        tester,
        todayClock: () => DateTime.utc(2026, 10, 22, 20),
      );
      await runIo(
        tester,
        () => f.store.editProfile(
          commandId: 'named',
          personId: meId,
          expectedRevision: 2,
          name: 'Mike',
          adultConfirmed: true,
        ),
      );
      await settle(tester);
      expect(find.text('Good evening, Mike'), findsOneWidget);
      final profile = find.byWidgetPredicate(
        (w) => w is Semantics && w.properties.label == 'Profile',
      );
      final settings = find.byWidgetPredicate(
        (w) => w is Semantics && w.properties.label == 'Settings',
      );
      expect(
        tester.getCenter(profile).dx,
        lessThan(tester.getCenter(settings).dx),
      );
      expect(find.text('Morning'), findsOneWidget);
      expect(find.text('Afternoon'), findsOneWidget);
      expect(find.text('Evening'), findsOneWidget);
      expect(find.text('Empty'), findsNWidgets(3));
      expect(find.text('No doses planned.'), findsNothing);
      expect(find.text('Daily progress'), findsNothing);
      expect(find.text('Week summary'), findsNothing);
      expect(find.text('Recorded'), findsNothing);
      final calendar = find
          .descendant(
            of: find.byType(StitchDashboard),
            matching: find.byType(PageView),
          )
          .first;
      final frame = find.byKey(const ValueKey('dashboard-calendar-frame'));
      final heading = find.byKey(const ValueKey('dashboard-calendar-heading'));
      expect(
        find.byKey(const ValueKey('dashboard-calendar-selection')),
        findsNothing,
      );
      final frameRect = tester.getRect(frame),
          headingRect = tester.getRect(heading);
      final gesture = await tester.startGesture(tester.getCenter(calendar));
      await gesture.moveBy(const Offset(-120, 0));
      await tester.pump(const Duration(milliseconds: 80));
      expect(tester.getRect(frame), frameRect);
      expect(tester.getRect(heading), headingRect);
      expect(f.container.read(routerProvider).state.uri.path, '/today');
      await gesture.moveBy(const Offset(120, 0));
      await gesture.up();
      await settle(tester);
      await tester.drag(calendar, const Offset(-600, 0));
      await settle(tester);
      expect(
        tester
            .widget<UnplannedMedication>(find.byType(UnplannedMedication))
            .day,
        day,
      );
      expect(f.container.read(routerProvider).state.uri.path, '/today');
      await tester.tap(find.text('26').hitTestable());
      await settle(tester);
      expect(
        tester
            .widget<UnplannedMedication>(find.byType(UnplannedMedication))
            .day,
        CivilDate(2026, 10, 26),
      );
      await tap(tester, 'Plan');
      await waitForText(tester, 'Plan a dose');
      expect(find.byType(QuickRecordSheet), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  appTest('greeting follows the local clock without recreating the dashboard', (
    tester,
  ) async {
    var now = DateTime.utc(2026, 10, 22, 10, 59);
    await launch(tester, todayClock: () => now);
    expect(find.text('Good morning, Me'), findsOneWidget);
    final dashboard = tester.state(find.byType(StitchDashboard));
    now = DateTime.utc(2026, 10, 22, 11);
    await tester.pump(const Duration(minutes: 1));
    await settle(tester);
    expect(find.text('Good afternoon, Me'), findsOneWidget);
    expect(tester.state(find.byType(StitchDashboard)), same(dashboard));
    final observations = find.text('Coming soon');
    await tester.ensureVisible(observations);
    await settle(tester);
    expect(find.text('Coming soon'), findsOneWidget);
    expect(find.byType(DoseForm), findsNothing);
  });

  appTest('period planning keeps its day and visible suggested time', (
    tester,
  ) async {
    final f = await launch(
      tester,
      todayClock: () => DateTime.utc(2026, 10, 22, 20),
    );
    final medicine = (await runIo(
      tester,
      () => f.store.createItem(
        commandId: 'period-item',
        expectedPersonRevision: 2,
        name: 'Period medicine',
        form: 'Tablet',
        unit: 'count',
        type: 'Medicine',
      ),
    ))!;
    final plan = find.descendant(
      of: find.byKey(const ValueKey('schedule-part-1')),
      matching: find.byType(StitchEmptySlot),
    );
    await tester.ensureVisible(plan);
    await settle(tester);
    await tester.tap(plan);
    await settle(tester);
    expect(
      f.container.read(routerProvider).state.uri.queryParameters['time'],
      '08:00',
    );
    await tap(tester, 'Period medicine');
    expect(
      f.container.read(routerProvider).state.uri.path,
      '/schedule/${medicine.id}',
    );
    final timeField = find.descendant(
      of: find.widgetWithText(LabelledInput, 'Planned time'),
      matching: find.byType(TextField),
    );
    expect(tester.widget<TextField>(timeField).controller!.text, '08:00');
    final start = find.descendant(
      of: find.widgetWithText(LabelledInput, 'Start date'),
      matching: find.byType(TextField),
    );
    expect(tester.widget<TextField>(start).controller!.text, '2026-10-22');
    expect((await runIo(tester, () => f.store.dailyPlans()))!, isEmpty);
    expect((await runIo(tester, () => f.store.records()))!, isEmpty);
    f.container
        .read(routerProvider)
        .go('/unplanned?new=1&plan=1&day=2026-10-23&time=20:00');
    await waitForText(tester, 'New medicine');
    await fill(tester, 'Name', 'New evening medicine');
    await tap(tester, 'Items');
    await tap(tester, 'Create');
    await waitForText(tester, 'Chosen times');
    expect(tester.widget<TextField>(timeField).controller!.text, '20:00');
    expect(tester.widget<TextField>(start).controller!.text, '2026-10-23');
    expect((await runIo(tester, () => f.store.records()))!, isEmpty);
  });

  appTest('quick existing medicine uses the guarded dose sheet', (
    tester,
  ) async {
    final f = await launch(tester);
    final medicine = (await runIo(
      tester,
      () => f.store.createItem(
        commandId: 'existing',
        expectedPersonRevision: 2,
        name: 'Existing medicine',
        form: 'Tablet',
        unit: 'count',
        type: 'Medicine',
      ),
    ))!;
    await settle(tester);
    await add(tester);
    await waitForText(tester, 'Existing medicine');
    await tap(tester, 'Existing medicine');
    expect(find.byType(DoseForm), findsOneWidget);
    await fill(tester, 'Amount', '2');
    await tap(tester, 'Save');
    final records = (await runIo(tester, () => f.store.records()))!;
    expect(records, hasLength(1));
    expect(records.single.itemId, medicine.id);
    expect(records.single.actualAmount, ExactAmount.parseEntry('2'));
    expect(records.single.actualUnit, 'count');
    expect(tester.takeException(), isNull);
  });

  appTest(
    'quick creation records now and medicine details can be edited later',
    (tester) async {
      final f = await launch(tester);
      await add(tester);
      await tap(tester, 'Create');
      await waitForText(tester, 'New medicine');
      await fill(tester, 'Name', 'Quick medicine');
      await tap(tester, 'Items');
      await tap(tester, 'Create');
      await waitForText(tester, 'Quick medicine');
      expect(find.byType(DoseForm), findsOneWidget);
      await fill(tester, 'Amount', '1');
      await tap(tester, 'Save');
      final item = (await runIo(tester, () => f.store.items()))!.single;
      expect(item.form, 'Not specified');
      expect((await runIo(tester, () => f.store.records()))!, hasLength(1));
      f.container.read(routerProvider).go('/substance/${item.id}/details');
      await settle(tester);
      await fill(tester, 'Name', 'Completed medicine name');
      await fill(tester, 'Form', 'Capsule');
      await tap(tester, 'Save');
      final edited = (await runIo(tester, () => f.store.itemById(item.id)))!;
      expect(edited.name, 'Completed medicine name');
      expect(edited.form, 'Capsule');
      final old = (await runIo(tester, () => f.store.records()))!.single;
      expect(old.name, 'Quick medicine');
      expect(old.form, 'Not specified');
      expect(tester.takeException(), isNull);
    },
  );

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    appTest('dashboard and quick sheet fit narrow 2x text in ${mode.name}', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      final f = await launch(tester);
      f.container.read(appearanceProvider.notifier).setMode(mode);
      await settle(tester);
      final verticalViewport = find
          .byWidgetPredicate(
            (w) =>
                w is SingleChildScrollView &&
                w.scrollDirection == Axis.vertical,
          )
          .first;
      expect(tester.getSize(verticalViewport).height, greaterThan(100));
      final dock = find.byType(ShellNavigation);
      expect(tester.getSize(dock).height, lessThan(140));
      for (final label in ['History', 'Today']) {
        final destination = find.descendant(
          of: dock,
          matching: find.text(label),
        );
        await tester.ensureVisible(destination);
        await settle(tester);
        await tester.tap(destination);
        await settle(tester);
        expect(
          f.container
              .read(routerProvider)
              .routeInformationProvider
              .value
              .uri
              .path,
          '/${label.toLowerCase()}',
        );
      }
      expect(tester.takeException(), isNull);
      await add(tester);
      await tap(tester, 'Create');
      await waitForText(tester, 'New medicine');
      await fill(
        tester,
        'Name',
        'Long name for a medicine being recorded quickly',
      );
      expect(tester.takeException(), isNull);
      await tap(tester, 'Items');
      await tester.binding.handlePopRoute();
      await settle(tester);
      expect(find.byType(ItemForm), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  appTest('capture the simplified dashboard in both themes', (tester) async {
    const output = String.fromEnvironment('VITAL_DASHBOARD_CAPTURES');
    if (output.isEmpty) return;
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final f = await launch(
      tester,
      todayClock: () => DateTime.utc(2026, 10, 22, 20),
    );
    await runIo(
      tester,
      () => f.store.editProfile(
        commandId: 'capture-name',
        personId: meId,
        expectedRevision: 2,
        name: 'Mike',
        adultConfirmed: true,
      ),
    );
    final key = GlobalKey();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: f.container,
        child: RepaintBoundary(key: key, child: const VitalApp()),
      ),
    );
    Future<void> capture(String name) async {
      await settle(tester);
      await tester.runAsync(() async {
        final image =
            await (key.currentContext!.findRenderObject()
                    as RenderRepaintBoundary)
                .toImage();
        try {
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final file = File('$output/$name.png');
          await file.parent.create(recursive: true);
          await file.writeAsBytes(bytes!.buffer.asUint8List());
        } finally {
          image.dispose();
        }
      });
    }

    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      f.container.read(appearanceProvider.notifier).setMode(mode);
      await capture('${mode.name}-today');
      tester.view.physicalSize = const Size(390, 1460);
      await capture('${mode.name}-today-full');
      tester.view.physicalSize = const Size(390, 844);
      await settle(tester);
    }
    final medicines = <SubstanceItem>[];
    for (final (index, hour) in [8, 20].indexed) {
      final item = (await runIo(
        tester,
        () => f.store.createItem(
          commandId: 'capture-item-$index',
          expectedPersonRevision: 3,
          name: index == 0 ? 'Morning medicine' : 'Evening medicine',
          form: 'Tablet',
          unit: 'mg',
          type: 'Medicine',
        ),
      ))!;
      medicines.add(item);
      await runIo(
        tester,
        () => f.store.saveDailyPlan(
          commandId: 'capture-plan-$index',
          expectedPersonRevision: 3,
          expectedGeneration: f.store.generation,
          plan: DailyPlanVersion(
            personId: meId,
            planId: 'capture-plan-$index',
            itemId: item.id,
            versionId: 'capture-v-$index',
            start: day,
            zoneBasis: FixedHome('Europe/London'),
            timing: DailySlots([
              DailySlot(
                id: 'dose',
                time: WallTime(hour, 0),
                amount: PlannedAmount(
                  quantity: ExactQuantity.parse('1'),
                  enteredText: '1',
                  unit: 'mg',
                ),
                reminderEnabled: false,
              ),
            ]),
          ),
        ),
      );
    }
    final rows = (await runIo(
      tester,
      () => f.store.dailyRows(
        from: day,
        toExclusive: day.addDays(1),
        observedZone: 'Europe/London',
      ),
    ))!.rows;
    await runIo(
      tester,
      () => f.store.actDaily(
        commandId: 'capture-taken',
        row: rows.first,
        kind: DailyActionKind.taken,
        actualAt: DateTime.utc(2026, 10, 22, 7, 10),
      ),
    );
    await runIo(
      tester,
      () => f.store.record(
        commandId: 'capture-unplanned',
        itemId: medicines.first.id,
        expectedPersonRevision: 3,
        amount: '0.125',
        actualAt: DateTime.utc(2026, 10, 22, 12),
      ),
    );
    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      f.container.read(appearanceProvider.notifier).setMode(mode);
      await tester.ensureVisible(
        find.byKey(const ValueKey('dashboard-calendar-frame')),
      );
      await capture('${mode.name}-timeline');
      await tester.ensureVisible(find.byType(UnplannedMedication));
      await capture('${mode.name}-unplanned');
      await add(tester);
      await capture('${mode.name}-chooser');
      await tap(tester, 'Morning medicine');
      await capture('${mode.name}-dose');
      f.container.read(routerProvider).go('/today');
      await settle(tester);
      await tester.ensureVisible(find.text('Morning'));
    }
  });
}
