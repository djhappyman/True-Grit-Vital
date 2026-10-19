import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/widgets.dart'
    show AppLifecycleState, WidgetsBinding, WidgetsBindingObserver;
import 'package:shadcn_flutter/shadcn_flutter.dart'
    show Widget, BuildContext, Locale;

import '../data/record_store.dart';
import '../l10n/app_localizations.dart';
import '../platform/attachments.dart';
import 'app_lock.dart';
import 'storage.dart';

final attachmentGatewayProvider = Provider<AttachmentGateway>(
  (ref) => defaultAttachmentGateway(
    dialogTitle: lookupAppLocalizations(const Locale('en', 'GB')).attachments,
  ),
);
final attachmentMediaProvider = Provider<AttachmentMediaDecoder>(
  (ref) => defaultAttachmentMediaDecoder(),
);
final attachmentHandoffProvider = Provider<AttachmentHandoffGateway>(
  (ref) => defaultAttachmentHandoffGateway(),
);
final attachmentSessionProvider = Provider<String>((ref) {
  ref.watch(recordStoreProvider.select((value) => value.value?.generation));
  return newCommandId();
});
final attachmentClockProvider = Provider<DateTime Function()>(
  (_) =>
      () => DateTime.now().toUtc(),
);
final attachmentCleanupIntervalProvider = Provider<Duration>(
  (_) => const Duration(minutes: 1),
);

class AttachmentRuntimeState {
  const AttachmentRuntimeState({
    this.busy = false,
    this.jobId,
    this.failureCode,
    this.notice,
  });
  final bool busy;
  final String? jobId, failureCode, notice;
}

final attachmentsControllerProvider =
    NotifierProvider<AttachmentsController, AttachmentRuntimeState>(
      AttachmentsController.new,
    );

/// Picker work keeps its durable captured job even when the visible feed changes.
class AttachmentsController extends Notifier<AttachmentRuntimeState> {
  RecordStore? _store;
  int _epoch = 0;
  bool _recovered = false;
  ({AttachmentJob job, AttachmentSelection selection})? _pending;
  AttachmentJob? _cancelPending;
  Future<void>? _reconciling;
  Future<void>? _maintenance;
  bool get _unlocked {
    if (!ref.mounted) return false;
    final lock = ref.read(appLockProvider);
    return lock.ready && !lock.locked && !lock.busy;
  }

  bool _current(int epoch) => ref.mounted && epoch == _epoch;
  @override
  AttachmentRuntimeState build() {
    _store = ref.watch(recordStoreProvider).value;
    ref.watch(attachmentGatewayProvider);
    ref.watch(attachmentMediaProvider);
    ref.watch(attachmentSessionProvider);
    final epoch = ++_epoch;
    _recovered = false;
    _pending = null;
    _cancelPending = null;
    _reconciling = null;
    _maintenance = null;
    final subscription = _store?.watchAttachmentJobs().listen(
      (_) {
        if (_current(epoch) && _unlocked) {
          unawaited(
            _reconcilePicker().catchError((Object error) {
              if (_current(epoch) && !state.busy) _failure(error);
            }),
          );
        }
      },
      onError: (Object _) {}, // Unlock recovery retries protected reads.
    );
    ref.onDispose(() {
      unawaited(subscription?.cancel());
    });
    ref.listen(appLockProvider, (_, next) {
      if (next.ready && !next.locked) unawaited(maintenance());
    });
    scheduleMicrotask(() {
      if (_current(epoch)) unawaited(recover());
    });
    return const AttachmentRuntimeState();
  }

  String _code(Object error) => error is AttachmentFailure
      ? error.code
      : error is CommandConflict
      ? error.code
      : 'attachment_failed';
  void _failure(Object error, {String? jobId}) {
    if (ref.mounted) {
      state = AttachmentRuntimeState(jobId: jobId, failureCode: _code(error));
    }
  }

