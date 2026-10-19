import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:true_grit_vital/app/app_lock.dart';
import 'package:true_grit_vital/app/attachments.dart';
import 'package:true_grit_vital/app/storage.dart';
import 'package:true_grit_vital/data/record_store.dart';
import 'package:true_grit_vital/platform/attachments.dart';

Future<AttachmentRecord> seedFile(
  RecordStore store,
  SubstanceItem item,
  Uint8List bytes,
) async {
  final job = AttachmentJob(
    id: newCommandId(),
    generation: store.generation,
    personId: item.personId,
    expectedPersonRevision: 1,
    targetKind: AttachmentTargetKind.item,
    targetId: item.id,
    targetRevision: item.revision,
    attachmentId: newCommandId(),
    versionId: newCommandId(),
    name: 'Original.bin',
    createdAt: DateTime.now().toUtc(),
  );
  await store.beginAttachment(
    BeginAttachmentCommand(commandId: newCommandId(), job: job),
  );
  await store.appendAttachmentChunk(
    commandId: newCommandId(),
    jobId: job.id,
    generation: job.generation,
    offset: 0,
    bytes: bytes,
  );
  final inspection = await const AttachmentMediaDecoder().inspect(bytes);
  return store.publishAttachment(
    commandId: newCommandId(),
    jobId: job.id,
    generation: job.generation,
    inspection: inspection,
    name: job.name,
  );
}

class RecoveryLock extends AppLockController {
  @override
  AppLockState build() => const AppLockState(ready: true, locked: false);
  void setLocked(bool locked) =>
      state = AppLockState(ready: true, locked: locked);
}

class InventoryGateway
    implements AttachmentGateway, AttachmentPickerRecoveryGateway {
  String? inventory;
  String status = 'pending';
  bool failRead = false, failFinish = false;
  final picked = <String>[], finished = <String>[];
  Uint8List source = Uint8List.fromList([1, 2, 3]);
  @override
  AttachmentCapabilities get capabilities => const AttachmentCapabilities(
    pickFile: true,
    photo: true,
    camera: false,
    share: true,
    save: false,
  );
  AttachmentSelection selection(String id) => AttachmentSelection(
    jobId: id,
    name: 'Original.bin',
    byteCount: source.length,
    openRead: () => failRead
        ? Stream.error(
            const AttachmentFailure('attachment_picker_source_unavailable'),
          )
        : Stream.value(source),
  );
  @override
  Future<String?> pendingJobId() async => inventory;
  @override
  Future<AttachmentSelection?> pickFile({required String jobId}) async {
    if (inventory != null) {
      throw const AttachmentFailure('attachment_picker_busy');
    }
    inventory = jobId;
    status = 'selected';
    picked.add(jobId);
    return selection(jobId);
  }

  @override
  Future<AttachmentSelection?> pickPhoto({
    required String jobId,
    bool camera = false,
  }) => pickFile(jobId: jobId);
  @override
  Future<AttachmentSelection?> recoverSelection({required String jobId}) async {
    if (inventory != jobId) return null;
    return status == 'selected' ? selection(jobId) : null;
  }

  @override
  Future<void> finishSelection(String jobId) async {
    if (failFinish) {
      failFinish = false;
      throw const AttachmentFailure('attachment_picker_recovery');
    }
    finished.add(jobId);
    if (inventory == jobId) inventory = null;
  }

  @override
  Future<bool> save({
    required String name,
    required String mime,
    required Uint8List bytes,
  }) async => false;
}

class FaultHandoff implements AttachmentHandoffGateway {
  FaultHandoff(this.clock);
  final DateTime Function() clock;
  final artifacts = <String, DateTime>{};
  final offered = <String>{};
  bool failBegin = false,
      failShare = false,
      uncertainShare = false,
      failCleanup = false;
  int cancels = 0, cleanups = 0;
  @override
  Future<void> begin({
    required String id,
    required String name,
    required String mime,
    required DateTime expiresAt,
  }) async {
    if (failBegin) throw const AttachmentFailure('attachment_handoff_capacity');
    artifacts[id] = expiresAt;
  }

