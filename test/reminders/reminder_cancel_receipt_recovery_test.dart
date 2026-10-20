import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:true_grit_vital/app/reminder_reconciler.dart';
import 'package:true_grit_vital/data/record_store.dart';
import 'package:true_grit_vital/platform/reminders.dart';

/// Cancel-receipt recovery under real protected SQLite with a fake adapter at
/// the shared repair boundary. A native receipt that confirms a desired
/// request is no longer registered must complete the durable intent instead of
/// stranding an active cancel row that no work or obsolete list reaches again.
void main() {
  late Directory dir;
  late RecordStore store;
  late String path;
  final key = List.generate(32, (i) => i + 1);
  final zone = 'Europe/London';

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('vital-t08-cancel-');
    path = '${dir.path}/records.db';
    store = await RecordStore.open(path: path, key: key, isNew: true);
    await seed(store);
  });

  tearDown(() async {
    await store.close();
    await dir.delete(recursive: true);
  });

  Future<ReminderProjection> prepare(DateTime at) => store.prepareReminders(
    now: at,
    observedZone: zone,
    clockSample: null,
    adapterFingerprint: 'test-adapter',
  );

  /// The one live request for the 19 October morning occurrence, with its
  /// durable intent revision from the observed projection.
  Future<(ReminderProjection, DesiredReminder)> morning(DateTime at) async {
    final p = await prepare(at);
    final matches = p.desired
        .where(
          (d) =>
              d.target.row.expectation.identity.originalDate ==
                  CivilDate(2026, 10, 19) &&
              d.target.row.expectation.identity.slotId == 'am',
        )
        .toList();
    expect(matches, hasLength(1), reason: 'one live request per occurrence');
    return (p, matches.single);
  }

  test('a cancelled receipt completes the live intent and keeps reconciliation stable', () async {
    final (_, occurrence) = await morning(DateTime.utc(2026, 10, 19, 6));
    final observation = await prepare(DateTime.utc(2026, 10, 19, 6, 30));
    expect(
      await store.acknowledgeReminder(
        generation: store.generation,
        requestToken: occurrence.requestToken,
        intentRevision: occurrence.intentRevision,
        sequence: observation.sequence,
        receipt: ReminderReceipt.accepted,
        adapterFingerprint: 'test-adapter',
      ),
      isTrue,
    );
    await store.close();
    expect(_row(path, key, occurrence.requestToken)['active'], 1);

    store = await RecordStore.open(path: path, key: key, isNew: false);
    final again = await prepare(DateTime.utc(2026, 10, 19, 6, 45));
    expect(
      await store.acknowledgeReminder(
        generation: store.generation,
        requestToken: occurrence.requestToken,
        intentRevision: occurrence.intentRevision,
        sequence: again.sequence,
        receipt: ReminderReceipt.cancelled,
        reason: 'native_cancelled',
        adapterFingerprint: 'test-adapter',
      ),
      isTrue,
    );
    await store.close();
    final ended = _row(path, key, occurrence.requestToken);
    expect(ended['state'], 'cancelled');
    expect(
      ended['active'],
      0,
      reason: 'the ended intent must not hold the bucket',
    );
    expect(
      ended['cancel_ack'],
      1,
      reason: 'the receipt evidenced the end once',
    );

    store = await RecordStore.open(path: path, key: key, isNew: false);
    final next = await prepare(DateTime.utc(2026, 10, 19, 6, 50));
    expect(
      next.desired.map((d) => d.requestToken),
      isNot(contains(occurrence.requestToken)),
      reason: 'completed intents never re-arm from their own strand',
    );
    expect(next.obsoleteTokens, isNot(contains(occurrence.requestToken)));
    expect(
      next.desired.where(
        (d) =>
            d.target.row.expectation.identity.originalDate ==
                CivilDate(2026, 10, 19) &&
            d.target.row.expectation.identity.slotId == 'am',
      ),
      isEmpty,
      reason: 'the dismissed occurrence does not register a replacement alert',
    );
    expect(
      next.desired,
      isNotEmpty,
      reason: 'later occurrences keep their work',
    );
  });

  test(
    'stranded active cancel rows from an earlier write shape are repaired once',
    () async {
      final (first, occurrence) = await morning(DateTime.utc(2026, 10, 19, 6));
      expect(
        await store.acknowledgeReminder(
          generation: store.generation,
          requestToken: occurrence.requestToken,
          intentRevision: occurrence.intentRevision,
          sequence: first.sequence,
          receipt: ReminderReceipt.cancelled,
          adapterFingerprint: 'test-adapter',
        ),
        isTrue,
      );
      // Reproduce the shape the previous durable write could leave behind.
      final raw = _db(path, key);
      raw.execute(
        "UPDATE reminder_request SET active=1,cancel_ack=0,state='cancelled' WHERE token=?",
        [occurrence.requestToken],
      );
      raw.close();
      expect(_row(path, key, occurrence.requestToken)['active'], 1);

      await prepare(DateTime.utc(2026, 10, 19, 6, 45));
      final repaired = _row(path, key, occurrence.requestToken);
      expect(repaired['state'], 'cancelled');
      expect(repaired['active'], 0);
      expect(repaired['cancel_ack'], 1);

      final next = await prepare(DateTime.utc(2026, 10, 19, 6, 50));
      expect(next.obsoleteTokens, isNot(contains(occurrence.requestToken)));
      expect(
        next.exclusions.any(
          (e) => e.scope == 'plan:p1' && e.reason == 'capacity',
        ),
        isFalse,
      );
    },
  );

  test('a fake-adapter repair flight converges when the device ends a desired request', () async {
    final gateway = _CancelFlightGateway();
    final reports = <ReminderRepairReport>[];
    final worker = ReminderReconciler(
      gateway: gateway,
      repository: _StoreBoundRepair(store),
      observedZone: () => zone,
      onReport: reports.add,
    );
    await worker.request();
    expect(reports.last.convergence, ReminderConvergence.converged);
    // The device-cancelled token left the desired set with one bounded
    // churn step and never returns to it.
    expect(gateway.appliedSequences.length, 2);
    expect(gateway.appliedSequences[1], gateway.appliedSequences[0] + 1);
    final settled = await prepare(DateTime.utc(2026, 10, 19, 6, 50));
    expect(
      settled.desired.map((d) => d.requestToken),
      isNot(contains(gateway.deviceCancelledToken)),
    );
    expect(reports.last.pendingCancellations, 0);
    worker.dispose();
  });
}

