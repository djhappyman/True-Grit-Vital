import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../backup/backup_service.dart';
import '../domain/backup/backup.dart';
import '../domain/artifact_transfer.dart';
import 'artifact_transfer.dart';
import 'app_lock.dart';
import 'storage.dart';

final backupDestinationProvider = Provider<BackupDestinationGateway>(
  ArtifactBackupDestination.new,
);

/// Streams the authenticated archive through the same bounded staging used
/// by reports and exports, preserving its reviewed length and checksum.
final class ArtifactBackupDestination implements BackupDestinationGateway {
  ArtifactBackupDestination(this.ref);
  final Ref ref;
  @override
  bool get supported =>
      ref.read(artifactTransferGatewayProvider).capabilities.save;

  @override
  Future<BackupSaveStatus> save(BackupArtifact artifact) async {
    if (artifact.byteCount >
        ref.read(artifactTransferGatewayProvider).capabilities.maxBytes) {
      throw const BackupFailure('backup_save_limit');
    }
    final outcome = await ref
        .read(artifactTransferControllerProvider.notifier)
        .save(
          ArtifactSource(
            kind: ArtifactKind.backup,
            byteCount: artifact.byteCount,
            fileName: artifact.name,
            expectedSha256: artifact.sha256,
            openRead: artifact.file.openRead,
          ),
        );
    if (outcome.completed) return BackupSaveStatus.saved;
    if (outcome.cancelled) return BackupSaveStatus.cancelled;
    throw const BackupFailure('backup_save_failed');
  }
}

String backupStagingPath(String databasePath) =>
    '${File(databasePath).parent.path}/backup-staging';

final backupStagingDirectoryProvider = Provider<Directory?>((ref) {
  final store = ref.watch(recordStoreProvider).value;
  return store == null
      ? null
      : Directory(backupStagingPath(store.databasePath));
});

final backupOperationsProvider = Provider<BackupOperations?>((ref) {
  final store = ref.watch(recordStoreProvider).value;
  final directory = ref.watch(backupStagingDirectoryProvider);
  if (store == null || directory == null) return null;
  return BackupService(
    recordStore: store,
    stagingDirectory: directory,
    destination: ref.watch(backupDestinationProvider),
  );
});

enum BackupPhase {
  idle,
  preparing,
  encrypting,
  verifying,
  ready,
  saving,
  saved,
  failed,
  cancelled,
}

/// Truthful outcome of the awaited staged-archive release used before a
/// data change. Anything but [released] must stop the change.
enum BackupRelease {
  /// The panel no longer owns a staged artifact and its deletion settled.
  released,

  /// Other or newer panel work owns the creation; nothing was deleted.
  busy,

  /// The deletion failed; the creation stays owned and normally retryable.
  failed,
}

/// One deletion this controller started on its own staged archive. A
/// settled failure is retained so the next release can retry it truthfully
/// instead of treating it as safely done.
final class _PendingDeletion {
  _PendingDeletion(this.creation, this.operations, {this.gate});

  final BackupCreation creation;

  /// The operations that produced and own the artifact; never swapped for
  /// a rebuilt backend.
  final BackupOperations operations;

  /// The save handoff still reading the archive when the deletion was
  /// released, if any. The deletion waits for it so a reset, lock or
  /// rebuild never deletes the file underneath an in-flight OS save.
  final Future<void>? gate;

  Completer<bool> settled = Completer<bool>();
  bool failed = false;

  Future<bool> get future => settled.future;
}

/// The OS handoff this controller owns for its staged archive. While it
/// runs, the archive is being saved: cleanup of staged work refuses, and a
/// released deletion waits through [future] instead of racing the save.
final class _ActiveSave {
  _ActiveSave(this.creation, this.operations);

  final BackupCreation creation;
  final BackupOperations operations;
  final Completer<void> settled = Completer<void>();

  Future<void> get future => settled.future;
}

/// One create attempt from start to its final hand-off: reaching the panel,
/// or a stale or cancelled outcome releasing its staged artifact through
/// the tracker. Retained until then so a data change cannot claim the
/// capture's staged work is safe while the capture is still live.
final class _ActiveCapture {
  final Completer<void> settled = Completer<void>();

  Future<void> get future => settled.future;
}

