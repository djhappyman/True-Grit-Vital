part of 'record_store.dart';

// Original chunks are protected by the already-admitted encrypted SQLite3MC engine.
// No plaintext filesystem staging or independent cipher is introduced here.
const attachmentSchemaV16 = [
  'CREATE TABLE attachment_record(id TEXT PRIMARY KEY,person TEXT NOT NULL,target_kind TEXT NOT NULL CHECK(target_kind IN (\'item\',\'record\')),target TEXT NOT NULL,version TEXT NOT NULL UNIQUE,revision INTEGER NOT NULL CHECK(revision>0),state TEXT NOT NULL CHECK(state IN (\'staging\',\'ready\',\'deleting\')),created_at INTEGER NOT NULL,snapshot TEXT NOT NULL CHECK(json_valid(snapshot)),UNIQUE(id,person)) STRICT',
  'CREATE TABLE attachment_link(attachment TEXT PRIMARY KEY,person TEXT NOT NULL REFERENCES person(id),item TEXT,record TEXT,CHECK((item IS NOT NULL AND record IS NULL) OR (item IS NULL AND record IS NOT NULL)),FOREIGN KEY(attachment,person) REFERENCES attachment_record(id,person) ON DELETE CASCADE,FOREIGN KEY(item,person) REFERENCES item(id,person),FOREIGN KEY(record,person) REFERENCES administration(id,person)) STRICT',
  'CREATE INDEX attachment_link_person ON attachment_link(person,attachment)',
  'CREATE INDEX attachment_target ON attachment_record(person,target_kind,target,state,created_at,id)',
  "CREATE INDEX attachment_deleting ON attachment_record(id) WHERE state='deleting'",
  'CREATE TABLE attachment_job(id TEXT PRIMARY KEY,person TEXT NOT NULL,attachment TEXT NOT NULL UNIQUE,version TEXT NOT NULL UNIQUE,state TEXT NOT NULL CHECK(state IN (\'awaitingPicker\',\'importing\',\'ready\',\'cancelled\',\'interrupted\')),received INTEGER NOT NULL CHECK(received>=0 AND received<=16777216),created_at INTEGER NOT NULL,snapshot TEXT NOT NULL CHECK(json_valid(snapshot)),revision INTEGER NOT NULL CHECK(revision>=0)) STRICT',
  "CREATE INDEX attachment_active_jobs ON attachment_job(state,created_at,id) WHERE state IN ('awaitingPicker','importing','interrupted')",
  'CREATE TABLE attachment_chunk(version TEXT NOT NULL,offset INTEGER NOT NULL CHECK(offset>=0),bytes BLOB NOT NULL CHECK(length(bytes)>0 AND length(bytes)<=65536),digest TEXT NOT NULL CHECK(length(digest)=64),PRIMARY KEY(version,offset)) STRICT',
  "CREATE TRIGGER attachment_chunk_immutable BEFORE UPDATE ON attachment_chunk BEGIN SELECT RAISE(ABORT,'immutable_attachment_chunk'); END",
  'CREATE TABLE attachment_pin(id TEXT PRIMARY KEY,version TEXT NOT NULL,attachment TEXT NOT NULL,session TEXT NOT NULL,purpose TEXT NOT NULL,expires INTEGER,snapshot TEXT NOT NULL CHECK(json_valid(snapshot))) STRICT',
  'CREATE INDEX attachment_pin_version ON attachment_pin(version,id)',
  'CREATE INDEX attachment_pin_expiry ON attachment_pin(expires,id)',
  'ALTER TABLE ordinary_draft RENAME TO ordinary_draft_v15',
  "CREATE TABLE ordinary_draft(id TEXT PRIMARY KEY,generation TEXT NOT NULL,operation TEXT NOT NULL UNIQUE,kind TEXT NOT NULL CHECK(kind IN ('item','dose','correction','profile','dailyPlan','pausePlan','phasePlan','itemType','stockContainer','stockAdjustment','productLabel','combinedDose','combinedCorrection','siteEdit','event','usePeriod','eventReview','attachmentRename')),person TEXT REFERENCES person(id),person_revision INTEGER,target TEXT,target_revision INTEGER,snapshot TEXT NOT NULL) STRICT",
  'INSERT INTO ordinary_draft SELECT * FROM ordinary_draft_v15',
  'DROP TABLE ordinary_draft_v15',
];