  @override
  Future<int> append({
    required String id,
    required int offset,
    required Uint8List bytes,
  }) async => offset + bytes.length;
  @override
  Future<void> publish({
    required String id,
    required int byteCount,
    required String sha256,
  }) async {}
  @override
  Future<bool> share(String id) async {
    if (uncertainShare) offered.add(id);
    if (failShare || uncertainShare) {
      throw const AttachmentFailure('attachment_handoff_unavailable');
    }
    offered.add(id);
    return true;
  }

  @override
  Future<bool> cancel(String id) async {
    cancels++;
    if (!artifacts.containsKey(id)) {
      throw const AttachmentFailure('attachment_handoff_missing');
    }
    if (offered.contains(id)) return false;
    artifacts.remove(id);
    return true;
  }

  @override
  Future<List<String>> cleanup() async {
    cleanups++;
    if (failCleanup) {
      throw const AttachmentFailure('attachment_handoff_unavailable');
    }
    final expired = artifacts.entries
        .where((e) => !e.value.isAfter(clock()))
        .map((e) => e.key)
        .toList();
    for (final id in expired) {
      artifacts.remove(id);
      offered.remove(id);
    }
    return expired;
  }
}

Future<void> until(FutureOr<bool> Function() condition) async {
  final watch = Stopwatch()..start();
  while (!await condition()) {
    if (watch.elapsed > const Duration(seconds: 5)) {
      throw StateError('attachment_condition_timeout');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late RecordStore store;
  late SubstanceItem item;
  late ProviderContainer container;
  late ProviderSubscription<AttachmentRuntimeState> subscription;
  Timer? expiryTicker;
  late InventoryGateway gateway;
  late FaultHandoff handoff;
  late DateTime now;
  AttachmentsController getController() =>
      container.read(attachmentsControllerProvider.notifier);
  ({int pins, int chunks}) retainedCounts() {
    final raw = sqlite3.open('${directory.path}/records.db');
    try {
      raw.execute("PRAGMA cipher='chacha20'");
      final hex = List.generate(
        32,
        (i) => i + 1,
      ).map((v) => v.toRadixString(16).padLeft(2, '0')).join();
      raw.execute('PRAGMA key="x\'$hex\'"');
      return (
        pins:
            raw.select('SELECT COUNT(*) n FROM attachment_pin').single['n']
                as int,
        chunks:
            raw.select('SELECT COUNT(*) n FROM attachment_chunk').single['n']
                as int,
      );
    } finally {
      raw.close();
    }
  }

  Future<void> start({Duration interval = const Duration(hours: 1)}) async {
    container = ProviderContainer(
      overrides: [
        storeLoaderProvider.overrideWithValue(() async => store),
        appLockProvider.overrideWith(RecoveryLock.new),
        attachmentGatewayProvider.overrideWithValue(gateway),
        attachmentHandoffProvider.overrideWithValue(handoff),
        attachmentClockProvider.overrideWithValue(() => now),
        attachmentCleanupIntervalProvider.overrideWithValue(interval),
      ],
    );
    await container.read(recordStoreProvider.future);
    subscription = container.listen(attachmentsControllerProvider, (_, _) {});
    await Future<void>.delayed(Duration.zero);
    await until(() => !container.read(attachmentsControllerProvider).busy);
    await getController().recover();
    if (interval < const Duration(hours: 1)) {
      expiryTicker = Timer.periodic(
        interval,
        (_) => unawaited(getController().maintenance()),
      );
    }
  }

  Future<AttachmentJob> job(String id) async {
    final job = AttachmentJob(
      id: id,
      generation: store.generation,
      personId: meId,
      expectedPersonRevision: 1,
      targetKind: AttachmentTargetKind.item,
      targetId: item.id,
      targetRevision: item.revision,
      attachmentId: 'attachment-$id',
      versionId: 'version-$id',
      name: 'Attachment',
      createdAt: DateTime.now().toUtc(),
    );
    await store.beginAttachment(
      BeginAttachmentCommand(commandId: 'begin-$id', job: job),
    );
    return job;
  }

  Future<void> erase(AttachmentRecord record) => store.deleteAttachment(
    commandId: newCommandId(),
    attachment: record,
    expectedPersonRevision: 1,
  );
  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'vital-attachment-controller-',
    );
    store = await RecordStore.open(
      path: '${directory.path}/records.db',
      key: List.generate(32, (i) => i + 1),
      isNew: true,
    );
    item = await store.createItem(
      commandId: 'item',
      name: 'Saved medicine',
      form: 'tablet',
      unit: 'mg',
      type: 'Medicine',
    );
    now = DateTime.now().toUtc();
    gateway = InventoryGateway();
    handoff = FaultHandoff(() => now);
  });
  tearDown(() async {
    expiryTicker?.cancel();
    expiryTicker = null;
    subscription.close();
    container.dispose();
    await store.close();
    await directory.delete(recursive: true);
  });

  for (final status in ['pending', 'cancelled']) {
    test(
      'Resume replaces stale $status inventory before allocating a picker',
      () async {
        final pending = await job(status);
        gateway.inventory = pending.id;
        gateway.status = status;
        await start();
        await getController().resume(pending);
        expect(gateway.picked, [pending.id]);
        expect(gateway.finished, contains(pending.id));
        expect(gateway.inventory, isNull);
        expect(
          (await store.attachments(personId: meId)).single.name,
          'Original.bin',
        );
        expect(container.read(attachmentsControllerProvider).busy, isFalse);
      },
    );
  }
  test('selected inventory is imported once through recovery without reopening picker', () async {
    final pending = await job('selected');
    gateway.inventory = pending.id;
    gateway.status = 'selected';
    await store.close();
    store = await RecordStore.open(
      path: '${directory.path}/records.db',
      key: List.generate(32, (i) => i + 1),
      isNew: false,
    );
    await start();
    expect(gateway.picked, isEmpty);
    expect(gateway.inventory, isNull);
    expect(await store.attachments(personId: meId), hasLength(1));
    await getController().recover();
    expect(await store.attachments(personId: meId), hasLength(1));
  });
  test('profile deletion reconciles orphan inventory during the same controller lifetime', () async {
    final pending = await job('deleted-owner');
    gateway.inventory = pending.id;
    await start();
    expect(gateway.inventory, pending.id);
    await store.deleteProfile(
      commandId: 'delete-owner',
      personId: meId,
      expectedRevision: 1,
    );
    await until(() => gateway.inventory == null);
    expect(gateway.finished, contains(pending.id));
    expect(await store.pendingAttachmentJobs(), isEmpty);
    expect(container.read(attachmentsControllerProvider).busy, isFalse);
  });
  test('failed import releases external selection and leaves a resumable fixed job', () async {
    final pending = await job('bad-read');
    gateway.failRead = true;
    await start();
    await getController().resume(pending);
    expect(gateway.inventory, isNull);
    expect(await store.pendingAttachmentJobs(), hasLength(1));
    gateway.failRead = false;
    await getController().resume((await store.attachmentJob(pending.id))!);
    expect(await store.attachments(personId: meId), hasLength(1));
    expect(gateway.picked, [pending.id, pending.id]);
  });
  test(
    'failed picker cleanup is retried rather than leaving Resume busy forever',
    () async {
      final pending = await job('failed-finish');
      gateway.inventory = pending.id;
      gateway.status = 'cancelled';
      await start();
      gateway.failFinish = true;
      await getController().resume(pending);
      expect(container.read(attachmentsControllerProvider).busy, isFalse);
      await getController().resume(pending);
      expect(gateway.inventory, isNull);
      expect(await store.attachments(personId: meId), hasLength(1));
    },
  );
  for (final failure in ['begin', 'share']) {
    test('$failure failure releases its unoffered protected pin', () async {
      final record = await seedFile(store, item, Uint8List.fromList([1, 2, 3]));
      await start();
      handoff.failBegin = failure == 'begin';
      handoff.failShare = failure == 'share';
      await getController().handoff(record, save: false);
      expect(handoff.artifacts, isEmpty);
      if (failure == 'begin') expect(handoff.cancels, 1);
      expect(container.read(attachmentsControllerProvider).busy, isFalse);
      await erase(record);
      expect(retainedCounts(), (pins: 0, chunks: 0));
    });
  }
  test('already-offered handoff remains pinned on an uncertain later share failure', () async {
    final record = await seedFile(store, item, Uint8List.fromList([1, 2, 3]));
    await start();
    handoff.uncertainShare = true;
    await getController().handoff(record, save: false);
    expect(handoff.artifacts, hasLength(1));
    await erase(record);
    expect(retainedCounts(), (pins: 1, chunks: 1));
    now = now.add(const Duration(hours: 24, minutes: 1));
    await getController().maintenance();
    expect(handoff.artifacts, isEmpty);
    expect(retainedCounts(), (pins: 0, chunks: 0));
  });
  test('periodic expiry reclaims deleted content without restarting the controller', () async {
    final record = await seedFile(store, item, Uint8List.fromList([1, 2, 3]));
    await start(interval: const Duration(milliseconds: 30));
    await getController().handoff(record, save: false);
    await erase(record);
    expect(retainedCounts(), (pins: 1, chunks: 1));
    now = now.add(const Duration(hours: 24, minutes: 1));
    await until(() => retainedCounts() == (pins: 0, chunks: 0));
    expect(handoff.artifacts, isEmpty);
    await until(() => !container.read(attachmentsControllerProvider).busy);
  });
  test('locked expiry releases expired handoffs without reopening protected reads or abandoning a live pin', () async {
    final record = await seedFile(store, item, Uint8List.fromList([1, 2, 3]));
    await start();
    await getController().handoff(record, save: false);
    final live = await store.pinAttachment(
      id: record.id,
      generation: store.generation,
      expectedRevision: record.revision,
      purpose: 'preview',
      sessionId: 'other-live-session',
    );
    await erase(record);
    store.suspendWrites(true);
    (container.read(appLockProvider.notifier) as RecoveryLock).setLocked(true);
    now = now.add(const Duration(hours: 24, minutes: 1));
    final picks = gateway.picked.length;
    await getController().maintenance();
    expect(handoff.artifacts, isEmpty);
    expect(retainedCounts(), (pins: 1, chunks: 1));
    expect(gateway.picked, hasLength(picks));
    await expectLater(
      store.attachmentById(record.id),
      throwsA(isA<CommandConflict>()),
    );
    await store.releaseAttachmentPin(live);
    expect(retainedCounts(), (pins: 0, chunks: 0));
  });
  test(
    'expiry repair is bounded to 256 pins per call and works while locked',
    () async {
      final record = await seedFile(store, item, Uint8List.fromList([1, 2, 3]));
      await start();
      final expires = DateTime.now().toUtc().add(const Duration(minutes: 1));
      for (var index = 0; index < 257; index++) {
        await store.pinAttachment(
          id: record.id,
          generation: store.generation,
          expectedRevision: record.revision,
          purpose: 'handoff',
          expiresAt: expires,
        );
      }
      await erase(record);
      store.suspendWrites(true);
      await expectLater(
        store.expireAttachmentPins(now: expires),
        throwsA(
          isA<AttachmentFailure>().having(
            (e) => e.code,
            'code',
            'attachment_cleanup_pending',
          ),
        ),
      );
      expect(retainedCounts(), (pins: 1, chunks: 1));
      await store.expireAttachmentPins(now: expires);
      expect(retainedCounts(), (pins: 0, chunks: 0));
    },
  );
  test(
    'native cleanup failure cannot prevent locked protected-pin expiry',
    () async {
      final record = await seedFile(store, item, Uint8List.fromList([1, 2, 3]));
      await start();
      await getController().handoff(record, save: false);
      await erase(record);
      handoff.failCleanup = true;
      now = now.add(const Duration(hours: 24, minutes: 1));
      store.suspendWrites(true);
      (container.read(appLockProvider.notifier) as RecoveryLock).setLocked(
        true,
      );
      await getController().maintenance();
      expect(retainedCounts(), (pins: 0, chunks: 0));
      expect(handoff.artifacts, hasLength(1));
      handoff.failCleanup = false;
      await getController().maintenance();
      expect(handoff.artifacts, isEmpty);
    },
  );
}
