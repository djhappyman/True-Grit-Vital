part of 'record_store.dart';

/// One captured, still-internal SQLite snapshot. It remains encrypted by the
/// live dataset key and is not distributed directly.
final class BackupSnapshotFile {
  const BackupSnapshotFile({
    required this.path,
    required this.generation,
    required this.schemaVersion,
    required this.byteCount,
    required this.sha256,
  });
  final String path, generation, sha256;
  final int schemaVersion, byteCount;
}

extension BackupRecordStore on RecordStore {
  Future<void> _backupAssertGeneration(String expected) async {
    if ((await _rows('SELECT generation FROM dataset')).single['generation'] !=
        expected) {
      throw const CommandConflict('generation');
    }
  }

  Future<int> _backupSchemaVersion() async {
    final rows = await _rows('PRAGMA user_version');
    final value = rows.single.values.single;
    if (value is! int || value < 1) {
      throw StateError('uninitialised_dataset');
    }
    return value;
  }

  AttachmentRecord _backupAttachmentRead(Map<String, Object?> row) =>
      AttachmentRecord.fromJson(
        Map<String, Object?>.from(
          jsonDecode(row['snapshot']! as String) as Map,
        ),
      );

  Future<void> _backupReclaimDeleting() async {
    final rows = await _rows(
      "SELECT id,version FROM attachment_record WHERE state='deleting' AND NOT EXISTS(SELECT 1 FROM attachment_pin p WHERE p.version=attachment_record.version) ORDER BY id LIMIT 5",
    );
    for (final row in rows.take(4)) {
      final id = row['id']! as String;
      final version = row['version']! as String;
      await _db.customStatement(
        'DELETE FROM attachment_chunk WHERE version=?',
        [version],
      );
      await _db.customStatement(
        'DELETE FROM attachment_job WHERE attachment=?',
        [id],
      );
      await _db.customStatement('DELETE FROM attachment_record WHERE id=?', [
        id,
      ]);
    }
  }

  Future<void> _backupPinAttachments(String sessionId) async {
    final rows = await _rows(
      "SELECT snapshot FROM attachment_record r WHERE r.state='ready' AND EXISTS(SELECT 1 FROM attachment_link l WHERE l.attachment=r.id AND l.person=r.person) ORDER BY r.id LIMIT ?",
      [BackupLimits.maxAttachmentCount + 1],
    );
    if (rows.length > BackupLimits.maxAttachmentCount) {
      throw const BackupFailure('backup_too_large');
    }
    if (rows.isEmpty) return;
    final expires = DateTime.now()
        .toUtc()
        .add(BackupLimits.pinLifetime)
        .microsecondsSinceEpoch;
    await _reminderTransaction(() async {
      for (final row in rows) {
        final attachment = _backupAttachmentRead(row);
        final pin = AttachmentPin(
          id: 'b${BackupLimits.randomHex(16)}',
          attachment: attachment,
          sessionId: sessionId,
          purpose: 'backup',
        );
        await _db.customStatement(
          'INSERT INTO attachment_pin(id,version,attachment,session,purpose,expires,snapshot) VALUES (?,?,?,?,?,?,?)',
          [
            pin.id,
            attachment.versionId,
            attachment.id,
            sessionId,
            'backup',
            expires,
            jsonEncode(pin.toJson()),
          ],
        );
      }
    });
  }

  /// Captures one coherent encrypted database view. Attachment bytes live in
  /// `attachment_chunk` inside the encrypted database, so no separate external
  /// originals are copied or hashed opportunistically. Pins retain the exact
  /// ready versions while the archive is validated.
  Future<BackupSnapshotFile> createBackupSnapshot({
    required Directory directory,
    required String sessionId,
  }) async {
    _requireWritable();
    attachmentIdentity(sessionId);
    await directory.create(recursive: true);
    final file = File('${directory.path}/snapshot-$sessionId.db');
    if (await file.exists()) throw const BackupFailure('backup_staging');
    final expectedGeneration = generation;
    final schemaVersion = await _backupSchemaVersion();
    await _backupPinAttachments(sessionId);
    try {
      await _backupAssertGeneration(expectedGeneration);
      final escaped = file.path.replaceAll("'", "''");
      await _db.customStatement("VACUUM INTO '$escaped'");
      await _backupAssertGeneration(expectedGeneration);
      final bytes = await file.length();
      if (bytes < 512 || bytes > BackupLimits.maxSnapshotBytes) {
        throw const BackupFailure('backup_too_large');
      }
      final digest = await sha256.bind(file.openRead()).first;
      return BackupSnapshotFile(
        path: file.path,
        generation: expectedGeneration,
        schemaVersion: schemaVersion,
        byteCount: bytes,
        sha256: digest.toString(),
      );
    } catch (_) {
      try {
        if (await file.exists()) await file.delete();
      } catch (_) {}
      rethrow;
    }
  }

