import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/reminders/reminders.dart';
import '../platform/reminders.dart';
import 'reminder_reconciler.dart' show ReminderConvergence;
import 'reminders.dart' show remindersProvider;

/// Why reminder preparation cannot be trusted in the current scope.
///
/// Order is the repair priority shown to the person: capability gates first,
/// then device identity, because a missing clock prevents safe Snooze.
enum ReminderBlocker {
  unsupportedHost,
  protectedStorage,
  notificationPermission,
  appDisabled,
  channelDisabled,
  exactAlarm,
  bootIdentity,
}

/// Truthful state of one prepared-through scope. It never means delivered.
enum ReminderScopeState {
  /// Every eligible reminder in this scope through the stated point is prepared.
  ready,

  /// Capacity stopped some eligible reminders in this scope.
  deferred,

  /// A prepared reminder needs review, for example after a device restart.
  attention,

  /// Preparation ran but coverage is incomplete for another stated reason.
  partial,

  /// A capability gate blocks preparation for every scope.
  blocked,
}

/// A limitation that must stay visible beside any health claim.
enum ReminderLimitation {
  deliveryNotGuaranteed,
  preparedWindowBounded,
  deviceRestartElapsedSnooze,
  forceStopAndBatteryLimits,
  capacityFinite,
  noBackgroundReplenishment,
}

/// Finite capacity use for one projection. Snooze and event-notice pools are
/// reserved, so an exhausted ordinary queue cannot starve either.
final class ReminderCapacityUse {
  const ReminderCapacityUse({
    this.ordinary = 0,
    this.snoozes = 0,
    this.eventEnds = 0,
    this.stockNotices = 0,
    this.deferred = 0,
  });

  final int ordinary, snoozes, eventEnds, stockNotices, deferred;

  bool get ordinaryFull => ordinary >= ReminderCapacity.ordinary;
  bool get snoozesFull => snoozes >= ReminderCapacity.snoozes;
  bool get eventEndsFull => eventEnds >= ReminderCapacity.eventEnds;
  bool get stockNoticesFull => stockNotices >= ReminderCapacity.stockNotices;
  bool get exhausted =>
      ordinaryFull || snoozesFull || eventEndsFull || stockNoticesFull;

  int get prepared => ordinary + snoozes + eventEnds + stockNotices;
}

final class ReminderScopeHealth {
  const ReminderScopeHealth({
    required this.scope,
    required this.state,
    required this.complete,
    required this.deferred,
    required this.attention,
    required this.reason,
    this.preparedThrough,
    this.checkedAt,
    this.basis,
  });

  final String scope;
  final ReminderScopeState state;
  final bool complete;
  final int deferred, attention;
  final String? reason;
  final DateTime? preparedThrough, checkedAt;
  final String? basis;

  bool get prepared =>
      preparedThrough != null && state == ReminderScopeState.ready;
}

/// Everything the reminder health surface may claim, derived from the last
/// bounded repair pass. Unsupported or blocked scopes stay explicit.
final class ReminderHealthSummary {
  const ReminderHealthSummary({
    required this.convergence,
    required this.blockers,
    required this.scopes,
    required this.capacity,
    required this.limitations,
    required this.checkedAt,
    required this.unconfirmedCancellations,
    required this.pendingCancellations,
    required this.failed,
    required this.attempted,
  });

  final ReminderConvergence convergence;
  final List<ReminderBlocker> blockers;
  final List<ReminderScopeHealth> scopes;
  final ReminderCapacityUse capacity;
  final List<ReminderLimitation> limitations;
  final DateTime? checkedAt;
  final int unconfirmedCancellations, pendingCancellations;
  final bool failed;

  /// False before the first foreground pass has reported anything, so an
  /// untouched surface never claims trouble it has not observed.
  final bool attempted;

  bool get blocked => blockers.isNotEmpty;
  bool get needsAttention =>
      attempted &&
      (failed ||
          convergence != ReminderConvergence.converged ||
          pendingCancellations > 0 ||
          unconfirmedCancellations > 0 ||
          blocked ||
          scopes.any((s) => s.state != ReminderScopeState.ready));

  /// Deliberately constant: no supported host can promise delivery.
  bool get deliveryGuaranteed => false;

  ReminderScopeHealth? operator [](String scope) {
    for (final s in scopes) {
      if (s.scope == scope) return s;
    }
    return null;
  }
}

/// Capability gates in repair priority order. Empty means the adapter reports
/// that preparation may proceed.
List<ReminderBlocker> reminderBlockers(ReminderCapabilities capabilities) => [
  if (!capabilities.supported) ReminderBlocker.unsupportedHost,
  if (!capabilities.protectedStorageAvailable) ReminderBlocker.protectedStorage,
  if (!capabilities.notificationPermission)
    ReminderBlocker.notificationPermission,
  if (!capabilities.appEnabled) ReminderBlocker.appDisabled,
  if (!capabilities.channelEnabled) ReminderBlocker.channelDisabled,
  if (!capabilities.exactAlarm) ReminderBlocker.exactAlarm,
  if (!capabilities.bootIdentityAvailable) ReminderBlocker.bootIdentity,
];

