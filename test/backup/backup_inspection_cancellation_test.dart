import 'dart:io';
import 'dart:async';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:true_grit_vital/backup/backup_service.dart';
import 'package:true_grit_vital/data/record_store.dart';
import 'package:true_grit_vital/domain/backup/backup.dart';

/// Regression: a cancellation command during the inspecting/quantity scan of a
/// capture or restore validation used to be silently unhooured until the whole
/// scan finished. The token now bounds the scan itself; a cancelled scan stops
/// before further re-hashing, releases its pins with the capture and preserves
/// the live dataset and any previous saved output.
void main() {
  late Directory directory;
  late RecordStore store;
  late BackupService service;
  final key = List.generate(32, (i) => i + 5);
  const password = 'synthetic backup password 73';

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('vital-backup-cancel-');
    store = await RecordStore.open(
      path: '${directory.path}/records.db',
      key: key,
      isNew: true,
    );
    service = BackupService(
      recordStore: store,
      stagingDirectory: Directory('${directory.path}/staging'),
      clock: () => DateTime.utc(2026, 10, 20, 12),
    );
    final item = await store.createItem(
      commandId: 'inspect-item',
      name: 'Synthetic inspection item',
      form: 'tablet',
      unit: 'count',
      type: 'medicine',
    );
    await store.record(
      commandId: 'inspect-record',
      itemId: item.id,
      amount: '3',
      actualAt: DateTime.utc(2026, 10, 20, 7),
    );
    await _attachment(store, 'cancel-attachment-1', item.id, 192);
    await _attachment(store, 'cancel-attachment-2', item.id, 192);
  });

  tearDown(() async {
    await store.close();
    await directory.delete(recursive: true);
  });

  List<String> stagingNames() {
    final target = service.stagingDirectory;
    if (!target.existsSync()) return const [];
    return target
        .listSync()
        .map((entry) => entry.path.split(Platform.pathSeparator).last)
        .toList();
  }

  test(
    'cancelling a validation scan fails closed and keeps the live dataset',
    () async {
      final token = BackupCancellationToken();
      final source = await Directory('${directory.path}/source').create();
      final snapshot = await store.createBackupSnapshot(
        directory: source,
        sessionId: 'cancelscan',
      );
      final scan = store.inspectOwnSnapshot(snapshot, token: token);
      // Cancel while the scan is still awaiting its row/chunk work, in the
      // same event loop turn as the scan, so no digest can be reported after
      // the cancellation command.
      Timer(const Duration(), token.cancel);
      final datasetBefore = (await store.records()).length;
      await expectLater(scan, throwsA(_Cancelled()));

      // The caller of a failed scan releases the capture pins for its session;
      // records and attachments above stay intact and untouched.
      await store.releaseBackupPins('cancelscan');
      expect(await store.records(), hasLength(datasetBefore));

      // The interrupted evaluation left no additional snapshot besides the
      // file the test created, and cleanup could not touch it.
      expect(stagingNames(), isEmpty);

      // The dataset that cancelled a validation stays fully usable.
      final retry = await service.createBackup(
        password: password,
        token: BackupCancellationToken(),
      );
      expect(retry.inventory.attachmentCount, 2);
      expect(retry.inventory.recordCount, 1);
      await service.discard(retry);
      expect(stagingNames(), isEmpty);
    },
  );

  test('an already cancelled validation opens no dataset', () async {
    final token = BackupCancellationToken();
    token.cancel();
    await expectLater(
      store.inspectOwnSnapshot(
        BackupSnapshotFile(
          path: '${directory.path}/missing.db',
          generation: 'cancel-generation-placeholder',
          schemaVersion: 21,
          byteCount: 8192,
          sha256: '0${'a' * 63}',
        ),
        token: token,
      ),
      throwsA(_Cancelled()),
    );
  });

  test(
    'a capture cancelled at the inspect stage reports no ready archive',
    () async {
      final token = BackupCancellationToken();
      Object? failure;
      try {
        await service.createBackup(
          password: password,
          token: token,
          onProgress: (progress) {
            if (progress.stage == BackupStage.inspect) {
              // The command must land either inside the scan or directly
              // after it; both keep staging clean and never report ready.
              token.cancel();
            }
          },
        );
      } on BackupFailure catch (error) {
        failure = error;
      }
      expect(failure, isA<BackupFailure>());
      expect(
        (failure! as BackupFailure).code,
        'backup_cancelled',
        reason: 'a cancelled capture is never reported ready',
      );
      expect(
        stagingNames().where((name) => name.endsWith('.vitalbackup')),
        isEmpty,
        reason: 'a cancelled capture deletes its own archive',
      );
      await service.cleanupAbandoned(olderThan: Duration.zero);
      expect(stagingNames(), isEmpty);

      // A completed previous capture stays usable for saving afterwards.
      final previous = await service.createBackup(
        password: password,
        token: BackupCancellationToken(),
      );
      expect(previous.inventory.attachmentCount, 2);
      await service.discard(previous);
    },
  );

  test(
    'restore validation honours a pre-cancelled token without staging',
    () async {
      final archive = await service.createBackup(
        password: password,
        token: BackupCancellationToken(),
      );
      final file = File(archive.archive.path);
      await service.discard(archive);
      final token = BackupCancellationToken();
      token.cancel();
      await expectLater(
        service.validateArchive(
          archive: file,
          password: password,
          token: token,
        ),
        throwsA(_Cancelled()),
      );
      expect(
        stagingNames().where((name) => name.startsWith('snapshot-')),
        isEmpty,
      );
    },
  );
}

final class _Cancelled extends Matcher {
  @override
  bool matches(Object? item, Map<Object?, Object?> matchState) =>
      item is BackupFailure && item.code == 'backup_cancelled';
  @override
  Description describe(Description description) =>
      description.add('BackupFailure(backup_cancelled)');
}

Future<void> _attachment(
  RecordStore store,
  String id,
  String itemId,
  int kib,
) async {
  final bytes = Uint8List.fromList(List.generate(kib * 1024, (i) => i % 251));
  final inspection = AttachmentInspection(
    mediaKind: AttachmentMediaKind.other,
    byteCount: bytes.length,
    sha256: sha256.convert(bytes).toString(),
    mimeType: 'application/octet-stream',
  );
  final job = AttachmentJob(
    id: '$id-job',
    generation: store.generation,
    personId: meId,
    expectedPersonRevision: 1,
    targetKind: AttachmentTargetKind.item,
    targetId: itemId,
    targetRevision: 1,
    attachmentId: id,
    versionId: '$id-version',
    name: 'Synthetic source $id',
    createdAt: DateTime.utc(2026, 10, 20),
  );
  await store.beginAttachment(
    BeginAttachmentCommand(commandId: '$id-begin', job: job),
  );
  for (var offset = 0; offset < bytes.length; offset += 64 * 1024) {
    final end = (offset + 64 * 1024).clamp(0, bytes.length);
    await store.appendAttachmentChunk(
      commandId: '$id-chunk-$offset',
      jobId: job.id,
      generation: store.generation,
      offset: offset,
      bytes: bytes.sublist(offset, end),
    );
  }
  await store.publishAttachment(
    commandId: '$id-publish',
    jobId: job.id,
    generation: store.generation,
    inspection: inspection,
  );
}