  Future<void> releaseBackupPins(String sessionId) async {
    await _reminderTransaction(() async {
      await _db.customStatement(
        "DELETE FROM attachment_pin WHERE purpose='backup' AND session=?",
        [sessionId],
      );
    });
    await _backupReclaimDeleting();
  }

  /// A startup cleanup has no active capture in this process, so every backup
  /// pin is abandoned. Clearing them lets interrupted deletions finish.
  Future<void> clearBackupPins() async {
    await _reminderTransaction(() async {
      await _db.customStatement(
        "DELETE FROM attachment_pin WHERE purpose='backup'",
      );
    });
    await _backupReclaimDeleting();
  }

  Future<void> expireBackupPins({DateTime? now}) async {
    final moment = (now ?? DateTime.now()).toUtc().microsecondsSinceEpoch;
    await _reminderTransaction(() async {
      await _db.customStatement(
        "DELETE FROM attachment_pin WHERE purpose='backup' AND expires IS NOT NULL AND expires<=?",
        [moment],
      );
    });
    await _backupReclaimDeleting();
  }

  Future<BackupInventory> inspectOwnSnapshot(
    BackupSnapshotFile snapshot, {
    BackupCancellationToken? token,
    void Function(int validatedRows)? onValidatedBatch,
  }) => inspectBackupSnapshot(
    path: snapshot.path,
    key: _key,
    token: token,
    onValidatedBatch: onValidatedBatch,
  );

  /// Encrypts the captured snapshot in a background isolate. The live dataset
  /// key never leaves the store by public API.
  Future<BackupArchiveSummary> writeBackupArchive({
    required BackupSnapshotFile snapshot,
    required String outputPath,
    required String password,
    required BackupHeader header,
    required BackupCancellationToken token,
    void Function(BackupProgress)? onProgress,
  }) => const BackupWorker().create(
    snapshot: File(snapshot.path),
    output: File(outputPath),
    password: password,
    header: header,
    datasetKey: _key,
    token: token,
    onProgress: onProgress,
  );

  /// Read-only chunk stream that does not depend on the app-lock write gate.
  Stream<Uint8List> _backupChunks(
    String version,
    int byteCount, [
    BackupCancellationToken? token,
  ]) async* {
    var offset = 0;
    while (offset < byteCount) {
      token?.throwIfCancelled();
      final rows = await _rows(
        'SELECT offset,bytes,digest FROM attachment_chunk WHERE version=? AND offset=?',
        [version, offset],
      );
      if (rows.length != 1) {
        throw const BackupFailure('backup_attachment_mismatch');
      }
      token?.throwIfCancelled();
      final data = rows.single['bytes'] as Uint8List;
      if (data.isEmpty ||
          data.length > AttachmentLimits.chunkBytes ||
          sha256.convert(data).toString() != rows.single['digest']) {
        throw const BackupFailure('backup_attachment_mismatch');
      }
      offset += data.length;
      if (offset > byteCount) {
        throw const BackupFailure('backup_attachment_mismatch');
      }
      yield Uint8List.fromList(data);
    }
  }