Future<void> seed(RecordStore store) async {
  final item = await store.createItem(
    commandId: 'item',
    name: 'Synthetic item',
    form: 'tablet',
    unit: 'mg',
    type: 'medicine',
  );
  await store.saveDailyPlan(
    commandId: 'plan-save',
    plan: DailyPlanVersion(
      personId: meId,
      planId: 'p1',
      itemId: item.id,
      versionId: 'v1',
      start: CivilDate(2026, 10, 19).addDays(-1),
      zoneBasis: const FollowingLocal(),
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
    ),
    expectedPersonRevision: (await store.profiles()).first.revision,
    expectedGeneration: store.generation,
  );
  await store.setPlanReminders(
    commandId: 'enable',
    planId: 'p1',
    personId: meId,
    expectedPlanRevision: 1,
    expectedPersonRevision: (await store.profiles()).first.revision,
    enabled: true,
  );
}

Database _db(String path, List<int> key) {
  final raw = sqlite3.open(path);
  raw.execute("PRAGMA cipher='chacha20'");
  raw.execute(
    'PRAGMA key="x\'${key.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}\'"',
  );
  return raw;
}

Map<String, Object?> _row(String path, List<int> key, String token) {
  final raw = _db(path, key);
  final out = Map<String, Object?>.from(
    raw.select(
      'SELECT token,state,reason,active,cancel_ack FROM reminder_request WHERE token=?',
      [token],
    ).single,
  );
  raw.close();
  return out;
}

final class _StoreBoundRepair implements ReminderRepairRepository {
  _StoreBoundRepair(this.store);
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

/// Fake adapter: the device accepts the flight but ends exactly one desired
/// request instead of registering it (it decided that occurrence is over).
final class _CancelFlightGateway implements ReminderGateway {
  final appliedSequences = <int>[];
  String? deviceCancelledToken;

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
        fingerprint: 'test-adapter',
      );

  @override
  Future<ReminderClockSample> sampleClock() async => ReminderClockSample(
    utcMilliseconds: DateTime.utc(2026, 10, 19, 6, 50).millisecondsSinceEpoch,
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
    appliedSequences.add(sequence);
    // First flight: the device ends one desired request instead of
    // registering it; later flights confirm that token stays ended.
    deviceCancelledToken ??= desired.isEmpty
        ? null
        : desired.first.requestToken;
    return NativeReminderSnapshot(
      accepted: true,
      epoch: epoch,
      sequence: sequence,
      receipts: [
        for (final request in desired)
          NativeReminderReceipt(
            requestToken: request.requestToken,
            state: deviceCancelledToken == request.requestToken
                ? NativeReminderState.cancelled
                : NativeReminderState.accepted,
          ),
      ],
      fingerprint: 'test-adapter',
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
