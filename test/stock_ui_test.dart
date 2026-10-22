import 'package:true_grit_vital/ui/vital_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:true_grit_vital/app/vital_app.dart';
import 'package:true_grit_vital/app/app_lock.dart';
import 'package:true_grit_vital/data/record_store.dart';
import 'package:true_grit_vital/features/recording/record_pages.dart';
import 'package:true_grit_vital/features/plans/daily_feed.dart';

import 'private_drafts_ui_test.dart' show FakeAuth;
import 'vital_app_test.dart'
    show appTest, launch, runIo, settle, tap, waitForText;

Finder field(String label) => find.descendant(
  of: find.widgetWithText(LabelledInput, label),
  matching: find.byType(TextField),
);
Future<void> enter(WidgetTester tester, String label, String value) async {
  if ((label == 'Actual time' || label == 'Actual date') &&
      find.widgetWithText(LabelledInput, label).evaluate().isEmpty) {
    await tap(tester, 'Edit');
  }
  await tester.ensureVisible(field(label));
  await tester.enterText(field(label), value);
  await settle(tester);
}

Future<SubstanceItem> item(
  RecordStore store, {
  String unit = 'mg',
  String personId = meId,
  String name = 'Invented amber',
}) async => store.createItem(
  expectedPersonRevision: (await store.profileById(personId))!.revision,
  commandId: newCommandId(),
  personId: personId,
  name: name,
  form: 'liquid',
  unit: unit,
  type: 'Test',
);
Future<StoredStockContainer> container(
  RecordStore store,
  SubstanceItem item, {
  String label = 'Bottle A',
  String strength = '10',
  String? strengthLabel,
  String? opening = '2',
  String? threshold,
  bool refill = false,
}) async => store.createStockContainer(
  commandId: newCommandId(),
  personId: item.personId,
  expectedPersonRevision: (await store.profileById(item.personId))!.revision,
  expectedGeneration: store.generation,
  itemId: item.id,
  label: label,
  unit: 'ml',
  strength: LabelledStrength(
    ingredientId: item.id,
    label: strengthLabel ?? '$strength mg/ml',
    mgPerMl: ExactAmount.parseEntry(strength),
  ),
  opening: opening == null ? null : ExactAmount.parseEntry(opening),
  lowThreshold: threshold == null ? null : ExactAmount.parseEntry(threshold),
  refillEnabled: refill,
);
Future<void> select(WidgetTester tester, String id) async {
  final button = find.byKey(ValueKey('choose-$id'));
  await tester.ensureVisible(button);
  await tester.tap(button);
  await settle(tester);
}

