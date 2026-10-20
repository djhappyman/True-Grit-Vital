import 'dart:io';

import '../domain/restore/restore.dart';
import 'restore_archive_picker.dart';

/// Copies one user-selected archive into the protected restore directory under
/// a fixed local name. The picker original is never reopened, and the archive
/// ceiling is enforced while streaming. This path is separate from the 16 MiB
/// source-attachment picker.
final class RestoreArchiveIntake {
  RestoreArchiveIntake({
    required this.picker,
    required this.directory,
    this.maxBytes = RestoreLimits.maxArchiveBytes,
  });

  final RestoreArchivePicker picker;
  final Directory directory;
  final int maxBytes;

  File get _target => File('${directory.path}/${RestoreLimits.intakeFile}');

  Future<RestorePick?> choose() async {
    if (!picker.supported) {
      throw const RestoreFailure(RestoreCodes.unavailable);
    }
    final selection = await picker.pick();
    if (selection == null) return null;
    final declared = selection.byteCount;
    if (declared != null && (declared <= 0 || declared > maxBytes)) {
      throw const RestoreFailure(RestoreCodes.tooLarge);
    }
    try {
      await directory.create(recursive: true);
      if (await _target.exists()) await _target.delete();
      final sink = await _target.open(mode: FileMode.writeOnly);
      var written = 0;
      try {
        await for (final chunk in selection.openRead()) {
          if (chunk.isEmpty) continue;
          written += chunk.length;
          if (written > maxBytes || (declared != null && written > declared)) {
            throw const RestoreFailure(RestoreCodes.tooLarge);
          }
          await sink.writeFrom(chunk);
        }
        await sink.flush();
        await sink.close();
      } catch (_) {
        try {
          await sink.close();
        } catch (_) {
          // The partial copy is removed below.
        }
        await discardFile();
        rethrow;
      }
      if (declared != null && written != declared) {
        await discardFile();
        throw const RestoreFailure(RestoreCodes.archiveChanged);
      }
      if (written < 1) {
        await discardFile();
        throw const RestoreFailure(RestoreCodes.archiveChanged);
      }
      return RestorePick(
        name: _displayName(selection.name),
        file: _target,
        byteCount: written,
      );
    } on FileSystemException {
      await discardFile();
      throw const RestoreFailure(RestoreCodes.storage);
    }
  }

  Future<void> discard(RestorePick pick) async {
    if (pick.file.path == _target.path) {
      await discardFile();
      return;
    }
    // Only this intake's fixed copy is owned here. Never delete a picker
    // original or an arbitrary path supplied through another gateway.
    throw const RestoreFailure(RestoreCodes.archiveChanged);
  }

  Future<void> discardFile() async {
    try {
      if (await _target.exists()) await _target.delete();
    } on FileSystemException {
      // Known intake names are retried by the next startup cleanup.
    }
  }
}

String _displayName(String value) {
  final parts = value.split(RegExp(r'[/\\]'));
  final name = parts.isEmpty ? value : parts.last;
  final cleaned = name.replaceAll(RegExp(r'[\x00-\x1f\x7f]'), '').trim();
  if (cleaned.isEmpty) return 'backup';
  return cleaned.length > 120 ? cleaned.substring(0, 120) : cleaned;
}
