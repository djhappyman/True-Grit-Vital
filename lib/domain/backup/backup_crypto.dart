import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' hide Hmac;
import 'package:cryptography/cryptography.dart';

import 'backup_format.dart';

const _wrapInfo = 'vital-backup/1/wrap';
const _contentInfo = 'vital-backup/1/content';

final class _BackupKeys {
  const _BackupKeys(this.wrapKey, this.contentKey);
  final SecretKey wrapKey, contentKey;
}

final class BackupWrappedKey {
  const BackupWrappedKey({required this.nonce, required this.cipherText});
  final Uint8List nonce, cipherText;
}

final class BackupArchive {
  const BackupArchive({
    required this.header,
    required this.coreBytes,
    required this.wrappedKey,
    required this.dataOffset,
  });
  final BackupHeader header;
  final Uint8List coreBytes;
  final BackupWrappedKey wrappedKey;
  final int dataOffset;
}

final class BackupArchiveSummary {
  const BackupArchiveSummary({required this.header, required this.bytes});
  final BackupHeader header;
  final int bytes;
}

final class BackupDecryptResult {
  const BackupDecryptResult({
    required this.header,
    required this.snapshotBytes,
    required this.snapshotSha256,
    required this.datasetKey,
    required this.archiveBytes,
  });
  final BackupHeader header;
  final int snapshotBytes;
  final String snapshotSha256;

  /// Sensitive. Never log, persist outside protected staging or place in
  /// exceptions. Used only to open the authenticated snapshot copy.
  final List<int> datasetKey;
  final int archiveBytes;
}

Future<_BackupKeys> _deriveKeys(
  String password,
  BackupKdfParameters kdf,
) async {
  if (password.isEmpty ||
      utf8.encode(password).length > BackupLimits.maxPasswordBytes) {
    throw const BackupFailure('backup_wrong_password');
  }
  final argon = Argon2id(
    memory: kdf.memoryKiB,
    iterations: kdf.iterations,
    parallelism: kdf.parallelism,
    hashLength: kdf.hashLength,
  );
  final master = await argon.deriveKey(
    secretKey: SecretKey(utf8.encode(password)),
    nonce: kdf.salt,
  );
  final hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: BackupLimits.keyBytes);
  final wrap = await hkdf.deriveKey(
    secretKey: master,
    info: utf8.encode(_wrapInfo),
  );
  final content = await hkdf.deriveKey(
    secretKey: master,
    info: utf8.encode(_contentInfo),
  );
  return _BackupKeys(SecretKey(wrap.bytes), SecretKey(content.bytes));
}

Future<BackupWrappedKey> _wrapDatasetKey({
  required SecretKey wrapKey,
  required List<int> datasetKey,
  required List<int> aad,
  Random? random,
}) async {
  if (datasetKey.length != BackupLimits.keyBytes) {
    throw const BackupFailure('backup_key');
  }
  final nonce = BackupLimits.randomBytes(24, random);
  final box = await Xchacha20.poly1305Aead().encrypt(
    datasetKey,
    secretKey: wrapKey,
    nonce: nonce,
    aad: aad,
  );
  return BackupWrappedKey(
    nonce: nonce,
    cipherText: Uint8List.fromList([...box.cipherText, ...box.mac.bytes]),
  );
}

Future<List<int>> _unwrapDatasetKey({
  required SecretKey wrapKey,
  required BackupWrappedKey wrapped,
  required List<int> aad,
}) async {
  if (wrapped.cipherText.length != BackupLimits.wrapCipherBytes) {
    throw const BackupFailure('backup_corrupt');
  }
  final cipherText = wrapped.cipherText.sublist(
    0,
    wrapped.cipherText.length - BackupLimits.tagBytes,
  );
  final mac = wrapped.cipherText.sublist(
    wrapped.cipherText.length - BackupLimits.tagBytes,
  );
  try {
    return await Xchacha20.poly1305Aead().decrypt(
      SecretBox(cipherText, nonce: wrapped.nonce, mac: Mac(mac)),
      secretKey: wrapKey,
      aad: aad,
    );
  } on SecretBoxAuthenticationError {
    throw const BackupFailure('backup_wrong_password');
  }
}

