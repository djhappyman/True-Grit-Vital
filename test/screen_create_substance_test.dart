import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:true_grit_vital/app/vital_app.dart';
import 'package:true_grit_vital/data/record_store.dart';
import 'package:true_grit_vital/features/recording/record_pages.dart';
import 'package:true_grit_vital/ui/stitch_ui.dart';
import 'package:true_grit_vital/ui/vital_ui.dart';

import 'vital_app_test.dart'
    show appTest, launch, runIo, settle, tap, waitForText;

Finder field(String label) => find.descendant(
  of: find.widgetWithText(LabelledInput, label),
  matching: find.byType(TextField),
);

Future<void> enter(WidgetTester tester, String label, String value) async {
  await tester.ensureVisible(field(label));
  await tester.enterText(field(label), value);
  await settle(tester);
}

void main() {
  appTest('identity save writes no schedule, stock, notes or example data', (
    tester,
  ) async {
    final f = await launch(tester);
    f.container.read(routerProvider).go('/create?person=$meId');
    await settle(tester);
    await waitForText(tester, 'New substance');
    expect(find.text('Drafting'), findsOneWidget);
    expect(find.text('Person: Me'), findsNothing);
    expect(find.text('Next steps'), findsOneWidget);
    expect(find.text('Optional'), findsOneWidget);
    expect(
      find.text(
        'Save this identity first. Schedule, stock and details are separate '
        'optional steps and nothing is assumed.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('food'), findsNothing);
    expect(
      find.text(
        'Strength belongs to a stock container. Add it from the substance overview after you save.',
      ),
      findsNothing,
    );

    await enter(tester, 'Full name', 'Invented complete substance');
    await tap(tester, 'Oral');
    await tap(tester, 'Tablet');
    await tap(tester, 'mg');
    await enter(tester, 'Type', 'Invented category');
    await tap(tester, 'Create');
    await waitForText(tester, 'Setup');
    await waitForText(tester, 'Invented complete substance');

    final items = (await runIo(tester, f.store.items))!;
    expect(items, hasLength(1));
    expect(items.single.name, 'Invented complete substance');
    expect(items.single.form, 'Tablet');
    expect(items.single.unit, 'mg');
    expect(items.single.type, 'Invented category');
    expect(await runIo(tester, f.store.records), isEmpty);
    expect(
      await runIo(tester, () => f.store.stockContainers(personId: meId)),
      isEmpty,
    );
    expect(await runIo(tester, f.store.dailyPlans), isEmpty);
    expect(
      (await runIo(
        tester,
        () => f.store.itemDetail(items.single.id),
      ))!.profile!.form,
      SubstanceForm.tablet,
    );
    final setup = await runIo(tester, () => f.store.itemSetup(items.single.id));
    expect(setup, isNotNull);
    expect(setup!.isComplete, isFalse);
    expect(await runIo(tester, f.store.drafts), isEmpty);
    expect(find.text('Skip'), findsNWidgets(2));
    expect(find.text('Finish'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  appTest('required name and form errors keep the entry open', (tester) async {
    final f = await launch(tester);
    f.container.read(routerProvider).go('/create?person=$meId');
    await settle(tester);
    await waitForText(tester, 'New substance');

    await tap(tester, 'Create');
    await waitForText(tester, 'Enter the full substance name.');
    expect(await runIo(tester, f.store.items), isEmpty);

    await enter(tester, 'Full name', 'Invented incomplete substance');
    await tap(tester, 'Create');
    await waitForText(
      tester,
      'Choose a unit and enter a form and type. Keep each field within 500 characters.',
    );
    expect(
      find.text(
        'Choose a unit and enter a form and type. Keep each field within 500 characters.',
      ),
      findsOneWidget,
    );
    expect(find.text('New substance'), findsOneWidget);
    expect(await runIo(tester, f.store.items), isEmpty);
    expect(tester.takeException(), isNull);
  });

  appTest('draft restores identity fields, form, unit and type choices', (
    tester,
  ) async {
    final f = await launch(tester);
    final router = f.container.read(routerProvider);
    router.go('/create?person=$meId');
    await settle(tester);
    await waitForText(tester, 'New substance');
    await enter(tester, 'Full name', 'Invented unfinished substance');
    await tap(tester, 'Oral');
    await tap(tester, 'Capsule');
    await tap(tester, 'ml');
    await enter(tester, 'Type', 'Invented draft category');
    await settle(tester);

    final drafts = (await runIo(tester, f.store.drafts))!;
    expect(drafts, hasLength(1));
    expect(drafts.single.fields['name'], 'Invented unfinished substance');
    expect(drafts.single.fields['form'], 'Capsule');
    expect(drafts.single.fields['unit'], 'ml');
    expect(drafts.single.fields['type'], 'Invented draft category');

    router.go('/today');
    await settle(tester);
    router.go('/create?person=$meId');
    await settle(tester);
    await waitForText(tester, 'Invented unfinished substance');
    expect(
      tester.widget<TextField>(field('Full name')).controller!.text,
      'Invented unfinished substance',
    );
    expect(find.text('Capsule'), findsOneWidget);
    expect(
      tester.widget<TextField>(field('Type')).controller!.text,
      'Invented draft category',
    );
    final selectedCapsule = tester
        .widgetList<Semantics>(
          find.ancestor(
            of: find.text('Capsule'),
            matching: find.byType(Semantics),
          ),
        )
        .any((semantics) => semantics.properties.selected == true);
    final selectedMl = tester
        .widgetList<Semantics>(
          find.ancestor(of: find.text('ml'), matching: find.byType(Semantics)),
        )
        .any((semantics) => semantics.properties.selected == true);
    expect(selectedCapsule, isTrue);
    expect(selectedMl, isTrue);
    expect(tester.takeException(), isNull);
  });

  appTest('dirty cancel keeps editing, then discards the encrypted draft', (
    tester,
  ) async {
    final f = await launch(tester);
    final router = f.container.read(routerProvider);
    router.go('/create?person=$meId');
    await settle(tester);
    await waitForText(tester, 'New substance');
    await enter(tester, 'Full name', 'Invented cancelled substance');

    await tap(tester, 'Back');
    await waitForText(tester, 'Unsaved changes');
    await tap(tester, 'Keep');
    expect(find.text('New substance'), findsOneWidget);
    expect(await runIo(tester, f.store.drafts), hasLength(1));

    await tap(tester, 'Back');
    await waitForText(tester, 'Unsaved changes');
    await tap(tester, 'Discard');
    await waitForText(tester, 'Substances');
    expect(await runIo(tester, f.store.drafts), isEmpty);
    expect(await runIo(tester, f.store.items), isEmpty);
    expect(tester.takeException(), isNull);
  });

  appTest('controls reach 48px and Create stays reachable at 320px 2x', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 740);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final f = await launch(tester);
    f.container.read(routerProvider).go('/create?person=$meId');
    await settle(tester);
    await waitForText(tester, 'New substance');

    await tap(tester, 'Oral');
    final tablet = find.widgetWithText(VitalButton, 'Tablet');
    expect(tester.getSize(tablet).height, greaterThanOrEqualTo(48));
    final milligrams = find.widgetWithText(StitchButton, 'mg');
    expect(tester.getSize(milligrams).height, greaterThanOrEqualTo(48));

    await tester.scrollUntilVisible(
      find.widgetWithText(StitchButton, 'Create'),
      240,
      scrollable: find.byType(Scrollable).first,
    );
    await settle(tester);
    final create = find.widgetWithText(StitchButton, 'Create');
    expect(create.hitTestable(), findsOneWidget);
    await tester.tap(create);
    await settle(tester);
    expect(find.text('Enter the full substance name.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  appTest('Create stays above an open keyboard', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final f = await launch(tester);
    f.container.read(routerProvider).go('/create?person=$meId');
    await settle(tester);
    await waitForText(tester, 'New substance');

    await tester.tap(field('Type'));
    await settle(tester);
    tester.view.viewInsets = const FakeViewPadding(bottom: 320);
    await settle(tester);

    final create = find.widgetWithText(StitchButton, 'Create');
    await tester.scrollUntilVisible(
      create,
      240,
      scrollable: find.byType(Scrollable).first,
    );
    await settle(tester);
    expect(create.hitTestable(), findsOneWidget);
    expect(tester.getRect(create).bottom, lessThanOrEqualTo(844 - 320));
    expect(tester.takeException(), isNull);
  });

  appTest('long custom type names stay complete at 320px 2x', (tester) async {
    tester.view.physicalSize = const Size(320, 740);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    const longName = 'Prescription compounded hormone therapy';
    final f = await launch(tester);
    await runIo(tester, () async {
      final person = (await f.store.profileById(meId))!;
      await f.store.createItemType(
        commandId: 'long-type',
        personId: meId,
        expectedPersonRevision: person.revision,
        name: longName,
      );
    });
    f.container.read(routerProvider).go('/create?person=$meId');
    await settle(tester);
    await waitForText(tester, 'New substance');

    final chip = find.widgetWithText(StitchButton, longName);
    await tester.ensureVisible(chip);
    await settle(tester);
    expect(chip, findsOneWidget);
    expect(tester.getSize(chip).width, lessThanOrEqualTo(288));
    await tap(tester, longName);
    await settle(tester);
    expect(find.text('Selected type: $longName'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
