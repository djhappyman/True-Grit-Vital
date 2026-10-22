import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:true_grit_vital/data/record_store.dart';

Future<RecordStore> _open(Directory directory) => RecordStore.open(
  path: '${directory.path}/report-stock.db',
  key: List.generate(32, (index) => index + 1),
  isNew: true,
);

Future<SubstanceItem> _item(
  RecordStore store, {
  required String command,
}) async {
  final profile = (await store.profileById(meId))!;
  return store.createItem(
    commandId: command,
    name: 'Synthetic stock item',
    form: 'Bottle',
    unit: 'ml',
    type: 'Medicine',
    expectedPersonRevision: profile.revision,
  );
}

ReportSelection _selection({
  Iterable<String> itemIds = const [],
  bool includeStock = true,
  required DateTime from,
  required DateTime before,
}) => ReportSelection(
  personId: meId,
  fromDate: CivilDate(from.year, from.month, from.day),
  beforeDate: CivilDate(before.year, before.month, before.day),
  displayZone: 'UTC',
  includeStock: includeStock,
  itemIds: itemIds,
);

void main() {
  group('ReportSelection stock option', () {
    ReportSelection selection() => ReportSelection(
      personId: meId,
      fromDate: CivilDate(2026, 10, 1),
      beforeDate: CivilDate(2026, 11, 1),
      displayZone: 'UTC',
    );

    test(
      'defaults off and old JSON decodes off without changing its shape',
      () {
        final legacy = selection().toJson();
        expect(legacy.containsKey('stock'), isFalse);

        final decoded = ReportSelection.fromJson(legacy);
        expect(decoded.includeStock, isFalse);
        expect(decoded.toJson().containsKey('stock'), isFalse);
        expect(decoded.identity, selection().identity);
      },
    );

    test('on round-trips and invalidates the reviewed identity', () {
      final off = selection();
      final on = off.copyWith(includeStock: true);
      expect(on.toJson()['stock'], isTrue);
      expect(on.identity, isNot(off.identity));
      expect(ReportSelection.fromJson(on.toJson()).includeStock, isTrue);
      expect(on.copyWith(includeStock: false).identity, off.identity);
    });
  });

  group('ReportStock capture', () {
    late Directory directory;
    late RecordStore store;
    late SubstanceItem item;
    setUp(() async {
      directory = await Directory.systemTemp.createTemp('vital-report-stock-');
      store = await _open(directory);
      final me = (await store.profileById(meId))!;
      await store.editProfile(
        commandId: 'profile',
        personId: meId,
        expectedRevision: me.revision,
        name: 'Synthetic Person',
        adultConfirmed: true,
      );
      item = await _item(store, command: 'item');
    });
    tearDown(() async {
      await store.close();
      await directory.delete(recursive: true);
    });

    Future<StoredStockContainer> container({
      required String command,
      String? lot,
      CivilDate? expiry,
      ExactAmount? capacity,
      ExactAmount? opening,
    }) async => store.createStockContainer(
      commandId: command,
      personId: meId,
      expectedPersonRevision: (await store.profileById(meId))!.revision,
      expectedGeneration: store.generation,
      itemId: item.id,
      label: 'Synthetic bottle',
      unit: 'ml',
      strength: LabelledStrength(ingredientId: item.id, label: 'Volume'),
      opening: opening,
      lot: lot,
      expiryDate: expiry,
      capacity: capacity,
    );

    Future<UseRecord> take(
      StoredStockContainer container, {
      required String command,
      required DateTime at,
      String amount = '0.5',
    }) async => store.record(
      commandId: command,
      itemId: item.id,
      amount: amount,
      actualAt: at,
      expectedPersonRevision: (await store.profileById(meId))!.revision,
      stockUse: StockUseInput(
        expectedGeneration: store.generation,
        containerId: container.id,
        expectedContainerRevision: container.revision,
        entered: EnteredStockAmount(amount, 'ml'),
      ),
    );

    test(
      'captures only the chosen actual-use container with exact facts',
      () async {
        final chosen = await container(
          command: 'container',
          lot: 'LOT-7',
          expiry: CivilDate(2026, 12, 31),
          capacity: ExactAmount(BigInt.one, BigInt.from(3)),
        );
        final first = await take(
          chosen,
          command: 'take-with-stock',
          at: DateTime.utc(2026, 10, 5, 9),
        );
        await store.record(
          commandId: 'take-without-stock',
          itemId: item.id,
          amount: '0.25',
          actualAt: DateTime.utc(2026, 10, 6, 9),
          expectedPersonRevision: (await store.profileById(meId))!.revision,
        );
        await store.record(
          commandId: 'outside',
          itemId: item.id,
          amount: '1',
          actualAt: DateTime.utc(2026, 11, 2, 9),
          expectedPersonRevision: (await store.profileById(meId))!.revision,
        );

        final now = DateTime.utc(2026, 10, 20, 12);
        final off = await store.captureReport(
          selection: _selection(
            includeStock: false,
            from: DateTime.utc(2026, 10, 1),
            before: DateTime.utc(2026, 11, 1),
          ),
          now: () => now,
        );
        expect(off.snapshot.records.length, 2);
        expect(
          off.snapshot.records.every((r) => r.stockSource == null),
          isTrue,
        );

        final capture = await store.captureReport(
          selection: _selection(
            from: DateTime.utc(2026, 10, 1),
            before: DateTime.utc(2026, 11, 1),
          ),
          now: () => now,
        );
        final records = capture.snapshot.records;
        expect(records.length, 2);
        final withStock = records.firstWhere((record) => record.id == first.id);
        final source = withStock.stockSource!;
        expect(source.containerId, chosen.id);
        expect(source.label, 'Synthetic bottle');
        expect(source.unit, 'ml');
        expect(source.lot, 'LOT-7');
        expect(source.expiryDate, CivilDate(2026, 12, 31));
        expect(source.capacity, ExactAmount(BigInt.one, BigInt.from(3)));
        expect(
          records.singleWhere((record) => record.id != first.id).stockSource,
          isNull,
        );
        expect(
          capture.snapshot.structuredText(use24Hour: true),
          contains('Capacity 1/3 ml'),
        );
      },
    );

    test(
      'a correction keeps the chosen source and filters stay exact',
      () async {
        final chosen = await container(command: 'container');
        final original = await take(
          chosen,
          command: 'take',
          at: DateTime.utc(2026, 10, 5, 9),
        );
        final corrected = await store.correct(
          commandId: 'correct',
          recordId: original.id,
          expectedRevision: original.revision,
          amount: '0.75',
          actualAt: DateTime.utc(2026, 10, 5, 10),
          expectedPersonRevision: (await store.profileById(meId))!.revision,
          stockCorrection: PhysicalCorrection.retainPhysicalEffect,
        );
        expect(corrected.revision, 2);

        final now = DateTime.utc(2026, 10, 20, 12);
        final capture = await store.captureReport(
          selection: _selection(
            from: DateTime.utc(2026, 10, 1),
            before: DateTime.utc(2026, 11, 1),
          ),
          now: () => now,
        );
        final record = capture.snapshot.records.single;
        expect(record.revision, 2);
        expect(record.stockSource!.containerId, chosen.id);
        expect(record.actualAt, DateTime.utc(2026, 10, 5, 10));

        final other = await store.createItem(
          commandId: 'other-item',
          name: 'Other synthetic item',
          form: 'Bottle',
          unit: 'ml',
          type: 'Medicine',
          expectedPersonRevision: (await store.profileById(meId))!.revision,
        );
        await store.record(
          commandId: 'other-record',
          itemId: other.id,
          amount: '1',
          actualAt: DateTime.utc(2026, 10, 7, 9),
          expectedPersonRevision: (await store.profileById(meId))!.revision,
        );
        final scoped = await store.captureReport(
          selection: _selection(
            itemIds: [item.id],
            from: DateTime.utc(2026, 10, 1),
            before: DateTime.utc(2026, 11, 1),
          ),
          now: () => now,
        );
        expect(scoped.snapshot.records.map((record) => record.itemId), [
          item.id,
        ]);
        expect(
          scoped.snapshot.records.single.stockSource!.containerId,
          chosen.id,
        );
      },
    );

    test('missing metadata and a stockless dose stay truthful', () async {
      final bare = await container(command: 'bare-container');
      await take(bare, command: 'bare-take', at: DateTime.utc(2026, 10, 5, 9));
      await store.record(
        commandId: 'stockless',
        itemId: item.id,
        amount: '0.25',
        actualAt: DateTime.utc(2026, 10, 6, 9),
        expectedPersonRevision: (await store.profileById(meId))!.revision,
      );
      final now = DateTime.utc(2026, 10, 20, 12);
      final capture = await store.captureReport(
        selection: _selection(
          from: DateTime.utc(2026, 10, 1),
          before: DateTime.utc(2026, 11, 1),
        ),
        now: () => now,
      );
      final bareRecord = capture.snapshot.records.singleWhere(
        (record) => record.stockSource != null,
      );
      expect(bareRecord.stockSource!.lot, isNull);
      expect(bareRecord.stockSource!.expiryDate, isNull);
      expect(bareRecord.stockSource!.capacity, isNull);
      expect(
        capture.snapshot.records.where((record) => record.stockSource == null),
        hasLength(1),
      );
      final text = capture.snapshot.structuredText(use24Hour: true);
      expect(
        text,
        isNot(
          contains('No dose in this report used a chosen stock container.'),
        ),
      );
      expect(text, contains(ReportText.partialStockSourceNote));
      expect(text, contains(ReportText.stockSourceDisclosure));
    });
  });
}