Uint8List _nonceFor(Uint8List prefix, int index) {
  final nonce = Uint8List(24);
  nonce.setRange(0, prefix.length, prefix);
  final data = ByteData.sublistView(nonce);
  data.setUint64(prefix.length, index, Endian.big);
  return nonce;
}

Uint8List _chunkAad(Uint8List base, int index) {
  final aad = Uint8List(base.length + 8);
  aad.setRange(0, base.length, base);
  ByteData.sublistView(aad).setUint64(base.length, index, Endian.big);
  return aad;
}

Future<void> _writeAll(RandomAccessFile file, List<int> bytes) async {
  await file.writeFrom(bytes);
}

Future<void> _deleteQuietly(File file) async {
  try {
    if (await file.exists()) await file.delete();
  } catch (_) {
    // A known staging path is retried by startup cleanup.
  }
}

/// Creates the authenticated archive. On any failure or cancellation the
/// incomplete output file is removed; the caller never reports it as complete.
Future<BackupArchiveSummary> createBackupArchive({
  required File snapshot,
  required File output,
  required String password,
  required BackupHeader header,
  required List<int> datasetKey,
  bool Function()? isCancelled,
  void Function(int completedBytes, int totalBytes)? onProgress,
  Random? random,
}) async {
  BackupLimits.checkPassword(password);
  header.validate();
  if (datasetKey.length != BackupLimits.keyBytes) {
    throw const BackupFailure('backup_key');
  }
  final cancelled = isCancelled ?? () => false;
  void checkCancelled() {
    if (cancelled()) throw const BackupFailure('backup_cancelled');
  }

  if (await output.exists()) {
    throw const BackupFailure('backup_staging');
  }
  final length = await snapshot.length();
  if (length != header.snapshot.bytes) {
    throw const BackupFailure('backup_snapshot_changed');
  }
  final total = header.snapshot.bytes;
  final coreBytes = header.encodeCore();
  final keys = await _deriveKeys(password, header.kdf);
  checkCancelled();
  final wrapped = await _wrapDatasetKey(
    wrapKey: keys.wrapKey,
    datasetKey: datasetKey,
    aad: coreBytes,
    random: random,
  );
  final baseAad = Uint8List.fromList([
    ...coreBytes,
    ...wrapped.nonce,
    ...wrapped.cipherText,
  ]);
  final source = await snapshot.open();
  RandomAccessFile? destination;
  try {
    destination = await output.open(mode: FileMode.writeOnly);
    await _writeAll(destination, utf8.encode(BackupLimits.magic));
    await _writeAll(destination, [BackupLimits.formatVersion]);
    final coreLength = ByteData(4)..setUint32(0, coreBytes.length, Endian.big);
    await _writeAll(destination, coreLength.buffer.asUint8List());
    await _writeAll(destination, coreBytes);
    await _writeAll(destination, wrapped.nonce);
    final wrapLength = ByteData(2)
      ..setUint16(0, wrapped.cipherText.length, Endian.big);
    await _writeAll(destination, wrapLength.buffer.asUint8List());
    await _writeAll(destination, wrapped.cipherText);

    final cipher = Xchacha20.poly1305Aead();
    final chunks = BackupLimits.chunkCountFor(total);
    var completed = 0;
    for (var index = 0; index < chunks; index++) {
      checkCancelled();
      final expected = index == chunks - 1
          ? total - completed
          : header.cipher.chunkBytes;
      final plain = await _readExactly(source, expected);
      final box = await cipher.encrypt(
        plain,
        secretKey: keys.contentKey,
        nonce: _nonceFor(header.cipher.noncePrefix, index),
        aad: _chunkAad(baseAad, index),
      );
      final cipherText = Uint8List.fromList([
        ...box.cipherText,
        ...box.mac.bytes,
      ]);
      final frame = ByteData(4)..setUint32(0, cipherText.length, Endian.big);
      await _writeAll(destination, frame.buffer.asUint8List());
      await _writeAll(destination, cipherText);
      completed += plain.length;
      onProgress?.call(completed, total);
    }
    await destination.flush();
    await destination.close();
    destination = null;
    return BackupArchiveSummary(header: header, bytes: await output.length());
  } catch (_) {
    try {
      await destination?.close();
    } catch (_) {}
    await _deleteQuietly(output);
    rethrow;
  } finally {
    await source.close();
  }
}

