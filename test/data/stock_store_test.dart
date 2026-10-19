import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:true_grit_vital/data/record_store.dart';

void main() {
  late Directory dir;
  late RecordStore store;
  late SubstanceItem item;
  late String path;
  final key = List.generate(32, (i) => i + 1);
  ExactAmount n(int a, [int b = 1]) =>
      ExactAmount(BigInt.from(a), BigInt.from(b));
  LabelledStrength strength([int concentration = 3]) => LabelledStrength(
    ingredientId: 'ingredient',
    label: '$concentration mg/ml',
    mgPerMl: n(concentration),
  );
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('vital-stock-');
    path = '${dir.path}/stock.db';
    store = await RecordStore.open(path: path, key: key, isNew: true);
    item = await store.createItem(
      commandId: 'item',
      name: 'Synthetic stock',
      form: 'liquid',
      unit: 'mg',
      type: 'medicine',
    );
  });
  tearDown(() async {
    await store.close();
    await dir.delete(recursive: true);
  });
  Future<StoredStockContainer> container({
    String op = 'container',
    ExactAmount? opening,
    LabelledStrength? labelled,
    ExactAmount? threshold,
    bool refill = false,
  }) => store.createStockContainer(
    commandId: op,
    personId: meId,
    expectedPersonRevision: 1,
    expectedGeneration: store.generation,
    itemId: item.id,
    label: 'Synthetic vial',
    unit: 'ml',
    strength: labelled ?? strength(),
    opening: opening,
    lowThreshold: threshold,
    refillEnabled: refill,
  );
  Future<StoredStockContainer> current(StoredStockContainer c) async =>
      (await store.stockContainerById(personId: meId, containerId: c.id))!;
  Future<UseRecord> take(
    StoredStockContainer c, {
    String op = 'take',
    String entered = '1',
    bool fail = false,
    StockReplacement? replacement,
  }) => store.record(
    commandId: op,
    itemId: item.id,
    amount: entered,
    actualAt: DateTime.utc(2026, 10, 19),
    stockUse: StockUseInput(
      expectedGeneration: store.generation,
      containerId: c.id,
      expectedContainerRevision: c.revision,
      entered: EnteredStockAmount(entered, 'mg'),
      replacement: replacement,
    ),
    failBeforeCommit: fail,
  );
  Future<StoredStockContainer> adjust(
    StoredStockContainer c,
    String op,
    StockMovementKind kind, {
    String? amount,
    ExactAmount? measured,
  }) => store.addStockMovement(
    commandId: op,
    personId: meId,
    expectedPersonRevision: 1,
    expectedGeneration: store.generation,
    containerId: c.id,
    expectedContainerRevision: c.revision,
    kind: kind,
    amount: amount == null ? null : EnteredStockAmount(amount, 'ml'),
    measured: measured,
  );
  test(
    'exact thirds survive encryption reopen and replay without duplicate use',
    () async {
      var c = await container(opening: n(1));
      final record = await take(c);
      c = await current(c);
      expect(c.balance.value, n(2, 3));
      await store.close();
      store = await RecordStore.open(path: path, key: key, isNew: false);
      final replay = await store.record(
        commandId: 'take',
        itemId: item.id,
        amount: '1',
        actualAt: record.actualAt,
        stockUse: StockUseInput(
          expectedGeneration: store.generation,
          containerId: c.id,
          expectedContainerRevision: c.revision - 1,
          entered: EnteredStockAmount('1', 'mg'),
        ),
      );
      expect(replay.alreadyCommitted, true);
      expect((await current(c)).balance.value, n(2, 3));
      expect(
        await store.stockMovements(personId: meId, containerId: c.id),
        hasLength(2),
      );
    },
  );
  test(
    'actual saves signed deficit and unknown conversion distinctly',
    () async {
      final c = await container(opening: n(0));
      await take(c);
      expect((await current(c)).balance.value, n(-1, 3));
      final unknown = await container(
        op: 'unknown',
        opening: n(2),
        labelled: LabelledStrength(
          ingredientId: 'ingredient',
          label: 'Unknown',
        ),
      );
      await take(unknown, op: 'unknown-use');
      expect((await current(unknown)).balance.value, isNull);
      expect((await current(unknown)).balance.limitReached, false);
      expect(await store.records(), hasLength(2));
    },
  );
  test('rollback leaves actual, ledger, checkpoint and retry intact', () async {
    final c = await container(opening: n(2));
    await expectLater(take(c, fail: true), throwsStateError);
    expect(await store.records(), isEmpty);
    expect((await current(c)).balance.value, n(2));
    expect(
      await store.stockMovements(personId: meId, containerId: c.id),
      hasLength(1),
    );
    await take(c);
    expect((await current(c)).balance.value, n(5, 3));
  });
  test('generation ownership and stale revision reject atomically', () async {
    final c = await container(opening: n(2));
    await take(c);
    await expectLater(take(c, op: 'stale'), throwsA(isA<CommandConflict>()));
    await expectLater(
      store.configureStockNotices(
        commandId: 'old-generation',
        personId: meId,
        expectedPersonRevision: 1,
        expectedGeneration: 'wrong',
        containerId: c.id,
        expectedContainerRevision: c.revision,
        refillEnabled: true,
      ),
      throwsA(isA<CommandConflict>()),
    );
    final other = await store.createProfile(
      commandId: 'other',
      name: 'Other',
      adultConfirmed: true,
    );
    await expectLater(
      store.record(
        commandId: 'owner',
        personId: other.id,
        itemId: item.id,
        amount: '1',
        actualAt: DateTime.utc(2026),
        stockUse: StockUseInput(
          expectedGeneration: store.generation,
          containerId: c.id,
          expectedContainerRevision: c.revision,
          entered: EnteredStockAmount('1', 'mg'),
        ),
      ),
      throwsA(isA<CommandConflict>()),
    );
    expect(await store.records(), hasLength(1));
  });
  test(
    'explicit correction never double consumes and only reverses once',
    () async {
      final c = await container(opening: n(2));
      final r = await take(c);
      await expectLater(
        store.correct(
          commandId: 'missing',
          recordId: r.id,
          expectedRevision: 1,
          amount: '2',
          actualAt: r.actualAt,
        ),
        throwsA(isA<CommandConflict>()),
      );
      final corrected = await store.correct(
        commandId: 'correct',
        recordId: r.id,
        expectedRevision: 1,
        amount: '2',
        actualAt: r.actualAt,
        stockCorrection: PhysicalCorrection.reverseRecordedEffect,
      );
      expect((await current(c)).balance.value, n(2));
      expect(corrected.actualAmount, n(2));
      await expectLater(
        store.voidRecord(
          commandId: 'twice',
          recordId: r.id,
          expectedRevision: 2,
          stockCorrection: PhysicalCorrection.reverseRecordedEffect,
        ),
        throwsA(isA<CommandConflict>()),
      );
      await store.voidRecord(
        commandId: 'void',
        recordId: r.id,
        expectedRevision: 2,
        stockCorrection: PhysicalCorrection.retainPhysicalEffect,
      );
      expect((await current(c)).balance.value, n(2));
      expect(
        await store.stockMovements(personId: meId, containerId: c.id),
        hasLength(3),
      );
    },
  );
  test(
    'retained effect stays consumed through subsequent edits and void',
    () async {
      final c = await container(opening: n(2));
      final r = await take(c);
      await store.correct(
        commandId: 'first',
        recordId: r.id,
        expectedRevision: 1,
        amount: '2',
        actualAt: r.actualAt,
        stockCorrection: PhysicalCorrection.retainPhysicalEffect,
      );
      await store.correct(
        commandId: 'second',
        recordId: r.id,
        expectedRevision: 2,
        amount: '3',
        actualAt: r.actualAt,
        stockCorrection: PhysicalCorrection.retainPhysicalEffect,
      );
      await store.voidRecord(
        commandId: 'void',
        recordId: r.id,
        expectedRevision: 3,
        stockCorrection: PhysicalCorrection.retainPhysicalEffect,
      );
      expect((await current(c)).balance.value, n(5, 3));
      expect(
        (await store.stockUseForRecord(
          personId: meId,
          recordId: r.id,
        ))!.reviewedCorrection,
        PhysicalCorrection.retainPhysicalEffect,
      );
    },
  );
  test('pre measurement reversal preserves measured balance including unknown original', () async {
    for (final known in [true, false]) {
      var c = await container(
        op: 'c-$known',
        opening: n(2),
        labelled: known
            ? strength()
            : LabelledStrength(ingredientId: 'ingredient', label: 'Unknown'),
      );
      final r = await take(c, op: 'take-$known');
      c = await current(c);
      c = await adjust(
        c,
        'measure-$known',
        StockMovementKind.reconciliation,
        measured: n(5),
      );
      await store.voidRecord(
        commandId: 'void-$known',
        recordId: r.id,
        expectedRevision: 1,
        stockCorrection: PhysicalCorrection.reverseRecordedEffect,
      );
      expect((await current(c)).balance.value, n(5));
    }
  });
  test('post measurement reverse restores stock and unknown reconciliation stays unknown', () async {
    var c = await container(opening: n(2));
    c = await adjust(
      c,
      'measure',
      StockMovementKind.reconciliation,
      measured: n(5),
    );
    final r = await take(c);
    await store.voidRecord(
      commandId: 'void',
      recordId: r.id,
      expectedRevision: 1,
      stockCorrection: PhysicalCorrection.reverseRecordedEffect,
    );
    expect((await current(c)).balance.value, n(5));
    c = await current(c);
    c = await adjust(c, 'unknown', StockMovementKind.reconciliation);
    c = await adjust(c, 'restock', StockMovementKind.restock, amount: '2');
    expect(c.balance.value, isNull);
  });
  test(
    'zero unknown threshold refill restock and correction notice transitions',
    () async {
      var c = await container(opening: n(1), threshold: n(1), refill: true);
      expect(c.notice, StockNoticeState.low);
      final r = await take(c, entered: '6');
      c = await current(c);
      expect(c.notice, StockNoticeState.refill);
      await store.voidRecord(
        commandId: 'void',
        recordId: r.id,
        expectedRevision: 1,
        stockCorrection: PhysicalCorrection.reverseRecordedEffect,
      );
      c = await current(c);
      expect(c.notice, StockNoticeState.low);
      c = await adjust(c, 'restock', StockMovementKind.restock, amount: '2');
      expect(c.notice, StockNoticeState.none);
      c = await adjust(c, 'unknown', StockMovementKind.reconciliation);
      expect(c.notice, StockNoticeState.unknown);
      c = await adjust(
        c,
        'zero',
        StockMovementKind.reconciliation,
        measured: n(0),
      );
      expect(c.notice, StockNoticeState.refill);
      c = await store.configureStockNotices(
        commandId: 'disable',
        personId: meId,
        expectedPersonRevision: 1,
        expectedGeneration: store.generation,
        containerId: c.id,
        expectedContainerRevision: c.revision,
        refillEnabled: false,
      );
      expect(c.notice, StockNoticeState.none);
    },
  );
  test(
    'replacement keeps ml but records exact actual mg per revision',
    () async {
      final c = await container(opening: n(10), labelled: strength(20));
      final replacement = StockReplacement(
        oldStrength: strength(10),
        newStrength: strength(20),
        keep: FixedReplacementAmount.millilitres,
      );
      final r = await take(c, entered: '5', replacement: replacement);
      expect(r.actualAmount, n(10));
      expect(r.actualUnit, 'mg');
      expect(r.originalEntry, '5');
      expect(() => r.amount, throwsStateError);
      expect((await current(c)).balance.value, n(19, 2));
      await store.correct(
        commandId: 'correct',
        recordId: r.id,
        expectedRevision: 1,
        amount: '7',
        actualAt: r.actualAt,
        stockCorrection: PhysicalCorrection.retainPhysicalEffect,
      );
      final history = await store.history(r.id);
      expect(history.first.actualAmount, n(10));
      expect(history.last.actualAmount, n(7));
      expect(history.last.replacement, isNull);
      expect(history.last.labelledStrength!.mgPerMl, n(20));
      expect((await current(c)).balance.value, n(19, 2));
    },
  );
  test('replacement repeating actual and standalone labelled source preserve exact values', () async {
    final c = await container(opening: n(10), labelled: strength(2));
    final r = await take(
      c,
      entered: '1',
      replacement: StockReplacement(
        oldStrength: strength(3),
        newStrength: strength(2),
        keep: FixedReplacementAmount.millilitres,
      ),
    );
    expect(r.actualAmount, n(2, 3));
    expect((await current(c)).balance.value, n(29, 3));
    final standalone = await store.record(
      commandId: 'label',
      itemId: item.id,
      amount: '1',
      actualAt: DateTime.utc(2026),
      stockUse: StockUseInput(
        expectedGeneration: store.generation,
        entered: EnteredStockAmount('1', 'ml'),
        strength: strength(2),
      ),
    );
    expect(standalone.actualAmount, n(1));
    expect(standalone.actualUnit, 'ml');
    expect(standalone.labelledStrength!.mgPerMl, n(2));
    expect(
      await store.stockUseForRecord(personId: meId, recordId: standalone.id),
      isNull,
    );
  });
  test(
    'bounded ledger pages and independent connection revision race',
    () async {
      final c = await container(opening: n(2));
      final other = await RecordStore.open(path: path, key: key, isNew: false);
      Future<bool> attempt(RecordStore s, String op) async {
        try {
          await s.record(
            commandId: op,
            itemId: item.id,
            amount: '1',
            actualAt: DateTime.utc(2026),
            stockUse: StockUseInput(
              expectedGeneration: store.generation,
              containerId: c.id,
              expectedContainerRevision: c.revision,
              entered: EnteredStockAmount('1', 'mg'),
            ),
          );
          return true;
        } on CommandConflict {
          return false;
        }
      }

      try {
        expect(
          await Future.wait([attempt(store, 'a'), attempt(other, 'b')]),
          containsAll([true, false]),
        );
      } finally {
        await other.close();
      }
      expect(
        await store.stockMovements(personId: meId, containerId: c.id, limit: 1),
        hasLength(1),
      );
      expect(
        (await store.stockMovements(
          personId: meId,
          containerId: c.id,
          limit: 1,
          offset: 1,
        )).single.kind,
        StockMovementKind.reconciliation,
      );
      await expectLater(
        store.stockMovements(personId: meId, containerId: c.id, limit: 501),
        throwsRangeError,
      );
    },
  );
  test(
    'scoped deletion removes ledger and invalidates operation replay',
    () async {
      final c = await container(opening: n(2));
      await take(c);
      await store.deleteProfile(
        commandId: 'delete',
        personId: meId,
        expectedRevision: 1,
      );
      expect(await store.stockContainers(personId: meId), isEmpty);
      expect(await store.records(), isEmpty);
      await expectLater(take(c), throwsA(isA<CommandConflict>()));
    },
  );
  test('SQLite stores text beyond int64 with no numeric aggregate', () async {
    final huge = ExactAmount(BigInt.parse('922337203685477580800'));
    final c = await container(opening: huge);
    await take(c);
    expect((await current(c)).balance.value, huge - n(1, 3));
    await store.close();
    final db = sqlite3.open(path);
    final hex = key.map((v) => v.toRadixString(16).padLeft(2, '0')).join();
    db.execute("PRAGMA cipher='chacha20'");
    db.execute("PRAGMA key=\"x'$hex'\"");
    expect(
      db
          .select('SELECT typeof(numerator) AS type FROM stock_movement')
          .every((r) => r['type'] == 'text'),
      true,
    );
    expect(
      () => db.execute('UPDATE stock_movement SET sequence=99'),
      throwsA(anything),
    );
    db.close();
    store = await RecordStore.open(path: path, key: key, isNew: false);
  });
  test('time only correction and void preserve repeating actual and source metadata', () async {
    final c = await container(opening: n(10), labelled: strength(7));
    final r = await take(
      c,
      entered: '5.000',
      replacement: StockReplacement(
        oldStrength: strength(3),
        newStrength: strength(7),
        keep: FixedReplacementAmount.millilitres,
      ),
    );
    expect(r.actualAmount, n(35, 3));
    final corrected = await store.correct(
      commandId: 'time',
      recordId: r.id,
      expectedRevision: 1,
      amount: null,
      actualAt: r.actualAt.add(const Duration(hours: 1)),
      stockCorrection: PhysicalCorrection.retainPhysicalEffect,
    );
    expect(corrected.actualAmount, n(35, 3));
    expect(corrected.originalEntry, '5.000');
    expect(corrected.replacement!.oldStrength.mgPerMl, n(3));
    expect(corrected.labelledStrength!.mgPerMl, n(7));
    final voided = await store.voidRecord(
      commandId: 'void',
      recordId: r.id,
      expectedRevision: 2,
      stockCorrection: PhysicalCorrection.retainPhysicalEffect,
    );
    expect(voided.actualAmount, n(35, 3));
    expect((await current(c)).balance.value, n(25, 3));
  });
  test('standalone ml replacement keeps mg and derives exact volume', () async {
    final r = await store.record(
      commandId: 'standalone',
      itemId: item.id,
      amount: '0.5',
      actualAt: DateTime.utc(2026),
      stockUse: StockUseInput(
        expectedGeneration: store.generation,
        entered: EnteredStockAmount('0.5', 'ml'),
        strength: strength(7),
        replacement: StockReplacement(
          oldStrength: strength(3),
          newStrength: strength(7),
          keep: FixedReplacementAmount.milligrams,
        ),
      ),
    );
    expect(r.actualAmount, n(3, 2));
    expect(r.actualUnit, 'mg');
    expect(r.originalUnit, 'ml');
    expect(await store.stockContainers(personId: meId), isEmpty);
  });
  test(
    'contradictory entry and out of envelope strength reject before writes',
    () async {
      final c = await container(opening: n(2));
      await expectLater(
        store.record(
          commandId: 'contradiction',
          itemId: item.id,
          amount: '1',
          actualAt: DateTime.utc(2026),
          stockUse: StockUseInput(
            expectedGeneration: store.generation,
            containerId: c.id,
            expectedContainerRevision: c.revision,
            entered: EnteredStockAmount('2', 'mg'),
          ),
        ),
        throwsFormatException,
      );
      await expectLater(
        container(
          op: 'bad-strength',
          labelled: LabelledStrength(
            ingredientId: 'ingredient',
            label: 'Too large',
            mgPerMl: ExactAmount(BigInt.from(10).pow(100)),
          ),
        ),
        throwsFormatException,
      );
      expect(await store.records(), isEmpty);
      expect((await current(c)).balance.value, n(2));
    },
  );
  test('unknown replacement remains explicit and actual use commits', () async {
    final unknown = LabelledStrength(
      ingredientId: 'ingredient',
      label: 'Unknown',
    );
    final c = await container(opening: n(2), labelled: unknown);
    final r = await take(
      c,
      replacement: StockReplacement(
        oldStrength: strength(3),
        newStrength: unknown,
        keep: FixedReplacementAmount.millilitres,
      ),
    );
    expect(r.replacementResolved, false);
    expect(r.actualAmount, n(1));
    expect((await current(c)).balance.value, isNull);
  });
  test(
    'aggregate limit commits raw use and measurement restores availability',
    () async {
      final oversized = ExactAmount(BigInt.one << 65536);
      var c = await container(opening: oversized);
      expect(c.balance.limitReached, true);
      final r = await take(c);
      expect(r.id, isNotEmpty);
      c = await current(c);
      expect(c.balance.limitReached, true);
      expect(
        await store.stockMovements(personId: meId, containerId: c.id),
        hasLength(2),
      );
      c = await adjust(
        c,
        'measure',
        StockMovementKind.reconciliation,
        measured: n(0),
      );
      expect(c.balance.limitReached, false);
      expect(c.balance.value, n(0));
    },
  );
  test(
    'daily Taken consumes atomically Skip does not and Undo requires choice',
    () async {
      var c = await container(opening: n(2));
      final day = CivilDate(2026, 10, 19);
      await store.saveDailyPlan(
        commandId: 'plan',
        plan: DailyPlanVersion(
          personId: meId,
          planId: 'plan',
          itemId: item.id,
          versionId: 'version',
          start: day,
          timing: DailyCount(
            2,
            PlannedAmount(quantity: ExactQuantity.parse('1'), unit: 'mg'),
          ),
          zoneBasis: const FollowingLocal(),
        ),
        expectedPersonRevision: 1,
        expectedGeneration: store.generation,
      );
      Future<DailyRow> row() async => (await store.dailyRows(
        from: day,
        toExclusive: day.addDays(1),
        observedZone: 'Europe/London',
      )).rows.single;
      final before = await row();
      final input = StockUseInput(
        expectedGeneration: store.generation,
        containerId: c.id,
        expectedContainerRevision: c.revision,
        entered: EnteredStockAmount('1', 'mg'),
      );
      await expectLater(
        store.actDaily(
          commandId: 'take',
          row: before,
          kind: DailyActionKind.taken,
          actualAt: DateTime.utc(2026, 10, 19),
          stockUse: input,
          failBeforeCommit: true,
        ),
        throwsStateError,
      );
      expect(await store.records(), isEmpty);
      expect((await current(c)).balance.value, n(2));
      final action = await store.actDaily(
        commandId: 'take',
        row: before,
        kind: DailyActionKind.taken,
        actualAt: DateTime.utc(2026, 10, 19),
        stockUse: input,
      );
      expect((await current(c)).balance.value, n(5, 3));
      await expectLater(
        store.undoDaily(
          commandId: 'undo-no-choice',
          row: await row(),
          action: action,
        ),
        throwsA(isA<CommandConflict>()),
      );
      await store.undoDaily(
        commandId: 'undo',
        row: await row(),
        action: action,
        stockCorrection: PhysicalCorrection.reverseRecordedEffect,
      );
      c = await current(c);
      expect(c.balance.value, n(2));
      await store.actDaily(
        commandId: 'skip',
        row: await row(),
        kind: DailyActionKind.skip,
      );
      expect((await current(c)).balance.value, n(2));
      expect(
        await store.stockMovements(personId: meId, containerId: c.id),
        hasLength(3),
      );
    },
  );
  test('populated v7 migration retains exact history identity drafts plans and replay', () async {
    await store.close();
    await File(path).delete();
    final raw = sqlite3.open(path);
    final hex = key.map((v) => v.toRadixString(16).padLeft(2, '0')).join();
    raw.execute("PRAGMA cipher='chacha20'");
    raw.execute("PRAGMA key=\"x'$hex'\"");
    raw.execute(
      await File('test/data/fixtures/record_store_v7.sql').readAsString(),
    );
    raw.close();
    store = await RecordStore.open(path: path, key: key, isNew: false);
    expect(store.generation, 'fixture-generation');
    expect((await store.history('record')).first.actualAmount, n(1, 8));
    expect((await store.items()).single.typeId, 'medicine-type');
    expect((await store.drafts()).single.fields['amount'], '1.000');
    expect(await store.dailyPlanVersions('plan', personId: meId), hasLength(1));
    final replay = await store.record(
      commandId: 'fixture-operation',
      itemId: 'item',
      amount: '0.125000',
      actualAt: DateTime.fromMicrosecondsSinceEpoch(
        1792368000000000,
        isUtc: true,
      ),
    );
    expect(replay.alreadyCommitted, true);
    expect(replay.actualAmount, n(1, 8));
    expect(await store.stockContainers(personId: meId), isEmpty);
  });
  test(
    'failed v7 migration rolls back all stock schema and retains recovery data',
    () async {
      final obstacle = '${dir.path}/obstacle.db';
      final raw = sqlite3.open(obstacle);
      final hex = key.map((v) => v.toRadixString(16).padLeft(2, '0')).join();
      raw.execute("PRAGMA cipher='chacha20'");
      raw.execute("PRAGMA key=\"x'$hex'\"");
      raw.execute(
        await File('test/data/fixtures/record_store_v7.sql').readAsString(),
      );
      raw.execute('CREATE TABLE stock_container(obstacle TEXT)');
      raw.close();
      await expectLater(
        RecordStore.open(path: obstacle, key: key, isNew: false),
        throwsA(anything),
      );
      final recovery = sqlite3.open(obstacle);
      recovery.execute("PRAGMA cipher='chacha20'");
      recovery.execute("PRAGMA key=\"x'$hex'\"");
      expect(recovery.select('PRAGMA user_version').single.values.single, 7);
      expect(recovery.select('SELECT * FROM revision'), hasLength(3));
      expect(
        recovery.select(
          "SELECT name FROM sqlite_master WHERE name='revision_quantity'",
        ),
        isEmpty,
      );
      expect(recovery.select('SELECT * FROM ordinary_draft'), hasLength(1));
      recovery.close();
    },
  );
  test('archived adult retains stock history rejects writes and never pools with Me', () async {
    final person = await store.createProfile(
      commandId: 'person',
      name: 'Other',
      adultConfirmed: true,
    );
    final theirs = await store.createItem(
      commandId: 'their-item',
      personId: person.id,
      expectedPersonRevision: 1,
      name: 'Other item',
      form: 'liquid',
      unit: 'ml',
      type: 'medicine',
    );
    final c = await store.createStockContainer(
      commandId: 'their-container',
      personId: person.id,
      expectedPersonRevision: 1,
      expectedGeneration: store.generation,
      itemId: theirs.id,
      label: 'Other vial',
      unit: 'ml',
      strength: strength(),
      opening: n(8),
    );
    await store.archiveProfile(
      commandId: 'archive',
      personId: person.id,
      expectedRevision: 1,
    );
    expect(
      (await store.stockContainers(personId: person.id)).single.balance.value,
      n(8),
    );
    expect(await store.stockContainers(personId: meId), isEmpty);
    await expectLater(
      store.addStockMovement(
        commandId: 'archived',
        personId: person.id,
        expectedPersonRevision: 2,
        expectedGeneration: store.generation,
        containerId: c.id,
        expectedContainerRevision: c.revision,
        kind: StockMovementKind.restock,
        amount: EnteredStockAmount('1', 'ml'),
      ),
      throwsA(isA<CommandConflict>()),
    );
    await store.deleteProfile(
      commandId: 'delete-other',
      personId: person.id,
      expectedRevision: 2,
    );
    expect(await store.stockContainers(personId: person.id), isEmpty);
    expect(await store.items(), hasLength(1));
  });

  test('SQL constraints independently reject malformed pairs signs targets and snapshots', () async {
    final c = await container(opening: n(3));
    await store.close();
    final raw = sqlite3.open(path);
    final hex = key.map((v) => v.toRadixString(16).padLeft(2, '0')).join();
    raw.execute("PRAGMA cipher='chacha20'");
    raw.execute("PRAGMA key=\"x'$hex'\"");
    raw.execute('PRAGMA foreign_keys=ON');
    final row = raw.select('SELECT * FROM stock_container').single;
    List<Object?> values(
      String id,
      String kind,
      String? numerator,
      String? denominator,
    ) => [
      id,
      meId,
      c.id,
      c.sequence + 1,
      kind,
      numerator,
      denominator,
      row['strength'],
      null,
      null,
      null,
      null,
      null,
      null,
      null,
      id,
      store.generation,
      0,
    ];
    for (final pair in [
      ['-1', '1'],
      ['01', '1'],
      ['1', '0'],
      ['1', '-1'],
      ['1', '01'],
      ['1.5', '1'],
      ['1', null],
      [null, null],
    ]) {
      expect(
        () => raw.execute(
          'INSERT INTO stock_movement VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)',
          values('invalid-${pair.join()}', 'restock', pair[0], pair[1]),
        ),
        throwsA(anything),
      );
    }
    final wrong = values('snapshot', 'restock', '1', '1');
    wrong[7] = '{}';
    expect(
      () => raw.execute(
        'INSERT INTO stock_movement VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)',
        wrong,
      ),
      throwsA(anything),
    );
    final correction = values('correction', 'correction', '1', '1');
    correction[11] = 'missing';
    correction[12] = 'reverseRecordedEffect';
    expect(
      () => raw.execute(
        'INSERT INTO stock_movement VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)',
        correction,
      ),
      throwsA(anything),
    );
    expect(
      () => raw.execute("UPDATE stock_container SET strength='{}'"),
      throwsA(anything),
    );
    raw.execute('CREATE TEMP TABLE unsafe_sum(value INTEGER)');
    raw.execute('INSERT INTO unsafe_sum VALUES (9223372036854775807),(1)');
    expect(
      () => raw.select('SELECT SUM(value) FROM unsafe_sum'),
      throwsA(anything),
    );
    raw.close();
    store = await RecordStore.open(path: path, key: key, isNew: false);
  });

  test('long exact ledger updates checkpoint beyond one page without replay truncation', () async {
    var c = await container(opening: n(0));
    for (var i = 0; i < 1101; i++) {
      c = await store.addStockMovement(
        commandId: 'restock-$i',
        personId: meId,
        expectedPersonRevision: 1,
        expectedGeneration: store.generation,
        containerId: c.id,
        expectedContainerRevision: c.revision,
        kind: StockMovementKind.restock,
        amount: EnteredStockAmount('1', 'mg'),
      );
    }
    expect(c.balance.value, n(367));
    expect(c.sequence, 1102);
    final first = await store.stockMovements(
      personId: meId,
      containerId: c.id,
      limit: 500,
    );
    final third = await store.stockMovements(
      personId: meId,
      containerId: c.id,
      limit: 500,
      offset: 1000,
    );
    expect(first, hasLength(500));
    expect(first.first.sequence, 1102);
    expect(third, hasLength(102));
    expect(third.last.sequence, 1);
  });
  test(
    'waste retains reason and exact stock effect without inventing actual use',
    () async {
      final c = await container(opening: n(2));
      final result = await store.addStockMovement(
        commandId: 'waste',
        personId: meId,
        expectedPersonRevision: 1,
        expectedGeneration: store.generation,
        containerId: c.id,
        expectedContainerRevision: c.revision,
        kind: StockMovementKind.waste,
        amount: EnteredStockAmount('1.000', 'mg'),
        reason: 'Synthetic spill',
      );
      expect(result.balance.value, n(5, 3));
      expect(await store.records(), isEmpty);
      final movement = (await store.stockMovements(
        personId: meId,
        containerId: c.id,
      )).first;
      expect(movement.kind, StockMovementKind.waste);
      expect(movement.amount, n(-1, 3));
      expect(movement.reason, 'Synthetic spill');
      expect(movement.enteredText, '1.000');
      expect(movement.recordId, isNull);
    },
  );
  test(
    'notice projection seeks eligible after more than fifty healthy containers',
    () async {
      for (var i = 0; i < 61; i++) {
        await container(op: 'healthy-$i', opening: n(1));
      }
      final all = await store.stockContainers(personId: meId, limit: 100);
      final target = all.last;
      await store.configureStockNotices(
        commandId: 'eligible',
        personId: meId,
        expectedPersonRevision: 1,
        expectedGeneration: store.generation,
        containerId: target.id,
        expectedContainerRevision: target.revision,
        lowThreshold: n(1),
        refillEnabled: false,
      );
      final page = await store.stockNotices(
        scope: const FeedScope.everyone(),
        limit: 50,
      );
      expect(page.rows, hasLength(1));
      expect(page.rows.single.container.id, target.id);
      expect(page.rows.single.personName, 'Me');
      expect(page.rows.single.itemName, item.name);
      expect(page.hasMore, false);
    },
  );
  test('sparse notices across more than one hundred adults use one indexed projection', () async {
    String? target;
    for (var i = 0; i < 110; i++) {
      final person = await store.createProfile(
        commandId: 'person-$i',
        name: 'Adult $i',
        adultConfirmed: true,
      );
      final ownedItem = await store.createItem(
        commandId: 'item-$i',
        personId: person.id,
        expectedPersonRevision: 1,
        name: 'Item $i',
        form: 'liquid',
        unit: 'ml',
        type: 'medicine',
      );
      await store.createStockContainer(
        commandId: 'container-$i',
        personId: person.id,
        expectedPersonRevision: 1,
        expectedGeneration: store.generation,
        itemId: ownedItem.id,
        label: 'Vial $i',
        unit: 'ml',
        strength: strength(),
        opening: n(1),
        lowThreshold: i == 105 ? n(1) : null,
      );
      if (i == 105) target = person.id;
    }
    var page = await store.stockNotices(scope: const FeedScope.everyone());
    expect(page.rows, hasLength(1));
    expect(page.rows.single.container.personId, target);
    expect(page.rows.single.personName, 'Adult 105');
    expect(
      (await store.stockNotices(scope: const FeedScope.me())).rows,
      isEmpty,
    );
    await store.archiveProfile(
      commandId: 'archive-notice',
      personId: target!,
      expectedRevision: 1,
    );
    expect(
      (await store.stockNotices(scope: const FeedScope.everyone())).rows,
      isEmpty,
    );
    await store.reactivateProfile(
      commandId: 'reactivate-notice',
      personId: target,
      expectedRevision: 2,
    );
    page = await store.stockNotices(scope: FeedScope.person(target));
    expect(page.rows, hasLength(1));
    await store.close();
    final raw = sqlite3.open(path);
    final hex = key.map((v) => v.toRadixString(16).padLeft(2, '0')).join();
    raw.execute("PRAGMA cipher='chacha20'");
    raw.execute("PRAGMA key=\"x'$hex'\"");
    final plan = raw
        .select(
          'EXPLAIN QUERY PLAN SELECT c.id FROM stock_container c JOIN person p ON p.id=c.person WHERE c.notice_active=1 AND c.notice_eligible=1 AND p.archived=0 ORDER BY c.person,c.item,c.id LIMIT 51',
        )
        .map((r) => r['detail'].toString())
        .join(' ');
    expect(plan, contains('stock_container_notices'));
    expect(plan, contains('SEARCH c'));
    expect(plan, isNot(contains('TEMP B-TREE')));
    raw.close();
    store = await RecordStore.open(path: path, key: key, isNew: false);
  });
  test('notice eligibility transitions deficits unknown limits settings and explicit pages', () async {
    var c = await container(opening: n(0));
    await take(c);
    var page = await store.stockNotices(scope: const FeedScope.me());
    expect(page.rows.single.container.balance.isDeficit, true);
    c = await current(c);
    c = await adjust(
      c,
      'measure-positive',
      StockMovementKind.reconciliation,
      measured: n(1),
    );
    expect(
      (await store.stockNotices(scope: const FeedScope.me())).rows,
      isEmpty,
    );
    c = await adjust(c, 'unknown-notice', StockMovementKind.reconciliation);
    expect(
      (await store.stockNotices(scope: const FeedScope.me())).rows,
      isEmpty,
    );
    c = await store.configureStockNotices(
      commandId: 'configure-unknown',
      personId: meId,
      expectedPersonRevision: 1,
      expectedGeneration: store.generation,
      containerId: c.id,
      expectedContainerRevision: c.revision,
      refillEnabled: true,
    );
    expect(
      (await store.stockNotices(scope: const FeedScope.me()))
          .rows
          .single
          .container
          .notice,
      StockNoticeState.unknown,
    );
    c = await adjust(
      c,
      'limit-notice',
      StockMovementKind.reconciliation,
      measured: ExactAmount(BigInt.one << 65536),
    );
    expect(
      (await store.stockNotices(scope: const FeedScope.me()))
          .rows
          .single
          .container
          .notice,
      StockNoticeState.limitReached,
    );
    for (var i = 0; i < 51; i++) {
      await container(op: 'low-$i', opening: n(0), refill: true);
    }
    page = await store.stockNotices(scope: const FeedScope.me(), limit: 50);
    expect(page.rows, hasLength(50));
    expect(page.hasMore, true);
    final next = await store.stockNotices(
      scope: const FeedScope.me(),
      limit: 50,
      offset: 50,
    );
    expect(next.rows, hasLength(2));
    expect(next.hasMore, false);
    expect(
      page.rows
          .map((r) => r.container.id)
          .toSet()
          .intersection(next.rows.map((r) => r.container.id).toSet()),
      isEmpty,
    );
  });
}
