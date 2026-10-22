import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:true_grit_vital/app/app_lock.dart';
import 'package:true_grit_vital/app/reminder_alerts.dart';
import 'package:true_grit_vital/app/reminder_gateway.dart';
import 'package:true_grit_vital/app/storage.dart';
import 'package:true_grit_vital/data/record_store.dart';
import 'package:true_grit_vital/platform/reminders.dart';

/// A complete adapter double: the controller only applies alert choices, but
/// the same provider also feeds the reminder runtime in production.
final class AlertGateway implements ReminderGateway, ReminderAlertGateway {
  AlertGateway({this.accept = true});
  final List<ReminderAlertPreferences> applied = [];
  bool accept;
  bool throwOnApply = false;
  int cancels = 0;
  @override
  Future<bool> applyAlertPreferences(
    ReminderAlertPreferences preferences,
  ) async {
    if (throwOnApply) throw PlatformException(code: 'apply_unavailable');
    applied.add(preferences);
    return accept;
  }

  @override
  Future<ReminderCapabilities> capabilities() async =>
      const ReminderCapabilities(
        supported: true,
        notificationPermission: true,
        appEnabled: true,
        channelEnabled: true,
        exactAlarm: true,
        protectedStorageAvailable: true,
        bootIdentityAvailable: true,
        alertChoicesAvailable: true,
        fingerprint: 'alert-test',
      );
  @override
  Future<NativeReminderSnapshot> applySnapshot({
    required String epoch,
    required int sequence,
    required List<NativeReminderRequest> desired,
    required List<String> obsoleteTokens,
  }) async => NativeReminderSnapshot(
    accepted: true,
    epoch: epoch,
    sequence: sequence,
    receipts: [
      for (final request in desired)
        NativeReminderReceipt(
          requestToken: request.requestToken,
          state: NativeReminderState.accepted,
        ),
    ],
    fingerprint: 'alert-test',
  );
  @override
  Future<List<NativeReminderReceipt>> cancel(List<String> tokens) async {
    cancels++;
    return [];
  }

  @override
  Future<List<NativeReminderReceipt>> inspect(List<String> tokens) async => [];
  @override
  Future<NativeReminderAction?> getInitialAction() async => null;
  @override
  Future<void> acknowledgeAction(String envelopeId) async {}
  @override
  Future<bool> invalidateEpoch({
    required String oldEpoch,
    required String newEpoch,
  }) async => true;
  @override
  Future<bool> openExactAlarmSettings() async => true;
  @override
  Future<bool> openNotificationSettings() async => true;
  @override
  Future<bool> requestNotifications() async => true;
  @override
  Future<ReminderClockSample> sampleClock() async => ReminderClockSample(
    utcMilliseconds: DateTime.now().toUtc().millisecondsSinceEpoch,
    elapsedMilliseconds: 1000,
    bootId: 'boot',
  );
  @override
  Stream<void> get changes => const Stream.empty();
}

class UnlockedLock extends AppLockController {
  @override
  AppLockState build() => const AppLockState(ready: true, locked: false);
}

class LockedLock extends AppLockController {
  @override
  AppLockState build() => const AppLockState(ready: true, locked: true);
}

class ToggleLock extends AppLockController {
  @override
  AppLockState build() => const AppLockState(ready: true, locked: true);
  void clearLock() => state = const AppLockState(ready: true, locked: false);
}

final class _Fixture {
  _Fixture(this.root, this.store, this.container, this.gateway, this.loader);
  final Directory root;
  final RecordStore store;
  final ProviderContainer container;
  final AlertGateway gateway;

  /// Mutable dataset seam; a restore replaces the store behind this loader.
  final _Loader loader;
}

final class _Loader {
  _Loader(this.store);
  RecordStore store;
  Future<RecordStore> call() async => store;
}

Future<RecordStore> _openStore(Directory root, String name) async {
  final directory = Directory('${root.path}/$name')..createSync();
  return RecordStore.open(
    path: '${directory.path}/db',
    key: List.generate(32, (index) => index + 1),
    isNew: true,
  );
}

