import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/reminder_alerts.dart';
import '../../app/reminders.dart';
import '../../app/settings_toggle_row.dart';
import '../../l10n/app_localizations.dart';
import '../../ui/vital_ui.dart';
import '../recording/record_pages.dart' show Heading;

/// Sound and vibration choices for reminder notifications.
///
/// The stored choice is durable intent; Android notification channels and the
/// system settings remain authoritative. Rows stay disabled while the active
/// channel is blocked so a new channel cannot quietly bypass a system mute.
class ReminderAlertSettings extends ConsumerWidget {
  const ReminderAlertSettings({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final alerts = ref.watch(reminderAlertsProvider);
    final reminderState = ref.watch(remindersProvider);
    final capabilities = reminderState.report.capabilities;
    final osReady =
        capabilities?.appEnabled == true &&
        capabilities?.channelEnabled == true;
    final enabled =
        alerts.loaded && !alerts.busy && !reminderState.busy && osReady;
    final canOpenSettings =
        capabilities?.notificationPermission == true && osReady;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (!alerts.loaded) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Heading(t.featureReminderAlertsHeading),
        Text(t.featureReminderAlertsHelp),
        const SizedBox(height: 12),
        if (alerts.loadFailed) ...[
          Semantics(
            liveRegion: true,
            child: Text(t.featureReminderAlertsReadFailed),
          ),
          VitalButton.secondary(
            onPressed: () => ref.invalidate(reminderAlertsProvider),
            child: Text(t.retry),
          ),
        ] else ...[
          if (alerts.saveFailed)
            Semantics(
              liveRegion: true,
              child: Text(t.featureReminderAlertsSaveFailed),
            ),
          if (alerts.applyFailed)
            Semantics(
              liveRegion: true,
              child: Text(t.featureReminderAlertsApplyFailed),
            ),
          SettingsToggleRow(
            label: t.featureReminderAlertsSound,
            description: t.featureReminderAlertsSoundHelp,
            value: alerts.preferences.sound,
            enabled: enabled,
            onChanged: (value) =>
                ref.read(reminderAlertsProvider.notifier).setSound(value),
            reduceMotion: reduceMotion,
          ),
          const SizedBox(height: 8),
          SettingsToggleRow(
            label: t.featureReminderAlertsVibration,
            description: t.featureReminderAlertsVibrationHelp,
            value: alerts.preferences.vibration,
            enabled: enabled,
            onChanged: (value) =>
                ref.read(reminderAlertsProvider.notifier).setVibration(value),
            reduceMotion: reduceMotion,
          ),
          if (alerts.applyFailed)
            VitalButton.secondary(
              onPressed: alerts.busy
                  ? null
                  : () =>
                        ref.read(reminderAlertsProvider.notifier).retryApply(),
              child: Text(t.retry),
            ),
          if (canOpenSettings)
            VitalButton.secondary(
              onPressed: reminderState.busy
                  ? null
                  : () => ref
                        .read(remindersProvider.notifier)
                        .permission(
                          (gateway) => gateway.openNotificationSettings(),
                        ),
              child: Text(t.reminderSettings),
            ),
        ],
      ],
    );
  }
}
