// Synthetic interruption fixture. The runner owns its temporary directory.
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:true_grit_vital/backup/backup_service.dart';
import 'package:true_grit_vital/data/record_store.dart';
import 'package:true_grit_vital/domain/backup/backup.dart';

const _password = 'synthetic process backup password';

Future<void> main(List<String> args) async {
  final directory = args[0], mode = args[1];
  final store = await RecordStore.open(
    path: '$directory/records.db',
    key: List.generate(32, (i) => i + 9),
    isNew: mode == 'init',
  );
  final staging = Directory('$directory/staging');
  final service = BackupService(
    recordStore: store,
    stagingDirectory: staging,
    destination: _ProcessDestination(),
  );
  if (mode == 'init') {
    final item = await store.createItem(
      commandId: 'item',
      name: 'Synthetic process item',
      form: 'tablet',
      unit: 'count',
      type: 'medicine',
    );
    await store.record(
      commandId: 'record',
      itemId: item.id,
      amount: '1',
      actualAt: DateTime.utc(2026, 10, 20),
    );
    final bytes = Uint8List.fromList(
      List.generate(1536 * 1024, (i) => i % 251),
    );
    final inspection = AttachmentInspection(
      mediaKind: AttachmentMediaKind.other,
      byteCount: bytes.length,
      sha256: sha256.convert(bytes).toString(),
      mimeType: 'application/octet-stream',
    );
    final job = AttachmentJob(
      id: 'process-job',
      generation: store.generation,
      personId: meId,
      expectedPersonRevision: 1,
      targetKind: AttachmentTargetKind.item,
      targetId: item.id,
      targetRevision: item.revision,
      attachmentId: 'process-attachment',
      versionId: 'process-version',
      name: 'Synthetic process source',
      createdAt: DateTime.utc(2026, 10, 20),
    );
    await store.beginAttachment(
      BeginAttachmentCommand(commandId: 'begin', job: job),
    );
    for (var offset = 0; offset < bytes.length; offset += 64 * 1024) {
      final end = (offset + 64 * 1024).clamp(0, bytes.length);
      await store.appendAttachmentChunk(
        commandId: 'chunk-$offset',
        jobId: job.id,
        generation: store.generation,
        offset: offset,
        bytes: bytes.sublist(offset, end),
      );
    }
    await store.publishAttachment(
      commandId: 'publish',
      jobId: job.id,
      generation: store.generation,
      inspection: inspection,
    );
    await File('$directory/generation.txt').writeAsString(store.generation);
  } else if (mode == 'interrupt') {
    await service.createBackup(
      password: _password,
      token: BackupCancellationToken(),
      onProgress: (progress) {
        if (progress.stage == BackupStage.encrypt &&
            progress.completedBytes > 0) {
          exit(90);
        }
      },
    );
    exit(91);
  } else if (mode == 'cleanup') {
    await service.cleanupAbandoned(olderThan: Duration.zero);
  } else if (mode == 'verify') {
    final generation = File('$directory/generation.txt').readAsStringSync();
    if (store.generation != generation) throw StateError('generation_changed');
    if (await store.recordCount() != 1) throw StateError('record_lost');
    if ((await store.attachments(personId: meId)).length != 1) {
      throw StateError('attachment_lost');
    }
    if (await staging.exists()) {
      final known = await staging
          .list()
          .where(
            (entry) =>
                entry.path.endsWith('.vitalbackup') ||
                entry.path.endsWith('.db') ||
                entry.path.endsWith('.db-wal') ||
                entry.path.endsWith('.db-shm'),
          )
          .toList();
      if (known.isNotEmpty) throw StateError('staging_not_cleaned');
    }
  } else {
    throw ArgumentError(mode);
  }
  await store.close();
  stdout.writeln('PASS backup $mode');
}

final class _ProcessDestination implements BackupDestinationGateway {
  const _ProcessDestination();
  @override
  bool get supported => false;
  @override
  Future<BackupSaveStatus> save(BackupArtifact artifact) async =>
      throw const BackupFailure('backup_unavailable');
}
