import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:true_grit_vital/platform/app_auth.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('true_grit_vital/app_auth');
  const auth = MethodChannelAppAuth();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.android);
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('Linux never authenticates or claims enabled privacy', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    messenger.setMockMethodCallHandler(
      channel,
      (_) async => fail('Unexpected channel'),
    );
    expect(await auth.availability(), AppAuthAvailability.unsupported);
    expect(await auth.authenticate(), AppAuthResult.unavailable);
    await expectLater(
      auth.setPrivacyEnabled(true),
      throwsA(isA<AppPrivacyException>()),
    );
    await auth.setPrivacyEnabled(false);
  });

  for (final availability in AppAuthAvailability.values) {
    test('availability preserves ${availability.name}', () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'availability');
        return availability.name;
      });
      expect(await auth.availability(), availability);
    });
  }

  for (final result in AppAuthResult.values) {
    test('authentication preserves ${result.name}', () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'authenticate');
        expect(call.arguments, isNull);
        return result.name;
      });
      expect(await auth.authenticate(), result);
    });
  }

  test('unknown and missing replies fail closed', () async {
    messenger.setMockMethodCallHandler(channel, (_) async => 'unexpected');
    expect(
      await auth.availability(),
      AppAuthAvailability.temporarilyUnavailable,
    );
    expect(await auth.authenticate(), AppAuthResult.failed);
    messenger.setMockMethodCallHandler(
      channel,
      (_) async => {'malformed': true},
    );
    expect(
      await auth.availability(),
      AppAuthAvailability.temporarilyUnavailable,
    );
    expect(await auth.authenticate(), AppAuthResult.failed);
    messenger.setMockMethodCallHandler(channel, null);
    expect(await auth.availability(), AppAuthAvailability.unsupported);
    expect(await auth.authenticate(), AppAuthResult.unavailable);
  });

  test('OS exceptions are coarse failures without exposing messages', () async {
    messenger.setMockMethodCallHandler(channel, (_) async {
      throw PlatformException(code: 'secret', message: 'sensitive-message');
    });
    expect(
      await auth.availability(),
      AppAuthAvailability.temporarilyUnavailable,
    );
    expect(await auth.authenticate(), AppAuthResult.failed);
    try {
      await auth.setPrivacyEnabled(true);
      fail('Expected privacy failure');
    } on AppPrivacyException catch (error) {
      expect(error.code, 'privacy_unavailable');
      expect(error.toString(), isNot(contains('sensitive')));
    }
  });

  test('privacy requires an explicit native acknowledgement', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'setPrivacyEnabled');
      expect(call.arguments, {'enabled': true});
      return true;
    });
    await auth.setPrivacyEnabled(true);
    messenger.setMockMethodCallHandler(channel, (_) async => null);
    await expectLater(
      auth.setPrivacyEnabled(true),
      throwsA(isA<AppPrivacyException>()),
    );
  });
}
