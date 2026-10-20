import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:true_grit_vital/app/reminder_reconciler.dart';
import 'package:true_grit_vital/data/record_store.dart';
import 'package:true_grit_vital/platform/reminders.dart';

const _sample = ReminderClockSample(
  utcMilliseconds: 1792400400000,
  elapsedMilliseconds: 3600000,
  bootId: 'b1',
);

ReminderCapabilities _capabilities({String? installedEpoch}) =>
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

DesiredReminder _desired({
  String token = 'r1',
  String namespace = 'ns-new',
  ReminderRepairState state = ReminderRepairState.pending,
}) {
  final instant = _sample.utc;
  final row = DailyRow(
    generation: 'g1',
    personRevision: 1,
    planRevision: 1,
    personName: 'Ada',
    itemName: 'Synthetic',
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
      amount: PlannedAmount(quantity: ExactQuantity.parse('1'), unit: 'mg'),
      resolution: DailyResolution.exact,
      calculatorVersion: 'daily-v1',
      timezoneDataVersion: '2026',
      originalTime: WallTime(9, 0),
      effectiveTime: WallTime(9, 0),
      instant: instant,
      clockCandidates: [instant],
    ),
    actions: const [],
    takenCount: 0,
    skippedCount: 0,
  );
  return DesiredReminder(
    requestToken: token,
    takenToken: '$token-t',
    snoozeToken: '$token-s',
    skipToken: '$token-k',
    generation: 'g1',
    namespace: namespace,
    target: ReminderTarget(row: row, snoozeRevision: 0),
    kind: ReminderKind.ordinary,
    trigger: ReminderTrigger.wall,
    deadlineMilliseconds: instant.millisecondsSinceEpoch,
    intentRevision: 1,
    repairState: state,
  );
}

final class _Store implements ReminderRepairRepository {
  _Store({this.namespace = 'ns-new', List<String> obsolete = const []})
    : obsoleteTokens = [...obsolete];

  String namespace;
  int sequence = 7;
  final List<String> obsoleteTokens;
  final List<String> acknowledged = [];
  final List<(String, ReminderReceipt, String?)> obsoleteAcknowledged = [];
  bool conditional = true;

  /// Mutates the desired sequence once, on this 1-based prepare call.
  int mutateOnPrepareCall = 0;
  int prepareCalls = 0;

  @override
  Future<ReminderProjection> prepare({
    required DateTime now,
    required String? observedZone,
    required ReminderClockSample? clockSample,
    required String adapterFingerprint,
  }) async {
    prepareCalls++;
    if (prepareCalls == mutateOnPrepareCall) sequence++;
    return ReminderProjection(
      generation: 'g1',
      namespace: namespace,
      sequence: sequence,
      desired: [_desired(namespace: namespace)],
      obsoleteTokens: obsoleteTokens,
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
    acknowledged.add(receipt.name);
    return conditional;
  }

  @override
  Future<void> acknowledgeObsolete({
    required String generation,
    required int sequence,
    required String requestToken,
    required ReminderReceipt receipt,
    required String? reason,
    required String adapterFingerprint,
  }) async {
    obsoleteAcknowledged.add((requestToken, receipt, reason));
  }
}

final class _Gateway implements ReminderGateway {
  _Gateway({String? installedEpoch}) : installed = installedEpoch;

  String? installed;
  bool accept = true;
  bool invalidateResult = true;
  final List<String> appliedEpochs = [];
  final List<int> appliedSequences = [];
  final List<(String, String)> invalidations = [];
  Map<String, NativeReminderState> obsoleteStates = const {};
  Future<void> Function(int call)? beforeApply;

  @override
  Future<ReminderCapabilities> capabilities() async =>
      _capabilities(installedEpoch: installed);

  @override
  Future<ReminderClockSample> sampleClock() async => _sample;

  @override
  Future<NativeReminderSnapshot> applySnapshot({
    required String epoch,
    required int sequence,
    required List<NativeReminderRequest> desired,
    required List<String> obsoleteTokens,
  }) async {
    final call = appliedSequences.length;
    appliedSequences.add(sequence);
    appliedEpochs.add(epoch);
    await beforeApply?.call(call);
    return NativeReminderSnapshot(
      accepted: accept,
      epoch: accept ? epoch : null,
      sequence: sequence,
      fingerprint: 'test-adapter',
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
    );
  }

