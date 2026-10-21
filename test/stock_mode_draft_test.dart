import 'package:flutter_test/flutter_test.dart';
import 'package:true_grit_vital/ui/vital_ui.dart' show VitalTaskFrame;
import 'package:shadcn_flutter/shadcn_flutter.dart' show TextField;
import 'package:true_grit_vital/app/vital_app.dart' show routerProvider;
import 'package:true_grit_vital/data/record_store.dart';
import 'package:true_grit_vital/domain/stock/exact_amount.dart' as stock;
import 'package:true_grit_vital/features/recording/record_pages.dart'
    show LabelledInput;

import 'vital_app_test.dart'
    show appTest, launch, runIo, settle, tap, waitForText;

Finder _field(String label) => find.descendant(
  of: find.widgetWithText(LabelledInput, label),
  matching: find.byType(TextField),
);

Future<void> _enter(WidgetTester tester, String label, String value) async {
  await tester.ensureVisible(_field(label));
  await tester.enterText(_field(label), value);
  await settle(tester);
}

Future<SubstanceItem?> _item(RecordStore store) async => store.createItem(
  expectedPersonRevision: (await store.profileById(meId))!.revision,
  commandId: newCommandId(),
  personId: meId,
  name: 'Draft mode amber',
  form: 'liquid',
  unit: 'ml',
  type: 'Test',
);

Future<StoredStockContainer> _container(
  RecordStore store,
  SubstanceItem item,
) async => store.createStockContainer(
  commandId: newCommandId(),
  personId: item.personId,
  expectedPersonRevision: (await store.profileById(item.personId))!.revision,
  expectedGeneration: store.generation,
  itemId: item.id,
  label: 'Mode draft bottle',
  unit: 'ml',
  strength: LabelledStrength(
    ingredientId: item.id,
    label: '10 mg/ml',
    mgPerMl: stock.ExactAmount.parseEntry('10'),
  ),
  opening: stock.ExactAmount.parseEntry('2'),
);

Future<List<OrdinaryDraft>> _adjustmentDrafts(
  WidgetTester tester,
  RecordStore store,
) async => (await runIo(
  tester,
  () => store.drafts(),
))!.where((d) => d.kind == DraftKind.stockAdjustment).toList();

Future<StoredStockContainer> _stored(
  WidgetTester tester,
  RecordStore store,
  String id,
) async => (await runIo(
  tester,
  () async =>
      (await store.stockContainerById(personId: meId, containerId: id))!,
))!;

