import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:true_grit_vital/data/record_store.dart';

void main() {
  late Directory directory;
  late RecordStore store;
  final key = List.generate(32, (i) => i + 1);
  late String path;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('vital-record-test-');
    path = '${directory.path}/records.db';
    store = await RecordStore.open(path: path, key: key, isNew: true);
  });
  tearDown(() async {
    await store.close();
    await directory.delete(recursive: true);
  });
  Future<SubstanceItem> item() => store.createItem(
    commandId: 'item',
    name: 'Synthetic snapshot',
    form: 'tablet',
    unit: 'mg',
    type: 'medicine',
  );
  Future<UseRecord> record(
    String id, {
    String amount = '0.125000',
    bool fail = false,
  }) async => store.record(
    commandId: id,
    itemId: (await item()).id,
    amount: amount,
    actualAt: DateTime.utc(2026, 10, 19),
    failBeforeCommit: fail,
  );
  test('exact quantity envelope rejects ambiguous and overflow input', () {
    expect(ExactQuantity.parse('0001.230000').canonical, '1.23');
    expect(ExactQuantity.parse('0.000001').scaled, 1);
    for (final value in [
      '0',
      '-1',
      '1,2',
      '1e2',
      '0.0000001',
      '9000000000.000001',
    ]) {
      expect(() => ExactQuantity.parse(value), throwsA(anything));
    }
  });
  test(
    'encrypted restart preserves owner, snapshots and idempotent result',
    () async {
      final original = await record('take');
      await store.writeSetting('appearance', 'dark');
      await store.close();
      final bytes = await File(path).readAsBytes();
      expect(String.fromCharCodes(bytes).contains('Synthetic snapshot'), false);
      expect(String.fromCharCodes(bytes).startsWith('SQLite format 3'), false);
      store = await RecordStore.open(path: path, key: key, isNew: false);
      final retry = await record('take');
      expect(retry.id, original.id);
      expect(retry.alreadyCommitted, true);
      expect(retry.enteredAmount, '0.125000');
      expect(retry.amount.canonical, '0.125');
      expect(retry.personId, meId);
      expect(await store.readSetting('appearance'), 'dark');
      expect((await store.records()).length, 1);
      await expectLater(
        record('take', amount: '2'),
        throwsA(isA<CommandConflict>()),
      );
    },
  );
  test('correction, competing revision and Undo preserve history', () async {
    final first = await record('take');
    final second = await store.correct(
      commandId: 'correct',
      recordId: first.id,
      expectedRevision: 1,
      amount: '0.5',
      actualAt: first.actualAt,
    );
    await expectLater(
      store.correct(
        commandId: 'stale',
        recordId: first.id,
        expectedRevision: 1,
        amount: '3',
        actualAt: first.actualAt,
      ),
      throwsA(isA<CommandConflict>()),
    );
    final undone = await store.voidRecord(
      commandId: 'undo',
      recordId: first.id,
      expectedRevision: second.revision,
    );
    expect(undone.isVoided, true);
    final replay = await store.voidRecord(
      commandId: 'undo',
      recordId: first.id,
      expectedRevision: second.revision,
    );
    expect(replay.alreadyCommitted, true);
    expect((await store.history(first.id)).map((r) => r.enteredAmount), [
      '0.125000',
      '0.5',
      '0.5',
    ]);
    await expectLater(
      store.voidRecord(
        commandId: 'again',
        recordId: first.id,
        expectedRevision: 3,
      ),
      throwsA(isA<CommandConflict>()),
    );
  });
  test('competing independent connections commit one correction', () async {
    final first = await record('take');
    final other = await RecordStore.open(path: path, key: key, isNew: false);
    try {
      Future<String> attempt(RecordStore db, String id) async {
        try {
          await db.correct(
            commandId: id,
            recordId: first.id,
            expectedRevision: 1,
            amount: '2',
            actualAt: first.actualAt,
          );
          return 'saved';
        } on CommandConflict {
          return 'conflict';
        }
      }

      expect(
        await Future.wait([attempt(store, 'a'), attempt(other, 'b')]),
        containsAll(['saved', 'conflict']),
      );
      expect((await store.history(first.id)).length, 2);
    } finally {
      await other.close();
    }
  });
  test('ownership rejects mixed references and revisions', () async {
    final first = await record('take');
    await expectLater(
      store.record(
        commandId: 'wrong',
        itemId: first.itemId,
        amount: '1',
        actualAt: first.actualAt,
        personId: 'other',
      ),
      throwsA(isA<CommandConflict>()),
    );
    await expectLater(
      store.voidRecord(
        commandId: 'wrong2',
        recordId: first.id,
        expectedRevision: 1,
        personId: 'other',
      ),
      throwsA(isA<CommandConflict>()),
    );
  });
  test(
    'interrupted commit and failed settings never announce durable state',
    () async {
      await expectLater(record('take', fail: true), throwsA(isA<StateError>()));
      expect(await store.records(), isEmpty);
      final success = await record('take');
      expect(success.revision, 1);
      await store.writeSetting('appearance', 'light');
      await expectLater(
        store.writeSetting('appearance', 'dark', failBeforeCommit: true),
        throwsA(isA<StateError>()),
      );
      expect(await store.readSetting('appearance'), 'light');
    },
  );
  test(
    'wrong, missing, truncated and corrupted datasets fail closed',
    () async {
      await record('take');
      await store.close();
      final before = await File(path).readAsBytes();
      await expectLater(
        RecordStore.open(path: path, key: List.filled(32, 2), isNew: false),
        throwsA(anything),
      );
      expect(await File(path).readAsBytes(), before);
      await expectLater(
        RecordStore.open(path: path, key: [], isNew: false),
        throwsA(anything),
      );
      await expectLater(
        RecordStore.open(
          path: '${directory.path}/missing',
          key: key,
          isNew: false,
        ),
        throwsA(anything),
      );
      expect(await File('${directory.path}/missing').exists(), false);
      final broken = '${directory.path}/broken';
      await File(broken).writeAsBytes([1, 2, 3]);
      await expectLater(
        RecordStore.open(path: broken, key: key, isNew: false),
        throwsA(anything),
      );
      await File(broken).writeAsBytes(List.filled(4096, 7));
      await expectLater(
        RecordStore.open(path: broken, key: key, isNew: false),
        throwsA(anything),
      );
      expect(await File(broken).readAsBytes(), List.filled(4096, 7));
      store = await RecordStore.open(path: path, key: key, isNew: false);
    },
  );
  test(
    'populated v1 migration preserves semantics and committed command result',
    () async {
      await store.close();
      await File(path).delete();
      final db = sqlite3.open(path);
      final hex = key.map((v) => v.toRadixString(16).padLeft(2, '0')).join();
      db.execute("PRAGMA cipher='chacha20'");
      db.execute("PRAGMA key=\"x'$hex'\"");
      db.execute(
        await File('test/data/fixtures/record_store_v1.sql').readAsString(),
      );
      db.close();
      store = await RecordStore.open(path: path, key: key, isNew: false);
      expect(store.generation, 'fixture-generation');
      final history = await store.history('record');
      expect(history.map((r) => r.enteredAmount), ['0.125000', '0.5']);
      expect(history.last.isVoided, true);
      expect(history.first.name, 'Original snapshot');
      expect((await store.items()).single.name, 'Current synthetic item');
      expect(
        (await store.records(personId: 'other')).single.name,
        'Other snapshot',
      );
      final retry = await store.record(
        commandId: 'fixture-operation',
        itemId: 'item',
        amount: '0.125000',
        actualAt: DateTime.fromMicrosecondsSinceEpoch(
          1792368000000000,
          isUtc: true,
        ),
      );
      expect(retry.alreadyCommitted, true);
      expect(retry.revision, 1);
      expect(retry.isVoided, false);
      await store.writeSetting('appearance', 'system');
      await store.close();
      store = await RecordStore.open(path: path, key: key, isNew: false);
      expect(await store.readSetting('appearance'), 'system');
      expect((await store.history('record')).length, 2);
    },
  );
  test(
    'failed populated migration preserves the recoverable v1 dataset',
    () async {
      final failedPath = '${directory.path}/migration.db';
      final db = sqlite3.open(failedPath);
      final hex = key.map((v) => v.toRadixString(16).padLeft(2, '0')).join();
      db.execute("PRAGMA cipher='chacha20'");
      db.execute("PRAGMA key=\"x'$hex'\"");
      db.execute(
        await File('test/data/fixtures/record_store_v1.sql').readAsString(),
      );
      // Simulate a schema obstacle at the actual migration statement.
      db.execute(
        'CREATE TABLE setting(key TEXT PRIMARY KEY,value TEXT NOT NULL) STRICT',
      );
      db.close();
      await expectLater(
        RecordStore.open(path: failedPath, key: key, isNew: false),
        throwsA(anything),
      );
      final recovered = sqlite3.open(failedPath);
      recovered.execute("PRAGMA cipher='chacha20'");
      recovered.execute("PRAGMA key=\"x'$hex'\"");
      expect(recovered.select('PRAGMA user_version').single.values.single, 1);
      expect(
        recovered
            .select('SELECT entered FROM revision ORDER BY record,revision')
            .map((r) => r['entered']),
        ['1', '0.125000', '0.5'],
      );
      expect(recovered.select('SELECT * FROM operation').length, 1);
      recovered.close();
    },
  );
  test(
    'populated v2 migration preserves settings and adds bounded feed index',
    () async {
      final v2path = '${directory.path}/v2.db';
      final db = sqlite3.open(v2path);
      final hex = key.map((v) => v.toRadixString(16).padLeft(2, '0')).join();
      db.execute("PRAGMA cipher='chacha20'");
      db.execute("PRAGMA key=\"x'$hex'\"");
      db.execute(
        await File('test/data/fixtures/record_store_v1.sql').readAsString(),
      );
      db.execute(
        "CREATE TABLE setting(key TEXT PRIMARY KEY,value TEXT NOT NULL) STRICT; INSERT INTO setting VALUES ('appearance','dark'); PRAGMA user_version=2;",
      );
      db.close();
      final migrated = await RecordStore.open(
        path: v2path,
        key: key,
        isNew: false,
      );
      try {
        expect(await migrated.readSetting('appearance'), 'dark');
        expect((await migrated.recordById('record'))?.isVoided, true);
        expect((await migrated.records(limit: 1)).single.id, 'record');
        expect((await migrated.history('record')).length, 2);
      } finally {
        await migrated.close();
      }
    },
  );
  test(
    'time corrections update indexed day filters without rewriting history',
    () async {
      final first = await record('take');
      final nextDay = first.actualAt.add(const Duration(days: 1));
      await store.correct(
        commandId: 'move',
        recordId: first.id,
        expectedRevision: 1,
        amount: '0.5',
        actualAt: nextDay,
      );
      expect(
        await store.records(actualFrom: first.actualAt, actualBefore: nextDay),
        isEmpty,
      );
      expect(
        (await store.records(
          actualFrom: nextDay,
          itemId: first.itemId,
        )).single.id,
        first.id,
      );
      expect((await store.history(first.id)).first.actualAt, first.actualAt);
      expect((await store.recordById(first.id))?.actualAt, nextDay);
      expect(await store.recordCount(actualFrom: nextDay), 1);
      await expectLater(store.records(limit: 501), throwsRangeError);
    },
  );
}
