import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:true_grit_vital/domain/artifact_transfer.dart';
import 'package:true_grit_vital/platform/artifact_transfer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() {
    messenger.setMockMethodCallHandler(AndroidArtifactTransfer.channel, null);
  });

  group('Android artifact gateway', () {
    test('stages, publishes and hands off exact neutral metadata', () async {
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(AndroidArtifactTransfer.channel, (
        call,
      ) async {
        calls.add(call);
        return switch (call.method) {
          'append' => ((call.arguments as Map)['offset'] as int) + 3,
          'save' || 'share' || 'cancel' => true,
          'cleanup' => <String>['stale'],
          _ => null,
        };
      });
      const gateway = AndroidArtifactTransfer();
      final bytes = Uint8List.fromList([1, 2, 3]);
      final hash = sha256.convert(bytes).toString();
      final expires = DateTime.utc(2026, 10, 21, 12);
      await gateway.begin(
        id: 'artifact_1',
        name: 'vital-export.csv',
        mimeType: 'text/csv',
        byteCount: 3,
        expiresAt: expires,
      );
      expect(
        await gateway.append(id: 'artifact_1', offset: 0, bytes: bytes),
        3,
      );
      await gateway.publish(id: 'artifact_1', byteCount: 3, sha256: hash);
      expect(
        await gateway.save(
          id: 'artifact_1',
          name: 'vital-export.csv',
          mimeType: 'text/csv',
        ),
        isTrue,
      );
      expect(
        await gateway.share(
          id: 'artifact_1',
          name: 'vital-export.csv',
          mimeType: 'text/csv',
        ),
        isTrue,
      );
      expect(await gateway.cancel('artifact_1'), isTrue);
      expect(await gateway.cleanup(preserve: 'artifact_1'), ['stale']);
      expect(await gateway.cleanup(includeOffered: true), ['stale']);
      expect(calls.last.arguments, {'preserve': null, 'includeOffered': true});

      expect(calls.map((call) => call.method), [
        'begin',
        'append',
        'publish',
        'save',
        'share',
        'cancel',
        'cleanup',
        'cleanup',
      ]);
      expect(calls.first.arguments, {
        'id': 'artifact_1',
        'name': 'vital-export.csv',
        'mime': 'text/csv',
        'bytes': 3,
        'expiresAt': expires.millisecondsSinceEpoch,
      });
      expect(calls[6].arguments, {
        'preserve': 'artifact_1',
        'includeOffered': false,
      });
    });

    test('bounds chunks and offsets before the channel is called', () async {
      var called = false;
      messenger.setMockMethodCallHandler(AndroidArtifactTransfer.channel, (
        _,
      ) async {
        called = true;
        return null;
      });
      const gateway = AndroidArtifactTransfer();
      await expectLater(
        gateway.append(
          id: 'artifact_1',
          offset: 0,
          bytes: Uint8List(ArtifactLimits.chunkBytes + 1),
        ),
        throwsA(_failure('artifact_transfer_input')),
      );
      await expectLater(
        gateway.append(id: 'artifact_1', offset: -1, bytes: Uint8List(1)),
        throwsA(_failure('artifact_transfer_input')),
      );
      await expectLater(
        gateway.begin(
          id: 'artifact_1',
          name: '../alice.pdf',
          mimeType: 'application/pdf',
          byteCount: 3,
          expiresAt: DateTime.utc(2026, 10, 21),
        ),
        throwsA(_failure('artifact_transfer_input')),
      );
      expect(called, isFalse);
    });

    test(
      'maps native failures and treats a missing artifact as cancelled',
      () async {
        var missing = true;
        messenger.setMockMethodCallHandler(AndroidArtifactTransfer.channel, (
          call,
        ) async {
          if (call.method == 'cancel' && missing) {
            throw PlatformException(code: 'artifact_transfer_missing');
          }
          throw PlatformException(code: 'artifact_transfer_integrity');
        });
        const gateway = AndroidArtifactTransfer();
        expect(await gateway.cancel('artifact_1'), isTrue);
        missing = false;
        await expectLater(
          gateway.cancel('artifact_1'),
          throwsA(_failure('artifact_transfer_integrity')),
        );
        await expectLater(
          gateway.publish(id: 'artifact_1', byteCount: 3, sha256: '0' * 64),
          throwsA(_failure('artifact_transfer_integrity')),
        );
      },
    );

    test(
      'reports an unavailable native bridge without a false success',
      () async {
        const gateway = AndroidArtifactTransfer();
        await expectLater(
          gateway.cleanup(),
          throwsA(_failure('artifact_transfer_unavailable')),
        );
        await expectLater(
          gateway.cancel('artifact_1'),
          throwsA(_failure('artifact_transfer_unavailable')),
        );
      },
    );

    test(
      'unsupported host advertises no capability and never succeeds',
      () async {
        const gateway = UnsupportedArtifactTransfer();
        expect(gateway.capabilities.save, isFalse);
        expect(gateway.capabilities.share, isFalse);
        expect(await gateway.cleanup(), isEmpty);
        await expectLater(
          gateway.save(
            id: 'artifact_1',
            name: 'vital-summary.pdf',
            mimeType: 'application/pdf',
          ),
          throwsA(_failure('artifact_transfer_unavailable')),
        );
      },
    );
  });

  group('file artifact gateway', () {
    late Directory root;
    late DateTime now;
    setUp(() async {
      root = await Directory.systemTemp.createTemp('vital-artifacts-');
      now = DateTime.utc(2026, 10, 20, 12);
    });
    tearDown(() => root.delete(recursive: true));

    ArtifactFileStore newStore() =>
        ArtifactFileStore(rootOverride: root, clock: () => now);

    test('stages, verifies and releases an exact copy', () async {
      final store = newStore();
      final bytes = Uint8List.fromList(
        List.generate(1024 * 70 + 7, (i) => i % 251),
      );
      final hash = sha256.convert(bytes).toString();
      final expires = now.add(const Duration(hours: 1));
      await store.begin(
        id: 'artifact_one',
        name: 'vital-summary.pdf',
        mimeType: 'application/pdf',
        byteCount: bytes.length,
        expiresAt: expires,
      );
      var offset = 0;
      for (final chunk in _chunks(bytes)) {
        offset = await store.append(
          id: 'artifact_one',
          offset: offset,
          bytes: chunk,
        );
      }
      expect(offset, bytes.length);
      await store.publish(
        id: 'artifact_one',
        byteCount: bytes.length,
        sha256: hash,
      );
      final readable = await store.readable('artifact_one');
      expect(await readable.readAsBytes(), bytes);
      expect(await store.cancel('artifact_one'), isTrue);
      expect(await store.cancel('artifact_one'), isTrue);
      await expectLater(
        store.readable('artifact_one'),
        throwsA(_failure('artifact_transfer_missing')),
      );
    });

    test('retries an identical append and rejects conflicting bytes', () async {
      final store = newStore();
      final bytes = Uint8List.fromList([1, 2, 3, 4]);
      await store.begin(
        id: 'artifact_one',
        name: 'vital-export.json',
        mimeType: 'application/json',
        byteCount: 4,
        expiresAt: now.add(const Duration(hours: 1)),
      );
      expect(
        await store.append(id: 'artifact_one', offset: 0, bytes: bytes),
        4,
      );
      expect(
        await store.append(id: 'artifact_one', offset: 0, bytes: bytes),
        4,
      );
      await expectLater(
        store.append(
          id: 'artifact_one',
          offset: 0,
          bytes: Uint8List.fromList([9, 9, 9, 9]),
        ),
        throwsA(_failure('artifact_transfer_conflict')),
      );
      await expectLater(
        store.append(
          id: 'artifact_one',
          offset: 1,
          bytes: Uint8List.fromList([9]),
        ),
        throwsA(_failure('artifact_transfer_conflict')),
      );
      await expectLater(
        store.append(
          id: 'artifact_one',
          offset: 4,
          bytes: Uint8List.fromList([5]),
        ),
        throwsA(_failure('artifact_transfer_input')),
      );
    });

    test('a digest mismatch never becomes readable', () async {
      final store = newStore();
      final bytes = Uint8List.fromList([7, 8, 9]);
      await store.begin(
        id: 'artifact_one',
        name: 'vital-export.csv',
        mimeType: 'text/csv',
        byteCount: 3,
        expiresAt: now.add(const Duration(hours: 1)),
      );
      await store.append(id: 'artifact_one', offset: 0, bytes: bytes);
      await expectLater(
        store.publish(id: 'artifact_one', byteCount: 3, sha256: '0' * 64),
        throwsA(_failure('artifact_transfer_integrity')),
      );
      await expectLater(
        store.readable('artifact_one'),
        throwsA(_failure('artifact_transfer_incomplete')),
      );
      expect(await store.cleanup(), ['artifact_one']);
    });

    test('startup cleanup reclaims interrupted and abandoned copies', () async {
      final expires = now.add(const Duration(hours: 1));
      final interrupted = newStore();
      await interrupted.begin(
        id: 'interrupted',
        name: 'vital-artifact.bin',
        mimeType: 'application/octet-stream',
        byteCount: 3,
        expiresAt: expires,
      );
      await interrupted.append(
        id: 'interrupted',
        offset: 0,
        bytes: Uint8List.fromList([1, 2]),
      );
      expect(await interrupted.cleanup(), ['interrupted']);

      final published = newStore();
      await published.begin(
        id: 'published',
        name: 'vital-artifact.bin',
        mimeType: 'application/octet-stream',
        byteCount: 3,
        expiresAt: expires,
      );
      await published.append(
        id: 'published',
        offset: 0,
        bytes: Uint8List.fromList([1, 2, 3]),
      );
      await published.publish(
        id: 'published',
        byteCount: 3,
        sha256: sha256.convert([1, 2, 3]).toString(),
      );
      final unrelated = File('${root.path}/keep-me.txt');
      await unrelated.writeAsString('preserve');
      expect(await published.cleanup(preserve: 'published'), isEmpty);
      expect(await published.readable('published'), isA<File>());
      expect(await published.cleanup(), ['published']);
      expect(await unrelated.readAsString(), 'preserve');
    });

    test('expiry and hostile input stay bounded', () async {
      final store = newStore();
      final expires = now.add(const Duration(hours: 1));
      Future<void> begin(String id) => store.begin(
        id: id,
        name: 'vital-backup.vitalbak',
        mimeType: 'application/octet-stream',
        byteCount: 3,
        expiresAt: expires,
      );

      await begin('one');
      now = now.add(const Duration(hours: 2));
      expect(await store.cleanup(), ['one']);
      await expectLater(
        store.begin(
          id: '../alice',
          name: 'vital-backup.vitalbak',
          mimeType: 'application/octet-stream',
          byteCount: 3,
          expiresAt: now.add(const Duration(hours: 1)),
        ),
        throwsA(_failure('artifact_transfer_identity')),
      );
      await expectLater(
        store.begin(
          id: 'alice',
          name: 'Alice backup.vitalbak',
          mimeType: 'application/octet-stream',
          byteCount: 3,
          expiresAt: now.add(const Duration(hours: 1)),
        ),
        throwsA(_failure('artifact_transfer_input')),
      );
      await expectLater(
        store.begin(
          id: 'large',
          name: 'vital-backup.vitalbak',
          mimeType: 'application/octet-stream',
          byteCount: ArtifactLimits.maxBytes + 1,
          expiresAt: now.add(const Duration(hours: 1)),
        ),
        throwsA(_failure('artifact_transfer_input')),
      );
    });

    test('save uses the exact staged bytes and an explicit bound', () async {
      final saves = <({String name, String mimeType, Uint8List bytes})>[];
      final gateway = FileArtifactTransfer(
        root: root,
        clock: () => now,
        maxSaveBytes: 4,
        saveDialog: ({required name, required mimeType, required bytes}) async {
          saves.add((
            name: name,
            mimeType: mimeType,
            bytes: Uint8List.fromList(bytes),
          ));
          return true;
        },
      );
      final bytes = Uint8List.fromList([1, 2, 3]);
      await _stage(gateway, bytes, now);
      await expectLater(
        gateway.save(
          id: 'artifact_one',
          name: 'alice-summary.pdf',
          mimeType: 'application/pdf',
        ),
        throwsA(_failure('artifact_transfer_conflict')),
      );
      expect(
        await gateway.save(
          id: 'artifact_one',
          name: 'vital-export.csv',
          mimeType: 'text/csv',
        ),
        isTrue,
      );
      expect(saves.single.name, 'vital-export.csv');
      expect(saves.single.mimeType, 'text/csv');
      expect(saves.single.bytes, bytes);
      final limited = FileArtifactTransfer(
        root: root,
        clock: () => now,
        maxSaveBytes: 2,
        saveDialog: ({
          required name,
          required mimeType,
          required bytes,
        }) async => true,
      );
      await expectLater(
        limited.save(
          id: 'artifact_one',
          name: 'vital-export.csv',
          mimeType: 'text/csv',
        ),
        throwsA(_failure('artifact_transfer_save_limit')),
      );
      await expectLater(
        gateway.share(
          id: 'artifact_one',
          name: 'vital-export.csv',
          mimeType: 'text/csv',
        ),
        throwsA(_failure('artifact_transfer_share_unavailable')),
      );
      expect(gateway.capabilities.save, isTrue);
      expect(gateway.capabilities.share, isFalse);
      expect(await gateway.cancel('artifact_one'), isTrue);
    });

    test('a cancelled save reports no success and leaves no reader', () async {
      final gateway = FileArtifactTransfer(
        root: root,
        clock: () => now,
        saveDialog: ({
          required name,
          required mimeType,
          required bytes,
        }) async => false,
      );
      await _stage(gateway, Uint8List.fromList([4, 5, 6]), now);
      expect(
        await gateway.save(
          id: 'artifact_one',
          name: 'vital-export.csv',
          mimeType: 'text/csv',
        ),
        isFalse,
      );
      expect(await gateway.cancel('artifact_one'), isTrue);
    });
  });
}

Iterable<Uint8List> _chunks(Uint8List bytes) sync* {
  var offset = 0;
  while (offset < bytes.length) {
    final end = offset + ArtifactLimits.chunkBytes < bytes.length
        ? offset + ArtifactLimits.chunkBytes
        : bytes.length;
    yield Uint8List.sublistView(bytes, offset, end);
    offset = end;
  }
}

Future<void> _stage(
  ArtifactTransferGateway gateway,
  Uint8List bytes,
  DateTime now,
) async {
  await gateway.begin(
    id: 'artifact_one',
    name: 'vital-export.csv',
    mimeType: 'text/csv',
    byteCount: bytes.length,
    expiresAt: now.add(const Duration(hours: 1)),
  );
  var offset = 0;
  for (final chunk in _chunks(bytes)) {
    offset = await gateway.append(
      id: 'artifact_one',
      offset: offset,
      bytes: chunk,
    );
  }
  await gateway.publish(
    id: 'artifact_one',
    byteCount: bytes.length,
    sha256: sha256.convert(bytes).toString(),
  );
}

Matcher _failure(String code) =>
    isA<ArtifactFailure>().having((error) => error.code, 'code', code);