final class BackupState {
  const BackupState({
    this.phase = BackupPhase.idle,
    this.completedBytes = 0,
    this.totalBytes = 0,
    this.errorCode,
    this.creation,
    this.savedName,
  });

  final BackupPhase phase;
  final int completedBytes, totalBytes;
  final String? errorCode;
  final BackupCreation? creation;
  final String? savedName;

  bool get busy =>
      phase == BackupPhase.preparing ||
      phase == BackupPhase.encrypting ||
      phase == BackupPhase.verifying ||
      phase == BackupPhase.saving;

  double? get fraction =>
      totalBytes > 0 ? (completedBytes / totalBytes).clamp(0, 1) : null;

  BackupState copyWith({
    BackupPhase? phase,
    int? completedBytes,
    int? totalBytes,
    String? errorCode,
    BackupCreation? creation,
    String? savedName,
    bool clearError = false,
    bool clearCreation = false,
    bool clearSavedName = false,
  }) => BackupState(
    phase: phase ?? this.phase,
    completedBytes: completedBytes ?? this.completedBytes,
    totalBytes: totalBytes ?? this.totalBytes,
    errorCode: clearError ? null : (errorCode ?? this.errorCode),
    creation: clearCreation ? null : (creation ?? this.creation),
    savedName: clearSavedName ? null : (savedName ?? this.savedName),
  );
}

final backupProvider = NotifierProvider<BackupController, BackupState>(
  BackupController.new,
);

class BackupController extends Notifier<BackupState> {
  BackupOperations? _operations;
  BackupCancellationToken? _token;
  int _epoch = 0;

  /// Operations that produced the creation currently offered in state.
  /// Cleanup always uses these, so a replaced backend never deletes with
  /// the wrong staging directory.
  BackupOperations? _creationOperations;

  /// Mirror of the creation offered in [BackupState]; every state update
  /// that adds or clears a creation keeps these in step.
  BackupCreation? _heldCreation;

  /// Every deletion this controller started on its own staged artifacts:
  /// direct discards, janitorial releases through reset/lock/rebuild and
  /// awaited data-change releases. Each entry keeps its own originating
  /// operations and settles with true when that artifact was actually
  /// deleted. Successful entries are removed; a failed one is retained so
  /// the next release retries truthfully instead of treating a cleared
  /// panel as proof that its artifact is gone.
  final List<_PendingDeletion> _pendingDeletions = [];

  /// The save handoff the controller currently owns for its staged
  /// archive, if any. A released deletion waits for it instead of
  /// deleting the file underneath the OS save.
  _ActiveSave? _activeSave;

  /// Create attempts the controller owns from start to final hand-off.
  /// A capture that lock or rebuild cleared from the panel is still live
  /// here, so a data change cannot treat a null panel as proof that the
  /// captured artifact is settled.
  final List<_ActiveCapture> _activeCaptures = [];

  @override
  BackupState build() {
    _token?.cancel();
    // A rebuild replaces the panel: any held ready creation is still a
    // pending staging artifact, so release it with the same fencing the
    // lock uses instead of leaking it.
    final held = _heldCreation;
    _releaseCreation(held);
    ref.onDispose(() => _token?.cancel());
    ref.listen(appLockProvider.select((state) => state.locked), (_, locked) {
      if (locked) {
        _token?.cancel();
        _epoch++;
        final creation = state.creation;
        state = const BackupState();
        _releaseCreation(creation);
      }
    });
    _operations = ref.watch(backupOperationsProvider);
    _epoch++;
    _token = null;
    return const BackupState();
  }

  bool _current(int epoch) => ref.mounted && epoch == _epoch;

  /// Drops an owned creation from the controller while handing its staged
  /// archive to the operations that created it. The deletion is started
  /// (or shared, when one is already running for the same creation) and
  /// kept observable, so a later data-change preparation can never report
  /// a released panel while that deletion is unsettled or failed.
  void _releaseCreation(BackupCreation? creation) {
    final operations = _creationOperations;
    _heldCreation = null;
    _creationOperations = null;
    if (creation == null || operations == null) return;
    for (final pending in _pendingDeletions) {
      if (identical(pending.creation, creation)) return;
    }
    _startDeletion(creation, operations);
  }

  void _clearCreation() {
    _heldCreation = null;
    _creationOperations = null;
  }

