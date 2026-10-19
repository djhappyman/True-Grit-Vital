import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/record_store.dart';
import '../platform/reminders.dart';
import 'app_lock.dart';
import 'device_zone.dart';
import 'reminder_reconciler.dart';
import 'storage.dart';

final reminderGatewayProvider = Provider<ReminderGateway>(
  (ref) => Platform.isAndroid
      ? const AndroidReminders()
      : const UnsupportedReminders(),
);

final class _StoreRepair
    implements ReminderRepairRepository, EventEndReminderRepairRepository {
  _StoreRepair(this.store);
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
    sequence: sequence,
    generation: desired.generation,
    requestToken: desired.requestToken,
    intentRevision: desired.intentRevision,
    receipt: receipt,
    reason: reason,
    adapterFingerprint: adapterFingerprint,
  );
  @override
  Future<bool> acknowledgeEventEnd({
    required int sequence,
    required EventEndReminder desired,
    required ReminderReceipt receipt,
    required String? reason,
    required String adapterFingerprint,
  }) => store.acknowledgeReminder(
    sequence: sequence,
    generation: desired.generation,
    requestToken: desired.requestToken,
    intentRevision: desired.eventRevision,
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
  }) async {
    await store.acknowledgeObsoleteReminder(
      generation: generation,
      sequence: sequence,
      requestToken: requestToken,
      receipt: receipt,
      reason: reason,
      adapterFingerprint: adapterFingerprint,
    );
  }
}

final class ReminderState {
  const ReminderState({
    this.report = const ReminderRepairReport(),
    this.pending = const [],
    this.eventPending = const [],
    this.busy = false,
    this.actionFailed = false,
  });
  final ReminderRepairReport report;
  final List<PendingReminderAction> pending;
  final List<PendingEventEndReview> eventPending;
  final bool busy, actionFailed;
}

final remindersProvider = NotifierProvider<ReminderController, ReminderState>(
  ReminderController.new,
);

