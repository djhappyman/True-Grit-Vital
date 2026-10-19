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
    directory = await Directory.systemTemp.createTemp('vital-profile-test-');
    path = '${directory.path}/records.db';
    store = await RecordStore.open(path: path, key: key, isNew: true);
  });
  tearDown(() async {
    await store.close();
    await directory.delete(recursive: true);
  });
  Future<AdultProfile> adult(String command) => store.createProfile(
    commandId: command,
    name: 'Alex Example',
    adultConfirmed: true,
  );
  Future<SubstanceItem> item(AdultProfile p, String command) =>
      store.createItem(
        commandId: command,
        personId: p.id,
        expectedPersonRevision: p.revision,
        name: 'Synthetic',
        form: 'tablet',
        unit: 'mg',
        type: 'medicine',
      );
  Future<UseRecord> record(AdultProfile p, SubstanceItem i, String command) =>
      store.record(
        commandId: command,
        personId: p.id,
        expectedPersonRevision: p.revision,
        itemId: i.id,
        amount: '1',
        actualAt: DateTime.utc(2026, 10, 19),
      );

  test(
    'adult confirmation, optional details, similar names and encrypted restart',
    () async {
      await expectLater(
        store.createProfile(
          commandId: 'minor',
          name: 'Alex',
          adultConfirmed: false,
        ),
        throwsA(isA<FormatException>()),
      );
      final a = await adult('a');
      final b = await adult('b');
      expect(a.id, isNot(b.id));
      expect((await adult('a')).id, a.id);
      final edited = await store.editProfile(
        commandId: 'edit',
        personId: a.id,
        expectedRevision: a.revision,
        name: 'Alex Example',
        adultConfirmed: true,
        reportName: 'Alexander Example',
        relationship: 'friend',
        notes: 'Synthetic private note',
      );
      expect(edited.id, a.id);
      await store.saveBrowsingScope(FeedScope.person(a.id));
      await store.close();
      expect(
        String.fromCharCodes(await File(path).readAsBytes())
            .contains('Synthetic private note'),
        false,
      );
      store = await RecordStore.open(path: path, key: key, isNew: false);
      expect(await store.readBrowsingScope(), FeedScope.person(a.id));
      expect((await store.profileById(a.id))!.reportName, 'Alexander Example');
      expect((await store.profileById(b.id))!.reportName, null);
      expect((await store.profileById(meId))!.isMe, true);
    },
  );

  test('captured owner, bounded Everyone, archive and reactivation never resume plans', () async {
    final a = await adult('a');
    final b = await adult('b');
    final ai = await item(a, 'ai');
    final bi = await item(b, 'bi');
    final ar = await record(a, ai, 'ar');
    expect(ar.source, RecordSource.recordedOnBehalf);
    await record(b, bi, 'br');
    await expectLater(record(b, ai, 'wrong'), throwsA(isA<CommandConflict>()));
    await store.saveBrowsingScope(FeedScope.person(a.id));
    expect(
      (await store.records(scope: const FeedScope.everyone(), limit: 1)).length,
      1,
    );
    expect(await store.recordCount(scope: const FeedScope.everyone()), 2);
    final archived = await store.archiveProfile(
      commandId: 'archive',
      personId: a.id,
      expectedRevision: a.revision,
    );
    expect(await store.readBrowsingScope(), const FeedScope.everyone());
    expect(
      (await store.records(scope: const FeedScope.everyone())).single.personId,
      b.id,
    );
    expect(
      (await store.items(scope: const FeedScope.everyone())).single.personId,
      b.id,
    );
    expect((await store.records(personId: a.id)).single.id, ar.id);
    expect((await store.profiles()).any((p) => p.id == a.id), false);
    await expectLater(record(a, ai, 'stale'), throwsA(isA<CommandConflict>()));
    await expectLater(
      store.correct(
        commandId: 'archived-correction',
        personId: a.id,
        recordId: ar.id,
        expectedRevision: ar.revision,
        amount: '2',
        actualAt: ar.actualAt,
      ),
      throwsA(isA<CommandConflict>()),
    );
    final resumed = await store.reactivateProfile(
      commandId: 'reactivate',
      personId: a.id,
      expectedRevision: archived.revision,
    );
    expect(resumed.remindersStopped, true);
    expect((await store.reminderStopIntents())[a.id], resumed.revision);
    await expectLater(
      record(a, ai, 'stale-after-reactivate'),
      throwsA(isA<CommandConflict>()),
    );
    expect((await store.records(personId: a.id)).length, 1);
    await record(resumed, ai, 'fresh');
    await expectLater(
      store.records(scope: const FeedScope.everyone(), limit: 501),
      throwsA(isA<RangeError>()),
    );
  });

  test(
    'deletion removes only selected graph, invalidates retries and keeps Me',
    () async {
      final a = await adult('a');
      final b = await adult('b');
      final namedLikeId = await store.createProfile(
        commandId: 'name-like-id',
        name: a.id,
        adultConfirmed: true,
      );
      final ai = await item(a, 'ai');
      final bi = await item(b, 'bi');
      final ar = await record(a, ai, 'ar');
      await record(b, bi, 'br');
      await store.deleteProfile(
        commandId: 'delete',
        personId: a.id,
        expectedRevision: a.revision,
      );
      expect(await store.profileById(a.id), null);
      expect(
        (await store.createProfile(
          commandId: 'name-like-id',
          name: a.id,
          adultConfirmed: true,
        )).id,
        namedLikeId.id,
      );
      expect(await store.history(ar.id), isEmpty);
      expect((await store.records(personId: b.id)).length, 1);
      await expectLater(record(a, ai, 'ar'), throwsA(isA<CommandConflict>()));
      await expectLater(adult('a'), throwsA(isA<CommandConflict>()));
      final me = (await store.profileById(meId))!;
      final mi = await item(me, 'mi');
      await record(me, mi, 'mr');
      await store.deleteProfile(
        commandId: 'delete-me',
        personId: meId,
        expectedRevision: me.revision,
      );
      expect((await store.profileById(meId))!.revision, me.revision + 1);
      expect(await store.items(), isEmpty);
      await expectLater(item(me, 'mi'), throwsA(isA<CommandConflict>()));
      await expectLater(
        store.archiveProfile(
          commandId: 'archive-me',
          personId: meId,
          expectedRevision: me.revision + 1,
        ),
        throwsA(isA<CommandConflict>()),
      );
      // A second deletion does not parse invalidated command contents as live operations.
      await store.deleteProfile(
        commandId: 'delete-me-again',
        personId: meId,
        expectedRevision: me.revision + 1,
      );
      final raw = sqlite3.open(path);
      final hex = key.map((v) => v.toRadixString(16).padLeft(2, '0')).join();
      raw.execute("PRAGMA cipher='chacha20'");
      raw.execute("PRAGMA key=\"x'$hex'\"");
      for (final command in ['a', 'ai', 'ar', 'mi', 'mr']) {
        final op = raw.select(
          'SELECT payload,result FROM operation WHERE id=?',
          [command],
        ).single;
        expect(op['payload'], '[]');
        expect(op['result'], '{"invalidated":true}');
      }
      expect(
        raw
            .select("SELECT result FROM operation WHERE id='br'")
            .single['result'],
        contains(b.id),
      );
      raw.close();
    },
  );

  test(
    'independent connection lifecycle race rejects captured stale write',
    () async {
      final a = await adult('a');
      final ai = await item(a, 'ai');
      final other = await RecordStore.open(path: path, key: key, isNew: false);
      try {
        await other.archiveProfile(
          commandId: 'archive',
          personId: a.id,
          expectedRevision: a.revision,
        );
        await expectLater(
          record(a, ai, 'stale'),
          throwsA(isA<CommandConflict>()),
        );
        await expectLater(
          store.editProfile(
            commandId: 'stale-edit',
            personId: a.id,
            expectedRevision: a.revision,
            name: 'Other',
            adultConfirmed: true,
          ),
          throwsA(isA<CommandConflict>()),
        );
      } finally {
        await other.close();
      }
    },
  );

  test('frozen populated v3 migration and restart preserve records and stable identities', () async {
    await store.close();
    await File(path).delete();
    final db = sqlite3.open(path);
    final hex = key.map((v) => v.toRadixString(16).padLeft(2, '0')).join();
    db.execute("PRAGMA cipher='chacha20'");
    db.execute("PRAGMA key=\"x'$hex'\"");
    db.execute(
      await File('test/data/fixtures/record_store_v3.sql').readAsString(),
    );
    db.close();
    store = await RecordStore.open(path: path, key: key, isNew: false);
    expect((await store.profiles()).map((p) => p.id).toSet(), {meId, 'other'});
    expect((await store.profileById(meId))!.adultConfirmed, false);
    expect((await store.records(scope: const FeedScope.everyone())).length, 2);
    expect((await store.history('record')).length, 2);
    expect(
      (await store.history('record')).first.source,
      RecordSource.unspecified,
    );
    expect(await store.readSetting('appearance'), 'dark');
    expect(store.generation, 'fixture-generation');
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
    expect(replay.source, RecordSource.unspecified);
    expect(replay.revision, 1);

    await store.close();
    store = await RecordStore.open(path: path, key: key, isNew: false);
    expect((await store.profileById('other'))!.name, 'Synthetic other');
  });
  test('competing lifecycle commands commit one revision and failed command emits no success', () async {
    final a = await adult('a');
    final emissions = <List<AdultProfile>>[];
    final subscription = store
        .watchProfiles(includeArchived: true)
        .listen(emissions.add);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    final before = emissions.length;
    await expectLater(
      store.archiveProfile(
        commandId: 'bad',
        personId: a.id,
        expectedRevision: 999,
      ),
      throwsA(isA<CommandConflict>()),
    );
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(emissions.length, before);
    final results = await Future.wait([
      store
          .archiveProfile(
            commandId: 'race-1',
            personId: a.id,
            expectedRevision: a.revision,
          )
          .then<Object>((v) => v, onError: (Object e) => e),
      store
          .archiveProfile(
            commandId: 'race-2',
            personId: a.id,
            expectedRevision: a.revision,
          )
          .then<Object>((v) => v, onError: (Object e) => e),
    ]);
    expect(results.whereType<AdultProfile>().length, 1);
    expect(results.whereType<CommandConflict>().length, 1);
    await subscription.cancel();
  });

  test('failed v3 profile migration rolls back all new columns and retains history', () async {
    final migrationPath = '${directory.path}/failed-v3.db';
    final db = sqlite3.open(migrationPath);
    final hex = key.map((v) => v.toRadixString(16).padLeft(2, '0')).join();
    db.execute("PRAGMA cipher='chacha20'");
    db.execute("PRAGMA key=\"x'$hex'\"");
    db.execute(
      await File('test/data/fixtures/record_store_v3.sql').readAsString(),
    );
    db.execute('CREATE TABLE reminder_stop(obstacle TEXT) STRICT');
    db.close();
    await expectLater(
      RecordStore.open(path: migrationPath, key: key, isNew: false),
      throwsA(anything),
    );
    final recovered = sqlite3.open(migrationPath);
    recovered.execute("PRAGMA cipher='chacha20'");
    recovered.execute("PRAGMA key=\"x'$hex'\"");
    expect(recovered.select('PRAGMA user_version').single.values.single, 3);
    expect(recovered.select('SELECT * FROM revision').length, 3);
    expect(
      recovered.select('PRAGMA table_info(person)').map((r) => r['name']),
      ['id', 'name'],
    );
    recovered.close();
  });
  test('new provenance survives correction and encrypted reopen', () async {
    final me = (await store.profileById(meId))!;
    final mi = await item(me, 'mi');
    final mr = await record(me, mi, 'mr');
    expect(mr.source, RecordSource.selfReported);
    await store.correct(
      commandId: 'correct-source',
      recordId: mr.id,
      expectedRevision: 1,
      amount: '2',
      actualAt: mr.actualAt,
    );
    await store.close();
    store = await RecordStore.open(path: path, key: key, isNew: false);
    expect(
      (await store.history(mr.id)).map((r) => r.source),
      everyElement(RecordSource.selfReported),
    );
  });
  test('100k archived-skewed history and 511 active adults keep Everyone pages bounded', () async {
    await store.close();
    await File(path).delete();
    final raw = sqlite3.open(path);
    final hex = key.map((v) => v.toRadixString(16).padLeft(2, '0')).join();
    raw.execute("PRAGMA cipher='chacha20'");
    raw.execute("PRAGMA key=\"x'$hex'\"");
    raw.execute(
      await File('test/data/fixtures/record_store_v3.sql').readAsString(),
    );
    final head = raw.prepare('INSERT INTO administration VALUES (?,?,?,1,?)');
    final revision = raw.prepare(
      'INSERT INTO revision VALUES (?,?,1,?,?,?,?,?,?,?,?,0)',
    );
    try {
      raw.execute('BEGIN');
      for (var n = 0; n < 100000; n++) {
        final owner = n < 95000 ? 'other' : meId;
        final id = 'skew-${n.toString().padLeft(6, '0')}';
        final actual = 1792368000000000 + n;
        head.execute([
          id,
          owner,
          owner == meId ? 'item' : 'other-item',
          actual,
        ]);
        revision.execute([
          id,
          owner,
          'Synthetic workload',
          'tablet',
          'mg',
          'medicine',
          1000000,
          '1',
          actual,
          actual,
        ]);
      }
      for (var n = 0; n < 510; n++) {
        raw.execute('INSERT INTO person VALUES (?,?)', [
          'empty-$n',
          'Synthetic empty $n',
        ]);
      }
      raw.execute('COMMIT');
    } finally {
      head.close();
      revision.close();
      raw.close();
    }
    store = await RecordStore.open(path: path, key: key, isNew: false);
    await store.archiveProfile(
      commandId: 'archive-skew',
      personId: 'other',
      expectedRevision: 1,
    );
    final timer = Stopwatch()..start();
    final first = await store.records(
      scope: const FeedScope.everyone(),
      limit: 50,
    );
    final micros = timer.elapsedMicroseconds;
    expect(first.length, 50);
    expect(first.every((r) => r.personId == meId), true);
    expect(first.first.id, 'skew-099999');
    final second = await store.records(
      scope: const FeedScope.everyone(),
      limit: 50,
      offset: 50,
    );
    expect(
      second
          .map((r) => r.id)
          .toSet()
          .intersection(first.map((r) => r.id).toSet()),
      isEmpty,
    );
    expect(second.first.id, 'skew-099949');
    await store.close();
    final plans = sqlite3.open(path);
    plans.execute("PRAGMA cipher='chacha20'");
    plans.execute("PRAGMA key=\"x'$hex'\"");
    const projection =
        'SELECT a.id,a.item,r.*,s.source FROM administration a JOIN revision r ON r.record=a.id AND r.person=a.person AND r.revision=a.revision LEFT JOIN revision_source s ON s.record=r.record AND s.revision=r.revision';
    final explain = plans
        .select(
          'EXPLAIN QUERY PLAN SELECT * FROM ($projection WHERE a.person=? ORDER BY a.actual DESC,a.id LIMIT ?) UNION ALL SELECT * FROM ($projection WHERE a.person=? ORDER BY a.actual DESC,a.id LIMIT ?) ORDER BY actual DESC,id LIMIT ?',
          [meId, 50, 'empty-0', 50, 50],
        )
        .map((r) => r['detail'] as String)
        .toList();
    expect(explain.join(' '), contains('administration_feed'));
    // Each branch uses the person/time index. The outer merge sorts at most page-size rows per adult.
    final branch = plans
        .select(
          'EXPLAIN QUERY PLAN $projection WHERE a.person=? ORDER BY a.actual DESC,a.id LIMIT ?',
          [meId, 50],
        )
        .map((r) => r['detail'] as String)
        .join(' ');
    expect(branch, isNot(contains('TEMP B-TREE')));
    plans.close();
    // ignore: avoid_print
    print(
      'profile_100k: activeAdults=511 records=100002 archivedRecords=95001 firstPage=50 elapsedMicroseconds=$micros plans=$explain',
    );
    store = await RecordStore.open(path: path, key: key, isNew: false);
  });
  test('close drains active collection reads and closes watched feeds without errors', () async {
    final errors = <Object>[];
    final subscriptions = [
      store
          .watchRecords(scope: const FeedScope.everyone())
          .listen((_) {}, onError: errors.add),
      store.watchProfiles().listen((_) {}, onError: errors.add),
      store
          .watchItems(scope: const FeedScope.everyone())
          .listen((_) {}, onError: errors.add),
    ];
    await Future<void>.delayed(Duration.zero);
    await store.close();
    for (final subscription in subscriptions) {
      await subscription.cancel();
    }
    expect(errors, isEmpty);
    store = await RecordStore.open(path: path, key: key, isNew: false);
    expect((await store.profileById(meId))!.isMe, true);
  });
}
