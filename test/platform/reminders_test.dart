import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:true_grit_vital/platform/reminders.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(
    () => messenger.setMockMethodCallHandler(AndroidReminders.channel, null),
  );
  test(
    'opaque wire preserves elapsed absolute deadline and receipts',
    () async {
      messenger.setMockMethodCallHandler(AndroidReminders.channel, (
        call,
      ) async {
        expect(call.method, 'applySnapshot');
        final wire = call.arguments as Map<Object?, Object?>;
        expect(wire['epoch'], 'opaque-epoch');
        final request =
            (wire['desired'] as List<Object?>).single as Map<Object?, Object?>;
        expect(request['clock'], 'elapsed');
        expect(request['purpose'], 'ordinary');
        expect(request['deadlineMilliseconds'], 4500000);
        expect(
          request.keys,
          unorderedEquals([
            'epoch',
            'purpose',
            'requestToken',
            'takenToken',
            'snoozeToken',
            'skipToken',
            'clock',
            'deadlineMilliseconds',
            'bootId',
          ]),
        );
        return {
          'accepted': true,
          'epoch': 'opaque-epoch',
          'sequence': 4,
          'fingerprint': 'v1',
          'receipts': [
            {
              'requestToken': 'request',
              'state': 'postUncertain',
              'reason': 'presentation_uncertain',
            },
          ],
        };
      });
      final result = await const AndroidReminders().applySnapshot(
        epoch: 'opaque-epoch',
        sequence: 4,
        desired: [
          const NativeReminderRequest(
            epoch: 'opaque-epoch',
            requestToken: 'request',
            takenToken: 'taken',
            snoozeToken: 'snooze',
            skipToken: 'skip',
            clock: ReminderNativeClock.elapsed,
            deadlineMilliseconds: 4500000,
            bootId: 'boot1',
          ),
        ],
        obsoleteTokens: [],
      );
      expect(result.receipts.single.state, NativeReminderState.postUncertain);
      expect(result.sequence, 4);
    },
  );
  test('capabilities read never requests permission', () async {
    final calls = <String>[];
    messenger.setMockMethodCallHandler(AndroidReminders.channel, (call) async {
      calls.add(call.method);
      return {
        'supported': true,
        'notificationPermission': false,
        'appEnabled': true,
        'channelEnabled': true,
        'exactAlarm': false,
        'protectedStorageAvailable': true,
        'bootIdentityAvailable': true,
        'fingerprint': 'v1',
      };
    });
    final result = await const AndroidReminders().capabilities();
    expect(result.notificationPermission, false);
    expect(result.exactAlarm, false);
    expect(result.installedEpoch, isNull);
    expect(calls, ['capabilities']);
  });
  test(
    'capabilities carry the installed epoch for a restore handshake',
    () async {
      messenger.setMockMethodCallHandler(AndroidReminders.channel, (_) async {
        return {
          'supported': true,
          'notificationPermission': true,
          'appEnabled': true,
          'channelEnabled': true,
          'exactAlarm': true,
          'protectedStorageAvailable': true,
          'bootIdentityAvailable': true,
          'fingerprint': 'v1',
          'installedEpoch': 'epoch-old',
        };
      });
      final result = await const AndroidReminders().capabilities();
      expect(result.installedEpoch, 'epoch-old');
    },
  );
  test(
    'action observation does not implicitly acknowledge durable transport',
    () async {
      final calls = <String>[];
      messenger.setMockMethodCallHandler(AndroidReminders.channel, (
        call,
      ) async {
        calls.add(call.method);
        if (call.method == 'acknowledgeAction') return null;
        return {
          'envelopeId': 'e',
          'epoch': 'g',
          'requestToken': 'r',
          'actionToken': 'a',
          'action': 'snooze',
        };
      });
      const gateway = AndroidReminders();
      expect((await gateway.getInitialAction())?.envelopeId, 'e');
      expect((await gateway.getInitialAction())?.envelopeId, 'e');
      expect(calls, ['getInitialAction', 'getInitialAction']);
      await gateway.acknowledgeAction('e');
      expect(calls.last, 'acknowledgeAction');
    },
  );
  test('native failures stay failures instead of claiming absence', () async {
    messenger.setMockMethodCallHandler(
      AndroidReminders.channel,
      (_) async =>
          throw PlatformException(code: 'protected_storage_unavailable'),
    );
    expect(
      const AndroidReminders().inspect(['r']),
      throwsA(isA<PlatformException>()),
    );
  });
  test('unsupported desktop remains callable without a plugin', () async {
    const gateway = UnsupportedReminders();
    expect((await gateway.capabilities()).supported, false);
    expect(await gateway.getInitialAction(), null);
    expect(await gateway.cancel(['r']), isEmpty);
    expect(await gateway.changes.toList(), isEmpty);
    expect(gateway.sampleClock(), throwsUnsupportedError);
  });
}
