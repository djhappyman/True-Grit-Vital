import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'artifact_transfer.dart';
import 'backup.dart';
import 'exports.dart';
import 'reports.dart';

/// Clears generated copies before erasure or replacement. An active capture
/// is cancelled first; an OS-owned handoff must finish before data changes.
///
/// The staged archive, if any, is released through the awaited controller
/// cleanup so the deletion is shared with anything already running, always
/// runs on its originating operations and settles before the data change
/// starts. A failed or replaced release stops here instead of continuing.
Future<void> prepareGeneratedArtifactsForDataChange(Ref ref) async {
  final backup = ref.read(backupProvider);
  if (backup.busy) {
    ref.read(backupProvider.notifier).cancel();
    throw StateError('generated_work_busy');
  }
  switch (await ref.read(backupProvider.notifier).releaseForDataChange()) {
    case BackupRelease.released:
      break;
    case BackupRelease.busy:
      throw StateError('generated_work_busy');
    case BackupRelease.failed:
      throw StateError('generated_work_cleanup_failed');
  }
  ref.read(reportControllerProvider.notifier).reset();
  ref.invalidate(exportControllerProvider);
  if (!await ref
      .read(artifactTransferControllerProvider.notifier)
      .discardAll()) {
    throw StateError('generated_work_busy');
  }
}
