import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:true_grit_vital/data/record_store.dart';

void main() {
  late Directory dir;
  late RecordStore store;
  late String path;
  late SubstanceItem item;
  final key = List.generate(32, (i) => i + 1);
  final at = DateTime.utc(2026, 10, 19, 8);
  ExactAmount n(int x, [int d = 1]) =>
      ExactAmount(BigInt.from(x), BigInt.from(d));
  List<ProductComponent> parts([String? a = '3', String? b = '7']) => [
    ProductComponent(
      ingredientId: 'a',
      name: 'Synthetic ingredient with retained salt A',
      concentrationText: a,
    ),
    ProductComponent(
      ingredientId: 'b',
      name: 'Synthetic ingredient with retained salt B',
      concentrationText: b,
    ),
  ];
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('vital-products-');
    path = '${dir.path}/records.db';
    store = await RecordStore.open(path: path, key: key, isNew: true);
    item = await store.createItem(
      commandId: 'item',
      name: 'Synthetic product',
      form: 'liquid',
      unit: 'ml',
      type: 'medicine',
      productComponents: parts(),
    );
  });
  tearDown(() async {
    await store.close();
    await dir.delete(recursive: true);
  });
  Future<ProductLabelSnapshot> label() =>
      store.productLabel(personId: meId, itemId: item.id).then((x) => x!);
  Future<ProductUseInput> use({
    String amount = '0.5',
    StoredStockContainer? source,
    ProductLabelSnapshot? original,
  }) async => ProductUseInput(
    expectedGeneration: store.generation,
    label: original ?? await label(),
    enteredVolume: EnteredStockAmount(amount, 'ml'),
    containerId: source?.id,
    expectedContainerRevision: source?.revision,
    sourceLabel: source?.productLabel,
  );
  Future<StoredStockContainer> container({
    String id = 'source',
    ProductLabelSnapshot? sourceLabel,
    ExactAmount? opening,
  }) async => store.createStockContainer(
    commandId: id,
    personId: meId,
    expectedPersonRevision: 1,
    expectedGeneration: store.generation,
    itemId: item.id,
    label: 'Synthetic vial',
    unit: 'ml',
    strength: LabelledStrength(
      ingredientId: item.id,
      label: 'Physical volume only',
    ),
    productLabel: sourceLabel ?? await label(),
    opening: opening ?? n(1),
  );
  Future<UseRecord> take(
    ProductUseInput input, {
    String id = 'take',
    bool fail = false,
  }) => store.recordProduct(
    commandId: id,
    personId: meId,
    expectedPersonRevision: 1,
    itemId: item.id,
    actualAt: at,
    use: input,
    failBeforeCommit: fail,
  );
  test(
    'atomic encrypted reopen replay changed payload and one physical outflow',
    () async {
      final c = await container();
      final input = await use(source: c);
      final r = await take(input);
      expect(r.product!.components.map((x) => x.amount), [n(3, 2), n(7, 2)]);
      expect(
        (await store.stockContainerById(
          personId: meId,
          containerId: c.id,
        ))!.balance.value,
        n(1, 2),
      );
      await store.close();
      store = await RecordStore.open(path: path, key: key, isNew: false);
      expect((await take(input)).alreadyCommitted, true);
      expect(
        await store.stockMovements(personId: meId, containerId: c.id),
        hasLength(2),
      );
      expect(await store.history(r.id), hasLength(1));
      await expectLater(
        take(await use(amount: '0.6', source: c)),
        throwsA(isA<CommandConflict>()),
      );
      expect(
        File(path).readAsBytesSync().take(16).toList(),
        isNot('SQLite format 3'.codeUnits),
      );
    },
  );
  test('rollback and context guards preserve complete transaction', () async {
    final c = await container();
    final input = await use(source: c);
    await expectLater(take(input, fail: true), throwsStateError);
    expect(await store.records(), isEmpty);
    expect(
      await store.stockMovements(personId: meId, containerId: c.id),
      hasLength(1),
    );
    final foreign = ProductLabelSnapshot(
      personId: 'other',
      itemId: item.id,
      revision: 1,
      components: parts(),
    );
    await expectLater(
      take(
        ProductUseInput(
          expectedGeneration: store.generation,
          label: foreign,
          enteredVolume: EnteredStockAmount('1', 'ml'),
        ),
      ),
      throwsA(isA<CommandConflict>()),
    );
    await expectLater(
      take(
        ProductUseInput(
          expectedGeneration: 'old',
          label: await label(),
          enteredVolume: EnteredStockAmount('1', 'ml'),
        ),
      ),
      throwsA(isA<CommandConflict>()),
    );
    await expectLater(
      store.record(
        commandId: 'scalar',
        itemId: item.id,
        amount: '1',
        actualAt: at,
      ),
      throwsA(isA<CommandConflict>()),
    );
    expect(await store.records(), isEmpty);
  });
  test(
    'label edit source replacement and corrections preserve original snapshots',
    () async {
      final original = await label();
      final c = await container();
      final r = await take(await use(source: c));
      final newer = await store.saveProductLabel(
        commandId: 'label',
        personId: meId,
        expectedPersonRevision: 1,
        expectedGeneration: store.generation,
        itemId: item.id,
        expectedItemRevision: 1,
        expectedProductRevision: 1,
        components: parts('5', null),
      );
      await expectLater(
        take(await use(original: original), id: 'stale'),
        throwsA(isA<CommandConflict>()),
      );
      final nowSource = (await store.stockContainerById(
        personId: meId,
        containerId: c.id,
      ))!;
      final replacement = await take(
        await use(source: nowSource),
        id: 'replacement',
      );
      expect(replacement.product!.defaultLabel.revision, newer.revision);
      expect(replacement.product!.label.revision, 1);
      expect(replacement.product!.components.last.amount, n(7, 2));
      expect((await label()).revision, 2);
      final time = await store.correct(
        commandId: 'time',
        recordId: r.id,
        expectedRevision: 1,
        amount: null,
        actualAt: at.add(const Duration(hours: 1)),
        stockCorrection: PhysicalCorrection.retainPhysicalEffect,
      );
      expect(time.product!.volume, n(1, 2));
      final corrected = await store.correct(
        commandId: 'correct',
        recordId: r.id,
        expectedRevision: 2,
        amount: '0.75',
        actualAt: at,
        stockCorrection: PhysicalCorrection.retainPhysicalEffect,
      );
      expect(corrected.product!.components.first.amount, n(9, 4));
      await store.voidRecord(
        commandId: 'void',
        recordId: r.id,
        expectedRevision: 3,
        stockCorrection: PhysicalCorrection.retainPhysicalEffect,
      );
      final totals = await store.productTotals(personId: meId);
      expect(totals.administrations, 1);
      expect(totals.ingredients.first.total, n(3, 2));
      expect(await store.history(r.id), hasLength(4));
      expect(
        (await store.stockContainerById(
          personId: meId,
          containerId: c.id,
        ))!.balance.value,
        n(0),
      );
      expect(
        await store.stockMovements(personId: meId, containerId: c.id),
        hasLength(4),
      );
    },
  );
  test('unknown no-stock deficit and report limits remain explicit', () async {
    await store.saveProductLabel(
      commandId: 'unknown',
      personId: meId,
      expectedPersonRevision: 1,
      expectedGeneration: store.generation,
      itemId: item.id,
      expectedItemRevision: 1,
      expectedProductRevision: 1,
      components: parts('3', null),
    );
    final c = await container(opening: n(0));
    await take(await use(source: c));
    await take(await use(), id: 'untracked');
    final totals = await store.productTotals(personId: meId);
    expect(totals.volume, n(1));
    expect(totals.ingredients.first.total, n(3));
    expect(totals.ingredients.last.total, isNull);
    expect(totals.ingredients.last.complete, false);
    expect(
      (await store.productTotals(personId: meId, maxRecords: 1)).complete,
      false,
    );
    expect(
      (await store.stockContainerById(
        personId: meId,
        containerId: c.id,
      ))!.balance.value,
      n(-1, 2),
    );
  });
  test('frozen populated schema9 migrates scalar metadata and reminder namespace', () async {
    await store.close();
    await File(path).delete();
    final raw = sqlite3.open(path);
    raw.execute("PRAGMA cipher='chacha20'");
    raw.execute(
      'PRAGMA key="x\'${key.map((x) => x.toRadixString(16).padLeft(2, '0')).join()}\'"',
    );
    raw.execute(
      File('test/data/fixtures/record_store_v9.sql').readAsStringSync(),
    );
    raw.close();
    store = await RecordStore.open(path: path, key: key, isNew: false);
    final old = (await store.recordById('other-record', personId: 'other'))!;
    expect(old.actualAmount, n(1, 3));
    expect(old.product, isNull);
    expect(old.labelledStrength!.label, 'Synthetic exact metadata');
    expect((await store.history('record')), hasLength(2));
    expect(await store.drafts(), isNotEmpty);
    // The frozen plan is PRN, so runtime eligibility is false despite the retained raw preference.
    expect(await store.planRemindersEnabled('plan'), false);
    final retained = sqlite3.open(path);
    retained.execute("PRAGMA cipher='chacha20'");
    final hex = key.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
    retained.execute("PRAGMA key=\"x'$hex'\"");
    expect(
      retained
          .select('SELECT plan,person,enabled,revision FROM reminder_config')
          .single
          .values,
      ['plan', 'me', 1, 1],
    );
    retained.close();
    final reminders = await store.prepareReminders(
      now: at,
      observedZone: 'Europe/London',
      clockSample: null,
      adapterFingerprint: 'migration-test',
    );
    expect(reminders.namespace, 'synthetic-v9-namespace');
    final product = await store.createItem(
      commandId: 'post-migration',
      name: 'Product',
      form: 'liquid',
      unit: 'ml',
      type: 'medicine',
      productComponents: parts(),
    );
    expect(
      await store.productLabel(personId: meId, itemId: product.id),
      isNotNull,
    );
  });
  Future<DailyRow> planned({
    CalendarPattern calendar = const EveryDay(),
  }) async {
    final date = CivilDate(2026, 10, 19);
    await store.saveDailyPlan(
      commandId: 'plan',
      expectedPersonRevision: 1,
      expectedGeneration: store.generation,
      plan: DailyPlanVersion(
        personId: meId,
        planId: 'p',
        itemId: item.id,
        versionId: 'v',
        start: date,
        calendar: calendar,
        timing: DailySlots([
          DailySlot(
            id: 'am',
            time: WallTime(8, 0),
            amount: PlannedAmount(
              quantity: ExactQuantity.parse('0.5'),
              enteredText: '0.5',
              unit: 'ml',
            ),
            reminderEnabled: true,
          ),
        ]),
        zoneBasis: const FollowingLocal(),
      ),
    );
    await store.setPlanReminders(
      commandId: 'enable',
      planId: 'p',
      personId: meId,
      expectedPlanRevision: 1,
      expectedPersonRevision: 1,
      enabled: true,
    );
    return (await store.dailyRows(
      from: date,
      toExclusive: date.addDays(1),
      observedZone: 'Europe/London',
    )).rows.single;
  }

  test('captured native target survives encrypted restart and records all components atomically', () async {
    await planned();
    final projection = await store.prepareReminders(
      now: at.subtract(const Duration(hours: 2)),
      observedZone: 'Europe/London',
      clockSample: null,
      adapterFingerprint: 'product-test',
    );
    final desired = projection.desired.first;
    final pending = await store.captureReminderAction(
      envelopeId: 'native',
      namespace: projection.namespace,
      requestToken: desired.requestToken,
      actionToken: desired.takenToken,
      action: ReminderActionKind.taken,
    );
    expect(pending!.target.row.productLabel!.revision, 1);
    await store.close();
    store = await RecordStore.open(path: path, key: key, isNew: false);
    final reopened = (await store.pendingReminderActions()).single;
    final action = await store.actDaily(
      commandId: reopened.commandId,
      row: reopened.target.row,
      kind: DailyActionKind.taken,
      actualAt: at,
      reminderTarget: reopened.target,
      reminderObservedZone: 'Europe/London',
    );
    final actual = (await store.recordById(action.recordId!))!;
    expect(actual.product!.components.map((x) => x.amount), [n(3, 2), n(7, 2)]);
    expect(
      (await store.actDaily(
        commandId: reopened.commandId,
        row: reopened.target.row,
        kind: DailyActionKind.taken,
        actualAt: at,
        reminderTarget: reopened.target,
        reminderObservedZone: 'America/New_York',
      )).alreadyCommitted,
      true,
    );
    final after = await store.prepareReminders(
      now: at.subtract(const Duration(hours: 2)),
      observedZone: 'Europe/London',
      clockSample: null,
      adapterFingerprint: 'product-test',
    );
    expect(
      after.desired.where(
        (x) =>
            x.target.row.expectation.identity ==
            reopened.target.row.expectation.identity,
      ),
      isEmpty,
    );
  });
  test('calendar product Taken versus Skip has one winner and one physical outflow at most', () async {
    final row = await planned(calendar: SelectedWeekdays([1, 3, 5]));
    final c = await container();
    final input = await use(source: c);
    final other = await RecordStore.open(path: path, key: key, isNew: false);
    try {
      final results = await Future.wait([
        store
            .actDaily(
              commandId: 'taken-race',
              row: row,
              kind: DailyActionKind.taken,
              actualAt: at,
              productUse: input,
            )
            .then<Object>((x) => x)
            .catchError((Object e) => e),
        other
            .actDaily(
              commandId: 'skip-race',
              row: row,
              kind: DailyActionKind.skip,
            )
            .then<Object>((x) => x)
            .catchError((Object e) => e),
      ]);
      expect(results.whereType<DailyAction>(), hasLength(1));
      expect(results.whereType<CommandConflict>(), hasLength(1));
      final records = await store.records();
      final moves = await store.stockMovements(
        personId: meId,
        containerId: c.id,
      );
      expect(
        moves.where((x) => x.kind == StockMovementKind.actualUse).length,
        records.length,
      );
      if (records.isNotEmpty) {
        expect(records.single.product!.components, hasLength(2));
      }
    } finally {
      await other.close();
    }
  });
  test('stale native product definition and wrong source fail before any resolution', () async {
    final row = await planned();
    final target = await store.reminderTarget(
      row,
      observedZone: 'Europe/London',
    );
    await store.saveProductLabel(
      commandId: 'change',
      personId: meId,
      expectedPersonRevision: 1,
      expectedGeneration: store.generation,
      itemId: item.id,
      expectedItemRevision: 1,
      expectedProductRevision: 1,
      components: parts('5', '8'),
    );
    await expectLater(
      store.actDaily(
        commandId: 'stale-native',
        row: row,
        kind: DailyActionKind.taken,
        actualAt: at,
        reminderTarget: target,
        reminderObservedZone: 'Europe/London',
      ),
      throwsA(isA<CommandConflict>()),
    );
    expect(await store.records(), isEmpty);
    final c = await container();
    final wrong = ProductLabelSnapshot(
      personId: meId,
      itemId: item.id,
      revision: 2,
      components: parts('9', '9'),
    );
    await expectLater(
      take(
        ProductUseInput(
          expectedGeneration: store.generation,
          label: await label(),
          enteredVolume: EnteredStockAmount('0.5', 'ml'),
          containerId: c.id,
          expectedContainerRevision: c.revision,
          sourceLabel: wrong,
        ),
      ),
      throwsA(isA<CommandConflict>()),
    );
    expect(
      await store.stockMovements(personId: meId, containerId: c.id),
      hasLength(1),
    );
  });
  test(
    'mixed-person source rejected and profile deletion scrubs product replay',
    () async {
      final adult = await store.createProfile(
        commandId: 'adult',
        name: 'Other adult',
        adultConfirmed: true,
      );
      final theirs = await store.createItem(
        commandId: 'other-item',
        personId: adult.id,
        expectedPersonRevision: adult.revision,
        name: 'Same product',
        form: 'liquid',
        unit: 'ml',
        type: 'medicine',
        productComponents: parts(),
      );
      final theirsLabel = (await store.productLabel(
        personId: adult.id,
        itemId: theirs.id,
      ))!;
      final c = await store.createStockContainer(
        commandId: 'other-source',
        personId: adult.id,
        expectedPersonRevision: adult.revision,
        expectedGeneration: store.generation,
        itemId: theirs.id,
        label: 'Other vial',
        unit: 'ml',
        strength: LabelledStrength(ingredientId: theirs.id, label: 'Volume'),
        productLabel: theirsLabel,
        opening: n(1),
      );
      await expectLater(
        take(
          ProductUseInput(
            expectedGeneration: store.generation,
            label: await label(),
            enteredVolume: EnteredStockAmount('0.5', 'ml'),
            containerId: c.id,
            expectedContainerRevision: c.revision,
            sourceLabel: theirsLabel,
          ),
        ),
        throwsA(isA<CommandConflict>()),
      );
      final input = ProductUseInput(
        expectedGeneration: store.generation,
        label: theirsLabel,
        enteredVolume: EnteredStockAmount('0.5', 'ml'),
      );
      await store.recordProduct(
        commandId: 'other-take',
        personId: adult.id,
        expectedPersonRevision: adult.revision,
        itemId: theirs.id,
        actualAt: at,
        use: input,
      );
      await store.deleteProfile(
        commandId: 'delete',
        personId: adult.id,
        expectedRevision: adult.revision,
      );
      await expectLater(
        store.recordProduct(
          commandId: 'other-take',
          personId: adult.id,
          expectedPersonRevision: adult.revision,
          itemId: theirs.id,
          actualAt: at,
          use: input,
        ),
        throwsA(isA<CommandConflict>()),
      );
      expect((await store.productTotals(personId: meId)).administrations, 0);
    },
  );
  test(
    'failed schema9 migration retains original recovery tables and version',
    () async {
      final failed = '${dir.path}/failed.db';
      final raw = sqlite3.open(failed);
      raw.execute("PRAGMA cipher='chacha20'");
      final hex = key.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
      raw.execute('PRAGMA key="x\'$hex\'"');
      raw.execute(
        File('test/data/fixtures/record_store_v9.sql').readAsStringSync(),
      );
      raw.execute('CREATE TABLE revision_product(obstacle TEXT) STRICT');
      raw.close();
      await expectLater(
        RecordStore.open(path: failed, key: key, isNew: false),
        throwsA(anything),
      );
      final recovery = sqlite3.open(failed);
      recovery.execute("PRAGMA cipher='chacha20'");
      recovery.execute('PRAGMA key="x\'$hex\'"');
      expect(recovery.select('PRAGMA user_version').single.values.single, 9);
      expect(
        recovery.select(
          "SELECT name FROM sqlite_master WHERE name='product_label'",
        ),
        isEmpty,
      );
      expect(
        recovery
            .select('SELECT numerator,denominator FROM revision_quantity')
            .single
            .values,
        ['1', '3'],
      );
      recovery.close();
    },
  );

  test('explicit reversal and repeated Undo are applied once while history remains', () async {
    final c = await container();
    final r = await take(await use(source: c));
    final undone = await store.voidRecord(
      commandId: 'undo-product',
      recordId: r.id,
      expectedRevision: 1,
      stockCorrection: PhysicalCorrection.reverseRecordedEffect,
    );
    expect(undone.isVoided, true);
    expect(
      (await store.voidRecord(
        commandId: 'undo-product',
        recordId: r.id,
        expectedRevision: 1,
        stockCorrection: PhysicalCorrection.reverseRecordedEffect,
      )).alreadyCommitted,
      true,
    );
    await expectLater(
      store.voidRecord(
        commandId: 'undo-again',
        recordId: r.id,
        expectedRevision: 1,
        stockCorrection: PhysicalCorrection.reverseRecordedEffect,
      ),
      throwsA(isA<CommandConflict>()),
    );
    expect(
      (await store.stockContainerById(
        personId: meId,
        containerId: c.id,
      ))!.balance.value,
      n(1),
    );
    expect((await store.productTotals(personId: meId)).administrations, 0);
    expect(await store.history(r.id), hasLength(2));
    expect(
      await store.stockMovements(personId: meId, containerId: c.id),
      hasLength(3),
    );
  });
  test('item revision frozen with input and conversion of an ml item retains old scalar actuals', () async {
    final scalar = await store.createItem(
      commandId: 'scalar-item',
      name: 'Previous single item',
      form: 'liquid',
      unit: 'ml',
      type: 'medicine',
    );
    final old = await store.record(
      commandId: 'old-scalar',
      itemId: scalar.id,
      amount: '0.5',
      actualAt: at,
    );
    final product = await store.saveProductLabel(
      commandId: 'convert',
      personId: meId,
      expectedPersonRevision: 1,
      expectedGeneration: store.generation,
      itemId: scalar.id,
      expectedItemRevision: scalar.revision,
      expectedProductRevision: 0,
      components: parts(),
    );
    await expectLater(
      store.recordProduct(
        commandId: 'stale-item',
        personId: meId,
        expectedPersonRevision: 1,
        itemId: scalar.id,
        actualAt: at,
        use: ProductUseInput(
          expectedGeneration: store.generation,
          label: product,
          expectedItemRevision: scalar.revision,
          enteredVolume: EnteredStockAmount('0.5', 'ml'),
        ),
      ),
      throwsA(isA<CommandConflict>()),
    );
    expect((await store.recordById(old.id))!.product, isNull);
  });
}
