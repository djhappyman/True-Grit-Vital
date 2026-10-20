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

  @override
  BackupState build() {
    _token?.cancel();
    ref.onDispose(() => _token?.cancel());
    ref.listen(appLockProvider.select((state) => state.locked), (_, locked) {
      if (locked) {
        _token?.cancel();
        _epoch++;
        final creation = state.creation;
        final operations = _operations;
        state = const BackupState();
        if (creation != null && operations != null) {
          unawaited(operations.discard(creation).catchError((Object _) {}));
        }
      }
    });
    _operations = ref.watch(backupOperationsProvider);
    _epoch++;
    _token = null;
    return const BackupState();
  }

  bool _current(int epoch) => ref.mounted && epoch == _epoch;

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
    final error = passwordError(password, confirmation);
    if (error != null) {
      state = state.copyWith(
        phase: BackupPhase.idle,
        errorCode: error,
        clearCreation: true,
        clearSavedName: true,
      );
      return;
    }
    final epoch = ++_epoch;
    final token = BackupCancellationToken();
    _token = token;
    state = const BackupState(phase: BackupPhase.preparing);
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
    final operations = _operations;
    if (creation == null || operations == null || state.busy) return;
    try {
      await operations.discard(creation);
      if (ref.mounted) state = const BackupState();
    } catch (_) {
      if (ref.mounted) {
        state = state.copyWith(
          phase: BackupPhase.ready,
          errorCode: 'backup_failed',
        );
      }
    }
  }

  void reset() {
    if (state.busy) return;
    state = const BackupState();
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
