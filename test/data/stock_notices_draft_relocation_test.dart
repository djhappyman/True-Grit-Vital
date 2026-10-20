import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:true_grit_vital/data/record_store.dart';

void main() {
  late Directory dir;
  late RecordStore store;
  late StoredStockContainer container;
  final key = List.generate(32, (i) => i + 1);
  final legacyId = 'stockAdjustment:$meId:container';
  final variantId = 'stockAdjustment:$meId:container:notices';
  Map<String, String> fieldsTo(String kind) => {
    'kind': kind,
    'amount': '0.25',
    'unknown': 'false',
    'reason': '',
    'clearThreshold': 'false',
  };
  Future<OrdinaryDraft> draftTo(
    String id,
    String kind, {
    String operation = 'op-1',
  }) async {
    final me = (await store.profileById(meId))!;
    return OrdinaryDraft(
      id: id,
      generation: store.generation,
      operationId: operation,
      kind: DraftKind.stockAdjustment,
      personId: meId,
      personRevision: me.revision,
      targetId: 'container',
      targetRevision: container.revision,
      fields: fieldsTo(kind),
    );
  }

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('vital-stock-relocate-');
    store = await RecordStore.open(
      path: '${dir.path}/stock.db',
      key: key,
      isNew: true,
    );
    container = await store.createStockContainer(
      commandId: 'container',
      personId: meId,
      expectedPersonRevision: 1,
      expectedGeneration: store.generation,
      itemId: (await store.createItem(
        commandId: 'item',
        expectedPersonRevision: (await store.profileById(meId))!.revision,
        personId: meId,
        name: 'Relocate draft source',
        form: 'liquid',
        unit: 'ml',
        type: 'Test',
      )).id,
      label: 'Relocation vial',
      unit: 'ml',
      strength: LabelledStrength(
        ingredientId: 'ingredient',
        label: '10 mg/ml',
        mgPerMl: ExactAmount.parseEntry('10'),
      ),
    );
  });
  tearDown(() async {
    await store.close();
    await dir.delete(recursive: true);
  });

  test('notices-kind draft adopts to the variant key unchanged', () async {
    final legacy = await draftTo(legacyId, 'notices');
    await store.saveDraft(legacy);
    final adopted = await store.relocateLegacyStockNoticesDraft(
      legacyId: legacyId,
      destinationId: variantId,
      personId: meId,
      targetId: 'container',
    );
    expect(adopted, isNotNull);
    expect(adopted!.id, variantId);
    expect(adopted.operationId, 'op-1');
    expect(adopted.submitted, false);
    expect(adopted.personId, meId);
    expect(adopted.targetId, 'container');
    expect(adopted.targetRevision, container.revision);
    expect(adopted.fields['kind'], 'notices');
    expect(adopted.fields['amount'], '0.25');
    expect(await store.draftById(legacyId), isNull);
    final moved = (await store.draftById(variantId))!;
    expect(moved.operationId, 'op-1');
    expect(moved.fields, fieldsTo('notices'));
  });

  test(
    'a movement-kind legacy row refuses relocation and is left intact',
    () async {
      final legacy = await draftTo(legacyId, 'restock');
      await store.saveDraft(legacy);
      Object? failure;
      try {
        await store.relocateLegacyStockNoticesDraft(
          legacyId: legacyId,
          destinationId: variantId,
          personId: meId,
          targetId: 'container',
        );
      } catch (e) {
        failure = e;
      }
      expect(failure, isA<CommandConflict>());
      final kept = (await store.draftById(legacyId))!;
      expect(kept.fields['kind'], 'restock');
      expect(kept.operationId, 'op-1');
    },
  );

  test(
    'an occupied destination refuses relocation and keeps both rows',
    () async {
      await store.saveDraft(
        await draftTo(legacyId, 'notices', operation: 'op-1'),
      );
      await store.saveDraft(
        await draftTo(variantId, 'notices', operation: 'op-2'),
      );
      Object? failure;
      try {
        await store.relocateLegacyStockNoticesDraft(
          legacyId: legacyId,
          destinationId: variantId,
          personId: meId,
          targetId: 'container',
        );
      } catch (e) {
        failure = e;
      }
      expect(failure, isA<CommandConflict>());
      expect(await store.draftById(legacyId), isNotNull);
      expect(await store.draftById(variantId), isNotNull);
    },
  );

  test(
    'an intent whose operation already committed cannot resurface',
    () async {
      final legacy = await draftTo(legacyId, 'notices', operation: 'op-1');
      // A committed result for the preserved operation arrives first.
      await store.createItem(
        commandId: 'op-1',
        expectedPersonRevision: (await store.profileById(meId))!.revision,
        personId: meId,
        name: 'Committed operation target',
        form: 'liquid',
        unit: 'ml',
        type: 'Test',
      );
      await store.saveDraft(legacy);
      // The durable writer drops the stale intent instead of resurrecting it.
      expect(await store.draftById(legacyId), isNull);
      final adopted = await store.relocateLegacyStockNoticesDraft(
        legacyId: legacyId,
        destinationId: variantId,
        personId: meId,
        targetId: 'container',
      );
      expect(adopted, isNull);
      expect(await store.draftById(variantId), isNull);
    },
  );

  test('a captured callback cannot resurrect a relocated legacy row', () async {
    final legacy = await draftTo(legacyId, 'notices', operation: 'op-3');
    await store.saveDraft(legacy);
    // A late callback captured before adoption, persisting after the move.
    final lateCapture = store.captureDraftCheckpoint(
      await draftTo(legacyId, 'notices', operation: 'op-3'),
    );
    final adopted = await store.relocateLegacyStockNoticesDraft(
      legacyId: legacyId,
      destinationId: variantId,
      personId: meId,
      targetId: 'container',
    );
    expect(adopted, isNotNull);
    Object? failure;
    try {
      await lateCapture.persist();
    } catch (e) {
      failure = e;
    }
    expect(failure, isNotNull);
    // No stale row reappears; the preserved content stays only at the variant.
    expect(await store.draftById(legacyId), isNull);
    expect((await store.draftById(variantId))!.operationId, 'op-3');
    expect((await store.drafts()).length, 1);
  });
}
