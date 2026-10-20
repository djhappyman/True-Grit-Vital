import 'package:flutter_test/flutter_test.dart';
import 'package:true_grit_vital/app/reminder_health.dart';
import 'package:true_grit_vital/app/reminder_reconciler.dart'
    show ReminderConvergence;
import 'package:true_grit_vital/data/record_store.dart';
import 'package:true_grit_vital/platform/reminders.dart';

ReminderCapabilities capabilities({
  bool supported = true,
  bool permission = true,
  bool appEnabled = true,
  bool channelEnabled = true,
  bool exactAlarm = true,
  bool storage = true,
  bool boot = true,
  String? installedEpoch,
}) => ReminderCapabilities(
  supported: supported,
  notificationPermission: permission,
  appEnabled: appEnabled,
  channelEnabled: channelEnabled,
  exactAlarm: exactAlarm,
  protectedStorageAvailable: storage,
  bootIdentityAvailable: boot,
  fingerprint: 'test-adapter',
  installedEpoch: installedEpoch,
);

DesiredReminder desired({
  String person = 'ada',
  String plan = 'p1',
  ReminderRepairState state = ReminderRepairState.prepared,
  ReminderKind kind = ReminderKind.ordinary,
}) {
  final instant = DateTime.utc(2026, 10, 19, 9);
  final row = DailyRow(
    generation: 'g1',
    personRevision: 1,
    planRevision: 1,
    personName: person,
    itemName: 'Synthetic',
    revision: 0,
    expectation: DailyExpectation(
      identity: DailyIdentity(
        personId: person,
        planId: plan,
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
    requestToken: '$person-$plan-${kind.name}',
    takenToken: 't',
    snoozeToken: 's',
    skipToken: 'k',
    generation: 'g1',
    namespace: 'ns1',
    target: ReminderTarget(row: row, snoozeRevision: 0),
    kind: kind,
    trigger: ReminderTrigger.wall,
    deadlineMilliseconds: instant.millisecondsSinceEpoch,
    intentRevision: 1,
    repairState: state,
  );
}

ReminderProjection projectionFor({
  required Iterable<ReminderCoverage> coverage,
  Iterable<DesiredReminder> desiredReminders = const [],
  Iterable<EventEndReminder> eventEnds = const [],
  Iterable<ReminderExclusion> exclusions = const [],
  Iterable<DesiredReminder> attention = const [],
  bool complete = true,
}) => ReminderProjection(
  generation: 'g1',
  namespace: 'ns1',
  sequence: 3,
  desired: desiredReminders,
  obsoleteTokens: const [],
  complete: complete,
  coverage: coverage,
  eventEnds: eventEnds,
  exclusions: exclusions,
  attention: attention,
);

ReminderCoverage coverage(
  String scope, {
  bool complete = true,
  DateTime? through,
  String? reason,
}) => ReminderCoverage(
  scope: scope,
  generation: 'g1',
  basis: 'Europe/London',
  adapterFingerprint: 'test-adapter',
  checkedAt: DateTime.utc(2026, 10, 19, 8),
  complete: complete,
  preparedThrough: through,
  reason: reason,
);

void main() {
  group('capability blockers', () {
    test('healthy adapter has no blockers in repair priority order', () {
      expect(reminderBlockers(capabilities()), isEmpty);
      expect(
        summariseReminderHealth(
          capabilities: capabilities(),
          projection: null,
          convergence: ReminderConvergence.converged,
          failed: false,
        ).blocked,
        isFalse,
      );
    });

    test('protected storage and unsupported hosts come first', () {
      expect(
        reminderBlockers(capabilities(storage: false, exactAlarm: false)),
        [ReminderBlocker.protectedStorage, ReminderBlocker.exactAlarm],
      );
      expect(
        reminderBlockers(
          capabilities(supported: false, permission: false, boot: false),
        ),
        [
          ReminderBlocker.unsupportedHost,
          ReminderBlocker.notificationPermission,
          ReminderBlocker.bootIdentity,
        ],
      );
    });

    test('blocked host never claims prepared scope coverage', () {
      final health = summariseReminderHealth(
        capabilities: capabilities(storage: false),
        projection: projectionFor(
          coverage: [coverage('everyone', through: DateTime.utc(2026, 10, 20))],
          desiredReminders: [desired()],
        ),
        convergence: ReminderConvergence.blocked,
        failed: false,
      );
      expect(health.blocked, isTrue);
      expect(health.scopes.single.state, ReminderScopeState.blocked);
      expect(health.scopes.single.prepared, isFalse);
      expect(health.needsAttention, isTrue);
    });
  });

  group('truthful scope state', () {
    for (final scenario in [
      'failed',
      'deferred',
      'permission',
      'uncertain cancellation',
    ]) {
      test('$scenario cannot retain a stale prepared-through claim', () {
        final health = summariseReminderHealth(
          capabilities: capabilities(permission: scenario != 'permission'),
          projection: projectionFor(
            coverage: [
              coverage('everyone', through: DateTime.utc(2026, 10, 20)),
            ],
          ),
          convergence: scenario == 'deferred'
              ? ReminderConvergence.deferred
              : ReminderConvergence.converged,
          failed: scenario == 'failed',
          unconfirmedCancellations: scenario == 'uncertain cancellation'
              ? 1
              : 0,
        );
        expect(health.scopes.single.preparedThrough, isNull);
        expect(health.scopes.single.complete, isFalse);
        expect(health.needsAttention, isTrue);
      });
    }
    test('complete coverage is the only ready state', () {
      final ready = summariseReminderHealth(
        capabilities: capabilities(),
        projection: projectionFor(
          coverage: [coverage('everyone', through: DateTime.utc(2026, 10, 20))],
          desiredReminders: [desired()],
        ),
        convergence: ReminderConvergence.converged,
        failed: false,
      );
      expect(ready.scopes.single.state, ReminderScopeState.ready);
      expect(ready.deliveryGuaranteed, isFalse);
      expect(ready.needsAttention, isFalse);

      final partial = summariseReminderHealth(
        capabilities: capabilities(),
        projection: projectionFor(
          coverage: [coverage('everyone')],
          complete: false,
        ),
        convergence: ReminderConvergence.deferred,
        failed: false,
      );
      expect(partial.scopes.single.state, ReminderScopeState.partial);
      expect(partial.needsAttention, isTrue);
    });

    test('capacity exclusion defers only its own scope', () {
      final health = summariseReminderHealth(
        capabilities: capabilities(),
        projection: projectionFor(
          coverage: [
            coverage('everyone', through: DateTime.utc(2026, 10, 20)),
            coverage('plan:p1', through: DateTime.utc(2026, 10, 20)),
            coverage('plan:p2', through: DateTime.utc(2026, 10, 20)),
          ],
          desiredReminders: [desired()],
          exclusions: const [
            ReminderExclusion(scope: 'plan:p2', reason: 'capacity', count: 3),
          ],
          complete: false,
        ),
        convergence: ReminderConvergence.deferred,
        failed: false,
      );
      expect(health['plan:p2']!.state, ReminderScopeState.deferred);
      expect(health['plan:p2']!.deferred, 3);
      expect(health['plan:p2']!.complete, isFalse);
      // A global capacity shortfall makes every scope untrusted, but the
      // displaced count is attributed only to the plan that lost its place.
      expect(health['plan:p1']!.state, ReminderScopeState.partial);
      expect(health['plan:p1']!.deferred, 0);
      expect(health.capacity.deferred, 3);
    });

    test('a restart review is attention, not readiness', () {
      final health = summariseReminderHealth(
        capabilities: capabilities(),
        projection: projectionFor(
          coverage: [coverage('everyone', through: DateTime.utc(2026, 10, 20))],
          desiredReminders: [
            desired(state: ReminderRepairState.prepared),
            desired(plan: 'p2', state: ReminderRepairState.interrupted),
          ],
          attention: [
            desired(plan: 'p2', state: ReminderRepairState.interrupted),
          ],
        ),
        convergence: ReminderConvergence.converged,
        failed: false,
      );
      expect(health['everyone']!.state, ReminderScopeState.attention);
      expect(health.needsAttention, isTrue);
      expect(
        health.limitations,
        contains(ReminderLimitation.deviceRestartElapsedSnooze),
      );
    });
  });

  group('capacity accounting', () {
    test('limits stay in step with the native snapshot bounds', () {
      expect(ReminderCapacity.ordinary, 232);
      expect(ReminderCapacity.snoozes, 16);
      expect(ReminderCapacity.eventEnds, 8);
      expect(ReminderCapacity.nativeOrdinaryPurpose, 248);
      expect(ReminderCapacity.nativeTotal, 256);
    });

    test('use counts reserved pools separately from ordinary requests', () {
      final use = reminderCapacityUse(
        projectionFor(
          coverage: [coverage('everyone')],
          desiredReminders: [
            desired(),
            desired(person: 'bea', plan: 'p2'),
            desired(person: 'bea', plan: 'p3', kind: ReminderKind.snooze),
          ],
        ),
      );
      expect(use.ordinary, 2);
      expect(use.snoozes, 1);
      expect(use.deferred, 0);
      expect(use.ordinaryFull, isFalse);
    });

    test('deferred total is unduplicated across emitted scopes', () {
      final use = reminderCapacityUse(
        projectionFor(
          coverage: [coverage('everyone')],
          exclusions: const [
            ReminderExclusion(scope: 'plan:p1', reason: 'capacity', count: 2),
            ReminderExclusion(scope: 'event:e1', reason: 'capacity', count: 1),
            ReminderExclusion(scope: 'plan:p2', reason: 'untimed', count: 4),
          ],
        ),
      );
      expect(use.deferred, 3);
      expect(use.prepared, 0);
    });
  });

  group('limitations', () {
    test('delivery is never promised and bounds are always disclosed', () {
      final health = summariseReminderHealth(
        capabilities: capabilities(),
        projection: projectionFor(
          coverage: [coverage('everyone', through: DateTime.utc(2026, 10, 20))],
          desiredReminders: [desired()],
        ),
        convergence: ReminderConvergence.converged,
        failed: false,
      );
      expect(
        health.limitations.first,
        ReminderLimitation.deliveryNotGuaranteed,
      );
      expect(
        health.limitations,
        containsAll([
          ReminderLimitation.preparedWindowBounded,
          ReminderLimitation.forceStopAndBatteryLimits,
          ReminderLimitation.capacityFinite,
          ReminderLimitation.noBackgroundReplenishment,
        ]),
      );
      expect(health.deliveryGuaranteed, isFalse);
    });

    test('no projection makes no coverage claim', () {
      final health = summariseReminderHealth(
        capabilities: capabilities(),
        projection: null,
        convergence: ReminderConvergence.deferred,
        failed: false,
      );
      expect(health.scopes, isEmpty);
      expect(health.capacity.prepared, 0);
      expect(
        health.limitations,
        isNot(contains(ReminderLimitation.preparedWindowBounded)),
      );
      expect(health.needsAttention, isTrue);
    });

    test('an untouched surface claims nothing before the first pass', () {
      final initial = summariseReminderHealth(
        capabilities: null,
        projection: null,
        convergence: ReminderConvergence.deferred,
        failed: false,
      );
      expect(initial.attempted, isFalse);
      expect(initial.needsAttention, isFalse);
      expect(initial.scopes, isEmpty);
      expect(initial.blockers, isEmpty);
    });

    test('pending cancellations keep the summary honest', () {
      final health = summariseReminderHealth(
        capabilities: capabilities(),
        projection: projectionFor(
          coverage: [coverage('everyone', through: DateTime.utc(2026, 10, 20))],
          desiredReminders: [desired()],
        ),
        convergence: ReminderConvergence.deferred,
        failed: false,
        pendingCancellations: 2,
        unconfirmedCancellations: 1,
      );
      expect(health.pendingCancellations, 2);
      expect(health.unconfirmedCancellations, 1);
      expect(health.needsAttention, isTrue);
    });
  });
}
