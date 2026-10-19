import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:true_grit_vital/app/app_lock.dart';
import 'package:true_grit_vital/app/storage.dart';
import 'package:true_grit_vital/data/record_store.dart';
import 'package:true_grit_vital/platform/app_auth.dart';

class ControlledAuth implements AppAuthGateway {
  AppAuthAvailability available = AppAuthAvailability.available;
  Future<AppAuthResult> Function()? challenge;
  Future<void> Function(bool)? privacy;
  final privacyCalls = <bool>[];
  int challenges = 0;

  @override
  Future<AppAuthAvailability> availability() async => available;
  @override
  Future<AppAuthResult> authenticate() async {
    challenges++;
    return challenge == null ? AppAuthResult.authenticated : await challenge!();
  }

  @override
  Future<void> setPrivacyEnabled(bool enabled) async {
    privacyCalls.add(enabled);
    await privacy?.call(enabled);
  }
}

Future<void> waitUntil(bool Function() predicate) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!predicate()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Controller state did not settle within five seconds');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

void main() {
  late Directory directory;
  late RecordStore store;
  late ControlledAuth auth;
  late ProviderContainer container;
  late Future<void> Function(RecordStore, bool, bool Function()) writer;
  final stores = <RecordStore>[];
  final key = List.generate(32, (index) => index + 1);

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('vital-lock-controller-');
    store = await RecordStore.open(
      path: '${directory.path}/first.db',
      key: key,
      isNew: true,
    );
    stores.add(store);
    auth = ControlledAuth();
    writer = (target, enabled, canCommit) => target.writeSetting(
      'app_lock',
      enabled.toString(),
      canCommit: canCommit,
    );
    container = ProviderContainer(
      overrides: [
        storeLoaderProvider.overrideWithValue(() async => store),
        appAuthGatewayProvider.overrideWithValue(auth),
        appLockWriterProvider.overrideWithValue(
          (target, enabled, canCommit) => writer(target, enabled, canCommit),
        ),
      ],
    );
    container.listen(appLockProvider, (_, _) {});
    await waitUntil(() => container.read(appLockProvider).ready);
  });

  tearDown(() async {
    container.dispose();
    for (final value in stores) {
      await value.close();
    }
    stores.clear();
    await directory.delete(recursive: true);
  });

  test('unsupported host cannot enable or persist a lock', () async {
    auth.available = AppAuthAvailability.unsupported;
    await container.read(appLockProvider.notifier).setEnabled(true);
    expect(container.read(appLockProvider).enabled, isFalse);
    expect(container.read(appLockProvider).locked, isFalse);
    expect(await store.readSetting('app_lock'), isNull);
    expect(auth.challenges, 0);
  });

  test(
    'cancelled credential setup resumes the original unlocked state',
    () async {
      final result = Completer<AppAuthResult>();
      auth.challenge = () => result.future;
      final controller = container.read(appLockProvider.notifier);
      final pending = controller.setEnabled(true);
      await waitUntil(() => auth.challenges == 1);
      controller.lifecycle(AppLifecycleState.inactive);
      controller.lifecycle(AppLifecycleState.resumed);
      result.complete(AppAuthResult.cancelled);
      await pending;
      expect(container.read(appLockProvider).enabled, isFalse);
      expect(container.read(appLockProvider).locked, isFalse);
      expect(store.writesSuspended, isFalse);
      expect(await store.readSetting('app_lock'), isNull);
    },
  );

  test(
    'background during privacy setup prevents enabling persistence',
    () async {
      final privacy = Completer<void>();
      auth.privacy = (enabled) => enabled ? privacy.future : Future.value();
      final controller = container.read(appLockProvider.notifier);
      final pending = controller.setEnabled(true);
      await waitUntil(() => auth.privacyCalls.contains(true));
      controller.lifecycle(AppLifecycleState.paused);
      privacy.complete();
      await pending;
      expect(await store.readSetting('app_lock'), isNull);
      expect(container.read(appLockProvider).enabled, isFalse);
      expect(auth.privacyCalls.last, isFalse);
    },
  );

  test(
    'background during settings persistence fails its commit guard',
    () async {
      final entered = Completer<void>(), release = Completer<void>();
      writer = (target, enabled, canCommit) async {
        entered.complete();
        await release.future;
        await target.writeSetting(
          'app_lock',
          enabled.toString(),
          canCommit: canCommit,
        );
      };
      final controller = container.read(appLockProvider.notifier);
      final pending = controller.setEnabled(true);
      await entered.future;
      controller.lifecycle(AppLifecycleState.paused);
      release.complete();
      await pending;
      expect(await store.readSetting('app_lock'), isNull);
      expect(container.read(appLockProvider).enabled, isFalse);
      expect(container.read(appLockProvider).failed, isTrue);
    },
  );

  test('cancelled unlock preserves protection and suspended writes', () async {
    final controller = container.read(appLockProvider.notifier);
    await controller.setEnabled(true);
    controller.lock();
    auth.challenge = () async => AppAuthResult.cancelled;
    await controller.unlock();
    expect(container.read(appLockProvider).enabled, isTrue);
    expect(container.read(appLockProvider).locked, isTrue);
    expect(store.writesSuspended, isTrue);
    expect(auth.privacyCalls.last, isTrue);
  });

  test(
    'old authentication completion cannot unlock a replacement dataset',
    () async {
      final controller = container.read(appLockProvider.notifier);
      await controller.setEnabled(true);
      controller.lock();
      final result = Completer<AppAuthResult>();
      auth.challenge = () => result.future;
      final pending = controller.unlock();
      await waitUntil(() => auth.challenges == 2);
      final replacement = await RecordStore.open(
        path: '${directory.path}/replacement.db',
        key: key,
        isNew: true,
      );
      stores.add(replacement);
      await replacement.writeSetting('app_lock', 'true');
      container.updateOverrides([
        storeLoaderProvider.overrideWithValue(() async => replacement),
        appAuthGatewayProvider.overrideWithValue(auth),
        appLockWriterProvider.overrideWithValue(
          (target, enabled, canCommit) => writer(target, enabled, canCommit),
        ),
      ]);
      await container.read(recordStoreProvider.future);
      await waitUntil(() => container.read(appLockProvider).ready);
      result.complete(AppAuthResult.authenticated);
      await pending;
      expect(container.read(appLockProvider).locked, isTrue);
      expect(replacement.writesSuspended, isTrue);
    },
  );

  test(
    'initialization failure can retry without exposing the dataset',
    () async {
      auth.privacy = (_) async =>
          throw const AppPrivacyException('test_failure');
      container.invalidate(appLockProvider);
      await waitUntil(() => container.read(appLockProvider).failed);
      expect(container.read(appLockProvider).ready, isFalse);
      expect(container.read(appLockProvider).locked, isTrue);
      expect(store.writesSuspended, isTrue);
      auth.privacy = null;
      container.invalidate(appLockProvider);
      await waitUntil(() => container.read(appLockProvider).ready);
      expect(container.read(appLockProvider).locked, isFalse);
      expect(store.writesSuspended, isFalse);
    },
  );
}