extension AttachmentRecordStore on RecordStore {
  Map<String, Object?> _attachmentObject(String text) =>
      Map<String, Object?>.from(jsonDecode(text) as Map);
  AttachmentJob _attachmentJobRead(Map<String, Object?> row) =>
      AttachmentJob.fromJson(_attachmentObject(row['snapshot'] as String));
  AttachmentRecord _attachmentRead(Map<String, Object?> row) =>
      AttachmentRecord.fromJson(_attachmentObject(row['snapshot'] as String));
  Future<AttachmentJob?> attachmentJob(String id) async {
    _requireWritable();
    final rows = await _rows('SELECT snapshot FROM attachment_job WHERE id=?', [
      id,
    ]);
    return rows.isEmpty ? null : _attachmentJobRead(rows.single);
  }

  Future<List<AttachmentJob>> pendingAttachmentJobs() async {
    _requireWritable();
    return (await _rows(
      "SELECT snapshot FROM attachment_job WHERE state IN ('awaitingPicker','importing','interrupted') ORDER BY created_at,id LIMIT 101",
    )).map(_attachmentJobRead).toList();
  }

  Future<void> _validateAttachmentTarget(AttachmentJob job) async {
    _dailyGeneration(job.generation);
    await _activeOwner(job.personId, job.expectedPersonRevision);
    switch (job.targetKind) {
      case AttachmentTargetKind.item:
        final item = await itemById(job.targetId, personId: job.personId);
        if (item == null || item.revision != job.targetRevision) {
          throw const CommandConflict('attachment_target_revision');
        }
      case AttachmentTargetKind.record:
        final record = await recordById(job.targetId, personId: job.personId);
        if (record == null ||
            record.isVoided ||
            record.revision != job.targetRevision) {
          throw const CommandConflict('attachment_target_revision');
        }
      case AttachmentTargetKind.supporting:
        final supporting = await supportingRecord(job.personId, job.targetId);
        if (supporting == null ||
            supporting.isVoided ||
            supporting.revision != job.targetRevision) {
          throw const CommandConflict('attachment_target_revision');
        }
    }
  }

  AttachmentJob _attachmentJobChange(
    AttachmentJob job, {
    AttachmentJobState? state,
    int? receivedBytes,
  }) => AttachmentJob.fromJson({
    ...job.toJson(),
    if (state != null) 'state': state.name,
    'receivedBytes': ?receivedBytes,
  });
  Future<void> _putAttachmentJob(AttachmentJob job) async {
    await _db.customStatement(
      'UPDATE attachment_job SET state=?,received=?,snapshot=?,revision=revision+1 WHERE id=?',
      [job.state.name, job.receivedBytes, jsonEncode(job.toJson()), job.id],
    );
  }

