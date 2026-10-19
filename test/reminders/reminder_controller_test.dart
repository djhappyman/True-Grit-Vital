import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:true_grit_vital/app/app_lock.dart';
import 'package:true_grit_vital/app/device_zone.dart';
import 'package:true_grit_vital/app/reminders.dart';
import 'package:true_grit_vital/app/storage.dart';
import 'package:true_grit_vital/data/record_store.dart';
import 'package:true_grit_vital/platform/app_auth.dart';
import 'package:true_grit_vital/platform/device_zone.dart';
import 'package:true_grit_vital/platform/reminders.dart';

class TransportGateway implements ReminderGateway {
  final held = Completer<NativeReminderAction?>();
  int reads = 0, acknowledgements = 0, permissionRequests = 0;
  Future<void> Function()? onAck;
  @override
  Future<ReminderCapabilities> capabilities() =>
      const UnsupportedReminders().capabilities();
  @override
  Stream<void> get changes => const Stream.empty();
  @override
  Future<NativeReminderAction?> getInitialAction() async {
    reads++;
    return reads == 1 ? await held.future : null;
  }

  @override
  Future<void> acknowledgeAction(String id) async {
    await onAck?.call();
    acknowledgements++;
  }

  @override
  Future<bool> requestNotifications() async {
    permissionRequests++;
    return false;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class NoLockAuth implements AppAuthGateway {
  @override
  Future<AppAuthAvailability> availability() async =>
      AppAuthAvailability.unsupported;
  @override
  Future<AppAuthResult> authenticate() async => AppAuthResult.cancelled;
  @override
  Future<void> setPrivacyEnabled(bool enabled) async {}
}

class UnlockAuth extends NoLockAuth {
  @override
  Future<AppAuthAvailability> availability() async =>
      AppAuthAvailability.available;
  @override
  Future<AppAuthResult> authenticate() async => AppAuthResult.authenticated;
}

Future<void> until(bool Function() check) async {
  final stop = DateTime.now().add(const Duration(seconds: 5));
  while (!check()) {
    if (DateTime.now().isAfter(stop)) fail('Reminder state did not settle');
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'dataset replacement fences a held native envelope and old completion',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'vital-reminder-provider-',
      );
      final first = await RecordStore.open(
        path: '${dir.path}/a.db',
        key: List.generate(32, (i) => i + 1),
        isNew: true,
      );
      final second = await RecordStore.open(
        path: '${dir.path}/b.db',
        key: List.generate(32, (i) => i + 2),
        isNew: true,
      );
      var current = first;
      final gateway = TransportGateway();
      final container = ProviderContainer(
        overrides: [
          storeLoaderProvider.overrideWithValue(() async => current),
          reminderGatewayProvider.overrideWithValue(gateway),
          appAuthGatewayProvider.overrideWithValue(NoLockAuth()),
          observedDeviceZoneProvider.overrideWith(
            (ref) =>
                Stream.value(DeviceZoneObservation.fromId('Europe/London')),
          ),
        ],
      );
      container.listen(remindersProvider, (_, _) {});
      await until(() => gateway.reads == 1);
      current = second;
      container.invalidate(recordStoreProvider);
      await until(() => gateway.reads >= 2);
      gateway.held.complete(
        const NativeReminderAction(
          envelopeId: 'e1',
          epoch: 'old',
          requestToken: 'r1',
          actionToken: 'a1',
          action: NativeReminderActionKind.taken,
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(gateway.acknowledgements, 0);
      expect(container.read(remindersProvider).pending, isEmpty);
      expect(gateway.permissionRequests, 0);
      container.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await dir.delete(recursive: true);
    },
  );
  test(
    'teardown does not acknowledge an envelope still held by native',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'vital-reminder-dispose-',
      );
      final store = await RecordStore.open(
        path: '${dir.path}/a.db',
        key: List.generate(32, (i) => i + 1),
        isNew: true,
      );
      final gateway = TransportGateway();
      final container = ProviderContainer(
        overrides: [
          storeLoaderProvider.overrideWithValue(() async => store),
          reminderGatewayProvider.overrideWithValue(gateway),
          appAuthGatewayProvider.overrideWithValue(NoLockAuth()),
          observedDeviceZoneProvider.overrideWith(
            (ref) =>
                Stream.value(DeviceZoneObservation.fromId('Europe/London')),
          ),
        ],
      );
      container.listen(remindersProvider, (_, _) {});
      await until(() => gateway.reads == 1);
      container.dispose();
      gateway.held.complete(
        const NativeReminderAction(
          envelopeId: 'e1',
          epoch: 'old',
          requestToken: 'r1',
          actionToken: 'a1',
          action: NativeReminderActionKind.snooze,
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(gateway.acknowledgements, 0);
      await dir.delete(recursive: true);
    },
  );
  test('locked native envelope waits for unlock, durable capture precedes acknowledgement', () async {
    final dir = await Directory.systemTemp.createTemp('vital-reminder-unlock-');
    final path = '${dir.path}/a.db', key = List.generate(32, (i) => i + 1);
    final store = await RecordStore.open(path: path, key: key, isNew: true);
    final item = await store.createItem(
      commandId: 'i',
      name: 'Original substance',
      form: 'tablet',
      unit: 'mg',
      type: 'medicine',
    );
    final date = CivilDate(2026, 10, 19);
    await store.saveDailyPlan(
      commandId: 'p',
      expectedPersonRevision: 1,
      expectedGeneration: store.generation,
      plan: DailyPlanVersion(
        personId: meId,
        itemId: item.id,
        planId: 'p',
        versionId: 'v',
        start: date,
        zoneBasis: const FollowingLocal(),
        timing: DailySlots([
          DailySlot(
            id: 'am',
            time: WallTime(9, 0),
            amount: PlannedAmount(
              quantity: ExactQuantity.parse('1'),
              unit: 'mg',
            ),
            reminderEnabled: false,
          ),
        ]),
      ),
    );
    await store.setPlanReminders(
      commandId: 'enable',
      planId: 'p',
      personId: meId,
      expectedPlanRevision: 1,
      expectedPersonRevision: 1,
      enabled: true,
    );
    final projection = await store.prepareReminders(
      now: DateTime.utc(2026, 10, 19, 6),
      observedZone: 'Europe/London',
      clockSample: null,
      adapterFingerprint: 'test-adapter',
    );
    final request = projection.desired.first;
    await store.writeSetting('app_lock', 'true');
    final gateway = TransportGateway();
    gateway.onAck = () async {
      final pending = await store.pendingReminderActions();
      expect(pending.single.envelopeId, 'held');
      expect(pending.single.target.row.expectation.identity.personId, meId);
    };
    final container = ProviderContainer(
      overrides: [
        storeLoaderProvider.overrideWithValue(() async => store),
        reminderGatewayProvider.overrideWithValue(gateway),
        appAuthGatewayProvider.overrideWithValue(UnlockAuth()),
        observedDeviceZoneProvider.overrideWith(
          (ref) => Stream.value(DeviceZoneObservation.fromId('Europe/London')),
        ),
      ],
    );
    container.listen(remindersProvider, (_, _) {});
    await until(() => container.read(appLockProvider).ready);
    expect(container.read(appLockProvider).locked, true);
    expect(gateway.reads, 0);
    gateway.held.complete(
      NativeReminderAction(
        envelopeId: 'held',
        epoch: projection.namespace,
        requestToken: request.requestToken,
        actionToken: request.snoozeToken,
        action: NativeReminderActionKind.snooze,
      ),
    );
    await container.read(appLockProvider.notifier).unlock();
    await until(() => gateway.acknowledgements == 1);
    expect(await store.records(), isEmpty);
    container.dispose();
    await store.close();
    final reopened = await RecordStore.open(path: path, key: key, isNew: false);
    await expectLater(
      reopened.pendingReminderActions(),
      throwsA(isA<CommandConflict>()),
    );
    // The previous provider test established authentication before access. This
    // new connection explicitly opens its simulated authenticated test session.
    reopened.suspendWrites(false);
    expect((await reopened.pendingReminderActions()).single.envelopeId, 'held');
    expect(await reopened.records(), isEmpty);
    await reopened.close();
    await dir.delete(recursive: true);
  });
}
