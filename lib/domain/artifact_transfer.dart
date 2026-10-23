import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

/// Bounded generated artifacts are separate from saved source attachments.
abstract final class ArtifactLimits {
  /// A whole-installation backup is the largest expected generated artifact.
  static const maxBytes = 512 * 1024 * 1024;
  static const chunkBytes = 64 * 1024;
  static const maxRetained = 2;
  static const maxNameLength = 80;
  static const lifetime = Duration(hours: 24);
}

enum ArtifactKind {
  summaryPdf,
  dataJson,
  dataCsv,
  dataFhir,
  plainText,
  backup,
  generic,
}

/// Names and media types come from the artifact kind, never from a person.
extension ArtifactKindContract on ArtifactKind {
  String get neutralName => switch (this) {
    ArtifactKind.summaryPdf => 'vital-summary.pdf',
    ArtifactKind.dataJson => 'vital-export.json',
    ArtifactKind.dataCsv => 'vital-export.csv',
    ArtifactKind.dataFhir => 'vital-export.json',
    ArtifactKind.plainText => 'vital-report.txt',
    ArtifactKind.backup => 'vital-backup.vitalbak',
    ArtifactKind.generic => 'vital-artifact.bin',
  };

  String get mimeType => switch (this) {
    ArtifactKind.summaryPdf => 'application/pdf',
    ArtifactKind.dataJson => 'application/json',
    ArtifactKind.dataCsv => 'text/csv',
    ArtifactKind.dataFhir => 'application/fhir+json',
    ArtifactKind.plainText => 'text/plain',
    ArtifactKind.backup => 'application/octet-stream',
    ArtifactKind.generic => 'application/octet-stream',
  };
}

enum ArtifactPurpose { save, share }

enum ArtifactPhase {
  idle,
  staging,
  saving,
  sharing,
  saved,
  offered,
  cancelled,
  failed,
}

final class ArtifactFailure implements Exception {
  const ArtifactFailure(this.code);
  final String code;
  @override
  String toString() => 'ArtifactFailure($code)';
}

final class ArtifactCapabilities {
  const ArtifactCapabilities({
    required this.save,
    required this.share,
    this.maxBytes = ArtifactLimits.maxBytes,
  });
  final bool save, share;
  final int maxBytes;
}

/// A completed artifact with an exact length and a bounded read stream.
///
/// Producers that already hold the bytes use [ArtifactSource.bytes]. Producers
/// that stage a long export or backup to a file use [ArtifactSource.file], so
/// transfer never requires a whole-file copy in memory.
final class ArtifactSource {
  ArtifactSource({
    required this.kind,
    required this.byteCount,
    required this.openRead,
    this.fileName,
    this.expectedSha256,
    this.dispose,
  }) {
    if (fileName != null) artifactNeutralName(fileName!);
    if (byteCount < 1 || byteCount > ArtifactLimits.maxBytes) {
      throw const ArtifactFailure('artifact_transfer_input');
    }
    if (!_mimePattern.hasMatch(kind.mimeType) || kind.mimeType.length > 128) {
      throw const ArtifactFailure('artifact_transfer_input');
    }
    final expected = expectedSha256;
    if (expected != null && !_digestPattern.hasMatch(expected)) {
      throw const ArtifactFailure('artifact_transfer_input');
    }
  }

  factory ArtifactSource.bytes(
    Uint8List bytes, {
    required ArtifactKind kind,
    String? expectedSha256,
    String? fileName,
  }) {
    if (bytes.isEmpty || bytes.length > ArtifactLimits.maxBytes) {
      throw const ArtifactFailure('artifact_transfer_input');
    }
    return ArtifactSource(
      kind: kind,
      byteCount: bytes.length,
      expectedSha256: expectedSha256,
      fileName: fileName,
      openRead: () => Stream.value(bytes),
    );
  }

  /// The file is read lazily; the length is captured before transfer starts.
  static Future<ArtifactSource> file(
    File file, {
    required ArtifactKind kind,
  }) async {
    final length = await file.length();
    if (length < 1 || length > ArtifactLimits.maxBytes) {
      throw const ArtifactFailure('artifact_transfer_input');
    }
    return ArtifactSource(
      kind: kind,
      byteCount: length,
      openRead: file.openRead,
    );
  }

  final ArtifactKind kind;
  final String? fileName;
  final int byteCount;
  final Stream<List<int>> Function() openRead;

  /// Optional precomputed digest. Transfer always computes its own digest.
  final String? expectedSha256;

  /// Adapter-owned cache or temporary source cleanup, never a user original.
  final Future<void> Function()? dispose;
}