  @override
  Future<bool> invalidateEpoch({
    required String oldEpoch,
    required String newEpoch,
  }) async {
    invalidations.add((oldEpoch, newEpoch));
    if (invalidateResult) installed = newEpoch;
    return invalidateResult;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test(
    'restored dataset hands the previous epoch over before applying',
    () async {
      final store = _Store(namespace: 'ns-restored');
      final gateway = _Gateway(installedEpoch: 'ns-original');
      final reports = <ReminderRepairReport>[];
      final worker = ReminderReconciler(
        gateway: gateway,
        repository: store,
        observedZone: () => 'Europe/London',
        onReport: reports.add,
      );
      await worker.request();
      expect(gateway.invalidations, [('ns-original', 'ns-restored')]);
      expect(gateway.appliedEpochs, ['ns-restored']);
      expect(reports.last.epochRecovered, isTrue);
      expect(reports.last.convergence, ReminderConvergence.converged);
      expect(reports.last.passes, 1);
      worker.dispose();
    },
  );

  test(
    'a refused epoch handshake stays deferred instead of claiming repair',
    () async {
      final store = _Store(namespace: 'ns-restored');
      final gateway = _Gateway(installedEpoch: 'ns-original')
        ..invalidateResult = false;
      final reports = <ReminderRepairReport>[];
      final worker = ReminderReconciler(
        gateway: gateway,
        repository: store,
        observedZone: () => 'Europe/London',
        onReport: reports.add,
      );
      await worker.request();
      expect(
        gateway.invalidations.length,
        2,
        reason: 'bounded to the pass limit',
      );
      expect(reports.last.epochRecovered, isFalse);
      expect(reports.last.convergence, ReminderConvergence.deferred);
      expect(reports.last.passes, 2);
      worker.dispose();
    },
  );

  test('a matching epoch never sends an unnecessary invalidation', () async {
    final store = _Store(namespace: 'ns-new');
    final gateway = _Gateway(installedEpoch: 'ns-new');
    final worker = ReminderReconciler(
      gateway: gateway,
      repository: store,
      observedZone: () => 'Europe/London',
      onReport: (_) {},
    );
    await worker.request();
    expect(gateway.invalidations, isEmpty);
    expect(gateway.appliedSequences, [7]);
    worker.dispose();
  });

  test(
    'partial cancel failure is bounded and reported, never silently dropped',
    () async {
      final store = _Store(obsolete: ['old-a', 'old-b']);
      final gateway = _Gateway()
        ..obsoleteStates = {
          'old-a': NativeReminderState.cancelled,
          'old-b': NativeReminderState.failed,
        };
      final reports = <ReminderRepairReport>[];
      final worker = ReminderReconciler(
        gateway: gateway,
        repository: store,
        observedZone: () => 'Europe/London',
        onReport: reports.add,
      );
      await worker.request();
      expect(gateway.appliedSequences.length, 2);
      expect(reports.last.pendingCancellations, 1);
      expect(reports.last.convergence, ReminderConvergence.deferred);
      expect(
        store.obsoleteAcknowledged.map((a) => a.$1),
        ['old-a', 'old-a'],
        reason: 'the failed token keeps its durable intent for the next event',
      );
      worker.dispose();
    },
  );

  test(
    'a token the adapter never held is closed once with an uncertain receipt',
    () async {
      final store = _Store(obsolete: ['ghost']);
      final gateway = _Gateway()
        ..obsoleteStates = {'ghost': NativeReminderState.unknown};
      final reports = <ReminderRepairReport>[];
      final worker = ReminderReconciler(
        gateway: gateway,
        repository: store,
        observedZone: () => 'Europe/London',
        onReport: reports.add,
      );
      await worker.request();
      expect(store.obsoleteAcknowledged, [
        ('ghost', ReminderReceipt.postUncertain, 'not_installed'),
      ]);
      expect(gateway.appliedSequences.length, 1, reason: 'no retry livelock');
      expect(reports.last.convergence, ReminderConvergence.converged);
      worker.dispose();
    },
  );

  test(
    'an accepted snapshot that conflicts with the sequence is a failure',
    () async {
      final store = _Store();
      final gateway = _Gateway()..accept = false;
      final reports = <ReminderRepairReport>[];
      final worker = ReminderReconciler(
        gateway: gateway,
        repository: store,
        observedZone: () => 'Europe/London',
        onReport: reports.add,
      );
      await worker.request();
      expect(reports.last.convergence, ReminderConvergence.failed);
      expect(reports.last.failed, isTrue);
      expect(store.acknowledged.every((a) => a == 'unknown'), isTrue);
      worker.dispose();
    },
  );

  test(
    'a mutation during the final pass re-arms exactly one bounded flight',
    () async {
      // The second prepare is the post-registration coverage check in pass one,
      // so the desired state changes after the first snapshot was applied.
      final store = _Store()..mutateOnPrepareCall = 2;
      final gateway = _Gateway();
      final reports = <ReminderRepairReport>[];
      late ReminderReconciler worker;
      var requested = false;
      gateway.beforeApply = (call) async {
        if (call == 1 && !requested) {
          requested = true;
          worker.request(revision: 2);
        }
      };
      worker = ReminderReconciler(
        gateway: gateway,
        repository: store,
        observedZone: () => 'Europe/London',
        onReport: reports.add,
      );
      await worker.request(revision: 1);
      // The follow-up flight starts after the first flight completes.
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(gateway.appliedSequences.length, 3);
      expect(reports.last.revision, 2);
      expect(reports.last.convergence, ReminderConvergence.converged);
      worker.dispose();
    },
  );

  test('a superseded request cannot win after disposal', () async {
    final store = _Store();
    final gateway = _Gateway();
    final gate = Completer<void>();
    gateway.beforeApply = (_) => gate.future;
    final worker = ReminderReconciler(
      gateway: gateway,
      repository: store,
      observedZone: () => 'Europe/London',
      onReport: (_) {},
    );
    final flight = worker.request(revision: 1);
    await Future<void>.delayed(Duration.zero);
    worker.request(revision: 2);
    worker.dispose();
    gate.complete();
    await flight;
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(gateway.appliedSequences.length, 1);
    expect(store.acknowledged, isEmpty);
  });
}
