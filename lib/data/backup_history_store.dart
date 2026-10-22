part of 'record_store.dart';

extension BackupHistoryStore on RecordStore {
  Stream<List<BackupReceipt>> watchBackupHistory() => _watch(
    () async => BackupHistory.decode(
      await readSetting(BackupHistory.settingKey),
      generation,
    ),
  );

  Future<List<BackupReceipt>> backupHistory() async => BackupHistory.decode(
    await readSetting(BackupHistory.settingKey),
    generation,
  );

  /// Acquires the write lock before merging, including across connections.
  /// A restored dataset receives a fresh generation and cannot inherit saves.
  Future<void> recordBackupReceipt(BackupReceipt receipt) async {
    _requireWritable();
    if (receipt.generation != generation) {
      throw const CommandConflict('generation');
    }
    await _db.transaction(() async {
      await _db.customStatement('UPDATE dataset SET generation=generation');
      await _backupAssertGeneration(generation);
      _requireWritable();
      final rows = await backupHistory();
      final old = rows.where((row) => row.sha256 == receipt.sha256).firstOrNull;
      final merged = receipt.savedAt == null && old?.savedAt != null
          ? old!
          : receipt;
      // Validate locally produced data by the same bounded reader as storage.
      final value = BackupHistory.encode([
        merged,
        ...rows.where((row) => row.sha256 != receipt.sha256),
      ]);
      BackupHistory.decode(value, generation);
      await _db.customStatement(
        'INSERT INTO setting VALUES (?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value',
        [BackupHistory.settingKey, value],
      );
      _requireWritable();
    });
    _changes.add(null);
  }
}
