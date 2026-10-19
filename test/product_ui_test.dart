import 'package:true_grit_vital/ui/vital_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:true_grit_vital/app/vital_app.dart';
import 'package:true_grit_vital/data/record_store.dart';
import 'package:true_grit_vital/features/recording/record_pages.dart';
import 'package:true_grit_vital/features/products/product_widgets.dart';
import 'package:true_grit_vital/features/plans/daily_feed.dart';

import 'stock_ui_test.dart' show enter, select;
import 'vital_app_test.dart'
    show appTest, launch, runIo, settle, tap, waitForText;

List<ProductComponent> ingredients({String known = '3', String? second}) => [
  ProductComponent(
    ingredientId: 'amber-identity',
    name: 'Invented amber full ingredient name',
    concentrationText: known,
  ),
  ProductComponent(
    ingredientId: 'blue-identity',
    name: 'Invented blue full ingredient name',
    concentrationText: second,
  ),
];
Future<SubstanceItem> product(RecordStore store) => store.createItem(
  commandId: newCommandId(),
  expectedPersonRevision: 2,
  name: 'Invented ready-mixed product',
  form: 'Liquid',
  unit: 'ml',
  type: 'Test',
  productComponents: ingredients(),
);
Future<void> tapFinder(WidgetTester tester, Finder target) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await settle(tester);
  await tester.ensureVisible(target);
  await settle(tester);
  await tester.tap(target);
  await settle(tester);
}

Finder ingredientField(String label, int index) => find.descendant(
  of: find.widgetWithText(LabelledInput, label).at(index),
  matching: find.byType(TextField),
);
Future<void> editIngredient(
  WidgetTester tester,
  String label,
  int index,
  String value,
) async {
  final target = ingredientField(label, index);
  await tester.ensureVisible(target);
  await tester.enterText(target, value);
  await settle(tester);
}