  Future<AttachmentJob> beginAttachment(
    BeginAttachmentCommand command, {
    bool failBeforeCommit = false,
    Future<void> Function()? beforeCommit,
  }) async {
    final j = command.job;
    _dailyGeneration(j.generation);
    final result = await _command(
      command.commandId,
      ['attachment_begin', j.personId, j.toJson()],
      () async {
        await _validateAttachmentTarget(j);
        if (j.state != AttachmentJobState.awaitingPicker ||
            j.receivedBytes != 0) {
          throw const CommandConflict('attachment_job_state');
        }
        final active = await _rows(
          "SELECT id FROM attachment_job WHERE state IN ('awaitingPicker','importing','interrupted') LIMIT ?",
          [AttachmentLimits.maxConcurrentJobs],
        );
        if (active.length >= AttachmentLimits.maxConcurrentJobs) {
          throw const CommandConflict('attachment_job_capacity');
        }
        if ((await _rows(
              'SELECT id FROM attachment_job WHERE id=? OR attachment=? OR version=?',
              [j.id, j.attachmentId, j.versionId],
            )).isNotEmpty ||
            (await _rows(
              'SELECT id FROM attachment_record WHERE id=? OR version=?',
              [j.attachmentId, j.versionId],
            )).isNotEmpty) {
          throw const CommandConflict('attachment_identity');
        }
        final record = AttachmentRecord(
          id: j.attachmentId,
          generation: j.generation,
          personId: j.personId,
          targetKind: j.targetKind,
          targetId: j.targetId,
          targetRevision: j.targetRevision,
          revision: 1,
          versionId: j.versionId,
          name: j.name,
          state: AttachmentState.staging,
          createdAt: j.createdAt,
        );
        await _db.customStatement(
          'INSERT INTO attachment_record VALUES (?,?,?,?,?,?,?,?,?)',
          [
            record.id,
            record.personId,
            record.targetKind.name,
            record.targetId,
            record.versionId,
            1,
            'staging',
            record.createdAt.microsecondsSinceEpoch,
            jsonEncode(record.toJson()),
          ],
        );
        await _db.customStatement(
          'INSERT INTO attachment_link VALUES (?,?,?,?,?)',
          [
            record.id,
            record.personId,
            record.targetKind == AttachmentTargetKind.item
                ? record.targetId
                : null,
            record.targetKind == AttachmentTargetKind.record
                ? record.targetId
                : null,
            record.targetKind == AttachmentTargetKind.supporting
                ? record.targetId
                : null,
          ],
        );
        await _db.customStatement(
          'INSERT INTO attachment_job VALUES (?,?,?,?,?,?,?,?,?)',
          [
            j.id,
            j.personId,
            j.attachmentId,
            j.versionId,
            j.state.name,
            0,
            j.createdAt.microsecondsSinceEpoch,
            jsonEncode(j.toJson()),
            0,
          ],
        );
        return {
          'person': j.personId,
          'attachmentId': j.attachmentId,
          'job': j.toJson(),
        };
      },
      failBeforeCommit: failBeforeCommit,
      beforeCommit: beforeCommit,
    );
    return AttachmentJob.fromJson(
      Map<String, Object?>.from(result['job'] as Map),
    );
  }

  Future<AttachmentJob> appendAttachmentChunk({
    required String commandId,
    required String jobId,
    required String generation,
    required int offset,
    required Uint8List bytes,
    bool failBeforeCommit = false,
    Future<void> Function()? beforeCommit,
  }) async {
    _dailyGeneration(generation);
    if (offset < 0 ||
        bytes.isEmpty ||
        bytes.length > AttachmentLimits.chunkBytes ||
        bytes.length > AttachmentLimits.maxInputBytes - offset) {
      throw const AttachmentFailure('attachment_byte_limit');
    }
    final captured = Uint8List.fromList(bytes),
        digest = sha256.convert(bytes).toString();
    final result = await _command(
      commandId,
      ['attachment_chunk', jobId, offset, bytes.length, digest],
      () async {
        final job = await attachmentJob(jobId);
        if (job == null) throw const CommandConflict('attachment_job');
        await _validateAttachmentTarget(job);
        if (![
              AttachmentJobState.awaitingPicker,
              AttachmentJobState.importing,
              AttachmentJobState.interrupted,
            ].contains(job.state) ||
            job.receivedBytes != offset) {
          throw const CommandConflict('attachment_job_revision');
        }
        await _db.customStatement(
          'INSERT INTO attachment_chunk VALUES (?,?,?,?)',
          [job.versionId, offset, captured, digest],
        );
        final next = _attachmentJobChange(
          job,
          state: AttachmentJobState.importing,
          receivedBytes: offset + captured.length,
        );
        await _putAttachmentJob(next);
        return {
          'person': job.personId,
          'attachmentId': job.attachmentId,
          'job': next.toJson(),
        };
      },
      failBeforeCommit: failBeforeCommit,
      beforeCommit: beforeCommit,
    );
    return AttachmentJob.fromJson(
      Map<String, Object?>.from(result['job'] as Map),
    );
  }

