import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:true_grit_vital/data/record_store.dart';

/// Durable void/restore recovery through the real encrypted store.
///
/// A confirmed request is written as a closed draft before the domain command.
/// These tests use genuine SQLite files, close and reopen the store, and inject
/// failures at the existing transaction boundary rather than simulating it.
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

  LabPanelSnapshot panel(String id, {String person = meId}) => LabPanelSnapshot(
    id: SupportingRecordId(id: id, personId: person),
    title: 'Synthetic recovery report',
    collectionDate: SupportingDate.day(CivilDate(2026, 10, 19)),
    reportDate: SupportingDate.partial(
      originalText: 'October 2026',
      year: 2026,
      month: 10,
    ),
    provenance: SupportingProvenance(
      mode: SupportingProvenanceMode.manualTranscription,
      laboratoryId: 'recovery-lab',
      laboratoryName: 'Synthetic laboratory',
      methodId: 'recovery-method',
      specimenId: 'recovery-specimen',
    ),
    results: [
      LabResultSnapshot(
        id: 'result-$id',
        metricId: 'recovery-metric-$id',
        markerName: 'Synthetic marker',
        value: SupportingValue.numeric('1.50'),
        unit: 'mg/L',
      ),
    ],
  );

  Future<SupportingRevision> seedPanel(
    String id, {
    String person = meId,
    int personRevision = 1,
  }) => store.saveLabPanel(
    SaveLabPanelCommand(
      commandId: 'seed-$id',
      generation: store.generation,
      expectedPersonRevision: personRevision,
      panel: panel(id, person: person),
    ),
  );

  var intentCount = 0;
  OrdinaryDraft intent({
    String recordId = 'report',
    String personId = meId,
    int personRevision = 1,
    int recordRevision = 1,
    bool isVoided = true,
    String? generation,
    String? operation,
  }) {
    final id = operation ?? 'void-intent-${intentCount++}';
    return OrdinaryDraft.supportingVoid(
      id: id,
      operationId: id,
      generation: generation ?? store.generation,
      personId: personId,
      personRevision: personRevision,
      recordId: recordId,
      recordRevision: recordRevision,
      isVoided: isVoided,
    );
  }

  VoidSupportingRecordCommand commandFor(OrdinaryDraft draft) =>
      VoidSupportingRecordCommand(
        commandId: draft.operationId,
        generation: draft.generation,
        personId: draft.personId!,
        id: draft.targetId!,
        expectedPersonRevision: draft.personRevision!,
        expectedRevision: draft.targetRevision!,
        isVoided: draft.fields['isVoided'] == 'true',
      );

  Matcher conflict(String code) =>
      isA<CommandConflict>().having((e) => e.code, 'code', code);

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('vital-void-recovery-');
    path = '${directory.path}/db';
    store = await RecordStore.open(path: path, key: key, isNew: true);
    await seedPanel('report');
  });
  tearDown(() async {
    await store.close();
    await directory.delete(recursive: true);
  });

  test(
    'restart before commit keeps the exact intent and commits once',
    () async {
      final draft = intent(operation: 'stable-void');
      await store.saveDraft(draft);
      await store.close();
      store = await RecordStore.open(path: path, key: key, isNew: false);

      final reopened = (await store.drafts()).single;
      expect(reopened.kind, DraftKind.supportingVoid);
      expect(reopened.operationId, 'stable-void');
      expect(reopened.personId, meId);
      expect(reopened.targetId, 'report');
      expect(reopened.personRevision, 1);
      expect(reopened.targetRevision, 1);
      expect(reopened.fields, {'isVoided': 'true'});
      expect(reopened.route, '/supporting/$meId/report?resume=stable-void');

      final committed = await store.resumeSupportingVoidDraft(reopened);
      expect(committed.revision, 2);
      expect(committed.isVoided, isTrue);
      expect(await store.drafts(), isEmpty);

      await store.close();
      store = await RecordStore.open(path: path, key: key, isNew: false);
      expect(await store.drafts(), isEmpty);
      expect((await store.supportingRecord(meId, 'report'))!.revision, 2);
      expect((await store.supportingRevisions(meId, 'report')).length, 2);
    },
  );

  test(
    'injected commit failure preserves the intent and replays once',
    () async {
      final draft = intent(operation: 'failed-void');
      await store.saveDraft(draft);
      await expectLater(
        store.voidSupportingRecord(commandFor(draft), failBeforeCommit: true),
        throwsA(isA<StateError>()),
      );
      expect((await store.drafts()).single.operationId, 'failed-void');
      final unchanged = (await store.supportingRecord(meId, 'report'))!;
      expect(unchanged.revision, 1);
      expect(unchanged.isVoided, isFalse);

      final committed = await store.resumeSupportingVoidDraft(draft);
      expect(committed.revision, 2);
      expect(await store.drafts(), isEmpty);
      expect((await store.supportingRevisions(meId, 'report')).length, 2);
    },
  );

  test(
    'lost reply after a durable commit resolves as committed, not stale',
    () async {
      final draft = intent(operation: 'lost-reply');
      await store.saveDraft(draft);
      // The command commits and its atomic draft removal succeeds; only the
      // caller's acknowledgement is lost.
      await store.voidSupportingRecord(commandFor(draft));
      expect(await store.drafts(), isEmpty);

      final replay = await store.resumeSupportingVoidDraft(draft);
      expect(replay.revision, 2);
      expect(await store.drafts(), isEmpty);
      expect((await store.supportingRevisions(meId, 'report')).length, 2);
      expect(await store.operationCommitted('lost-reply'), isTrue);
    },
  );

  test('repeated resume keeps one revision and no pending action', () async {
    final draft = intent(operation: 'repeat-void');
    await store.saveDraft(draft);
    await store.resumeSupportingVoidDraft(draft);
    final again = await store.resumeSupportingVoidDraft(draft);
    expect(again.revision, 2);
    expect(await store.drafts(), isEmpty);
    expect((await store.supportingRevisions(meId, 'report')).length, 2);
  });

  test(
    'changed owner revision rejects without writing and keeps the intent',
    () async {
      final draft = intent(operation: 'owner-changed');
      await store.saveDraft(draft);
      final owner = (await store.profileById(meId))!;
      await store.editProfile(
        commandId: 'rename-owner',
        personId: meId,
        expectedRevision: owner.revision,
        name: 'Me renamed',
        adultConfirmed: true,
      );
      await expectLater(
        store.resumeSupportingVoidDraft(draft),
        throwsA(conflict('person_context')),
      );
      expect((await store.drafts()).single.operationId, 'owner-changed');
      final unchanged = (await store.supportingRecord(meId, 'report'))!;
      expect(unchanged.revision, 1);
      expect(unchanged.isVoided, isFalse);
    },
  );

  test(
    'changed record revision rejects without overwriting the newer head',
    () async {
      final draft = intent(operation: 'record-changed');
      await store.saveDraft(draft);
      await store.voidSupportingRecord(
        VoidSupportingRecordCommand(
          commandId: 'other-void',
          generation: store.generation,
          personId: meId,
          id: 'report',
          expectedPersonRevision: 1,
          expectedRevision: 1,
        ),
      );
      await expectLater(
        store.resumeSupportingVoidDraft(draft),
        throwsA(conflict('supporting_revision')),
      );
      expect((await store.drafts()).single.operationId, 'record-changed');
      final newer = (await store.supportingRecord(meId, 'report'))!;
      expect(newer.revision, 2);
      expect(newer.isVoided, isTrue);
    },
  );

  test('a different dataset generation rejects before the command', () async {
    final draft = intent(
      operation: 'generation-changed',
      generation: 'not-this-dataset',
    );
    await expectLater(
      store.resumeSupportingVoidDraft(draft),
      throwsA(conflict('generation')),
    );
    expect(await store.drafts(), isEmpty);
    expect((await store.supportingRecord(meId, 'report'))!.revision, 1);
  });

  test('explicit discard invalidates the exact operation', () async {
    final draft = intent(operation: 'discarded');
    await store.saveDraft(draft);
    await store.discardDraft(draft.id);
    expect(await store.drafts(), isEmpty);
    await expectLater(
      store.resumeSupportingVoidDraft(draft),
      throwsA(conflict('deleted_context')),
    );
    await expectLater(
      store.operationCommitted(draft.operationId),
      throwsA(conflict('deleted_context')),
    );
    final unchanged = (await store.supportingRecord(meId, 'report'))!;
    expect(unchanged.revision, 1);
    expect(unchanged.isVoided, isFalse);
  });

  test('wrong owner target is rejected without linking records', () async {
    final other = await store.createProfile(
      commandId: 'wrong-owner-adult',
      name: 'Wrong owner adult',
      adultConfirmed: true,
    );
    await seedPanel('other-report', person: other.id);
    final draft = intent(
      operation: 'wrong-owner',
      recordId: 'other-report',
      personRevision: 1,
      recordRevision: 1,
    );
    await store.saveDraft(draft);
    await expectLater(
      store.resumeSupportingVoidDraft(draft),
      throwsA(conflict('supporting_revision')),
    );
    expect(await store.supportingRecord(meId, 'other-report'), isNull);
    final untouched = (await store.supportingRecord(other.id, 'other-report'))!;
    expect(untouched.revision, 1);
    expect(untouched.isVoided, isFalse);
    expect((await store.drafts()).single.operationId, 'wrong-owner');
  });

  test('archived owner keeps the intent until explicit discard', () async {
    final other = await store.createProfile(
      commandId: 'archived-adult',
      name: 'Archived adult',
      adultConfirmed: true,
    );
    await seedPanel('archived-report', person: other.id);
    final draft = intent(
      operation: 'archived-owner',
      recordId: 'archived-report',
      personId: other.id,
      personRevision: other.revision,
      recordRevision: 1,
    );
    await store.saveDraft(draft);
    await store.archiveProfile(
      commandId: 'archive-adult',
      personId: other.id,
      expectedRevision: other.revision,
    );
    await expectLater(
      store.resumeSupportingVoidDraft(draft),
      throwsA(conflict('person_context')),
    );
    expect((await store.drafts()).single.operationId, 'archived-owner');
    expect(
      (await store.supportingRecord(other.id, 'archived-report'))!.revision,
      1,
    );
    await store.discardDraft(draft.id);
    expect(await store.drafts(), isEmpty);
  });

  test('lock hides the intent until writes resume', () async {
    final draft = intent(operation: 'locked-intent');
    await store.saveDraft(draft);
    await store.writeSetting('app_lock', 'true');
    await store.close();
    store = await RecordStore.open(path: path, key: key, isNew: false);
    expect(store.writesSuspended, isTrue);
    await expectLater(store.drafts(), throwsA(conflict('app_locked')));
    store.suspendWrites(false);
    final visible = (await store.drafts()).single;
    expect(visible.operationId, 'locked-intent');
    final committed = await store.resumeSupportingVoidDraft(visible);
    expect(committed.revision, 2);
  });

  test(
    'profile deletion removes the intent and invalidates its operation',
    () async {
      final other = await store.createProfile(
        commandId: 'other-adult',
        name: 'Other adult',
        adultConfirmed: true,
      );
      await seedPanel('other-report', person: other.id);
      final draft = intent(
        operation: 'deleted-owner',
        recordId: 'other-report',
        personId: other.id,
        personRevision: other.revision,
        recordRevision: 1,
      );
      await store.saveDraft(draft);
      await store.deleteProfile(
        commandId: 'delete-other',
        personId: other.id,
        expectedRevision: other.revision,
      );
      expect(await store.drafts(), isEmpty);
      await expectLater(
        store.resumeSupportingVoidDraft(draft),
        throwsA(conflict('deleted_context')),
      );
      expect(await store.supportingRecord(other.id, 'other-report'), isNull);
      expect((await store.supportingRecord(meId, 'report'))!.revision, 1);
    },
  );

  group('schema 21 recovery migration', () {
    setUp(() async {
      await store.close();
      await directory.delete(recursive: true);
      directory = await Directory.systemTemp.createTemp('vital-void-migrate-');
      path = '${directory.path}/db';
      final fixture = raw();
      fixture.execute(
        File('test/data/fixtures/record_store_v19_recovery.sql')
            .readAsStringSync(),
      );
      fixture.close();
      store = await RecordStore.open(path: path, key: key, isNew: false);
    });

    test('populated v19 keeps every draft and supporting revision', () async {
      final db = raw();
      expect(db.select('PRAGMA user_version').single.values.single, currentRecordSchemaVersion);
      expect(db.select('PRAGMA integrity_check').single.values.single, 'ok');
      expect(db.select('PRAGMA foreign_key_check'), isEmpty);
      final drafts = db.select(
        'SELECT id,kind,operation,person,target FROM ordinary_draft ORDER BY id',
      );
      expect(drafts.length, 2);
      expect(drafts.first['kind'], 'dose');
      expect(drafts.last['kind'], 'labPanel');
      expect(drafts.last['operation'], 'v19-supporting-operation');
      expect(
        db
            .select(
              'SELECT kind,revision,voided FROM supporting_record ORDER BY id',
            )
            .single
            .values,
        ['labPanel', 2, 1],
      );
      expect(
        db.select('SELECT COUNT(*) AS n FROM supporting_revision').single['n'],
        2,
      );
      db.close();
      final recovered = await store.supportingRevisions(meId, 'v19-panel');
      expect(recovered.map((r) => r.revision), [2, 1]);
      expect((await store.drafts()).map((d) => d.kind), [
        DraftKind.dose,
        DraftKind.labPanel,
      ]);
    });

    test('new intent inserts and resumes after the rebuild', () async {
      final draft = intent(
        operation: 'after-migration',
        recordId: 'v19-panel',
        personRevision: 1,
        recordRevision: 2,
        isVoided: false,
      );
      await store.saveDraft(draft);
      final committed = await store.resumeSupportingVoidDraft(draft);
      expect(committed.revision, 3);
      expect(committed.isVoided, isFalse);
      expect(
        (await store.drafts()).where((d) => d.kind == DraftKind.supportingVoid),
        isEmpty,
      );
      expect((await store.supportingRevisions(meId, 'v19-panel')).length, 3);
    });

    test('unknown draft kinds still fail the closed CHECK', () async {
      final db = raw();
      expect(
        () => db.execute(
          "INSERT INTO ordinary_draft VALUES ('x','g','op','notAKind','me',1,NULL,NULL,'{}')",
        ),
        throwsA(isA<SqliteException>()),
      );
      db.close();
    });
  });

  test(
    'populated schema20 upgrades recovery without repeating query migration',
    () async {
      await store.close();
      await File(path).delete();
      final seeded = raw();
      seeded.execute(
        File('test/data/fixtures/record_store_v19_recovery.sql')
            .readAsStringSync(),
      );
      for (final sql in supportingSchemaV20) {
        seeded.execute(sql);
      }
      seeded.execute('PRAGMA user_version=20');
      final drafts = seeded
          .select('SELECT * FROM ordinary_draft ORDER BY id')
          .map((r) => r.values.toList())
          .toList();
      final revisions = seeded
          .select('SELECT * FROM supporting_revision ORDER BY record,revision')
          .map((r) => r.values.toList())
          .toList();
      seeded.close();
      store = await RecordStore.open(path: path, key: key, isNew: false);
      final upgraded = raw();
      expect(upgraded.select('PRAGMA user_version').single.values.single, currentRecordSchemaVersion);
      expect(
        upgraded
            .select('SELECT * FROM ordinary_draft ORDER BY id')
            .map((r) => r.values.toList())
            .toList(),
        drafts,
      );
      expect(
        upgraded
            .select(
              'SELECT * FROM supporting_revision ORDER BY record,revision',
            )
            .map((r) => r.values.toList())
            .toList(),
        revisions,
      );
      expect(
        upgraded.select('PRAGMA integrity_check').single.values.single,
        'ok',
      );
      expect(upgraded.select('PRAGMA foreign_key_check'), isEmpty);
      upgraded.close();
      final draft = intent(
        operation: 'schema20-recovery',
        recordId: 'v19-panel',
        recordRevision: 2,
        isVoided: false,
      );
      await store.saveDraft(draft);
      expect((await store.resumeSupportingVoidDraft(draft)).isVoided, isFalse);
    },
  );
  test('a damaged intermediate table aborts before changing schema 19', () async {
    await store.close();
    await directory.delete(recursive: true);
    directory = await Directory.systemTemp.createTemp('vital-void-collision-');
    path = '${directory.path}/db';
    var db = raw();
    db.execute(
      File('test/data/fixtures/record_store_v19_recovery.sql')
          .readAsStringSync(),
    );
    db.execute('CREATE TABLE ordinary_draft_v20(id TEXT) STRICT');
    db.close();
    await expectLater(
      RecordStore.open(path: path, key: key, isNew: false),
      throwsA(
        predicate<Object>(
          (error) =>
              error.toString().contains('supporting_void_migration_collision'),
        ),
      ),
    );
    db = raw();
    expect(db.select('PRAGMA user_version').single.values.single, 19);
    expect(
      db.select('SELECT COUNT(*) AS n FROM ordinary_draft').single['n'],
      2,
    );
    expect(db.select('PRAGMA foreign_key_check'), isEmpty);
    db.close();
    // The outer tear-down closes the already-closed store and removes the file.
  });
}
