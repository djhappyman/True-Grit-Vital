import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:true_grit_vital/app/reminders.dart';

import 'reminders/reminder_ui_test.dart' show UiGateway;

import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:true_grit_vital/app/vital_app.dart';
import 'package:true_grit_vital/data/record_store.dart';
import 'package:true_grit_vital/features/recording/record_pages.dart';

import 'product_ui_test.dart' show product, tapFinder;
import 'stock_ui_test.dart' show enter;
import 'vital_app_test.dart'
    show appTest, launch, runIo, settle, tap, waitForText;

Future<void> addSource(WidgetTester tester, String id) async {
  await tap(tester, 'Add');
  await tapFinder(tester, find.byKey(ValueKey('combine-add-$id')));
}

Future<void> amountAt(WidgetTester tester, int index, String value) async {
  final field = find.descendant(
    of: find.widgetWithText(LabelledInput, 'Amount').at(index),
    matching: find.byType(TextField),
  );
  await tester.ensureVisible(field);
  await tester.enterText(field, value);
  await settle(tester);
}

void main() {
  appTest(
    'combined review cancels without writes and atomically saves product plus separate source',
    (tester) async {
      final f = await launch(tester);
      final blend = (await runIo(tester, () => product(f.store)))!;
      final tablet = (await runIo(
        tester,
        () => f.store.createItem(
          commandId: newCommandId(),
          expectedPersonRevision: 2,
          name: 'Invented separate tablet',
          form: 'Tablet',
          unit: 'count',
          type: 'Test',
        ),
      ))!;
      f.container.read(routerProvider).go('/combined/$meId');
      await settle(tester);
      await addSource(tester, blend.id);
      await addSource(tester, tablet.id);
      await amountAt(tester, 0, '2');
      await amountAt(tester, 1, '1');
      await tap(tester, 'Review');
      expect(find.text('Review entry'), findsOneWidget);
      expect(find.text('Amount: 6 mg.'), findsOneWidget);
      expect(find.text('Amount unknown.'), findsOneWidget);
      await tap(tester, 'Cancel');
      expect(await runIo(tester, f.store.records), isEmpty);
      await tap(tester, 'Review');
      await tap(tester, 'Save');
      await waitForText(
        tester,
        'Correct or undo every source together. Each source retains its own history.',
      );
      final records = (await runIo(tester, f.store.records))!;
      expect(records.length, 2);
      expect(records.map((r) => r.combinedActionId).toSet().length, 1);
      expect(records.first.personId, meId);
      expect(tester.takeException(), isNull);
    },
  );
  appTest('raw combined draft reopens malformed quantities without guessing', (
    tester,
  ) async {
    final f = await launch(tester);
    final item = (await runIo(tester, () => product(f.store)))!;
    f.container.read(routerProvider).go('/combined/$meId');
    await settle(tester);
    await addSource(tester, item.id);
    await addSource(tester, item.id);
    await amountAt(tester, 0, 'not an amount');
    await amountAt(tester, 1, '1,25');
    await settle(tester);
    final draft = (await runIo(tester, f.store.drafts))!.single;
    expect(draft.kind, DraftKind.combinedDose);
    expect(draft.fields['components'], contains('not an amount'));
    f.container.read(routerProvider).go('/today');
    await settle(tester);
    f.container.read(routerProvider).go(draft.route);
    await settle(tester);
    expect(find.text('not an amount'), findsOneWidget);
    expect(find.text('1,25'), findsOneWidget);
    expect(await runIo(tester, f.store.records), isEmpty);
    expect(tester.takeException(), isNull);
  });
  appTest(
    'combined retry resolves a lost reply once using the frozen command',
    (tester) async {
      var calls = 0;
      final f = await launch(
        tester,
        combinedWriter: (store, command) async {
          calls++;
          final result = await store.recordCombined(command);
          if (calls == 1) throw StateError('synthetic lost reply');
          return result;
        },
      );
      final item = (await runIo(tester, () => product(f.store)))!;
      f.container.read(routerProvider).go('/combined/$meId');
      await settle(tester);
      await addSource(tester, item.id);
      await addSource(tester, item.id);
      await amountAt(tester, 0, '1');
      await amountAt(tester, 1, '2');
      await tap(tester, 'Review');
      await tap(tester, 'Save');
      await waitForText(tester, 'Retry');
      expect((await runIo(tester, f.store.records))!.length, 2);
      await tap(tester, 'Retry');
      await waitForText(
        tester,
        'Correct or undo every source together. Each source retains its own history.',
      );
      expect((await runIo(tester, f.store.records))!.length, 2);
      expect(calls, 1);
      expect(tester.takeException(), isNull);
    },
  );
  appTest(
    'combined owner stays fixed through scope changes at narrow and large layouts',
    (tester) async {
      final f = await launch(tester);
      final adult = (await runIo(
        tester,
        () => f.store.createProfile(
          commandId: newCommandId(),
          name: 'Same complete adult name',
          adultConfirmed: true,
        ),
      ))!;
      final item = (await runIo(
        tester,
        () => f.store.createItem(
          commandId: newCommandId(),
          personId: adult.id,
          expectedPersonRevision: adult.revision,
          name:
              'Complete unusually long original source name with full identity',
          form: 'Tablet',
          unit: 'count',
          type: 'Test',
        ),
      ))!;
      await tester.binding.setSurfaceSize(const Size(375, 812));
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(() async {
        await tester.binding.setSurfaceSize(null);
        tester.platformDispatcher.clearTextScaleFactorTestValue();
      });
      f.container.read(routerProvider).go('/combined/${adult.id}');
      await settle(tester);
      await addSource(tester, item.id);
      await addSource(tester, item.id);
      await amountAt(tester, 0, '1');
      await amountAt(tester, 1, '2');
      await runIo(
        tester,
        () => f.store.saveBrowsingScope(const FeedScope.me()),
      );
      await settle(tester);
      expect(find.text('Person: Same complete adult name'), findsOneWidget);
      for (final size in [
        const Size(812, 375),
        const Size(1280, 800),
        const Size(375, 812),
      ]) {
        await tester.binding.setSurfaceSize(size);
        await settle(tester);
        expect(tester.takeException(), isNull);
      }
      await tap(tester, 'Review');
      await tap(tester, 'Save');
      await waitForText(tester, 'Same complete adult name: 1 count');
      expect(find.text('Same complete adult name: 2 count'), findsOneWidget);
      final records = (await runIo(
        tester,
        () => f.store.records(personId: adult.id),
      ))!;
      expect(records.length, 2);
      expect(records.every((r) => r.personId == adult.id), true);
    },
  );

  appTest(
    'shared physical source reviews cumulative outflow and Undo keeps all consumption',
    (tester) async {
      final f = await launch(tester);
      final item = (await runIo(tester, () => product(f.store)))!;
      final label = (await runIo(
        tester,
        () => f.store.productLabel(personId: meId, itemId: item.id),
      ))!;
      final container = (await runIo(
        tester,
        () => f.store.createStockContainer(
          commandId: newCommandId(),
          expectedGeneration: f.store.generation,
          personId: meId,
          expectedPersonRevision: 2,
          itemId: item.id,
          label: 'Complete shared physical bottle',
          unit: 'ml',
          strength: LabelledStrength(ingredientId: item.id, label: item.name),
          productLabel: label,
          opening: ExactAmount.parseEntry('10'),
        ),
      ))!;
      f.container.read(routerProvider).go('/combined/$meId');
      await settle(tester);
      await addSource(tester, item.id);
      await addSource(tester, item.id);
      await amountAt(tester, 0, '1');
      await amountAt(tester, 1, '2');
      for (var i = 0; i < 2; i++) {
        await tapFinder(tester, find.byKey(ValueKey('combined-stock-$i')));
        await tapFinder(
          tester,
          find.byKey(ValueKey('choose-${container.id}')).at(i),
        );
      }
      await tap(tester, 'Review');
      expect(
        find.text('Total from Complete shared physical bottle: 3 ml.'),
        findsOneWidget,
      );
      expect(find.text('Remaining: 7 ml.'), findsOneWidget);
      await tap(tester, 'Save');
      await waitForText(
        tester,
        'Correct or undo every source together. Each source retains its own history.',
      );
      final records = (await runIo(tester, f.store.records))!;
      expect(
        (await runIo(
          tester,
          () => f.store.stockContainerById(
            personId: meId,
            containerId: container.id,
          ),
        ))!.balance.value,
        ExactAmount.parseEntry('7'),
      );
      f.container
          .read(routerProvider)
          .go(
            '/combined/$meId/edit/${records.first.combinedActionId}?undo=true',
          );
      await settle(tester);
      for (var i = 0; i < 2; i++) {
        await tapFinder(tester, find.text('Keep').at(i));
      }
      await tap(tester, 'Review');
      await tap(tester, 'Save');
      await waitForText(tester, 'Voided');
      expect(
        (await runIo(tester, f.store.records))!.every((r) => r.isVoided),
        true,
      );
      expect(
        (await runIo(
          tester,
          () => f.store.stockContainerById(
            personId: meId,
            containerId: container.id,
          ),
        ))!.balance.value,
        ExactAmount.parseEntry('7'),
      );
      expect(tester.takeException(), isNull);
    },
  );

  appTest(
    'optional single site and site-only correction preserve dose and stock history',
    (tester) async {
      final f = await launch(tester);
      final item = (await runIo(tester, () => product(f.store)))!;
      f.container.read(routerProvider).go('/record/${item.id}');
      await settle(tester);
      expect(
        find.widgetWithText(LabelledInput, 'Site (optional)'),
        findsNothing,
      );
      await enter(tester, 'Amount', '1');
      await tap(tester, 'Site');
      await enter(tester, 'Site (optional)', '  Exact personal site label  ');
      await tap(tester, 'Save');
      await waitForText(tester, 'Site:   Exact personal site label  .');
      final record = (await runIo(tester, f.store.records))!.single;
      f.container.read(routerProvider).go('/site/$meId/${record.id}');
      await settle(tester);
      await enter(tester, 'Site (optional)', 'Corrected personal site');
      await tap(tester, 'Save');
      await waitForText(tester, 'Site: Corrected personal site.');
      expect(
        (await runIo(tester, () => f.store.history(record.id)))!.length,
        1,
      );
      expect(
        (await runIo(
          tester,
          () => f.store.recordById(record.id, personId: meId),
        ))!.revision,
        1,
      );
      expect(
        (await runIo(tester, () => f.store.siteHistory(personId: meId)))!,
        containsAll([
          '  Exact personal site label  ',
          'Corrected personal site',
        ]),
      );
      expect(tester.takeException(), isNull);
    },
  );
  appTest(
    'containerless correction and reopened Undo retain one complete group',
    (tester) async {
      final f = await launch(tester);
      final item = (await runIo(tester, () => product(f.store)))!;
      final label = (await runIo(
        tester,
        () => f.store.productLabel(personId: meId, itemId: item.id),
      ))!;
      final group = (await runIo(
        tester,
        () => f.store.recordCombined(
          CombinedUseCommand(
            commandId: newCommandId(),
            expectedGeneration: f.store.generation,
            personId: meId,
            expectedPersonRevision: 2,
            actualAt: DateTime.now().toUtc(),
            components: [
              for (var i = 0; i < 2; i++)
                CombinedUseComponent(
                  itemId: item.id,
                  expectedItemRevision: item.revision,
                  enteredAmount: '1',
                  productUse: ProductUseInput(
                    expectedGeneration: f.store.generation,
                    label: label,
                    enteredVolume: EnteredStockAmount('1', 'ml'),
                  ),
                ),
            ],
          ),
        ),
      ))!;
      f.container
          .read(routerProvider)
          .go('/combined/$meId/edit/${group.actionId}');
      await settle(tester);
      expect(find.text('Keep'), findsNothing);
      expect(find.text('Restore'), findsNothing);
      await amountAt(tester, 0, '2');
      await tap(tester, 'Review');
      await tap(tester, 'Save');
      await waitForText(
        tester,
        'Correct or undo every source together. Each source retains its own history.',
      );
      expect(
        (await runIo(tester, f.store.records))!.every((r) => r.revision == 2),
        true,
      );
      f.container
          .read(routerProvider)
          .go('/combined/$meId/edit/${group.actionId}?undo=true');
      await settle(tester);
      await tap(tester, 'Review');
      final draft = (await runIo(tester, f.store.drafts))!.single;
      expect(draft.route, contains('?undo=true'));
      f.container.read(routerProvider).go('/today');
      await settle(tester);
      await tap(tester, 'Resume');
      expect(
        find.text(
          'Undo marks every source as voided. Choose the physical stock consequence for each source.',
        ),
        findsOneWidget,
      );
      await tap(tester, 'Save');
      await waitForText(tester, 'Voided');
      expect(
        (await runIo(
          tester,
          f.store.records,
        ))!.every((r) => r.isVoided && r.revision == 3),
        true,
      );
      expect(tester.takeException(), isNull);
    },
  );
  appTest(
    'planned combined source retains its identity while Extra and scope stay independent',
    (tester) async {
      CombinedUseCommand? submitted;
      final f = await launch(
        tester,
        combinedWriter: (store, command) async {
          submitted = command;
          return store.recordCombined(command);
        },
      );
      final gateway = UiGateway();
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: f.container,
          child: ProviderScope(
            overrides: [reminderGatewayProvider.overrideWithValue(gateway)],
            child: const VitalApp(),
          ),
        ),
      );
      await settle(tester);
      final item = (await runIo(
        tester,
        () => f.store.createItem(
          commandId: newCommandId(),
          expectedPersonRevision: 2,
          name: 'Complete planned physical source',
          form: 'Liquid',
          unit: 'ml',
          type: 'Test',
        ),
      ))!;
      final c = (await runIo(
        tester,
        () => f.store.createStockContainer(
          commandId: newCommandId(),
          personId: meId,
          expectedPersonRevision: 2,
          expectedGeneration: f.store.generation,
          itemId: item.id,
          label: 'Planned shared physical bottle',
          unit: 'ml',
          strength: LabelledStrength(ingredientId: item.id, label: item.name),
          opening: ExactAmount.parseEntry('10'),
        ),
      ))!;
      final now = DateTime.now().toUtc();
      final date = CivilDate.fromDateTime(now.toLocal());
      final plan = DailyPlanVersion(
        personId: meId,
        planId: newCommandId(),
        itemId: item.id,
        versionId: newCommandId(),
        start: date.addDays(-1),
        zoneBasis: FixedHome('Europe/London'),
        timing: ElapsedInterval(
          segmentId: newCommandId(),
          duration: ExactElapsed.parseHours('6'),
          mode: IntervalMode.qualifyingActual,
          amount: PlannedAmount(quantity: ExactQuantity.parse('1'), unit: 'ml'),
          reminderEnabled: true,
        ),
      );
      final saved = (await runIo(
        tester,
        () => f.store.saveDailyPlan(
          commandId: newCommandId(),
          plan: plan,
          expectedPersonRevision: 2,
          expectedGeneration: f.store.generation,
          intervalClockSample: gateway.clock,
        ),
      ))!;
      final seed = (await runIo(
        tester,
        () => f.store.record(
          commandId: newCommandId(),
          itemId: item.id,
          amount: '1',
          actualAt: now.subtract(const Duration(hours: 7)),
          expectedPersonRevision: 2,
        ),
      ))!;
      final initial = (await runIo(
        tester,
        () => f.store.previewIntervalChange(
          plan: saved,
          recordId: seed.id,
          expectedRecordRevision: 1,
          qualifies: true,
          now: now,
          observedZone: 'Europe/London',
          intervalClockSample: gateway.clock,
        ),
      ))!;
      await runIo(
        tester,
        () =>
            f.store.qualifyInterval(commandId: newCommandId(), review: initial),
      );
      final intended = (await runIo(
        tester,
        () => f.store.todayDailyRows(
          scope: const FeedScope.me(),
          now: now,
          observedZone: 'Europe/London',
        ),
      ))!.rows.single;
      f.container.read(routerProvider).go('/combined/$meId');
      await settle(tester);
      await addSource(tester, item.id);
      await addSource(tester, item.id);
      await amountAt(tester, 0, '1');
      await amountAt(tester, 1, '2');
      for (var i = 0; i < 2; i++) {
        await tapFinder(tester, find.byKey(ValueKey('combined-stock-$i')));
        await tapFinder(tester, find.byKey(ValueKey('choose-${c.id}')).at(i));
      }
      final firstSource = find.byKey(const ValueKey('combined-source-0'));
      await tapFinder(
        tester,
        find.descendant(of: firstSource, matching: find.text('Schedule')),
      );
      await tapFinder(
        tester,
        find.descendant(of: firstSource, matching: find.text('Choose')),
      );
      await runIo(
        tester,
        () => f.store.saveBrowsingScope(const FeedScope.everyone()),
      );
      await settle(tester);
      expect(find.text('Person: Me'), findsOneWidget);
      await tap(tester, 'Review');
      final draft = (await runIo(tester, f.store.drafts))!.single;
      final frozen = decodeCombinedUse(
        jsonDecode(draft.fields['frozen']!) as Map<String, dynamic>,
      );
      expect(frozen.personId, meId);
      expect(frozen.expectedPersonRevision, 2);
      expect(
        frozen.components.first.intendedRow!.expectation.identity,
        intended.expectation.identity,
      );
      expect(frozen.components.last.intendedRow, isNull);
      expect(frozen.components.map((e) => e.intervalClockSample!.bootId), [
        gateway.clock.bootId,
        gateway.clock.bootId,
      ]);
      final frozenJson = jsonEncode(encodeCombinedUse(frozen));
      gateway.clock = ReminderClockSample(
        utcMilliseconds: gateway.clock.utcMilliseconds + 60000,
        elapsedMilliseconds: gateway.clock.elapsedMilliseconds + 60000,
        bootId: gateway.clock.bootId,
      );
      await tap(tester, 'Save');
      await waitForText(
        tester,
        'Correct or undo every source together. Each source retains its own history.',
      );
      expect(jsonEncode(encodeCombinedUse(submitted!)), frozenJson);
      final records = (await runIo(tester, f.store.records))!;
      final grouped = records.where((r) => r.combinedActionId != null).toList();
      expect(records.length, 3);
      expect(grouped.length, 2);
      expect(grouped.every((r) => r.personId == meId), true);
      final sources = (await runIo(
        tester,
        () => f.store.intervalSources(planId: plan.planId, personId: meId),
      ))!;
      expect(sources.where((r) => r.qualifies).length, 2);
      expect(
        sources.any(
          (r) =>
              r.actualId ==
              grouped.singleWhere((r) => r.enteredAmount == '2').id,
        ),
        false,
      );
      final movements = (await runIo(
        tester,
        () => f.store.stockMovements(personId: meId, containerId: c.id),
      ))!;
      expect(
        movements.where((m) => m.kind == StockMovementKind.actualUse).length,
        2,
      );
      expect(
        (await runIo(
          tester,
          () => f.store.stockContainerById(personId: meId, containerId: c.id),
        ))!.balance.value,
        ExactAmount.parseEntry('7'),
      );
      expect(tester.takeException(), isNull);
    },
  );
}
