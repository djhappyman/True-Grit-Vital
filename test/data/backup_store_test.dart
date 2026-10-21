import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:true_grit_vital/data/record_store.dart';
import 'package:true_grit_vital/domain/backup/backup.dart';

void main() {
  late Directory directory;
  late RecordStore store;
  final key = List.generate(32, (i) => i + 11);

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('vital-backup-store-');
    store = await RecordStore.open(
      path: '${directory.path}/records.db',
      key: key,
      isNew: true,
    );
  });

  tearDown(() async {
    await store.close();
    await directory.delete(recursive: true);
  });

  Future<AttachmentRecord> attachment(SubstanceItem item) async {
    final bytes = Uint8List.fromList(
      List.generate(AttachmentLimits.chunkBytes + 123, (i) => i % 251),
    );
    final inspection = AttachmentInspection(
      mediaKind: AttachmentMediaKind.other,
      byteCount: bytes.length,
      sha256: sha256.convert(bytes).toString(),
      mimeType: 'application/octet-stream',
    );
    final job = AttachmentJob(
      id: 'backup-job',
      generation: store.generation,
      personId: meId,
      expectedPersonRevision: 1,
      targetKind: AttachmentTargetKind.item,
      targetId: item.id,
      targetRevision: item.revision,
      attachmentId: 'backup-attachment',
      versionId: 'backup-version',
      name: 'Synthetic source',
      createdAt: DateTime.utc(2026, 10, 20),
    );
    await store.beginAttachment(
      BeginAttachmentCommand(commandId: 'begin', job: job),
    );
    await store.appendAttachmentChunk(
      commandId: 'chunk-0',
      jobId: job.id,
      generation: store.generation,
      offset: 0,
      bytes: bytes.sublist(0, AttachmentLimits.chunkBytes),
    );
    await store.appendAttachmentChunk(
      commandId: 'chunk-1',
      jobId: job.id,
      generation: store.generation,
      offset: AttachmentLimits.chunkBytes,
      bytes: bytes.sublist(AttachmentLimits.chunkBytes),
    );
    return store.publishAttachment(
      commandId: 'publish',
      jobId: job.id,
      generation: store.generation,
      inspection: inspection,
    );
  }

  test('captures people, records and attachment bytes coherently', () async {
    final other = await store.createProfile(
      commandId: 'adult',
      name: 'Synthetic adult',
      adultConfirmed: true,
    );
    final mine = await store.createItem(
      commandId: 'mine',
      name: 'Synthetic item',
      form: 'tablet',
      unit: 'count',
      type: 'medicine',
    );
    final theirs = await store.createItem(
      commandId: 'theirs',
      personId: other.id,
      name: 'Other item',
      form: 'liquid',
      unit: 'ml',
      type: 'medicine',
    );
    await store.record(
      commandId: 'mine-record',
      itemId: mine.id,
      amount: '2',
      actualAt: DateTime.utc(2026, 10, 20, 8),
    );
    await store.record(
      commandId: 'their-record',
      personId: other.id,
      expectedPersonRevision: other.revision,
      itemId: theirs.id,
      amount: '1.5',
      actualAt: DateTime.utc(2026, 10, 20, 9),
    );
    final saved = await attachment(mine);

    final snapshot = await store.createBackupSnapshot(
      directory: directory,
      sessionId: 'capture-one',
    );
    expect(await File(snapshot.path).exists(), isTrue);
    final header = File(snapshot.path).openSync().readSync(16);
    expect(String.fromCharCodes(header), isNot(startsWith('SQLite format 3')));
    expect(snapshot.generation, store.generation);
    expect(snapshot.schemaVersion, 23);

    final inventory = await store.inspectOwnSnapshot(snapshot);
    expect(inventory.peopleCount, 2);
    expect(inventory.recordCount, 2);
    expect(inventory.attachmentCount, 1);
    expect(inventory.attachmentBytes, saved.inspection!.byteCount);
    expect(inventory.coverage.length, 2);
    final otherCoverage = inventory.coverage.firstWhere(
      (coverage) => coverage.person.id == other.id,
    );
    expect(otherCoverage.recordCount, 1);
    expect(otherCoverage.attachmentCount, 0);
    expect(
      inventory.coverage
          .firstWhere((coverage) => coverage.person.id == meId)
          .attachmentCount,
      1,
    );
    expect(inventory.earliestRecord, DateTime.utc(2026, 10, 20, 8));

    // Later live edits cannot rewrite the captured snapshot.
    await store.record(
      commandId: 'later',
      itemId: mine.id,
      amount: '1',
      actualAt: DateTime.utc(2026, 10, 21, 8),
    );
    final unchanged = await inspectBackupSnapshot(
      path: snapshot.path,
      key: key,
    );
    expect(unchanged.recordCount, 2);
    expect(await store.recordCount(scope: const FeedScope.everyone()), 3);

    await store.deleteAttachment(
      commandId: 'delete-after-capture',
      attachment: saved,
      expectedPersonRevision: (await store.profileById(meId))!.revision,
    );
    expect(await store.attachmentById(saved.id), isNull);
    // The backup pin retains the exact version while capture validation runs.
    expect(await store.attachmentJob('backup-job'), isNotNull);
    await store.expireBackupPins(
      now: DateTime.now().toUtc().add(const Duration(hours: 3)),
    );
    expect(await store.attachmentJob('backup-job'), isNull);

    final afterDelete = await store.createBackupSnapshot(
      directory: directory,
      sessionId: 'capture-two',
    );
    final newInventory = await store.inspectOwnSnapshot(afterDelete);
    expect(newInventory.attachmentCount, 0);
    await store.releaseBackupPins('capture-two');
  });

  test('rejects a snapshot destination that already exists', () async {
    await store.createBackupSnapshot(directory: directory, sessionId: 'same');
    await expectLater(
      store.createBackupSnapshot(directory: directory, sessionId: 'same'),
      throwsA(isA<BackupFailure>()),
    );
  });

  test(
    'staged snapshot can be re-keyed without exposing the archive key',
    () async {
      await store.createItem(
        commandId: 'item',
        name: 'Synthetic item',
        form: 'tablet',
        unit: 'count',
        type: 'medicine',
      );
      final snapshot = await store.createBackupSnapshot(
        directory: directory,
        sessionId: 'rekey',
      );
      await store.releaseBackupPins('rekey');
      final newKey = List.generate(32, (i) => 255 - i);
      await rekeyBackupSnapshot(
        path: snapshot.path,
        currentKey: key,
        newKey: newKey,
      );
      await expectLater(
        RecordStore.open(path: snapshot.path, key: key, isNew: false),
        throwsA(anything),
      );
      final inventory = await inspectBackupSnapshot(
        path: snapshot.path,
        key: newKey,
      );
      expect(inventory.generation, store.generation);
      expect(inventory.peopleCount, 1);
    },
  );

  test('a failed capture leaves the live dataset writable', () async {
    final blocker = File('${directory.path}/not-a-directory');
    await blocker.writeAsString('x');
    await expectLater(
      store.createBackupSnapshot(
        directory: Directory(blocker.path),
        sessionId: 'failed',
      ),
      throwsA(anything),
    );
    final item = await store.createItem(
      commandId: 'after-failure',
      name: 'Still writable',
      form: 'tablet',
      unit: 'count',
      type: 'medicine',
    );
    expect(item.name, 'Still writable');
  });
}
