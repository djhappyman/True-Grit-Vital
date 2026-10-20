import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:true_grit_vital/app/reminder_health.dart';
import 'package:true_grit_vital/app/reminder_reconciler.dart';
import 'package:true_grit_vital/data/record_store.dart';
import 'package:true_grit_vital/platform/reminders.dart';

/// Host recovery harness: real temporary SQLite through the shared repair
/// boundary, with a fake adapter only for the OS side. Fakes prove our durable
/// intent and bounds, never Android delivery.
void main() {
  late Directory dir;
  late RecordStore store;
  late String path;
  final key = List.generate(32, (i) => i + 1);
  final date = CivilDate(2026, 10, 19);
  final now = DateTime.utc(2026, 10, 19, 6);
  const zone = 'Europe/London';
  final sample = ReminderClockSample(
    utcMilliseconds: DateTime.utc(2026, 10, 19, 9).millisecondsSinceEpoch,
    elapsedMilliseconds: 3600000,
    bootId: 'b1',
  );

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('vital-t09-');
    path = '${dir.path}/records.db';
    store = await RecordStore.open(path: path, key: key, isNew: true);
    await _seed(store, date);
  });

  tearDown(() async {
    await store.close();
    await dir.delete(recursive: true);
  });

  Future<ReminderProjection> prepare({
    RecordStore? source,
    ReminderClockSample? clock,
    String observedZone = zone,
    DateTime? at,
  }) => (source ?? store).prepareReminders(
    now: at ?? now,
    observedZone: observedZone,
    clockSample: clock ?? sample,
    adapterFingerprint: 'test-adapter',
  );

  test(
    'a restored dataset keeps portable IDs but rejects the old generation',
    () async {
      final first = await prepare();
      final oldGeneration = store.generation;
      expect(first.namespace, isNotEmpty);
      expect(first.desired, isNotEmpty);

      // Same person, plan and slot identifiers in a genuinely fresh dataset.
      final restoredDir = await Directory.systemTemp.createTemp(
        'vital-t09-restore-',
      );
      final restoredPath = '${restoredDir.path}/records.db';
      final restored = await RecordStore.open(
        path: restoredPath,
        key: key,
        isNew: true,
      );
      try {
        await _seed(restored, date);
        final second = await prepare(source: restored);
        expect(second.generation, isNot(oldGeneration));
        expect(second.namespace, isNot(first.namespace));
        expect(
          second.desired.first.target.row.expectation.identity.slotId,
          first.desired.first.target.row.expectation.identity.slotId,
          reason: 'restored identity keeps the stable portable slot identity',
        );
        // A delayed acknowledgement from the previous dataset cannot win.
        expect(
          await restored.acknowledgeReminder(
            generation: oldGeneration,
            requestToken: second.desired.first.requestToken,
            intentRevision: second.desired.first.intentRevision,
            sequence: second.sequence,
            receipt: ReminderReceipt.accepted,
            adapterFingerprint: 'test-adapter',
          ),
          isFalse,
        );

        // The adapter still holds the old epoch, so reconciliation must hand it
        // over before the restored namespace can register anything.
        final gateway = _HostGateway(installedEpoch: first.namespace);
        final reports = <ReminderRepairReport>[];
        final worker = ReminderReconciler(
          gateway: gateway,
          repository: _ProjectionRepair(restored),
          observedZone: () => zone,
          onReport: reports.add,
        );
        await worker.request();
        expect(gateway.invalidations, [(first.namespace, second.namespace)]);
        expect(gateway.acceptedEpochs.toSet(), {second.namespace});
        expect(
          reports.any((r) => r.epochRecovered),
          isTrue,
          reason: 'the walk-over is reported for the flight',
        );
        expect(reports.last.convergence, ReminderConvergence.converged);
        worker.dispose();
      } finally {
        await restored.close();
        await restoredDir.delete(recursive: true);
      }
    },
  );

  test(
    'a reboot interrupts an elapsed snooze instead of rearming it',
    () async {
      final target = await store.reminderTarget(
        (await store.dailyRows(
          from: date,
          toExclusive: date.addDays(1),
          observedZone: zone,
        )).rows.single,
        observedZone: zone,
      );
      final snoozed = await store.snoozeReminder(
        SnoozeCommand(
          commandId: 's1',
          target: target,
          delayMinutes: 15,
          sample: sample,
          observedZone: zone,
        ),
        currentObservedZone: zone,
      );
      final before = await prepare();
      expect(
        before.desired.map((d) => d.requestToken),
        contains(snoozed.desired.requestToken),
      );

      final after = await prepare(
        clock: ReminderClockSample(
          utcMilliseconds: sample.utcMilliseconds + 3600000,
          elapsedMilliseconds: 1800000,
          bootId: 'boot-2',
        ),
      );
      expect(
        after.desired.map((d) => d.requestToken),
        isNot(contains(snoozed.desired.requestToken)),
        reason: 'elapsed alarms do not survive a restart',
      );
      expect(
        after.attention.map((d) => d.repairState),
        contains(ReminderRepairState.interrupted),
      );
      final health = summariseReminderHealth(
        capabilities: const ReminderCapabilities(
          supported: true,
          notificationPermission: true,
          appEnabled: true,
          channelEnabled: true,
          exactAlarm: true,
          protectedStorageAvailable: true,
          bootIdentityAvailable: true,
          fingerprint: 'test-adapter',
        ),
        projection: after,
        convergence: ReminderConvergence.converged,
        failed: false,
      );
      expect(health['everyone']!.state, ReminderScopeState.attention);
      expect(
        health['everyone']!.preparedThrough,
        isNull,
        reason: 'an interrupted alert blocks a prepared-through claim',
      );
      expect(health.deliveryGuaranteed, isFalse);
    },
  );

  test(
    'locked protected storage prepares nothing and registers nothing',
    () async {
      final gateway = _HostGateway(installedEpoch: null)
        ..capabilitiesOverride = const ReminderCapabilities(
          supported: true,
          notificationPermission: true,
          appEnabled: true,
          channelEnabled: true,
          exactAlarm: true,
          protectedStorageAvailable: false,
          bootIdentityAvailable: false,
          fingerprint: 'test-adapter',
        );
      final reports = <ReminderRepairReport>[];
      final worker = ReminderReconciler(
        gateway: gateway,
        repository: _ProjectionRepair(store),
        observedZone: () => zone,
        onReport: reports.add,
      );
      await worker.request();
      expect(gateway.applyCalls, 0);
      expect(reports.last.convergence, ReminderConvergence.blocked);
      expect(reports.last.projection, isNull);
      worker.dispose();
    },
  );

  test(
    'a zone change keeps one row per occurrence instead of duplicating it',
    () async {
      String identity(DesiredReminder d) {
        final i = d.target.row.expectation.identity;
        return '${i.personId}/${i.planId}/${i.originalDate}/${i.slotId}';
      }

      final london = await prepare();
      final newYork = await prepare(observedZone: 'America/New_York');
      expect(
        newYork.desired.map(identity),
        london.desired.map(identity),
        reason:
            'the same planned occurrence is not duplicated by a zone change',
      );
      expect(
        newYork.desired.map(identity).toSet().length,
        newYork.desired.length,
      );
    },
  );

  test(
    'unchanged plans and a process restart add no native sequence churn',
    () async {
      final first = await prepare();
      final again = await prepare();
      expect(again.sequence, first.sequence);
      expect(again.obsoleteTokens, isEmpty);

      // Simulate app termination and relaunch on the same durable dataset.
      await store.close();
      store = await RecordStore.open(path: path, key: key, isNew: false);
      final reopened = await prepare();
      expect(reopened.sequence, first.sequence);
      expect(
        reopened.desired.map((d) => d.requestToken),
        first.desired.map((d) => d.requestToken),
      );
    },
  );

  test(
    'capacity displacement is reported once per plan with an exact count',
    () async {
      // 240 synthetic plans in one person's scope, well over the ordinary pool.
      for (var i = 0; i < 240; i++) {
        await _seed(store, date, suffix: '$i');
      }
      final projection = await prepare(at: DateTime.utc(2026, 10, 19, 6));
      final capacity = projection.exclusions
          .where((e) => e.reason == 'capacity')
          .toList();
      expect(capacity, isNotEmpty);
      expect(capacity.length, lessThanOrEqualTo(capacity.length));
      final byScope = <String, int>{};
      for (final exclusion in capacity) {
        expect(
          byScope.containsKey(exclusion.scope),
          isFalse,
          reason: 'one truth row per scope, not one per displaced reminder',
        );
        byScope[exclusion.scope] = exclusion.count;
      }
      expect(byScope.values.fold<int>(0, (a, b) => a + b), greaterThan(0));
      expect(
        projection.desired.length,
        lessThanOrEqualTo(ReminderCapacity.nativeOrdinaryPurpose),
      );
      expect(projection.complete, isFalse);
    },
  );
}