  /// Starts the deletion for [creation] on exactly [operations] and keeps
  /// it observable until it settles. When a save handoff is still reading
  /// the same archive, the deletion is gated on that handoff instead of
  /// deleting the file underneath it.
  _PendingDeletion _startDeletion(
    BackupCreation creation,
    BackupOperations operations,
  ) {
    final activeSave = _activeSave;
    final gate = activeSave != null && identical(activeSave.creation, creation)
        ? activeSave.future
        : null;
    final pending = _PendingDeletion(creation, operations, gate: gate);
    _pendingDeletions.add(pending);
    unawaited(_run(pending));
    return pending;
  }

  /// Finds this controller's originated deletion for [creation]: one
  /// already running is shared on the exact same future, and only a failed
  /// one is restarted. Every discard and every release call the same
  /// sharing path, so a repeated request never duplicates the delete.
  _PendingDeletion _shareDeletion(
    BackupCreation creation,
    BackupOperations operations,
  ) {
    for (final pending in _pendingDeletions) {
      if (identical(pending.creation, creation)) {
        if (pending.failed) _restartDeletion(pending);
        return pending;
      }
    }
    return _startDeletion(creation, operations);
  }

  void _restartDeletion(_PendingDeletion pending) {
    pending
      ..failed = false
      ..settled = Completer<bool>();
    unawaited(_run(pending));
  }

  /// Settles [pending] with the actual deletion outcome. While the panel
  /// still offers the same creation and no newer work superseded it, a
  /// success clears the panel and a failure keeps the creation retryable
  /// with the normal backup error state; a newer attempt is never touched.
  Future<void> _run(_PendingDeletion pending) async {
    final gate = pending.gate;
    if (gate != null) {
      // The OS handoff owns the file until it settles; the deletion waits
      // for it and stays observable as unsettled the whole time.
      await gate;
    }
    final epoch = _epoch;
    bool deleted;
    try {
      await pending.operations.discard(pending.creation);
      deleted = true;
    } catch (_) {
      deleted = false;
    }
    pending.failed = !deleted;
    if (deleted) _pendingDeletions.remove(pending);
    if (ref.mounted &&
        epoch == _epoch &&
        identical(state.creation, pending.creation)) {
      if (deleted) {
        state = const BackupState();
        _clearCreation();
      } else {
        // Preserve the creation so the deletion can be retried truthfully.
        state = state.copyWith(
          phase: BackupPhase.ready,
          errorCode: 'backup_failed',
        );
      }
    }
    pending.settled.complete(deleted);
  }

  bool get available => _operations != null;
  bool get canSave => _operations?.destinationSupported ?? false;

  static String? passwordError(String password, String confirmation) {
    if (password != confirmation) return 'backup_password_mismatch';
    try {
      BackupLimits.checkPassword(password);
    } on BackupFailure catch (failure) {
      return failure.code;
    }
    return null;
  }