  Stream<Uint8List> _attachmentChunks(String version, int byteCount) async* {
    var offset = 0;
    while (offset < byteCount) {
      _requireWritable();
      final rows = await _rows(
        'SELECT offset,bytes,digest FROM attachment_chunk WHERE version=? AND offset=?',
        [version, offset],
      );
      if (rows.length != 1) {
        throw const AttachmentFailure('attachment_incomplete');
      }
      final data = rows.single['bytes'] as Uint8List;
      if (data.isEmpty ||
          data.length > AttachmentLimits.chunkBytes ||
          sha256.convert(data).toString() != rows.single['digest']) {
        throw const AttachmentFailure('attachment_corrupt');
      }
      offset += data.length;
      if (offset > byteCount) {
        throw const AttachmentFailure('attachment_incomplete');
      }
      yield Uint8List.fromList(data);
    }
  }

  Future<AttachmentRecord> publishAttachment({
    required String commandId,
    required String jobId,
    required String generation,
    required AttachmentInspection inspection,
    String? name,
    bool failBeforeCommit = false,
    Future<void> Function()? beforeCommit,
    Future<void> Function()? afterVerification,
  }) async {
    _dailyGeneration(generation);
    _requireWritable();
    // Replay precedes target validation, but always retains the original payload.
    final captured = await _rows(
      'SELECT snapshot,revision FROM attachment_job WHERE id=?',
      [jobId],
    );
    if (captured.isEmpty) throw const CommandConflict('attachment_job');
    final job = _attachmentJobRead(captured.single);
    if (job.pickerKind != AttachmentPickerKind.file &&
        inspection.mediaKind != AttachmentMediaKind.image) {
      throw const AttachmentFailure('attachment_image_required');
    }
    final capturedJobRevision = captured.single['revision'];
    final displayName = name ?? job.name;
    if (displayName.trim().isEmpty || displayName.length > 255) {
      throw const AttachmentFailure('attachment_name');
    }
    final prior = await _rows('SELECT result FROM operation WHERE id=?', [
      commandId,
    ]);
    if (prior.isEmpty) {
      if (job.state != AttachmentJobState.importing ||
          job.receivedBytes != inspection.byteCount) {
        throw const AttachmentFailure('attachment_incomplete');
      }
      final digest = await sha256
          .bind(_attachmentChunks(job.versionId, job.receivedBytes))
          .first;
      if (digest.toString() != inspection.sha256) {
        throw const AttachmentFailure('attachment_hash');
      }
    }
    await afterVerification?.call();
    final result = await _command(
      commandId,
      [
        'attachment_publish',
        job.personId,
        jobId,
        inspection.toJson(),
        displayName,
      ],
      () async {
        final current = await attachmentJob(jobId);
        if (current == null ||
            current.state != AttachmentJobState.importing ||
            current.receivedBytes != inspection.byteCount ||
            current.versionId != job.versionId) {
          throw const CommandConflict('attachment_job_revision');
        }
        if ((await _rows('SELECT revision FROM attachment_job WHERE id=?', [
              jobId,
            ])).single['revision'] !=
            capturedJobRevision) {
          throw const CommandConflict('attachment_job_revision');
        }
        await _validateAttachmentTarget(current);
        final record = AttachmentRecord(
          id: current.attachmentId,
          generation: generation,
          personId: current.personId,
          targetKind: current.targetKind,
          targetId: current.targetId,
          targetRevision: current.targetRevision,
          revision: 1,
          versionId: current.versionId,
          name: displayName,
          state: AttachmentState.ready,
          createdAt: current.createdAt,
          inspection: inspection,
        );
        await _db.customStatement(
          "UPDATE attachment_record SET state='ready',snapshot=? WHERE id=? AND state='staging'",
          [jsonEncode(record.toJson()), record.id],
        );
        await _putAttachmentJob(
          _attachmentJobChange(current, state: AttachmentJobState.ready),
        );
        return {
          'person': current.personId,
          'attachmentId': record.id,
          'attachment': record.toJson(),
        };
      },
      failBeforeCommit: failBeforeCommit,
      beforeCommit: beforeCommit,
    );
    return AttachmentRecord.fromJson(
      Map<String, Object?>.from(result['attachment'] as Map),
    );
  }

