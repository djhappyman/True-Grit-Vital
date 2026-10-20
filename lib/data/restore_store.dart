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
  Future<RestorePreparedDatabase> prepareRestoredDatabase({
    required String stagedPath,
    required Future<void> Function(List<int> installationKey) rekeyTo,
  }) async {
    _requireWritable();
    final installationAppLock = await readSetting('app_lock');
    final previousGeneration = generation;
    final previousNamespace = await restoreObjectNamespace();
    // The archive key never leaves the archive reader and this store.
    await rekeyTo(_key);
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
      final integrity = await staged._rows('PRAGMA integrity_check');
      if (integrity.length != 1 || integrity.single.values.single != 'ok') {
        throw const RestoreFailure(RestoreCodes.corrupt);
      }
      if ((await staged._rows('PRAGMA foreign_key_check')).isNotEmpty) {
        throw const RestoreFailure(RestoreCodes.corrupt);
      }
      try {
        await staged._validateBackupQuantities();
      } on BackupFailure {
        throw const RestoreFailure(RestoreCodes.corrupt);
      }
      final dataset = await staged._rows('SELECT generation FROM dataset');
      if (dataset.length != 1 ||
          dataset.single['generation'] != staged.generation) {
        throw const RestoreFailure(RestoreCodes.corrupt);
      }
      final people =
          (await staged._rows('SELECT count(*) c FROM person')).single['c']!
              as int;
      if (people < 1 ||
          (await staged._rows("SELECT id FROM person WHERE id='me'")).length !=
              1) {
        throw const RestoreFailure(RestoreCodes.corrupt);
      }
      if ((await staged._rows(
                "SELECT count(*) c FROM attachment_record r WHERE r.state='ready' AND NOT EXISTS(SELECT 1 FROM attachment_link l WHERE l.attachment=r.id AND l.person=r.person)",
              )).single['c'] !=
              0 ||
          (await staged._rows(
                'SELECT count(*) c FROM attachment_link l JOIN attachment_record r ON r.id=l.attachment WHERE l.person<>r.person',
              )).single['c'] !=
              0) {
        throw const RestoreFailure(RestoreCodes.corrupt);
      }
      final generation = newCommandId();
      final namespace = newCommandId();
      await staged._db.transaction(() async {
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
        await staged._db.customStatement('DELETE FROM reminder_pending');
        await staged._db.customStatement('DELETE FROM reminder_request');
        await staged._db.customStatement('DELETE FROM event_pending');
        await staged._db.customStatement('DELETE FROM event_end_request');
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
      await staged._db.customStatement('PRAGMA wal_checkpoint(TRUNCATE)');
      final counts = await staged._rows('''
        SELECT
          (SELECT count(*) FROM person) people,
          (SELECT count(*) FROM item) items,
          (SELECT count(*) FROM supporting_record WHERE voided=0) supporting,
          (SELECT count(*) FROM administration a JOIN revision r ON r.record=a.id AND r.person=a.person AND r.revision=a.revision WHERE r.voided=0) records,
          (SELECT count(*) FROM attachment_record WHERE state='ready') attachments
      ''');
      final row = counts.single;
      return RestorePreparedDatabase(
        path: stagedPath,
        previousGeneration: previousGeneration,
        generation: generation,
        previousNamespace: previousNamespace,
        reminderNamespace: namespace,
        schemaVersion: await staged._restoreSchemaVersion(),
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