  Future<void> create({
    required String password,
    required String confirmation,
  }) async {
    if (state.busy || ref.read(appLockProvider).locked) return;
    final operations = _operations;
    if (operations == null) {
      state = state.copyWith(
        phase: BackupPhase.failed,
        errorCode: 'backup_unavailable',
      );
      return;
    }
    final previous = state.creation;
    final error = passwordError(password, confirmation);
    if (error != null) {
      state = state.copyWith(
        phase: BackupPhase.idle,
        errorCode: error,
        clearCreation: true,
        clearSavedName: true,
      );
      _releaseCreation(previous);
      return;
    }
    final epoch = ++_epoch;
    final token = BackupCancellationToken();
    _token = token;
    // The capture is owned from here to its final hand-off: even when a
    // lock or rebuild clears the panel while it runs, a data change waits
    // for it instead of treating the staged artifact as settled.
    final capture = _ActiveCapture();
    _activeCaptures.add(capture);
    state = const BackupState(phase: BackupPhase.preparing);
    _releaseCreation(previous);
    try {
      final creation = await operations.createBackup(
        password: password,
        token: token,
        onProgress: (progress) {
          if (!_current(epoch)) return;
          state = state.copyWith(
            phase: switch (progress.stage) {
              BackupStage.snapshot ||
              BackupStage.inspect => BackupPhase.preparing,
              BackupStage.encrypt => BackupPhase.encrypting,
              BackupStage.verify => BackupPhase.verifying,
            },
            completedBytes: progress.completedBytes,
            totalBytes: progress.totalBytes,
            clearError: true,
          );
        },
      );
      if (!_current(epoch)) {
        // A stale capture cannot keep the panel: release its staged
        // artifact through the tracked path and finish the attempt. The
        // deletion stays observable, so a data change waits for it instead
        // of claiming the capture's work is safe.
        _shareDeletion(creation, operations);
        return;
      }
      if (token.isCancelled) {
        // Same tracked release; the failure stays retained for a truthful
        // retry while the attempt reports cancellation to the panel.
        _shareDeletion(creation, operations);
        throw const BackupFailure('backup_cancelled');
      }
      state = state.copyWith(
        phase: BackupPhase.ready,
        completedBytes: creation.byteCount,
        totalBytes: creation.byteCount,
        creation: creation,
        clearError: true,
      );
      _heldCreation = creation;
      _creationOperations = operations;
    } on BackupFailure catch (failure) {
      if (!_current(epoch)) return;
      final cancelled = failure.code == 'backup_cancelled';
      state = state.copyWith(
        phase: cancelled ? BackupPhase.cancelled : BackupPhase.failed,
        errorCode: failure.code,
        clearCreation: true,
        clearSavedName: true,
      );
    } catch (_) {
      if (!_current(epoch)) return;
      state = state.copyWith(
        phase: BackupPhase.failed,
        errorCode: 'backup_failed',
        clearCreation: true,
        clearSavedName: true,
      );
    } finally {
      if (_current(epoch)) _token = null;
      // The capture's final hand-off is done: either the panel owns the
      // creation or the staged artifact settled through the tracker.
      _activeCaptures.remove(capture);
      capture.settled.complete();
    }
  }

  void cancel() => _token?.cancel();

  /// True while this controller still owns a deletion for [creation],
  /// running or retained after a failure. The archive is being deleted or
  /// left over from a failed deletion, so saving it would read a file the
  /// controller is destroying.
  bool _ownsDeletion(BackupCreation creation) =>
      _pendingDeletions.any((pending) => identical(pending.creation, creation));

  Future<void> save() async {
    final creation = state.creation;
    // The save always runs on the operations that staged the artifact: a
    // replaced backend must never be handed an archive it did not create.
    final operations = _creationOperations ?? _operations;
    if (creation == null ||
        operations == null ||
        state.busy ||
        ref.read(appLockProvider).locked ||
        _ownsDeletion(creation)) {
      return;
    }
    final epoch = ++_epoch;
    final activeSave = _ActiveSave(creation, operations);
    _activeSave = activeSave;
    state = state.copyWith(phase: BackupPhase.saving, clearError: true);
    try {
      final result = await operations.save(creation);
      if (!_current(epoch)) return;
      state = result == BackupSaveStatus.saved
          ? state.copyWith(
              phase: BackupPhase.saved,
              savedName: creation.fileName,
              clearCreation: true,
              clearError: true,
            )
          : state.copyWith(phase: BackupPhase.ready);
      if (result == BackupSaveStatus.saved) _clearCreation();
    } on BackupFailure catch (failure) {
      if (!_current(epoch)) return;
      state = state.copyWith(phase: BackupPhase.ready, errorCode: failure.code);
    } catch (_) {
      if (!_current(epoch)) return;
      state = state.copyWith(
        phase: BackupPhase.ready,
        errorCode: 'backup_save_failed',
      );
    } finally {
      // The handoff no longer reads the archive: released deletions may
      // run, and a new data change stops being refused on its account.
      if (identical(_activeSave, activeSave)) _activeSave = null;
      activeSave.settled.complete();
    }
  }

  Future<void> discard() async {
    final creation = state.creation;
    final operations = _creationOperations;
    if (creation == null || operations == null || state.busy) return;
    // Share the running deletion instead of duplicating it and wait for
    // its actual outcome. The shared entry drives the retry and
    // cleared-state semantics for every caller of the same creation.
    final pending = _shareDeletion(creation, operations);
    await pending.future;
  }