/// Parses and bounds-checks the public header without deriving a key.
Future<BackupArchive> openBackupArchive(File archive) async {
  if (!await archive.exists()) {
    throw const BackupFailure('backup_missing');
  }
  final length = await archive.length();
  if (length < 8 + 1 + 4 + 24 + 2 + BackupLimits.wrapCipherBytes ||
      length > BackupLimits.maxArchiveBytes) {
    throw const BackupFailure('backup_corrupt');
  }
  final file = await archive.open();
  try {
    final magic = await _readExactly(file, 8);
    if (!_bytesEqual(magic, utf8.encode(BackupLimits.magic))) {
      throw const BackupFailure('backup_corrupt');
    }
    final version = (await _readExactly(file, 1)).single;
    if (version != BackupLimits.formatVersion) {
      throw const BackupFailure('backup_unsupported_version');
    }
    final coreLength = ByteData.sublistView(await _readExactly(file, 4))
        .getUint32(0, Endian.big);
    if (coreLength < 2 || coreLength > BackupLimits.maxHeaderBytes) {
      throw const BackupFailure('backup_corrupt');
    }
    final coreBytes = await _readExactly(file, coreLength);
    final Map<String, Object?> json;
    try {
      json = Map<String, Object?>.from(
        jsonDecode(utf8.decode(coreBytes)) as Map,
      );
    } on FormatException {
      throw const BackupFailure('backup_corrupt');
    } on TypeError {
      throw const BackupFailure('backup_corrupt');
    }
    final header = BackupHeader.fromJson(json);
    final wrapNonce = await _readExactly(file, 24);
    final wrapLength = ByteData.sublistView(await _readExactly(file, 2))
        .getUint16(0, Endian.big);
    if (wrapLength != BackupLimits.wrapCipherBytes) {
      throw const BackupFailure('backup_unsupported_version');
    }
    final wrapCipher = await _readExactly(file, wrapLength);
    final dataOffset = 8 + 1 + 4 + coreLength + 24 + 2 + wrapLength;
    final expected =
        dataOffset + BackupLimits.archiveBodyBytes(header.snapshot.bytes);
    if (expected != length) {
      throw const BackupFailure('backup_corrupt');
    }
    return BackupArchive(
      header: header,
      coreBytes: coreBytes,
      wrappedKey: BackupWrappedKey(nonce: wrapNonce, cipherText: wrapCipher),
      dataOffset: dataOffset,
    );
  } finally {
    await file.close();
  }
}

