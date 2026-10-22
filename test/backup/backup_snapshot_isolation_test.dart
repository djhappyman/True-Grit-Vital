import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:true_grit_vital/backup/backup_service.dart';
import 'package:true_grit_vital/data/record_store.dart';
import 'package:true_grit_vital/domain/backup/backup.dart';

void main() {
  late Directory directory;
  late RecordStore live;
  late BackupSnapshotFile snapshot;
  final key = List.generate(32, (i) => i + 7);
  final newKey = List.generate(32, (i) => 255 - i);
  final warnings = <String>[];
  final originalPrint = driftRuntimeOptions.debugPrint;

  setUp(() async {
    expect(driftRuntimeOptions.dontWarnAboutMultipleDatabases, isFalse);
    warnings.clear();
    driftRuntimeOptions.debugPrint = warnings.add;
    directory = await Directory.systemTemp.createTemp(
      'vital-snapshot-isolation-',
    );
    live = await RecordStore.open(
      path: '${directory.path}/live.db',
      key: key,
      isNew: true,
    );
    final item = await live.createItem(
      commandId: 'item',
      name: 'Synthetic item',
      form: 'tablet',
      unit: 'count',
      type: 'medicine',
    );
    await live.record(
      commandId: 'record',
      itemId: item.id,
      amount: '2',
      actualAt: DateTime.utc(2026, 10, 22),
    );
    snapshot = await live.createBackupSnapshot(
      directory: directory,
      sessionId: 'isolated',
    );
  });

  tearDown(() async {
    await live.close();
    driftRuntimeOptions.debugPrint = originalPrint;
    await directory.delete(recursive: true);
  });

  test(
    'inspect and rekey use isolated executors without muting live warnings',
    () async {
      final generation = live.generation;
      final inventory = await inspectBackupSnapshot(
        path: snapshot.path,
        key: key,
      );
      expect(inventory.recordCount, 1);
      expect(inventory.generation, generation);
      await rekeyBackupSnapshot(
        path: snapshot.path,
        currentKey: key,
        newKey: newKey,
      );
      expect(
        (await inspectBackupSnapshot(
          path: snapshot.path,
          key: newKey,
        )).recordCount,
        1,
      );
      expect(
        warnings,
        isEmpty,
        reason:
            'snapshot connections must not register alongside the live store',
      );
      expect(driftRuntimeOptions.dontWarnAboutMultipleDatabases, isFalse);
      expect(await live.recordCount(), 1);
      expect(live.generation, generation);
      _expectSnapshotClosed(snapshot.path);

      // Drift must still diagnose a duplicate live connection. The snapshot
      // architecture cannot disable registration for ordinary stores.
      final duplicate = await RecordStore.open(
        path: live.databasePath,
        key: key,
        isNew: false,
      );
      await duplicate.close();
      expect(
        warnings.where((line) => line.contains('multiple times')),
        hasLength(1),
      );
    },
  );

  test(
    'wrong keys, thrown observers and cancellation close snapshot handles',
    () async {
      final generation = live.generation;
      await expectLater(
        inspectBackupSnapshot(path: snapshot.path, key: newKey),
        throwsA(anything),
      );
      _expectSnapshotClosed(snapshot.path);
      await expectLater(
        rekeyBackupSnapshot(
          path: snapshot.path,
          currentKey: newKey,
          newKey: key,
        ),
        throwsA(anything),
      );
      _expectSnapshotClosed(snapshot.path);
      final failure = StateError('synthetic validation observer failure');
      await expectLater(
        inspectBackupSnapshot(
          path: snapshot.path,
          key: key,
          onValidatedBatch: (_) => throw failure,
        ),
        throwsA(same(failure)),
      );
      _expectSnapshotClosed(snapshot.path);
      final token = BackupCancellationToken();
      await expectLater(
        inspectBackupSnapshot(
          path: snapshot.path,
          key: key,
          token: token,
          onValidatedBatch: (_) => token.cancel(),
        ),
        throwsA(
          isA<BackupFailure>().having(
            (e) => e.code,
            'code',
            'backup_cancelled',
          ),
        ),
      );
      _expectSnapshotClosed(snapshot.path);
      expect(
        (await inspectBackupSnapshot(
          path: snapshot.path,
          key: key,
        )).recordCount,
        1,
      );
      expect(await live.recordCount(), 1);
      expect(live.generation, generation);
      expect(warnings, isEmpty);
    },
  );

  test(
    'live writes during inspection leave the captured inventory unchanged',
    () async {
      final item = (await live.items()).single;
      final generation = live.generation;
      final writing = Completer<void>();
      final token = BackupCancellationToken();
      await expectLater(
        inspectBackupSnapshot(
          path: snapshot.path,
          key: key,
          token: token,
          onValidatedBatch: (_) {
            if (Platform.isLinux) {
              final open = _openFiles();
              expect(open, contains(live.databasePath));
              expect(open, contains(snapshot.path));
              expect(snapshot.path, isNot(live.databasePath));
            }
            writing.complete(
              live
                  .record(
                    commandId: 'concurrent',
                    itemId: item.id,
                    amount: '3',
                    actualAt: DateTime.utc(2026, 10, 23),
                  )
                  .then<void>((_) {}),
            );
            token.cancel();
          },
        ),
        throwsA(isA<BackupFailure>()),
      );
      await writing.future;
      expect(await live.recordCount(), 2);
      expect(
        (await inspectBackupSnapshot(
          path: snapshot.path,
          key: key,
        )).recordCount,
        1,
      );
      expect(live.generation, generation);
      expect(warnings, isEmpty);
      _expectSnapshotClosed(snapshot.path);
    },
  );

  test('invalid quantity validation closes its executor and preserves the live dataset', () async {
    final raw = sqlite.sqlite3.open(snapshot.path);
    try {
      final hex = key.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      raw.execute("PRAGMA cipher = 'chacha20'");
      raw.execute('PRAGMA key = "x\'$hex\'"');
      raw.execute("UPDATE revision SET entered='999'");
    } finally {
      raw.close();
    }
    await expectLater(
      inspectBackupSnapshot(path: snapshot.path, key: key),
      throwsA(
        isA<BackupFailure>().having(
          (e) => e.code,
          'code',
          'backup_invalid_dataset',
        ),
      ),
    );
    _expectSnapshotClosed(snapshot.path);
    expect(await live.recordCount(), 1);
    final valid = await live.createBackupSnapshot(
      directory: directory,
      sessionId: 'valid',
    );
    expect((await live.inspectOwnSnapshot(valid)).recordCount, 1);
    expect(warnings, isEmpty);
  });

  test(
    'concurrent rekey and live writes use different encrypted files',
    () async {
      final item = (await live.items()).single;
      final generation = live.generation;
      final rekey = rekeyBackupSnapshot(
        path: snapshot.path,
        currentKey: key,
        newKey: newKey,
      );
      final writing = live.record(
        commandId: 'during-rekey',
        itemId: item.id,
        amount: '3',
        actualAt: DateTime.utc(2026, 10, 23),
      );
      await Future.wait<Object?>([rekey, writing]);
      expect(await live.recordCount(), 2);
      final inventories = await Future.wait([
        inspectBackupSnapshot(path: snapshot.path, key: newKey),
        inspectBackupSnapshot(path: snapshot.path, key: newKey),
      ]);
      expect(inventories.map((v) => v.recordCount), everyElement(1));
      expect(inventories.map((v) => v.generation), everyElement(generation));
      _expectSnapshotClosed(snapshot.path);
      await expectLater(
        inspectBackupSnapshot(path: snapshot.path, key: key),
        throwsA(anything),
      );
      _expectSnapshotClosed(snapshot.path);
      expect(live.generation, generation);
      expect(warnings, isEmpty);
    },
  );

  test('cancelled creation preserves prior valid output and concurrent live writes', () async {
    final service = BackupService(
      recordStore: live,
      stagingDirectory: Directory('${directory.path}/staging'),
    );
    const password = 'Synthetic snapshot isolation password';
    final previous = await service.createBackup(
      password: password,
      token: BackupCancellationToken(),
    );
    final bytesBefore = await previous.archive.readAsBytes();
    final generation = live.generation;
    final item = (await live.items()).single;
    final writing = Completer<void>();
    final token = BackupCancellationToken();
    var startedWrite = false;
    await expectLater(
      service.createBackup(
        password: password,
        token: token,
        onProgress: (progress) {
          if (progress.stage == BackupStage.inspect && !startedWrite) {
            startedWrite = true;
            writing.complete(
              live
                  .record(
                    commandId: 'during-create',
                    itemId: item.id,
                    amount: '4',
                    actualAt: DateTime.utc(2026, 10, 24),
                  )
                  .then<void>((_) {}),
            );
          }
          if (progress.stage == BackupStage.encrypt &&
              progress.completedBytes > 0) {
            token.cancel();
          }
        },
      ),
      throwsA(
        isA<BackupFailure>().having((e) => e.code, 'code', 'backup_cancelled'),
      ),
    );
    expect(startedWrite, isTrue);
    await writing.future;
    expect(await live.recordCount(), 2);
    expect(live.generation, generation);
    expect(await previous.archive.readAsBytes(), orderedEquals(bytesBefore));
    final restored = await service.validateArchive(
      archive: previous.archive,
      password: password,
      token: BackupCancellationToken(),
    );
    expect(restored.inventory.recordCount, 1);
    _expectSnapshotClosed(restored.databasePath);
    await restored.discard();
    expect(service.stagingDirectory.listSync().map((e) => e.path), [
      previous.archive.path,
    ]);
    expect(warnings, isEmpty);
    await service.discard(previous);
  });
}

void _expectSnapshotClosed(String path) {
  if (!Platform.isLinux) return;
  expect(
    _openFiles().where((target) => target.startsWith(path)),
    isEmpty,
    reason: 'the snapshot database and sidecars must have no open descriptors',
  );
}

List<String> _openFiles() {
  final targets = <String>[];
  for (final entry in Directory('/proc/self/fd').listSync()) {
    try {
      targets.add(Link(entry.path).targetSync());
    } on FileSystemException {
      // A descriptor from listing /proc can close before readlink.
    }
  }
  return targets;
}
