import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:true_grit_vital/app/vital_app.dart';
import 'package:true_grit_vital/data/record_store.dart';
import 'package:true_grit_vital/features/recording/record_pages.dart';
import 'package:true_grit_vital/ui/vital_ui.dart';

import 'vital_app_test.dart'
    show appTest, launch, runIo, settle, tap, waitForText;

Finder field(String label) => find.descendant(
  of: find.widgetWithText(LabelledInput, label),
  matching: find.byType(TextField),
);

Finder panelButton(String panelTitle, String label) => find.descendant(
  of: find
      .ancestor(of: find.text(panelTitle), matching: find.byType(VitalPanel))
      .first,
  matching: find.widgetWithText(VitalButton, label),
);

Future<SubstanceItem> createItem(RecordStore store, String name) =>
    store.createItem(
      commandId: newCommandId(),
      expectedPersonRevision: 2,
      name: name,
      form: 'Tablet',
      unit: 'mg',
      type: 'Medicine',
    );

Future<void> enter(WidgetTester tester, String label, String value) async {
  await tester.ensureVisible(field(label));
  await tester.enterText(field(label), value);
  await settle(tester);
}

Future<void> tapPanelButton(
  WidgetTester tester,
  String panelTitle,
  String label,
) async {
  final target = panelButton(panelTitle, label);
  await tester.ensureVisible(target);
  await settle(tester);
  expect(target.hitTestable(), findsOneWidget);
  await tester.tap(target);
  await settle(tester);
}

