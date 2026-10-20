import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/backup/backup.dart';
import '../domain/restore/restore.dart';
import '../restore/backup_restore_source.dart';
import '../restore/restore_activation.dart';
import '../restore/restore_archive_picker.dart';
import '../restore/restore_intake.dart';
import 'reminders.dart';
import 'storage.dart';
import 'app_lock.dart';
import 'generated_artifacts.dart';
import 'restore_notice.dart';

/// Truthful null means restore cannot run on this host or the store is still
/// loading. The page disables the flow rather than showing a no-op control.
final restoreGatewayProvider = Provider<RestoreGateway?>((ref) {
  final store = ref.watch(recordStoreProvider).value;
  if (store == null) return null;
  final dataDirectory = File(store.databasePath).parent;
  return BackupRestoreGateway(
    store: store,
    intake: RestoreArchiveIntake(
      picker: const PlatformRestoreArchivePicker(),
      directory: Directory(
        '${dataDirectory.path}/${RestoreLimits.restoreDirectory}',
      ),
    ),
    activation: RestoreActivation(databasePath: store.databasePath),
    stagingDirectory: Directory('${dataDirectory.path}/backup-staging'),
    beforeActivate: () async {
      if (ref.read(appLockProvider).locked) {
        throw const RestoreFailure(RestoreCodes.locked);
      }
      try {
        await prepareGeneratedArtifactsForDataChange(ref);
      } catch (_) {
        throw const RestoreFailure(RestoreCodes.busy);
      }
      if (ref.read(appLockProvider).locked) {
        throw const RestoreFailure(RestoreCodes.locked);
      }
    },
    onOutcome: (outcome) => ref
        .read(restoreRecoveryNoticeProvider.notifier)
        .record(
          RestoreRecovery(
            outcome: RestoreRecoveryOutcome.completed,
            generation: outcome.result.newGeneration,
            reason: outcome.remindersInvalidated ? null : 'reminder_warning',
          ),
        ),
    invalidateReminders:
        ({
          required String previousNamespace,
          required String reminderNamespace,
        }) async {
          final reminders = ref.read(reminderGatewayProvider);
          try {
            final capabilities = await reminders.capabilities();
            if (!capabilities.supported) return true;
            return await reminders.invalidateEpoch(
              oldEpoch: previousNamespace,
              newEpoch: reminderNamespace,
            );
          } catch (_) {
            return false;
          }
        },
    onRefresh: () async {
      if (ref.mounted) ref.invalidate(recordStoreProvider);
    },
  );
});

enum RestorePhase {
  idle,
  choosing,
  checking,
  preview,
  preparing,
  replacing,
  complete,
  failed,
  cancelled,
}

final class RestoreState {
  const RestoreState({
    this.phase = RestorePhase.idle,
    this.fileName,
    this.preview,
    this.progress,
    this.errorCode,
    this.confirmed = false,
    this.outcome,
    this.reminderWarning = false,
  });

  final RestorePhase phase;
  final String? fileName;
  final RestorePreview? preview;
  final RestoreProgress? progress;
  final String? errorCode;
  final bool confirmed;
  final RestoreActivationOutcome? outcome;
  final bool reminderWarning;

  bool get busy =>
      phase == RestorePhase.choosing ||
      phase == RestorePhase.checking ||
      phase == RestorePhase.preparing ||
      phase == RestorePhase.replacing;

  bool get canCancelCheck => phase == RestorePhase.checking;

  double? get fraction => progress?.fraction;

  RestoreState copyWith({
    RestorePhase? phase,
    String? fileName,
    RestorePreview? preview,
    RestoreProgress? progress,
    String? errorCode,
    bool? confirmed,
    RestoreActivationOutcome? outcome,
    bool? reminderWarning,
    bool clearError = false,
    bool clearPreview = false,
    bool clearProgress = false,
    bool clearOutcome = false,
    bool clearFileName = false,
  }) => RestoreState(
    phase: phase ?? this.phase,
    fileName: clearFileName ? null : (fileName ?? this.fileName),
    preview: clearPreview ? null : (preview ?? this.preview),
    progress: clearProgress ? null : (progress ?? this.progress),
    errorCode: clearError ? null : (errorCode ?? this.errorCode),
    confirmed: confirmed ?? this.confirmed,
    outcome: clearOutcome ? null : (outcome ?? this.outcome),
    reminderWarning: reminderWarning ?? this.reminderWarning,
  );
}

