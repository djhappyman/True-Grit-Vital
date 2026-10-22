import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:true_grit_vital/app/app_lock.dart';
import 'package:true_grit_vital/app/appearance.dart';
import 'package:true_grit_vital/app/vital_app.dart';
import 'package:true_grit_vital/features/recording/quick_record_sheet.dart';
import 'package:true_grit_vital/features/recording/record_pages.dart';

import 'private_drafts_ui_test.dart' show FakeAuth;
import 'screen_settings_hub_test.dart' show loadFonts;
import 'vital_app_test.dart'
    show appTest, launch, runIo, settle, tap, waitForText;

Finder field(String label) => find
    .descendant(
      of: find.widgetWithText(LabelledInput, label),
      matching: find.byType(TextField),
    )
    .first;

Future<void> fill(WidgetTester tester, String label, String value) async {
  final input = field(label);
  await tester.ensureVisible(input);
  await settle(tester);
  await tester.enterText(input, value);
  await settle(tester);
}

Future<void> go(
  WidgetTester tester,
  ProviderContainer container,
  String location,
) async {
  container.read(routerProvider).go(location);
  await settle(tester);
}

/// The dose sheet keeps the actual date/time behind its one Edit disclosure.
Future<void> openActualTime(WidgetTester tester) async {
  await waitForText(tester, 'Edit');
  await tap(tester, 'Edit');
  await waitForText(tester, 'Actual date');
}

String todayText() {
  final now = DateTime.now();
  return '${now.year.toString().padLeft(4, '0')}-'
      '${now.month.toString().padLeft(2, '0')}-'
      '${now.day.toString().padLeft(2, '0')}';
}

