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

  /// Creation whose deletion is currently in flight. Fences a repeated
  /// delete request and lets the lock path skip an already running one.
  BackupCreation? _discarding;

  /// Settles with true when the staged artifact of [_discarding] was
  /// deleted and false when that deletion failed, so callers sharing the
  /// in-flight deletion observe its actual outcome instead of issuing a
  /// duplicate delete.
  Completer<bool>? _deletion;

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
  /// archive to the operations that created it. A deletion already running
  /// for the same creation is left alone; its stale completion is rejected
  /// by the fenced [discard].
  void _releaseCreation(BackupCreation? creation) {
    final operations = _creationOperations;
    _heldCreation = null;
    _creationOperations = null;
    if (creation == null || operations == null) return;
    if (identical(_discarding, creation)) return;
    unawaited(operations.discard(creation).catchError((Object _) {}));
  }

  void _clearCreation() {
    _heldCreation = null;
    _creationOperations = null;
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
        await operations.discard(creation);
        return;
      }
      if (token.isCancelled) {
        await operations.discard(creation);
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
    }
  }

  void cancel() => _token?.cancel();

  Future<void> save() async {
    final creation = state.creation;
    final operations = _operations;
    if (creation == null ||
        operations == null ||
        state.busy ||
        ref.read(appLockProvider).locked) {
      return;
    }
    final epoch = ++_epoch;
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
    }
  }

  Future<void> discard() async {
    final creation = state.creation;
    final operations = _creationOperations;
    if (creation == null || operations == null || state.busy) return;
    if (identical(_discarding, creation)) {
      // Share the running deletion instead of duplicating it. Whoever
      // started it already drives the retry and cleared-state semantics.
      await _deletion!.future;
      return;
    }
    _discarding = creation;
    final deletion = _deletion = Completer<bool>();
    final epoch = _epoch;
    try {
      await operations.discard(creation);
      deletion.complete(true);
      if (!_current(epoch) || !identical(state.creation, creation)) return;
      state = const BackupState();
      _clearCreation();
    } catch (_) {
      deletion.complete(false);
      if (!_current(epoch) || !identical(state.creation, creation)) return;
      // Preserve the creation so the deletion can be retried truthfully.
      state = state.copyWith(
        phase: BackupPhase.ready,
        errorCode: 'backup_failed',
      );
    } finally {
      if (identical(_discarding, creation)) {
        _discarding = null;
        _deletion = null;
      }
    }
  }

  /// Releases the staged archive owned by this panel during data-change
  /// preparation, awaiting the actual deletion instead of leaving one open.
  /// The deletion always runs on the operations that originated the offered
  /// creation, and one already running is shared rather than duplicated.
  ///
  /// [BackupRelease.released] is only returned once the panel no longer
  /// owns a staged artifact and its deletion settled truthfully.
  /// [BackupRelease.failed] keeps the creation exactly as [discard] leaves
  /// it, still retryable there. [BackupRelease.busy] means other or newer
  /// panel work owns the flow; callers must not erase data on it because a
  /// late completion can never discard a newer attempt or pretend the
  /// change is safe.
  Future<BackupRelease> releaseForDataChange() async {
    if (state.busy) return BackupRelease.busy;
    final creation = state.creation;
    if (creation == null) return BackupRelease.released;
    if (identical(_discarding, creation)) {
      // Share the in-flight deletion; a same-file delete must never race.
      final settled = await _deletion!.future;
      return _releaseOutcome(creation, deleted: settled);
    }
    final operations = _creationOperations;
    if (operations == null) return BackupRelease.failed;
    _discarding = creation;
    final deletion = _deletion = Completer<bool>();
    bool deleted = false;
    try {
      await operations.discard(creation);
      deleted = true;
      deletion.complete(true);
    } catch (_) {
      deletion.complete(false);
    } finally {
      if (identical(_discarding, creation)) {
        _discarding = null;
        _deletion = null;
      }
    }
    return _releaseOutcome(creation, deleted: deleted);
  }

  /// Observes the settled panel for [creation]. A still offered creation is
  /// cleared on success or kept retryable on failure; a panel that moved to
  /// other owned work is never touched.
  BackupRelease _releaseOutcome(
    BackupCreation creation, {
    required bool deleted,
  }) {
    if (!ref.mounted) return BackupRelease.busy;
    if (identical(state.creation, creation)) {
      if (state.busy) return BackupRelease.busy;
      if (deleted) {
        state = const BackupState();
        _clearCreation();
        return BackupRelease.released;
      }
      // Keep the creation so the deletion can be retried truthfully.
      state = state.copyWith(
        phase: BackupPhase.ready,
        errorCode: 'backup_failed',
      );
      return BackupRelease.failed;
    }
    if (state.busy || state.creation != null) {
      // A newer attempt or different panel work owns the flow now.
      return BackupRelease.busy;
    }
    // The panel moved on while the deletion ran: the outcome is the fate
    // of the artifact itself, never a claim about newer work.
    return deleted ? BackupRelease.released : BackupRelease.failed;
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