  Future<void> _validate(AttachmentJob job) async {
    final store = _store!;
    if (store.generation != job.generation) {
      throw const CommandConflict('generation');
    }
    final owner = await store.profileById(job.personId);
    if (owner == null ||
        owner.isArchived ||
        owner.revision != job.expectedPersonRevision) {
      throw const CommandConflict('person_context');
    }
    if (job.targetKind == AttachmentTargetKind.item) {
      final item = await store.itemById(job.targetId, personId: job.personId);
      if (item == null || item.revision != job.targetRevision) {
        throw const CommandConflict('attachment_target_revision');
      }
    } else if (job.targetKind == AttachmentTargetKind.record) {
      final record = await store.recordById(
        job.targetId,
        personId: job.personId,
      );
      if (record == null ||
          record.isVoided ||
          record.revision != job.targetRevision) {
        throw const CommandConflict('attachment_target_revision');
      }
    } else {
      final supporting = await store.supportingRecord(
        job.personId,
        job.targetId,
      );
      if (supporting == null ||
          supporting.isVoided ||
          supporting.revision != job.targetRevision) {
        throw const CommandConflict('attachment_target_revision');
      }
    }
    if (!_unlocked) throw const CommandConflict('app_locked');
  }

  Future<void> _reconcilePicker() async {
    if (_store == null || !_unlocked) return;
    if (_reconciling case final running?) return running;
    final gateway = ref.read(attachmentGatewayProvider),
        store = _store!,
        epoch = _epoch;
    if (gateway is! AttachmentPickerRecoveryGateway) return;
    final work = () async {
      final nativeId = await (gateway as AttachmentPickerRecoveryGateway)
          .pendingJobId();
      if (nativeId == null || !_current(epoch) || !_unlocked) return;
      final original = await store.attachmentJob(nativeId);
      if (!_current(epoch) || !_unlocked) return;
      if (original == null ||
          original.generation != store.generation ||
          original.state == AttachmentJobState.ready ||
          original.state == AttachmentJobState.cancelled) {
        await gateway.finishSelection(nativeId);
      }
    }();
    _reconciling = work;
    try {
      await work;
    } finally {
      if (identical(_reconciling, work)) _reconciling = null;
    }
  }

  /// Expiry is independent of one-time startup repair. Native cleanup is safe
  /// while locked; protected reads/imports remain behind the unlock boundary.
  Future<void> maintenance() async {
    if (_maintenance case final running?) return running;
    final work = _maintain();
    _maintenance = work;
    try {
      await work;
    } finally {
      if (identical(_maintenance, work)) _maintenance = null;
    }
  }

  Future<void> _maintain() async {
    if (_store == null) return;
    final epoch = _epoch;
    Object? cleanupFailure;
    try {
      if (ref.read(attachmentGatewayProvider).capabilities.share) {
        try {
          await ref.read(attachmentHandoffProvider).cleanup();
        } catch (error) {
          cleanupFailure = error;
        }
      }
      if (!_current(epoch)) return;
      for (var batch = 0; batch < 4; batch++) {
        try {
          await _store!.expireAttachmentPins(
            now: ref.read(attachmentClockProvider)(),
          );
          break;
        } on AttachmentFailure catch (error) {
          if (error.code != 'attachment_cleanup_pending') rethrow;
          await Future<void>.delayed(Duration.zero);
          if (!_current(epoch)) return;
        }
      }
      if (!_current(epoch) || !_unlocked) return;
      await _reconcilePicker();
      if (_current(epoch) && !state.busy) {
        if (cleanupFailure != null) {
          _failure(cleanupFailure);
        } else {
          await recover();
        }
      }
    } catch (error) {
      if (_current(epoch) && _unlocked && !state.busy) _failure(error);
    }
  }