Future<void> _waitFor(
  Future<bool> Function() condition, {
  String reason = 'fixture condition',
}) async {
  for (var attempt = 0; attempt < 3000; attempt++) {
    if (await condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 2));
    await pumpEventQueue();
  }
  fail(reason);
}

Future<_Fixture> _fixture({
  String? setting,
  bool locked = false,
  AppLockController Function()? lock,
  AlertGateway? gateway,
  ReminderAlertsWriter? writer,
}) async {
  final root = await Directory.systemTemp.createTemp('vital-alert-settings-');
  final store = await _openStore(root, 'records');
  if (setting != null) {
    await store.writeSetting(reminderAlertsSettingKey, setting);
  }
  final loader = _Loader(store);
  final adapter = gateway ?? AlertGateway();
  final container = ProviderContainer(
    overrides: [
      storeLoaderProvider.overrideWithValue(loader.call),
      reminderGatewayProvider.overrideWithValue(adapter),
      appLockProvider.overrideWith(
        lock ?? (locked ? LockedLock.new : UnlockedLock.new),
      ),
      if (writer != null)
        reminderAlertsWriterProvider.overrideWithValue(writer),
    ],
  );
  addTearDown(() async {
    container.dispose();
    await store.close();
    await loader.store.close();
    await root.delete(recursive: true);
  });
  container.listen(reminderAlertsProvider, (_, _) {}, fireImmediately: true);
  return _Fixture(root, store, container, adapter, loader);
}

Future<ReminderAlerts> _settled(_Fixture fixture) async {
  await _waitFor(
    () async =>
        fixture.container.read(reminderAlertsProvider).loaded &&
        fixture.gateway.applied.isNotEmpty,
    reason: 'alert preference did not load and apply',
  );
  return fixture.container.read(reminderAlertsProvider);
}

