import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

/// Technical backup failure codes. Presentation maps them to reviewed copy.
final class BackupFailure implements Exception {
  const BackupFailure(this.code);
  final String code;
  @override
  String toString() => 'BackupFailure($code)';
}

/// Format-wide bounds. Reader-side limits apply to untrusted archives.
abstract final class BackupLimits {
  static const magic = 'VITALBK1';
  static const formatVersion = 1;

  static const chunkBytes = 256 * 1024;
  static const saltBytes = 16;
  static const noncePrefixBytes = 16;
  static const keyBytes = 32;
  static const tagBytes = 16;
  static const wrapCipherBytes = keyBytes + tagBytes;

  static const maxHeaderBytes = 64 * 1024;
  static const maxSnapshotBytes = 4 * 1024 * 1024 * 1024;
  static const maxArchiveBytes =
      maxSnapshotBytes +
      maxHeaderBytes +
      (maxSnapshotBytes ~/ chunkBytes + 1) * (4 + tagBytes) +
      512;

  static const minPasswordRunes = 12;
  static const maxPasswordBytes = 1024;

  /// Ready attachments pinned for one capture. The writer fails truthfully
  /// rather than silently omitting older versions beyond this bound.
  static const maxAttachmentCount = 20000;

  /// Abandoned pin rows are reclaimable by normal startup maintenance after
  /// this lifetime, so a killed capture cannot block deletion forever.
  static const pinLifetime = Duration(hours: 2);

  static int chunkCountFor(int snapshotBytes) =>
      (snapshotBytes + chunkBytes - 1) ~/ chunkBytes;

  static int archiveBodyBytes(int snapshotBytes) {
    final chunks = chunkCountFor(snapshotBytes);
    return snapshotBytes + chunks * (4 + tagBytes);
  }

  static void checkPassword(String password) {
    if (password.runes.length < minPasswordRunes) {
      throw const BackupFailure('backup_password_short');
    }
    if (utf8.encode(password).length > maxPasswordBytes) {
      throw const BackupFailure('backup_password_long');
    }
  }

  static String randomHex(int byteCount, [Random? random]) {
    final source = random ?? Random.secure();
    return List.generate(
      byteCount,
      (_) => source.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }

  static Uint8List randomBytes(int byteCount, [Random? random]) {
    final source = random ?? Random.secure();
    return Uint8List.fromList(
      List.generate(byteCount, (_) => source.nextInt(256)),
    );
  }
}

void backupIdentity(String value, String code) {
  if (!RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(value)) {
    throw BackupFailure(code);
  }
}

bool isSha256(String value) => RegExp(r'^[a-f0-9]{64}$').hasMatch(value);

Map<String, Object?> _object(Object? value, String code) {
  if (value is! Map) throw BackupFailure(code);
  return Map<String, Object?>.from(value);
}

String _string(Object? value, String code) {
  if (value is! String) throw BackupFailure(code);
  return value;
}

int _int(Object? value, String code) {
  if (value is! int) throw BackupFailure(code);
  return value;
}

/// Versioned password KDF parameters. Argon2id is provided by the admitted
/// `cryptography` package; no custom primitive is implemented here.
final class BackupKdfParameters {
  const BackupKdfParameters({
    required this.memoryKiB,
    required this.iterations,
    required this.parallelism,
    required this.hashLength,
    required this.salt,
  });

  static const algorithm = 'argon2id';
  static const algorithmVersion = 19;

  /// Measured v1 envelope. Host measurement: 443 ms on the implementation host.
  static const defaultMemoryKiB = 65536;
  static const defaultIterations = 3;
  static const defaultParallelism = 1;

  final int memoryKiB;
  final int iterations;
  final int parallelism;
  final int hashLength;
  final Uint8List salt;

  factory BackupKdfParameters.fresh({Random? random}) => BackupKdfParameters(
    memoryKiB: defaultMemoryKiB,
    iterations: defaultIterations,
    parallelism: defaultParallelism,
    hashLength: BackupLimits.keyBytes,
    salt: BackupLimits.randomBytes(BackupLimits.saltBytes, random),
  );

  void validate() {
    if (hashLength != BackupLimits.keyBytes ||
        memoryKiB < 8192 ||
        memoryKiB > 262144 ||
        iterations < 1 ||
        iterations > 10 ||
        parallelism < 1 ||
        parallelism > 4 ||
        salt.length < 16 ||
        salt.length > 32) {
      throw const BackupFailure('backup_corrupt');
    }
  }

  Map<String, Object?> toJson() => {
    'name': algorithm,
    'version': algorithmVersion,
    'memoryKiB': memoryKiB,
    'iterations': iterations,
    'parallelism': parallelism,
    'hashLength': hashLength,
    'salt': base64Encode(salt),
  };