  Future<void> recover() async {
    if (_store == null || !_unlocked || state.busy) return;
    final epoch = _epoch,
        store = _store!,
        gateway = ref.read(attachmentGatewayProvider);
    final previous = state;
    state = const AttachmentRuntimeState(busy: true);
    try {
      if (!_recovered) {
        while (true) {
          try {
            await store.recoverAttachmentState(
              sessionId: ref.read(attachmentSessionProvider),
            );
            break;
          } on AttachmentFailure catch (failure) {
            if (failure.code != 'attachment_cleanup_pending') rethrow;
          }
          await Future<void>.delayed(Duration.zero);
          if (!_current(epoch)) return;
          if (!_unlocked) {
            state = const AttachmentRuntimeState(notice: 'interrupted');
            return;
          }
        }
        if (!_current(epoch)) return;
        if (gateway.capabilities.share) {
          await ref.read(attachmentHandoffProvider).cleanup();
        }
        _recovered = true;
      }
      await _reconcilePicker();
      if (_cancelPending case final job?) {
        _cancelPending = null;
        await _cancel(job);
      }
      if (_pending case final pending?) {
        _pending = null;
        await _import(pending.job, pending.selection);
        return;
      }
      final jobs = await store.pendingAttachmentJobs();
      for (final job in jobs) {
        if (!_current(epoch)) return;
        if (!_unlocked) {
          state = const AttachmentRuntimeState(notice: 'interrupted');
          return;
        }
        await _validate(job);
        if (!gateway.capabilities.pickFile && !gateway.capabilities.photo) {
          continue;
        }
        final selection = await gateway.recoverSelection(jobId: job.id);
        if (!_current(epoch)) return;
        if (selection != null) {
          await _import(job, selection);
          return;
        }
      }
      if (_current(epoch) && state.busy) {
        state = AttachmentRuntimeState(
          notice: previous.notice,
          failureCode: previous.failureCode,
        );
      }
    } catch (error) {
      if (_current(epoch)) _failure(error);
    }
  }

  Future<void> begin({
    required String personId,
    required int personRevision,
    required AttachmentTargetKind targetKind,
    required String targetId,
    required int targetRevision,
    required AttachmentPickerKind pickerKind,
  }) async {
    if (state.busy || !_unlocked || _store == null) return;
    final store = _store!, epoch = _epoch;
    final job = AttachmentJob(
      id: newCommandId(),
      generation: store.generation,
      personId: personId,
      expectedPersonRevision: personRevision,
      targetKind: targetKind,
      targetId: targetId,
      targetRevision: targetRevision,
      attachmentId: newCommandId(),
      versionId: newCommandId(),
      name: 'Attachment',
      createdAt: DateTime.now().toUtc(),
      pickerKind: pickerKind,
    );
    state = AttachmentRuntimeState(busy: true, jobId: job.id);
    try {
      await store.beginAttachment(
        BeginAttachmentCommand(commandId: '${job.id}:begin', job: job),
      );
      if (!_current(epoch)) return;
      await _pick(job);
    } catch (error) {
      if (_current(epoch)) _failure(error, jobId: job.id);
    }
  }

  Future<void> resume(AttachmentJob job) async {
    if (state.busy || !_unlocked || _store == null) return;
    state = AttachmentRuntimeState(busy: true, jobId: job.id);
    try {
      await _validate(job);
      await _pick(job);
    } catch (error) {
      _failure(error, jobId: job.id);
    }
  }

  Future<void> _pick(AttachmentJob job) async {
    final epoch = _epoch;
    final gateway = ref.read(attachmentGatewayProvider);
    await _validate(job);
    await _reconcilePicker();
    if (!_current(epoch)) return;
    if (gateway is AttachmentPickerRecoveryGateway) {
      final nativeId = await (gateway as AttachmentPickerRecoveryGateway)
          .pendingJobId();
      if (nativeId != null) {
        if (nativeId == job.id) {
          final recovered = await gateway.recoverSelection(jobId: job.id);
          if (recovered != null) {
            await _import(job, recovered);
            return;
          }
        }
        // No live picker is running here: Resume/new Choose explicitly replaces
        // stale pending/cancelled inventory, releasing any prior URI grant.
        await gateway.finishSelection(nativeId);
      }
    }
    if (!_current(epoch)) return;
    if (!_unlocked) {
      state = AttachmentRuntimeState(jobId: job.id, notice: 'interrupted');
      return;
    }
    final selection = job.pickerKind == AttachmentPickerKind.file
        ? await gateway.pickFile(jobId: job.id)
        : await gateway.pickPhoto(
            jobId: job.id,
            camera: job.pickerKind == AttachmentPickerKind.camera,
          );
    if (!_current(epoch)) return;
    if (selection == null) {
      if (!_unlocked) {
        _cancelPending = job;
        state = AttachmentRuntimeState(jobId: job.id, notice: 'interrupted');
        return;
      }
      await _cancel(job);
      return;
    }
    await _import(job, selection);
  }

