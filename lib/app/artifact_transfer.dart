import 'dart:async';

import 'package:crypto/crypto.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/artifact_transfer.dart';
import '../domain/records.dart' show newCommandId;
import '../platform/artifact_transfer.dart';
import 'app_lock.dart';
import 'storage.dart';

final artifactTransferGatewayProvider = Provider<ArtifactTransferGateway>((
  ref,
) {
  final generation = ref.watch(
    recordStoreProvider.select((value) => value.value?.generation),
  );
  // Synthetic/provider-overridden datasets must never maintain staging from
  // the real installation. A replacement discards its old staging before
  // switching the active generation.
  if (generation == null) return const UnsupportedArtifactTransfer();
  return defaultArtifactTransferGateway(scope: generation);
});
final artifactTransferClockProvider = Provider<DateTime Function()>(
  (_) =>
      () => DateTime.now().toUtc(),
);

/// Protected staging is only available after the records unlock.
final artifactTransferGateProvider = Provider<bool Function()>((ref) {
  return () {
    final lock = ref.read(appLockProvider);
    return lock.ready && !lock.locked && !lock.busy;
  };
});

final artifactTransferControllerProvider =
    NotifierProvider<ArtifactTransferController, ArtifactTransferState>(
      ArtifactTransferController.new,
    );

/// Owns one bounded generated-artifact handoff at a time.
///
/// Feature code supplies a completed [ArtifactSource]. The controller stages
/// and verifies it, reports bounded staging progress, then offers a real save
/// or share. It never persists artifact data or receiver details.
class ArtifactTransferController extends Notifier<ArtifactTransferState> {
  bool _busy = false;
  bool _cancelRequested = false;
  String? _activeId;
  Future<void>? _maintenance;

  @override
  ArtifactTransferState build() => const ArtifactTransferState();

  Future<ArtifactTransferOutcome> save(ArtifactSource source) =>
      _consume(source, ArtifactPurpose.save);

  Future<ArtifactTransferOutcome> share(ArtifactSource source) =>
      _consume(source, ArtifactPurpose.share);

  Future<ArtifactTransferOutcome> _consume(
    ArtifactSource source,
    ArtifactPurpose purpose,
  ) async {
    try {
      return await _transfer(source, purpose);
    } finally {
      final dispose = source.dispose;
      if (dispose != null) {
        try {
          await dispose();
        } catch (_) {
          // Adapter-owned temporary cleanup is retried by its owner.
        }
      }
    }
  }

  /// Cooperative cancellation during bounded staging only.
  ///
  /// An OS save or share dialog belongs to the platform and is cancelled
  /// there; no false claim of stopping a receiver is made here.
  void cancel() {
    if (!_busy || !state.busy || state.phase != ArtifactPhase.staging) return;
    _cancelRequested = true;
    state = state.copy(cancelling: true);
  }

  /// Removes expired, incomplete and abandoned protected staging.
  Future<void> maintenance() {
    if (_busy) return Future<void>.value();
    final running = _maintenance;
    if (running != null) return running;
    final work = _maintain();
    _maintenance = work;
    work.whenComplete(() {
      if (identical(_maintenance, work)) _maintenance = null;
    });
    return work;
  }

  /// Removes every known staged copy, including offered shares. Intended for
  /// dataset replacement/restore so old artifacts cannot outlive their data.
  /// Returns false when a handoff is busy or cleanup failed.
  Future<bool> discardAll() async {
    if (_busy) return false;
    _busy = true;
    var cleaned = false;
    try {
      final maintenance = _maintenance;
      if (maintenance != null) await maintenance;
      await ref
          .read(artifactTransferGatewayProvider)
          .cleanup(includeOffered: true);
      cleaned = true;
      if (ref.mounted) state = const ArtifactTransferState();
    } on ArtifactFailure catch (error) {
      if (ref.mounted) state = ArtifactTransferState(failureCode: error.code);
    } catch (_) {
      if (ref.mounted) {
        state = const ArtifactTransferState(
          failureCode: 'artifact_transfer_storage',
        );
      }
    } finally {
      _busy = false;
    }
    return cleaned;
  }