void main() {
  appTest(
    'ready-mixed creation saves one ml item and separate unknown ingredient',
    (tester) async {
      final f = await launch(tester);
      f.container.read(routerProvider).go('/create?person=$meId');
      await settle(tester);
      await enter(tester, 'Full name', 'Invented created blend');
      await enter(tester, 'Form', 'Liquid');
      await tap(tester, 'Ready-mixed product');
      await editIngredient(tester, 'Ingredient name', 0, 'Complete amber name');
      await editIngredient(tester, 'Ingredient name', 1, 'Complete blue name');
      await tapFinder(tester, find.text('Known strength').first);
      await editIngredient(tester, 'Concentration', 0, '3,5');
      await enter(tester, 'Type', 'Test');
      await tap(tester, 'Create');
      await waitForText(tester, 'Invented created blend');
      final saved = (await runIo(tester, () => f.store.items()))!.single;
      expect(saved.unit, 'ml');
      final label = await runIo(
        tester,
        () => f.store.productLabel(personId: meId, itemId: saved.id),
      );
      expect(label!.components.map((c) => c.name), [
        'Complete amber name',
        'Complete blue name',
      ]);
      expect(label.components.first.concentrationText, '3.5');
      expect(label.components.last.mgPerMl, isNull);
      expect(await runIo(tester, f.store.records), isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  appTest(
    'product source preview keeps ml and consumes supply once; correction retains labels',
    (tester) async {
      final f = await launch(tester);
      final item = (await runIo(tester, () => product(f.store)))!;
      final label = (await runIo(
        tester,
        () => f.store.productLabel(personId: meId, itemId: item.id),
      ))!;
      final source = ProductLabelSnapshot(
        personId: meId,
        itemId: item.id,
        revision: label.revision,
        components: ingredients(known: '7'),
      );
      final c = (await runIo(
        tester,
        () => f.store.createStockContainer(
          commandId: newCommandId(),
          expectedGeneration: f.store.generation,
          personId: meId,
          expectedPersonRevision: 2,
          itemId: item.id,
          label: 'Invented source bottle',
          unit: 'ml',
          strength: LabelledStrength(ingredientId: item.id, label: item.name),
          productLabel: source,
          opening: ExactAmount.parseEntry('5'),
        ),
      ))!;
      f.container.read(routerProvider).go('/record/${item.id}');
      await settle(tester);
      await enter(tester, 'Amount', '2');
      await select(tester, c.id);
      expect(find.text('Amount: 14 mg.'), findsOneWidget);
      expect(find.text('Amount unknown.'), findsWidgets);
      expect(find.text('Default label'), findsOneWidget);
      expect(find.text('Selected label'), findsOneWidget);
      await tap(tester, 'Save');
      await waitForText(tester, 'Me: 2 ml');
      final record = (await runIo(tester, f.store.records))!.single;
      expect(
        record.product!.components.first.amount,
        ExactAmount.parseEntry('14'),
      );
      expect(record.product!.components.last.amount, isNull);
      expect(
        (await runIo(
          tester,
          () => f.store.stockContainerById(personId: meId, containerId: c.id),
        ))!.balance.value,
        ExactAmount.parseEntry('3'),
      );
      f.container.read(routerProvider).go('/correct/${record.id}?person=$meId');
      await settle(tester);
      await enter(tester, 'Actual time', '12:34');
      await tap(tester, 'Keep consumed');
      await tap(tester, 'Save');
      await waitForText(tester, 'Me: 2 ml');
      final history = (await runIo(tester, () => f.store.history(record.id)))!;
      expect(history.length, 2);
      expect(
        history.last.product!.label.components.first.concentrationText,
        '7',
      );
      expect(history.last.product!.volume, ExactAmount.parseEntry('2'));
      final movements = (await runIo(
        tester,
        () => f.store.stockMovements(personId: meId, containerId: c.id),
      ))!;
      expect(
        movements.where((m) => m.kind == StockMovementKind.actualUse).length,
        1,
      );
      expect(tester.takeException(), isNull);
    },
  );

  appTest('label draft reopens raw fields and saves a new future snapshot', (
    tester,
  ) async {
    final f = await launch(tester);
    final item = (await runIo(tester, () => product(f.store)))!;
    f.container.read(routerProvider).go('/products/$meId/label/${item.id}');
    await settle(tester);
    await editIngredient(tester, 'Concentration', 0, 'not a number');
    await settle(tester);
    final drafts = (await runIo(tester, f.store.drafts))!;
    expect(drafts.single.kind, DraftKind.productLabel);
    expect(drafts.single.fields['productComponents'], contains('not a number'));
    f.container.read(routerProvider).go('/today');
    await settle(tester);
    f.container.read(routerProvider).go('/products/$meId/label/${item.id}');
    await settle(tester);
    expect(
      tester
          .widget<TextField>(ingredientField('Concentration', 0))
          .controller!
          .text,
      'not a number',
    );
    await tap(tester, 'Save');
    expect(
      find.text(
        'Enter 2–32 ingredients with names and units. Known concentrations must be positive decimals with up to six decimal places.',
      ),
      findsWidgets,
    );
    await editIngredient(tester, 'Concentration', 0, '9');
    await tap(tester, 'Save');
    await waitForText(tester, 'Label: 9 mg/ml.');
    expect(
      (await runIo(
        tester,
        () => f.store.productLabel(personId: meId, itemId: item.id),
      ))!.revision,
      2,
    );
    expect(tester.takeException(), isNull);
  });

  appTest(
    'container captures edited ingredients and unsupported label units remain unknown',
    (tester) async {
      final f = await launch(tester);
      final item = (await runIo(tester, () => product(f.store)))!;
      f.container
          .read(routerProvider)
          .go('/stock/$meId/create?item=${item.id}');
      await settle(tester);
      await enter(tester, 'Container name', 'Independent labelled bottle');
      await editIngredient(tester, 'Concentration', 0, '7');
      await editIngredient(tester, 'Mass unit', 0, 'IU');
      await tap(tester, 'Create');
      await waitForText(tester, 'Independent labelled bottle');
      final c = (await runIo(
        tester,
        () => f.store.stockContainers(personId: meId),
      ))!.single;
      expect(c.productLabel!.components.first.concentrationText, '7');
      expect(c.productLabel!.components.first.massUnit, 'IU');
      expect(c.productLabel!.components.first.mgPerMl, isNull);
      f.container.read(routerProvider).go('/record/${item.id}');
      await settle(tester);
      await enter(tester, 'Amount', '1');
      await select(tester, c.id);
      expect(find.text('Label: 7 IU/ml.'), findsWidgets);
      expect(find.text('Amount unknown.'), findsWidgets);
      await tap(tester, 'Save');
      await waitForText(tester, 'Me: 1 ml');
      final r = (await runIo(tester, f.store.records))!.single;
      expect(r.product!.components.every((c) => c.amount == null), true);
      expect(r.product!.volume, ExactAmount.parseEntry('1'));
      expect(tester.takeException(), isNull);
    },
  );

  appTest(
    'same-name adult label draft keeps ownership through scope change and archive',
    (tester) async {
      final f = await launch(tester);
      final adult = (await runIo(
        tester,
        () => f.store.createProfile(
          commandId: newCommandId(),
          name: 'Alex',
          adultConfirmed: true,
        ),
      ))!;
      await runIo(
        tester,
        () => f.store.createProfile(
          commandId: newCommandId(),
          name: 'Alex',
          adultConfirmed: true,
        ),
      );
      final item = (await runIo(
        tester,
        () => f.store.createItem(
          commandId: newCommandId(),
          personId: adult.id,
          expectedPersonRevision: adult.revision,
          name: 'Alex full product name',
          form: 'Liquid',
          unit: 'ml',
          type: 'Test',
          productComponents: ingredients(),
        ),
      ))!;
      f.container
          .read(routerProvider)
          .go('/products/${adult.id}/label/${item.id}');
      await settle(tester);
      await editIngredient(
        tester,
        'Ingredient name',
        0,
        'Unfinished original ingredient',
      );
      await runIo(
        tester,
        () => f.store.saveBrowsingScope(const FeedScope.me()),
      );
      await settle(tester);
      expect(find.text('Person: Alex. Profile ${adult.id}'), findsOneWidget);
      final draft = (await runIo(tester, f.store.drafts))!.single;
      expect(draft.personId, adult.id);
      await runIo(
        tester,
        () => f.store.archiveProfile(
          commandId: newCommandId(),
          personId: adult.id,
          expectedRevision: adult.revision,
        ),
      );
      await settle(tester);
      expect(
        tester
            .widget<VitalButton>(find.widgetWithText(VitalButton, 'Save'))
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<TextField>(ingredientField('Ingredient name', 0))
            .controller!
            .text,
        'Unfinished original ingredient',
      );
      expect(tester.takeException(), isNull);
    },
  );

  appTest(
    'planned product Taken captures selected label and Undo reverses one volume',
    (tester) async {
      final f = await launch(tester);
      final item = (await runIo(tester, () => product(f.store)))!;
      final label = (await runIo(
        tester,
        () => f.store.productLabel(personId: meId, itemId: item.id),
      ))!;
      final c = (await runIo(
        tester,
        () => f.store.createStockContainer(
          commandId: newCommandId(),
          expectedGeneration: f.store.generation,
          personId: meId,
          expectedPersonRevision: 2,
          itemId: item.id,
          label: 'Planned blend bottle',
          unit: 'ml',
          strength: LabelledStrength(ingredientId: item.id, label: item.name),
          productLabel: ProductLabelSnapshot(
            personId: meId,
            itemId: item.id,
            revision: 1,
            components: ingredients(known: '8'),
          ),
          opening: ExactAmount.parseEntry('5'),
        ),
      ))!;
      await runIo(
        tester,
        () => f.store.saveDailyPlan(
          commandId: newCommandId(),
          expectedGeneration: f.store.generation,
          expectedPersonRevision: 2,
          plan: DailyPlanVersion(
            personId: meId,
            planId: 'product-plan',
            itemId: item.id,
            versionId: 'product-v1',
            start: CivilDate.fromDateTime(DateTime.now()),
            zoneBasis: const FollowingLocal(),
            timing: DailyCount(
              1,
              PlannedAmount(
                quantity: ExactQuantity.parse('0.5'),
                enteredText: '0.5',
                unit: 'ml',
              ),
            ),
          ),
        ),
      );
      f.container.read(routerProvider).go('/today');
      await settle(tester);
      await tap(tester, 'Source');
      await select(tester, c.id);
      expect(find.text('Amount: 4 mg.'), findsOneWidget);
      await tap(tester, 'Taken');
      await waitForText(tester, '1 recorded, 0 skipped, 1 planned');
      final record = (await runIo(tester, f.store.records))!.single;
      expect(record.product!.defaultLabel.revision, label.revision);
      expect(
        record.product!.components.first.amount,
        ExactAmount.parseEntry('4'),
      );
      expect(record.product!.components.last.amount, isNull);
      expect(
        (await runIo(
          tester,
          () => f.store.stockContainerById(personId: meId, containerId: c.id),
        ))!.balance.value,
        ExactAmount.parseEntry('4.5'),
      );
      final undo = find
          .descendant(
            of: find.byType(DailyRowCard),
            matching: find.text('Undo'),
          )
          .first;
      await tapFinder(tester, undo);
      await tap(tester, 'Reverse entry');
      await waitForText(tester, '0 recorded, 0 skipped, 1 planned');
      expect(
        (await runIo(
          tester,
          () => f.store.stockContainerById(personId: meId, containerId: c.id),
        ))!.balance.value,
        ExactAmount.parseEntry('5'),
      );
      expect((await runIo(tester, f.store.records))!.single.isVoided, true);
      expect(tester.takeException(), isNull);
    },
  );

  appTest(
    'product label remains readable at narrow large text and keyboard traversal works',
    (tester) async {
      tester.view.physicalSize = const Size(375, 812);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final f = await launch(tester);
      final item = (await runIo(tester, () => product(f.store)))!;
      f.container.read(routerProvider).go('/products/$meId/label/${item.id}');
      await settle(tester);
      final field = ingredientField('Ingredient name', 0);
      await tester.ensureVisible(field);
      await tester.tap(field);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await settle(tester);
      expect(FocusManager.instance.primaryFocus, isNotNull);
      expect(find.byType(ProductComponentEditor), findsOneWidget);
      await tester.ensureVisible(find.text('Save'));
      expect(tester.takeException(), isNull);
      for (final size in [const Size(812, 375), const Size(1280, 800)]) {
        tester.view.physicalSize = size;
        await settle(tester);
        await tester.ensureVisible(find.text('Save'));
        expect(tester.takeException(), isNull);
      }
    },
  );
}
