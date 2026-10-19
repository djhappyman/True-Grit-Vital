import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:true_grit_vital/data/record_store.dart';
import 'package:true_grit_vital/platform/linux_storage_bootstrap.dart';
import 'package:true_grit_vital/platform/storage_bootstrap.dart';

final class _Secrets implements LinuxSecretStore {
  String? value;
  bool locked = false;
  bool refuseWrite = false;
  int writes = 0;

  @override
  Future<String?> read() async {
    if (locked) {
      throw const StorageBootstrapException('linux_keyring_unavailable');
    }
    return value;
  }

  @override
  Future<void> write(String input) async {
    writes++;
    if (refuseWrite) {
      throw const StorageBootstrapException('linux_keyring_unavailable');
    }
    value = input;
  }
}

Matcher failsWith(String code) => throwsA(
  isA<StorageBootstrapException>().having((e) => e.code, 'code', code),
);

void main() {
  group('Linux storage protocol', skip: !Platform.isLinux, () {
    late Directory directory;
    late _Secrets secrets;
    late LinuxStorageBootstrap bootstrap;
    final stores = <RecordStore>[];

    Future<RecordStore> open(StorageLocation location) async {
      final store = await RecordStore.open(
        path: location.path,
        key: location.key,
        isNew: location.isNew,
      );
      stores.add(store);
      return store;
    }

    Future<StorageLocation> initialise({bool activate = true}) async {
      final location = await bootstrap.prepare();
      final store = await open(location);
      final item = await store.createItem(
        commandId: 'synthetic-item',
        name: 'Synthetic Linux protected record',
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
      if (activate) await bootstrap.activate(location);
      await store.close();
      return location;
    }

    Future<Map<String, String>> snapshot() async => {
      await for (final file in directory.list())
        if (file is File)
          file.path.split('/').last: base64Encode(await file.readAsBytes()),
    };

    setUp(() async {
      directory = await Directory.systemTemp.createTemp('vital-linux-test-');
      secrets = _Secrets();
      bootstrap = LinuxStorageBootstrap(
        dataDirectory: directory.path,
        secretStore: secrets,
      );
    });
    tearDown(() async {
      for (final store in stores) {
        await store.close();
      }
      stores.clear();
      await directory.delete(recursive: true);
    });

    test(
      'fresh encrypted dataset reopens with exact ownership and history',
      () async {
        final original = await initialise();
        expect(original.isNew, isTrue);
        expect(original.key.toSet().length, greaterThan(1));
        expect(secrets.writes, 1);
        final bytes = await File(original.path).readAsBytes();
        expect(
          utf8.decode(bytes, allowMalformed: true),
          isNot(contains('Synthetic Linux protected record')),
        );
        expect(bytes.take(16), isNot(utf8.encode('SQLite format 3\u0000')));
        final restarted = LinuxStorageBootstrap(
          dataDirectory: directory.path,
          secretStore: secrets,
        );
        final location = await restarted.prepare();
        expect(location.isNew, isFalse);
        expect(location.key, original.key);
        final store = await open(location);
        await restarted.activate(location);
        final row = (await store.records()).single;
        expect(row.personId, meId);
        expect(row.enteredAmount, '0.125000');
        final corrected = await store.correct(
          commandId: 'synthetic-correct',
          recordId: row.id,
          expectedRevision: 1,
          amount: '0.5',
          actualAt: row.actualAt,
        );
        await store.voidRecord(
          commandId: 'synthetic-undo',
          recordId: row.id,
          expectedRevision: corrected.revision,
        );
        expect((await store.history(row.id)).map((r) => r.enteredAmount), [
          '0.125000',
          '0.5',
          '0.5',
        ]);
        expect((await store.records()).single.isVoided, isTrue);
        expect(secrets.writes, 1);
        expect((await directory.stat()).mode & 0x1ff, 0x1c0);
        for (final name in ['initializing', 'active', 'records.sqlite']) {
          expect(
            (await File('${directory.path}/$name').stat()).mode & 0x1ff,
            0x180,
          );
        }
      },
    );

    test(
      'missing existing credential preserves every file without replacement',
      () async {
        await initialise();
        final before = await snapshot();
        secrets.value = null;
        await expectLater(
          bootstrap.prepare(),
          failsWith('storage_recovery_required'),
        );
        expect(await snapshot(), before);
        expect(secrets.writes, 1);
      },
    );

    test(
      'unavailable keyring cannot turn existing records into a fresh dataset',
      () async {
        await initialise();
        final before = await snapshot();
        secrets.locked = true;
        await expectLater(
          bootstrap.prepare(),
          failsWith('linux_keyring_unavailable'),
        );
        expect(await snapshot(), before);
        expect(secrets.writes, 1);
      },
    );

    test(
      'unavailable fresh keyring writes neither intent nor database',
      () async {
        secrets.locked = true;
        await expectLater(
          bootstrap.prepare(),
          failsWith('linux_keyring_unavailable'),
        );
        expect((await snapshot()).keys, ['.bootstrap.lock']);
        expect(secrets.writes, 0);
      },
    );

    test('failed secret publication leaves recovery evidence', () async {
      secrets.refuseWrite = true;
      await expectLater(
        bootstrap.prepare(),
        failsWith('linux_keyring_unavailable'),
      );
      expect(await File('${directory.path}/initializing').exists(), isTrue);
      expect(await File('${directory.path}/records.sqlite').exists(), isFalse);
      secrets.refuseWrite = false;
      await expectLater(
        bootstrap.prepare(),
        failsWith('storage_recovery_required'),
      );
      expect(secrets.writes, 1);
    });

    test(
      'orphan key and interrupted pre-database setup both require recovery',
      () async {
        final location = await bootstrap.prepare();
        expect(location.isNew, isTrue);
        await expectLater(
          bootstrap.prepare(),
          failsWith('storage_recovery_required'),
        );
        await File('${directory.path}/initializing').delete();
        await expectLater(
          bootstrap.prepare(),
          failsWith('storage_recovery_required'),
        );
        expect(secrets.writes, 1);
        expect(await File(location.path).exists(), isFalse);
      },
    );

    test(
      'validated dataset without active marker can complete activation',
      () async {
        final original = await initialise(activate: false);
        expect(await File('${directory.path}/active').exists(), isFalse);
        final location = await bootstrap.prepare();
        expect(location.isNew, isFalse);
        expect(location.key, original.key);
        await open(location);
        await bootstrap.activate(location);
        expect(
          await File('${directory.path}/active').readAsString(),
          await File('${directory.path}/initializing').readAsString(),
        );
      },
    );

    for (final damage in [
      'pending',
      'active identity',
      'secret identity',
      'truncated database',
      'missing database',
    ]) {
      test('$damage is refused without replacing remaining evidence', () async {
        final location = await initialise();
        switch (damage) {
          case 'pending':
            await File('${directory.path}/active.pending')
                .writeAsString('interrupted');
          case 'active identity':
            await File('${directory.path}/active').writeAsString('0' * 32);
          case 'secret identity':
            final decoded = jsonDecode(secrets.value!) as Map<String, dynamic>;
            decoded['dataset'] = '0' * 32;
            secrets.value = jsonEncode(decoded);
          case 'truncated database':
            await File(location.path).writeAsBytes([1, 2, 3]);
          case 'missing database':
            await File(location.path).delete();
        }
        final before = await snapshot();
        await expectLater(
          bootstrap.prepare(),
          failsWith('storage_recovery_required'),
        );
        expect(await snapshot(), before);
        expect(secrets.writes, 1);
      });
    }

    test(
      'activation rejects credentials not prepared for the dataset',
      () async {
        final location = await initialise(activate: false);
        await expectLater(
          bootstrap.activate(
            StorageLocation(
              path: location.path,
              key: List.filled(32, 0),
              isNew: true,
            ),
          ),
          failsWith('storage_recovery_required'),
        );
        expect(await File('${directory.path}/active').exists(), isFalse);
      },
    );

    test(
      'symbolic dataset path is refused without writing its target',
      () async {
        final link = Link('${directory.path}/linked');
        await link.create(directory.path);
        final unsafe = LinuxStorageBootstrap(
          dataDirectory: link.path,
          secretStore: secrets,
        );
        await expectLater(
          unsafe.prepare(),
          failsWith('storage_recovery_required'),
        );
        expect(secrets.writes, 0);
        expect(await File('${directory.path}/initializing').exists(), isFalse);
      },
    );

    test('competing fresh callers publish only one credential', () async {
      final other = LinuxStorageBootstrap(
        dataDirectory: directory.path,
        secretStore: secrets,
      );
      Future<Object> attempt(LinuxStorageBootstrap instance) async {
        try {
          return await instance.prepare();
        } on StorageBootstrapException catch (error) {
          return error.code;
        }
      }

      final results = await Future.wait([attempt(bootstrap), attempt(other)]);
      expect(results.whereType<StorageLocation>().length, 1);
      expect(results, contains('storage_recovery_required'));
      expect(secrets.writes, 1);
    });

    test('real Secret Service synthetic namespace saves and reopens', () async {
      final namespace =
          'dev.truegrit.vital.test.$pid.${DateTime.now().microsecondsSinceEpoch}';
      final service = SecretToolStore(namespace: namespace);
      addTearDown(() async {
        final result = await Process.run('/usr/bin/secret-tool', [
          'clear',
          'application',
          namespace,
          'dataset',
          'main',
        ]);
        expect(result.exitCode, 0, reason: 'Remove only this test namespace');
      });
      expect(await service.read(), isNull);
      final real = LinuxStorageBootstrap(
        dataDirectory: directory.path,
        secretStore: service,
      );
      final location = await real.prepare();
      final store = await open(location);
      final item = await store.createItem(
        commandId: 'real-keyring-item',
        name: 'Synthetic keyring fixture',
        form: 'Tablet',
        unit: 'count',
        type: 'Supplement',
      );
      await store.record(
        commandId: 'real-keyring-dose',
        itemId: item.id,
        amount: '1',
        actualAt: DateTime.utc(2026, 10, 19),
      );
      await real.activate(location);
      await store.close();
      final second = LinuxStorageBootstrap(
        dataDirectory: directory.path,
        secretStore: service,
      );
      final restored = await second.prepare();
      expect(restored.isNew, isFalse);
      expect(restored.key, location.key);
      final reopened = await open(restored);
      expect(
        (await reopened.records()).single.name,
        'Synthetic keyring fixture',
      );
    }, skip: Platform.environment['VITAL_TEST_SECRET_SERVICE'] != '1');
  });
}