void main() {
  appTest('setup resumes and skips only the steps chosen', (tester) async {
    final f = await launch(tester);
    final item = (await runIo(
      tester,
      () => createItem(f.store, 'Resumable setup substance'),
    ))!;
    final router = f.container.read(routerProvider);

    router.go('/substance/${item.id}/setup');
    await settle(tester);
    await waitForText(tester, 'Setup');
    expect(find.text('Resumable setup substance'), findsOneWidget);
    expect(find.text('Skip'), findsNWidgets(3));

    await tapPanelButton(tester, 'Schedule', 'Skip');

    final afterSchedule = (await runIo(
      tester,
      () => f.store.itemSetup(item.id),
    ))!;
    expect(afterSchedule.scheduleSkipped, isTrue);
    await waitForText(tester, 'Skipped');
    expect(afterSchedule.scheduleSkipped, isTrue);
    expect(afterSchedule.stockSkipped, isFalse);
    expect(afterSchedule.isComplete, isFalse);
    expect(await runIo(tester, f.store.dailyPlans), isEmpty);

    await tapPanelButton(tester, 'Stock', 'Skip');
    await tapPanelButton(tester, 'Details', 'Skip');

    await tester.tap(find.widgetWithText(VitalButton, 'Finish'));
    await settle(tester);
    await waitForText(tester, 'Resumable setup substance');
    expect(router.routerDelegate.state.uri.path, '/substance/${item.id}');

    final completed = (await runIo(tester, () => f.store.itemSetup(item.id)))!;
    expect(completed.isComplete, isTrue);
    expect(completed.stockSkipped, isTrue);
    expect(completed.detailsSkipped, isTrue);
    expect(await runIo(tester, f.store.records), isEmpty);
    expect(await runIo(tester, f.store.dailyPlans), isEmpty);
    expect(
      await runIo(tester, () => f.store.stockContainers(personId: meId)),
      isEmpty,
    );
    expect(find.text('Continue'), findsNothing);
    expect(find.text('No details added'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  appTest('overview resumes an unfinished setup and saves details', (
    tester,
  ) async {
    final f = await launch(tester);
    final item = (await runIo(
      tester,
      () => createItem(f.store, 'Interrupted setup substance'),
    ))!;
    final router = f.container.read(routerProvider);

    router.go('/substance/${item.id}');
    await settle(tester);
    await waitForText(tester, 'Interrupted setup substance');
    expect(find.text('Continue'), findsOneWidget);
    expect(find.text('No details added'), findsOneWidget);

    await tap(tester, 'Continue');
    await waitForText(tester, 'Setup');
    expect(router.routerDelegate.state.uri.path, '/substance/${item.id}/setup');

    await tapPanelButton(tester, 'Details', 'Add');
    await waitForText(tester, 'Instructions');
    expect(
      router.routerDelegate.state.uri.path,
      '/substance/${item.id}/details',
    );

    const instructions = 'Use the labelled amount: 0.125 mg, <0.10.';
    const notes = 'Private note kept word for word.';
    await enter(tester, 'Instructions', instructions);
    await enter(tester, 'Private notes', notes);
    await tap(tester, 'Save');
    await settle(tester);
    await waitForText(tester, 'Interrupted setup substance');
    expect(router.routerDelegate.state.uri.path, '/substance/${item.id}/setup');
    await waitForText(tester, 'Added');

    final detail = (await runIo(tester, () => f.store.itemDetail(item.id)))!;
    expect(detail.instructions, instructions);
    expect(detail.notes, notes);
    expect(detail.revision, 1);
    router.go('/substance/${item.id}');
    await settle(tester);
    await waitForText(tester, instructions);
    expect(find.text(notes), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  appTest('setup returns from the canonical schedule and stock editors', (
    tester,
  ) async {
    final f = await launch(tester);
    final item = (await runIo(
      tester,
      () => createItem(f.store, 'Guided setup substance'),
    ))!;
    final router = f.container.read(routerProvider);
    router.go('/substance/${item.id}/setup');
    await settle(tester);
    await waitForText(tester, 'Setup');
    await tapPanelButton(tester, 'Schedule', 'Add');
    await waitForText(tester, 'As needed');
    await tap(tester, 'As needed');
    await tap(tester, 'Preview');
    await tap(tester, 'Save');
    await settle(tester);
    await waitForText(tester, 'Setup');
    expect(router.routerDelegate.state.uri.path, '/substance/${item.id}/setup');
    expect((await runIo(tester, f.store.dailyPlans))!, hasLength(1));
    await tapPanelButton(tester, 'Stock', 'Add');
    await waitForText(tester, 'Container name');
    await enter(tester, 'Container name', 'Opening bottle');
    await enter(tester, 'Labelled strength', 'Original tablet label');
    await tap(tester, 'Create');
    await settle(tester);
    await waitForText(tester, 'Setup');
    expect(router.routerDelegate.state.uri.path, '/substance/${item.id}/setup');
    expect(
      (await runIo(tester, () => f.store.stockContainers(personId: meId)))!,
      hasLength(1),
    );
    expect(await runIo(tester, f.store.records), isEmpty);
    expect(tester.takeException(), isNull);
  });

  appTest('details draft survives leaving the form', (tester) async {
    final f = await launch(tester);
    final item = (await runIo(
      tester,
      () => createItem(f.store, 'Draft detail substance'),
    ))!;
    final router = f.container.read(routerProvider);
    router.go('/substance/${item.id}/details');
    await settle(tester);
    await waitForText(tester, 'Instructions');

    await enter(tester, 'Instructions', 'Unfinished authored instruction');
    await enter(tester, 'Private notes', 'Unfinished private note');
    router.go('/substance/${item.id}');
    await settle(tester);
    expect(await runIo(tester, f.store.drafts), hasLength(1));

    router.go('/substance/${item.id}/details');
    await settle(tester);
    await waitForText(tester, 'Unfinished authored instruction');
    expect(
      tester.widget<TextField>(field('Instructions')).controller!.text,
      'Unfinished authored instruction',
    );
    expect(
      tester.widget<TextField>(field('Private notes')).controller!.text,
      'Unfinished private note',
    );
    expect(await runIo(tester, () => f.store.itemDetail(item.id)), isNull);
    expect(tester.takeException(), isNull);
  });

  appTest('setup and details stay usable at 320px with 2x text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 740);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final f = await launch(tester);
    final item = (await runIo(
      tester,
      () => createItem(f.store, 'Narrow setup substance'),
    ))!;
    final router = f.container.read(routerProvider);

    router.go('/substance/${item.id}/setup');
    await settle(tester);
    await waitForText(tester, 'Setup');
    await tester.scrollUntilVisible(
      find.widgetWithText(VitalButton, 'Finish'),
      240,
      scrollable: find.byType(Scrollable).first,
    );
    await settle(tester);
    expect(
      find.widgetWithText(VitalButton, 'Finish').hitTestable(),
      findsOneWidget,
    );

    router.go('/substance/${item.id}/details');
    await settle(tester);
    await waitForText(tester, 'Instructions');
    await enter(tester, 'Instructions', 'Narrow instruction text');
    await tester.scrollUntilVisible(
      find.widgetWithText(VitalButton, 'Save'),
      240,
      scrollable: find.byType(Scrollable).first,
    );
    await settle(tester);
    expect(
      find.widgetWithText(VitalButton, 'Save').hitTestable(),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
