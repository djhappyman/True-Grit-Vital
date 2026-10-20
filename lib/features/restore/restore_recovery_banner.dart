import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../app/restore_notice.dart';
import '../../domain/restore/restore.dart';
import '../../l10n/app_localizations.dart';
import '../../ui/vital_ui.dart';

/// In-memory recovery outcome, visible only inside the unlocked app.
class RestoreRecoveryBanner extends ConsumerWidget {
  const RestoreRecoveryBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recovery = ref.watch(restoreRecoveryNoticeProvider);
    if (recovery == null || recovery.outcome == RestoreRecoveryOutcome.none) {
      return const SizedBox.shrink();
    }
    final t = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.all(12),
      child: VitalSurface(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              liveRegion: true,
              child: Text(switch (recovery.outcome) {
                RestoreRecoveryOutcome.completed => t.restoreRecoveryCompleted,
                RestoreRecoveryOutcome.rolledBack =>
                  t.restoreRecoveryRolledBack,
                _ => t.restoreRecoveryCleaned,
              }),
            ),
            if (recovery.reason == 'reminder_warning')
              Text(t.restoreReminderWarning),
            const SizedBox(height: 8),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: VitalButton.secondary(
                onPressed: () =>
                    ref.read(restoreRecoveryNoticeProvider.notifier).clear(),
                child: Text(t.done),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