  Future<void> _import(
    AttachmentJob intended,
    AttachmentSelection selection,
  ) async {
    final epoch = _epoch,
        store = _store!,
        gateway = ref.read(attachmentGatewayProvider);
    if (selection.jobId != intended.id) {
      throw const AttachmentFailure('attachment_picker_context');
    }
    if (!_unlocked) {
      _pending = (job: intended, selection: selection);
      state = AttachmentRuntimeState(jobId: intended.id, notice: 'interrupted');
      return;
    }
    state = AttachmentRuntimeState(busy: true, jobId: intended.id);
    Uint8List? bytes;
    try {
      await _validate(intended);
      var job = (await store.attachmentJob(intended.id))!;
      if (job.state == AttachmentJobState.ready) {
        await gateway.finishSelection(job.id);
        await selection.dispose?.call();
        if (_current(epoch)) {
          state = AttachmentRuntimeState(jobId: job.id, notice: 'saved');
        }
        return;
      }
      if (job.receivedBytes > 0) {
        job = await store.restartAttachmentJob(
          commandId: newCommandId(),
          jobId: job.id,
          generation: job.generation,
        );
      }
      if (selection.byteCount > AttachmentLimits.maxInputBytes) {
        throw const AttachmentFailure('attachment_byte_limit');
      }
      bytes = await readAttachmentBytes(selection.openRead());
      if (!_current(epoch)) return;
      if (!_unlocked) {
        _pending = (job: job, selection: selection);
        state = AttachmentRuntimeState(jobId: job.id, notice: 'interrupted');
        return;
      }
      if (selection.byteCount >= 0 && selection.byteCount != bytes.length) {
        throw const AttachmentFailure('attachment_incomplete');
      }
      final inspection = await ref.read(attachmentMediaProvider).inspect(bytes);
      var offset = 0;
      await for (final chunk in boundedAttachmentChunks(Stream.value(bytes))) {
        if (!_current(epoch)) return;
        if (!_unlocked) {
          _pending = (job: job, selection: selection);
          state = AttachmentRuntimeState(jobId: job.id, notice: 'interrupted');
          return;
        }
        await store.appendAttachmentChunk(
          commandId: newCommandId(),
          jobId: job.id,
          generation: job.generation,
          offset: offset,
          bytes: chunk,
        );
        offset += chunk.length;
      }
      await store.publishAttachment(
        commandId: '${job.id}:publish',
        jobId: job.id,
        generation: job.generation,
        inspection: inspection,
        name: selection.name,
      );
      await gateway.finishSelection(job.id);
      await selection.dispose?.call();
      if (_current(epoch)) {
        state = AttachmentRuntimeState(jobId: job.id, notice: 'saved');
      }
    } catch (error) {
      if (_unlocked) {
        try {
          await gateway.finishSelection(intended.id);
          await selection.dispose?.call();
        } catch (_) {
          // The durable job and inventory reconciliation remain retryable.
        }
      }
      if (_current(epoch)) {
        if (!_unlocked &&
            error is CommandConflict &&
            error.code == 'app_locked') {
          _pending = (job: intended, selection: selection);
        }
        _failure(error, jobId: intended.id);
      }
    } finally {
      bytes?.fillRange(0, bytes.length, 0);
    }
  }

  Future<void> cancel(AttachmentJob job) async {
    if (state.busy || !_unlocked) return;
    state = AttachmentRuntimeState(busy: true, jobId: job.id);
    try {
      await _cancel(job);
    } catch (error) {
      _failure(error, jobId: job.id);
    }
  }

  Future<void> _cancel(AttachmentJob job) async {
    final store = _store!;
    if (store.generation != job.generation) {
      throw const CommandConflict('generation');
    }
    final gateway = ref.read(attachmentGatewayProvider);
    if (gateway.capabilities.pickFile || gateway.capabilities.photo) {
      await gateway.finishSelection(job.id);
    }
    if (await store.attachmentJob(job.id) != null) {
      await store.cancelAttachment(
        commandId: '${job.id}:cancel',
        jobId: job.id,
        generation: job.generation,
      );
    }
    state = AttachmentRuntimeState(jobId: job.id, notice: 'cancelled');
  }

