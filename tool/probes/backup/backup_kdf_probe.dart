// Host measurement for the protected-backup KDF/cipher envelope.
// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';
import 'package:true_grit_vital/domain/backup/backup.dart';

Future<void> main() async {
  print('host=${Platform.operatingSystem} ${Platform.version}');
  for (final (memory, iterations, parallelism) in [
    (19456, 2, 1),
    (32768, 3, 1),
    (65536, 3, 1),
    (65536, 4, 1),
  ]) {
    final watch = Stopwatch()..start();
    await Argon2id(
      memory: memory,
      iterations: iterations,
      parallelism: parallelism,
      hashLength: 32,
    ).deriveKey(
      secretKey: SecretKey(utf8.encode('synthetic backup benchmark')),
      nonce: Uint8List(16),
    );
    print(
      'argon2id m=${memory}KiB t=$iterations p=$parallelism '
      '${watch.elapsedMilliseconds}ms',
    );
  }

  final directory = await Directory.systemTemp.createTemp(
    'vital-backup-bench-',
  );
  try {
    final source = File('${directory.path}/snapshot.db');
    final size = 8 * 1024 * 1024;
    await source.writeAsBytes(
      Uint8List.fromList(List.generate(size, (i) => i % 251)),
    );
    final digest = await sha256.bind(source.openRead()).first;
    final header = BackupHeader(
      createdAt: DateTime.now().toUtc(),
      schemaVersion: 21,
      generation: 'benchmark',
      kdf: BackupKdfParameters(
        memoryKiB: 65536,
        iterations: 3,
        parallelism: 1,
        hashLength: 32,
        salt: Uint8List.fromList([
          1,
          2,
          3,
          4,
          5,
          6,
          7,
          8,
          9,
          10,
          11,
          12,
          13,
          14,
          15,
          16,
        ]),
      ),
      cipher: BackupCipherParameters(
        chunkBytes: BackupLimits.chunkBytes,
        noncePrefix: Uint8List(16),
      ),
      snapshot: BackupSnapshotSummary(
        bytes: size,
        sha256: digest.toString(),
        attachmentCount: 0,
        attachmentBytes: 0,
        attachmentSha256: sha256.convert(const []).toString(),
      ),
    );
    final archive = File('${directory.path}/bench.vitalbackup');
    final createWatch = Stopwatch()..start();
    await createBackupArchive(
      snapshot: source,
      output: archive,
      password: 'synthetic backup password',
      header: header,
      datasetKey: List.generate(32, (i) => i),
      random: Random(1),
    );
    print('create 8MiB ${createWatch.elapsedMilliseconds}ms');
    final decryptWatch = Stopwatch()..start();
    await decryptBackupArchive(
      archive: archive,
      output: File('${directory.path}/roundtrip.db'),
      password: 'synthetic backup password',
    );
    print('decrypt 8MiB ${decryptWatch.elapsedMilliseconds}ms');
  } finally {
    await directory.delete(recursive: true);
  }
}
