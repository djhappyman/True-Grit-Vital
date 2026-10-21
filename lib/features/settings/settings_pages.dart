import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../app/appearance.dart';
import '../../app/display_preferences.dart';
import '../../app/privacy.dart';
import '../../l10n/app_localizations.dart';
import '../../ui/vital_ui.dart';
import 'settings_widgets.dart';

/// The three factual groups of the Settings hub.
///
/// Each group maps to one card whose rows are real, capability-gated
/// destinations. The filter only chooses which cards are shown; no group owns a
/// second copy of a form, and every destination stays reachable from `All`.
enum SettingsHubGroup { general, privacy, data }

/// Settings: one hub for the implemented capabilities.
///
/// Dependent report, export, backup and restore rows appear only when that
/// route is actually registered by the integrated build, or when a caller
/// explicitly injects one through [settingsCapabilitiesProvider]. A missing
/// capability is absent, not a disabled placeholder. Features that are not
/// implemented are shown as labelled previews and never as working controls.
class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  /// `null` shows every group, so the hub hides no destination by default.
  SettingsHubGroup _group = SettingsHubGroup.general;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final capabilities = settingsCapabilitiesFor(
      GoRouter.of(context),
      configured: ref.watch(settingsCapabilitiesProvider),
    );
    final displayFailed =
        ref.watch(appearanceErrorProvider) ||
        ref.watch(displayPreferencesProvider).failed;
    final sections = <Widget>[
      SettingsSection(
        title: t.screenSettingsGroupGeneral,
        icon: LucideIcons.slidersHorizontal,
        description: t.screenSettingsGeneralBody,
        children: [
          SettingsNavigationRow(
            icon: LucideIcons.userRound,
            label: t.profile,
            description: t.settingsProfileBody,
            onPressed: () => context.push('/profile'),
          ),
          SettingsNavigationRow(
            icon: LucideIcons.sunMoon,
            label: t.appearance,
            description: t.settingsAppearanceBody,
            onPressed: () => context.push('/appearance'),
          ),
          SettingsNavigationRow(
            icon: LucideIcons.bell,
            label: t.reminders,
            description: t.settingsRemindersBody,
            onPressed: () => context.push('/reminders'),
          ),
          SettingsNavigationRow(
            icon: LucideIcons.circleHelp,
            label: t.help,
            description: t.settingsHelpBody,
            onPressed: () => context.push('/settings/help'),
          ),
          SettingsNavigationRow(
            icon: LucideIcons.scrollText,
            label: t.licences,
            description: t.settingsLicencesBody,
            onPressed: () => context.push('/settings/licences'),
          ),
        ],
      ),
      SettingsSection(
        title: t.privacy,
        icon: LucideIcons.shieldCheck,
        description: t.privacyBody,
        children: [
          SettingsNavigationRow(
            icon: LucideIcons.archive,
            label: t.privacy,
            description: t.settingsPrivacyBody,
            onPressed: () => context.push('/settings/privacy'),
          ),
          SettingsNavigationRow(
            icon: LucideIcons.activity,
            label: t.diagnostics,
            description: t.settingsDiagnosticsBody,
            onPressed: () => context.push('/settings/diagnostics'),
          ),
        ],
      ),
      SettingsSection(
        title: t.data,
        icon: LucideIcons.database,
        description: t.screenSettingsDataBody,
        children: [
          if (capabilities.hasReports)
            SettingsNavigationRow(
              icon: LucideIcons.fileText,
              label: t.reports,
              description: t.settingsReportsBody,
              onPressed: () => context.push(capabilities.reportsPath!),
            ),
          if (capabilities.hasExports)
            SettingsNavigationRow(
              icon: LucideIcons.download,
              label: t.exports,
              description: t.settingsExportsBody,
              onPressed: () => context.push(capabilities.exportsPath!),
            ),
          if (capabilities.hasBackup)
            SettingsNavigationRow(
              icon: LucideIcons.lockKeyhole,
              label: t.backup,
              description: t.settingsBackupBody,
              onPressed: () => context.push(capabilities.backupPath!),
            ),
          if (capabilities.hasRestore)
            SettingsNavigationRow(
              icon: LucideIcons.upload,
              label: t.restore,
              description: t.settingsRestoreBody,
              onPressed: () => context.push(capabilities.restorePath!),
            ),
        ],
      ),
    ];
    return SafeArea(
      child: Scaffold(
        headers: [
          VitalPageBody(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: VitalButton.secondary(
                    onPressed: () =>
                        context.canPop() ? context.pop() : context.go('/today'),
                    leading: const Icon(LucideIcons.arrowLeft),
                    child: Text(t.back),
                  ),
                ),
                const SizedBox(height: 12),
                _SettingsGroupFilter(
                  group: _group,
                  onChanged: (group) => setState(() => _group = group!),
                ),
              ],
            ),
          ),
        ],
        child: VitalPager(
          index: _group.index,
          itemCount: 3,
          onChanged: (index) =>
              setState(() => _group = SettingsHubGroup.values[index]),
          itemBuilder: (_, index) => VitalScrollBody(
            children: [
              if (index == 0) ...[
                const _SettingsHero(),
                const SizedBox(height: 16),
              ],
              if (displayFailed)
                SettingsNotice(
                  message: t.settingsDisplayUnsaved,
                  isError: true,
                  action: VitalButton.secondary(
                    onPressed: () => context.push('/appearance'),
                    child: Text(t.appearance),
                  ),
                ),
              sections[index],
            ],
          ),
        ),
      ),
    );
  }
}

/// The page identity: the hub title, one factual storage badge and the body.
///
/// It replaces the plain title so the first thing on the screen names what the
/// hub controls. It claims no cipher, version, size or remote custody.
class _SettingsHero extends StatelessWidget {
  const _SettingsHero();

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final colours = Theme.of(context).colorScheme;
    return VitalPanel(
      gap: 8,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          runSpacing: 8,
          children: [
            Semantics(
              header: true,
              child: Text(t.settings, style: VitalType.detailTitle),
            ),
            VitalBadge(
              t.screenSettingsVaultBadge,
              tone: VitalTone.positive,
              dot: true,
            ),
          ],
        ),
        Text(
          t.settingsBody,
          style: VitalType.metadata.copyWith(color: colours.mutedForeground),
        ),
      ],
    );
  }
}

/// Short mutually exclusive group choices, with `All` first.
///
/// The shared segment control supplies the 48px targets, keyboard activation
/// and selected-state semantics; wrapping at large text keeps every label
/// readable.
class _SettingsGroupFilter extends StatelessWidget {
  const _SettingsGroupFilter({required this.group, required this.onChanged});

  final SettingsHubGroup? group;
  final ValueChanged<SettingsHubGroup?> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return VitalSegments<SettingsHubGroup?>(
      values: const [
        SettingsHubGroup.general,
        SettingsHubGroup.privacy,
        SettingsHubGroup.data,
      ],
      selected: group,
      onChanged: onChanged,
      label: (value) => switch (value) {
        null => t.screenSettingsGroupAll,
        SettingsHubGroup.general => t.screenSettingsGroupGeneral,
        SettingsHubGroup.privacy => t.privacy,
        SettingsHubGroup.data => t.data,
      },
    );
  }
}
