import 'dart:async';

import '../domain/reminders/reminders.dart';
import '../platform/reminders.dart';

/// The background capability deliberately excludes administration commands.
abstract interface class ReminderRepairRepository {
  Future<ReminderProjection> prepare({
    required DateTime now,
    required String? observedZone,
    required ReminderClockSample? clockSample,
    required String adapterFingerprint,
  });
  Future<bool> acknowledge({
    required int sequence,
    required DesiredReminder desired,
    required ReminderReceipt receipt,
    required String? reason,
    required String adapterFingerprint,
  });
  Future<void> acknowledgeObsolete({
    required String generation,
    required int sequence,
    required String requestToken,
    required ReminderReceipt receipt,
    required String? reason,
    required String adapterFingerprint,
  });
}

/// Optional review-only extension; ordinary repair adapters retain their contract.
abstract interface class EventEndReminderRepairRepository {
  Future<bool> acknowledgeEventEnd({
    required int sequence,
    required EventEndReminder desired,
    required ReminderReceipt receipt,
    required String? reason,
    required String adapterFingerprint,
  });
}

final class ReminderRepairReport {
  const ReminderRepairReport({
    this.capabilities,
    this.projection,
    this.failed = false,
    this.revision = 0,
  });
  final ReminderCapabilities? capabilities;
  final ReminderProjection? projection;
  final bool failed;
  final int revision;
}

/// One foreground-owned bounded worker. Events coalesce; there is no timer or
/// permission retry loop. A timeout is unknown, never evidence of absence.
final class ReminderReconciler {
  ReminderReconciler({
    required this.gateway,
    required this.repository,
    required this.observedZone,
    required this.onReport,
    this.callTimeout = const Duration(seconds: 5),
  });
  final ReminderGateway gateway;
  final ReminderRepairRepository repository;
  final String? Function() observedZone;
  final void Function(ReminderRepairReport) onReport;
  final Duration callTimeout;
  bool _disposed = false, _running = false, _again = false;
  Future<void>? _flight;
  int _revision = 0;

  Future<void> request({int revision = 0}) {
    if (_disposed) return Future.value();
    _revision = revision;
    if (_running) {
      _again = true;
      return _flight!;
    }
    _running = true;
    final done = Completer<void>();
    _flight = done.future;
    unawaited(
      _run().whenComplete(() {
        _running = false;
        done.complete();
      }),
    );
    return done.future;
  }