void main() {
  appTest('quantity and threshold drafts stay separate for one container', (
    tester,
  ) async {
    final f = await launch(tester);
    final i = (await runIo(tester, () => _item(f.store)))!;
    final c = (await runIo(tester, () => _container(f.store, i)))!;
    f.container
        .read(routerProvider)
        .go('/stock/$meId/adjust/${c.id}?notices=true');
    await settle(tester);
    await _enter(tester, 'Low-stock threshold', '0.25');
    // A threshold draft alone must not save nor change the container yet.
    f.container.read(routerProvider).go('/today');
    await settle(tester);
    final stored = await _stored(tester, f.store, c.id);
    expect(stored.lowThreshold, isNull);
    expect((await runIo(tester, () => f.store.drafts()))!.length, 1);

    // The quantity surface never restores the stored threshold.
    f.container.read(routerProvider).go('/stock/$meId/adjust/${c.id}');
    await settle(tester);
    expect(
      find.descendant(
        of: find.byType(VitalTaskFrame),
        matching: find.text('Adjust stock'),
      ),
      findsOneWidget,
    );
    expect(find.text('Stock notices'), findsNothing);
    await tap(tester, 'Restock');
    await _enter(tester, 'Amount', '4');
    await _enter(tester, 'Reason (optional)', 'Delivery');
    f.container.read(routerProvider).go('/today');
    await settle(tester);

    final drafts = await _adjustmentDrafts(tester, f.store);
    expect(drafts.length, 2);
    final movement = drafts.singleWhere((d) => d.fields['kind'] == 'restock');
    final threshold = drafts.singleWhere((d) => d.fields['kind'] == 'notices');
    // Movement content keeps the legacy shared key and raw container identity.
    expect(movement.id, 'stockAdjustment:$meId:${c.id}');
    expect(movement.operationId, isNotEmpty);
    expect(movement.personId, meId);
    expect(movement.targetId, c.id);
    expect(movement.targetId, isNot(contains('?')));
    expect(movement.route, '/stock/$meId/adjust/${c.id}');
    expect(movement.fields['amount'], '4');
    expect(movement.fields['reason'], 'Delivery');
    // Notices content carries the stable variant key with the raw target too.
    expect(threshold.id, 'stockAdjustment:$meId:${c.id}:notices');
    expect(threshold.operationId, isNot(movement.operationId));
    expect(threshold.personId, meId);
    expect(threshold.targetId, c.id);
    expect(threshold.route, '/stock/$meId/adjust/${c.id}?notices=true');
    expect(threshold.fields['amount'], '0.25');
    expect(threshold.submitted, false);

    // Same-surface reopening keeps threshold values and its operation identity.
    f.container
        .read(routerProvider)
        .go('/stock/$meId/adjust/${c.id}?notices=true');
    await settle(tester);
    expect(find.text('Stock notices'), findsOneWidget);
    expect(
      tester.widget<TextField>(_field('Low-stock threshold')).controller!.text,
      '0.25',
    );
    final reopened = (await _adjustmentDrafts(
      tester,
      f.store,
    )).singleWhere((d) => d.fields['kind'] == 'notices');
    expect(reopened.id, threshold.id);
    expect(reopened.operationId, threshold.operationId);
    expect(reopened.personRevision, threshold.personRevision);
    expect(reopened.targetRevision, threshold.targetRevision);
  });

  appTest('pending threshold draft resumes and saves without stock changes', (
    tester,
  ) async {
    final f = await launch(tester);
    final i = (await runIo(tester, () => _item(f.store)))!;
    final c = (await runIo(tester, () => _container(f.store, i)))!;
    f.container
        .read(routerProvider)
        .go('/stock/$meId/adjust/${c.id}?notices=true');
    await settle(tester);
    await _enter(tester, 'Low-stock threshold', '0.25');
    final original = (await _adjustmentDrafts(tester, f.store)).single;
    f.container.read(routerProvider).go('/today');
    await settle(tester);
    // Today lists the entry and its real Resume control recovers it.
    await waitForText(tester, 'Unfinished entries');
    expect(find.text('Adjust stock'), findsOneWidget);
    expect(find.text('Resume'), findsOneWidget);
    await tap(tester, 'Resume');
    expect(find.text('Stock notices'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(VitalTaskFrame),
        matching: find.text('Adjust stock'),
      ),
      findsNothing,
    );
    expect(
      tester.widget<TextField>(_field('Low-stock threshold')).controller!.text,
      '0.25',
    );
    // The resumed draft keeps the captured operation, revisions and target.
    final resumed = (await _adjustmentDrafts(tester, f.store)).single;
    expect(resumed.id, original.id);
    expect(resumed.operationId, original.operationId);
    expect(resumed.targetId, c.id);
    expect(resumed.personRevision, original.personRevision);
    expect(resumed.targetRevision, original.targetRevision);
    final movementsBefore = await runIo(
      tester,
      () => f.store.stockMovements(personId: meId, containerId: c.id),
    );
    await tap(tester, 'Save');
    await settle(tester);
    // Saving the threshold changes no physical stock.
    final stored = await _stored(tester, f.store, c.id);
    expect(stored.lowThreshold!.numerator, BigInt.one);
    expect(stored.lowThreshold!.denominator, BigInt.from(4));
    expect(
      (await runIo(
        tester,
        () => f.store.stockMovements(personId: meId, containerId: c.id),
      )),
      hasLength(movementsBefore!.length),
    );
    expect((await runIo(tester, () => f.store.drafts()))!, isEmpty);
  });

  appTest('saving a restock draft keeps the threshold draft usable', (
    tester,
  ) async {
    final f = await launch(tester);
    final i = (await runIo(tester, () => _item(f.store)))!;
    final c = (await runIo(tester, () => _container(f.store, i)))!;
    f.container
        .read(routerProvider)
        .go('/stock/$meId/adjust/${c.id}?notices=true');
    await settle(tester);
    await _enter(tester, 'Low-stock threshold', '0.25');
    f.container.read(routerProvider).go('/today');
    await settle(tester);
    f.container.read(routerProvider).go('/stock/$meId/adjust/${c.id}');
    await settle(tester);
    await tap(tester, 'Restock');
    await _enter(tester, 'Amount', '4');
    await tap(tester, 'Save');
    await waitForText(tester, 'Remaining: 6 ml');
    // One committed restock beyond the container's own opening measurement;
    // the notices entry stays pending at its variant key.
    final movements = (await runIo(
      tester,
      () => f.store.stockMovements(personId: meId, containerId: c.id),
    ))!;
    expect(movements, hasLength(2));
    final restock = movements.singleWhere(
      (m) => m.kind == StockMovementKind.restock,
    );
    expect(restock.amount!.numerator, BigInt.from(4));
    expect(restock.amount!.denominator, BigInt.one);
    final notices = await _adjustmentDrafts(tester, f.store);
    expect(notices.length, 1);
    expect(notices.single.fields['kind'], 'notices');
    expect(notices.single.fields['amount'], '0.25');
    expect(notices.single.targetId, c.id);
    expect(notices.single.id, 'stockAdjustment:$meId:${c.id}:notices');
    // The notices entry still resumes and saves without touching stock.
    f.container
        .read(routerProvider)
        .go('/stock/$meId/adjust/${c.id}?notices=true');
    await settle(tester);
    expect(find.text('Stock notices'), findsOneWidget);
    expect(
      tester.widget<TextField>(_field('Low-stock threshold')).controller!.text,
      '0.25',
    );
    await _enter(tester, 'Low-stock threshold', '0.5');
    await tap(tester, 'Save');
    await settle(tester);
    // The restock advanced the captured revision, so the stale threshold
    // command reports the conflict and nothing is saved; the entry stays
    // pending, reviewed at its own surface.
    expect(find.textContaining('This record has changed'), findsOneWidget);
    final saved = await _stored(tester, f.store, c.id);
    expect(saved.lowThreshold, isNull);
    expect(
      (await runIo(
        tester,
        () => f.store.stockMovements(personId: meId, containerId: c.id),
      )),
      hasLength(2),
    );
    final retained = (await _adjustmentDrafts(tester, f.store));
    expect(retained.length, 1);
    expect(retained.single.fields['amount'], '0.25');
  });

  appTest('stored restock draft keeps its kind and values after reopening', (
    tester,
  ) async {
    final f = await launch(tester);
    final i = (await runIo(tester, () => _item(f.store)))!;
    final c = (await runIo(tester, () => _container(f.store, i)))!;
    f.container.read(routerProvider).go('/stock/$meId/adjust/${c.id}');
    await settle(tester);
    await tap(tester, 'Restock');
    await _enter(tester, 'Amount', '4');
    await _enter(tester, 'Reason (optional)', 'Delivery');
    final original = (await _adjustmentDrafts(tester, f.store)).single;
    f.container.read(routerProvider).go('/today');
    await settle(tester);
    // The notices surface must not resurrect the pending movement command.
    f.container
        .read(routerProvider)
        .go('/stock/$meId/adjust/${c.id}?notices=true');
    await settle(tester);
    expect(find.text('Stock notices'), findsOneWidget);
    expect(
      tester.widget<TextField>(_field('Low-stock threshold')).controller!.text,
      isEmpty,
    );
    final kept = (await _adjustmentDrafts(tester, f.store)).single;
    expect(kept.id, original.id);
    expect(kept.fields['kind'], 'restock');
    expect(kept.fields['amount'], '4');
    // Reopening the same surface restores the exact saved fields.
    f.container.read(routerProvider).go('/today');
    await settle(tester);
    f.container.read(routerProvider).go('/stock/$meId/adjust/${c.id}');
    await settle(tester);
    expect(
      find.descendant(
        of: find.byType(VitalTaskFrame),
        matching: find.text('Adjust stock'),
      ),
      findsOneWidget,
    );
    expect(tester.widget<TextField>(_field('Amount')).controller!.text, '4');
    expect(
      tester.widget<TextField>(_field('Reason (optional)')).controller!.text,
      'Delivery',
    );
    final restored = (await _adjustmentDrafts(tester, f.store)).single;
    expect(restored.operationId, original.operationId);
    // Saving applies exactly one restock of 4 against the 2 held.
    await tap(tester, 'Save');
    await waitForText(tester, 'Remaining: 6 ml');
    final movements = (await runIo(
      tester,
      () => f.store.stockMovements(personId: meId, containerId: c.id),
    ))!;
    expect(movements, hasLength(2));
    final restock = movements.singleWhere(
      (m) => m.kind == StockMovementKind.restock,
    );
    expect(restock.amount!.numerator, BigInt.from(4));
    expect(restock.amount!.denominator, BigInt.one);
  });

  appTest('quantity editor frees the shared key for a legacy threshold draft', (
    tester,
  ) async {
    final f = await launch(tester);
    final i = (await runIo(tester, () => _item(f.store)))!;
    final c = (await runIo(tester, () => _container(f.store, i)))!;
    final me = (await runIo(tester, () => f.store.profileById(meId)))!;
    // A draft written before mode variants existed, at the shared key.
    await runIo(
      tester,
      () => f.store.saveDraft(
        OrdinaryDraft(
          id: 'stockAdjustment:$meId:${c.id}',
          generation: f.store.generation,
          operationId: 'fixture-legacy-1',
          kind: DraftKind.stockAdjustment,
          personId: meId,
          personRevision: me.revision,
          targetId: c.id,
          targetRevision: c.revision,
          fields: {
            'kind': 'notices',
            'amount': '0.25',
            'unknown': 'false',
            'reason': '',
            'clearThreshold': 'false',
          },
        ),
      ),
    );
    f.container.read(routerProvider).go('/stock/$meId/adjust/${c.id}');
    await settle(tester);
    // No legacy content leaks into the quantity editor: the legacy key is
    // already freed and holds nothing here.
    expect(
      find.descendant(
        of: find.byType(VitalTaskFrame),
        matching: find.text('Adjust stock'),
      ),
      findsOneWidget,
    );
    expect(
      await runIo(
        tester,
        () => f.store.draftById('stockAdjustment:$meId:${c.id}'),
      ),
      isNull,
    );
    await tap(tester, 'Restock');
    await _enter(tester, 'Amount', '1');
    final kept = (await _adjustmentDrafts(
      tester,
      f.store,
    )).singleWhere((d) => d.fields['kind'] == 'notices');
    expect(kept.id, 'stockAdjustment:$meId:${c.id}:notices');
    expect(kept.operationId, 'fixture-legacy-1');
    expect(kept.targetId, c.id);
    expect(kept.fields['amount'], '0.25');
    // The movement saves normally and the relocated notices entry survives.
    await tap(tester, 'Save');
    await waitForText(tester, 'Remaining: 3 ml');
    final pending = (await _adjustmentDrafts(tester, f.store));
    expect(pending.length, 1);
    expect(pending.single.id, 'stockAdjustment:$meId:${c.id}:notices');
    expect(pending.single.operationId, 'fixture-legacy-1');
    f.container.read(routerProvider).go('/today');
    await settle(tester);
    f.container
        .read(routerProvider)
        .go('/stock/$meId/adjust/${c.id}?notices=true');
    await settle(tester);
    expect(find.text('Stock notices'), findsOneWidget);
    expect(
      tester.widget<TextField>(_field('Low-stock threshold')).controller!.text,
      '0.25',
    );
  });

  appTest('notices editor adopts a legacy threshold draft from its old key', (
    tester,
  ) async {
    final f = await launch(tester);
    final i = (await runIo(tester, () => _item(f.store)))!;
    final c = (await runIo(tester, () => _container(f.store, i)))!;
    final me = (await runIo(tester, () => f.store.profileById(meId)))!;
    await runIo(
      tester,
      () => f.store.saveDraft(
        OrdinaryDraft(
          id: 'stockAdjustment:$meId:${c.id}',
          generation: f.store.generation,
          operationId: 'fixture-legacy-2',
          kind: DraftKind.stockAdjustment,
          personId: meId,
          personRevision: me.revision,
          targetId: c.id,
          targetRevision: c.revision,
          fields: {
            'kind': 'notices',
            'amount': '0.25',
            'unknown': 'false',
            'reason': '',
            'clearThreshold': 'false',
          },
        ),
      ),
    );
    f.container
        .read(routerProvider)
        .go('/stock/$meId/adjust/${c.id}?notices=true');
    await settle(tester);
    expect(find.text('Stock notices'), findsOneWidget);
    expect(
      tester.widget<TextField>(_field('Low-stock threshold')).controller!.text,
      '0.25',
    );
    final adopted = (await _adjustmentDrafts(tester, f.store)).single;
    expect(adopted.id, 'stockAdjustment:$meId:${c.id}:notices');
    expect(adopted.operationId, 'fixture-legacy-2');
    expect(adopted.targetId, c.id);
    expect(adopted.targetRevision, c.revision);
    expect(adopted.fields['amount'], '0.25');
    final movementsBefore = await runIo(
      tester,
      () => f.store.stockMovements(personId: meId, containerId: c.id),
    );
    await tap(tester, 'Save');
    await settle(tester);
    final stored = await _stored(tester, f.store, c.id);
    expect(stored.lowThreshold!.numerator, BigInt.one);
    expect(stored.lowThreshold!.denominator, BigInt.from(4));
    expect(
      (await runIo(
        tester,
        () => f.store.stockMovements(personId: meId, containerId: c.id),
      )),
      hasLength(movementsBefore!.length),
    );
    expect((await runIo(tester, () => f.store.drafts()))!, isEmpty);
  });
}
