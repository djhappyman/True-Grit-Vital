import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:true_grit_vital/app/vital_app.dart';
import 'package:true_grit_vital/app/display_preferences.dart';
import 'package:true_grit_vital/features/recording/record_pages.dart';
import 'package:true_grit_vital/data/record_store.dart';
import 'package:true_grit_vital/features/recording/dose_sheet.dart';
import 'package:true_grit_vital/features/supporting/supporting_pages.dart';
import 'package:true_grit_vital/ui/stitch_ui.dart';

import 'vital_app_test.dart'
    show appTest, launch, runIo, settle, tap, waitForText;

Future<SubstanceItem> createItem(
  RecordStore store, {
  String name = 'Synthetic dose',
  String unit = 'ml',
  String form = 'Liquid',
  String type = 'Prescription',
}) async => store.createItem(
  expectedPersonRevision: (await store.profileById(meId))!.revision,
  commandId: newCommandId(),
  name: name,
  form: form,
  unit: unit,
  type: type,
);

Future<StoredStockContainer> createContainer(
  RecordStore store,
  SubstanceItem item, {
  String? opening = '2',
  String? threshold = '1',
  String strength = '10',
  String unit = 'ml',
  String label = 'Original bottle',
}) async => store.createStockContainer(
  commandId: newCommandId(),
  personId: item.personId,
  expectedPersonRevision: (await store.profileById(item.personId))!.revision,
  expectedGeneration: store.generation,
  itemId: item.id,
  label: label,
  unit: unit,
  strength: LabelledStrength(
    ingredientId: item.id,
    label: '$strength mg/ml',
    mgPerMl: ExactAmount.parseEntry(strength),
  ),
  opening: opening == null ? null : ExactAmount.parseEntry(opening),
  lowThreshold: threshold == null ? null : ExactAmount.parseEntry(threshold),
  refillEnabled: false,
);

Future<void> enterAmount(WidgetTester tester, String value) async {
  final field = find.byType(TextField).first;
  await tester.ensureVisible(field);
  await tester.enterText(field, value);
  await settle(tester);
}

Future<void> selectSource(WidgetTester tester, String id) async {
  final button = find.byKey(ValueKey('choose-$id'));
  await tester.ensureVisible(button);
  await settle(tester);
  await tester.tap(button);
  await settle(tester);
}

