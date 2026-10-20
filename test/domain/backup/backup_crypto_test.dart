import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:true_grit_vital/domain/backup/backup.dart';

void main() {
  late Directory directory;
  late List<int> datasetKey;
  late Uint8List snapshotBytes;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('vital-backup-crypto-');
    datasetKey = List.generate(32, (i) => (i * 7 + 3) % 256);
    snapshotBytes = Uint8List.fromList(
      List.generate(BackupLimits.chunkBytes + 2048, (i) => (i * 31 + 11) % 256),
    );
  });

  tearDown(() async {
    await directory.delete(recursive: true);
  });

  BackupHeader headerFor(Uint8List data) => BackupHeader(
    createdAt: DateTime.utc(2026, 10, 20, 12),
    schemaVersion: 21,
    generation: 'generation_crypto',
    kdf: BackupKdfParameters(
      memoryKiB: 8192,
      iterations: 1,
      parallelism: 1,
      hashLength: 32,
      salt: Uint8List.fromList(List.generate(16, (i) => i + 1)),
    ),
    cipher: BackupCipherParameters(
      chunkBytes: BackupLimits.chunkBytes,
      noncePrefix: Uint8List.fromList(List.generate(16, (i) => i + 20)),
    ),
    snapshot: BackupSnapshotSummary(
      bytes: data.length,
      sha256: sha256.convert(data).toString(),
      attachmentCount: 2,
      attachmentBytes: 48,
      attachmentSha256: sha256.convert([1, 2, 3]).toString(),
    ),
  );

  Future<File> create({String password = 'correct horse battery'}) async {
    final source = File('${directory.path}/snapshot.db');
    await source.writeAsBytes(snapshotBytes);
    final archive = File('${directory.path}/archive.vitalbackup');
    await createBackupArchive(
      snapshot: source,
      output: archive,
      password: password,
      header: headerFor(snapshotBytes),
      datasetKey: datasetKey,
      random: Random(9),
    );
    return archive;
  }

  test('round trips exact bytes and unwraps the dataset key', () async {
    final archive = await create();
    final opened = await openBackupArchive(archive);
    expect(opened.header.snapshot.bytes, snapshotBytes.length);
    expect(opened.header.generation, 'generation_crypto');
    final output = File('${directory.path}/decrypted.db');
    final result = await decryptBackupArchive(
      archive: archive,
      output: output,
      password: 'correct horse battery',
      onProgress: (_, _) {},
    );
    expect(result.datasetKey, datasetKey);
    expect(result.snapshotSha256, opened.header.snapshot.sha256);
    expect(await output.readAsBytes(), snapshotBytes);
  });

  test('does not write plaintext, the password or the key', () async {
    final archive = await create(password: 'unique synthetic password 42');
    final bytes = await archive.readAsBytes();
    final asText = String.fromCharCodes(bytes);
    expect(asText.contains('unique synthetic password 42'), isFalse);
    expect(asText.contains('SQLite format 3'), isFalse);
    final keyHex = datasetKey
        .map((v) => v.toRadixString(16).padLeft(2, '0'))
        .join();
    expect(asText.contains(keyHex), isFalse);
  });

  test('wrong password is rejected before a snapshot is written', () async {
    final archive = await create();
    final output = File('${directory.path}/wrong.db');
    await expectLater(
      decryptBackupArchive(
        archive: archive,
        output: output,
        password: 'incorrect password',
      ),
      throwsA(
        isA<BackupFailure>().having(
          (e) => e.code,
          'code',
          'backup_wrong_password',
        ),
      ),
    );
    expect(await output.exists(), isFalse);
  });

  test('tampered body is rejected and partial staging is removed', () async {
    final archive = await create();
    final opened = await openBackupArchive(archive);
    final bytes = await archive.readAsBytes();
    bytes[opened.dataOffset + 8] ^= 1;
    await archive.writeAsBytes(bytes);
    final output = File('${directory.path}/tampered.db');
    await expectLater(
      decryptBackupArchive(
        archive: archive,
        output: output,
        password: 'correct horse battery',
      ),
      throwsA(
        isA<BackupFailure>().having((e) => e.code, 'code', 'backup_corrupt'),
      ),
    );
    expect(await output.exists(), isFalse);
  });

  test('truncated and extended archives are rejected', () async {
    final archive = await create();
    final bytes = await archive.readAsBytes();
    await archive.writeAsBytes(bytes.sublist(0, bytes.length - 1));
    await expectLater(
      openBackupArchive(archive),
      throwsA(isA<BackupFailure>()),
    );
    await archive.writeAsBytes([...bytes, 0]);
    await expectLater(
      openBackupArchive(archive),
      throwsA(isA<BackupFailure>()),
    );
  });

  test('a changed header cannot authenticate the wrapped key', () async {
    final archive = await create();
    final bytes = await archive.readAsBytes();
    // The core starts after magic (8), version (1) and core length (4).
    final coreOffset = 13;
    bytes[coreOffset + 2] = bytes[coreOffset + 2] ^ 1;
    await archive.writeAsBytes(bytes);
    await expectLater(
      decryptBackupArchive(
        archive: archive,
        output: File('${directory.path}/header.db'),
        password: 'correct horse battery',
      ),
      throwsA(isA<BackupFailure>()),
    );
  });

  test('hostile header and chunk lengths fail before large work', () async {
    final archive = await create();
    final opened = await openBackupArchive(archive);
    final original = await archive.readAsBytes();
    final hostileHeader = Uint8List.fromList(original);
    ByteData.sublistView(
      hostileHeader,
      9,
      13,
    ).setUint32(0, 0xFFFFFFFF, Endian.big);
    await archive.writeAsBytes(hostileHeader);
    await expectLater(
      openBackupArchive(archive),
      throwsA(isA<BackupFailure>()),
    );

    final hostileChunk = Uint8List.fromList(original);
    ByteData.sublistView(
      hostileChunk,
      opened.dataOffset,
      opened.dataOffset + 4,
    ).setUint32(0, 0xFFFFFFFF, Endian.big);
    await archive.writeAsBytes(hostileChunk);
    final output = File('${directory.path}/hostile.db');
    await expectLater(
      decryptBackupArchive(
        archive: archive,
        output: output,
        password: 'correct horse battery',
      ),
      throwsA(
        isA<BackupFailure>().having((e) => e.code, 'code', 'backup_corrupt'),
      ),
    );
    expect(await output.exists(), isFalse);
  });

  test('cancellation deletes incomplete output', () async {
    final archive = await create();
    final output = File('${directory.path}/cancelled.db');
    await expectLater(
      decryptBackupArchive(
        archive: archive,
        output: output,
        password: 'correct horse battery',
        isCancelled: () => true,
      ),
      throwsA(
        isA<BackupFailure>().having((e) => e.code, 'code', 'backup_cancelled'),
      ),
    );
    expect(await output.exists(), isFalse);
  });

  test('large header and snapshot metadata fail closed', () async {
    final source = File('${directory.path}/empty.db');
    await source.writeAsBytes([1]);
    await expectLater(
      createBackupArchive(
        snapshot: source,
        output: File('${directory.path}/bad.vitalbackup'),
        password: 'correct horse battery',
        header: headerFor(Uint8List(0)),
        datasetKey: datasetKey,
      ),
      throwsA(
        isA<BackupFailure>().having((e) => e.code, 'code', 'backup_corrupt'),
      ),
    );
  });
}