  Future<BackupInventory> _backupInventory([
    BackupCancellationToken? token,
    void Function(int validatedRows)? onValidatedBatch,
  ]) async {
    token?.throwIfCancelled();
    if ((await _rows('PRAGMA integrity_check')).single.values.single != 'ok') {
      throw const BackupFailure('backup_invalid_dataset');
    }
    if ((await _rows('PRAGMA foreign_key_check')).isNotEmpty) {
      throw const BackupFailure('backup_invalid_dataset');
    }
    await _validateBackupQuantities(token, onValidatedBatch);
    final dataset = await _rows('SELECT generation FROM dataset');
    if (dataset.length != 1) {
      throw const BackupFailure('backup_invalid_dataset');
    }
    final generation = dataset.single['generation']! as String;
    final schemaVersion = await _backupSchemaVersion();
    final peopleRows = await _rows(
      'SELECT id,name,archived FROM person ORDER BY archived,id LIMIT 201',
    );
    final peopleCount =
        (await _rows('SELECT count(*) c FROM person')).single['c']! as int;
    final people = peopleRows
        .take(200)
        .map(
          (row) => BackupPerson(
            id: row['id']! as String,
            name: row['name']! as String,
            archived: row['archived'] == 1,
          ),
        )
        .toList(growable: false);

    if ((await _rows(
          "SELECT count(*) c FROM attachment_record r WHERE r.state='ready' AND NOT EXISTS(SELECT 1 FROM attachment_link l WHERE l.attachment=r.id AND l.person=r.person)",
        )).single['c'] !=
        0) {
      throw const BackupFailure('backup_invalid_dataset');
    }
    if ((await _rows(
          'SELECT count(*) c FROM attachment_link l JOIN attachment_record r ON r.id=l.attachment WHERE l.person<>r.person',
        )).single['c'] !=
        0) {
      throw const BackupFailure('backup_invalid_dataset');
    }

    final attachments = await _rows(
      "SELECT snapshot FROM attachment_record r WHERE r.state='ready' AND EXISTS(SELECT 1 FROM attachment_link l WHERE l.attachment=r.id AND l.person=r.person) ORDER BY r.id LIMIT ?",
      [BackupLimits.maxAttachmentCount + 1],
    );
    if (attachments.length > BackupLimits.maxAttachmentCount) {
      throw const BackupFailure('backup_too_large');
    }
    var attachmentBytes = 0;
    final lines = <String>[];
    for (final row in attachments) {
      token?.throwIfCancelled();
      final attachment = _backupAttachmentRead(row);
      final inspection = attachment.inspection;
      if (inspection == null) {
        throw const BackupFailure('backup_attachment_mismatch');
      }
      final digest = await sha256
          .bind(
            _backupChunks(attachment.versionId, inspection.byteCount, token),
          )
          .first;
      token?.throwIfCancelled();
      if (digest.toString() != inspection.sha256) {
        throw const BackupFailure('backup_attachment_mismatch');
      }
      attachmentBytes += inspection.byteCount;
      lines.add(
        '${attachment.id}|${attachment.versionId}|${inspection.byteCount}|${inspection.sha256}',
      );
    }
    final attachmentSha256 = sha256
        .convert(utf8.encode(lines.join('\n')))
        .toString();

    final recordRange = (await _rows(
      'SELECT count(*) c,min(r.actual) lo,max(r.actual) hi FROM administration a JOIN revision r ON r.record=a.id AND r.person=a.person AND r.revision=a.revision WHERE r.voided=0',
    )).single;
    final itemCount =
        (await _rows('SELECT count(*) c FROM item')).single['c']! as int;
    final supportingCount =
        (await _rows(
              'SELECT count(*) c FROM supporting_record WHERE voided=0',
            )).single['c']!
            as int;
    final recordCount = recordRange['c']! as int;
    final lo = recordRange['lo'] as int?;
    final hi = recordRange['hi'] as int?;
    final recordByPerson = {
      for (final row in await _rows(
        'SELECT a.person p,count(*) c,min(r.actual) lo,max(r.actual) hi FROM administration a JOIN revision r ON r.record=a.id AND r.person=a.person AND r.revision=a.revision WHERE r.voided=0 GROUP BY a.person',
      ))
        row['p']! as String: row,
    };
    final attachmentsByPerson = {
      for (final row in await _rows(
        "SELECT r.person p,count(*) c FROM attachment_record r WHERE r.state='ready' AND EXISTS(SELECT 1 FROM attachment_link l WHERE l.attachment=r.id AND l.person=r.person) GROUP BY r.person",
      ))
        row['p']! as String: row['c']! as int,
    };
    final coverage = people
        .map((person) {
          final row = recordByPerson[person.id];
          final personLo = row?['lo'] as int?;
          final personHi = row?['hi'] as int?;
          return BackupPersonCoverage(
            person: person,
            recordCount: (row?['c'] as int?) ?? 0,
            attachmentCount: attachmentsByPerson[person.id] ?? 0,
            earliestRecord: personLo == null
                ? null
                : DateTime.fromMicrosecondsSinceEpoch(personLo, isUtc: true),
            latestRecord: personHi == null
                ? null
                : DateTime.fromMicrosecondsSinceEpoch(personHi, isUtc: true),
          );
        })
        .toList(growable: false);
    // The awaited quantity and metadata scans above consume event-loop turns
    // after the earlier boundaries, so a command cancelled during them fails
    // closed here instead of returning a completed result.
    token?.throwIfCancelled();
    return BackupInventory(
      generation: generation,
      schemaVersion: schemaVersion,
      people: people,
      peopleCount: peopleCount,
      recordCount: recordCount,
      itemCount: itemCount,
      supportingCount: supportingCount,
      attachmentCount: attachments.length,
      attachmentBytes: attachmentBytes,
      attachmentSha256: attachmentSha256,
      coverage: coverage,
      earliestRecord: lo == null
          ? null
          : DateTime.fromMicrosecondsSinceEpoch(lo, isUtc: true),
      latestRecord: hi == null
          ? null
          : DateTime.fromMicrosecondsSinceEpoch(hi, isUtc: true),
    );
  }

