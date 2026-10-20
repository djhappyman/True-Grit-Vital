import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:true_grit_vital/data/record_store.dart';
import 'package:true_grit_vital/domain/restore/restore.dart';
import 'package:true_grit_vital/platform/linux_storage_bootstrap.dart';
import 'package:true_grit_vital/restore/restore_activation.dart';

final class _Secrets implements LinuxSecretStore {
  String? value;
  int writes = 0;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String input) async {
    writes++;
    value = input;
  }
}

void main() {
  group('restore startup on Linux storage', skip: !Platform.isLinux, () {
    late Directory directory;
    late _Secrets secrets;
    late LinuxStorageBootstrap bootstrap;

    setUp(() async {
      directory = await Directory.systemTemp.createTemp('vital-restore-boot-');
      secrets = _Secrets();
      bootstrap = LinuxStorageBootstrap(
        dataDirectory: directory.path,
        secretStore: secrets,
      );
    });

    tearDown(() async {
      await directory.delete(recursive: true);
    });

    test('keeps the live dataset and clears stale staging before open', () async {
      final location = await bootstrap.prepare();
      final store = await RecordStore.open(
        path: location.path,
        key: location.key,
        isNew: true,
      );
      final item = await store.createItem(
        commandId: 'synthetic-item',
        name: 'Synthetic restore source',
        form: 'Tablet',
        unit: 'mg',
        type: 'Supplement',
      );
      await store.record(
        commandId: 'synthetic-dose',
        itemId: item.id,
        amount: '0.125000',
        actualAt: DateTime.utc(2026, 10, 19, 12),
      );
      final generation = store.generation;
      await bootstrap.activate(location);
      await store.close();

      final restoreDirectory = Directory('${directory.path}/restore');
      await restoreDirectory.create();
      await File('${restoreDirectory.path}/${RestoreLimits.stagedFile}')
          .writeAsBytes(List<int>.filled(64, 1));
      await File('${restoreDirectory.path}/${RestoreLimits.intakeFile}')
          .writeAsBytes(List<int>.filled(8, 2));

      final recovery = await RestoreActivation(databasePath: location.path)
          .recoverInterrupted(key: location.key);
      expect(recovery.outcome, RestoreRecoveryOutcome.cleaned);
      expect(recovery.generation, generation);
      expect(await restoreDirectory.exists(), isFalse);

      // The next normal launch admits the private child directory and does not
      // mistake it for unknown evidence or a fresh installation.
      await restoreDirectory.create();
      await File('${restoreDirectory.path}/synthetic').writeAsString('x');
      final backupDirectory = Directory('${directory.path}/backup-staging');
      await backupDirectory.create();
      final reopened = await bootstrap.prepare();
      expect((await backupDirectory.stat()).mode & 0x1ff, 0x1c0);
      expect(reopened.isNew, isFalse);
      expect(secrets.writes, 1);
      expect((await restoreDirectory.stat()).mode & 0x1ff, 0x1c0);
      final storeAgain = await RecordStore.open(
        path: reopened.path,
        key: reopened.key,
        isNew: false,
      );
      try {
        expect(storeAgain.generation, generation);
        expect(await storeAgain.records(), hasLength(1));
      } finally {
        await storeAgain.close();
      }
    });
  });
}
