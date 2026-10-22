import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:true_grit_vital/data/record_store.dart';
import 'package:true_grit_vital/domain/exports/exports.dart';

void main() {
  late Directory directory;
  late RecordStore store;
  late SubstanceItem item;
  final key = List.generate(32, (i) => i + 21);
  ExactAmount n(int a, [int b = 1]) =>
      ExactAmount(BigInt.from(a), BigInt.from(b));

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('vital-stock-lot-');
    store = await RecordStore.open(
      path: '${directory.path}/records.db',
      key: key,
      isNew: true,
    );
    item = await store.createItem(
      commandId: 'item',
      name: 'Synthetic labelled vial',
      form: 'liquid',
      unit: 'ml',
      type: 'medicine',
    );
  });

  tearDown(() async {
    await store.close();
    await directory.delete(recursive: true);
  });

  Future<StoredStockContainer> create({
    String op = 'container',
    String? lot,
    CivilDate? expiry,
    ExactAmount? capacity,
    ExactAmount? opening,
  }) => store.createStockContainer(
    commandId: op,
    personId: meId,
    expectedPersonRevision: 1,
    expectedGeneration: store.generation,
    itemId: item.id,
    label: 'Amber vial',
    unit: 'ml',
    strength: LabelledStrength(
      ingredientId: item.id,
      label: '10 mg/ml',
      mgPerMl: n(10),
    ),
    opening: opening,
    lot: lot,
    expiryDate: expiry,
    capacity: capacity,
  );

  test('metadata-free create keeps the legacy payload and replays', () async {
    final container = await create(op: 'legacy-create', opening: n(2));
    final hex = key.map((v) => v.toRadixString(16).padLeft(2, '0')).join();
    final raw = sqlite3.open('${directory.path}/records.db');
    raw.execute("PRAGMA cipher='chacha20'");
    raw.execute("PRAGMA key=\"x'$hex'\"");
    final payload = jsonDecode(
      raw
              .select("SELECT payload FROM operation WHERE id='legacy-create'")
              .single['payload']
          as String,
    ) as List<dynamic>;
    raw.close();
    // The frozen pre-metadata payload stays exactly ten entries.
    // Frozen pre-metadata identity: generation plus the original ten fields.
    expect(payload, hasLength(11));
    expect(payload[1], 'stock_container');
    expect(payload[10], 1);
    expect(container.lot, isNull);
    await store.close();
    store = await RecordStore.open(
      path: '${directory.path}/records.db',
      key: key,
      isNew: false,
    );
    final replay = await store.createStockContainer(
      commandId: 'legacy-create',
      personId: meId,
      expectedPersonRevision: 1,
      expectedGeneration: store.generation,
      itemId: item.id,
      label: 'Amber vial',
      unit: 'ml',
      strength: LabelledStrength(
        ingredientId: item.id,
        label: '10 mg/ml',
        mgPerMl: n(10),
      ),
      opening: n(2),
    );
    expect(replay.alreadyCommitted, true);
  });

  test('older containers read empty pack facts and no capacity', () async {
    final container = await create();
    expect(container.lot, isNull);
    expect(container.expiryDate, isNull);
    expect(container.capacity, isNull);
    expect(
      container.expiryState(CivilDate(2026, 10, 22)),
      StockExpiryState.none,
    );
    final history = await store.stockMetadataHistory(
      personId: meId,
      containerId: container.id,
    );
    expect(history, hasLength(1));
    expect(history.single.source, 'created');
    expect(history.single.lot, isNull);
    expect(history.single.capacity, isNull);
  });

  test('exact pack capacity is descriptive and never caps stock', () async {
    final container = await create(
      lot: ' LOT-42 ',
      expiry: CivilDate(2026, 12, 1),
      capacity: n(10),
      opening: n(7),
    );
    expect(container.lot, 'LOT-42');
    expect(container.expiryDate, CivilDate(2026, 12, 1));
    expect(container.capacity, n(10));
    expect(
      container.expiryState(CivilDate(2026, 10, 21)),
      StockExpiryState.future,
    );
    expect(
      container.expiryState(CivilDate(2026, 12, 1)),
      StockExpiryState.today,
    );
    expect(
      container.expiryState(CivilDate(2026, 12, 2)),
      StockExpiryState.expired,
    );
    final restocked = await store.addStockMovement(
      commandId: 'restock',
      personId: meId,
      expectedPersonRevision: 1,
      expectedGeneration: store.generation,
      containerId: container.id,
      expectedContainerRevision: container.revision,
      kind: StockMovementKind.restock,
      amount: EnteredStockAmount('5', 'ml'),
    );
    // Capacity is descriptive: the exact balance may exceed it.
    expect(restocked.balance.value, n(12));
    expect(restocked.capacity, n(10));
  });

  test('invalid capacity and civil dates fail closed', () async {
    await expectLater(create(capacity: n(0)), throwsA(isA<FormatException>()));
    await expectLater(
      create(capacity: ExactAmount(BigInt.from(-2))),
      throwsA(isA<FormatException>()),
    );
    expect(() => CivilDate.parse('2026-02-30'), throwsA(isA<ArgumentError>()));
    expect(await store.stockContainers(personId: meId), isEmpty);
  });

  test('metadata edit keeps revision guards and replays once', () async {
    final container = await create(lot: 'LOT-A', capacity: n(10));
    final before = container.revision;
    final updated = await store.updateStockMetadata(
      commandId: 'edit-1',
      personId: meId,
      expectedPersonRevision: 1,
      expectedGeneration: store.generation,
      containerId: container.id,
      expectedContainerRevision: before,
      lot: 'LOT-B',
      expiryDate: CivilDate(2027, 1, 31),
      capacity: n(12),
    );
    expect(updated.revision, before + 1);
    expect(updated.lot, 'LOT-B');
    expect(updated.capacity, n(12));
    // The same command replays its committed result.
    final replay = await store.updateStockMetadata(
      commandId: 'edit-1',
      personId: meId,
      expectedPersonRevision: 1,
      expectedGeneration: store.generation,
      containerId: container.id,
      expectedContainerRevision: before,
      lot: 'LOT-B',
      expiryDate: CivilDate(2027, 1, 31),
      capacity: n(12),
    );
    expect(replay.alreadyCommitted, true);
    expect(replay.revision, before + 1);
    // A different command with the stale revision is a conflict.
    await expectLater(
      store.updateStockMetadata(
        commandId: 'edit-2',
        personId: meId,
        expectedPersonRevision: 1,
        expectedGeneration: store.generation,
        containerId: container.id,
        expectedContainerRevision: before,
        lot: 'LOT-C',
      ),
      throwsA(isA<CommandConflict>()),
    );
    final history = await store.stockMetadataHistory(
      personId: meId,
      containerId: container.id,
    );
    expect(history.map((row) => row.lot), ['LOT-B', 'LOT-A']);
    expect(history.first.source, 'edited');
  });

  test(
    'editing metadata never rewrites movement or strength snapshots',
    () async {
      final container = await create(
        lot: 'LOT-A',
        expiry: CivilDate(2027, 6, 1),
        capacity: n(10),
        opening: n(4),
      );
      final record = await store.record(
        commandId: 'dose',
        itemId: item.id,
        amount: '20',
        actualAt: DateTime.utc(2026, 10, 22, 8),
        stockUse: StockUseInput(
          expectedGeneration: store.generation,
          containerId: container.id,
          expectedContainerRevision: container.revision,
          entered: EnteredStockAmount('20', 'mg'),
        ),
      );
      final movement = (await store.stockMovements(
        personId: meId,
        containerId: container.id,
      )).firstWhere((row) => row.kind == StockMovementKind.actualUse);
      await store.updateStockMetadata(
        commandId: 'details',
        personId: meId,
        expectedPersonRevision: 1,
        expectedGeneration: store.generation,
        containerId: container.id,
        expectedContainerRevision: (await store.stockContainerById(
          personId: meId,
          containerId: container.id,
        ))!.revision,
        lot: 'LOT-B',
        capacity: n(12),
      );
      final after = (await store.stockMovements(
        personId: meId,
        containerId: container.id,
      )).firstWhere((row) => row.kind == StockMovementKind.actualUse);
      expect(after.id, movement.id);
      expect(after.amount, movement.amount);
      expect(after.strength.label, movement.strength.label);
      expect(after.strength.mgPerMl, movement.strength.mgPerMl);
      expect(movement.amount, ExactAmount(BigInt.from(-2)));
      expect((await store.recordById(record.id))!.actualAmount, n(20));
      // Undo remains unchanged and exact.
      await store.voidRecord(
        commandId: 'undo',
        recordId: record.id,
        expectedRevision: 1,
        stockCorrection: PhysicalCorrection.reverseRecordedEffect,
      );
      expect((await store.records()).single.isVoided, true);
      expect(
        (await store.stockContainerById(
          personId: meId,
          containerId: container.id,
        ))!.balance.value,
        n(4),
      );
    },
  );

  test('structured export carries saved stock source facts', () async {
    final container = await create(
      lot: 'LOT-EXPORT',
      expiry: CivilDate(2027, 3, 4),
      capacity: n(10),
      opening: n(6),
    );
    await store.record(
      commandId: 'dose',
      itemId: item.id,
      amount: '1',
      actualAt: DateTime.utc(2026, 10, 22, 9),
      stockUse: StockUseInput(
        expectedGeneration: store.generation,
        containerId: container.id,
        expectedContainerRevision: container.revision,
        entered: EnteredStockAmount('1', 'ml'),
      ),
    );
    final selection = ExportSelection(
      personId: meId,
      fromDay: CivilDate(2026, 10, 22),
      beforeDay: CivilDate(2026, 10, 23),
      zoneId: 'UTC',
      contents: const [ExportContent.doses],
      format: ExportFormat.json,
    );
    final document = await store.captureExport(selection);
    final source = document.doses.single.stockSource!;
    expect(source.containerId, container.id);
    expect(source.label, 'Amber vial');
    expect(source.lot, 'LOT-EXPORT');
    expect(source.expiryDate, CivilDate(2027, 3, 4));
    expect(source.capacity, n(10));
    final json = document.toJson();
    expect(
      (json['doses'] as List).single['provenance']['stockSource']['lot'],
      'LOT-EXPORT',
    );
    final csv = encodeExportCsv(
      await store.captureExport(
        ExportSelection(
          personId: meId,
          fromDay: CivilDate(2026, 10, 22),
          beforeDay: CivilDate(2026, 10, 23),
          zoneId: 'UTC',
          contents: const [ExportContent.doses],
          format: ExportFormat.csv,
        ),
      ),
    );
    expect(csv, contains('stock_lot'));
    expect(csv, contains('LOT-EXPORT'));
    expect(csv, contains('2027-03-04'));
  });
}