  /// Releases the staged archive owned by this panel during data-change
  /// preparation, awaiting the actual deletion instead of leaving one
  /// open. Every deletion this controller originated is drained: the
  /// panel's own creation and any janitorial release/reset/lock/rebuild
  /// deletion. A settled failure is retried once per call and retained
  /// until its deletion actually succeeds. The deletion always runs on
  /// the operations that originated the creation, and one already running
  /// is shared rather than duplicated.
  ///
  /// [BackupRelease.busy] also covers live owned work outside the panel:
  /// an in-flight create capture, an in-flight save handoff, and any
  /// deletion released while the drain was running (including a later
  /// reset of a newer capture). None of it is discarded by this release
  /// and none of it is claimed safe; a repeated call may drain what was
  /// refused here.
  ///
  /// [BackupRelease.released] is only returned once the panel no longer
  /// owns a staged artifact and every originated deletion settled
  /// truthfully. [BackupRelease.failed] keeps the panel's creation exactly
  /// as [discard] leaves it, still retryable there. [BackupRelease.busy]
  /// means newer or other panel work owns the flow; callers must not erase
  /// data on it because a late completion can never discard a newer
  /// attempt or pretend the change is safe.
  Future<BackupRelease> releaseForDataChange() async {
    if (!ref.mounted) return BackupRelease.busy;
    if (state.busy) return BackupRelease.busy;
    if (_activeSave != null || _activeCaptures.isNotEmpty) {
      // A capture or save handoff still owns staged work; the change must
      // not claim safety while it is live, even if the panel was cleared.
      return BackupRelease.busy;
    }
    final target = state.creation;
    final epoch = _epoch;
    if (target == null && _pendingDeletions.isEmpty) {
      return BackupRelease.released;
    }
    final entries = <_PendingDeletion>[];
    if (target != null) {
      final operations = _creationOperations;
      if (operations == null) return BackupRelease.failed;
      entries.add(_shareDeletion(target, operations));
    }
    for (final pending in _pendingDeletions) {
      if (entries.contains(pending)) continue;
      if (pending.failed) _restartDeletion(pending);
      entries.add(pending);
    }
    final outcomes = await Future.wait([
      for (final pending in entries) pending.future,
    ]);
    if (!ref.mounted) return BackupRelease.busy;
    if (state.busy) return BackupRelease.busy;
    if (epoch != _epoch) {
      return BackupRelease.busy;
    }
    if (_activeSave != null || _activeCaptures.isNotEmpty) {
      return BackupRelease.busy;
    }
    // Work released while this drain ran is newer owned work: it is never
    // discarded here and never claimed safe; a repeated call may drain it.
    for (final pending in _pendingDeletions) {
      if (!entries.contains(pending)) return BackupRelease.busy;
    }
    final current = state.creation;
    final allDeleted = outcomes.every((outcome) => outcome);
    if (current == null) {
      // The panel is clear; with everything actually deleted the change is
      // safe, otherwise a retained failed deletion keeps the change blocked.
      return allDeleted ? BackupRelease.released : BackupRelease.failed;
    }
    if (target == null || !identical(current, target)) {
      // A newer attempt or different panel work owns the flow now.
      return BackupRelease.busy;
    }
    if (!allDeleted) {
      // Keep the creation so the deletion can be retried truthfully.
      state = state.copyWith(
        phase: BackupPhase.ready,
        errorCode: 'backup_failed',
      );
      return BackupRelease.failed;
    }
    state = const BackupState();
    _clearCreation();
    return BackupRelease.released;
  }

  void reset() {
    if (state.busy) return;
    final previous = state.creation;
    state = const BackupState();
    _releaseCreation(previous);
  }
}

/// Cleans known abandoned staging files and expired backup pins early in app
/// startup. It never creates, decrypts or activates a backup.
class BackupRuntime extends ConsumerStatefulWidget {
  const BackupRuntime({super.key, required this.child});
  final Widget child;
  @override
  ConsumerState<BackupRuntime> createState() => _BackupRuntimeState();
}

class _BackupRuntimeState extends ConsumerState<BackupRuntime> {
  @override
  void initState() {
    super.initState();
    unawaited(_cleanup());
  }

  Future<void> _cleanup() async {
    try {
      final store = await ref.read(recordStoreProvider.future);
      await BackupService(
        recordStore: store,
        stagingDirectory: Directory(backupStagingPath(store.databasePath)),
        destination: ref.read(backupDestinationProvider),
      ).cleanupAbandoned(olderThan: Duration.zero);
    } catch (_) {
      // Storage recovery keeps its own truthful state; staging cleanup retries
      // on the next successful launch or backup completion.
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
