part of 'record_store.dart';

/// One live installation's restore preparation. The stage count is bounded so
/// an oversized archive cannot turn validation into an unbounded scan.
extension RestoreRecordStore on RecordStore {
  /// Narrows the retained dataset key to one restore call. Never log, copy or
  /// persist the supplied bytes.
  Future<T> withRestoreKey<T>(Future<T> Function(List<int> key) body) =>
      body(_key);

  Future<String?> restoreObjectNamespace() async {
    final rows = await _rows('SELECT namespace FROM reminder_meta WHERE id=1');
    return rows.isEmpty ? null : rows.single['namespace'] as String;
  }

  /// Re-keys, migrates and scrubs a validated staged snapshot, then stamps a
  /// fresh local generation. The live store is untouched; the caller closes it
  /// only when activation is ready. Device-local drafts, operation receipts,
  /// native reminder payloads and attachment jobs never survive replacement,
  /// even when restored record or person IDs match.
  ///
  /// [token] is checked cooperatively before and after each await and after
  /// every bounded attachment-manifest batch. Cancellation only abandons this
  /// preparation; it never interrupts activation or a journal swap. The staged
  /// connection and empty sidecars are closed on every exit path, and the
  /// caller still discards the abandoned staged archive.
  ///
  /// [onManifestBatch] is a synchronous test observer invoked after each
  /// attachment-manifest page is written inside the preparation transaction. It
  /// carries no production state and is not called after cancellation.
  Future<RestorePreparedDatabase> prepareRestoredDatabase({
    required String stagedPath,
    required Future<void> Function(List<int> installationKey) rekeyTo,
    BackupCancellationToken? token,
    void Function()? onManifestBatch,
  }) async {
    _restoreThrowIfCancelled(token);
    _requireWritable();
    final installationAppLock = await readSetting('app_lock');
    _restoreThrowIfCancelled(token);
    final previousGeneration = generation;
    final previousNamespace = await restoreObjectNamespace();
    _restoreThrowIfCancelled(token);
    // The archive key never leaves the archive reader and this store.
    await rekeyTo(_key);
    _restoreThrowIfCancelled(token);
    final RecordStore staged;
    try {
      staged = await RecordStore.open(
        path: stagedPath,
        key: _key,
        isNew: false,
      );
    } on RestoreFailure {
      rethrow;
    } catch (_) {
      await _restoreRemoveEmptySidecars(stagedPath);
      throw const RestoreFailure(RestoreCodes.corrupt);
    }
    try {
      if (staged._closed) {
        throw const RestoreFailure(RestoreCodes.storage);
      }
      _restoreThrowIfCancelled(token);
      final integrity = await staged._rows('PRAGMA integrity_check');
      _restoreThrowIfCancelled(token);
      if (integrity.length != 1 || integrity.single.values.single != 'ok') {
        throw const RestoreFailure(RestoreCodes.corrupt);
      }
      final foreignKeys = await staged._rows('PRAGMA foreign_key_check');
      _restoreThrowIfCancelled(token);
      if (foreignKeys.isNotEmpty) {
        throw const RestoreFailure(RestoreCodes.corrupt);
      }
      try {
        await staged._validateBackupQuantities(token);
      } on BackupFailure catch (error) {
        if (error.code == 'backup_cancelled') {
          throw const RestoreFailure(RestoreCodes.cancelled);
        }
        throw const RestoreFailure(RestoreCodes.corrupt);
      }
      _restoreThrowIfCancelled(token);
      final dataset = await staged._rows('SELECT generation FROM dataset');
      _restoreThrowIfCancelled(token);
      if (dataset.length != 1 ||
          dataset.single['generation'] != staged.generation) {
        throw const RestoreFailure(RestoreCodes.corrupt);
      }
      final peopleRow = await staged._rows('SELECT count(*) c FROM person');
      _restoreThrowIfCancelled(token);
      final people = peopleRow.single['c']! as int;
      if (people != 1 ||
          (await staged._rows(
                "SELECT id FROM person WHERE id='me' AND archived=0",
              )).length !=
              1) {
        throw const RestoreFailure(RestoreCodes.multiplePeople);
      }
      await staged.enableSingleUser();
      _restoreThrowIfCancelled(token);
      final unlinked = await staged._rows(
        "SELECT count(*) c FROM attachment_record r WHERE r.state='ready' AND NOT EXISTS(SELECT 1 FROM attachment_link l WHERE l.attachment=r.id AND l.person=r.person)",
      );
      _restoreThrowIfCancelled(token);
      final mismatchedLinks = await staged._rows(
        'SELECT count(*) c FROM attachment_link l JOIN attachment_record r ON r.id=l.attachment WHERE l.person<>r.person',
      );
      _restoreThrowIfCancelled(token);
      if (unlinked.single['c'] != 0 || mismatchedLinks.single['c'] != 0) {
        throw const RestoreFailure(RestoreCodes.corrupt);
      }
      // Direct preparation of an arbitrary staged file must apply the same
      // archive-wide attachment bound as the authenticated archive reader.
      // Probe only one row beyond the bound so an oversized staged file cannot
      // turn this check itself into an unbounded scan.
      final attachmentProbe = await staged._rows(
        "SELECT 1 FROM attachment_record WHERE state='ready' LIMIT ?",
        [BackupLimits.maxAttachmentCount + 1],
      );
      _restoreThrowIfCancelled(token);
      if (attachmentProbe.length > BackupLimits.maxAttachmentCount) {
        throw const RestoreFailure(RestoreCodes.tooLarge);
      }
      _restoreThrowIfCancelled(token);
      final generation = newCommandId();
      final namespace = newCommandId();
      await staged._db.transaction(() async {
        _restoreThrowIfCancelled(token);
        // Device authentication is an installation choice. Restoring an old
        // archive must not silently disable the operator's current app lock.
        await staged._db.customStatement(
          "DELETE FROM setting WHERE key='app_lock'",
        );
        if (installationAppLock != null) {
          await staged._db.customStatement('INSERT INTO setting VALUES (?,?)', [
            'app_lock',
            installationAppLock,
          ]);
        }
        // Stale operation receipts become fail-closed tombstones. A replay of
        // an old action ID reports deleted context instead of stale success.
        await staged._db.customStatement(
          'UPDATE operation SET payload=\'[]\',result=\'{"invalidated":true}\'',
        );
        await staged._db.customStatement('DELETE FROM ordinary_draft');
        await staged._db.customStatement('DELETE FROM item_setup');
        await staged._db.customStatement('DELETE FROM reminder_pending');
        await staged._db.customStatement('DELETE FROM reminder_request');
        await staged._db.customStatement('DELETE FROM event_pending');
        await staged._db.customStatement('DELETE FROM event_end_request');
        await staged._db.customStatement('DELETE FROM stock_notice_request');
        await staged._db.customStatement('DELETE FROM stock_notice_episode');
        await staged._db.customStatement(
          'INSERT INTO reminder_meta(id,namespace,sequence,fingerprint) VALUES (1,?,0,\'\') ON CONFLICT(id) DO UPDATE SET namespace=excluded.namespace,sequence=0,fingerprint=\'\'',
          [namespace],
        );
        // Capture pins, picker jobs and staging/deleting attachment versions
        // are local in-flight state, never portable truth.
        await staged._db.customStatement('DELETE FROM attachment_pin');
        await staged._db.customStatement('DELETE FROM attachment_job');
        await staged._db.customStatement(
          "DELETE FROM attachment_record WHERE state IN ('staging','deleting')",
        );
        await staged._db.customStatement(
          'DELETE FROM attachment_chunk WHERE version NOT IN (SELECT version FROM attachment_record)',
        );
        // A ready manifest's snapshot carries the archive dataset generation as
        // operational metadata. Rebind those retained rows to the replacement
        // generation so pin, rename and delete accept the restored snapshot.
        // The content version, byte chunks, checksum, ownership, target
        // revision, metadata revision and provenance are left untouched.
        // Walk stable id keyset batches so a hostile or unusually large staged
        // dataset never materialises every retained manifest at once.
        String? attachmentCursor;
        while (true) {
          _restoreThrowIfCancelled(token);
          final rows = await staged._rows(
            "SELECT id,snapshot FROM attachment_record WHERE state='ready'"
            "${attachmentCursor == null ? '' : ' AND id>?'} "
            'ORDER BY id LIMIT $_restoreAttachmentBatch',
            [?attachmentCursor],
          );
          _restoreThrowIfCancelled(token);
          if (rows.isEmpty) break;
          for (final row in rows) {
            final id = row['id']! as String;
            final Map<String, Object?> snapshot;
            final AttachmentRecord retained;
            try {
              snapshot = Map<String, Object?>.from(
                jsonDecode(row['snapshot']! as String) as Map,
              );
              retained = AttachmentRecord.fromJson(snapshot);
            } catch (_) {
              throw const RestoreFailure(RestoreCodes.corrupt);
            }
            if (retained.id != id || retained.state != AttachmentState.ready) {
              throw const RestoreFailure(RestoreCodes.corrupt);
            }
            await staged._db.customStatement(
              'UPDATE attachment_record SET snapshot=? WHERE id=?',
              [
                jsonEncode({...snapshot, 'generation': generation}),
                id,
              ],
            );
            _restoreThrowIfCancelled(token);
          }
          attachmentCursor = rows.last['id']! as String;
          onManifestBatch?.call();
          _restoreThrowIfCancelled(token);
        }
        await staged._db.customStatement('UPDATE dataset SET generation=?', [
          generation,
        ]);
        if ((await staged._rows('SELECT generation FROM dataset'))
                    .single['generation'] !=
                generation ||
            (await staged._rows(
                  'SELECT namespace FROM reminder_meta WHERE id=1',
                )).single['namespace'] !=
                namespace) {
          throw const RestoreFailure(RestoreCodes.failed);
        }
      });
      _restoreThrowIfCancelled(token);
      await staged._db.customStatement('PRAGMA wal_checkpoint(TRUNCATE)');
      _restoreThrowIfCancelled(token);
      final counts = await staged._rows('''
        SELECT
          (SELECT count(*) FROM person) people,
          (SELECT count(*) FROM item) items,
          (SELECT count(*) FROM supporting_record WHERE voided=0) supporting,
          (SELECT count(*) FROM administration a JOIN revision r ON r.record=a.id AND r.person=a.person AND r.revision=a.revision WHERE r.voided=0) records,
          (SELECT count(*) FROM attachment_record WHERE state='ready') attachments
      ''');
      _restoreThrowIfCancelled(token);
      final row = counts.single;
      final schemaVersion = await staged._restoreSchemaVersion();
      _restoreThrowIfCancelled(token);
      return RestorePreparedDatabase(
        path: stagedPath,
        previousGeneration: previousGeneration,
        generation: generation,
        previousNamespace: previousNamespace,
        reminderNamespace: namespace,
        schemaVersion: schemaVersion,
        peopleCount: row['people']! as int,
        recordCount: row['records']! as int,
        itemCount: row['items']! as int,
        supportingCount: row['supporting']! as int,
        attachmentCount: row['attachments']! as int,
      );
    } finally {
      await staged.close();
      await _restoreRemoveEmptySidecars(stagedPath);
    }
  }

  Future<int> _restoreSchemaVersion() async {
    final rows = await _rows('PRAGMA user_version');
    final value = rows.single.values.single;
    if (value is! int || value < 1) {
      throw const RestoreFailure(RestoreCodes.corrupt);
    }
    return value;
  }
}

/// Keyset page for rebinding retained attachment manifests during restore.
/// Keeps transient manifest memory bounded independently of archive size.
const _restoreAttachmentBatch = 128;

/// Cooperative preparation cancellation. The restore flow never passes a token
/// into activation, so this can only abandon work before the journal boundary.
void _restoreThrowIfCancelled(BackupCancellationToken? token) {
  if (token?.isCancelled ?? false) {
    throw const RestoreFailure(RestoreCodes.cancelled);
  }
}

Future<void> _restoreRemoveEmptySidecars(String path) async {
  for (final suffix in ['-wal', '-shm', '-journal']) {
    final file = File('$path$suffix');
    if (!await file.exists()) continue;
    if (await file.length() != 0) {
      throw const RestoreFailure(RestoreCodes.storage);
    }
    try {
      await file.delete();
    } on FileSystemException {
      throw const RestoreFailure(RestoreCodes.storage);
    }
  }
}