final restoreProvider =
    NotifierProvider.autoDispose<RestoreController, RestoreState>(
      RestoreController.new,
    );

/// Orchestrates one restore attempt. The gateway is read at call time so a
/// successful replacement, which rebuilds the store provider, does not reset
/// the completed state underneath the user.
class RestoreController extends Notifier<RestoreState> {
  RestorePick? _pick;
  RestoreArchive? _archive;
  RestoreGateway? _gatewayCache;
  BackupCancellationToken? _token;
  int _epoch = 0;
  bool _activating = false;

  @override
  RestoreState build() {
    _epoch++;
    ref.listen(appLockProvider.select((state) => state.locked), (_, locked) {
      if (locked && !_activating) {
        _token?.cancel();
        _epoch++;
        unawaited(_discardDetached());
        state = const RestoreState();
      }
    });
    ref.onDispose(() {
      _token?.cancel();
      if (_activating) return;
      unawaited(_discardDetached());
    });
    return const RestoreState();
  }

  RestoreGateway? get _gateway {
    final gateway = ref.read(restoreGatewayProvider);
    _gatewayCache = gateway;
    return gateway;
  }

  bool _current(int epoch) =>
      ref.mounted && epoch == _epoch && !ref.read(appLockProvider).locked;

  bool get available => _gateway?.supported ?? false;

  Future<void> choose() async {
    if (state.busy || _activating || ref.read(appLockProvider).locked) return;
    final gateway = _gateway;
    if (gateway == null || !gateway.supported) {
      state = state.copyWith(
        phase: RestorePhase.failed,
        errorCode: RestoreCodes.unavailable,
      );
      return;
    }
    final epoch = ++_epoch;
    state = state.copyWith(
      phase: RestorePhase.choosing,
      clearError: true,
      clearPreview: true,
      clearOutcome: true,
      clearProgress: true,
      confirmed: false,
    );
    await _discard();
    try {
      final pick = await gateway.chooseArchive();
      if (!_current(epoch)) {
        if (pick != null) await gateway.discardPick(pick);
        return;
      }
      if (pick == null) {
        state = state.copyWith(phase: RestorePhase.idle);
        return;
      }
      _pick = pick;
      state = state.copyWith(
        phase: RestorePhase.idle,
        fileName: pick.name,
        clearError: true,
      );
    } catch (error) {
      if (!_current(epoch)) return;
      state = state.copyWith(
        phase: RestorePhase.failed,
        errorCode: restoreErrorCode(error),
      );
    }
  }

  Future<void> check(String password) async {
    if (state.busy || _activating || ref.read(appLockProvider).locked) return;
    final gateway = _gateway;
    final pick = _pick;
    if (gateway == null || !gateway.supported) {
      state = state.copyWith(
        phase: RestorePhase.failed,
        errorCode: RestoreCodes.unavailable,
      );
      return;
    }
    if (pick == null) {
      state = state.copyWith(errorCode: RestoreCodes.chooseArchive);
      return;
    }
    if (password.isEmpty) {
      state = state.copyWith(errorCode: RestoreCodes.passwordRequired);
      return;
    }
    if (utf8.encode(password).length > RestoreLimits.maxPasswordBytes) {
      state = state.copyWith(errorCode: RestoreCodes.passwordLong);
      return;
    }
    final epoch = ++_epoch;
    final token = BackupCancellationToken();
    _token = token;
    await _discardArchive();
    state = state.copyWith(
      phase: RestorePhase.checking,
      clearError: true,
      clearPreview: true,
      clearOutcome: true,
      confirmed: false,
      progress: const RestoreProgress(stage: RestoreProgressStage.checking),
    );
    try {
      final archive = await gateway.validateArchive(
        pick: pick,
        password: password,
        token: token,
        onProgress: (progress) {
          if (_current(epoch)) {
            state = state.copyWith(progress: progress);
          }
        },
      );
      if (!_current(epoch)) {
        await gateway.discardArchive(archive);
        return;
      }
      if (token.isCancelled) {
        await gateway.discardArchive(archive);
        throw const BackupFailure('backup_cancelled');
      }
      if (!archive.inventory.singleUserCompatible) {
        await gateway.discardArchive(archive);
        throw const RestoreFailure(RestoreCodes.multiplePeople);
      }
      _archive = archive;
      _pick = null;
      state = state.copyWith(
        phase: RestorePhase.preview,
        preview: restorePreviewFor(
          archive: archive,
          fileName: pick.name,
          currentSchemaVersion: gateway.currentSchemaVersion,
        ),
        clearProgress: true,
      );
    } catch (error) {
      if (!_current(epoch)) return;
      if (isRestoreCancellation(error)) {
        state = state.copyWith(
          phase: RestorePhase.idle,
          clearProgress: true,
          clearError: true,
        );
      } else {
        state = state.copyWith(
          phase: RestorePhase.failed,
          errorCode: restoreErrorCode(error),
          clearProgress: true,
        );
      }
      await _discardArchive();
    } finally {
      if (_token == token) _token = null;
    }
  }