  Future<void> _maintain() async {
    if (!ref.read(artifactTransferGateProvider)()) return;
    final gateway = ref.read(artifactTransferGatewayProvider);
    try {
      await gateway.cleanup(preserve: _activeId);
      if (ref.mounted &&
          !_busy &&
          state.phase == ArtifactPhase.idle &&
          state.failureCode != null) {
        state = const ArtifactTransferState();
      }
    } on ArtifactFailure catch (error) {
      _maintenanceFailure(error.code);
    } catch (_) {
      _maintenanceFailure('artifact_transfer_storage');
    }
  }

  void _maintenanceFailure(String code) {
    if (ref.mounted && !_busy && state.phase == ArtifactPhase.idle) {
      state = ArtifactTransferState(failureCode: code);
    }
  }

  Future<ArtifactTransferOutcome> _transfer(
    ArtifactSource source,
    ArtifactPurpose purpose,
  ) async {
    if (_busy) {
      return const ArtifactTransferOutcome.failure('artifact_transfer_busy');
    }
    final gateway = ref.read(artifactTransferGatewayProvider);
    final capabilities = gateway.capabilities;
    if (source.byteCount > capabilities.maxBytes) {
      return const ArtifactTransferOutcome.failure('artifact_transfer_limit');
    }
    if (purpose == ArtifactPurpose.save && !capabilities.save) {
      return const ArtifactTransferOutcome.failure(
        'artifact_transfer_save_unavailable',
      );
    }
    if (purpose == ArtifactPurpose.share && !capabilities.share) {
      return const ArtifactTransferOutcome.failure(
        'artifact_transfer_share_unavailable',
      );
    }
    final gate = ref.read(artifactTransferGateProvider);
    if (!gate()) {
      return const ArtifactTransferOutcome.failure('artifact_transfer_locked');
    }

    final id = newCommandId();
    final name = source.fileName ?? source.kind.neutralName;
    final mimeType = source.kind.mimeType;
    final expiresAt = artifactLifetimeFrom(
      ref.read(artifactTransferClockProvider)(),
    );

    // An in-flight startup/resume cleanup must finish before new staging is
    // created, so it cannot reclaim the artifact this operation begins.
    _busy = true;
    final maintenance = _maintenance;
    if (maintenance != null) await maintenance;
    if (!ref.mounted) {
      _busy = false;
      return const ArtifactTransferOutcome.failure(
        'artifact_transfer_interrupted',
      );
    }
    if (!gate()) {
      _busy = false;
      return const ArtifactTransferOutcome.failure('artifact_transfer_locked');
    }

    _cancelRequested = false;
    _activeId = id;
    var offset = 0;
    var begun = false;
    var retained = false;
    var finished = false;
    final digestSink = _DigestSink();
    final hasher = sha256.startChunkedConversion(digestSink);
    state = ArtifactTransferState(
      phase: ArtifactPhase.staging,
      artifactId: id,
      kind: source.kind,
      purpose: purpose,
      byteCount: source.byteCount,
    );

    Future<ArtifactTransferOutcome> stop({
      String? failureCode,
      bool cancelled = false,
    }) async {
      if (begun && !retained) {
        retained = !await _release(gateway, id);
      }
      finished = true;
      if (ref.mounted) {
        state = ArtifactTransferState(
          phase: cancelled ? ArtifactPhase.cancelled : ArtifactPhase.failed,
          artifactId: id,
          kind: source.kind,
          purpose: purpose,
          byteCount: source.byteCount,
          bytesWritten: offset,
          retained: retained,
          failureCode: failureCode,
        );
      }
      return cancelled
          ? ArtifactTransferOutcome.cancelled(retained: retained)
          : ArtifactTransferOutcome.failure(
              failureCode ?? 'artifact_transfer_failed',
              retained: retained,
            );
    }

    try {
      await gateway.begin(
        id: id,
        name: name,
        mimeType: mimeType,
        byteCount: source.byteCount,
        expiresAt: expiresAt,
      );
      begun = true;
      await for (final chunk in boundedArtifactChunks(
        source.openRead(),
        byteCount: source.byteCount,
      )) {
        if (_cancelRequested) return await stop(cancelled: true);
        if (!gate()) {
          return await stop(failureCode: 'artifact_transfer_locked');
        }
        hasher.add(chunk);
        offset = await gateway.append(id: id, offset: offset, bytes: chunk);
        if (offset > source.byteCount) {
          return await stop(failureCode: 'artifact_transfer_incomplete');
        }
        if (ref.mounted) state = state.copy(bytesWritten: offset);
      }
      if (_cancelRequested) return await stop(cancelled: true);
      if (!gate()) return await stop(failureCode: 'artifact_transfer_locked');
      hasher.close();
      final actual = digestSink.value?.toString();
      if (actual == null || offset != source.byteCount) {
        return await stop(failureCode: 'artifact_transfer_incomplete');
      }
      final expected = source.expectedSha256;
      if (expected != null && expected != actual) {
        return await stop(failureCode: 'artifact_transfer_integrity');
      }
      await gateway.publish(id: id, byteCount: offset, sha256: actual);
      if (_cancelRequested) return await stop(cancelled: true);
      if (!gate()) return await stop(failureCode: 'artifact_transfer_locked');
      if (ref.mounted) {
        state = state.copy(bytesWritten: offset, sha256: actual);
      }
      if (purpose == ArtifactPurpose.save) {
        if (ref.mounted) state = state.copy(phase: ArtifactPhase.saving);
        final saved = await gateway.save(
          id: id,
          name: name,
          mimeType: mimeType,
        );
        if (!saved) return await stop(cancelled: true);
        retained = !await _release(gateway, id);
        finished = true;
        if (ref.mounted) {
          state = ArtifactTransferState(
            phase: ArtifactPhase.saved,
            artifactId: id,
            kind: source.kind,
            purpose: purpose,
            byteCount: offset,
            bytesWritten: offset,
            retained: retained,
            sha256: actual,
          );
        }
        return ArtifactTransferOutcome(
          completed: true,
          retained: retained,
          sha256: actual,
        );
      }
      if (ref.mounted) state = state.copy(phase: ArtifactPhase.sharing);
      final shared = await gateway.share(
        id: id,
        name: name,
        mimeType: mimeType,
      );
      if (!shared) return await stop(cancelled: true);
      // An offered grant may outlive this app process; keep the staged copy
      // until the receiver lifetime ends or cancellation confirms removal.
      retained = !await _release(gateway, id);
      finished = true;
      if (ref.mounted) {
        state = ArtifactTransferState(
          phase: ArtifactPhase.offered,
          artifactId: id,
          kind: source.kind,
          purpose: purpose,
          byteCount: offset,
          bytesWritten: offset,
          retained: retained,
          sha256: actual,
        );
      }
      return ArtifactTransferOutcome(
        completed: true,
        retained: retained,
        sha256: actual,
      );
    } on ArtifactFailure catch (error) {
      return await stop(failureCode: error.code);
    } catch (_) {
      return await stop(failureCode: 'artifact_transfer_failed');
    } finally {
      if (!finished && begun && !retained) {
        retained = !await _release(gateway, id);
        if (ref.mounted) state = state.copy(retained: retained);
      }
      _busy = false;
      _activeId = null;
      _cancelRequested = false;
    }
  }

  /// Returns true when the staged copy is known to be removed.
  Future<bool> _release(ArtifactTransferGateway gateway, String id) async {
    try {
      return await gateway.cancel(id);
    } catch (_) {
      return false;
    }
  }
}

/// Runs protected staging cleanup at startup, on unlock and on resume.
class ArtifactTransferRuntime extends ConsumerStatefulWidget {
  const ArtifactTransferRuntime({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<ArtifactTransferRuntime> createState() =>
      _ArtifactTransferRuntimeState();
}

class _ArtifactTransferRuntimeState
    extends ConsumerState<ArtifactTransferRuntime>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    scheduleMicrotask(_maintain);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _maintain();
  }

  void _maintain() {
    if (!mounted) return;
    unawaited(
      ref.read(artifactTransferControllerProvider.notifier).maintenance(),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(appLockProvider, (previous, next) {
      if (next.ready &&
          !next.locked &&
          !next.busy &&
          (previous == null || !previous.ready || previous.locked)) {
        _maintain();
      }
    });
    return widget.child;
  }
}

final class _DigestSink implements Sink<Digest> {
  Digest? value;
  @override
  void add(Digest data) => value = data;
  @override
  void close() {}
}
