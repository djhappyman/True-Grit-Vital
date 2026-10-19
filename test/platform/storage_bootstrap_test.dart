import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:true_grit_vital/platform/storage_bootstrap.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dev.truegrit.vital/storage');
  const bootstrap = AndroidStorageBootstrap();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('unsupported desktop fails without requesting credentials', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    var requested = false;
    messenger.setMockMethodCallHandler(channel, (_) async {
      requested = true;
      return null;
    });
    await expectLater(
      bootstrap.prepare(),
      throwsA(
        isA<StorageBootstrapException>().having(
          (error) => error.code,
          'code',
          'unsupported_host',
        ),
      ),
    );
    expect(requested, isFalse);
  });

  test('native credentials preserve exact bytes and creation state', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final bytes = Uint8List.fromList(List.generate(32, (index) => index));
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'prepare');
      return {'path': '/private/records.sqlite', 'key': bytes, 'isNew': true};
    });
    final location = await bootstrap.prepare();
    expect(location.path, '/private/records.sqlite');
    expect(location.key, bytes);
    expect(location.isNew, isTrue);
    expect(() => location.key[0] = 100, throwsUnsupportedError);
  });

  test('malformed native secret is refused', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    messenger.setMockMethodCallHandler(
      channel,
      (_) async => {
        'path': '/private/records.sqlite',
        'key': Uint8List(31),
        'isNew': true,
      },
    );
    await expectLater(
      bootstrap.prepare(),
      throwsA(
        isA<StorageBootstrapException>().having(
          (error) => error.code,
          'code',
          'invalid_native_response',
        ),
      ),
    );
  });

  test('recovery errors contain only the technical code', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    messenger.setMockMethodCallHandler(channel, (_) async {
      throw PlatformException(
        code: 'storage_recovery_required',
        message: 'synthetic-secret-do-not-display',
      );
    });
    try {
      await bootstrap.prepare();
      fail('Expected recovery error');
    } on StorageBootstrapException catch (error) {
      expect(error.code, 'storage_recovery_required');
      expect(error.toString(), isNot(contains('synthetic-secret')));
    }
  });

  test('missing implementation fails without fallback', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await expectLater(
      bootstrap.prepare(),
      throwsA(
        isA<StorageBootstrapException>().having(
          (error) => error.code,
          'code',
          'unsupported_host',
        ),
      ),
    );
  });

  test('activation sends path without returning the key to native', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final location = StorageLocation(
      path: '/private/records.sqlite',
      key: List.filled(32, 19),
      isNew: false,
    );
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'activate');
      expect(call.arguments, {'path': location.path});
      return null;
    });
    await bootstrap.activate(location);
  });

  test('explicit fixture credentials are validated and copied', () {
    final fixture = List.filled(32, 9);
    final location = StorageLocation(
      path: 'fixture',
      key: fixture,
      isNew: true,
    );
    fixture[0] = 1;
    expect(location.key[0], 9);
    expect(
      () => StorageLocation(path: 'fixture', key: [1], isNew: true),
      throwsArgumentError,
    );
    expect(
      () => StorageLocation(path: '', key: fixture, isNew: true),
      throwsArgumentError,
    );
  });
}