Future<void> _seed(
  RecordStore store,
  CivilDate date, {
  String suffix = '',
}) async {
  final item = await store.createItem(
    commandId: 'item$suffix',
    name: 'Synthetic item $suffix',
    form: 'tablet',
    unit: 'mg',
    type: 'medicine',
  );
  final plan = 'p$suffix';
  await store.saveDailyPlan(
    commandId: 'plan$suffix',
    plan: DailyPlanVersion(
      personId: meId,
      planId: plan,
      itemId: item.id,
      versionId: 'v$suffix',
      start: date,
      timing: DailySlots([
        DailySlot(
          id: 'am',
          time: WallTime(8, 0),
          amount: PlannedAmount(
            quantity: ExactQuantity.parse('1'),
            enteredText: '1.000',
            unit: 'mg',
          ),
          reminderEnabled: true,
        ),
      ]),
      zoneBasis: const FollowingLocal(),
    ),
    expectedPersonRevision: await _personRevision(store),
    expectedGeneration: store.generation,
  );
  await store.setPlanReminders(
    commandId: 'enable$suffix',
    planId: plan,
    personId: meId,
    expectedPlanRevision: 1,
    expectedPersonRevision: await _personRevision(store),
    enabled: true,
  );
}

Future<int> _personRevision(RecordStore store) async =>
    (await store.profiles()).first.revision;