void main() {
  group('alert preference record', () {
    test('legacy is sound and vibration, and explicit choices round trip', () {
      expect(ReminderAlertPreferences.legacy.sound, true);
      expect(ReminderAlertPreferences.legacy.vibration, true);
      expect(ReminderAlertPreferences.legacy.isLegacy, true);
      const choice = ReminderAlertPreferences(sound: false, vibration: true);
      expect(ReminderAlertPreferences.decode(choice.encode()), choice);
      expect(choice.isLegacy, false);
    });
    test('absent keys keep legacy, explicit false disables, damage fails', () {
      expect(
        ReminderAlertPreferences.decode('{}'),
        ReminderAlertPreferences.legacy,
      );
      expect(
        ReminderAlertPreferences.decode('{"sound":false}'),
        const ReminderAlertPreferences(sound: false, vibration: true),
      );
      expect(
        ReminderAlertPreferences.decode('{"vibration":false}'),
        const ReminderAlertPreferences(sound: true, vibration: false),
      );
      expect(
        () => ReminderAlertPreferences.decode('not-json'),
        throwsFormatException,
      );
      expect(
        () => ReminderAlertPreferences.decode('[]'),
        throwsFormatException,
      );
      expect(
        () => ReminderAlertPreferences.decode('{"sound":"no"}'),
        throwsFormatException,
      );
    });
  });

  group('alert preference settings', () {
    test(
      'a saved choice is applied on load and advances reconciliation',
      () async {
        final fixture = await _fixture(
          setting: '{"sound":false,"vibration":true}',
        );
        final state = await _settled(fixture);
        expect(
          state.preferences,
          const ReminderAlertPreferences(sound: false, vibration: true),
        );
        expect(state.applyFailed, false);
        expect(fixture.gateway.applied.last, state.preferences);
        expect(state.revision, greaterThan(0));
      },
    );

    test('an absent choice keeps the legacy channel and default', () async {
      final fixture = await _fixture();
      final state = await _settled(fixture);
      expect(state.preferences, ReminderAlertPreferences.legacy);
      expect(fixture.gateway.applied.single, ReminderAlertPreferences.legacy);
      expect(await fixture.store.readSetting(reminderAlertsSettingKey), isNull);
    });

    test('a change persists before applying and survives a reload', () async {
      final fixture = await _fixture();
      await _settled(fixture);
      final ok = await fixture.container
          .read(reminderAlertsProvider.notifier)
          .setSound(false);
      expect(ok, true);
      expect(
        await fixture.store.readSetting(reminderAlertsSettingKey),
        '{"sound":false,"vibration":true}',
      );
      expect(
        fixture.gateway.applied.last,
        const ReminderAlertPreferences(sound: false, vibration: true),
      );
      final revision = fixture.container.read(reminderAlertsProvider).revision;

      // A fresh container is the cold-start/reload path: the durable record is
      // read again and its intent is applied to a new adapter instance.
      final reloadedGateway = AlertGateway();
      final reloadedContainer = ProviderContainer(
        overrides: [
          storeLoaderProvider.overrideWithValue(() async => fixture.store),
          reminderGatewayProvider.overrideWithValue(reloadedGateway),
          appLockProvider.overrideWith(UnlockedLock.new),
        ],
      );
      addTearDown(reloadedContainer.dispose);
      reloadedContainer.listen(
        reminderAlertsProvider,
        (_, _) {},
        fireImmediately: true,
      );
      await _waitFor(
        () async =>
            reloadedContainer.read(reminderAlertsProvider).loaded &&
            reloadedGateway.applied.isNotEmpty,
        reason: 'the saved alert choice did not reload',
      );
      final reloaded = reloadedContainer.read(reminderAlertsProvider);
      expect(
        reloaded.preferences,
        const ReminderAlertPreferences(sound: false, vibration: true),
      );
      expect(
        reloadedGateway.applied.single,
        const ReminderAlertPreferences(sound: false, vibration: true),
      );
      expect(reloaded.revision, greaterThan(0));
      expect(revision, greaterThan(0));
    });

    test(
      'a damaged record is an explicit read failure, not a silent reset',
      () async {
        final fixture = await _fixture(setting: 'not-json');
        await _waitFor(
          () async => fixture.container.read(reminderAlertsProvider).loaded,
        );
        final state = fixture.container.read(reminderAlertsProvider);
        expect(state.loadFailed, true);
        expect(state.preferences, ReminderAlertPreferences.legacy);
        expect(fixture.gateway.applied, isEmpty);
      },
    );

    test(
      'a write failure restores the previous choice and is not applied',
      () async {
        final fixture = await _fixture(
          writer: (store, value, canCommit) async {
            throw StateError('injected');
          },
        );
        await _settled(fixture);
        final ok = await fixture.container
            .read(reminderAlertsProvider.notifier)
            .setVibration(false);
        expect(ok, false);
        final state = fixture.container.read(reminderAlertsProvider);
        expect(state.preferences, ReminderAlertPreferences.legacy);
        expect(state.saveFailed, true);
        expect(state.busy, false);
        expect(
          await fixture.store.readSetting(reminderAlertsSettingKey),
          isNull,
        );
        expect(fixture.gateway.applied, [ReminderAlertPreferences.legacy]);
      },
    );

    test(
      'an unapplied native change stays saved, reports it and retries',
      () async {
        final gateway = AlertGateway(accept: false);
        final fixture = await _fixture(gateway: gateway);
        await _waitFor(
          () async =>
              fixture.container.read(reminderAlertsProvider).loaded &&
              fixture.container.read(reminderAlertsProvider).applyFailed,
          reason: 'the initial unapplied choice was not reported',
        );
        final ok = await fixture.container
            .read(reminderAlertsProvider.notifier)
            .setSound(false);
        expect(ok, true);
        expect(
          fixture.container.read(reminderAlertsProvider).applyFailed,
          true,
        );
        expect(
          await fixture.store.readSetting(reminderAlertsSettingKey),
          '{"sound":false,"vibration":true}',
        );

        gateway.accept = true;
        expect(
          await fixture.container
              .read(reminderAlertsProvider.notifier)
              .retryApply(),
          true,
        );
        final state = fixture.container.read(reminderAlertsProvider);
        expect(state.applyFailed, false);
        expect(
          state.preferences,
          const ReminderAlertPreferences(sound: false, vibration: true),
        );
        expect(gateway.applied.last, state.preferences);
      },
    );

    test(
      'a native exception is reported as unapplied, not as a lost choice',
      () async {
        final gateway = AlertGateway()..throwOnApply = true;
        final fixture = await _fixture(gateway: gateway);
        await _waitFor(
          () async =>
              fixture.container.read(reminderAlertsProvider).loaded &&
              fixture.container.read(reminderAlertsProvider).applyFailed,
        );
        expect(
          fixture.container.read(reminderAlertsProvider).preferences,
          ReminderAlertPreferences.legacy,
        );
        expect(
          fixture.container.read(reminderAlertsProvider).saveFailed,
          false,
        );
        expect(fixture.gateway.applied, isEmpty);
      },
    );

    test('a locked app never writes or applies a changed choice', () async {
      final fixture = await _fixture(locked: true);
      await _settled(fixture);
      final ok = await fixture.container
          .read(reminderAlertsProvider.notifier)
          .setSound(false);
      expect(ok, false);
      expect(
        fixture.container.read(reminderAlertsProvider).preferences,
        ReminderAlertPreferences.legacy,
      );
      expect(await fixture.store.readSetting(reminderAlertsSettingKey), isNull);
      expect(fixture.gateway.applied, [ReminderAlertPreferences.legacy]);
    });

    test('an unapplied choice retries once the lock clears', () async {
      final gateway = AlertGateway()..throwOnApply = true;
      final fixture = await _fixture(gateway: gateway, lock: ToggleLock.new);
      await _waitFor(
        () async =>
            fixture.container.read(reminderAlertsProvider).loaded &&
            fixture.container.read(reminderAlertsProvider).applyFailed,
        reason: 'the locked apply failure was not reported',
      );
      gateway.throwOnApply = false;
      (fixture.container.read(appLockProvider.notifier) as ToggleLock)
          .clearLock();
      await _waitFor(
        () async =>
            !fixture.container.read(reminderAlertsProvider).applyFailed &&
            gateway.applied.isNotEmpty,
        reason: 'the alert choice did not retry after unlock',
      );
      expect(gateway.applied.last, ReminderAlertPreferences.legacy);
    });

    test(
      'a channel failure after saving keeps intent and recovers on retry',
      () async {
        final fixture = await _fixture();
        await _settled(fixture);
        fixture.gateway.throwOnApply = true;
        final saved = await fixture.container
            .read(reminderAlertsProvider.notifier)
            .setSound(false);
        expect(saved, true);
        expect(
          fixture.container.read(reminderAlertsProvider).applyFailed,
          true,
        );
        expect(
          await fixture.store.readSetting(reminderAlertsSettingKey),
          '{"sound":false,"vibration":true}',
        );

        fixture.gateway.throwOnApply = false;
        expect(
          await fixture.container
              .read(reminderAlertsProvider.notifier)
              .retryApply(),
          true,
        );
        final state = fixture.container.read(reminderAlertsProvider);
        expect(state.applyFailed, false);
        expect(
          state.preferences,
          const ReminderAlertPreferences(sound: false, vibration: true),
        );
        expect(fixture.gateway.applied.last, state.preferences);
      },
    );

    test('a replacement adapter reapplies the same saved choice', () async {
      final fixture = await _fixture(
        setting: '{"sound":false,"vibration":true}',
      );
      await _settled(fixture);
      final replacement = AlertGateway();
      fixture.container.updateOverrides([
        storeLoaderProvider.overrideWithValue(fixture.loader.call),
        reminderGatewayProvider.overrideWithValue(replacement),
        appLockProvider.overrideWith(UnlockedLock.new),
      ]);
      await _waitFor(
        () async => replacement.applied.isNotEmpty,
        reason: 'the replacement adapter did not receive the saved choice',
      );
      expect(
        replacement.applied.single,
        const ReminderAlertPreferences(sound: false, vibration: true),
      );
    });

    test('a restored dataset reapplies an identical choice', () async {
      final fixture = await _fixture(
        setting: '{"sound":false,"vibration":true}',
      );
      await _settled(fixture);
      final applied = fixture.gateway.applied.length;
      final restored = await _openStore(fixture.root, 'restored-same');
      await restored.writeSetting(
        reminderAlertsSettingKey,
        '{"sound":false,"vibration":true}',
      );
      addTearDown(restored.close);
      fixture.loader.store = restored;
      fixture.container.invalidate(recordStoreProvider);
      await _waitFor(
        () async =>
            fixture.container.read(reminderAlertsProvider).loaded &&
            fixture.gateway.applied.length > applied,
        reason: 'an identical choice was skipped after a dataset change',
      );
      expect(
        fixture.gateway.applied.last,
        const ReminderAlertPreferences(sound: false, vibration: true),
      );
    });

    test(
      'a restored dataset reloads its own choice, including the default',
      () async {
        final fixture = await _fixture(
          setting: '{"sound":false,"vibration":false}',
        );
        await _settled(fixture);
        final restored = await _openStore(fixture.root, 'restored');
        addTearDown(restored.close);
        fixture.loader.store = restored;
        fixture.container.invalidate(recordStoreProvider);
        await _waitFor(
          () async =>
              fixture.container.read(reminderAlertsProvider).loaded &&
              fixture.gateway.applied.last == ReminderAlertPreferences.legacy,
          reason: 'the restored default choice was not applied',
        );
        expect(
          fixture.container.read(reminderAlertsProvider).preferences,
          ReminderAlertPreferences.legacy,
        );
      },
    );
  });

  test(
    'changing alerts keeps prepared reminder identity and cancels nothing',
    () async {
      final fixture = await _fixture();
      final store = fixture.store;
      await store.editProfile(
        commandId: 'adult',
        personId: meId,
        expectedRevision: 1,
        name: 'Ada',
        adultConfirmed: true,
      );
      final item = await store.createItem(
        commandId: 'item',
        expectedPersonRevision: 2,
        name: 'Original substance',
        form: 'tablet',
        unit: 'mg',
        type: 'medicine',
      );
      final now = DateTime.utc(2026, 10, 22, 6);
      final date = CivilDate.fromDateTime(now);
      await store.saveDailyPlan(
        commandId: 'plan',
        expectedPersonRevision: 2,
        expectedGeneration: store.generation,
        plan: DailyPlanVersion(
          personId: meId,
          itemId: item.id,
          planId: 'p1',
          versionId: 'v1',
          start: date,
          zoneBasis: const FollowingLocal(),
          timing: DailySlots([
            DailySlot(
              id: 'am',
              time: WallTime(12, 0),
              amount: PlannedAmount(
                quantity: ExactQuantity.parse('1.25'),
                unit: 'mg',
              ),
              reminderEnabled: true,
            ),
          ]),
        ),
      );
      await store.setPlanReminders(
        commandId: 'enable',
        planId: 'p1',
        personId: meId,
        expectedPlanRevision: 1,
        expectedPersonRevision: 2,
        enabled: true,
      );
      final before = await store.prepareReminders(
        now: now,
        observedZone: 'Europe/London',
        clockSample: null,
        adapterFingerprint: 'alert-test',
      );
      expect(before.desired, isNotEmpty);
      await _settled(fixture);
      final ok = await fixture.container
          .read(reminderAlertsProvider.notifier)
          .setVibration(false);
      expect(ok, true);
      final after = await store.prepareReminders(
        now: now,
        observedZone: 'Europe/London',
        clockSample: null,
        adapterFingerprint: 'alert-test',
      );
      expect(
        after.desired.map((value) => value.requestToken),
        before.desired.map((value) => value.requestToken),
      );
      final beforeTokens = before.desired
          .map((value) => value.requestToken)
          .toSet();
      expect(after.obsoleteTokens.where(beforeTokens.contains), isEmpty);
      expect(fixture.gateway.cancels, 0);
    },
  );
}