  /// SQL integrity does not establish the meaning of quantity text. Validate
  /// every historical revision and exact pair before accepting an archive.
  ///
  /// [onValidatedBatch] is an optional synchronous inspection progress
  /// observer. It is called after each completed nonempty bounded validation
  /// batch with the cumulative count of validated rows. The count describes
  /// row work done for inspection only; it is NOT a clinical dose count or a
  /// byte volume. Production callers omit it. Cancellation is re-checked at
  /// the next boundary after the observer returns and before further work, so
  /// an observer that cancels the token stops the scan before the next batch.
  Future<void> _validateBackupQuantities([
    BackupCancellationToken? token,
    void Function(int validatedRows)? onValidatedBatch,
  ]) async {
    var validatedRows = 0;
    for (final table in ['revision', 'revision_quantity']) {
      token?.throwIfCancelled();
      String? record;
      var revision = 0;
      var inspected = 0;
      while (true) {
        token?.throwIfCancelled();
        final columns = table == 'revision'
            ? 'record,revision,amount,entered'
            : 'record,revision,numerator,denominator,entered';
        final rows = await _rows(
          'SELECT $columns FROM $table ${record == null ? '' : 'WHERE record>? OR (record=? AND revision>?)'} ORDER BY record,revision LIMIT 500',
          [
            if (record != null) ...[record, record, revision],
          ],
        );
        inspected += rows.length;
        if (inspected > 2000000) throw const BackupFailure('backup_too_large');
        for (final row in rows) {
          token?.throwIfCancelled();
          try {
            final entered = ExactQuantity.parse(row['entered'] as String);
            if (table == 'revision') {
              if (entered.scaled != row['amount']) {
                throw const FormatException('quantity_scale');
              }
            } else {
              final actual = ExactAmount.fromStorage(
                row['numerator'] as String,
                row['denominator'] as String,
              );
              if (actual <= ExactAmount.zero) {
                throw const FormatException('quantity_positive');
              }
            }
          } catch (_) {
            throw const BackupFailure('backup_invalid_dataset');
          }
        }
        // The bounded batch completed with rows, so report the cumulative
        // validated row count whether or not a cancellation token exists.
        if (rows.isNotEmpty) {
          validatedRows += rows.length;
          onValidatedBatch?.call(validatedRows);
        }
        // Next-boundary position: honour a cancellation the observer issued
        // (or one that arrived mid-batch) before any further validation work.
        token?.throwIfCancelled();
        if (rows.length < 500) break;
        record = rows.last['record'] as String;
        revision = rows.last['revision'] as int;
      }
    }
  }
}

/// Opens a captured snapshot with its explicit dataset key and verifies every
/// row/file invariant required by recovery preview. It never activates data.
/// [token] bounds an abandoned validation attempt: a cancelled scan stops
/// before further re-hashing or row work and the caller deletes the staging.
/// [onValidatedBatch] is an optional synchronous inspection progress observer
/// (validated rows, not clinical dose counts or bytes) called after each
/// completed nonempty bounded quantity-validation batch; production callers
/// omit it.
Future<BackupInventory> inspectBackupSnapshot({
  required String path,
  required List<int> key,
  BackupCancellationToken? token,
  void Function(int validatedRows)? onValidatedBatch,
}) async {
  token?.throwIfCancelled();
  final store = await RecordStore.open(path: path, key: key, isNew: false);
  try {
    return await store._backupInventory(token, onValidatedBatch);
  } finally {
    await store.close();
  }
}

/// Re-keys a decrypted staged snapshot for a new installation. The old key is
/// never distributed in the archive in unwrapped form.
Future<void> rekeyBackupSnapshot({
  required String path,
  required List<int> currentKey,
  required List<int> newKey,
}) async {
  if (newKey.length != 32 || newKey.any((b) => b < 0 || b > 255)) {
    throw const BackupFailure('backup_key');
  }
  final store = await RecordStore.open(
    path: path,
    key: currentKey,
    isNew: false,
  );
  try {
    final hex = newKey.map((v) => v.toRadixString(16).padLeft(2, '0')).join();
    await store._db.customStatement("PRAGMA rekey = \"x'$hex'\"");
  } finally {
    await store.close();
  }
  final verified = await RecordStore.open(
    path: path,
    key: newKey,
    isNew: false,
  );
  await verified.close();
}
