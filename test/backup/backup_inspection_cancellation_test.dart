import 'dart:io';
import 'dart:async';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:true_grit_vital/backup/backup_service.dart';
import 'package:true_grit_vital/data/record_store.dart';
import 'package:true_grit_vital/domain/backup/backup.dart';

/// Regression: a cancellation command during the inspecting/quantity scan of a
/// capture, restore validation or standalone inspection used to go unhonoured
/// until the whole scan had finished, so an abandoned command could still
/// report a complete inventory. Every awaited scan boundary now fails closed
/// on a cancelled token; the cancelled scans below therefore return no result,
/// keep the live dataset intact and leave no stray staging or archive behind.
const _quantityScanRevisions = 640;

/// Event-loop turns of awaited live-store reads ordered between starting the
/// standalone scan and issuing the cancellation command, calibrated so the
/// command lands inside the scan's awaited quantity/metadata region while it
/// is still running.
const _scanCancellationPacingTurns = 108;

void main() {
  late Directory directory;
  late RecordStore store;
  late BackupService service;
  late String itemId;
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
    itemId = item.id;
    await store.record(
      commandId: 'inspect-record',
      itemId: item.id,
      amount: '3',
      actualAt: DateTime.utc(2026, 10, 20, 7),
    );
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

  Future<void> seedAttachments() async {
    await _attachment(store, 'cancel-attachment-1', itemId, 192);
    await _attachment(store, 'cancel-attachment-2', itemId, 192);
  }

  test(
    'cancelling a validation scan fails closed and keeps the live dataset',
    () async {
      await seedAttachments();
      final token = BackupCancellationToken();
      final source = await Directory('${directory.path}/source').create();
      final snapshot = await store.createBackupSnapshot(
        directory: source,
        sessionId: 'cancelscan',
      );
      final scan = store.inspectOwnSnapshot(snapshot, token: token);
      // Cancel while the scan is still in flight; whichever scan boundary
      // processes the cancelled command first must fail closed so that no
      // digest can be reported after the cancellation command.
      Timer(const Duration(), token.cancel);
      final datasetBefore = (await store.records()).length;
      await expectLater(scan, throwsA(_Cancelled()));

      // The caller of a failed scan releases the capture pins for its session;
      // records and attachments above stay intact and untouched.
      await store.releaseBackupPins('cancelscan');
      expect(await store.records(), hasLength(datasetBefore));

      // No archive or snapshot db landed in the shared staging by the failed
      // scan; only the files the test created elsewhere remain.
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
    'a quantity-only snapshot scan cancelled mid-flight returns no inventory',
    () async {
      // Revisions beyond one full validation page make the quantity scan cross
      // awaited read boundaries while the cancellation command is still in
      // flight instead of finishing between two turns.
      for (var v = 0; v < _quantityScanRevisions; v++) {
        await store.record(
          commandId: 'quantity-scan-$v',
          itemId: itemId,
          amount: '3',
          actualAt: DateTime.utc(2026, 10, 20, 7, v % 60),
        );
      }
      final source = await Directory('${directory.path}/quantity-source')
          .create();
      final snapshot = await store.createBackupSnapshot(
        directory: source,
        sessionId: 'quant-scans',
      );
      // The uncancelled baseline proves the same snapshot stays valid later.
      final baseline = await store.inspectOwnSnapshot(snapshot);
      expect(baseline.recordCount, 1 + _quantityScanRevisions);
      expect(baseline.attachmentCount, 0);

      final livePage = (await store.records()).length;
      final token = BackupCancellationToken();
      final scan = store.inspectOwnSnapshot(snapshot, token: token);
      // Order the command past the snapshot's open and entry phases using the
      // same awaited round-trip cadence the scan's own queries use, so the
      // cancelled command arrives while the quantity or metadata scans are
      // still in flight. Wherever the scan processes it, the next scan
      // boundary must fail closed instead of returning the completed result.
      for (var turn = 0; turn < _scanCancellationPacingTurns; turn++) {
        await store.records(limit: 1);
      }
      token.cancel();
      await expectLater(scan, throwsA(_Cancelled()));

      // The abandoned scan disturbed nothing: the live dataset keeps its
      // records and the same snapshot still validates identically. No pin or
      // staging operation belongs to this standalone inspection, so none is
      // asserted here.
      expect((await store.records()).length, livePage);
      final stable = await store.inspectOwnSnapshot(snapshot);
      expect(stable.recordCount, baseline.recordCount);
      expect(stable.attachmentCount, baseline.attachmentCount);
    },
  );

  test(
    'a capture cancelled at the inspect stage reports no ready archive',
    () async {
      await seedAttachments();
      final token = BackupCancellationToken();
      Object? failure;
      try {
        await service.createBackup(
          password: password,
          token: token,
          onProgress: (progress) {
            if (progress.stage == BackupStage.inspect) {
              // The command lands directly before the scan begins; both the
              // scan's own boundaries and the capture's post-scan boundary
              // fail a cancelled command, and the capture never reports
              // ready.
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
    'restore validation of a pre-cancelled command reads no archive',
    () async {
      // The archive exists on disk when the command arrives, so this proves
      // precedence only: a pre-cancelled command must fail before any archive
      // read, decrypt or staging open. Cancellation while a validation is
      // already mid-run is the scan-regression above.
      final archive = await service.createBackup(
        password: password,
        token: BackupCancellationToken(),
      );
      final file = File(archive.archive.path);
      expect(await file.exists(), isTrue, reason: 'the archive is live here');
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
      // The rejected command staged no snapshot and the existing archive stays
      // untouched until its owner discards it.
      expect(
        stagingNames().where((name) => name.startsWith('snapshot-')),
        isEmpty,
      );
      await service.discard(archive);
      expect(await file.exists(), isFalse);
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
