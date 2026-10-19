import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:true_grit_vital/app/reminder_reconciler.dart';
import 'package:true_grit_vital/data/record_store.dart';
import 'package:true_grit_vital/platform/reminders.dart';

const testCapabilities = ReminderCapabilities(
  supported: true,
  notificationPermission: true,
  appEnabled: true,
  channelEnabled: true,
  exactAlarm: true,
  protectedStorageAvailable: true,
  bootIdentityAvailable: true,
  fingerprint: 'test-adapter',
);
const sample = ReminderClockSample(
  utcMilliseconds: 1792400400000,
  elapsedMilliseconds: 3600000,
  bootId: 'b1',
);

DesiredReminder request() {
  final row = DailyRow(
    generation: 'g1',
    personRevision: 1,
    planRevision: 1,
    personName: 'Ada',
    itemName: 'Original substance',
    revision: 0,
    expectation: DailyExpectation(
      identity: DailyIdentity(
        personId: 'ada',
        planId: 'p1',
        originalDate: CivilDate(2026, 10, 19),
        slotId: 'am',
      ),
      itemId: 'i1',
      versionId: 'v1',
      zoneId: 'Europe/London',
      amount: PlannedAmount(quantity: ExactQuantity.parse('1.25'), unit: 'mg'),
      resolution: DailyResolution.exact,
      calculatorVersion: 'daily-v1',
      timezoneDataVersion: '2026',
      originalTime: WallTime(9, 0),
      effectiveTime: WallTime(9, 0),
      instant: sample.utc,
      clockCandidates: [sample.utc],
    ),
    actions: const [],
    takenCount: 0,
    skippedCount: 0,
  );
  return DesiredReminder(
    requestToken: 'r1',
    takenToken: 't1',
    snoozeToken: 's1',
    skipToken: 'k1',
    generation: 'g1',
    namespace: 'ns1',
    target: ReminderTarget(row: row, snoozeRevision: 0),
    kind: ReminderKind.ordinary,
    trigger: ReminderTrigger.wall,
    deadlineMilliseconds: sample.utcMilliseconds,
    intentRevision: 1,
    repairState: ReminderRepairState.pending,
  );
}

class RepairStore implements ReminderRepairRepository {
  final desired = request();
  final acknowledgements = <ReminderReceipt>[];
  bool conditional = true;
  int preparations = 0;
  @override
  Future<void> acknowledgeObsolete({
    required String generation,
    required int sequence,
    required String requestToken,
    required ReminderReceipt receipt,
    required String? reason,
    required String adapterFingerprint,
  }) async {}
  @override
  Future<ReminderProjection> prepare({
    required DateTime now,
    required String? observedZone,
    required ReminderClockSample? clockSample,
    required String adapterFingerprint,
  }) async {
    preparations++;
    return ReminderProjection(
      generation: 'g1',
      namespace: 'ns1',
      sequence: 1,
      desired: [desired],
      obsoleteTokens: const ['old'],
      complete: true,
      coverage: const [],
    );
  }

  @override
  Future<bool> acknowledge({
    required int sequence,
    required DesiredReminder desired,
    required ReminderReceipt receipt,
    required String? reason,
    required String adapterFingerprint,
  }) async {
    acknowledgements.add(receipt);
    return conditional;
  }
}

