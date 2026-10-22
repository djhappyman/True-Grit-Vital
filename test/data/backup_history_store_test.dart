import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:true_grit_vital/data/record_store.dart';

BackupReceipt receipt(String generation, int id, {bool saved = false}) =>
    BackupReceipt(
      generation: generation,
      sha256: id.toRadixString(16).padLeft(64, '0'),
      byteCount: 12345,
      schemaVersion: currentRecordSchemaVersion,
      recordCount: 3,
      itemCount: 2,
      attachmentCount: 1,
      createdAt: DateTime.utc(2026, 10, 22, 8),
      verifiedAt: DateTime.utc(2026, 10, 22, 8, 1),
      savedAt: saved ? DateTime.utc(2026, 10, 22, 8, 2) : null,
    );

void main() {
  late Directory directory;
  late RecordStore store;
  final key = List.generate(32, (i) => i + 1);
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('vital-backup-history-');
    store = await RecordStore.open(
      path: '${directory.path}/records.db',
      key: key,
      isNew: true,
    );
  });
  tearDown(() async {
    await store.close();
    await directory.delete(recursive: true);
  });

  test('receipts persist encrypted, merge a save and remain bounded', () async {
    expect(await store.backupHistory(), isEmpty);
    final generation = store.generation;
    await store.recordBackupReceipt(receipt(generation, 1));
    expect((await store.backupHistory()).single.savedAt, isNull);
    await store.recordBackupReceipt(receipt(generation, 1, saved: true));
    await store.recordBackupReceipt(receipt(generation, 1));
    expect((await store.backupHistory()).single.savedAt, isNotNull);
    for (var i = 2; i <= 22; i++) {
      await store.recordBackupReceipt(receipt(generation, i));
    }
    await store.close();
    store = await RecordStore.open(
      path: '${directory.path}/records.db',
      key: key,
      isNew: false,
    );
    final rows = await store.backupHistory();
    expect(rows, hasLength(20));
    expect(rows.first.sha256, receipt(generation, 22).sha256);
    final value = await store.readSetting(BackupHistory.settingKey);
    expect(value, isNot(contains('password')));
    expect(value, isNot(contains('destination')));
    expect(value, isNot(contains(directory.path)));
    expect(BackupHistory.decode(value, 'fresh_restored_generation'), isEmpty);
  });

  test('independent connections merge instead of losing receipts', () async {
    final other = await RecordStore.open(
      path: store.databasePath,
      key: key,
      isNew: false,
    );
    try {
      await Future.wait([
        store.recordBackupReceipt(receipt(store.generation, 1)),
        other.recordBackupReceipt(receipt(store.generation, 2, saved: true)),
      ]);
      expect(await store.backupHistory(), hasLength(2));
    } finally {
      await other.close();
    }
  });

  test(
    'lock and wrong dataset reject receipts without claiming a save',
    () async {
      store.suspendWrites(true);
      await expectLater(
        store.recordBackupReceipt(receipt(store.generation, 1, saved: true)),
        throwsA(isA<CommandConflict>()),
      );
      store.suspendWrites(false);
      await expectLater(
        store.recordBackupReceipt(receipt('other_generation', 1)),
        throwsA(isA<CommandConflict>()),
      );
      expect(await store.backupHistory(), isEmpty);
    },
  );

  test('malformed or future history remains an explicit error', () async {
    await store.writeSetting(
      BackupHistory.settingKey,
      '{"version":2,"receipts":[]}',
    );
    await expectLater(store.backupHistory(), throwsFormatException);
    await expectLater(
      store.recordBackupReceipt(receipt(store.generation, 1)),
      throwsFormatException,
    );
    expect(
      await store.readSetting(BackupHistory.settingKey),
      contains('"version":2'),
    );
  });
}
