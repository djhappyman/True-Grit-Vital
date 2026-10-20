import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:true_grit_vital/backup/backup_service.dart';
import 'package:true_grit_vital/data/record_store.dart';
import 'package:true_grit_vital/domain/backup/backup.dart';

final class _CopyDestination implements BackupDestinationGateway {
  _CopyDestination(this.target, {this.status = BackupSaveStatus.saved});
  final File target;
  final BackupSaveStatus status;
  int calls = 0;
  @override
  bool get supported => true;
  @override
  Future<BackupSaveStatus> save(BackupArtifact artifact) async {
    calls++;
    if (status == BackupSaveStatus.saved) {
      await artifact.file.copy(target.path);
    }
    return status;
  }
}

void main() {
  late Directory directory;
  late RecordStore store;
  late BackupService service;
  final key = List.generate(32, (i) => i + 5);
  const password = 'synthetic backup password 73';

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('vital-backup-service-');
    store = await RecordStore.open(
      path: '${directory.path}/records.db',
      key: key,
      isNew: true,
    );
    service = BackupService(
      recordStore: store,
      stagingDirectory: Directory('${directory.path}/staging'),
      destination: _CopyDestination(
        File('${directory.path}/saved.vitalbackup'),
      ),
      clock: () => DateTime.utc(2026, 10, 20, 12),
    );
    final item = await store.createItem(
      commandId: 'item',
      name: 'Synthetic service item',
      form: 'tablet',
      unit: 'count',
      type: 'medicine',
    );
    await store.record(
      commandId: 'record',
      itemId: item.id,
      amount: '3',
      actualAt: DateTime.utc(2026, 10, 20, 7),
    );
  });

  tearDown(() async {
    await store.close();
    await directory.delete(recursive: true);
  });

  Future<AttachmentRecord> largeAttachment(SubstanceItem item, int kib) async {
    final bytes = Uint8List.fromList(List.generate(kib * 1024, (i) => i % 251));
    final inspection = AttachmentInspection(
      mediaKind: AttachmentMediaKind.other,
      byteCount: bytes.length,
      sha256: sha256.convert(bytes).toString(),
      mimeType: 'application/octet-stream',
    );
    final job = AttachmentJob(
      id: 'large-job',
      generation: store.generation,
      personId: meId,
      expectedPersonRevision: 1,
      targetKind: AttachmentTargetKind.item,
      targetId: item.id,
      targetRevision: item.revision,
      attachmentId: 'large-attachment',
      versionId: 'large-version',
      name: 'Synthetic large source',
      createdAt: DateTime.utc(2026, 10, 20),
    );
    await store.beginAttachment(
      BeginAttachmentCommand(commandId: 'large-begin', job: job),
    );
    for (var offset = 0; offset < bytes.length; offset += 64 * 1024) {
      final end = (offset + 64 * 1024).clamp(0, bytes.length);
      await store.appendAttachmentChunk(
        commandId: 'large-chunk-$offset',
        jobId: job.id,
        generation: store.generation,
        offset: offset,
        bytes: bytes.sublist(offset, end),
      );
    }
    return store.publishAttachment(
      commandId: 'large-publish',
      jobId: job.id,
      generation: store.generation,
      inspection: inspection,
    );
  }

  test('creates, validates and saves a complete archive', () async {
    final creation = await service.createBackup(
      password: password,
      token: BackupCancellationToken(),
    );
    expect(await creation.archive.exists(), isTrue);
    expect(creation.fileName, startsWith('backup-'));
    expect(creation.fileName, endsWith('.vitalbackup'));
    expect(creation.inventory.recordCount, 1);
    expect(creation.byteCount, greaterThan(512));
    expect(
      '${directory.path}/staging/snapshot-${creation.fileName}',
      isNot(equals(creation.archive.path)),
    );
    final archiveBytes = await creation.archive.readAsBytes();
    expect(String.fromCharCodes(archiveBytes).contains(password), isFalse);
    expect(
      String.fromCharCodes(archiveBytes).contains('SQLite format 3'),
      isFalse,
    );

    final staged = await service.validateArchive(
      archive: creation.archive,
      password: password,
      token: BackupCancellationToken(),
    );
    expect(staged.inventory.recordCount, 1);
    expect(staged.generation, store.generation);
    await staged.discard();

    final status = await service.save(creation);
    expect(status, BackupSaveStatus.saved);
    expect(await File('${directory.path}/saved.vitalbackup').exists(), isTrue);
    expect(await creation.archive.exists(), isFalse);
  });

  test('wrong password and tampered archive fail closed', () async {
    final creation = await service.createBackup(
      password: password,
      token: BackupCancellationToken(),
    );
    await expectLater(
      service.validateArchive(
        archive: creation.archive,
        password: 'another wrong password',
        token: BackupCancellationToken(),
      ),
      throwsA(
        isA<BackupFailure>().having(
          (e) => e.code,
          'code',
          'backup_wrong_password',
        ),
      ),
    );
    final bytes = await creation.archive.readAsBytes();
    bytes[bytes.length - 1] ^= 1;
    await creation.archive.writeAsBytes(bytes);
    await expectLater(
      service.validateArchive(
        archive: creation.archive,
        password: password,
        token: BackupCancellationToken(),
      ),
      throwsA(isA<BackupFailure>()),
    );
    final remaining = await Directory('${directory.path}/staging')
        .list()
        .toList();
    expect(remaining.where((entry) => entry.path.endsWith('.db')), isEmpty);
  });

  test('cancellation stops encryption and reports no backup', () async {
    final item = (await store.items()).single;
    await largeAttachment(item, 2 * 1024);
    final token = BackupCancellationToken();
    await expectLater(
      service.createBackup(
        password: password,
        token: token,
        onProgress: (progress) {
          if (progress.stage == BackupStage.encrypt &&
              progress.completedBytes > 0) {
            token.cancel();
          }
        },
      ),
      throwsA(
        isA<BackupFailure>().having((e) => e.code, 'code', 'backup_cancelled'),
      ),
    );
    final entries = await Directory('${directory.path}/staging')
        .list()
        .toList();
    expect(
      entries.where(
        (entry) =>
            entry.path.endsWith('.vitalbackup') || entry.path.endsWith('.db'),
      ),
      isEmpty,
    );
  });

  test(
    'a well-formed container with a non-database snapshot is rejected',
    () async {
      final bytes = Uint8List.fromList(
        List.generate(4096, (_) => Random(3).nextInt(256)),
      );
      final source = File('${directory.path}/not-a-database.db')
        ..writeAsBytesSync(bytes);
      final digest = sha256.convert(bytes).toString();
      final archive = File('${directory.path}/hostile.vitalbackup');
      final header = BackupHeader(
        createdAt: DateTime.utc(2026, 10, 20, 12),
        schemaVersion: 21,
        generation: 'hostile_generation',
        kdf: BackupKdfParameters(
          memoryKiB: 8192,
          iterations: 1,
          parallelism: 1,
          hashLength: 32,
          salt: Uint8List(16),
        ),
        cipher: BackupCipherParameters(
          chunkBytes: BackupLimits.chunkBytes,
          noncePrefix: Uint8List(16),
        ),
        snapshot: BackupSnapshotSummary(
          bytes: bytes.length,
          sha256: digest,
          attachmentCount: 0,
          attachmentBytes: 0,
          attachmentSha256: sha256.convert(const []).toString(),
        ),
      );
      await createBackupArchive(
        snapshot: source,
        output: archive,
        password: password,
        header: header,
        datasetKey: key,
        random: Random(4),
      );
      await expectLater(
        service.validateArchive(
          archive: archive,
          password: password,
          token: BackupCancellationToken(),
        ),
        throwsA(
          isA<BackupFailure>().having((e) => e.code, 'code', 'backup_corrupt'),
        ),
      );
      final staging = await Directory('${directory.path}/staging')
          .list()
          .toList();
      expect(staging.where((entry) => entry.path.endsWith('.db')), isEmpty);
    },
  );

  test('only one protected capture can run in a process', () async {
    final other = BackupService(
      recordStore: store,
      stagingDirectory: Directory('${directory.path}/staging'),
      destination: _CopyDestination(
        File('${directory.path}/other.vitalbackup'),
      ),
    );
    final first = service.createBackup(
      password: password,
      token: BackupCancellationToken(),
    );
    await expectLater(
      other.createBackup(password: password, token: BackupCancellationToken()),
      throwsA(
        isA<BackupFailure>().having((e) => e.code, 'code', 'backup_busy'),
      ),
    );
    final creation = await first;
    await service.discard(creation);
  });

  test('a cancelled save retains the archive for another attempt', () async {
    final cancelled = BackupService(
      recordStore: store,
      stagingDirectory: Directory('${directory.path}/staging'),
      destination: _CopyDestination(
        File('${directory.path}/unused.vitalbackup'),
        status: BackupSaveStatus.cancelled,
      ),
      clock: () => DateTime.utc(2026, 10, 20, 12),
    );
    final creation = await cancelled.createBackup(
      password: password,
      token: BackupCancellationToken(),
    );
    expect(await cancelled.save(creation), BackupSaveStatus.cancelled);
    expect(await creation.archive.exists(), isTrue);
    await cancelled.discard(creation);
    expect(await creation.archive.exists(), isFalse);
  });

  test('a failed capture keeps live records usable', () async {
    final blocker = File('${directory.path}/blocker');
    await blocker.writeAsString('x');
    final failing = BackupService(
      recordStore: store,
      stagingDirectory: Directory(blocker.path),
      destination: _CopyDestination(File('${directory.path}/never')),
    );
    await expectLater(
      failing.createBackup(
        password: password,
        token: BackupCancellationToken(),
      ),
      throwsA(anything),
    );
    await store.record(
      commandId: 'after-failure',
      itemId: (await store.items()).single.id,
      amount: '1',
      actualAt: DateTime.utc(2026, 10, 21),
    );
    expect(await store.recordCount(), 2);
  });

  test('startup cleanup removes only known abandoned staging files', () async {
    final staging = Directory('${directory.path}/staging');
    await staging.create(recursive: true);
    final oldArchive = File('${staging.path}/backup-old.vitalbackup')
      ..writeAsStringSync('old');
    final oldSnapshot = File('${staging.path}/snapshot-old.db')
      ..writeAsStringSync('old');
    final oldSidecar = File('${staging.path}/snapshot-old.db-wal')
      ..writeAsStringSync('old');
    final recent = File('${staging.path}/backup-recent.vitalbackup')
      ..writeAsStringSync('recent');
    final unknown = File('${staging.path}/notes.txt')
      ..writeAsStringSync('keep');
    final past = DateTime.now().toUtc().subtract(const Duration(hours: 2));
    for (final file in [oldArchive, oldSnapshot, oldSidecar]) {
      await file.setLastModified(past);
    }
    final cleanup = BackupService(
      recordStore: store,
      stagingDirectory: staging,
      destination: _CopyDestination(File('${directory.path}/never-saved')),
    );
    await cleanup.cleanupAbandoned();
    expect(await oldArchive.exists(), isFalse);
    expect(await oldSnapshot.exists(), isFalse);
    expect(await oldSidecar.exists(), isFalse);
    expect(await recent.exists(), isTrue);
    expect(await unknown.exists(), isTrue);
  });
}