class RepairGateway implements ReminderGateway {
  int calls = 0, inFlight = 0, maximumInFlight = 0;
  NativeReminderState receipt = NativeReminderState.accepted;
  Completer<NativeReminderSnapshot>? delayed;
  bool accepted = true, permission = true;
  @override
  Future<ReminderCapabilities> capabilities() async => testCapabilities;
  @override
  Future<ReminderClockSample> sampleClock() async => sample;
  @override
  Future<NativeReminderSnapshot> applySnapshot({
    required String epoch,
    required int sequence,
    required List<NativeReminderRequest> desired,
    required List<String> obsoleteTokens,
  }) async {
    calls++;
    inFlight++;
    if (inFlight > maximumInFlight) maximumInFlight = inFlight;
    expect(desired.single.requestToken, 'r1');
    expect(obsoleteTokens, ['old']);
    try {
      if (delayed != null) return await delayed!.future;
      return NativeReminderSnapshot(
        accepted: accepted,
        epoch: epoch,
        sequence: sequence,
        receipts: [NativeReminderReceipt(requestToken: 'r1', state: receipt)],
        fingerprint: 'test-adapter',
      );
    } finally {
      inFlight--;
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class EventRepairStore extends RepairStore
    implements EventEndReminderRepairRepository {
  final event = const EventEndReminder(
    requestToken: 'end',
    takenToken: 'end-t',
    snoozeToken: 'end-s',
    skipToken: 'end-k',
    generation: 'g1',
    namespace: 'ns1',
    eventId: 'e',
    personId: 'p',
    eventRevision: 2,
    personRevision: 1,
    deadlineMilliseconds: 1792486800000,
    repairState: ReminderRepairState.pending,
  );
  final eventReceipts = <ReminderReceipt>[];
  @override
  Future<ReminderProjection> prepare({
    required DateTime now,
    required String? observedZone,
    required ReminderClockSample? clockSample,
    required String adapterFingerprint,
  }) async => ReminderProjection(
    generation: 'g1',
    namespace: 'ns1',
    sequence: 1,
    desired: const [],
    eventEnds: [event],
    obsoleteTokens: const [],
    complete: true,
    coverage: const [],
  );
  @override
  Future<bool> acknowledgeEventEnd({
    required int sequence,
    required EventEndReminder desired,
    required ReminderReceipt receipt,
    required String? reason,
    required String adapterFingerprint,
  }) async {
    eventReceipts.add(receipt);
    return true;
  }
}

class EventRepairGateway extends RepairGateway {
  bool includeReceipt = true;
  @override
  Future<NativeReminderSnapshot> applySnapshot({
    required String epoch,
    required int sequence,
    required List<NativeReminderRequest> desired,
    required List<String> obsoleteTokens,
  }) async {
    expect(desired.single.purpose, NativeReminderPurpose.eventEnd);
    expect(desired.single.clock, ReminderNativeClock.wall);
    expect(desired.single.toMap()['purpose'], 'eventEnd');
    return NativeReminderSnapshot(
      accepted: true,
      epoch: epoch,
      sequence: sequence,
      receipts: [
        if (includeReceipt)
          const NativeReminderReceipt(
            requestToken: 'end',
            state: NativeReminderState.accepted,
          ),
      ],
      fingerprint: 'test-adapter',
    );
  }
}

void main() {
  test(
    'event review native request is typed and missing receipt remains unknown',
    () async {
      for (final includeReceipt in [true, false]) {
        final store = EventRepairStore(),
            gateway = EventRepairGateway()..includeReceipt = includeReceipt;
        final worker = ReminderReconciler(
          gateway: gateway,
          repository: store,
          observedZone: () => 'Europe/London',
          onReport: (_) {},
        );
        await worker.request();
        expect(
          store.eventReceipts.single,
          includeReceipt ? ReminderReceipt.accepted : ReminderReceipt.unknown,
        );
        expect(store.acknowledgements, isEmpty);
        worker.dispose();
      }
    },
  );
  test(
    'terminal native receipts synchronize without becoming registrations',
    () async {
      for (final terminal in [
        NativeReminderState.consumed,
        NativeReminderState.cancelled,
        NativeReminderState.postUncertain,
      ]) {
        final store = RepairStore(),
            gateway = RepairGateway()..receipt = terminal;
        final worker = ReminderReconciler(
          gateway: gateway,
          repository: store,
          observedZone: () => 'Europe/London',
          onReport: (_) {},
        );
        await worker.request();
        expect(store.acknowledgements.single.name, terminal.name);
        expect(gateway.calls, 1);
        worker.dispose();
      }
    },
  );
  test(
    'timeout is unknown and a late result cannot acknowledge preparation',
    () async {
      final store = RepairStore(),
          gateway = RepairGateway()..delayed = Completer();
      final worker = ReminderReconciler(
        gateway: gateway,
        repository: store,
        observedZone: () => 'Europe/London',
        onReport: (_) {},
        callTimeout: const Duration(milliseconds: 10),
      );
      await worker.request();
      expect(store.acknowledgements, [ReminderReceipt.unknown]);
      gateway.delayed!.complete(
        const NativeReminderSnapshot(
          accepted: true,
          epoch: 'ns1',
          sequence: 1,
          receipts: [
            NativeReminderReceipt(
              requestToken: 'r1',
              state: NativeReminderState.accepted,
            ),
          ],
          fingerprint: 'test-adapter',
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(store.acknowledgements, [ReminderReceipt.unknown]);
      worker.dispose();
    },
  );
  test(
    'stale fence is unknown and stale acknowledgements have a two-pass bound',
    () async {
      final store = RepairStore()..conditional = false,
          gateway = RepairGateway()..accepted = false;
      final worker = ReminderReconciler(
        gateway: gateway,
        repository: store,
        observedZone: () => 'Europe/London',
        onReport: (_) {},
      );
      await worker.request();
      expect(gateway.calls, 2);
      expect(store.acknowledgements, [
        ReminderReceipt.unknown,
        ReminderReceipt.unknown,
      ]);
      worker.dispose();
    },
  );
  test(
    'events coalesce and disposal rejects delayed acknowledgements',
    () async {
      final store = RepairStore(),
          gateway = RepairGateway()..delayed = Completer();
      final worker = ReminderReconciler(
        gateway: gateway,
        repository: store,
        observedZone: () => 'Europe/London',
        onReport: (_) {},
      );
      final flight = worker.request();
      await Future<void>.delayed(Duration.zero);
      worker.request();
      worker.request();
      worker.dispose();
      gateway.delayed!.complete(
        const NativeReminderSnapshot(
          accepted: true,
          epoch: 'ns1',
          sequence: 1,
          receipts: [],
          fingerprint: 'test-adapter',
        ),
      );
      await flight;
      expect(gateway.calls, 1);
      expect(store.acknowledgements, isEmpty);
      expect(gateway.maximumInFlight, 1);
    },
  );
}