  Future<AttachmentRecord?> attachmentById(String id) async {
    _requireWritable();
    final rows = await _rows(
      "SELECT r.snapshot FROM attachment_record r JOIN attachment_link l ON l.attachment=r.id AND l.person=r.person WHERE r.id=? AND r.state='ready'",
      [id],
    );
    return rows.isEmpty ? null : _attachmentRead(rows.single);
  }

  Future<List<AttachmentRecord>> attachments({
    required String personId,
    AttachmentTargetKind? targetKind,
    String? targetId,
    int limit = 100,
    int offset = 0,
  }) async {
    _requireWritable();
    _pageBounds(limit, offset);
    return (await _rows(
      "SELECT snapshot FROM attachment_record WHERE person=? AND state='ready' AND EXISTS(SELECT 1 FROM attachment_link l WHERE l.attachment=attachment_record.id AND l.person=attachment_record.person) ${targetKind == null ? '' : 'AND target_kind=?'} ${targetId == null ? '' : 'AND target=?'} ORDER BY created_at DESC,id LIMIT ? OFFSET ?",
      [
        personId,
        if (targetKind != null) targetKind.name,
        ?targetId,
        limit,
        offset,
      ],
    )).map(_attachmentRead).toList();
  }

  Stream<List<AttachmentRecord>> watchAttachments({
    required String personId,
    AttachmentTargetKind? targetKind,
    String? targetId,
    int limit = 100,
    int offset = 0,
  }) => _watch(
    () => attachments(
      personId: personId,
      targetKind: targetKind,
      targetId: targetId,
      limit: limit,
      offset: offset,
    ),
  );
  Stream<List<AttachmentJob>> watchAttachmentJobs() =>
      _watch(pendingAttachmentJobs);
  Future<AttachmentRecord> _attachmentContext(
    AttachmentRecord attachment,
    int expectedPersonRevision,
  ) async {
    _dailyGeneration(attachment.generation);
    await _activeOwner(attachment.personId, expectedPersonRevision);
    final current = await attachmentById(attachment.id);
    if (current == null ||
        current.revision != attachment.revision ||
        current.personId != attachment.personId ||
        current.versionId != attachment.versionId) {
      throw const CommandConflict('attachment_revision');
    }
    return current;
  }

  Future<AttachmentRecord> renameAttachment({
    required String commandId,
    required AttachmentRecord attachment,
    required int expectedPersonRevision,
    required String name,
  }) async {
    _dailyGeneration(attachment.generation);
    if (name.trim().isEmpty || name.length > 255) {
      throw const AttachmentFailure('attachment_name');
    }
    final result = await _command(
      commandId,
      [
        'attachment_rename',
        attachment.personId,
        attachment.id,
        attachment.revision,
        expectedPersonRevision,
        name,
      ],
      () async {
        final current = await _attachmentContext(
          attachment,
          expectedPersonRevision,
        );
        final next = AttachmentRecord.fromJson({
          ...current.toJson(),
          'name': name,
          'revision': current.revision + 1,
        });
        await _db.customStatement(
          'UPDATE attachment_record SET revision=?,snapshot=? WHERE id=?',
          [next.revision, jsonEncode(next.toJson()), next.id],
        );
        return {
          'person': next.personId,
          'attachmentId': next.id,
          'attachment': next.toJson(),
        };
      },
    );
    return AttachmentRecord.fromJson(
      Map<String, Object?>.from(result['attachment'] as Map),
    );
  }

