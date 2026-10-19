import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:true_grit_vital/data/record_store.dart';

void main() {
  late Directory dir;
  late RecordStore store;
  late String path;
  late SubstanceItem item;
  final key = List.generate(32, (i) => i + 1);
  final bytes = Uint8List.fromList(
    utf8.encode(
      'Synthetic protected original bytes. Do not cache this marker.',
    ),
  );
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('vital-attachment-');
    path = '${dir.path}/attachment.db';
    store = await RecordStore.open(path: path, key: key, isNew: true);
    item = await store.createItem(
      commandId: 'item',
      name: 'Synthetic source',
      form: 'tablet',
      unit: 'count',
      type: 'medicine',
    );
  });
  tearDown(() async {
    await store.close();
    await dir.delete(recursive: true);
  });
  AttachmentJob job({
    String id = 'job',
    String? person,
    String? target,
    int? ownerRevision,
    AttachmentTargetKind kind = AttachmentTargetKind.item,
    int targetRevision = 1,
  }) => AttachmentJob(
    id: id,
    generation: store.generation,
    personId: person ?? meId,
    expectedPersonRevision: ownerRevision ?? 1,
    targetKind: kind,
    targetId: target ?? item.id,
    targetRevision: targetRevision,
    attachmentId: 'attachment-$id',
    versionId: 'version-$id',
    name: '../../private-original.txt',
    createdAt: DateTime.utc(2026, 10, 19),
  );
  AttachmentInspection inspection([Uint8List? data]) => AttachmentInspection(
    mediaKind: AttachmentMediaKind.other,
    byteCount: (data ?? bytes).length,
    sha256: sha256.convert(data ?? bytes).toString(),
    mimeType: 'application/octet-stream',
  );
  Future<AttachmentRecord> saved({
    String id = 'job',
    AttachmentJob? targetJob,
  }) async {
    final j = targetJob ?? job(id: id);
    await store.beginAttachment(
      BeginAttachmentCommand(commandId: 'begin-$id', job: j),
    );
    await store.appendAttachmentChunk(
      commandId: 'chunk-$id',
      jobId: j.id,
      generation: store.generation,
      offset: 0,
      bytes: bytes,
    );
    return store.publishAttachment(
      commandId: 'publish-$id',
      jobId: j.id,
      generation: store.generation,
      inspection: inspection(),
    );
  }

  Future<List<int>> contents(AttachmentPin pin) async => [
    await for (final chunk in store.readAttachmentPin(pin)) ...chunk,
  ];
  test('job precedes picker, staged bytes stay hidden, publish and chunk retries retain one original', () async {
    final j = job();
    final cmd = BeginAttachmentCommand(commandId: 'begin', job: j);
    await store.beginAttachment(cmd);
    await store.beginAttachment(cmd);
    expect((await store.pendingAttachmentJobs()).single.personId, meId);
    expect(await store.attachments(personId: meId), isEmpty);
    await store.appendAttachmentChunk(
      commandId: 'chunk',
      jobId: j.id,
      generation: store.generation,
      offset: 0,
      bytes: bytes,
    );
    await store.appendAttachmentChunk(
      commandId: 'chunk',
      jobId: j.id,
      generation: store.generation,
      offset: 0,
      bytes: bytes,
    );
    await expectLater(
      store.appendAttachmentChunk(
        commandId: 'chunk',
        jobId: j.id,
        generation: store.generation,
        offset: 0,
        bytes: Uint8List.fromList([1]),
      ),
      throwsA(isA<CommandConflict>()),
    );
    expect(await store.attachments(personId: meId), isEmpty);
    final original = await store.publishAttachment(
      commandId: 'publish',
      jobId: j.id,
      generation: store.generation,
      inspection: inspection(),
    );
    await store.publishAttachment(
      commandId: 'publish',
      jobId: j.id,
      generation: store.generation,
      inspection: inspection(),
    );
    expect((await store.attachments(personId: meId)).length, 1);
    expect(original.name, '../../private-original.txt');
    expect((await store.attachmentJob(j.id))!.state, AttachmentJobState.ready);
    final pin = await store.pinAttachment(
      id: original.id,
      generation: store.generation,
      expectedRevision: 1,
    );
    expect(await contents(pin), bytes);
    await store.releaseAttachmentPin(pin);
  });
  test('bounded staging rejects gaps, excessive chunks and mismatched hash without deleting source', () async {
    final source = File('${dir.path}/selected-original');
    await source.writeAsBytes(bytes);
    final j = job();
    await store.beginAttachment(
      BeginAttachmentCommand(commandId: 'begin', job: j),
    );
    await expectLater(
      store.appendAttachmentChunk(
        commandId: 'gap',
        jobId: j.id,
        generation: store.generation,
        offset: 1,
        bytes: bytes,
      ),
      throwsA(isA<CommandConflict>()),
    );
    await expectLater(
      store.appendAttachmentChunk(
        commandId: 'large',
        jobId: j.id,
        generation: store.generation,
        offset: 0,
        bytes: Uint8List(AttachmentLimits.chunkBytes + 1),
      ),
      throwsA(isA<AttachmentFailure>()),
    );
    await store.appendAttachmentChunk(
      commandId: 'chunk',
      jobId: j.id,
      generation: store.generation,
      offset: 0,
      bytes: bytes,
    );
    await expectLater(
      store.publishAttachment(
        commandId: 'bad-hash',
        jobId: j.id,
        generation: store.generation,
        inspection: AttachmentInspection(
          mediaKind: AttachmentMediaKind.other,
          byteCount: bytes.length,
          sha256: '0' * 64,
          mimeType: 'application/octet-stream',
        ),
      ),
      throwsA(isA<AttachmentFailure>()),
    );
    expect(await store.attachments(personId: meId), isEmpty);
    await store.cancelAttachment(
      commandId: 'cancel',
      jobId: j.id,
      generation: store.generation,
    );
    expect(await source.readAsBytes(), bytes);
    expect(await store.pendingAttachmentJobs(), isEmpty);
  });
  test('fixed original target rejects another adult, stale record, owner and generation after picker', () async {
    final adult = await store.createProfile(
      commandId: 'adult',
      name: 'Other adult',
      adultConfirmed: true,
    );
    await expectLater(
      store.beginAttachment(
        BeginAttachmentCommand(
          commandId: 'wrong-owner',
          job: job(person: adult.id),
        ),
      ),
      throwsA(isA<CommandConflict>()),
    );
    final r = await store.record(
      commandId: 'dose',
      itemId: item.id,
      amount: '1',
      actualAt: DateTime.utc(2026, 10, 19),
    );
    final j = job(kind: AttachmentTargetKind.record, target: r.id);
    await store.beginAttachment(
      BeginAttachmentCommand(commandId: 'record-job', job: j),
    );
    await store.correct(
      commandId: 'correct',
      recordId: r.id,
      expectedRevision: 1,
      amount: null,
      actualAt: DateTime.utc(2026, 10, 19, 1),
    );
    await expectLater(
      store.appendAttachmentChunk(
        commandId: 'late',
        jobId: j.id,
        generation: store.generation,
        offset: 0,
        bytes: bytes,
      ),
      throwsA(isA<CommandConflict>()),
    );
    await expectLater(
      store.appendAttachmentChunk(
        commandId: 'wrong-generation',
        jobId: j.id,
        generation: 'other',
        offset: 0,
        bytes: bytes,
      ),
      throwsA(isA<CommandConflict>()),
    );
    expect((await store.pendingAttachmentJobs()).single.targetId, r.id);
    expect(await store.attachments(personId: adult.id), isEmpty);
  });
  test('rename and association deletion preserve active pin exact metadata and bytes', () async {
    final a = await saved();
    final pin = await store.pinAttachment(
      id: a.id,
      generation: store.generation,
      expectedRevision: 1,
      sessionId: 'preview-session',
    );
    final renamed = await store.renameAttachment(
      commandId: 'rename',
      attachment: a,
      expectedPersonRevision: 1,
      name: 'Renamed original',
    );
    expect(pin.attachment.name, a.name);
    expect(renamed.versionId, a.versionId);
    await expectLater(
      store.renameAttachment(
        commandId: 'stale-rename',
        attachment: a,
        expectedPersonRevision: 1,
        name: 'Bad rename',
      ),
      throwsA(isA<CommandConflict>()),
    );
    await store.deleteAttachment(
      commandId: 'delete',
      attachment: renamed,
      expectedPersonRevision: 1,
    );
    expect(await store.attachmentById(a.id), isNull);
    expect(await contents(pin), bytes);
    await expectLater(
      store.pinAttachment(
        id: a.id,
        generation: store.generation,
        expectedRevision: renamed.revision,
      ),
      throwsA(isA<CommandConflict>()),
    );
    await store.releaseAttachmentPin(pin);
    await expectLater(contents(pin), throwsA(isA<CommandConflict>()));
    await expectLater(
      store.publishAttachment(
        commandId: 'publish-job',
        jobId: 'job',
        generation: store.generation,
        inspection: inspection(),
      ),
      throwsA(isA<CommandConflict>()),
    );
  });
  test('profile deletion preserves only active pinned source and cannot resurrect prior jobs', () async {
    final a = await saved();
    final pin = await store.pinAttachment(
      id: a.id,
      generation: store.generation,
      expectedRevision: 1,
    );
    await store.deleteProfile(
      commandId: 'delete-profile',
      personId: meId,
      expectedRevision: 1,
    );
    expect(await store.attachments(personId: meId), isEmpty);
    expect(await store.pendingAttachmentJobs(), isEmpty);
    expect(await contents(pin), bytes);
    await expectLater(
      store.beginAttachment(
        BeginAttachmentCommand(commandId: 'begin-job', job: job()),
      ),
      throwsA(isA<CommandConflict>()),
    );
    await store.releaseAttachmentPin(pin);
  });
  test('lock stops protected reads and clinical writes while pin release remains safe', () async {
    final a = await saved();
    final pin = await store.pinAttachment(
      id: a.id,
      generation: store.generation,
      expectedRevision: 1,
    );
    store.suspendWrites(true);
    await expectLater(contents(pin), throwsA(isA<CommandConflict>()));
    await expectLater(
      store.renameAttachment(
        commandId: 'locked-rename',
        attachment: a,
        expectedPersonRevision: 1,
        name: 'Hidden',
      ),
      throwsA(isA<CommandConflict>()),
    );
    await store.releaseAttachmentPin(pin);
    store.suspendWrites(false);
    expect((await store.attachmentById(a.id))!.name, a.name);
  });
  test('restart retains staged job, cleans abandoned preview pins and retains handoff lifetime', () async {
    final a = await saved();
    final preview = await store.pinAttachment(
      id: a.id,
      generation: store.generation,
      expectedRevision: 1,
      sessionId: 'old',
    );
    final handoff = await store.pinAttachment(
      id: a.id,
      generation: store.generation,
      expectedRevision: 1,
      sessionId: 'old',
      purpose: 'handoff',
      expiresAt: DateTime.now().toUtc().add(const Duration(hours: 24)),
    );
    final j = job(id: 'waiting');
    await store.beginAttachment(
      BeginAttachmentCommand(commandId: 'waiting-job', job: j),
    );
    await store.close();
    store = await RecordStore.open(path: path, key: key, isNew: false);
    expect(
      (await store.recoverAttachmentState(sessionId: 'new')).single.id,
      j.id,
    );
    await expectLater(contents(preview), throwsA(isA<CommandConflict>()));
    expect(await contents(handoff), bytes);
    await store.releaseAttachmentPin(handoff);
  });
  test('encrypted reopen preserves originals and byte content never appears in raw database', () async {
    final a = await saved();
    await store.close();
    final rawBytes = await File(path).readAsBytes();
    expect(
      utf8
          .decode(rawBytes, allowMalformed: true)
          .contains('Synthetic protected original bytes'),
      isFalse,
    );
    store = await RecordStore.open(path: path, key: key, isNew: false);
    final pin = await store.pinAttachment(
      id: a.id,
      generation: store.generation,
      expectedRevision: 1,
    );
    expect(await contents(pin), bytes);
    await store.releaseAttachmentPin(pin);
  });
  test('explicit restart retains original target and replaces only unfinished protected bytes', () async {
    final j = job();
    await store.beginAttachment(
      BeginAttachmentCommand(commandId: 'begin', job: j),
    );
    await store.appendAttachmentChunk(
      commandId: 'old-chunk',
      jobId: j.id,
      generation: store.generation,
      offset: 0,
      bytes: bytes,
    );
    final restarted = await store.restartAttachmentJob(
      commandId: 'restart',
      jobId: j.id,
      generation: store.generation,
    );
    expect(restarted.receivedBytes, 0);
    expect(restarted.targetId, item.id);
    await expectLater(
      store.appendAttachmentChunk(
        commandId: 'old-chunk',
        jobId: j.id,
        generation: store.generation,
        offset: 0,
        bytes: bytes,
      ),
      throwsA(isA<CommandConflict>()),
    );
    await store.appendAttachmentChunk(
      commandId: 'new-chunk',
      jobId: j.id,
      generation: store.generation,
      offset: 0,
      bytes: bytes,
    );
    final a = await store.publishAttachment(
      commandId: 'publish',
      jobId: j.id,
      generation: store.generation,
      inspection: inspection(),
    );
    expect(a.targetId, item.id);
  });
  test('publish and delete failures preserve coherent staged ready and pinned states', () async {
    final j = job();
    await store.beginAttachment(
      BeginAttachmentCommand(commandId: 'begin', job: j),
    );
    await expectLater(
      store.appendAttachmentChunk(
        commandId: 'failed-chunk',
        jobId: j.id,
        generation: store.generation,
        offset: 0,
        bytes: bytes,
        failBeforeCommit: true,
      ),
      throwsA(anything),
    );
    expect((await store.attachmentJob(j.id))!.receivedBytes, 0);
    await store.appendAttachmentChunk(
      commandId: 'chunk',
      jobId: j.id,
      generation: store.generation,
      offset: 0,
      bytes: bytes,
    );
    await expectLater(
      store.publishAttachment(
        commandId: 'publish',
        jobId: j.id,
        generation: store.generation,
        inspection: inspection(),
        failBeforeCommit: true,
      ),
      throwsA(anything),
    );
    expect(await store.attachments(personId: meId), isEmpty);
    expect(
      (await store.attachmentJob(j.id))!.state,
      AttachmentJobState.importing,
    );
    final a = await store.publishAttachment(
      commandId: 'publish',
      jobId: j.id,
      generation: store.generation,
      inspection: inspection(),
    );
    final pin = await store.pinAttachment(
      id: a.id,
      generation: store.generation,
      expectedRevision: 1,
    );
    await expectLater(
      store.deleteAttachment(
        commandId: 'delete',
        attachment: a,
        expectedPersonRevision: 1,
        failBeforeCommit: true,
      ),
      throwsA(anything),
    );
    expect(await store.attachmentById(a.id), isNotNull);
    expect(await contents(pin), bytes);
    await store.releaseAttachmentPin(pin);
  });
  test(
    'same names across adults remain separately owned under profile deletion',
    () async {
      final a = await saved();
      final other = await store.createProfile(
        commandId: 'adult',
        name: 'Other adult',
        adultConfirmed: true,
      );
      final otherItem = await store.createItem(
        commandId: 'other-item',
        personId: other.id,
        expectedPersonRevision: 1,
        name: 'Other source',
        form: 'tablet',
        unit: 'count',
        type: 'medicine',
      );
      final b = await saved(
        id: 'other',
        targetJob: job(id: 'other', person: other.id, target: otherItem.id),
      );
      expect(a.name, b.name);
      final pin = await store.pinAttachment(
        id: a.id,
        generation: store.generation,
        expectedRevision: 1,
      );
      await store.deleteProfile(
        commandId: 'delete-me',
        personId: meId,
        expectedRevision: 1,
      );
      expect((await store.attachments(personId: other.id)).single.id, b.id);
      expect(await contents(pin), bytes);
      await store.releaseAttachmentPin(pin);
      final bPin = await store.pinAttachment(
        id: b.id,
        generation: store.generation,
        expectedRevision: 1,
      );
      expect(await contents(bPin), bytes);
      await store.releaseAttachmentPin(bPin);
    },
  );
  test('populated encrypted v15 migration retains events use history drafts groups and replay', () async {
    final p = '${dir.path}/v15.db';
    var raw = sqlite3.open(p);
    raw.execute("PRAGMA cipher='chacha20'");
    final keySql =
        'PRAGMA key="x\'${key.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}\'"';
    raw.execute(keySql);
    raw.execute(
      File('test/data/fixtures/record_store_v15.sql').readAsStringSync(),
    );
    final gen =
        raw.select('SELECT generation FROM dataset').single['generation']
            as String;
    final draft = OrdinaryDraft(
      id: 'v15-draft',
      generation: gen,
      operationId: 'v15-draft-save',
      kind: DraftKind.event,
      personId: meId,
      personRevision: 1,
      targetId: 'fixture-event',
      targetRevision: 1,
      fields: {'name': 'Unfinished original event'},
    );
    raw.execute('INSERT INTO ordinary_draft VALUES (?,?,?,?,?,?,?,?,?)', [
      draft.id,
      gen,
      draft.operationId,
      draft.kind.name,
      meId,
      1,
      draft.targetId,
      1,
      draft.encode(),
    ]);
    final tables = [
      'event_record',
      'event_audit',
      'event_membership',
      'use_period',
      'use_period_audit',
      'event_item_decision',
      'combined_member',
      'combined_audit',
      'operation',
      'ordinary_draft',
    ];
    final before = {
      for (final t in tables)
        t: raw
            .select('SELECT * FROM $t ORDER BY rowid')
            .map((r) => Map<String, Object?>.from(r))
            .toList(),
    };
    raw.close();
    final migrated = await RecordStore.open(path: p, key: key, isNew: false);
    expect((await migrated.events()).single.id, 'fixture-event');
    expect(
      (await migrated.drafts()).single.fields['name'],
      'Unfinished original event',
    );
    expect(await migrated.attachments(personId: meId), isEmpty);
    await migrated.close();
    raw = sqlite3.open(p);
    raw.execute("PRAGMA cipher='chacha20'");
    raw.execute(keySql);
    expect(raw.select('PRAGMA user_version').single.values.single, 19);
    for (final t in tables) {
      expect(
        raw
            .select('SELECT * FROM $t ORDER BY rowid')
            .map((r) => Map<String, Object?>.from(r))
            .toList(),
        before[t],
        reason: t,
      );
    }
    expect(raw.select('PRAGMA foreign_key_check'), isEmpty);
    raw.close();
  });
  test('early and late v16 migration failures preserve recoverable v15 and original event data', () async {
    for (final collision in [
      'attachment_record',
      'attachment_chunk',
      'ordinary_draft_v15',
    ]) {
      final p = '${dir.path}/$collision.db';
      var raw = sqlite3.open(p);
      raw.execute("PRAGMA cipher='chacha20'");
      final keySql =
          'PRAGMA key="x\'${key.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}\'"';
      raw.execute(keySql);
      raw.execute(
        File('test/data/fixtures/record_store_v15.sql').readAsStringSync(),
      );
      raw.execute('CREATE TABLE $collision(recovery TEXT)');
      raw.close();
      await expectLater(
        RecordStore.open(path: p, key: key, isNew: false),
        throwsA(anything),
      );
      raw = sqlite3.open(p);
      raw.execute("PRAGMA cipher='chacha20'");
      raw.execute(keySql);
      expect(raw.select('PRAGMA user_version').single.values.single, 15);
      expect(raw.select('SELECT * FROM event_record').length, 1);
      expect(raw.select('SELECT * FROM combined_member').length, 2);
      expect(
        raw.select(
          "SELECT name FROM sqlite_master WHERE name='attachment_pin'",
        ),
        isEmpty,
      );
      expect(raw.select('PRAGMA foreign_key_check'), isEmpty);
      raw.close();
    }
  });

  test('independent append contention commits one exact offset without duplicate original bytes', () async {
    final j = job();
    await store.beginAttachment(
      BeginAttachmentCommand(commandId: 'begin', job: j),
    );
    final second = await RecordStore.open(path: path, key: key, isNew: false);
    Future<Object> settle(Future<AttachmentJob> f) async {
      try {
        return await f;
      } catch (e) {
        return e;
      }
    }

    try {
      final results = await Future.wait([
        settle(
          store.appendAttachmentChunk(
            commandId: 'append-first',
            jobId: j.id,
            generation: store.generation,
            offset: 0,
            bytes: bytes,
          ),
        ),
        settle(
          second.appendAttachmentChunk(
            commandId: 'append-second',
            jobId: j.id,
            generation: store.generation,
            offset: 0,
            bytes: bytes,
          ),
        ),
      ]);
      expect(results.whereType<AttachmentJob>().length, 1);
      expect(results.whereType<CommandConflict>().length, 1);
      expect((await store.attachmentJob(j.id))!.receivedBytes, bytes.length);
    } finally {
      await second.close();
    }
  });
  test('database ownership constraints reject retargeting the live attachment link', () async {
    final a = await saved();
    final other = await store.createProfile(
      commandId: 'adult',
      name: 'Other adult',
      adultConfirmed: true,
    );
    await store.close();
    final raw = sqlite3.open(path);
    raw.execute("PRAGMA cipher='chacha20'");
    raw.execute(
      'PRAGMA key="x\'${key.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}\'"',
    );
    raw.execute('PRAGMA foreign_keys=ON');
    expect(
      () => raw.execute(
        'UPDATE attachment_link SET person=? WHERE attachment=?',
        [other.id, a.id],
      ),
      throwsA(isA<SqliteException>()),
    );
    expect(raw.select('PRAGMA foreign_key_check'), isEmpty);
    raw.close();
    store = await RecordStore.open(path: path, key: key, isNew: false);
    expect((await store.attachments(personId: meId)).single.id, a.id);
    expect(await store.attachments(personId: other.id), isEmpty);
  });
  test('restart replacing equal-length bytes after verification rejects stale publication', () async {
    final j = job();
    await store.beginAttachment(
      BeginAttachmentCommand(commandId: 'begin', job: j),
    );
    await store.appendAttachmentChunk(
      commandId: 'first-chunk',
      jobId: j.id,
      generation: store.generation,
      offset: 0,
      bytes: bytes,
    );
    final replacement = Uint8List.fromList(List.filled(bytes.length, 7));
    await expectLater(
      store.publishAttachment(
        commandId: 'stale-publish',
        jobId: j.id,
        generation: store.generation,
        inspection: inspection(),
        afterVerification: () async {
          await store.restartAttachmentJob(
            commandId: 'restart-race',
            jobId: j.id,
            generation: store.generation,
          );
          await store.appendAttachmentChunk(
            commandId: 'replacement',
            jobId: j.id,
            generation: store.generation,
            offset: 0,
            bytes: replacement,
          );
        },
      ),
      throwsA(
        isA<CommandConflict>().having(
          (e) => e.code,
          'code',
          'attachment_job_revision',
        ),
      ),
    );
    expect(await store.attachments(personId: meId), isEmpty);
    final actual = await store.publishAttachment(
      commandId: 'new-publish',
      jobId: j.id,
      generation: store.generation,
      inspection: inspection(replacement),
    );
    final pin = await store.pinAttachment(
      id: actual.id,
      generation: store.generation,
      expectedRevision: 1,
    );
    expect(await contents(pin), replacement);
    await store.releaseAttachmentPin(pin);
  });
  test(
    'photo jobs reject non-image content despite picker MIME hints',
    () async {
      final photo = AttachmentJob.fromJson({
        ...job().toJson(),
        'pickerKind': 'photo',
      });
      await store.beginAttachment(
        BeginAttachmentCommand(commandId: 'photo-begin', job: photo),
      );
      await store.appendAttachmentChunk(
        commandId: 'photo-bytes',
        jobId: photo.id,
        generation: store.generation,
        offset: 0,
        bytes: bytes,
      );
      await expectLater(
        store.publishAttachment(
          commandId: 'photo-publish',
          jobId: photo.id,
          generation: store.generation,
          inspection: inspection(),
        ),
        throwsA(
          isA<AttachmentFailure>().having(
            (e) => e.code,
            'code',
            'attachment_image_required',
          ),
        ),
      );
      expect(await store.attachments(personId: meId), isEmpty);
      expect(
        (await store.attachmentJob(photo.id))!.receivedBytes,
        bytes.length,
      );
    },
  );
}