ReminderCapacityUse reminderCapacityUse(ReminderProjection? projection) {
  if (projection == null) return const ReminderCapacityUse();
  // The store emits one capacity exclusion per displaced request, scoped to its
  // plan or event. No other scope is emitted, so the sum is unduplicated.
  final deferred = projection.exclusions
      .where((e) => e.reason == 'capacity')
      .fold<int>(0, (sum, e) => sum + e.count);
  return ReminderCapacityUse(
    ordinary: projection.desired
        .where((d) => d.kind == ReminderKind.ordinary)
        .length,
    snoozes: projection.desired
        .where((d) => d.kind == ReminderKind.snooze)
        .length,
    eventEnds: projection.eventEnds.length,
    stockNotices: projection.stockNotices.length,
    deferred: deferred,
  );
}

int _deferredInScope(ReminderProjection projection, String scope) {
  if (!scope.startsWith('plan:') && !scope.startsWith('event:')) return 0;
  return projection.exclusions
      .where((e) => e.scope == scope && e.reason == 'capacity')
      .fold<int>(0, (sum, e) => sum + e.count);
}

/// Build the only claim set the health surface is allowed to render.
ReminderHealthSummary summariseReminderHealth({
  required ReminderCapabilities? capabilities,
  required ReminderProjection? projection,
  required ReminderConvergence convergence,
  required bool failed,
  int pendingCancellations = 0,
  int unconfirmedCancellations = 0,
  DateTime? checkedAt,
}) {
  final blockers = capabilities == null
      ? const <ReminderBlocker>[]
      : reminderBlockers(capabilities);
  final blockedByHost = blockers.any(
    (b) =>
        b == ReminderBlocker.unsupportedHost ||
        b == ReminderBlocker.protectedStorage,
  );
  final capacity = reminderCapacityUse(projection);
  final projectionComplete = projection?.complete ?? false;
  final verified =
      capabilities != null &&
      blockers.isEmpty &&
      !failed &&
      convergence == ReminderConvergence.converged &&
      pendingCancellations == 0 &&
      unconfirmedCancellations == 0;
  final scopes = <ReminderScopeHealth>[];
  for (final coverage in projection?.coverage ?? const <ReminderCoverage>[]) {
    final excluded = projection!.exclusions.any(
      (e) => e.scope == coverage.scope && e.reason != 'capacity',
    );
    final deferred = _deferredInScope(projection, coverage.scope);
    final attention = projection.attention
        .where((d) => _desiredInScope(d, coverage.scope))
        .length;
    final state = blockedByHost
        ? ReminderScopeState.blocked
        : deferred > 0
        ? ReminderScopeState.deferred
        : attention > 0
        ? ReminderScopeState.attention
        : verified && projectionComplete && coverage.complete && !excluded
        ? ReminderScopeState.ready
        : ReminderScopeState.partial;
    scopes.add(
      ReminderScopeHealth(
        scope: coverage.scope,
        state: state,
        complete: state == ReminderScopeState.ready,
        deferred: deferred,
        attention: attention,
        reason: coverage.reason,
        // Prepared-through means every eligible reminder in this scope through
        // that point is prepared. Anything else must not print a time.
        preparedThrough: state == ReminderScopeState.ready
            ? coverage.preparedThrough
            : null,
        checkedAt: coverage.checkedAt,
        basis: coverage.basis,
      ),
    );
  }
  scopes.sort((a, b) => a.scope.compareTo(b.scope));
  final restartSeen =
      scopes.any((s) => s.state == ReminderScopeState.attention) ||
      projection?.attention.any(
            (d) => d.repairState == ReminderRepairState.interrupted,
          ) ==
          true;
  return ReminderHealthSummary(
    convergence: convergence,
    blockers: List.unmodifiable(blockers),
    scopes: List.unmodifiable(scopes),
    capacity: capacity,
    limitations: List.unmodifiable([
      ReminderLimitation.deliveryNotGuaranteed,
      if (projection != null) ReminderLimitation.preparedWindowBounded,
      if (restartSeen) ReminderLimitation.deviceRestartElapsedSnooze,
      ReminderLimitation.forceStopAndBatteryLimits,
      if (capacity.prepared > 0 || capacity.deferred > 0)
        ReminderLimitation.capacityFinite,
      if (projection != null) ReminderLimitation.noBackgroundReplenishment,
    ]),
    checkedAt: checkedAt,
    unconfirmedCancellations: unconfirmedCancellations,
    pendingCancellations: pendingCancellations,
    failed: failed,
    attempted: capabilities != null || projection != null || failed,
  );
}

bool _desiredInScope(DesiredReminder desired, String scope) {
  final identity = desired.target.row.expectation.identity;
  if (scope == 'everyone') return true;
  if (scope.startsWith('person:')) {
    return scope.substring(7) == identity.personId;
  }
  if (scope.startsWith('plan:')) return scope.substring(5) == identity.planId;
  return false;
}

/// The single health claim set for any settings/help surface. T08 and the lead
/// embed this instead of re-deriving reminder claims from raw projections.
final reminderHealthProvider = Provider<ReminderHealthSummary>((ref) {
  final state = ref.watch(remindersProvider);
  final report = state.report;
  final projection = report.projection;
  return summariseReminderHealth(
    capabilities: report.capabilities,
    projection: projection,
    convergence: report.failed
        ? ReminderConvergence.failed
        : report.convergence,
    failed: report.failed,
    pendingCancellations: report.pendingCancellations,
    unconfirmedCancellations: report.unconfirmedCancellations,
    checkedAt: projection?.coverage.map((c) => c.checkedAt).fold<DateTime?>(
      null,
      (latest, at) {
        if (latest == null || at.isAfter(latest)) return at;
        return latest;
      },
    ),
  );
});