/// Authenticates the password, unwraps the dataset key and writes the exact
/// inner encrypted SQLite snapshot to [output]. Incomplete output is removed.
Future<BackupDecryptResult> decryptBackupArchive({
  required File archive,
  required File output,
  required String password,
  bool Function()? isCancelled,
  void Function(int completedBytes, int totalBytes)? onProgress,
}) async {
  final opened = await openBackupArchive(archive);
  final cancelled = isCancelled ?? () => false;
  void checkCancelled() {
    if (cancelled()) throw const BackupFailure('backup_cancelled');
  }

  if (await output.exists()) {
    throw const BackupFailure('backup_staging');
  }
  final keys = await _deriveKeys(password, opened.header.kdf);
  checkCancelled();
  final datasetKey = await _unwrapDatasetKey(
    wrapKey: keys.wrapKey,
    wrapped: opened.wrappedKey,
    aad: opened.coreBytes,
  );
  if (datasetKey.length != BackupLimits.keyBytes) {
    throw const BackupFailure('backup_corrupt');
  }
  final baseAad = Uint8List.fromList([
    ...opened.coreBytes,
    ...opened.wrappedKey.nonce,
    ...opened.wrappedKey.cipherText,
  ]);
  final total = opened.header.snapshot.bytes;
  final chunks = BackupLimits.chunkCountFor(total);
  final source = await archive.open();
  RandomAccessFile? destination;
  final digestSink = _BackupDigestSink();
  final digestInput = sha256.startChunkedConversion(digestSink);
  try {
    await source.setPosition(opened.dataOffset);
    destination = await output.open(mode: FileMode.writeOnly);
    final cipher = Xchacha20.poly1305Aead();
    var completed = 0;
    for (var index = 0; index < chunks; index++) {
      checkCancelled();
      final frameLength = ByteData.sublistView(await _readExactly(source, 4))
          .getUint32(0, Endian.big);
      final expectedPlain = index == chunks - 1
          ? total - completed
          : opened.header.cipher.chunkBytes;
      if (frameLength != expectedPlain + BackupLimits.tagBytes) {
        throw const BackupFailure('backup_corrupt');
      }
      final cipherText = await _readExactly(source, frameLength);
      final plain = await _decryptChunk(
        cipher: cipher,
        key: keys.contentKey,
        cipherText: cipherText,
        nonce: _nonceFor(opened.header.cipher.noncePrefix, index),
        aad: _chunkAad(baseAad, index),
      );
      await _writeAll(destination, plain);
      digestInput.add(plain);
      completed += plain.length;
      onProgress?.call(completed, total);
    }
    if (completed != total ||
        await source.position() != await archive.length()) {
      throw const BackupFailure('backup_corrupt');
    }
    digestInput.close();
    final digest = (digestSink.value ?? sha256.convert(const [])).toString();
    if (digest != opened.header.snapshot.sha256) {
      throw const BackupFailure('backup_corrupt');
    }
    await destination.flush();
    await destination.close();
    destination = null;
    return BackupDecryptResult(
      header: opened.header,
      snapshotBytes: completed,
      snapshotSha256: digest,
      datasetKey: datasetKey,
      archiveBytes: await archive.length(),
    );
  } catch (_) {
    try {
      digestInput.close();
    } catch (_) {}
    try {
      await destination?.close();
    } catch (_) {}
    await _deleteQuietly(output);
    rethrow;
  } finally {
    await source.close();
  }
}

Future<List<int>> _decryptChunk({
  required Xchacha20 cipher,
  required SecretKey key,
  required Uint8List cipherText,
  required Uint8List nonce,
  required Uint8List aad,
}) async {
  final body = cipherText.sublist(0, cipherText.length - BackupLimits.tagBytes);
  final mac = cipherText.sublist(cipherText.length - BackupLimits.tagBytes);
  try {
    return await cipher.decrypt(
      SecretBox(body, nonce: nonce, mac: Mac(mac)),
      secretKey: key,
      aad: aad,
    );
  } on SecretBoxAuthenticationError {
    throw const BackupFailure('backup_corrupt');
  }
}

Future<Uint8List> _readExactly(RandomAccessFile file, int count) async {
  if (count < 0) throw const BackupFailure('backup_corrupt');
  final buffer = Uint8List(count);
  var offset = 0;
  while (offset < count) {
    final read = await file.read(count - offset);
    if (read.isEmpty) throw const BackupFailure('backup_corrupt');
    buffer.setRange(offset, offset + read.length, read);
    offset += read.length;
  }
  return buffer;
}

bool _bytesEqual(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  var difference = 0;
  for (var i = 0; i < a.length; i++) {
    difference |= a[i] ^ b[i];
  }
  return difference == 0;
}

final class _BackupDigestSink implements Sink<Digest> {
  Digest? value;
  @override
  void add(Digest data) => value = data;
  @override
  void close() {}
}