  Future<void> _reclaimAttachment(String id) async {
    final rows = await _rows(
      "SELECT version FROM attachment_record WHERE id=? AND state='deleting'",
      [id],
    );
    if (rows.isEmpty) return;
    final version = rows.single['version'];
    if ((await _rows('SELECT id FROM attachment_pin WHERE version=? LIMIT 1', [
      version,
    ])).isNotEmpty) {
      return;
    }
    await _db.customStatement('DELETE FROM attachment_chunk WHERE version=?', [
      version,
    ]);
    await _db.customStatement('DELETE FROM attachment_job WHERE attachment=?', [
      id,
    ]);
    await _db.customStatement('DELETE FROM attachment_record WHERE id=?', [id]);
  }

  Future<void> _invalidateAttachmentOperations(String id) async {
    await _db.customStatement(
      "UPDATE operation SET payload='[]',result='{\"invalidated\":true}' WHERE json_extract(result,'\$.attachmentId')=?",
      [id],
    );
    final drafts = await _rows(
      "SELECT operation FROM ordinary_draft WHERE target=? AND kind='attachmentRename'",
      [id],
    );
    for (final d in drafts) {
      await _db.customStatement(
        "INSERT INTO operation VALUES (?,'[]','{\"invalidated\":true}') ON CONFLICT(id) DO NOTHING",
        [d['operation']],
      );
    }
    await _db.customStatement(
      "DELETE FROM ordinary_draft WHERE target=? AND kind='attachmentRename'",
      [id],
    );
  }

  Future<void> deleteAttachment({
    required String commandId,
    required AttachmentRecord attachment,
    required int expectedPersonRevision,
    bool failBeforeCommit = false,
    Future<void> Function()? beforeCommit,
  }) async {
    _dailyGeneration(attachment.generation);
    await _command(
      commandId,
      [
        'attachment_delete',
        attachment.personId,
        attachment.id,
        attachment.revision,
        expectedPersonRevision,
      ],
      () async {
        final current = await _attachmentContext(
          attachment,
          expectedPersonRevision,
        );
        final next = AttachmentRecord.fromJson({
          ...current.toJson(),
          'state': 'deleting',
          'revision': current.revision + 1,
        });
        await _db.customStatement(
          "UPDATE attachment_record SET state='deleting',revision=?,snapshot=? WHERE id=?",
          [next.revision, jsonEncode(next.toJson()), next.id],
        );
        await _db.customStatement(
          'DELETE FROM attachment_link WHERE attachment=?',
          [current.id],
        );
        await _invalidateAttachmentOperations(current.id);
        // Pins retain their selected immutable version until the owning job releases.
        await _reclaimAttachment(current.id);
        return {
          'person': current.personId,
          'attachmentId': current.id,
          'deleted': true,
        };
      },
      failBeforeCommit: failBeforeCommit,
      beforeCommit: beforeCommit,
    );
  }

  Future<void> cancelAttachment({
    required String commandId,
    required String jobId,
    required String generation,
  }) async {
    _dailyGeneration(generation);
    await _command(commandId, ['attachment_cancel', jobId], () async {
      final job = await attachmentJob(jobId);
      if (job == null) throw const CommandConflict('attachment_job');
      if (job.state == AttachmentJobState.ready) {
        throw const CommandConflict('attachment_job_state');
      }
      await _invalidateAttachmentOperations(job.attachmentId);
      await _db.customStatement(
        'DELETE FROM attachment_link WHERE attachment=?',
        [job.attachmentId],
      );
      await _db.customStatement(
        "UPDATE attachment_record SET state='deleting',snapshot=json_set(snapshot,'\$.state','deleting') WHERE id=?",
        [job.attachmentId],
      );
      await _reclaimAttachment(job.attachmentId);
      return {
        'person': job.personId,
        'attachmentId': job.attachmentId,
        'cancelled': true,
      };
    });
  }

