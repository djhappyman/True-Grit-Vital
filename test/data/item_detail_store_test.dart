import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:true_grit_vital/data/record_store.dart';

void main() {
  late Directory directory;
  late String path;
  late RecordStore store;
  final key = List.generate(32, (i) => i + 1);

  Database raw() {
    final db = sqlite3.open(path);
    db.execute("PRAGMA cipher='chacha20'");
    db.execute(
      'PRAGMA key="x\'${key.map((v) => v.toRadixString(16).padLeft(2, '0')).join()}\'"',
    );
    db.execute('PRAGMA foreign_keys=ON');
    return db;
  }

  Future<SubstanceItem> createItem([String command = 'item']) =>
      store.createItem(
        commandId: command,
        name: 'Synthetic detail substance',
        form: 'Tablet',
        unit: 'mg',
        type: 'Medicine',
      );

  Future<SubstanceDetail> saveDetail({
    String command = 'detail-save',
    required String itemId,
    String instructions = '',
    String notes = '',
    int? expectedRevision,
  }) => store.saveItemDetail(
    commandId: command,
    itemId: itemId,
    instructions: instructions,
    notes: notes,
    expectedRevision: expectedRevision,
  );

  Future<ItemSetupState> updateSetup({
    String command = 'setup-update',
    required String itemId,
    bool skipSchedule = false,
    bool skipStock = false,
    bool skipDetails = false,
    bool complete = false,
  }) => store.updateItemSetup(
    commandId: command,
    itemId: itemId,
    skipSchedule: skipSchedule,
    skipStock: skipStock,
    skipDetails: skipDetails,
    complete: complete,
  );

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('vital-item-detail-');
    path = '${directory.path}/records.db';
    store = await RecordStore.open(path: path, key: key, isNew: true);
  });

  tearDown(() async {
    await store.close();
    await directory.delete(recursive: true);
  });

  test(
    'identity creation starts setup and creates no clinical record',
    () async {
      final item = await createItem();

      expect(await store.records(), isEmpty);
      expect(await store.dailyPlans(), isEmpty);
      expect(await store.stockContainers(personId: meId), isEmpty);
      expect(await store.itemDetail(item.id), isNull);

      final setup = (await store.itemSetup(item.id))!;
      expect(setup.generation, store.generation);
      expect(setup.isComplete, isFalse);
      expect(setup.scheduleSkipped, isFalse);
      expect(setup.stockSkipped, isFalse);
      expect(setup.detailsSkipped, isFalse);

      final retry = await createItem();
      expect(retry.id, item.id);
      expect(retry.alreadyCommitted, isTrue);
      expect(await store.items(), hasLength(1));

      final db = raw();
      try {
        expect(
          db.select('SELECT count(*) c FROM item_setup').single['c'],
          1,
          reason: 'identity replay must not duplicate setup progress',
        );
      } finally {
        db.close();
      }
    },
  );

  test(
    'detail copies authored text exactly across an encrypted reopen',
    () async {
      final item = await createItem();
      const instructions =
          'Keep the original casing: 0.125 mg, <0.10, 1/8 and 2.500000.\n'
          'Second line stays separate.';
      const notes =
          'Private note: allergies noted by hand.\nNo interpretation.';

      final saved = await saveDetail(
        itemId: item.id,
        instructions: instructions,
        notes: notes,
      );
      expect(saved.revision, 1);
      expect(saved.instructions, instructions);
      expect(saved.notes, notes);

      final replay = await saveDetail(
        itemId: item.id,
        instructions: instructions,
        notes: notes,
      );
      expect(replay.revision, 1);
      expect(replay.updatedAt, saved.updatedAt);

      await store.close();
      store = await RecordStore.open(path: path, key: key, isNew: false);
      final reopened = (await store.itemDetail(item.id))!;
      expect(reopened.instructions, instructions);
      expect(reopened.notes, notes);
      expect(reopened.revision, 1);
      expect(reopened.personId, meId);
    },
  );

  test('identity edits are revision guarded, replay safely and preserve past doses', () async {
    final item = await createItem();
    final dose = await store.record(
      commandId: 'dose',
      itemId: item.id,
      amount: '0.125',
      actualAt: DateTime.utc(2026, 10, 22, 8),
    );
    Future<SubstanceDetail> edit({
      String command = 'identity',
      String name = 'Completed name',
      int? itemRevision,
    }) => store.saveItemDetail(
      commandId: command,
      itemId: item.id,
      expectedGeneration: store.generation,
      expectedRevision: null,
      expectedItemRevision: itemRevision ?? item.revision,
      name: name,
      form: 'Capsule',
      instructions: 'Exact instructions',
      notes: '',
    );
    final saved = await edit();
    final replay = await edit();
    expect(replay.revision, saved.revision);
    expect((await store.itemById(item.id))!.revision, item.revision + 1);
    expect((await store.itemById(item.id))!.name, 'Completed name');
    final old = (await store.recordById(dose.id))!;
    expect(old.name, item.name);
    expect(old.form, item.form);
    expect(old.actualAmount, ExactAmount.parseEntry('0.125'));
    expect(old.actualUnit, 'mg');
    final conflict = throwsA(
      isA<CommandConflict>().having((e) => e.code, 'code', 'revision'),
    );
    await expectLater(edit(command: 'stale', name: 'Stale'), conflict);
    expect((await store.itemDetail(item.id))!.revision, saved.revision);
    expect((await store.itemById(item.id))!.name, 'Completed name');
    await expectLater(
      store.saveItemDetail(
        commandId: 'old-detail',
        itemId: item.id,
        expectedRevision: 0,
        expectedItemRevision: item.revision + 1,
        name: 'Rejected',
        form: 'Liquid',
        instructions: '',
        notes: '',
      ),
      conflict,
    );
    expect((await store.itemById(item.id))!.name, 'Completed name');
  });

  test('detail revisions fence stale writers and command reuse', () async {
    final item = await createItem();
    final first = await saveDetail(
      itemId: item.id,
      instructions: 'Original instructions',
      notes: 'Original note',
    );

    await expectLater(
      saveDetail(
        command: 'implicit-overwrite',
        itemId: item.id,
        instructions: 'Replacement',
        expectedRevision: null,
      ),
      throwsA(
        isA<CommandConflict>().having(
          (error) => error.code,
          'code',
          'revision',
        ),
      ),
    );
    await expectLater(
      saveDetail(
        command: 'stale-write',
        itemId: item.id,
        instructions: 'Stale',
        expectedRevision: 0,
      ),
      throwsA(
        isA<CommandConflict>().having(
          (error) => error.code,
          'code',
          'revision',
        ),
      ),
    );

    final second = await saveDetail(
      command: 'detail-second',
      itemId: item.id,
      instructions: 'Corrected instructions',
      notes: 'Corrected note',
      expectedRevision: first.revision,
    );
    expect(second.revision, 2);
    expect(
      (await store.itemDetail(item.id))!.instructions,
      'Corrected instructions',
    );

    await expectLater(
      saveDetail(
        command: 'detail-second',
        itemId: item.id,
        instructions: 'Different payload',
        notes: 'Corrected note',
        expectedRevision: first.revision,
      ),
      throwsA(
        isA<CommandConflict>().having((error) => error.code, 'code', 'payload'),
      ),
    );

    final replay = await saveDetail(
      command: 'detail-second',
      itemId: item.id,
      instructions: 'Corrected instructions',
      notes: 'Corrected note',
      expectedRevision: first.revision,
    );
    expect(replay.revision, 2);
    expect(replay.updatedAt, second.updatedAt);
  });

  test(
    'setup skips accumulate and completion is durable without records',
    () async {
      final item = await createItem();

      final schedule = await updateSetup(itemId: item.id, skipSchedule: true);
      expect(schedule.scheduleSkipped, isTrue);
      expect(schedule.stockSkipped, isFalse);
      expect(schedule.isComplete, isFalse);

      final rest = await updateSetup(
        command: 'setup-rest',
        itemId: item.id,
        skipStock: true,
        skipDetails: true,
      );
      expect(rest.scheduleSkipped, isTrue);
      expect(rest.stockSkipped, isTrue);
      expect(rest.detailsSkipped, isTrue);
      expect(rest.isComplete, isFalse);

      final completed = await updateSetup(
        command: 'setup-complete',
        itemId: item.id,
        complete: true,
      );
      expect(completed.isComplete, isTrue);

      final replay = await updateSetup(
        command: 'setup-complete',
        itemId: item.id,
        complete: true,
      );
      expect(replay.isComplete, isTrue);
      expect(replay.completedAt, completed.completedAt);

      await store.close();
      store = await RecordStore.open(path: path, key: key, isNew: false);
      final reopened = (await store.itemSetup(item.id))!;
      expect(reopened.isComplete, isTrue);
      expect(reopened.scheduleSkipped, isTrue);
      expect(await store.dailyPlans(), isEmpty);
      expect(await store.stockContainers(personId: meId), isEmpty);
    },
  );

  test('lock blocks setup and detail writes without losing progress', () async {
    final item = await createItem();
    await updateSetup(itemId: item.id, skipSchedule: true);
    await saveDetail(itemId: item.id, notes: 'Kept while locked');

    store.suspendWrites(true);
    await expectLater(
      updateSetup(command: 'locked-setup', itemId: item.id, skipStock: true),
      throwsA(
        isA<CommandConflict>().having(
          (error) => error.code,
          'code',
          'app_locked',
        ),
      ),
    );
    await expectLater(
      saveDetail(
        command: 'locked-detail',
        itemId: item.id,
        notes: 'Must not enter',
        expectedRevision: 1,
      ),
      throwsA(
        isA<CommandConflict>().having(
          (error) => error.code,
          'code',
          'app_locked',
        ),
      ),
    );
    store.suspendWrites(false);

    final setup = (await store.itemSetup(item.id))!;
    expect(setup.scheduleSkipped, isTrue);
    expect(setup.stockSkipped, isFalse);
    expect((await store.itemDetail(item.id))!.notes, 'Kept while locked');
  });

  test('captured setup and detail commands reject another dataset', () async {
    final item = await createItem();
    final conflict = throwsA(
      isA<CommandConflict>().having((e) => e.code, 'code', 'generation'),
    );
    await expectLater(
      store.updateItemSetup(
        commandId: 'stale-setup',
        itemId: item.id,
        expectedGeneration: 'retired-dataset',
        skipStock: true,
      ),
      conflict,
    );
    await expectLater(
      store.saveItemDetail(
        commandId: 'stale-detail',
        itemId: item.id,
        expectedGeneration: 'retired-dataset',
        expectedRevision: null,
        instructions: 'Stale text',
        notes: '',
      ),
      conflict,
    );
    expect((await store.itemSetup(item.id))!.stockSkipped, isFalse);
    expect(await store.itemDetail(item.id), isNull);
  });

  test('a replaced dataset generation retires stale setup progress', () async {
    final item = await createItem();
    await updateSetup(itemId: item.id, skipSchedule: true);
    await saveDetail(itemId: item.id, instructions: 'Kept across replacement');

    await store.close();
    final db = raw();
    try {
      db.execute("UPDATE item_setup SET generation='previous-dataset'");
    } finally {
      db.close();
    }
    store = await RecordStore.open(path: path, key: key, isNew: false);

    expect(await store.itemSetup(item.id), isNull);
    expect(await store.itemDetail(item.id), isNotNull);
    final restarted = await updateSetup(
      command: 'new-generation-setup',
      itemId: item.id,
      skipStock: true,
    );
    expect(restarted.scheduleSkipped, isFalse);
    expect(restarted.stockSkipped, isTrue);
  });

  test('deleting the profile removes setup and authored detail', () async {
    final item = await createItem();
    await updateSetup(itemId: item.id, skipSchedule: true, complete: true);
    await saveDetail(
      itemId: item.id,
      instructions: 'Private',
      notes: 'Private',
    );

    await store.deleteProfile(
      commandId: 'delete-profile',
      personId: meId,
      expectedRevision: 1,
    );

    expect(await store.itemDetail(item.id), isNull);
    expect(await store.itemSetup(item.id), isNull);
    expect(await store.items(), isEmpty);
    final db = raw();
    try {
      expect(db.select('SELECT count(*) c FROM item_detail').single['c'], 0);
      expect(db.select('SELECT count(*) c FROM item_setup').single['c'], 0);
    } finally {
      db.close();
    }
  });

  test('report capture includes details only with notes selected', () async {
    final item = await createItem();
    await store.record(
      commandId: 'dose',
      itemId: item.id,
      amount: '1',
      actualAt: DateTime.utc(2026, 10, 20, 8),
    );
    await saveDetail(
      itemId: item.id,
      instructions: 'Use the labelled amount: 0.125 mg.',
      notes: 'Private observation',
    );
    ReportSelection selection({required bool includeNotes}) => ReportSelection(
      personId: meId,
      fromDate: CivilDate(2026, 10, 1),
      beforeDate: CivilDate(2026, 11, 1),
      displayZone: 'UTC',
      includeNotes: includeNotes,
    );

    final hidden = await store.captureReport(
      selection: selection(includeNotes: false),
      now: () => DateTime.utc(2026, 10, 21),
    );
    expect(hidden.snapshot.itemDetails, isEmpty);
    final hiddenText = ReportText.build(
      snapshot: hidden.snapshot,
      use24Hour: true,
    );
    expect(hiddenText, isNot(contains('0.125 mg')));
    expect(hiddenText, isNot(contains('Private observation')));

    final shown = await store.captureReport(
      selection: selection(includeNotes: true),
      now: () => DateTime.utc(2026, 10, 21),
    );
    expect(
      shown.snapshot.itemDetails[item.id]!.instructions,
      contains('0.125 mg'),
    );
    expect(shown.snapshot.itemDetails[item.id]!.notes, 'Private observation');
    final shownText = ReportText.build(
      snapshot: shown.snapshot,
      use24Hour: true,
    );
    expect(
      shownText,
      contains('Instructions: Use the labelled amount: 0.125 mg.'),
    );
    expect(shownText, contains('Private note: Private observation'));
  });
}