class ReminderRuntime extends ConsumerWidget {
  const ReminderRuntime({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(remindersProvider);
    return child;
  }
}

/// Owns native observation, bounded repair and opaque transport. Clinical
/// submission belongs only to the unlocked, explicitly confirmed action page.
class ReminderController extends Notifier<ReminderState>
    with WidgetsBindingObserver {
  ReminderReconciler? _repair;
  StreamSubscription<void>? _native, _changes;
  bool _disposed = false, _capturing = false, _captureAgain = false;
  bool _foreground = true;
  RecordStore? _store;
  int _session = 0;
  int _refreshRevision = 0;
  bool _current(int session) =>
      !_disposed && ref.mounted && session == _session;

  @override
  ReminderState build() {
    final session = ++_session;
    _repair = null;
    _changes = null;
    _capturing = false;
    _captureAgain = false;
    final store = ref.watch(recordStoreProvider).value;
    final gateway = ref.watch(reminderGatewayProvider);
    _store = store;
    _disposed = false;
    _foreground =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
    if (store != null) {
      _repair = ReminderReconciler(
        gateway: gateway,
        repository: _StoreRepair(store),
        observedZone: () => ref.read(observedDeviceZoneProvider).value?.zoneId,
        onReport: (report) {
          if (_current(session) && report.revision == _refreshRevision) {
            state = ReminderState(
              report: report,
              pending: state.pending,
              eventPending: state.eventPending,
              busy: state.busy,
              actionFailed: state.actionFailed,
            );
          }
        },
      );
      _changes = store.watchReminderChanges().listen((_) {
        if (_current(session)) refresh();
      });
    }
    _native = gateway.changes.listen(
      (_) {
        if (_current(session)) refresh();
      },
      onError: (Object _) {
        if (_current(session)) refresh();
      },
    );
    ref.listen(appLockProvider, (_, next) {
      if (next.ready && !next.locked) unawaited(capture());
    });
    ref.listen(observedDeviceZoneProvider, (_, next) => refresh());
    final ownedRepair = _repair, ownedNative = _native, ownedChanges = _changes;
    ref.onDispose(() {
      _disposed = true;
      WidgetsBinding.instance.removeObserver(this);
      ownedRepair?.dispose();
      unawaited(ownedNative?.cancel());
      unawaited(ownedChanges?.cancel());
    });
    scheduleMicrotask(() {
      if (_current(session)) refresh();
    });
    return const ReminderState();
  }

  Future<void> refresh() {
    if (_disposed || !ref.mounted || !_foreground) return Future.value();
    final revision = ++_refreshRevision;
    if (state.report.projection != null) {
      state = ReminderState(
        report: ReminderRepairReport(
          capabilities: state.report.capabilities,
          revision: revision,
        ),
        pending: state.pending,
        eventPending: state.eventPending,
        busy: state.busy,
        actionFailed: state.actionFailed,
      );
    }
    unawaited(_readCapabilities(revision));
    unawaited(capture());
    return _repair?.request(revision: revision) ?? Future.value();
  }

  Future<void> retry() async {
    if (!_unlocked || state.busy) return;
    final session = _session;
    final repair = _repair;
    state = ReminderState(
      report: state.report,
      pending: state.pending,
      eventPending: state.eventPending,
      actionFailed: state.actionFailed,
      busy: true,
    );
    try {
      await refresh();
      // An explicit repair arriving during the final coalesced pass owns one
      // fresh bounded attempt, rather than being dropped with that old pass.
      if (_current(session) &&
          _repair == repair &&
          state.report.projection == null) {
        await refresh();
      }
    } finally {
      if (_current(session)) {
        state = ReminderState(
          report: state.report,
          pending: state.pending,
          eventPending: state.eventPending,
          actionFailed: state.actionFailed,
        );
      }
    }
  }

  Future<void> _readCapabilities(int revision) async {
    final session = _session;
    try {
      final capabilities = await ref
          .read(reminderGatewayProvider)
          .capabilities()
          .timeout(const Duration(seconds: 5));
      if (_current(session) && revision == _refreshRevision) {
        state = ReminderState(
          report: ReminderRepairReport(
            capabilities: capabilities,
            projection:
                state.report.revision == revision &&
                    _sameCapabilities(state.report.capabilities, capabilities)
                ? state.report.projection
                : null,
            revision: revision,
            failed: state.report.failed,
          ),
          pending: state.pending,
          eventPending: state.eventPending,
          busy: state.busy,
          actionFailed: state.actionFailed,
        );
      }
    } catch (_) {
      /* Storage recovery remains the existing protected gate. */
    }
  }

  bool _sameCapabilities(ReminderCapabilities? a, ReminderCapabilities b) =>
      a != null &&
      a.supported == b.supported &&
      a.notificationPermission == b.notificationPermission &&
      a.appEnabled == b.appEnabled &&
      a.channelEnabled == b.channelEnabled &&
      a.exactAlarm == b.exactAlarm &&
      a.protectedStorageAvailable == b.protectedStorageAvailable &&
      a.bootIdentityAvailable == b.bootIdentityAvailable &&
      a.fingerprint == b.fingerprint;

  bool get _unlocked {
    if (_disposed || !ref.mounted || !_foreground) return false;
    final lock = ref.read(appLockProvider);
    return lock.ready && !lock.locked && !lock.busy;
  }

  Future<void> capture() async {
    if (!_unlocked || _store == null) return;
    if (_capturing) {
      _captureAgain = true;
      return;
    }
    _capturing = true;
    final session = _session;
    final store = _store!, gateway = ref.read(reminderGatewayProvider);
    try {
      // Native retains unacknowledged envelopes across process recreation.
      for (var i = 0; i < 8 && _current(session) && _unlocked; i++) {
        final envelope = await gateway.getInitialAction().timeout(
          const Duration(seconds: 5),
        );
        if (!_current(session) || !_unlocked || envelope == null) break;
        final eventCaptured = await store.captureEventEndAction(
          envelopeId: envelope.envelopeId,
          namespace: envelope.epoch,
          requestToken: envelope.requestToken,
          actionToken: envelope.actionToken,
          action: switch (envelope.action) {
            NativeReminderActionKind.open => ReminderActionKind.open,
            NativeReminderActionKind.taken => ReminderActionKind.taken,
            NativeReminderActionKind.snooze => ReminderActionKind.snooze,
            NativeReminderActionKind.skip => ReminderActionKind.skip,
          },
        );
        if (!eventCaptured) {
          await store.captureReminderAction(
            envelopeId: envelope.envelopeId,
            namespace: envelope.epoch,
            requestToken: envelope.requestToken,
            actionToken: envelope.actionToken,
            action: switch (envelope.action) {
              NativeReminderActionKind.open => ReminderActionKind.open,
              NativeReminderActionKind.taken => ReminderActionKind.taken,
              NativeReminderActionKind.snooze => ReminderActionKind.snooze,
              NativeReminderActionKind.skip => ReminderActionKind.skip,
            },
          );
        }
        if (!_current(session)) return;
        // Returning means encrypted pending capture or durable stale validation.
        // Relocking cannot invalidate that durable transport acknowledgement.
        await gateway
            .acknowledgeAction(envelope.envelopeId)
            .timeout(const Duration(seconds: 5));
      }
      final pending = await store.pendingReminderActions();
      final eventPending = await store.pendingEventEndReviews();
      if (_current(session) && _unlocked) {
        state = ReminderState(
          report: state.report,
          pending: List.unmodifiable(pending),
          eventPending: List.unmodifiable(eventPending),
          busy: state.busy,
        );
      }
    } catch (_) {
      if (_current(session)) {
        state = ReminderState(
          report: state.report,
          pending: state.pending,
          eventPending: state.eventPending,
          actionFailed: true,
          busy: state.busy,
        );
      }
    } finally {
      if (_current(session)) {
        _capturing = false;
        if (_captureAgain) {
          _captureAgain = false;
          if (_unlocked) unawaited(capture());
        }
      }
    }
  }

  Future<void> permission(
    Future<bool> Function(ReminderGateway) operation,
  ) async {
    if (!_unlocked || state.busy) return;
    final session = _session;
    state = ReminderState(
      report: state.report,
      pending: state.pending,
      eventPending: state.eventPending,
      busy: true,
    );
    try {
      await operation(ref.read(reminderGatewayProvider))
          .timeout(const Duration(seconds: 5));
    } catch (_) {
      /* Capability re-observation supplies the effective truth. */
    } finally {
      if (_current(session)) {
        state = ReminderState(
          report: state.report,
          pending: state.pending,
          eventPending: state.eventPending,
        );
        refresh();
      }
    }
  }

  void completeEventPending(String envelopeId) {
    if (_disposed || !ref.mounted) return;
    state = ReminderState(
      report: state.report,
      busy: state.busy,
      pending: state.pending,
      eventPending: List.unmodifiable(
        state.eventPending.where((p) => p.envelopeId != envelopeId),
      ),
    );
    refresh();
  }

  void completePending(String envelopeId) {
    if (_disposed || !ref.mounted) return;
    state = ReminderState(
      report: state.report,
      busy: state.busy,
      eventPending: state.eventPending,
      pending: List.unmodifiable(
        state.pending.where((p) => p.envelopeId != envelopeId),
      ),
    );
    refresh();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) refresh();
  }
}