  factory BackupKdfParameters.fromJson(Map<String, Object?> json) {
    if (_string(json['name'], 'backup_corrupt') != algorithm ||
        _int(json['version'], 'backup_corrupt') != algorithmVersion) {
      throw const BackupFailure('backup_unsupported_version');
    }
    final parameters = BackupKdfParameters(
      memoryKiB: _int(json['memoryKiB'], 'backup_corrupt'),
      iterations: _int(json['iterations'], 'backup_corrupt'),
      parallelism: _int(json['parallelism'], 'backup_corrupt'),
      hashLength: _int(json['hashLength'], 'backup_corrupt'),
      salt: _decodeBase64(json['salt'], 'backup_corrupt'),
    );
    parameters.validate();
    return parameters;
  }
}

final class BackupCipherParameters {
  const BackupCipherParameters({
    required this.chunkBytes,
    required this.noncePrefix,
  });

  static const algorithm = 'xchacha20-poly1305';

  final int chunkBytes;
  final Uint8List noncePrefix;

  factory BackupCipherParameters.fresh({Random? random}) =>
      BackupCipherParameters(
        chunkBytes: BackupLimits.chunkBytes,
        noncePrefix: BackupLimits.randomBytes(
          BackupLimits.noncePrefixBytes,
          random,
        ),
      );

  void validate() {
    if (chunkBytes != BackupLimits.chunkBytes ||
        noncePrefix.length != BackupLimits.noncePrefixBytes) {
      throw const BackupFailure('backup_unsupported_version');
    }
  }

  Map<String, Object?> toJson() => {
    'name': algorithm,
    'chunkBytes': chunkBytes,
    'noncePrefix': base64Encode(noncePrefix),
  };

  factory BackupCipherParameters.fromJson(Map<String, Object?> json) {
    if (_string(json['name'], 'backup_corrupt') != algorithm) {
      throw const BackupFailure('backup_unsupported_version');
    }
    final parameters = BackupCipherParameters(
      chunkBytes: _int(json['chunkBytes'], 'backup_corrupt'),
      noncePrefix: _decodeBase64(json['noncePrefix'], 'backup_corrupt'),
    );
    parameters.validate();
    return parameters;
  }
}

final class BackupSnapshotSummary {
  const BackupSnapshotSummary({
    required this.bytes,
    required this.sha256,
    required this.attachmentCount,
    required this.attachmentBytes,
    required this.attachmentSha256,
  });

  final int bytes;
  final String sha256;
  final int attachmentCount;
  final int attachmentBytes;
  final String attachmentSha256;

  void validate() {
    if (bytes < 1 ||
        bytes > BackupLimits.maxSnapshotBytes ||
        !isSha256(sha256) ||
        attachmentCount < 0 ||
        attachmentCount > BackupLimits.maxAttachmentCount ||
        attachmentBytes < 0 ||
        !isSha256(attachmentSha256)) {
      throw const BackupFailure('backup_corrupt');
    }
  }

  Map<String, Object?> toJson() => {
    'bytes': bytes,
    'sha256': sha256,
    'attachmentCount': attachmentCount,
    'attachmentBytes': attachmentBytes,
    'attachmentSha256': attachmentSha256,
  };

  factory BackupSnapshotSummary.fromJson(Map<String, Object?> json) {
    final summary = BackupSnapshotSummary(
      bytes: _int(json['bytes'], 'backup_corrupt'),
      sha256: _string(json['sha256'], 'backup_corrupt'),
      attachmentCount: _int(json['attachmentCount'], 'backup_corrupt'),
      attachmentBytes: _int(json['attachmentBytes'], 'backup_corrupt'),
      attachmentSha256: _string(json['attachmentSha256'], 'backup_corrupt'),
    );
    summary.validate();
    return summary;
  }
}

/// Authenticated header core. The serialised core is the associated data for
/// the wrapped dataset key and every body chunk.
final class BackupHeader {
  const BackupHeader({
    required this.createdAt,
    required this.schemaVersion,
    required this.generation,
    required this.kdf,
    required this.cipher,
    required this.snapshot,
  });

  static const format = 'vital-backup';

  final DateTime createdAt;
  final int schemaVersion;
  final String generation;
  final BackupKdfParameters kdf;
  final BackupCipherParameters cipher;
  final BackupSnapshotSummary snapshot;

  void validate() {
    if (!createdAt.isUtc ||
        schemaVersion < 1 ||
        schemaVersion > 1000 ||
        !RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(generation)) {
      throw const BackupFailure('backup_corrupt');
    }
    kdf.validate();
    cipher.validate();
    snapshot.validate();
  }

