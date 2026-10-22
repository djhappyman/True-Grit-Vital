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
    directory = await Directory.systemTemp.createTemp('vital-drafts-');
    path = '${directory.path}/records.db';
    store = await RecordStore.open(path: path, key: key, isNew: true);
  });
  tearDown(() async {
    await store.close();
    await directory.delete(recursive: true);
  });
  OrdinaryDraft draft({
    String person = meId,
    int revision = 1,
    String op = 'take',
    String id = 'draft',
    String? generation,
  }) => OrdinaryDraft(
    id: id,
    generation: generation ?? store.generation,
    operationId: op,
    kind: DraftKind.item,
    personId: person,
    personRevision: revision,
    targetId: null,
    targetRevision: null,
    fields: {
      'name': 'Synthetic private unfinished substance',
      'form': 'tablet',
      'unit': 'mg',
      'type': 'medicine',
    },
  );
  Future<SubstanceItem> save(String op) => store.createItem(
    commandId: op,
    name: 'Synthetic private unfinished substance',
    form: 'tablet',
    unit: 'mg',
    type: 'medicine',
  );
  test('quick creation drafts retain selected day and task across encrypted reopen', () async {
    final quick = OrdinaryDraft(
      id: 'quick-day',
      generation: store.generation,
      operationId: 'quick-create',
      kind: DraftKind.item,
      personId: meId,
      personRevision: 1,
      targetId: null,
      targetRevision: null,
      fields: {
        'name': 'Quick draft',
        'form': 'Not specified',
        'unit': 'mcg',
        'type': 'Medicine',
        'quick': 'true',
        'quickTime': '20:00',
        'day': '2026-10-20',
        'plan': 'true',
      },
    );
    await store.saveDraft(quick);
    await store.close();
    store = await RecordStore.open(path: path, key: key, isNew: false);
    final restored = (await store.drafts()).single;
    expect(restored.fields['unit'], 'mcg');
    final route = Uri.parse(restored.route);
    expect(route.path, '/unplanned');
    expect(route.queryParameters, {
      'new': '1',
      'plan': '1',
      'day': '2026-10-20',
      'time': '20:00',
    });
    expect(restored.operationId, 'quick-create');
  });

  test('encrypted unfinished entries survive reopen, save clears atomically, replay precedes stale owner', () async {
    await store.saveDraft(draft());
    await store.close();
    expect(
      String.fromCharCodes(await File(path).readAsBytes()),
      isNot(contains('Synthetic private unfinished substance')),
    );
    store = await RecordStore.open(path: path, key: key, isNew: false);
    expect(
      (await store.drafts()).single.fields['name'],
      'Synthetic private unfinished substance',
    );
    final result = await save('take');
    expect(await store.drafts(), isEmpty);
    await store.editProfile(
      commandId: 'edit',
      personId: meId,
      expectedRevision: 1,
      name: 'Me',
      adultConfirmed: true,
    );
    expect((await save('take')).id, result.id);
    expect(await store.operationCommitted('take'), true);
    await store.saveDraft(draft());
    expect(await store.drafts(), isEmpty);
  });
  test('lock rejects writes, failed or interrupted command keeps draft and original operation', () async {
    await store.saveDraft(draft());
    store.suspendWrites(true);
    await expectLater(save('take'), throwsA(isA<CommandConflict>()));
    await expectLater(
      store.saveDraft(draft(id: 'new', op: 'new')),
      throwsA(isA<CommandConflict>()),
    );
    store.suspendWrites(false);
    final item = await save('other-item');
    final dose = OrdinaryDraft(
      id: 'dose',
      generation: store.generation,
      operationId: 'dose-op',
      kind: DraftKind.dose,
      personId: meId,
      personRevision: 1,
      targetId: item.id,
      targetRevision: null,
      submitted: true,
      fields: {
        'amount': '0.125000',
        'date': '2026-10-19',
        'time': '12:00',
        'instant': '',
      },
    );
    await store.saveDraft(dose);
    await expectLater(
      store.record(
        commandId: 'dose-op',
        itemId: item.id,
        amount: '0.125000',
        actualAt: DateTime.utc(2026, 10, 19),
        failBeforeCommit: true,
      ),
      throwsStateError,
    );
    expect((await store.draftById('dose'))!.operationId, 'dose-op');
    expect(await store.records(), isEmpty);
    await expectLater(
      store.record(
        commandId: 'dose-op',
        itemId: item.id,
        amount: '0.125000',
        actualAt: DateTime.utc(2026, 10, 19),
        beforeCommit: () async => store.suspendWrites(true),
      ),
      throwsA(isA<CommandConflict>()),
    );
    store.suspendWrites(false);
    expect(await store.records(), isEmpty);
    expect(await store.draftById('dose'), isNotNull);
    await store.record(
      commandId: 'dose-op',
      itemId: item.id,
      amount: '0.125000',
      actualAt: DateTime.utc(2026, 10, 19),
    );
    expect(await store.draftById('dose'), isNull);
  });
  test('archive retains review draft, scoped deletion clears only owner and prevents stale Me resurrection', () async {
    final a = await store.createProfile(
      commandId: 'adult',
      name: 'Alex',
      adultConfirmed: true,
    );
    await store.saveDraft(draft(person: a.id, id: 'a', op: 'a-op'));
    await store.saveDraft(draft());
    await store.archiveProfile(
      commandId: 'archive',
      personId: a.id,
      expectedRevision: 1,
    );
    expect((await store.draftById('a'))!.personRevision, 1);
    await store.deleteProfile(
      commandId: 'delete',
      personId: a.id,
      expectedRevision: 2,
    );
    expect(await store.draftById('a'), null);
    expect(await store.draftById('draft'), isNotNull);
    await store.deleteProfile(
      commandId: 'delete-me',
      personId: meId,
      expectedRevision: 1,
    );
    expect(await store.drafts(), isEmpty);
    await expectLater(
      store.saveDraft(draft()),
      throwsA(isA<CommandConflict>()),
    );
    await expectLater(
      store.saveDraft(draft(generation: 'replaced')),
      throwsA(isA<CommandConflict>()),
    );
  });
  test(
    'closed snapshot format rejects passwords and out of bound fields',
    () async {
      expect(
        () => OrdinaryDraft(
          id: 'x',
          generation: 'g',
          operationId: 'o',
          kind: DraftKind.profile,
          personId: null,
          personRevision: null,
          targetId: null,
          targetRevision: null,
          fields: {'password': 'never'},
        ),
        throwsFormatException,
      );
      await store.saveDraft(draft());
      await store.discardDraft('draft');
      expect(await store.drafts(), isEmpty);
    },
  );
  test('captured final text persists behind lock; discarded callbacks cannot resurrect text', () async {
    final checkpoint = store.captureDraftCheckpoint(draft());
    store.suspendWrites(true);
    await checkpoint.persist();
    expect(
      () => store.captureDraftCheckpoint(draft(id: 'blocked', op: 'blocked')),
      throwsA(isA<CommandConflict>()),
    );
    store.suspendWrites(false);
    expect(
      (await store.drafts()).single.fields['name'],
      'Synthetic private unfinished substance',
    );
    final delayed = store.captureDraftCheckpoint(
      draft(op: 'pending', id: 'new-profile'),
    );
    await store.discardDraft('new-profile');
    await expectLater(delayed.persist(), throwsA(isA<CommandConflict>()));
    expect(await store.draftById('new-profile'), isNull);
    await expectLater(
      store.saveDraft(draft(op: 'collision')),
      throwsA(isA<CommandConflict>()),
    );
    expect((await store.drafts()).single.operationId, 'take');
  });
  test('frozen populated v4 migrates and reopens without changing provenance or identity', () async {
    await store.close();
    await File(path).delete();
    final db = sqlite3.open(path);
    final hex = key.map((v) => v.toRadixString(16).padLeft(2, '0')).join();
    db.execute("PRAGMA cipher='chacha20'");
    db.execute("PRAGMA key=\"x'$hex'\"");
    db.execute(
      await File('test/data/fixtures/record_store_v4.sql').readAsString(),
    );
    db.close();
    store = await RecordStore.open(path: path, key: key, isNew: false);
    expect(store.generation, 'fixture-generation');
    expect((await store.profileById('other'))!.revision, 3);
    expect(
      (await store.history('other-record')).single.source,
      RecordSource.recordedOnBehalf,
    );
    expect((await store.history('record')).map((r) => r.enteredAmount), [
      '0.125000',
      '0.5',
    ]);
    await store.saveDraft(draft(person: 'other', revision: 3));
    await store.close();
    store = await RecordStore.open(path: path, key: key, isNew: false);
    expect((await store.drafts()).single.personId, 'other');
  });
  test('v4 draft migration obstacle rolls back without replacing profiles or records', () async {
    final failedPath = '${directory.path}/migration-failure.db';
    final db = sqlite3.open(failedPath);
    final hex = key.map((v) => v.toRadixString(16).padLeft(2, '0')).join();
    db.execute("PRAGMA cipher='chacha20'");
    db.execute("PRAGMA key=\"x'$hex'\"");
    db.execute(
      await File('test/data/fixtures/record_store_v4.sql').readAsString(),
    );
    db.execute('CREATE TABLE ordinary_draft(obstacle TEXT) STRICT');
    db.close();
    await expectLater(
      RecordStore.open(path: failedPath, key: key, isNew: false),
      throwsA(anything),
    );
    final check = sqlite3.open(failedPath);
    check.execute("PRAGMA cipher='chacha20'");
    check.execute("PRAGMA key=\"x'$hex'\"");
    expect(check.select('PRAGMA user_version').single.values.single, 4);
    expect(check.select('SELECT * FROM revision').length, 3);
    expect(
      check.select("SELECT notes FROM person WHERE id='other'").single['notes'],
      'Synthetic profile secret',
    );
    check.close();
  });
}