void main() {
  setUpAll(loadFonts);

  appTest('impossible day is rejected instead of normalised', (tester) async {
    final f = await launch(tester);
    final item = (await runIo(
      tester,
      () => f.store.createItem(
        commandId: 'day-item',
        expectedPersonRevision: 2,
        name: 'Day medicine',
        form: 'Tablet',
        unit: 'count',
        type: 'Medicine',
      ),
    ))!;

    await go(tester, f.container, '/unplanned?item=${item.id}&day=2026-02-30');
    expect(find.text('Link problem'), findsOneWidget);
    expect(
      find.text(
        'The day in this link is not valid. Continue with today instead.',
      ),
      findsOneWidget,
    );
    expect(find.byType(DoseForm), findsNothing);

    await tap(tester, 'Continue');
    expect(find.byType(DoseForm), findsOneWidget);
    await openActualTime(tester);
    final date = tester
        .widget<TextField>(field('Actual date'))
        .controller!
        .text;
    expect(date, todayText());
    expect(date, isNot('2026-03-01'));
    expect(date, isNot('2026-03-02'));
    expect(tester.takeException(), isNull);
  });

  appTest('recovery back leaves no duplicate editor task', (tester) async {
    final f = await launch(tester);
    await go(tester, f.container, '/unplanned?new=1&day=2026-02-30');
    expect(find.text('Link problem'), findsOneWidget);

    await tap(tester, 'Back');
    expect(find.byType(ItemForm), findsNothing);
    expect(find.byType(DoseForm), findsNothing);
    expect(f.container.read(routerProvider).state.uri.path, '/today');
    expect(tester.takeException(), isNull);
  });

  appTest('leap day and suggested time survive new planning', (tester) async {
    final f = await launch(tester);
    await go(
      tester,
      f.container,
      '/unplanned?new=1&plan=1&day=2024-02-29&time=08:00',
    );
    expect(find.text('Link problem'), findsNothing);
    expect(find.byType(ItemForm), findsOneWidget);

    await fill(tester, 'Name', 'Leap medicine');
    await tap(tester, 'Items');
    await tap(tester, 'Create');
    await waitForText(tester, 'Chosen times');

    final uri = f.container.read(routerProvider).state.uri;
    expect(uri.path, startsWith('/schedule/'));
    expect(uri.queryParameters['start'], '2024-02-29');
    expect(uri.queryParameters['time'], '08:00');
    expect(
      tester.widget<TextField>(field('Start date')).controller!.text,
      '2024-02-29',
    );
    expect(
      tester.widget<TextField>(field('Planned time')).controller!.text,
      '08:00',
    );
    expect((await runIo(tester, () => f.store.records()))!, isEmpty);
    expect(tester.takeException(), isNull);
  });

  appTest('final-year day is accepted exactly', (tester) async {
    final f = await launch(tester);
    await go(tester, f.container, '/unplanned?new=1&day=9999-12-31');
    expect(find.text('Link problem'), findsNothing);
    expect(find.byType(ItemForm), findsOneWidget);
  });

  appTest('malformed day and time are dropped before creation', (tester) async {
    final f = await launch(tester);
    await go(tester, f.container, '/unplanned?new=1&day=2026-02-30&time=25:00');
    expect(find.text('Link problem'), findsOneWidget);
    expect(
      find.text(
        'The day in this link is not valid. Continue with today instead.',
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        'The time in this link is not valid. Continue without a suggested time.',
      ),
      findsOneWidget,
    );

    await tap(tester, 'Continue');
    await waitForText(tester, 'Name');
    await fill(tester, 'Name', 'Recovered medicine');
    await tap(tester, 'Items');
    await tap(tester, 'Create');
    await waitForText(tester, 'Recovered medicine');

    final uri = f.container.read(routerProvider).state.uri;
    expect(uri.path, '/unplanned');
    expect(uri.queryParameters.containsKey('day'), isFalse);
    expect(uri.queryParameters.containsKey('time'), isFalse);
    expect(uri.queryParameters['item'], isNotNull);
    expect(find.byType(DoseForm), findsOneWidget);
    expect(find.byType(ItemForm), findsNothing);
    await openActualTime(tester);
    expect(
      tester.widget<TextField>(field('Actual date')).controller!.text,
      todayText(),
    );

    await fill(tester, 'Amount', '1');
    await tap(tester, 'Save');
    expect((await runIo(tester, () => f.store.records()))!, hasLength(1));
    expect(tester.takeException(), isNull);
  });

  appTest('item with the plan flag asks instead of recording silently', (
    tester,
  ) async {
    final f = await launch(tester);
    final item = (await runIo(
      tester,
      () => f.store.createItem(
        commandId: 'plan-item',
        expectedPersonRevision: 2,
        name: 'Plan medicine',
        form: 'Tablet',
        unit: 'count',
        type: 'Medicine',
      ),
    ))!;

    await go(
      tester,
      f.container,
      '/unplanned?item=${item.id}&plan=1&day=2026-10-23&time=20:00',
    );
    expect(find.text('Link problem'), findsOneWidget);
    expect(
      find.text('This link asks to plan the item and record it. Choose one.'),
      findsOneWidget,
    );
    expect(find.byType(DoseForm), findsNothing);

    await tap(tester, 'Plan');
    await waitForText(tester, 'Chosen times');
    final uri = f.container.read(routerProvider).state.uri;
    expect(uri.path, '/schedule/${item.id}');
    expect(uri.queryParameters['start'], '2026-10-23');
    expect(uri.queryParameters['time'], '20:00');
    expect(
      tester.widget<TextField>(field('Planned time')).controller!.text,
      '20:00',
    );
    expect(tester.takeException(), isNull);
  });

  appTest('item with the new flag keeps both explicit choices', (tester) async {
    final f = await launch(tester);
    final item = (await runIo(
      tester,
      () => f.store.createItem(
        commandId: 'new-item',
        expectedPersonRevision: 2,
        name: 'Existing medicine',
        form: 'Tablet',
        unit: 'count',
        type: 'Medicine',
      ),
    ))!;

    await go(
      tester,
      f.container,
      '/unplanned?new=1&item=${item.id}&day=2026-10-23',
    );
    expect(
      find.text(
        'This link asks to record an existing item and create a new item. Choose one.',
      ),
      findsOneWidget,
    );
    await tap(tester, 'Record');
    expect(find.byType(DoseForm), findsOneWidget);
    expect(f.container.read(routerProvider).state.uri.path, '/unplanned');
    await openActualTime(tester);
    expect(
      tester.widget<TextField>(field('Actual date')).controller!.text,
      '2026-10-23',
    );
    expect(find.byType(ItemForm), findsNothing);
    expect(tester.takeException(), isNull);
  });

  appTest('existing item records on the selected day without planning', (
    tester,
  ) async {
    final f = await launch(tester);
    final item = (await runIo(
      tester,
      () => f.store.createItem(
        commandId: 'record-item',
        expectedPersonRevision: 2,
        name: 'Recorded medicine',
        form: 'Tablet',
        unit: 'count',
        type: 'Medicine',
      ),
    ))!;

    await go(tester, f.container, '/unplanned?item=${item.id}&day=2024-02-29');
    await openActualTime(tester);
    expect(
      tester.widget<TextField>(field('Actual date')).controller!.text,
      '2024-02-29',
    );
    expect(find.byType(ItemForm), findsNothing);

    await fill(tester, 'Amount', '1');
    await tap(tester, 'Save');
    expect((await runIo(tester, () => f.store.records()))!, hasLength(1));
    final uri = f.container.read(routerProvider).state.uri;
    expect(uri.path, '/today');
    expect(tester.takeException(), isNull);
  });

  appTest('malformed item recovers before the intended task', (tester) async {
    final f = await launch(tester);
    await go(tester, f.container, '/unplanned?item=');
    expect(find.text('Link problem'), findsOneWidget);
    expect(
      find.text('The item in this link is not valid. Choose an item.'),
      findsOneWidget,
    );
    await tap(tester, 'Continue');
    expect(find.byType(DoseForm), findsNothing);
    expect(find.byType(ItemForm), findsNothing);
    expect(field('Search'), findsOneWidget);

    await go(tester, f.container, '/unplanned?new=1&item=%20');
    expect(
      find.text('The item in this link is not valid. Continue without it.'),
      findsOneWidget,
    );
    await tap(tester, 'Continue');
    expect(find.byType(ItemForm), findsOneWidget);
    expect(find.byType(DoseForm), findsNothing);
    expect(tester.takeException(), isNull);
  });

  appTest('one choice tap opens one editor', (tester) async {
    final f = await launch(tester);
    final item = (await runIo(
      tester,
      () => f.store.createItem(
        commandId: 'double-item',
        expectedPersonRevision: 2,
        name: 'Double medicine',
        form: 'Tablet',
        unit: 'count',
        type: 'Medicine',
      ),
    ))!;

    await go(
      tester,
      f.container,
      '/unplanned?new=1&item=${item.id}&day=2026-10-23',
    );
    await tester.tap(find.text('Record'));
    await tester.tap(find.text('Record'));
    await settle(tester);
    await openActualTime(tester);
    expect(find.byType(DoseForm), findsOneWidget);
    expect(find.byType(ItemForm), findsNothing);
    expect(f.container.read(routerProvider).state.uri.path, '/unplanned');
    expect(tester.takeException(), isNull);
  });

  appTest('chooser route seeds the retained search', (tester) async {
    final f = await launch(tester);
    for (final (index, name) in ['Alpha medicine', 'Beta medicine'].indexed) {
      await runIo(
        tester,
        () => f.store.createItem(
          commandId: 'seed-$index',
          expectedPersonRevision: 2,
          name: name,
          form: 'Tablet',
          unit: 'count',
          type: 'Medicine',
        ),
      );
    }
    await go(tester, f.container, '/unplanned?q=Beta');
    expect(tester.widget<TextField>(field('Search')).controller!.text, 'Beta');
    expect(find.text('Beta medicine'), findsOneWidget);
    expect(find.text('Alpha medicine'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  appTest('lock covers quick entry and keeps its query on unlock', (
    tester,
  ) async {
    final f = await launch(tester, auth: FakeAuth());
    await go(tester, f.container, '/unplanned?q=Beta');
    expect(find.byType(QuickRecordSheet), findsOneWidget);

    await runIo(
      tester,
      () => f.container.read(appLockProvider.notifier).setEnabled(true),
    );
    f.container
        .read(appLockProvider.notifier)
        .lifecycle(AppLifecycleState.inactive);
    await settle(tester);
    expect(
      find.text(
        'Use your device screen lock to open Vital. '
        'Your unfinished entries stay private.',
      ),
      findsOneWidget,
    );
    expect(find.byType(QuickRecordSheet), findsNothing);

    f.container
        .read(appLockProvider.notifier)
        .lifecycle(AppLifecycleState.resumed);
    await tap(tester, 'Unlock');
    expect(find.byType(QuickRecordSheet), findsOneWidget);
    expect(tester.widget<TextField>(field('Search')).controller!.text, 'Beta');
    expect(tester.takeException(), isNull);
  });

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    appTest('recovery and choice fit 320px at 2x text in ${mode.name}', (
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
      final item = (await runIo(
        tester,
        () => f.store.createItem(
          commandId: 'narrow-$mode',
          expectedPersonRevision: 2,
          name: 'Narrow medicine',
          form: 'Tablet',
          unit: 'count',
          type: 'Medicine',
        ),
      ))!;

      await go(tester, f.container, '/unplanned?new=1&day=2026-02-30');
      expect(find.text('Continue').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);

      await go(
        tester,
        f.container,
        '/unplanned?new=1&item=${item.id}&day=2026-10-23',
      );
      expect(find.text('Create').hitTestable(), findsOneWidget);
      expect(find.text('Record').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  appTest('capture quick-entry recovery and choice evidence', (tester) async {
    const output = String.fromEnvironment('VITAL_T12_CAPTURES');
    if (output.isEmpty) return;
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final f = await launch(
      tester,
      todayClock: () => DateTime.utc(2026, 10, 22),
    );
    final item = (await runIo(
      tester,
      () => f.store.createItem(
        commandId: 'capture-item',
        expectedPersonRevision: 2,
        name: 'Synthetic medicine',
        form: 'Tablet',
        unit: 'count',
        type: 'Medicine',
      ),
    ))!;

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

    await go(tester, f.container, '/unplanned?new=1&day=2026-02-30&time=25:00');
    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      f.container.read(appearanceProvider.notifier).setMode(mode);
      await capture('${mode.name}-recovery');
    }

    await go(
      tester,
      f.container,
      '/unplanned?new=1&item=${item.id}&day=2026-10-23&plan=1&time=20:00',
    );
    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      f.container.read(appearanceProvider.notifier).setMode(mode);
      await capture('${mode.name}-choice');
    }

    tester.view.physicalSize = const Size(320, 900);
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    f.container.read(appearanceProvider.notifier).setMode(ThemeMode.dark);
    await go(tester, f.container, '/unplanned?new=1&day=2026-02-30');
    await capture('dark-320-recovery-2x');
  });
}