  Future<void> _run() async {
    // A concurrent mutation gets one convergence pass, never an unbounded loop.
    for (var pass = 0; pass < 2 && !_disposed; pass++) {
      _again = false;
      final revision = _revision;
      ReminderCapabilities? capabilities;
      try {
        capabilities = await gateway.capabilities().timeout(callTimeout);
        if (_disposed) return;
        // Capability controls must not wait for the SQL repair projection.
        onReport(
          ReminderRepairReport(capabilities: capabilities, revision: revision),
        );
        if (!capabilities.supported ||
            !capabilities.protectedStorageAvailable) {
          onReport(
            ReminderRepairReport(
              capabilities: capabilities,
              revision: revision,
            ),
          );
          return;
        }
        ReminderClockSample? sample;
        try {
          sample = await gateway.sampleClock().timeout(callTimeout);
        } catch (_) {
          /* Wall requests can still be prepared without a boot ID. */
        }
        if (_disposed) return;
        final projection = await repository.prepare(
          now: sample == null
              ? DateTime.now().toUtc()
              : DateTime.fromMillisecondsSinceEpoch(
                  sample.utcMilliseconds,
                  isUtc: true,
                ),
          observedZone: observedZone(),
          clockSample: sample,
          adapterFingerprint: capabilities.fingerprint,
        );
        if (_disposed) return;
        NativeReminderSnapshot? applied;
        try {
          applied = await gateway
              .applySnapshot(
                epoch: projection.namespace,
                sequence: projection.sequence,
                desired: [
                  for (final d in projection.desired)
                    NativeReminderRequest(
                      epoch: d.namespace,
                      requestToken: d.requestToken,
                      takenToken: d.takenToken,
                      snoozeToken: d.snoozeToken,
                      skipToken: d.skipToken,
                      clock: d.trigger == ReminderTrigger.elapsed
                          ? ReminderNativeClock.elapsed
                          : ReminderNativeClock.wall,
                      deadlineMilliseconds: d.deadlineMilliseconds,
                      bootId: d.bootId,
                    ),
                  for (final d in projection.eventEnds)
                    NativeReminderRequest(
                      epoch: d.namespace,
                      requestToken: d.requestToken,
                      takenToken: d.takenToken,
                      snoozeToken: d.snoozeToken,
                      skipToken: d.skipToken,
                      clock: ReminderNativeClock.wall,
                      deadlineMilliseconds: d.deadlineMilliseconds,
                      purpose: NativeReminderPurpose.eventEnd,
                    ),
                ],
                obsoleteTokens: projection.obsoleteTokens,
              )
              .timeout(callTimeout);
        } catch (_) {
          /* The serial native fence resolves any late completion. */
        }
        if (_disposed) return;
        final current =
            applied != null &&
            applied.accepted &&
            applied.epoch == projection.namespace &&
            applied.sequence == projection.sequence &&
            applied.fingerprint == capabilities.fingerprint;
        final receipts = {
          if (current)
            for (final r in applied.receipts) r.requestToken: r,
        };
        for (final desired in projection.desired) {
          if (_disposed) return;
          final receipt = receipts[desired.requestToken];
          final accepted = await repository.acknowledge(
            sequence: projection.sequence,
            desired: desired,
            receipt: receipt == null
                ? ReminderReceipt.unknown
                : switch (receipt.state) {
                    NativeReminderState.accepted => ReminderReceipt.accepted,
                    NativeReminderState.consumed => ReminderReceipt.consumed,
                    NativeReminderState.cancelled => ReminderReceipt.cancelled,
                    NativeReminderState.postUncertain =>
                      ReminderReceipt.postUncertain,
                    NativeReminderState.failed => ReminderReceipt.failed,
                    NativeReminderState.unknown => ReminderReceipt.unknown,
                  },
            reason: receipt == null
                ? (current ? 'missing_receipt' : 'native_unknown')
                : receipt.reason,
            adapterFingerprint: capabilities.fingerprint,
          );
          if (!accepted) _again = true;
        }
        final eventRepository = repository;
        if (eventRepository is EventEndReminderRepairRepository) {
          for (final desired in projection.eventEnds) {
            if (_disposed) return;
            final receipt = receipts[desired.requestToken];
            final accepted =
                await (eventRepository as EventEndReminderRepairRepository)
                    .acknowledgeEventEnd(
                      sequence: projection.sequence,
                      desired: desired,
                      receipt: receipt == null
                          ? ReminderReceipt.unknown
                          : ReminderReceipt.values.byName(receipt.state.name),
                      reason: receipt == null
                          ? (current ? 'missing_receipt' : 'native_unknown')
                          : receipt.reason,
                      adapterFingerprint: capabilities.fingerprint,
                    );
            if (!accepted) _again = true;
          }
        }
        for (final token in projection.obsoleteTokens) {
          if (_disposed) return;
          final receipt = receipts[token];
          if (receipt != null &&
              const [
                NativeReminderState.cancelled,
                NativeReminderState.consumed,
                NativeReminderState.postUncertain,
              ].contains(receipt.state)) {
            await repository.acknowledgeObsolete(
              generation: projection.generation,
              sequence: projection.sequence,
              requestToken: token,
              receipt: switch (receipt.state) {
                NativeReminderState.consumed => ReminderReceipt.consumed,
                NativeReminderState.postUncertain =>
                  ReminderReceipt.postUncertain,
                _ => ReminderReceipt.cancelled,
              },
              reason: receipt.reason,
              adapterFingerprint: capabilities.fingerprint,
            );
          }
        }
        if (_disposed) return;
        // Coverage is read after conditional acknowledgements. An old snapshot
        // can never announce that newly changed work is prepared.
        final checked = await repository.prepare(
          now: DateTime.now().toUtc(),
          observedZone: observedZone(),
          clockSample: sample,
          adapterFingerprint: capabilities.fingerprint,
        );
        if (checked.sequence != projection.sequence ||
            checked.eventEnds.map((d) => d.requestToken).join(',') !=
                projection.eventEnds.map((d) => d.requestToken).join(',') ||
            checked.desired.map((d) => d.requestToken).join(',') !=
                projection.desired.map((d) => d.requestToken).join(',') ||
            checked.obsoleteTokens.join(',') !=
                projection.obsoleteTokens.join(',')) {
          _again = true;
        }
        if (!_disposed) {
          onReport(
            ReminderRepairReport(
              capabilities: capabilities,
              projection: checked,
              failed: !current,
              revision: revision,
            ),
          );
        }
      } catch (_) {
        if (!_disposed) {
          onReport(
            ReminderRepairReport(
              capabilities: capabilities,
              failed: true,
              revision: revision,
            ),
          );
        }
        return;
      }
      if (!_again) return;
    }
  }

  void dispose() {
    _disposed = true;
  }
}
