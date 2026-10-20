import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';

import '../domain/restore/restore.dart';

/// One archive chosen by the platform picker. The bytes are read lazily so a
/// full backup is never loaded into memory just to copy it into staging.
final class RestorePickedFile {
  const RestorePickedFile({
    required this.name,
    required this.byteCount,
    required this.openRead,
  });
  final String name;
  final int? byteCount;
  final Stream<List<int>> Function() openRead;
}

/// A restore-specific picker. It deliberately does not reuse the attachment
/// picker, whose native staging contract is bounded to 16 MiB and is intended
/// for source photos/files rather than full-installation archives.
abstract interface class RestoreArchivePicker {
  bool get supported;
  Future<RestorePickedFile?> pick();
}

final class PlatformRestoreArchivePicker implements RestoreArchivePicker {
  const PlatformRestoreArchivePicker();

  @override
  bool get supported => true;

  @override
  Future<RestorePickedFile?> pick() async {
    try {
      final selected = await FilePicker.pickFile(type: FileType.any);
      if (selected == null) return null;
      final length = await selected.length();
      if (length != null && length < 1) {
        throw const RestoreFailure(RestoreCodes.archiveChanged);
      }
      return RestorePickedFile(
        name: selected.name,
        byteCount: length,
        openRead: selected.readAsByteStream,
      );
    } on RestoreFailure {
      rethrow;
    } on MissingPluginException {
      throw const RestoreFailure(RestoreCodes.unavailable);
    } on PlatformException {
      throw const RestoreFailure(RestoreCodes.failed);
    } catch (_) {
      throw const RestoreFailure(RestoreCodes.failed);
    }
  }
}