  Map<String, Object?> toJson() => {
    'format': format,
    'version': BackupLimits.formatVersion,
    'createdAt': createdAt.toIso8601String(),
    'schemaVersion': schemaVersion,
    'generation': generation,
    'kdf': kdf.toJson(),
    'cipher': cipher.toJson(),
    'snapshot': snapshot.toJson(),
  };

  factory BackupHeader.fromJson(Map<String, Object?> json) {
    if (_string(json['format'], 'backup_corrupt') != format) {
      throw const BackupFailure('backup_corrupt');
    }
    if (_int(json['version'], 'backup_corrupt') != BackupLimits.formatVersion) {
      throw const BackupFailure('backup_unsupported_version');
    }
    final createdAt = DateTime.tryParse(
      _string(json['createdAt'], 'backup_corrupt'),
    );
    if (createdAt == null || !createdAt.isUtc) {
      throw const BackupFailure('backup_corrupt');
    }
    final header = BackupHeader(
      createdAt: createdAt,
      schemaVersion: _int(json['schemaVersion'], 'backup_corrupt'),
      generation: _string(json['generation'], 'backup_corrupt'),
      kdf: BackupKdfParameters.fromJson(_object(json['kdf'], 'backup_corrupt')),
      cipher: BackupCipherParameters.fromJson(
        _object(json['cipher'], 'backup_corrupt'),
      ),
      snapshot: BackupSnapshotSummary.fromJson(
        _object(json['snapshot'], 'backup_corrupt'),
      ),
    );
    header.validate();
    return header;
  }

  Uint8List encodeCore() =>
      Uint8List.fromList(utf8.encode(jsonEncode(toJson())));
}

Uint8List _decodeBase64(Object? value, String code) {
  try {
    return base64Decode(_string(value, code));
  } on FormatException {
    throw BackupFailure(code);
  }
}

/// One person represented in a staged or captured dataset.
final class BackupPerson {
  const BackupPerson({
    required this.id,
    required this.name,
    required this.archived,
  });
  final String id, name;
  final bool archived;
}

/// Person-scoped coverage for a staged-backup preview. No live activation is
/// implied, and the list is bounded with the people preview.
final class BackupPersonCoverage {
  const BackupPersonCoverage({
    required this.person,
    required this.recordCount,
    required this.attachmentCount,
    this.earliestRecord,
    this.latestRecord,
  });
  final BackupPerson person;
  final int recordCount, attachmentCount;
  final DateTime? earliestRecord, latestRecord;
}

/// Bounded preview of a staged/captured dataset. It never substitutes for the
/// archive's authenticated snapshot summary.
final class BackupInventory {
  const BackupInventory({
    required this.generation,
    required this.schemaVersion,
    required this.people,
    required this.peopleCount,
    required this.recordCount,
    required this.itemCount,
    required this.supportingCount,
    required this.attachmentCount,
    required this.attachmentBytes,
    required this.attachmentSha256,
    this.coverage = const [],
    this.earliestRecord,
    this.latestRecord,
  });

  final String generation;
  final int schemaVersion;
  final List<BackupPerson> people;
  final int peopleCount,
      recordCount,
      itemCount,
      supportingCount,
      attachmentCount,
      attachmentBytes;
  final String attachmentSha256;
  final List<BackupPersonCoverage> coverage;
  final DateTime? earliestRecord, latestRecord;

  bool get singleUserCompatible =>
      peopleCount == 1 &&
      people.length == 1 &&
      people.single.id == 'me' &&
      !people.single.archived;

  BackupSnapshotSummary summaryFor(int snapshotBytes, String snapshotSha256) =>
      BackupSnapshotSummary(
        bytes: snapshotBytes,
        sha256: snapshotSha256,
        attachmentCount: attachmentCount,
        attachmentBytes: attachmentBytes,
        attachmentSha256: attachmentSha256,
      );
}

enum BackupStage { snapshot, inspect, encrypt, verify }

final class BackupProgress {
  const BackupProgress({
    required this.stage,
    this.completedBytes = 0,
    this.totalBytes = 0,
  });
  final BackupStage stage;
  final int completedBytes, totalBytes;

  double? get fraction =>
      totalBytes > 0 ? (completedBytes / totalBytes).clamp(0, 1) : null;
}

final class BackupCancellationToken {
  bool _cancelled = false;
  final List<void Function()> _listeners = [];
  bool get isCancelled => _cancelled;

  void addListener(void Function() listener) {
    if (_cancelled) {
      listener();
      return;
    }
    _listeners.add(listener);
  }

  void removeListener(void Function() listener) => _listeners.remove(listener);

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    for (final listener in List<void Function()>.of(_listeners)) {
      listener();
    }
    _listeners.clear();
  }

  void throwIfCancelled() {
    if (_cancelled) throw const BackupFailure('backup_cancelled');
  }
}