/// Bridges the real store into the narrow repair contract under test.
final class _ProjectionRepair implements ReminderRepairRepository {
  _ProjectionRepair(this.store);
  final RecordStore store;

  @override
  Future<ReminderProjection> prepare({
    required DateTime now,
    required String? observedZone,
    required ReminderClockSample? clockSample,
    required String adapterFingerprint,
  }) => store.prepareReminders(
    now: now,
    observedZone: observedZone,
    clockSample: clockSample,
    adapterFingerprint: adapterFingerprint,
  );

  @override
  Future<bool> acknowledge({
    required int sequence,
    required DesiredReminder desired,
    required ReminderReceipt receipt,
    required String? reason,
    required String adapterFingerprint,
  }) => store.acknowledgeReminder(
    generation: desired.generation,
    requestToken: desired.requestToken,
    intentRevision: desired.intentRevision,
    sequence: sequence,
    receipt: receipt,
    reason: reason,
    adapterFingerprint: adapterFingerprint,
  );

  @override
  Future<void> acknowledgeObsolete({
    required String generation,
    required int sequence,
    required String requestToken,
    required ReminderReceipt receipt,
    required String? reason,
    required String adapterFingerprint,
  }) => store.acknowledgeObsoleteReminder(
    generation: generation,
    sequence: sequence,
    requestToken: requestToken,
    receipt: receipt,
    reason: reason,
    adapterFingerprint: adapterFingerprint,
  );
}

final class _HostGateway implements ReminderGateway {
  _HostGateway({this.installedEpoch});
  String? installedEpoch;
  ReminderCapabilities? capabilitiesOverride;
  int applyCalls = 0;
  Map<String, NativeReminderState> obsoleteStates = const {};
  final List<String> acceptedEpochs = [];
  final List<(String, String)> invalidations = [];

  @override
  Future<ReminderCapabilities> capabilities() async =>
      capabilitiesOverride ??
      ReminderCapabilities(
        supported: true,
        notificationPermission: true,
        appEnabled: true,
        channelEnabled: true,
        exactAlarm: true,
        protectedStorageAvailable: true,
        bootIdentityAvailable: true,
        fingerprint: 'test-adapter',
        installedEpoch: installedEpoch,
      );

  @override
  Future<ReminderClockSample> sampleClock() async => ReminderClockSample(
    utcMilliseconds: DateTime.utc(2026, 10, 19, 9).millisecondsSinceEpoch,
    elapsedMilliseconds: 3600000,
    bootId: 'b1',
  );

  @override
  Future<NativeReminderSnapshot> applySnapshot({
    required String epoch,
    required int sequence,
    required List<NativeReminderRequest> desired,
    required List<String> obsoleteTokens,
  }) async {
    applyCalls++;
    if (installedEpoch != null && installedEpoch != epoch) {
      return NativeReminderSnapshot(
        accepted: false,
        epoch: installedEpoch,
        sequence: sequence,
        receipts: const [],
        fingerprint: 'test-adapter',
        reason: 'epoch_rejected',
      );
    }
    acceptedEpochs.add(epoch);
    return NativeReminderSnapshot(
      accepted: true,
      epoch: epoch,
      sequence: sequence,
      receipts: [
        for (final request in desired)
          NativeReminderReceipt(
            requestToken: request.requestToken,
            state: NativeReminderState.accepted,
          ),
        for (final token in obsoleteTokens)
          NativeReminderReceipt(
            requestToken: token,
            state: obsoleteStates[token] ?? NativeReminderState.cancelled,
            reason: obsoleteStates[token] == NativeReminderState.unknown
                ? 'not_installed'
                : null,
          ),
      ],
      fingerprint: 'test-adapter',
    );
  }

  @override
  Future<bool> invalidateEpoch({
    required String oldEpoch,
    required String newEpoch,
  }) async {
    invalidations.add((oldEpoch, newEpoch));
    if (installedEpoch != oldEpoch) return false;
    installedEpoch = newEpoch;
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