void main() {
  appTest(
    'replacement requires fixed choice and history shows canonical actual with source provenance',
    (tester) async {
      final f = await launch(tester);
      final i = (await runIo(tester, () => item(f.store)))!;
      final old = (await runIo(tester, () => container(f.store, i)))!;
      final next = (await runIo(
        tester,
        () => container(f.store, i, label: 'Bottle B', strength: '20'),
      ))!;
      f.container.read(routerProvider).go('/record/${i.id}');
      await settle(tester);
      await enter(tester, 'Amount', '5');
      await select(tester, old.id);
      await select(tester, next.id);
      await tap(tester, 'Save');
      expect(find.text('Choose whether mg or ml stays fixed.'), findsOneWidget);
      expect(await runIo(tester, () => f.store.records()), isEmpty);
      await tap(tester, 'Keep ml');
      expect(find.text('This dose: 10 mg'), findsOneWidget);
      await tap(tester, 'Save');
      await waitForText(tester, 'Me: 10 mg');
      expect(find.text('Entered: 5 mg.'), findsWidgets);
      await runIo(tester, () async {
        final r = (await f.store.records()).single;
        expect(r.actualAmount, ExactAmount.parseEntry('10'));
        expect(r.originalEntry, '5');
        expect(
          (await f.store.stockContainerById(
            personId: meId,
            containerId: next.id,
          ))!.balance.value,
          ExactAmount.parseEntry('1.5'),
        );
        expect(
          (await f.store.stockContainerById(
            personId: meId,
            containerId: old.id,
          ))!.balance.value,
          ExactAmount.parseEntry('2'),
        );
      });
    },
  );
  appTest(
    'dose saves deficit and correction keeps physical consumption without another outflow',
    (tester) async {
      final f = await launch(tester);
      final i = (await runIo(tester, () => item(f.store, unit: 'ml')))!;
      final c = (await runIo(
        tester,
        () =>
            container(f.store, i, opening: '1', threshold: '0.5', refill: true),
      ))!;
      f.container.read(routerProvider).go('/record/${i.id}');
      await settle(tester);
      await enter(tester, 'Amount', '2');
      await select(tester, c.id);
      await tap(tester, 'Save');
      await waitForText(
        tester,
        'Stock mismatch. The dose is saved. Review the container separately.',
      );
      final r = (await runIo(tester, () => f.store.records()))!.single;
      f.container.read(routerProvider).go('/correct/${r.id}?person=$meId');
      await settle(tester);
      await tap(tester, 'Save');
      expect(
        find.text(
          'Choose whether the supply was consumed or the entry was a mistake.',
        ),
        findsOneWidget,
      );
      await tap(tester, 'Keep consumed');
      await tap(tester, 'Save');
      await waitForText(
        tester,
        'Stock mismatch. The dose is saved. Review the container separately.',
      );
      await runIo(tester, () async {
        expect(
          (await f.store.stockContainerById(
            personId: meId,
            containerId: c.id,
          ))!.balance.value,
          -ExactAmount.parseEntry('1'),
        );
        expect(
          (await f.store.stockMovements(
            personId: meId,
            containerId: c.id,
          )).where((m) => m.kind == StockMovementKind.actualUse).length,
          1,
        );
      });
      await tap(tester, 'Undo');
      expect(
        find.text(
          'The stock effect was already reviewed. Later detail changes keep that effect.',
        ),
        findsOneWidget,
      );
      expect(find.text('Reverse entry'), findsNothing);
      await tap(tester, 'Keep balance');
      await settle(tester);
      await runIo(tester, () async {
        expect(
          (await f.store.stockContainerById(
            personId: meId,
            containerId: c.id,
          ))!.balance.value,
          -ExactAmount.parseEntry('1'),
        );
      });
    },
  );
  appTest(
    'labelled strength can save without a container and repeating preview is approximate',
    (tester) async {
      final f = await launch(tester);
      final i = (await runIo(tester, () => item(f.store)))!;
      final c = (await runIo(
        tester,
        () => container(f.store, i, strength: '3'),
      ))!;
      f.container.read(routerProvider).go('/record/${i.id}');
      await settle(tester);
      await enter(tester, 'Amount', '1');
      await select(tester, c.id);
      expect(find.text('This dose: Approximately 0.333333 ml'), findsOneWidget);
      await tap(tester, 'No container');
      final toggle = find.bySemanticsLabel('Labelled strength');
      await tester.ensureVisible(toggle);
      await tester.tap(toggle);
      await settle(tester);
      await enter(tester, 'Labelled strength', '3 mg/ml original label');
      await enter(tester, 'Strength (mg/ml)', '3');
      await tap(tester, 'Save');
      await waitForText(tester, 'Labelled strength: 3 mg/ml original label');
      await runIo(tester, () async {
        final r = (await f.store.records()).single;
        expect(r.labelledStrength!.mgPerMl, ExactAmount.parseEntry('3'));
        expect(
          await f.store.stockUseForRecord(personId: meId, recordId: r.id),
          isNull,
        );
        expect(
          (await f.store.stockContainerById(
            personId: meId,
            containerId: c.id,
          ))!.balance.value,
          ExactAmount.parseEntry('2'),
        );
      });
    },
  );
  appTest(
    'container draft preserves owner, decimal input and strength through lock at large text',
    (tester) async {
      tester.view.physicalSize = const Size(375, 812);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final f = await launch(tester, auth: FakeAuth());
      final i = (await runIo(tester, () => item(f.store, unit: 'ml')))!;
      f.container.read(routerProvider).go('/stock/$meId/create?item=${i.id}');
      await settle(tester);
      await enter(tester, 'Container name', 'Long original vial name');
      await enter(tester, 'Labelled strength', 'Original unknown strength');
      final toggle = find.bySemanticsLabel('Known amount');
      await tester.ensureVisible(toggle);
      await tester.tap(toggle);
      await settle(tester);
      await enter(tester, 'Starting amount', '0,500000');
      await runIo(
        tester,
        () => f.container.read(appLockProvider.notifier).setEnabled(true),
      );
      f.container.read(appLockProvider.notifier).lock();
      await settle(tester);
      expect(find.text('Long original vial name'), findsNothing);
      await tap(tester, 'Unlock');
      f.container.read(routerProvider).go('/today');
      await settle(tester);
      f.container.read(routerProvider).go('/stock/$meId/create?item=${i.id}');
      await settle(tester);
      expect(
        tester.widget<TextField>(field('Container name')).controller!.text,
        'Long original vial name',
      );
      expect(
        tester.widget<TextField>(field('Starting amount')).controller!.text,
        '0,500000',
      );
      await tap(tester, 'Create');
      await waitForText(tester, 'Remaining: 0.5 ml');
      expect(tester.takeException(), isNull);
      await runIo(tester, () async {
        final saved = (await f.store.stockContainers(personId: meId)).single;
        expect(saved.personId, meId);
        expect(saved.strength.mgPerMl, isNull);
      });
    },
  );
  appTest(
    'threshold draft is durable and unknown stock remains visible after a low notice',
    (tester) async {
      final f = await launch(tester);
      final i = (await runIo(tester, () => item(f.store, unit: 'ml')))!;
      var c = (await runIo(
        tester,
        () => container(f.store, i, opening: '1', threshold: '2'),
      ))!;
      f.container.read(routerProvider).go('/today');
      await settle(tester);
      await waitForText(tester, 'Stock needs attention');
      await waitForText(tester, i.name);
      f.container
          .read(routerProvider)
          .go('/stock/$meId/adjust/${c.id}?notices=true');
      await settle(tester);
      await enter(tester, 'Low-stock threshold', '0.750000');
      f.container.read(routerProvider).go('/today');
      await settle(tester);
      f.container
          .read(routerProvider)
          .go('/stock/$meId/adjust/${c.id}?notices=true');
      await settle(tester);
      expect(
        tester.widget<TextField>(field('Low-stock threshold')).controller!.text,
        '0.750000',
      );
      await tap(tester, 'Save');
      await settle(tester);
      c = (await runIo(
        tester,
        () async => (await f.store.stockContainerById(
          personId: meId,
          containerId: c.id,
        ))!,
      ))!;
      await runIo(
        tester,
        () => f.store.addStockMovement(
          commandId: newCommandId(),
          personId: meId,
          expectedPersonRevision: 2,
          expectedGeneration: f.store.generation,
          containerId: c.id,
          expectedContainerRevision: c.revision,
          kind: StockMovementKind.reconciliation,
        ),
      );
      f.container.read(routerProvider).go('/today');
      await settle(tester);
      f.container.read(routerProvider).go('/stock/$meId');
      await settle(tester);
      await waitForText(
        tester,
        'Stock unknown. Measure the remaining amount to establish a balance.',
      );
      expect(find.text('Low stock'), findsNothing);
    },
  );
  appTest('measurement accepts zero and waste never becomes a dose', (
    tester,
  ) async {
    final f = await launch(tester);
    final i = (await runIo(tester, () => item(f.store, unit: 'ml')))!;
    final c = (await runIo(tester, () => container(f.store, i)))!;
    f.container.read(routerProvider).go('/stock/$meId/adjust/${c.id}');
    await settle(tester);
    await tap(tester, 'Measure');
    await enter(tester, 'Amount', '0');
    await enter(tester, 'Reason (optional)', 'Measured empty');
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    FocusManager.instance.primaryFocus?.unfocus();
    tester.testTextInput.hide();
    await tap(tester, 'Save');
    await waitForText(tester, 'Remaining: 0 ml');
    expect(await runIo(tester, () => f.store.records()), isEmpty);
    expect(
      (await runIo(
        tester,
        () => f.store.stockMovements(personId: meId, containerId: c.id),
      ))!.where((m) => m.reason != null).single.reason,
      'Measured empty',
    );
  });
  appTest(
    'opening threshold editor keeps exact settings until explicit Clear and stale edits cannot overwrite',
    (tester) async {
      final f = await launch(tester);
      final i = (await runIo(tester, () => item(f.store)))!;
      var c = (await runIo(
        tester,
        () => container(f.store, i, threshold: '0.75'),
      ))!;
      f.container
          .read(routerProvider)
          .go('/stock/$meId/adjust/${c.id}?notices=true');
      await settle(tester);
      await tap(tester, 'Save');
      await waitForText(tester, 'Low-stock threshold: 0.75 ml');
      c = (await runIo(
        tester,
        () async => (await f.store.stockContainerById(
          personId: meId,
          containerId: c.id,
        ))!,
      ))!;
      expect(c.lowThreshold, ExactAmount.parseEntry('0.75'));
      f.container
          .read(routerProvider)
          .go('/stock/$meId/adjust/${c.id}?notices=true');
      await settle(tester);
      await tap(tester, 'Clear');
      expect(
        find.text('Low-stock notices will be turned off when you save.'),
        findsOneWidget,
      );
      await tap(tester, 'Save');
      await settle(tester);
      c = (await runIo(
        tester,
        () async => (await f.store.stockContainerById(
          personId: meId,
          containerId: c.id,
        ))!,
      ))!;
      expect(c.lowThreshold, isNull);
      f.container
          .read(routerProvider)
          .go('/stock/$meId/adjust/${c.id}?notices=true');
      await settle(tester);
      await enter(tester, 'Low-stock threshold', '0.25');
      await runIo(
        tester,
        () => f.store.configureStockNotices(
          commandId: newCommandId(),
          personId: meId,
          expectedPersonRevision: 2,
          expectedGeneration: f.store.generation,
          containerId: c.id,
          expectedContainerRevision: c.revision,
          lowThreshold: ExactAmount.parseEntry('0.5'),
          refillEnabled: false,
        ),
      );
      await settle(tester);
      final save = tester.widget<VitalButton>(
        find.widgetWithText(VitalButton, 'Save'),
      );
      expect(save.onPressed, isNull);
      expect(
        tester.widget<TextField>(field('Low-stock threshold')).controller!.text,
        '0.25',
      );
      expect(
        (await runIo(
          tester,
          () => f.store.stockContainerById(personId: meId, containerId: c.id),
        ))!.lowThreshold,
        ExactAmount.parseEntry('0.5'),
      );
    },
  );

  appTest(
    'later correction after a reversed stock entry keeps the current balance',
    (tester) async {
      final f = await launch(tester);
      final i = (await runIo(tester, () => item(f.store, unit: 'ml')))!;
      final c = (await runIo(tester, () => container(f.store, i)))!;
      final r = (await runIo(tester, () async {
        final actual = await f.store.record(
          commandId: newCommandId(),
          personId: meId,
          expectedPersonRevision: 2,
          itemId: i.id,
          amount: '1',
          actualAt: DateTime.now().toUtc(),
          stockUse: StockUseInput(
            expectedGeneration: f.store.generation,
            containerId: c.id,
            expectedContainerRevision: c.revision,
            entered: EnteredStockAmount('1', 'ml'),
          ),
        );
        return f.store.correct(
          commandId: newCommandId(),
          recordId: actual.id,
          personId: meId,
          expectedPersonRevision: 2,
          expectedRevision: actual.revision,
          amount: null,
          actualAt: actual.actualAt,
          stockCorrection: PhysicalCorrection.reverseRecordedEffect,
        );
      }))!;
      f.container.read(routerProvider).go('/correct/${r.id}?person=$meId');
      await settle(tester);
      expect(find.text('Reverse entry'), findsNothing);
      expect(
        find.text('The supply was used or lost. Keep its stock effect.'),
        findsNothing,
      );
      await tap(tester, 'Keep balance');
      await tap(tester, 'Save');
      await waitForText(tester, 'Me: 1 ml');
      expect(
        (await runIo(
          tester,
          () => f.store.stockContainerById(personId: meId, containerId: c.id),
        ))!.balance.value,
        ExactAmount.parseEntry('2'),
      );
    },
  );

  appTest(
    'same-strength container switch records without a fixed-quantity prompt',
    (tester) async {
      tester.view.physicalSize = const Size(812, 375);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final f = await launch(tester);
      final i = (await runIo(tester, () => item(f.store)))!;
      final old = (await runIo(tester, () => container(f.store, i)))!;
      final next = (await runIo(
        tester,
        () => container(
          f.store,
          i,
          label: 'Bottle B',
          strengthLabel: 'Different brand label, 10 mg/ml',
        ),
      ))!;
      f.container.read(routerProvider).go('/record/${i.id}');
      await settle(tester);
      await enter(tester, 'Amount', '1');
      await select(tester, old.id);
      await select(tester, next.id);
      expect(find.text('Strength changed'), findsNothing);
      expect(find.text('Keep mg'), findsNothing);
      await tap(tester, 'Save');
      await waitForText(tester, 'Me: 1 mg');
      final r = (await runIo(tester, () => f.store.records()))!.single;
      expect(r.replacement, isNull);
      expect(
        (await runIo(
          tester,
          () => f.store.stockContainerById(personId: meId, containerId: old.id),
        ))!.balance.value,
        ExactAmount.parseEntry('2'),
      );
      expect(
        (await runIo(
          tester,
          () =>
              f.store.stockContainerById(personId: meId, containerId: next.id),
        ))!.balance.value,
        ExactAmount.parseEntry('1.9'),
      );
    },
  );
  appTest(
    'planned Taken consumes selected source once and Undo reviews its physical effect',
    (tester) async {
      final f = await launch(tester);
      final i = (await runIo(tester, () => item(f.store)))!;
      final c = (await runIo(
        tester,
        () => container(f.store, i, strength: '3'),
      ))!;
      final saved = (await runIo(
        tester,
        () => f.store.saveDailyPlan(
          commandId: newCommandId(),
          expectedPersonRevision: 2,
          expectedGeneration: f.store.generation,
          plan: DailyPlanVersion(
            personId: meId,
            planId: 'stock-plan',
            itemId: i.id,
            versionId: 'stock-plan-v1',
            start: CivilDate.fromDateTime(DateTime.now()),
            timing: DailyCount(
              1,
              PlannedAmount(
                quantity: ExactQuantity.parse('1.000'),
                enteredText: '1.000',
                unit: 'mg',
              ),
            ),
            zoneBasis: const FollowingLocal(),
          ),
        ),
      ))!;
      f.container.read(routerProvider).go('/today');
      await settle(tester);
      await tap(tester, 'Details');
      await tap(tester, 'Source');
      await select(tester, c.id);
      final hero = find.byWidgetPredicate(
        (w) =>
            w is DailyRowCard &&
            w.presentation == DailyCardPresentation.timeline,
      );
      final taken = find.descendant(of: hero, matching: find.text('Taken'));
      await tester.ensureVisible(taken);
      await settle(tester);
      await tester.tap(taken);
      await settle(tester);
      await waitForText(tester, '1 recorded, 0 skipped, 1 planned');
      expect(
        (await runIo(
          tester,
          () => f.store.stockContainerById(personId: meId, containerId: c.id),
        ))!.balance.value,
        ExactAmount(BigInt.from(5), BigInt.from(3)),
      );
      final undo = find
          .descendant(
            of: find.byType(DailyRowCard),
            matching: find.text('Undo'),
          )
          .first;
      await tester.ensureVisible(undo);
      await tester.tap(undo);
      await settle(tester);
      expect(find.text('Bottle A'), findsWidgets);
      await tap(tester, 'Reverse entry');
      await waitForText(tester, '0 recorded, 0 skipped, 1 planned');
      expect(
        (await runIo(
          tester,
          () => f.store.stockContainerById(personId: meId, containerId: c.id),
        ))!.balance.value,
        ExactAmount.parseEntry('2'),
      );
      final plans = (await runIo(
        tester,
        () => f.store.dailyPlans(itemId: i.id),
      ))!;
      expect(plans.single.revision, saved.revision);
      expect(
        (plans.single.plan.timing as DailyCount).amount.enteredText,
        '1.000',
      );
    },
  );
  appTest(
    'mg item records entered ml with exact strength equivalent and keeps actual ml on correction',
    (tester) async {
      final f = await launch(tester);
      final i = (await runIo(tester, () => item(f.store)))!;
      final c = (await runIo(
        tester,
        () => container(f.store, i, strength: '3'),
      ))!;
      f.container.read(routerProvider).go('/record/${i.id}');
      await settle(tester);
      await enter(tester, 'Amount', '0.500000');
      await select(tester, c.id);
      await tap(tester, 'ml');
      expect(find.text('This dose: 1.5 mg'), findsOneWidget);
      await tap(tester, 'Save');
      await waitForText(tester, 'Me: 0.500000 ml');
      expect(find.text('Entered: 0.500000 ml.'), findsOneWidget);
      expect(find.text('This dose: 1.5 mg'), findsWidgets);
      final r = (await runIo(tester, () => f.store.records()))!.single;
      expect(r.actualUnit, 'ml');
      expect(r.originalUnit, 'ml');
      expect(r.actualAmount, ExactAmount.parseEntry('0.5'));
      f.container.read(routerProvider).go('/correct/${r.id}?person=$meId');
      await settle(tester);
      expect(find.text('ml'), findsOneWidget);
      await enter(tester, 'Amount', '0.25');
      expect(
        (await runIo(
          tester,
          () => f.store.drafts(),
        ))!.single.fields['amountEdited'],
        'true',
      );
      f.container.read(routerProvider).go('/today');
      await settle(tester);
      f.container.read(routerProvider).go('/correct/${r.id}?person=$meId');
      await settle(tester);
      expect(
        tester.widget<TextField>(field('Amount')).controller!.text,
        '0.25',
      );
      await tap(tester, 'Keep consumed');
      await tap(tester, 'Save');
      await waitForText(tester, 'Me: 0.25 ml');
      final corrected = (await runIo(
        tester,
        () => f.store.recordById(r.id, personId: meId),
      ))!;
      expect(corrected.actualUnit, 'ml');
      expect(
        (await runIo(
          tester,
          () => f.store.stockContainerById(personId: meId, containerId: c.id),
        ))!.balance.value,
        ExactAmount.parseEntry('1.5'),
      );
    },
  );
}
