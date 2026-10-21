import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' show TextField;
import 'package:true_grit_vital/app/vital_app.dart' show routerProvider;
import 'package:true_grit_vital/data/record_store.dart';
import 'package:true_grit_vital/domain/stock/exact_amount.dart' as stock;
import 'package:true_grit_vital/features/recording/record_pages.dart'
    show LabelledInput;

import 'vital_app_test.dart' show appTest, launch, runIo, settle, tap;

Finder _field(String label) => find.descendant(
  of: find.widgetWithText(LabelledInput, label),
  matching: find.byType(TextField),
);

String _entered(WidgetTester tester, String label) =>
    tester.widget<TextField>(_field(label)).controller?.text ?? '';

Future<List<OrdinaryDraft>> _adjustmentDrafts(
  WidgetTester tester,
  RecordStore store,
) async => (await runIo(
  tester,
  store.drafts,
))!.where((d) => d.kind == DraftKind.stockAdjustment).toList();

void main() {
  appTest(
    'an in-place surface switch rebuilds each surface with its own draft',
    (tester) async {
      final f = await launch(tester);
      final me = (await runIo(tester, () => f.store.profileById(meId)))!;
      final item = (await runIo(
        tester,
        () => f.store.createItem(
          expectedPersonRevision: me.revision,
          commandId: newCommandId(),
          personId: meId,
          name: 'Surface switch item',
          form: 'liquid',
          unit: 'ml',
          type: 'Test',
        ),
      ))!;
      final container = (await runIo(
        tester,
        () => f.store.createStockContainer(
          commandId: newCommandId(),
          personId: meId,
          expectedPersonRevision: me.revision,
          expectedGeneration: f.store.generation,
          itemId: item.id,
          label: 'Switch vial',
          unit: 'ml',
          strength: LabelledStrength(
            ingredientId: item.id,
            label: '10 mg/ml',
            mgPerMl: stock.ExactAmount.parseEntry('10'),
          ),
          opening: stock.ExactAmount.parseEntry('2'),
        ),
      ))!;

      final noticesPath = '/stock/$meId/adjust/${container.id}?notices=true';
      final quantityPath = '/stock/$meId/adjust/${container.id}';

      // Start on the notices surface and save a threshold draft.
      f.container.read(routerProvider).go(noticesPath);
      await settle(tester);
      expect(find.text('Stock notices'), findsOneWidget);
      await tester.enterText(_field('Low-stock threshold'), '0.25');
      await settle(tester);

      // In-place switch to the quantity surface on the same route pattern.
      f.container.read(routerProvider).go(quantityPath);
      await settle(tester);
      expect(find.text('Adjust stock'), findsOneWidget);
      expect(find.text('Stock notices'), findsNothing);
      await tap(tester, 'Restock');
      await tester.enterText(_field('Amount'), '4');
      await tester.enterText(_field('Reason (optional)'), 'Delivery');
      await settle(tester);

      // Back in place to the notices surface; the threshold draft restores.
      f.container.read(routerProvider).go(noticesPath);
      await settle(tester);
      expect(find.text('Stock notices'), findsOneWidget);
      expect(find.text('Restock'), findsNothing);
      expect(_entered(tester, 'Low-stock threshold'), '0.25');

      // Forward again: the movement draft restores its own fields, not the
      // threshold amount.
      f.container.read(routerProvider).go(quantityPath);
      await settle(tester);
      await tester.ensureVisible(_field('Amount'));
      expect(_entered(tester, 'Amount'), '4');
      expect(_entered(tester, 'Reason (optional)'), 'Delivery');

      // Both surfaces kept distinct durable drafts on the raw container.
      final drafts = await _adjustmentDrafts(tester, f.store);
      expect(drafts.length, 2);
      final threshold = drafts.singleWhere(
        (d) => d.fields['kind'] == 'notices',
      );
      final movement = drafts.singleWhere((d) => d.fields['kind'] == 'restock');
      expect(threshold.id, 'stockAdjustment:$meId:${container.id}:notices');
      expect(movement.id, 'stockAdjustment:$meId:${container.id}');
      expect(movement.targetId, container.id);
      expect(threshold.fields['amount'], '0.25');
      expect(movement.fields['amount'], '4');
    },
  );

  appTest('a foreign command at the notices draft key conflicts truthfully', (
    tester,
  ) async {
    final f = await launch(tester);
    final me = (await runIo(tester, () => f.store.profileById(meId)))!;
    final item = (await runIo(
      tester,
      () => f.store.createItem(
        expectedPersonRevision: me.revision,
        commandId: newCommandId(),
        personId: meId,
        name: 'Foreign command item',
        form: 'liquid',
        unit: 'ml',
        type: 'Test',
      ),
    ))!;
    final container = (await runIo(
      tester,
      () => f.store.createStockContainer(
        commandId: newCommandId(),
        personId: meId,
        expectedPersonRevision: me.revision,
        expectedGeneration: f.store.generation,
        itemId: item.id,
        label: 'Conflict vial',
        unit: 'ml',
        strength: LabelledStrength(
          ingredientId: item.id,
          label: '10 mg/ml',
          mgPerMl: stock.ExactAmount.parseEntry('10'),
        ),
        opening: stock.ExactAmount.parseEntry('2'),
      ),
    ))!;
    // A movement command is stored at the notices surface's draft key.
    await runIo(
      tester,
      () => f.store.saveDraft(
        OrdinaryDraft(
          id: 'stockAdjustment:$meId:${container.id}:notices',
          generation: f.store.generation,
          operationId: 'op-foreign',
          kind: DraftKind.stockAdjustment,
          personId: meId,
          personRevision: me.revision,
          targetId: container.id,
          targetRevision: container.revision,
          fields: const {
            'kind': 'restock',
            'amount': '3',
            'unknown': 'false',
            'reason': '',
            'clearThreshold': 'false',
          },
        ),
      ),
    );
    f.container
        .read(routerProvider)
        .go('/stock/$meId/adjust/${container.id}?notices=true');
    await settle(tester);
    // The route still shows the notices surface and reports the conflict
    // instead of restoring or rewriting the foreign command.
    expect(find.text('Stock notices'), findsOneWidget);
    expect(find.textContaining('This record has changed'), findsOneWidget);
    expect(_entered(tester, 'Low-stock threshold'), isEmpty);
    // The stored foreign draft is untouched: both commands stay whole.
    final stored = await _adjustmentDrafts(tester, f.store);
    expect(stored.single.fields['kind'], 'restock');
    expect(stored.single.operationId, 'op-foreign');
    expect(stored.single.fields['amount'], '3');
  });
}