  Future<AttachmentPin> pinAttachment({
    required String id,
    required String generation,
    required int expectedRevision,
    String purpose = 'preview',
    String? sessionId,
    DateTime? expiresAt,
  }) async {
    _dailyGeneration(generation);
    _requireWritable();
    if (sessionId != null) attachmentIdentity(sessionId);
    final pinNow = DateTime.now().toUtc();
    if (expiresAt != null &&
        (!expiresAt.isUtc ||
            !expiresAt.isAfter(pinNow) ||
            purpose == 'handoff' &&
                expiresAt.isAfter(
                  pinNow.add(AttachmentLimits.handoffLifetime),
                ))) {
      throw const AttachmentFailure('attachment_pin_lifetime');
    }
    if (![
          'preview',
          'report',
          'export',
          'backup',
          'handoff',
        ].contains(purpose) ||
        purpose == 'handoff' && (expiresAt == null || !expiresAt.isUtc)) {
      throw const AttachmentFailure('attachment_pin');
    }
    return _reminderTransaction(() async {
      _requireWritable();
      final current = await attachmentById(id);
      if (current == null || current.revision != expectedRevision) {
        throw const CommandConflict('attachment_revision');
      }
      final pin = AttachmentPin(
        id: newCommandId(),
        attachment: current,
        sessionId: sessionId ?? generation,
        purpose: purpose,
        expiresAt: expiresAt,
      );
      await _db.customStatement(
        'INSERT INTO attachment_pin VALUES (?,?,?,?,?,?,?)',
        [
          pin.id,
          pin.versionId,
          current.id,
          pin.sessionId,
          pin.purpose,
          pin.expiresAt?.microsecondsSinceEpoch,
          jsonEncode(pin.toJson()),
        ],
      );
      return pin;
    });
  }

  Future<void> _validateAttachmentPin(AttachmentPin pin) async {
    _dailyGeneration(pin.generation);
    _requireWritable();
    if ((await _rows('SELECT generation FROM dataset')).single['generation'] !=
        generation) {
      throw const CommandConflict('generation');
    }
    final rows = await _rows('SELECT snapshot FROM attachment_pin WHERE id=?', [
      pin.id,
    ]);
    if (rows.isEmpty ||
        rows.single['snapshot'] != jsonEncode(pin.toJson()) ||
        pin.expiresAt != null &&
            !pin.expiresAt!.isAfter(DateTime.now().toUtc())) {
      throw const CommandConflict('attachment_pin');
    }
  }

  Stream<Uint8List> readAttachmentPin(AttachmentPin pin) async* {
    await _validateAttachmentPin(pin);
    final byteCount = pin.attachment.inspection?.byteCount;
    if (byteCount == null) {
      throw const AttachmentFailure('attachment_incomplete');
    }
    await for (final bytes in _attachmentChunks(pin.versionId, byteCount)) {
      await _validateAttachmentPin(pin);
      yield bytes;
    }
  }

  Future<void> releaseAttachmentPin(AttachmentPin pin) async {
    _dailyGeneration(pin.generation);
    await _reminderTransaction(() async {
      final rows = await _rows(
        'SELECT snapshot FROM attachment_pin WHERE id=?',
        [pin.id],
      );
      if (rows.isNotEmpty &&
          rows.single['snapshot'] != jsonEncode(pin.toJson())) {
        throw const CommandConflict('attachment_pin');
      }
      await _db.customStatement('DELETE FROM attachment_pin WHERE id=?', [
        pin.id,
      ]);
      await _reclaimAttachment(pin.attachment.id);
    });
  }

