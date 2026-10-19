import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:true_grit_vital/data/record_store.dart';

void main() {
  late Directory directory;
  late RecordStore store;
  late String path;
  final key = List.generate(32, (i) => i + 1);
  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'vital-catalogue-records-',
    );
    path = '${directory.path}/records.db';
    store = await RecordStore.open(path: path, key: key, isNew: true);
  });
  tearDown(() async {
    await store.close();
    await directory.delete(recursive: true);
  });
  CatalogueSnapshot snapshot(String version) => CatalogueSnapshot(
    product: const CatalogueProduct(
      code: 'synthetic-code',
      conceptClass: 'test',
      name: 'Invented selection',
      form: 'tablet',
      strength: '25 mg descriptive',
    ),
    manifest: CatalogueManifest(
      version: version,
      sourceId: 'synthetic',
      releaseDate: '2026-10-19',
      sourceUrl: 'https://example.invalid',
      sourceSha256: 'a' * 64,
      projectionSha256: 'b' * 64,
      licence: 'Synthetic fixture',
      attribution: 'Invented test only',
      licenceSha256: 'c' * 64,
      recordCount: 1,
      admissionReference: 'test',
      synthetic: true,
    ),
  );
  Future<SubstanceItem> create(
    String command, {
    CatalogueSnapshot? source,
    String? typeId,
    String type = 'Medicine',
  }) => store.createItem(
    commandId: command,
    name: source?.product.name ?? 'Custom',
    form: source?.product.form ?? 'tablet',
    unit: 'mg',
    type: type,
    typeId: typeId,
    catalogueSnapshot: source,
  );
  test('catalogue provenance survives encryption restart corrections and category rename', () async {
    final selected = snapshot('v1');
    final item = await create('item', source: selected);
    final actual = await store.record(
      commandId: 'actual',
      itemId: item.id,
      amount: '0.125000',
      actualAt: DateTime.utc(2026, 10, 19),
    );
    final type = (await store.itemTypes()).single;
    await store.renameItemType(
      commandId: 'rename',
      typeId: type.id,
      expectedRevision: 1,
      name: 'Personal category',
    );
    expect((await store.itemById(item.id))!.type, 'Personal category');
    expect((await store.itemById(item.id))!.revision, 2);
    final corrected = await store.correct(
      commandId: 'correct',
      recordId: actual.id,
      expectedRevision: 1,
      amount: '0.500000',
      actualAt: actual.actualAt,
    );
    expect(corrected.type, 'Medicine');
    expect(corrected.catalogueSnapshot!.manifest.version, 'v1');
    await create('next', source: snapshot('v2'), typeId: type.id);
    await store.close();
    expect(
      String.fromCharCodes(await File(path).readAsBytes())
          .contains('Invented selection'),
      false,
    );
    store = await RecordStore.open(path: path, key: key, isNew: false);
    final history = await store.history(actual.id);
    expect(history.map((r) => r.enteredAmount), ['0.125000', '0.500000']);
    expect(history.map((r) => r.type), ['Medicine', 'Medicine']);
    expect(history.map((r) => r.catalogueSnapshot!.manifest.version), [
      'v1',
      'v1',
    ]);
    expect(history.first.catalogueSnapshot!.toJson(), selected.toJson());
    final retry = await create('item', source: selected);
    expect(retry.alreadyCommitted, true);
    expect(retry.type, 'Medicine');
    expect(retry.catalogueSnapshot!.manifest.version, 'v1');
    final newer = await store.record(
      commandId: 'later',
      itemId: item.id,
      amount: '1',
      actualAt: actual.actualAt,
    );
    expect(newer.type, 'Personal category');
    expect(newer.catalogueSnapshot!.product.strength, '25 mg descriptive');
  });
  test('daily Taken correction Undo and reopen retain selected catalogue provenance', () async {
    final selected = snapshot('daily-source-v1');
    final item = await create('daily-item', source: selected);
    final date = CivilDate(2026, 10, 19);
    await store.saveDailyPlan(
      commandId: 'daily-plan',
      plan: DailyPlanVersion(
        personId: meId,
        planId: 'catalogue-plan',
        itemId: item.id,
        versionId: 'daily-v1',
        start: date,
        timing: DailyCount(
          1,
          PlannedAmount(
            quantity: ExactQuantity.parse('0.125000'),
            enteredText: '0.125000',
            unit: 'mg',
          ),
        ),
        zoneBasis: const FollowingLocal(),
      ),
      expectedPersonRevision: 1,
      expectedGeneration: store.generation,
    );
    Future<DailyRow> current() async => (await store.dailyRows(
      from: date,
      toExclusive: date.addDays(1),
      observedZone: 'Europe/London',
    )).rows.single;
    final action = await store.actDaily(
      commandId: 'daily-taken',
      row: await current(),
      kind: DailyActionKind.taken,
      actualAt: DateTime.utc(2026, 10, 19, 8),
    );
    final taken = (await store.recordById(action.recordId!))!;
    expect(taken.catalogueSnapshot!.toJson(), selected.toJson());
    expect(taken.enteredAmount, '0.125000');
    final type = (await store.itemTypes()).single;
    // No catalogue manager, installed corpus or reader is present in this test.
    await store.renameItemType(
      commandId: 'daily-rename',
      typeId: type.id,
      expectedRevision: 1,
      name: 'Current category',
    );
    final corrected = await store.correct(
      commandId: 'daily-correct',
      recordId: taken.id,
      expectedRevision: 1,
      amount: '0.500000',
      actualAt: taken.actualAt,
    );
    expect(corrected.catalogueSnapshot!.toJson(), selected.toJson());
    expect(corrected.type, 'Medicine');
    final correctedRow = await current();
    await store.undoDaily(
      commandId: 'daily-undo',
      row: correctedRow,
      action: correctedRow.actions.single,
    );
    expect((await current()).takenCount, 0);
    await store.close();
    store = await RecordStore.open(path: path, key: key, isNew: false);
    final history = await store.history(taken.id);
    expect(history.map((r) => r.revision), [1, 2, 3]);
    expect(history.map((r) => r.enteredAmount), [
      '0.125000',
      '0.500000',
      '0.500000',
    ]);
    expect(history.map((r) => r.isVoided), [false, false, true]);
    for (final revision in history) {
      expect(revision.catalogueSnapshot!.toJson(), selected.toJson());
      expect(revision.type, 'Medicine');
      expect(revision.source, RecordSource.selfReported);
    }
    final restored = await current();
    expect(restored.actions.single.isUndone, true);
    expect(restored.expectation.amount.enteredText, '0.125000');
    final replacement = await store.actDaily(
      commandId: 'daily-replacement',
      row: restored,
      kind: DailyActionKind.taken,
      actualAt: taken.actualAt,
    );
    final actual = (await store.recordById(replacement.recordId!))!;
    expect(actual.type, 'Current category');
    expect(actual.catalogueSnapshot!.toJson(), selected.toJson());
  });
  test('owner scoped types reject stale rename replay misuse archive and scoped deletion', () async {
    final owner = await store.createProfile(
      commandId: 'person',
      name: 'Other adult',
      adultConfirmed: true,
    );
    final own = await store.createItemType(commandId: 'own', name: 'Same name');
    final other = await store.createItemType(
      commandId: 'other',
      name: 'Same name',
      personId: owner.id,
    );
    expect(own.id, isNot(other.id));
    await expectLater(
      store.renameItemType(
        commandId: 'wrong-owner-rename',
        typeId: own.id,
        personId: owner.id,
        expectedRevision: 1,
        name: 'Foreign edit',
      ),
      throwsA(isA<CommandConflict>()),
    );
    expect(
      (await store.itemTypeById(own.id, personId: meId))!.name,
      'Same name',
    );
    await expectLater(
      store.createItem(
        commandId: 'wrong',
        name: 'Wrong',
        form: 'tablet',
        unit: 'mg',
        type: 'Same name',
        typeId: own.id,
        personId: owner.id,
      ),
      throwsA(isA<CommandConflict>()),
    );
    final first = await store.renameItemType(
      commandId: 'rename',
      typeId: own.id,
      expectedRevision: 1,
      name: 'Renamed',
    );
    expect(first.revision, 2);
    expect(
      (await store.renameItemType(
        commandId: 'rename',
        typeId: own.id,
        expectedRevision: 1,
        name: 'Renamed',
      )).alreadyCommitted,
      true,
    );
    await expectLater(
      store.renameItemType(
        commandId: 'stale',
        typeId: own.id,
        expectedRevision: 1,
        name: 'Other',
      ),
      throwsA(isA<CommandConflict>()),
    );
    await expectLater(
      store.renameItemType(
        commandId: 'rename',
        typeId: own.id,
        expectedRevision: 1,
        name: 'Changed payload',
      ),
      throwsA(isA<CommandConflict>()),
    );
    await store.deleteProfile(
      commandId: 'delete',
      personId: owner.id,
      expectedRevision: 1,
    );
    expect(await store.itemTypes(personId: owner.id), isEmpty);
    await expectLater(
      store.createItemType(
        commandId: 'other',
        name: 'Same name',
        personId: owner.id,
      ),
      throwsA(isA<CommandConflict>()),
    );
    expect((await store.itemTypes()).single.name, 'Renamed');
    store.suspendWrites(true);
    await expectLater(
      store.createItemType(commandId: 'locked', name: 'Blocked'),
      throwsA(isA<CommandConflict>()),
    );
  });
  test('captured type revision rejects renamed selection and incomplete selection rolls back', () async {
    final type = await store.createItemType(
      commandId: 'type',
      name: 'Original',
    );
    await store.renameItemType(
      commandId: 'rename',
      typeId: type.id,
      expectedRevision: 1,
      name: 'Renamed',
    );
    await expectLater(
      store.createItem(
        commandId: 'stale-item',
        name: 'Captured',
        form: 'tablet',
        unit: 'mg',
        type: 'Original',
        typeId: type.id,
        expectedTypeRevision: 1,
      ),
      throwsA(isA<CommandConflict>()),
    );
    expect(await store.items(), isEmpty);
    final unchangedTypes = await store.itemTypes();
    expect(unchangedTypes.length, 1);
    expect(unchangedTypes.single.id, type.id);
    expect(unchangedTypes.single.name, 'Renamed');
    expect(unchangedTypes.single.revision, 2);
    await expectLater(
      store.createItem(
        commandId: 'bad-source',
        name: 'Mismatched',
        form: 'tablet',
        unit: 'mg',
        type: 'New category',
        catalogueSnapshot: snapshot('v1'),
      ),
      throwsA(isA<FormatException>()),
    );
    expect((await store.itemTypes()).length, 1);
    final owner = await store.createProfile(
      commandId: 'adult',
      name: 'Archived adult',
      adultConfirmed: true,
    );
    final archivedType = await store.createItemType(
      commandId: 'adult-type',
      personId: owner.id,
      name: 'Archived category',
    );
    await store.archiveProfile(
      commandId: 'archive',
      personId: owner.id,
      expectedRevision: 1,
    );
    await expectLater(
      store.createItemType(
        commandId: 'archived-type',
        personId: owner.id,
        name: 'Forbidden',
        expectedPersonRevision: 2,
      ),
      throwsA(isA<CommandConflict>()),
    );
    await expectLater(
      store.renameItemType(
        commandId: 'archived-rename',
        typeId: archivedType.id,
        personId: owner.id,
        expectedPersonRevision: 2,
        expectedRevision: 1,
        name: 'Forbidden rename',
      ),
      throwsA(isA<CommandConflict>()),
    );
    expect(
      (await store.itemTypeById(archivedType.id, personId: owner.id))!.name,
      'Archived category',
    );
  });
  test(
    'independent writers serialize category revisions and bounded pages',
    () async {
      final type = await store.createItemType(
        commandId: 'type',
        name: 'Original',
      );
      final second = await RecordStore.open(path: path, key: key, isNew: false);
      try {
        final replies = await Future.wait([
          store
              .renameItemType(
                commandId: 'a',
                typeId: type.id,
                expectedRevision: 1,
                name: 'A',
              )
              .then<Object>((v) => v, onError: (Object e) => e),
          second
              .renameItemType(
                commandId: 'b',
                typeId: type.id,
                expectedRevision: 1,
                name: 'B',
              )
              .then<Object>((v) => v, onError: (Object e) => e),
        ]);
        expect(replies.whereType<PersonalItemType>().length, 1);
        expect(replies.whereType<CommandConflict>().length, 1);
        for (var i = 0; i < 15; i++) {
          await store.createItemType(commandId: 'page$i', name: 'Page$i');
        }
        expect((await store.itemTypes(limit: 5)).length, 5);
        expect((await store.itemTypes(limit: 5, offset: 15)).length, 1);
        await expectLater(
          store.itemTypes(limit: 501),
          throwsA(isA<RangeError>()),
        );
      } finally {
        await second.close();
      }
    },
  );
  test(
    'populated encrypted v5 migration preserves exact fields and old snapshots',
    () async {
      await store.close();
      await File(path).delete();
      final db = sqlite3.open(path);
      final hex = key.map((v) => v.toRadixString(16).padLeft(2, '0')).join();
      db.execute("PRAGMA cipher='chacha20'");
      db.execute("PRAGMA key=\"x'$hex'\"");
      db.execute(
        await File('test/data/fixtures/record_store_v5.sql').readAsString(),
      );
      db.close();
      store = await RecordStore.open(path: path, key: key, isNew: false);
      final item = (await store.itemById('item'))!;
      expect(item.name, 'Current synthetic item');
      expect(item.form, 'tablet');
      expect(item.unit, 'mg');
      expect(item.type, 'medicine');
      expect(item.typeId, isNotNull);
      expect(item.catalogueSnapshot, isNull);
      expect((await store.drafts()).single.fields['amount'], '1.000');
      final before = await store.history('record');
      await store.renameItemType(
        commandId: 'rename',
        typeId: item.typeId!,
        expectedRevision: 1,
        name: 'Renamed',
      );
      final after = await store.history('record');
      expect(after.map((r) => r.name), before.map((r) => r.name));
      expect(after.map((r) => r.type), before.map((r) => r.type));
      expect(after.map((r) => r.enteredAmount), ['0.125000', '0.5']);
      expect(after.every((r) => r.catalogueSnapshot == null), true);
    },
  );
  for (final fail in [false, true]) {
    test(
      'frozen populated v6 migration ${fail ? 'rolls back on failure' : 'retains plans and snapshots'}',
      () async {
        await store.close();
        await File(path).delete();
        final hex = key.map((v) => v.toRadixString(16).padLeft(2, '0')).join();
        final db = sqlite3.open(path);
        db.execute("PRAGMA cipher='chacha20'");
        db.execute("PRAGMA key=\"x'$hex'\"");
        db.execute(
          await File('test/data/fixtures/record_store_v6.sql').readAsString(),
        );
        if (fail) {
          db.execute('CREATE TABLE revision_catalogue(obstacle TEXT) STRICT');
        }
        db.close();
        if (fail) {
          await expectLater(
            RecordStore.open(path: path, key: key, isNew: false),
            throwsA(anything),
          );
          final check = sqlite3.open(path);
          check.execute("PRAGMA cipher='chacha20'");
          check.execute("PRAGMA key=\"x'$hex'\"");
          expect(check.select('PRAGMA user_version').single.values.single, 6);
          expect(check.select('SELECT * FROM revision').length, 3);
          expect(check.select('SELECT * FROM daily_plan').length, 1);
          expect(
            check.select(
              "SELECT name FROM pragma_table_info('item') WHERE name='type_id'",
            ),
            isEmpty,
          );
          check.execute('DROP TABLE revision_catalogue');
          check.close();
        }
        store = await RecordStore.open(path: path, key: key, isNew: false);
        expect((await store.dailyPlans()).single.plan.itemId, 'item');
        expect((await store.itemTypes()).single.name, 'medicine');
        expect((await store.history('record')).first.enteredAmount, '0.125000');
      },
    );
  }
}
