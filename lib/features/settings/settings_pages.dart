import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../app/appearance.dart';
import '../../app/display_preferences.dart';
import '../../app/privacy.dart';
import '../../l10n/app_localizations.dart';
import '../../ui/vital_ui.dart';
import '../recording/record_pages.dart' show EntryPage, Heading;
import 'settings_widgets.dart';
import '../restore/restore_recovery_banner.dart';

/// S19 Settings: the single inventory of implemented capabilities.
///
/// Dependent report, export, backup and restore rows appear only when that
/// route is actually registered by the integrated build, or when a caller
/// explicitly injects one through [settingsCapabilitiesProvider]. A missing
/// capability is absent, not a disabled placeholder.
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final capabilities = settingsCapabilitiesFor(
      GoRouter.of(context),
      configured: ref.watch(settingsCapabilitiesProvider),
    );
    final displayFailed =
        ref.watch(appearanceErrorProvider) ||
        ref.watch(displayPreferencesProvider).failed;
    return EntryPage(
      children: [
        const RestoreRecoveryBanner(),
        Heading(t.settings),
        Text(t.settingsBody),
        if (displayFailed) ...[
          const SizedBox(height: 16),
          SettingsNotice(
            message: t.settingsDisplayUnsaved,
            isError: true,
            action: VitalButton.secondary(
              onPressed: () => context.push('/appearance'),
              child: Text(t.appearance),
            ),
          ),
        ],
        const SizedBox(height: 28),
        SettingsSection(
          title: t.people,
          children: [
            SettingsNavigationRow(
              label: t.people,
              description: t.settingsPeopleBody,
              onPressed: () => context.push('/people'),
            ),
            SettingsNavigationRow(
              label: t.privacy,
              description: t.settingsPrivacyBody,
              onPressed: () => context.push('/settings/privacy'),
            ),
          ],
        ),
        const SizedBox(height: 28),
        SettingsSection(
          title: t.display,
          children: [
            SettingsNavigationRow(
              label: t.appearance,
              description: t.settingsAppearanceBody,
              onPressed: () => context.push('/appearance'),
            ),
          ],
        ),
        const SizedBox(height: 28),
        SettingsSection(
          title: t.alerts,
          children: [
            SettingsNavigationRow(
              label: t.reminders,
              description: t.settingsRemindersBody,
              onPressed: () => context.push('/reminders'),
            ),
          ],
        ),
        if (capabilities.hasDataSection) ...[
          const SizedBox(height: 28),
          SettingsSection(
            title: t.data,
            children: [
              if (capabilities.hasReports)
                SettingsNavigationRow(
                  label: t.reports,
                  description: t.settingsReportsBody,
                  onPressed: () => context.push(capabilities.reportsPath!),
                ),
              if (capabilities.hasExports)
                SettingsNavigationRow(
                  label: t.exports,
                  description: t.settingsExportsBody,
                  onPressed: () => context.push(capabilities.exportsPath!),
                ),
              if (capabilities.hasBackup)
                SettingsNavigationRow(
                  label: t.backup,
                  description: t.settingsBackupBody,
                  onPressed: () => context.push(capabilities.backupPath!),
                ),
              if (capabilities.hasRestore)
                SettingsNavigationRow(
                  label: t.restore,
                  description: t.settingsRestoreBody,
                  onPressed: () => context.push(capabilities.restorePath!),
                ),
            ],
          ),
        ],
        const SizedBox(height: 28),
        SettingsSection(
          title: t.support,
          children: [
            SettingsNavigationRow(
              label: t.diagnostics,
              description: t.settingsDiagnosticsBody,
              onPressed: () => context.push('/settings/diagnostics'),
            ),
            SettingsNavigationRow(
              label: t.help,
              description: t.settingsHelpBody,
              onPressed: () => context.push('/settings/help'),
            ),
            SettingsNavigationRow(
              label: t.licences,
              description: t.settingsLicencesBody,
              onPressed: () => context.push('/settings/licences'),
            ),
          ],
        ),
      ],
    );
  }
}