  Future<void> _forgetAttachmentPerson(String person) async {
    await _db.customStatement('DELETE FROM attachment_link WHERE person=?', [
      person,
    ]);
    await _db.customStatement(
      "UPDATE attachment_record SET state='deleting',snapshot=json_set(snapshot,'\$.state','deleting') WHERE person=?",
      [person],
    );
    await _db.customStatement('DELETE FROM attachment_job WHERE person=?', [
      person,
    ]);
  }

  Future<bool> _cleanupAttachmentDeletes() => _reminderTransaction(() async {
    final rows = await _rows(
      "SELECT id FROM attachment_record WHERE state='deleting' AND NOT EXISTS(SELECT 1 FROM attachment_pin p WHERE p.version=attachment_record.version) ORDER BY id LIMIT 5",
    );
    for (final row in rows.take(4)) {
      await _reclaimAttachment(row['id'] as String);
    }
    return rows.length <= 4;
  });

  /// Narrow expiry-only maintenance, also permitted while clinical reads and
  /// writes are locked. It never returns attachment data or abandons a session.
  Future<void> expireAttachmentPins({DateTime? now}) =>
      _cleanupAttachmentPins(now: now);

  Future<void> _cleanupAttachmentPins({
    DateTime? now,
    String? abandonSession,
  }) async {
    var cleanupPending = false;
    await _reminderTransaction(() async {
      final moment = (now ?? DateTime.now()).toUtc().microsecondsSinceEpoch;
      final pins = await _rows(
        // Backup pins have their own expiry and startup release. Preserve them
        // while a capture may still be validating the pinned versions.
        "SELECT id,attachment FROM attachment_pin WHERE (expires IS NOT NULL AND expires<=?) ${abandonSession != null ? "OR (purpose<>'handoff' AND purpose<>'backup' AND session<>?)" : ''} ORDER BY id LIMIT 257",
        [moment, ?abandonSession],
      );
      cleanupPending = pins.length > 256;
      for (final pin in pins.take(256)) {
        await _db.customStatement('DELETE FROM attachment_pin WHERE id=?', [
          pin['id'],
        ]);
      }
    });
    final contentComplete = await _cleanupAttachmentDeletes();
    if (cleanupPending || !contentComplete) {
      throw const AttachmentFailure('attachment_cleanup_pending');
    }
  }

  Future<List<AttachmentJob>> recoverAttachmentState({
    required String sessionId,
    DateTime? now,
    bool abandonOtherSessions = true,
  }) async {
    _requireWritable();
    attachmentIdentity(sessionId);
    await _cleanupAttachmentPins(
      now: now,
      abandonSession: abandonOtherSessions ? sessionId : null,
    );
    return pendingAttachmentJobs();
  }

  Stream<AttachmentRecord?> watchAttachmentById(String id) =>
      _watch(() => attachmentById(id));
  Future<AttachmentJob> restartAttachmentJob({
    required String commandId,
    required String jobId,
    required String generation,
  }) async {
    _dailyGeneration(generation);
    final result = await _command(
      commandId,
      ['attachment_restart', jobId],
      () async {
        final job = await attachmentJob(jobId);
        if (job == null ||
            ![
              AttachmentJobState.awaitingPicker,
              AttachmentJobState.importing,
              AttachmentJobState.interrupted,
            ].contains(job.state)) {
          throw const CommandConflict('attachment_job_state');
        }
        await _validateAttachmentTarget(job);
        await _invalidateAttachmentOperations(job.attachmentId);
        await _db.customStatement(
          'DELETE FROM attachment_chunk WHERE version=?',
          [job.versionId],
        );
        final next = _attachmentJobChange(
          job,
          state: AttachmentJobState.awaitingPicker,
          receivedBytes: 0,
        );
        await _putAttachmentJob(next);
        return {
          'person': job.personId,
          'attachmentId': job.attachmentId,
          'job': next.toJson(),
        };
      },
    );
    return AttachmentJob.fromJson(
      Map<String, Object?>.from(result['job'] as Map),
    );
  }
}
