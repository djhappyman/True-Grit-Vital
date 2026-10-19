import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:true_grit_vital/app/app_lock.dart';
import 'package:true_grit_vital/app/storage.dart';
import 'package:true_grit_vital/app/vital_app.dart';
import 'package:true_grit_vital/data/record_store.dart';
import 'package:true_grit_vital/platform/app_auth.dart';

class _ObservedNativeAuth implements AppAuthGateway {
  const _ObservedNativeAuth();
  static const delegate = MethodChannelAppAuth();
  @override
  Future<AppAuthAvailability> availability() => delegate.availability();
  @override
  Future<void> setPrivacyEnabled(bool enabled) =>
      delegate.setPrivacyEnabled(enabled);
  @override
  Future<AppAuthResult> authenticate() async {
    final result = await delegate.authenticate();
    debugPrint(
      'VITAL_AUTH_RESULT:${result.name}:${WidgetsBinding.instance.lifecycleState?.name}',
    );
    return result;
  }
}

/// Run through tool/check_android_auth.py on its dedicated disposable AVD only.
/// The encrypted fixture never opens or changes the production dataset.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('real Android credential and window privacy boundary', (
    tester,
  ) async {
    const auth = _ObservedNativeAuth();
    Directory? directory;
    RecordStore? store;
    ProviderContainer? container;
    Future<void> waitFor(bool Function() condition) async {
      for (var i = 0; i < 300; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        if (condition()) return;
      }
      fail('Native auth fixture did not reach the expected state');
    }

    Future<void> checkpoint(String name) async {
      // Only synthetic test coordination markers, never record or auth payloads.
      debugPrint('VITAL_AUTH_STEP:$name');
      final ack = File('${Directory.systemTemp.path}/vital-auth-ack-$name');
      for (var i = 0; i < 300; i++) {
        if (await File('${Directory.systemTemp.path}/vital-auth-driver-error')
            .exists()) {
          fail('Native auth driver reported a failed check');
        }
        if (await ack.exists()) {
          await ack.delete();
          return;
        }
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      fail('Native auth driver did not acknowledge $name');
    }

    Future<void> authenticate(
      String name,
      Future<void> Function() action,
    ) async {
      final operation = action();
      debugPrint('VITAL_AUTH_STEP:$name');
      await operation.timeout(const Duration(seconds: 45));
      await tester.pumpAndSettle();
    }

    try {
      debugPrint('VITAL_AUTH_TEMP:${Directory.systemTemp.path}');
      await checkpoint('initial-secure');
      expect(await auth.availability(), AppAuthAvailability.setupRequired);
      directory = await Directory.systemTemp.createTemp('vital-native-auth-');
      store = await RecordStore.open(
        path: '${directory.path}/records.db',
        key: List.generate(32, (i) => i + 1),
        isNew: true,
      );
      await store.editProfile(
        commandId: 'native-auth-fixture',
        personId: meId,
        expectedRevision: 1,
        name: 'Synthetic auth adult',
        adultConfirmed: true,
      );
      await store.writeSetting('app_lock', 'false');
      final testStore = store;
      container = ProviderContainer(
        overrides: [
          storeLoaderProvider.overrideWithValue(() async => testStore),
          appAuthGatewayProvider.overrideWithValue(auth),
        ],
      );
      final testContainer = container;
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: testContainer,
          child: const VitalApp(),
        ),
      );
      await waitFor(() => testContainer.read(appLockProvider).ready);
      final controller = testContainer.read(appLockProvider.notifier);
      await controller.setEnabled(true);
      expect(testContainer.read(appLockProvider).enabled, isFalse);
      expect(await testStore.readSetting('app_lock'), 'false');
      await checkpoint('setup-required-off');
      await checkpoint('configure-pin');
      expect(await auth.availability(), AppAuthAvailability.available);

      await authenticate('cancel-enable', () => controller.setEnabled(true));
      expect(testContainer.read(appLockProvider).enabled, isFalse);
      expect(await testStore.readSetting('app_lock'), 'false');
      await checkpoint('cancel-keeps-off');

      await authenticate('enable-pin', () => controller.setEnabled(true));
      expect(testContainer.read(appLockProvider).enabled, isTrue);
      expect(testContainer.read(appLockProvider).locked, isFalse);
      expect(await testStore.readSetting('app_lock'), 'true');
      expect(find.text('Today'), findsWidgets);
      await checkpoint('enabled-secure');

      await checkpoint('background-return');
      await tester.pumpAndSettle();
      expect(testContainer.read(appLockProvider).locked, isTrue);
      expect(testStore.writesSuspended, isTrue);
      expect(find.text('Today'), findsNothing);
      await authenticate('cancel-unlock', controller.unlock);
      expect(testContainer.read(appLockProvider).locked, isTrue);
      expect(find.text('Today'), findsNothing);
      await checkpoint('cancel-stays-locked');
      await authenticate('unlock-pin', controller.unlock);
      expect(testContainer.read(appLockProvider).locked, isFalse);
      expect(testStore.writesSuspended, isFalse);
      expect(find.text('Today'), findsWidgets);
      await checkpoint('unlocked-secure');

      await authenticate('disable-pin', () => controller.setEnabled(false));
      expect(testContainer.read(appLockProvider).enabled, isFalse);
      expect(await testStore.readSetting('app_lock'), 'false');
      await checkpoint('disabled-unsecured');
      expect(tester.takeException(), isNull);
    } finally {
      // Only this explicitly synthetic encrypted fixture is reset for teardown.
      if (store != null) {
        store.suspendWrites(false);
        await store.writeSetting('app_lock', 'false');
      }
      await auth.setPrivacyEnabled(false);
      debugPrint('VITAL_AUTH_LOCK_DISABLED');
      await tester.pumpWidget(const SizedBox.shrink());
      container?.dispose();
      await store?.close();
      if (directory != null) await directory.delete(recursive: true);
    }
  });
}
