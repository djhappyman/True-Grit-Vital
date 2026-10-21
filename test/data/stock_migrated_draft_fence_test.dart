import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:true_grit_vital/data/record_store.dart';

/// Focused fence regression for an adopted legacy notices draft identity:
/// captures and discards that arrive for the legacy (draftId, operationId)
/// pair after the relocation must not rewrite the adopted row or tombstone
/// its pending operation, while the legacy key stays free for fresh quantity
/// drafts on their own operations.
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
    bool submitted = false,
  }) async {
    final me = (await store.profileById(meId))!;
    return OrdinaryDraft(
      id: id,
      generation: store.generation,
      operationId: operation,
      kind: DraftKind.stockAdjustment,
      personId: meId,
      personRevision: me.revision,
      targetId: container.id,
      targetRevision: container.revision,
      fields: fieldsTo(kind),
      submitted: submitted,
    );
  }

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('vital-stock-fence-');
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
        name: 'Fence draft source',
        form: 'liquid',
        unit: 'ml',
        type: 'Test',
      )).id,
      label: 'Fenced vial',
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

  test(
    'a capture taken before adoption cannot persist after the move',
    () async {
      final legacy = await draftTo(legacyId, 'notices', operation: 'op-3');
      await store.saveDraft(legacy);
      // A late callback captured before the migration, persisting after it.
      final lateCapture = store.captureDraftCheckpoint(
        await draftTo(legacyId, 'notices', operation: 'op-3'),
      );
      final adopted = await store.relocateLegacyStockNoticesDraft(
        legacyId: legacyId,
        destinationId: variantId,
        personId: meId,
        targetId: container.id,
      );
      expect(adopted, isNotNull);
      Object? failure;
      try {
        await lateCapture.persist();
      } catch (e) {
        failure = e;
      }
      expect(failure, isA<CommandConflict>());
      // No stale row reappears and no alias invalidates the adopted intent.
      expect(await store.draftById(legacyId), isNull);
      expect((await store.draftById(variantId))!.operationId, 'op-3');
      // Even after the failed write the legacy key cannot tombstone the
      // adopted operation.
      await store.discardDraft(legacyId);
      expect(await store.draftById(variantId), isNotNull);
      expect((await store.drafts()).where((d) => d.id == legacyId), isEmpty);
    },
  );

  test('a capture taken after adoption plus a legacy discard keeps the adopted intent', () async {
    final legacy = await draftTo(legacyId, 'notices', operation: 'op-late');
    await store.saveDraft(legacy);
    await store.relocateLegacyStockNoticesDraft(
      legacyId: legacyId,
      destinationId: variantId,
      personId: meId,
      targetId: container.id,
    );
    // A still-mounted legacy form captures after the move. Capture mutates
    // the in-memory operation map even before persistence is attempted.
    store.captureDraftCheckpoint(legacy);
    await store.discardDraft(legacyId);
    expect(await store.draftById(variantId), isNotNull);
    expect(await store.operationCommitted('op-late'), isFalse);
    expect(await store.draftById(legacyId), isNull);
  });

  test('a fresh quantity draft on a different operation is the only casualty of a legacy discard', () async {
    final legacy = await draftTo(legacyId, 'notices', operation: 'op-ab');
    await store.saveDraft(legacy);
    await store.relocateLegacyStockNoticesDraft(
      legacyId: legacyId,
      destinationId: variantId,
      personId: meId,
      targetId: container.id,
    );
    // A late legacy capture is interleaved with a legitimate fresh
    // quantity draft created and saved on the shared key afterwards.
    store.captureDraftCheckpoint(legacy);
    await store.saveDraft(
      await draftTo(legacyId, 'restock', operation: 'op-fresh'),
    );
    await store.discardDraft(legacyId);
    // A discarded quantity intent is invalidly invalidated; the adopted
    // notices intent stays pending and untouched.
    await expectLater(
      store.operationCommitted('op-fresh'),
      throwsA(isA<CommandConflict>()),
    );
    expect(await store.draftById(variantId), isNotNull);
    final probes = await (
      store.operationCommitted('op-ab'),
      store.draftById(legacyId),
    ).wait;
    expect(probes.$2, isNull); // no tombstone of the adopted operation
    expect(probes.$1, isFalse);
  });

  test(
    'old callbacks after the adopted draft was discarded cannot resurrect it',
    () async {
      final legacy = await draftTo(legacyId, 'notices', operation: 'op-4');
      await store.saveDraft(legacy);
      await store.relocateLegacyStockNoticesDraft(
        legacyId: legacyId,
        destinationId: variantId,
        personId: meId,
        targetId: container.id,
      );
      final lateCapture = store.captureDraftCheckpoint(
        await draftTo(legacyId, 'notices', operation: 'op-4'),
      );
      await store.discardDraft(variantId);
      Object? failure;
      try {
        await lateCapture.persist();
      } catch (e) {
        failure = e;
      }
      expect(failure, isA<CommandConflict>());
      expect(await store.draftById(legacyId), isNull);
      expect(await store.draftById(variantId), isNull);
      expect((await store.drafts()).where((d) => d.id == legacyId), isEmpty);
    },
  );

  test('a submitted intent keeps its identity across adoption', () async {
    final legacy = await draftTo(
      legacyId,
      'notices',
      operation: 'op-5',
      submitted: true,
    );
    await store.saveDraft(legacy);
    final adopted = await store.relocateLegacyStockNoticesDraft(
      legacyId: legacyId,
      destinationId: variantId,
      personId: meId,
      targetId: container.id,
    );
    expect(adopted, isNotNull);
    expect(adopted!.id, variantId);
    expect(adopted.operationId, 'op-5');
    expect(adopted.submitted, true);
    expect(adopted.fields, fieldsTo('notices'));
    expect(adopted.personRevision, (await store.profileById(meId))!.revision);
  });

  test('the real command behind an adopted intent can still be saved after late callbacks', () async {
    final legacy = await draftTo(legacyId, 'notices', operation: 'op-real');
    await store.saveDraft(legacy);
    store.captureDraftCheckpoint(legacy);
    await store.relocateLegacyStockNoticesDraft(
      legacyId: legacyId,
      destinationId: variantId,
      personId: meId,
      targetId: container.id,
    );
    Object? failure;
    try {
      await store.configureStockNotices(
        commandId: 'op-real',
        personId: meId,
        expectedPersonRevision: (await store.profileById(meId))!.revision,
        containerId: container.id,
        expectedContainerRevision: container.revision,
        expectedGeneration: store.generation,
        lowThreshold: ExactAmount.parseEntry('0.25'),
        refillEnabled: container.refillEnabled,
      );
    } catch (e) {
      failure = e;
    }
    expect(failure, isNull);
    expect(await store.operationCommitted('op-real'), isTrue);
    // The committed command drops its draft row without losing the content.
    expect(await store.draftById(variantId), isNull);
    expect(await store.draftById(legacyId), isNull);
  });
}
