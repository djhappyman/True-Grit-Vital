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

/// Optional stock-notice extension. Its only native action is Open; it never
/// grants an administration or stock-movement command.
abstract interface class StockNoticeRepairRepository {
  Future<bool> acknowledgeStockNotice({
    required int sequence,
    required StockNoticeReminder desired,
    required ReminderReceipt receipt,
    required String? reason,
    required String adapterFingerprint,
  });
}

/// Outcome of one bounded foreground repair flight. It is reported even when
/// the bound is reached, so a partial repair is never presented as complete.
enum ReminderConvergence {
  /// Desired state matched the last native snapshot within the pass bound.
  converged,

  /// Work remained after the bound. Another foreground pass is required.
  deferred,

  /// A capability or protected-storage gate stopped preparation.
  blocked,

  /// A pass threw or the native fence rejected the snapshot.
  failed,
}

final class ReminderRepairReport {
  const ReminderRepairReport({
    this.capabilities,
    this.projection,
    this.convergence = ReminderConvergence.deferred,
    this.failed = false,
    this.revision = 0,
    this.passes = 0,
    this.pendingCancellations = 0,
    this.unconfirmedCancellations = 0,
    this.epochRecovered = false,
  });
  final ReminderCapabilities? capabilities;
  final ReminderProjection? projection;
  final ReminderConvergence convergence;
  final bool failed;
  final int revision, passes, pendingCancellations, unconfirmedCancellations;
  final bool epochRecovered;
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
    this.passLimit = 2,
  });
  final ReminderGateway gateway;
  final ReminderRepairRepository repository;
  final String? Function() observedZone;
  final void Function(ReminderRepairReport) onReport;
  final Duration callTimeout;

  /// Hard cap on convergence passes inside one flight. A foreground mutation
  /// that lands after the final pass re-arms exactly one further bounded
  /// flight instead of being silently dropped.
  final int passLimit;
  bool _disposed = false, _running = false, _again = false, _pending = false;
  Future<void>? _flight;
  int _revision = 0;

  Future<void> request({int revision = 0}) {
    if (_disposed) return Future.value();
    _revision = revision;
    _pending = true;
    if (_running) {
      _again = true;
      return _flight!;
    }
    return _start();
  }

  Future<void> _start() {
    _running = true;
    final done = Completer<void>();
    _flight = done.future;
    unawaited(
      _run().whenComplete(() {
        _running = false;
        done.complete();
        if (!_disposed && _pending) unawaited(_start());
      }),
    );
    return done.future;
  }

  Future<void> _run() async {
    var lastConvergence = ReminderConvergence.deferred;
    ReminderProjection? lastProjection;
    ReminderCapabilities? capabilities;
    var passes = 0;
    var lastPending = 0, lastUnconfirmed = 0;
    // Flight-level truth: the epoch was handed over at least once in this run.
    var recoveredEpoch = false;
    for (; passes < passLimit && !_disposed;) {
      _again = false;
      _pending = false;
      passes++;
      final revision = _revision;
      try {
        capabilities = await gateway.capabilities().timeout(callTimeout);
        if (_disposed) return;
        // Capability controls must not wait for the SQL repair projection.
        onReport(
          ReminderRepairReport(
            capabilities: capabilities,
            convergence:
                capabilities.supported && capabilities.protectedStorageAvailable
                ? ReminderConvergence.deferred
                : ReminderConvergence.blocked,
            revision: revision,
            passes: passes,
          ),
        );
        if (!capabilities.supported ||
            !capabilities.protectedStorageAvailable) {
          return;
        }
        ReminderClockSample? sample;
        try {
          sample = await gateway.sampleClock().timeout(callTimeout);
        } catch (_) {
          /* Wall requests can still be prepared without a boot ID. */
        }
        if (_disposed) return;
        final now = sample == null
            ? DateTime.now().toUtc()
            : DateTime.fromMillisecondsSinceEpoch(
                sample.utcMilliseconds,
                isUtc: true,
              );
        var projection = await repository.prepare(
          now: now,
          observedZone: observedZone(),
          clockSample: sample,
          adapterFingerprint: capabilities.fingerprint,
        );
        if (_disposed) return;
        // A restored dataset carries a fresh durable namespace while the
        // adapter still holds the previous epoch. Hand it over explicitly;
        // otherwise the adapter rejects every snapshot until a reinstall.
        final installed = capabilities.installedEpoch;
        if (installed != null && installed != projection.namespace) {
          var handedOver = false;
          try {
            handedOver = await gateway
                .invalidateEpoch(
                  oldEpoch: installed,
                  newEpoch: projection.namespace,
                )
                .timeout(callTimeout);
          } catch (_) {
            handedOver = false;
          }
          if (_disposed) return;
          if (handedOver) recoveredEpoch = true;
          if (!handedOver) _again = true;
        }
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
                  for (final d in projection.stockNotices)
                    NativeReminderRequest(
                      epoch: d.namespace,
                      requestToken: d.requestToken,
                      takenToken: d.takenToken,
                      snoozeToken: d.snoozeToken,
                      skipToken: d.skipToken,
                      clock: ReminderNativeClock.wall,
                      deadlineMilliseconds: d.deadlineMilliseconds,
                      purpose: NativeReminderPurpose.stockLow,
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
        final stockRepository = repository;
        if (stockRepository is StockNoticeRepairRepository) {
          for (final desired in projection.stockNotices) {
            if (_disposed) return;
            final receipt = receipts[desired.requestToken];
            final accepted =
                await (stockRepository as StockNoticeRepairRepository)
                    .acknowledgeStockNotice(
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
        var pendingCancellations = 0;
        var unconfirmedCancellations = 0;
        for (final token in projection.obsoleteTokens) {
          if (_disposed) return;
          final receipt = receipts[token];
          if (receipt == null) {
            if (current) {
              // The adapter accepted the snapshot but omitted this receipt. It
              // cannot be confirmed, so it is closed once as uncertain rather
              // than retried forever or silently treated as cancelled.
              unconfirmedCancellations++;
              await repository.acknowledgeObsolete(
                generation: projection.generation,
                sequence: projection.sequence,
                requestToken: token,
                receipt: ReminderReceipt.postUncertain,
                reason: 'missing_receipt',
                adapterFingerprint: capabilities.fingerprint,
              );
            }
            continue;
          }
          if (receipt.reason == 'cancellation_unknown') {
            unconfirmedCancellations++;
          }
          if (const [
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
            continue;
          }
          // A state of unknown from a current snapshot means the adapter holds
          // no entry for the token, so nothing can still fire. Recording an
          // explicit uncertain receipt ends the retry loop truthfully instead
          // of leaving an unacknowledgeable row forever.
          if (receipt.state == NativeReminderState.unknown) {
            await repository.acknowledgeObsolete(
              generation: projection.generation,
              sequence: projection.sequence,
              requestToken: token,
              receipt: ReminderReceipt.postUncertain,
              reason: receipt.reason ?? 'not_installed',
              adapterFingerprint: capabilities.fingerprint,
            );
            continue;
          }
          pendingCancellations++;
          _again = true;
        }
        if (_disposed) return;
        // Coverage is read after conditional acknowledgements. An old snapshot
        // can never announce that newly changed work is prepared. The same
        // clock basis is reused so an unchanged plan does not look changed and
        // cause needless native churn.
        final checked = await repository.prepare(
          now: now,
          observedZone: observedZone(),
          clockSample: sample,
          adapterFingerprint: capabilities.fingerprint,
        );
        if (_disposed) return;
        if (checked.sequence != projection.sequence ||
            checked.eventEnds.map((d) => d.requestToken).join(',') !=
                projection.eventEnds.map((d) => d.requestToken).join(',') ||
            checked.stockNotices.map((d) => d.requestToken).join(',') !=
                projection.stockNotices.map((d) => d.requestToken).join(',') ||
            checked.desired.map((d) => d.requestToken).join(',') !=
                projection.desired.map((d) => d.requestToken).join(',') ||
            checked.obsoleteTokens.join(',') !=
                projection.obsoleteTokens.join(',')) {
          _again = true;
        }
        lastConvergence = !current
            ? ReminderConvergence.failed
            : _again
            ? ReminderConvergence.deferred
            : ReminderConvergence.converged;
        lastProjection = checked;
        lastPending = pendingCancellations;
        lastUnconfirmed = unconfirmedCancellations;
        onReport(
          ReminderRepairReport(
            capabilities: capabilities,
            projection: checked,
            convergence: lastConvergence,
            failed: !current,
            revision: revision,
            passes: passes,
            pendingCancellations: pendingCancellations,
            unconfirmedCancellations: unconfirmedCancellations,
            epochRecovered: recoveredEpoch,
          ),
        );
      } catch (_) {
        if (!_disposed) {
          onReport(
            ReminderRepairReport(
              capabilities: capabilities,
              convergence: ReminderConvergence.failed,
              failed: true,
              revision: revision,
              passes: passes,
            ),
          );
        }
        return;
      }
      if (!_again) return;
    }
    // The pass bound was reached with work outstanding. Report that honestly
    // and stop; the next foreground event owns the follow-up.
    if (!_disposed && lastConvergence != ReminderConvergence.converged) {
      onReport(
        ReminderRepairReport(
          capabilities: capabilities,
          projection: lastProjection,
          convergence: lastConvergence == ReminderConvergence.failed
              ? ReminderConvergence.failed
              : ReminderConvergence.deferred,
          failed: lastConvergence == ReminderConvergence.failed,
          revision: _revision,
          passes: passes,
          pendingCancellations: lastPending,
          unconfirmedCancellations: lastUnconfirmed,
          epochRecovered: recoveredEpoch,
        ),
      );
    }
  }

  void dispose() {
    _disposed = true;
  }
}
