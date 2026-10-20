import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'artifact_transfer.dart';
import 'backup.dart';
import 'exports.dart';
import 'reports.dart';

/// Clears generated copies before erasure or replacement. An active capture
/// is cancelled first; an OS-owned handoff must finish before data changes.
Future<void> prepareGeneratedArtifactsForDataChange(Ref ref) async {
  final backup = ref.read(backupProvider);
  if (backup.busy) {
    ref.read(backupProvider.notifier).cancel();
    throw StateError('generated_work_busy');
  }
  if (backup.creation != null) {
    await ref.read(backupOperationsProvider)!.discard(backup.creation!);
    ref.read(backupProvider.notifier).reset();
  }
  ref.read(reportControllerProvider.notifier).reset();
  ref.invalidate(exportControllerProvider);
  if (!await ref
      .read(artifactTransferControllerProvider.notifier)
      .discardAll()) {
    throw StateError('generated_work_busy');
  }
}
