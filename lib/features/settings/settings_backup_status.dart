import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../app/app_lock.dart';
import '../../app/backup.dart';
import '../../app/display_preferences.dart';
import '../../domain/backup/backup_history.dart';
import '../../l10n/app_localizations.dart';
import '../../ui/vital_ui.dart';
import 'settings_widgets.dart';

/// The latest receipt with a confirmed save, ordered by the save itself.
///
/// Stored history is newest-receipt first, but that order follows receipt
/// insertion. The archive check time and list position are not save times.
BackupReceipt? latestConfirmedBackup(Iterable<BackupReceipt> receipts) {
  BackupReceipt? latest;
  for (final receipt in receipts) {
    final savedAt = receipt.savedAt;
    if (savedAt == null) continue;
    if (latest == null || savedAt.isAfter(latest.savedAt!)) {
      latest = receipt;
    }
  }
  return latest;
}

/// Read-only backup receipt summary inside Settings Data.
///
/// It reads the current dataset's retained receipts and never starts a backup,
/// asks for a password or claims that an external copy still exists. The one
/// command opens the existing Backup workflow.
class SettingsBackupStatus extends ConsumerWidget {
  const SettingsBackupStatus({super.key, this.backupPath});

  /// The registered Backup route, or null when the host does not expose it.
  final String? backupPath;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(appLockProvider.select((state) => state.locked))) {
      return const SizedBox.shrink();
    }
    final text = AppLocalizations.of(context);
    final history = ref.watch(backupHistoryProvider);
    final path = backupPath;
    return VitalSurfaceFrame(
      key: const ValueKey('settings-backup-status'),
      inset: true,
      radius: VitalLayout.sectionRadius,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(text.directBackupStatusHeading, style: VitalType.section),
          const SizedBox(height: 8),
          history.when(
            skipError: false,
            skipLoadingOnReload: false,
            skipLoadingOnRefresh: false,
            loading: () => Semantics(
              liveRegion: true,
              child: Text(text.directBackupStatusLoading),
            ),
            error: (_, _) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  liveRegion: true,
                  child: Text(text.directBackupStatusFailed),
                ),
                const SizedBox(height: 8),
                VitalButton.secondary(
                  onPressed: () => ref.invalidate(backupHistoryProvider),
                  child: Text(text.retry),
                ),
              ],
            ),
            data: (receipts) {
              final latest = latestConfirmedBackup(receipts);
              if (latest == null) {
                return Text(text.directBackupStatusEmpty);
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    text.directBackupStatusSaved(
                      displayStamp(context, ref, latest.savedAt!),
                    ),
                    key: const ValueKey('settings-backup-status-saved'),
                    style: VitalType.body,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    text.directBackupStatusHelp,
                    style: VitalType.metadata.copyWith(
                      color: VitalColors(context).muted,
                    ),
                  ),
                ],
              );
            },
          ),
          if (path != null) ...[
            const SizedBox(height: 12),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: SettingsCommandButton(
                label: text.backup,
                semanticLabel: text.backup,
                onPressed: () => context.push(path),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