  Future<void> handoff(
    AttachmentRecord attachment, {
    required bool save,
  }) async {
    if (state.busy || !_unlocked || _store == null) return;
    final store = _store!,
        epoch = _epoch,
        gateway = ref.read(attachmentGatewayProvider),
        platform = ref.read(attachmentHandoffProvider);
    state = const AttachmentRuntimeState(busy: true);
    AttachmentPin? pin;
    var retained = false;
    var begun = false;
    Uint8List? bytes;
    try {
      if (attachment.generation != store.generation) {
        throw const CommandConflict('generation');
      }
      final expiresAt = ref
          .read(attachmentClockProvider)()
          .toUtc()
          .add(AttachmentLimits.handoffLifetime);
      pin = await store.pinAttachment(
        id: attachment.id,
        generation: attachment.generation,
        expectedRevision: attachment.revision,
        purpose: save ? 'export' : 'handoff',
        sessionId: ref.read(attachmentSessionProvider),
        expiresAt: save ? null : expiresAt,
      );
      final source = pin.attachment, inspection = source.inspection!;
      final name = inspection.mediaKind == AttachmentMediaKind.pdf
          ? 'attachment.pdf'
          : inspection.mimeType == 'image/png'
          ? 'attachment.png'
          : inspection.mimeType == 'image/jpeg'
          ? 'attachment.jpg'
          : 'attachment.bin';
      if (save) {
        bytes = await readAttachmentBytes(store.readAttachmentPin(pin));
        if (!_current(epoch) || !_unlocked) {
          throw const CommandConflict('app_locked');
        }
        final saved = await gateway.save(
          name: name,
          mime: inspection.mimeType,
          bytes: bytes,
        );
        if (_current(epoch)) {
          state = AttachmentRuntimeState(
            notice: saved ? 'copySaved' : 'cancelled',
          );
        }
      } else {
        await platform.begin(
          id: pin.id,
          name: name,
          mime: inspection.mimeType,
          expiresAt: expiresAt,
        );
        begun = true;
        var offset = 0;
        await for (final chunk in store.readAttachmentPin(pin)) {
          if (!_current(epoch) || !_unlocked) {
            throw const CommandConflict('app_locked');
          }
          offset = await platform.append(
            id: pin.id,
            offset: offset,
            bytes: chunk,
          );
        }
        await platform.publish(
          id: pin.id,
          byteCount: inspection.byteCount,
          sha256: inspection.sha256,
        );
        if (!_unlocked) throw const CommandConflict('app_locked');
        final offered = await platform.share(pin.id);
        retained = offered || !await platform.cancel(pin.id);
        if (_current(epoch)) {
          state = AttachmentRuntimeState(
            notice: offered ? 'shared' : 'cancelled',
          );
        }
      }
    } catch (error) {
      if (!save && pin != null) {
        try {
          final cancelled = await platform.cancel(pin.id);
          retained = begun && !cancelled;
        } catch (_) {
          // A failed begin cannot have offered this fresh pin to a receiver.
          // Still attempt cancellation to remove any partially written entry.
          retained = begun;
        }
      }
      if (_current(epoch)) _failure(error);
    } finally {
      bytes?.fillRange(0, bytes.length, 0);
      if (pin != null && !retained) await store.releaseAttachmentPin(pin);
    }
  }
}

class AttachmentRuntime extends ConsumerStatefulWidget {
  const AttachmentRuntime({super.key, required this.child});
  final Widget child;
  @override
  ConsumerState<AttachmentRuntime> createState() => _AttachmentRuntimeState();
}

class _AttachmentRuntimeState extends ConsumerState<AttachmentRuntime>
    with WidgetsBindingObserver {
  Timer? _maintenanceTimer;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _maintenanceTimer = Timer.periodic(
      ref.read(attachmentCleanupIntervalProvider),
      (_) => unawaited(
        ref.read(attachmentsControllerProvider.notifier).maintenance(),
      ),
    );
  }

  @override
  void dispose() {
    _maintenanceTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(ref.read(attachmentsControllerProvider.notifier).maintenance());
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(attachmentsControllerProvider);
    return widget.child;
  }
}