void main() {
  appTest('record sheet uses live identity and exact stock consequence', (
    tester,
  ) async {
    final f = await launch(tester);
    final item = (await runIo(
      tester,
      () => createItem(
        f.store,
        name: 'Telmisartan 40mg complete product name',
        type: 'Prescription',
        form: 'Oral tablet',
      ),
    ))!;
    final container = (await runIo(
      tester,
      () => createContainer(f.store, item),
    ))!;
    f.container.read(routerProvider).go('/record/${item.id}');
    await settle(tester);

    expect(find.byType(DoseSheetHeader), findsOneWidget);
    expect(find.text('Record dose'), findsOneWidget);
    expect(find.text('Edit'), findsOneWidget);
    expect(find.text('Telmisartan 40mg complete product name'), findsOneWidget);
    expect(find.text('Prescription · Oral tablet'), findsOneWidget);
    expect(find.text('QUANTITY'), findsOneWidget);
    expect(find.text('CONTEXT & CONDITIONS'), findsNothing);
    expect(find.text('VITALS & OBSERVATIONS'), findsNothing);
    expect(find.text('PRN'), findsNothing);
    expect(find.text('Skip'), findsNothing);

    await enterAmount(tester, '1');
    await selectSource(tester, container.id);
    expect(find.text('Deducts 1 ml, leaving 1 ml.'), findsOneWidget);
    expect(find.text('Low stock at or below 1 ml.'), findsOneWidget);

    final save = tester.getSize(find.widgetWithText(StitchButton, 'Save'));
    final edit = tester.getSize(find.widgetWithText(StitchButton, 'Edit'));
    expect(save.height, greaterThanOrEqualTo(48));
    expect(edit.height, greaterThanOrEqualTo(48));
    expect(tester.takeException(), isNull);
  });

  appTest('unknown stock stays explicit without inventing a deduction', (
    tester,
  ) async {
    final f = await launch(tester);
    final item = (await runIo(tester, () => createItem(f.store)))!;
    final container = (await runIo(
      tester,
      () => createContainer(f.store, item, opening: null),
    ))!;
    f.container.read(routerProvider).go('/record/${item.id}');
    await settle(tester);
    expect(find.text('Record dose'), findsOneWidget);
    await enterAmount(tester, '1');
    await selectSource(tester, container.id);
    expect(
      find.text('Deducts 1 ml. Remaining balance is unknown.'),
      findsOneWidget,
    );
    await tap(tester, 'Save');
    await waitForText(tester, 'Saved for Me: Synthetic dose, 1 ml.');
    expect((await runIo(tester, () => f.store.records()))!.length, 1);
  });

  appTest('a negative balance is previewed without blocking the dose', (
    tester,
  ) async {
    final f = await launch(tester);
    final item = (await runIo(tester, () => createItem(f.store)))!;
    final container = (await runIo(
      tester,
      () => createContainer(f.store, item, opening: '1'),
    ))!;
    f.container.read(routerProvider).go('/record/${item.id}');
    await settle(tester);
    await enterAmount(tester, '2');
    await selectSource(tester, container.id);
    expect(find.text('This leaves the balance below zero.'), findsOneWidget);
    expect(find.widgetWithText(StitchButton, 'Save'), findsOneWidget);
  });

  appTest('unconvertible stock units are named instead of guessed', (
    tester,
  ) async {
    final f = await launch(tester);
    final item = (await runIo(tester, () => createItem(f.store, unit: 'mg')))!;
    final container = (await runIo(
      tester,
      () async => f.store.createStockContainer(
        commandId: newCommandId(),
        personId: item.personId,
        expectedPersonRevision: (await f.store.profileById(item.personId))!
            .revision,
        expectedGeneration: f.store.generation,
        itemId: item.id,
        label: 'Counted supply',
        unit: 'count',
        strength: LabelledStrength(
          ingredientId: item.id,
          label: 'Unlabelled concentration',
        ),
        opening: ExactAmount.parseEntry('2'),
      ),
    ))!;
    f.container.read(routerProvider).go('/record/${item.id}');
    await settle(tester);
    await enterAmount(tester, '1');
    await selectSource(tester, container.id);
    expect(
      find.text('The stock deduction cannot be calculated for these units.'),
      findsOneWidget,
    );
  });

  appTest('observations action opens supporting observations for this item', (
    tester,
  ) async {
    final f = await launch(tester);
    final item = (await runIo(tester, () => createItem(f.store)))!;
    f.container.read(routerProvider).go('/record/${item.id}');
    await settle(tester);
    await tap(tester, 'More');
    await tap(tester, 'Observations');
    expect(find.byType(SupportingRecordsPage), findsOneWidget);
    final page = tester.widget<SupportingRecordsPage>(
      find.byType(SupportingRecordsPage),
    );
    expect(page.location, contains('kind=observation'));
    expect(Uri.parse(page.location).queryParameters['item'], item.id);
  });

  appTest('header respects the chosen clock format without changing entry', (
    tester,
  ) async {
    final f = await launch(tester);
    final item = (await runIo(tester, () => createItem(f.store)))!;
    f.container.read(routerProvider).go('/record/${item.id}');
    await waitForText(tester, 'Record dose');
    Finder field(String label) => find.descendant(
      of: find.widgetWithText(LabelledInput, label),
      matching: find.byType(TextField),
    );
    await tap(tester, 'Edit');
    final time = field('Actual time');
    await tester.ensureVisible(time);
    await tester.enterText(time, '20:15');
    await settle(tester);
    await runIo(
      tester,
      () => f.container
          .read(displayPreferencesProvider.notifier)
          .setTimeFormat(TimeFormat.h24),
    );
    await settle(tester);
    expect(
      tester.widget<DoseSheetHeader>(find.byType(DoseSheetHeader)).timestamp,
      contains('20:15'),
    );
    await runIo(
      tester,
      () => f.container
          .read(displayPreferencesProvider.notifier)
          .setTimeFormat(TimeFormat.h12),
    );
    await settle(tester);
    final header = tester.widget<DoseSheetHeader>(find.byType(DoseSheetHeader));
    expect(header.timestamp, contains('8:15'));
    expect(header.timestamp, contains('PM'));
    expect(tester.widget<TextField>(time).controller!.text, '20:15');
    expect(await runIo(tester, f.store.records), isEmpty);
    expect(tester.takeException(), isNull);
  });

  appTest('320/390/430 layouts keep the full dose sheet reachable', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final f = await launch(tester);
    final item = (await runIo(
      tester,
      () => createItem(
        f.store,
        name: 'A complete long substance name that must never clip',
      ),
    ))!;
    final container = (await runIo(
      tester,
      () => createContainer(f.store, item),
    ))!;
    f.container.read(routerProvider).go('/record/${item.id}');
    await settle(tester);
    for (final size in const [Size(320, 740), Size(390, 844), Size(430, 932)]) {
      for (final scale in const [1.0, 2.0]) {
        tester.view.physicalSize = size;
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        await tester.pump();
        await settle(tester);
        await enterAmount(tester, '0.5');
        await selectSource(tester, container.id);
        await tester.ensureVisible(find.widgetWithText(StitchButton, 'Save'));
        await settle(tester);
        expect(
          find.text('A complete long substance name that must never clip'),
          findsOneWidget,
          reason: '$size at ${scale}x',
        );
        expect(
          find.widgetWithText(StitchButton, 'Save'),
          findsOneWidget,
          reason: '$size at ${scale}x',
        );
        expect(tester.takeException(), isNull, reason: '$size at ${scale}x');
      }
    }
  });
}