  void cancelCheck() {
    _token?.cancel();
  }

  void setConfirmed(bool value) {
    if (state.phase != RestorePhase.preview) return;
    state = state.copyWith(confirmed: value);
  }

  /// Returns to the chooser after a safe failure. A still-valid intake copy is
  /// kept so the user can correct the password without picking the file again.
  void retry() {
    if (state.phase != RestorePhase.failed &&
        state.phase != RestorePhase.cancelled) {
      return;
    }
    final pick = _pick;
    if (pick == null) {
      unawaited(reset());
      return;
    }
    state = RestoreState(phase: RestorePhase.idle, fileName: pick.name);
  }

  Future<void> replace() async {
    if (_activating || state.busy || ref.read(appLockProvider).locked) return;
    final gateway = _gateway;
    final archive = _archive;
    if (gateway == null || !gateway.supported) {
      state = state.copyWith(
        phase: RestorePhase.failed,
        errorCode: RestoreCodes.unavailable,
      );
      return;
    }
    if (state.phase != RestorePhase.preview || archive == null) return;
    if (!state.confirmed) {
      state = state.copyWith(errorCode: RestoreCodes.confirmationRequired);
      return;
    }
    final epoch = ++_epoch;
    _activating = true;
    state = state.copyWith(
      phase: RestorePhase.preparing,
      clearError: true,
      progress: const RestoreProgress(stage: RestoreProgressStage.preparing),
    );
    try {
      final prepared = await gateway.prepare(archive);
      if (!_current(epoch)) {
        await gateway.discardArchive(archive);
        return;
      }
      state = state.copyWith(
        phase: RestorePhase.replacing,
        progress: const RestoreProgress(stage: RestoreProgressStage.replacing),
      );
      final outcome = await gateway.activate(
        archive: archive,
        prepared: prepared,
        onProgress: (progress) {
          if (_current(epoch)) {
            state = state.copyWith(progress: progress);
          }
        },
      );
      if (outcome.result.newGeneration == prepared.generation) {
        _archive = null;
        _pick = null;
      }
      if (_current(epoch)) {
        state = state.copyWith(
          phase: RestorePhase.complete,
          outcome: outcome,
          reminderWarning: !outcome.remindersInvalidated,
          clearProgress: true,
        );
      }
    } catch (error) {
      if (_current(epoch)) {
        state = state.copyWith(
          phase: isRestoreCancellation(error)
              ? RestorePhase.cancelled
              : RestorePhase.failed,
          errorCode: restoreErrorCode(error),
          clearProgress: true,
        );
      }
      await _discardArchive();
    } finally {
      _activating = false;
    }
  }

  Future<void> reset() async {
    if (_activating) return;
    _epoch++;
    await _discard();
    if (ref.mounted) state = const RestoreState();
  }

  Future<void> _discardArchive() async {
    final archive = _archive;
    _archive = null;
    if (archive != null) {
      try {
        await archive.discard();
      } catch (_) {
        // The startup recovery pass removes known staging names.
      }
    }
  }

  Future<void> _discard() async {
    final gateway = _gateway;
    final pick = _pick;
    _pick = null;
    await _discardArchive();
    if (gateway != null && pick != null) {
      try {
        await gateway.discardPick(pick);
      } catch (_) {
        // The startup recovery pass removes the fixed intake name.
      }
    }
  }

  /// Dispose-safe cleanup: never reads Riverpod after disposal.
  Future<void> _discardDetached() async {
    final pick = _pick;
    _pick = null;
    await _discardArchive();
    final gateway = _gatewayCache;
    if (gateway != null && pick != null) {
      try {
        await gateway.discardPick(pick);
      } catch (_) {
        // The startup recovery pass removes the fixed intake name.
      }
    }
  }
}
