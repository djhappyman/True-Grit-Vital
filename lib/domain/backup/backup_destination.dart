import 'dart:io';

import 'backup_format.dart';

/// A completed archive handed to the shared generated-artifact destination
/// gateway (T05). The gateway owns the platform Save/Share operation; it must
/// copy or stream from [file] and return saved only after that copy completes.
final class BackupArtifact {
  const BackupArtifact({
    required this.file,
    required this.name,
    required this.byteCount,
    required this.sha256,
    required this.createdAt,
  });

  final File file;
  final String name;
  final int byteCount;
  final String sha256;
  final DateTime createdAt;

  static const mimeType = 'application/vnd.truegrit.vital.backup';
}

enum BackupSaveStatus { saved, cancelled }

abstract interface class BackupDestinationGateway {
  /// False when the host or integrated generated-artifact bridge cannot save a
  /// file. A false capability must disable the action rather than silently
  /// succeed.
  bool get supported;

  Future<BackupSaveStatus> save(BackupArtifact artifact);
}

/// Truthful default until the shared generated-artifact handoff is wired.
final class UnsupportedBackupDestination implements BackupDestinationGateway {
  const UnsupportedBackupDestination();
  @override
  bool get supported => false;
  @override
  Future<BackupSaveStatus> save(BackupArtifact artifact) async =>
      throw const BackupFailure('backup_unavailable');
}

BackupDestinationGateway defaultBackupDestination() =>
    const UnsupportedBackupDestination();