final class ArtifactTransferState {
  const ArtifactTransferState({
    this.phase = ArtifactPhase.idle,
    this.artifactId,
    this.kind,
    this.purpose,
    this.byteCount = 0,
    this.bytesWritten = 0,
    this.cancelling = false,
    this.retained = false,
    this.failureCode,
    this.sha256,
  });

  final ArtifactPhase phase;
  final String? artifactId;
  final ArtifactKind? kind;
  final ArtifactPurpose? purpose;
  final int byteCount, bytesWritten;
  final bool cancelling, retained;
  final String? failureCode, sha256;

  bool get busy =>
      phase == ArtifactPhase.staging ||
      phase == ArtifactPhase.saving ||
      phase == ArtifactPhase.sharing;

  /// Zero-based progress for the bounded staging phase only.
  double? get progress {
    if (byteCount < 1) return null;
    return (bytesWritten / byteCount).clamp(0, 1);
  }

  ArtifactTransferState copy({
    ArtifactPhase? phase,
    ArtifactKind? kind,
    int? byteCount,
    int? bytesWritten,
    bool? cancelling,
    bool? retained,
    String? sha256,
  }) => ArtifactTransferState(
    phase: phase ?? this.phase,
    artifactId: artifactId,
    kind: kind ?? this.kind,
    purpose: purpose,
    byteCount: byteCount ?? this.byteCount,
    bytesWritten: bytesWritten ?? this.bytesWritten,
    cancelling: cancelling ?? this.cancelling,
    retained: retained ?? this.retained,
    failureCode: failureCode,
    sha256: sha256 ?? this.sha256,
  );
}

final class ArtifactTransferOutcome {
  const ArtifactTransferOutcome({
    required this.completed,
    required this.retained,
    this.cancelled = false,
    this.failureCode,
    this.sha256,
  });
  const ArtifactTransferOutcome.failure(
    String this.failureCode, {
    this.retained = false,
  }) : completed = false,
       cancelled = false,
       sha256 = null;
  const ArtifactTransferOutcome.cancelled({this.retained = false})
    : completed = false,
      cancelled = true,
      failureCode = null,
      sha256 = null;

  final bool completed, retained, cancelled;
  final String? failureCode, sha256;

  bool get failed => failureCode != null;
}

/// Re-chunks arbitrary producer streams to the native transfer bound.
Stream<Uint8List> boundedArtifactChunks(
  Stream<List<int>> source, {
  required int byteCount,
}) async* {
  if (byteCount < 1 || byteCount > ArtifactLimits.maxBytes) {
    throw const ArtifactFailure('artifact_transfer_input');
  }
  var total = 0;
  await for (final bytes in source) {
    if (bytes.isEmpty) continue;
    var offset = 0;
    while (offset < bytes.length) {
      final end = offset + ArtifactLimits.chunkBytes < bytes.length
          ? offset + ArtifactLimits.chunkBytes
          : bytes.length;
      final chunk = Uint8List.fromList(bytes.sublist(offset, end));
      total += chunk.length;
      if (total > byteCount) {
        throw const ArtifactFailure('artifact_transfer_incomplete');
      }
      offset = end;
      yield chunk;
    }
  }
}

DateTime artifactLifetimeFrom(DateTime now) {
  if (!now.isUtc) throw const ArtifactFailure('artifact_transfer_input');
  return now.add(ArtifactLimits.lifetime);
}

void artifactExpiry(DateTime now, DateTime expiresAt) {
  if (!now.isUtc ||
      !expiresAt.isUtc ||
      !expiresAt.isAfter(now) ||
      expiresAt.isAfter(artifactLifetimeFrom(now))) {
    throw const ArtifactFailure('artifact_transfer_input');
  }
}

void artifactIdentity(String value) {
  if (!RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(value)) {
    throw const ArtifactFailure('artifact_transfer_identity');
  }
}

void artifactNeutralName(String value) {
  if (value.isEmpty ||
      value.length > ArtifactLimits.maxNameLength ||
      !RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]*$').hasMatch(value) ||
      value.contains('..')) {
    throw const ArtifactFailure('artifact_transfer_input');
  }
}

void artifactMimeType(String value) {
  if (value.length > 128 || !_mimePattern.hasMatch(value)) {
    throw const ArtifactFailure('artifact_transfer_input');
  }
}

void artifactDigest(String value) {
  if (!_digestPattern.hasMatch(value)) {
    throw const ArtifactFailure('artifact_transfer_input');
  }
}

final _mimePattern = RegExp(r'^[A-Za-z0-9.+_-]+/[A-Za-z0-9.+_-]+$');
final _digestPattern = RegExp(r'^[a-f0-9]{64}$');
