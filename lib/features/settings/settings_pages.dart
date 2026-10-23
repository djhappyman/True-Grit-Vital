import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../app/privacy.dart';
import '../../l10n/app_localizations.dart';
import '../../ui/vital_ui.dart';
import '../profiles/profile_pages.dart' show profilesProvider;
import 'settings_widgets.dart';

/// Stable section identities for existing Settings return links.
///
/// All sections appear in one list; a group URL reveals its section.
enum SettingsHubGroup { general, privacy, data }

/// Settings: one hub for the implemented capabilities.
///
/// Dependent report, export, backup and restore rows appear only when that
/// route is actually registered by the integrated build, or when a caller
/// explicitly injects one through [settingsCapabilitiesProvider]. A missing
/// capability is absent, not a disabled placeholder. Features that are not
/// implemented stay in the roadmap rather than becoming dead controls.
class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key, this.initialGroup = SettingsHubGroup.general});
  final SettingsHubGroup initialGroup;

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  final _groups = [for (var i = 0; i < 3; i++) GlobalKey()];

  @override
  void initState() {
    super.initState();
    _revealGroup();
  }

  @override
  void didUpdateWidget(SettingsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialGroup != widget.initialGroup) _revealGroup();
  }

  void _revealGroup() {
    if (widget.initialGroup == SettingsHubGroup.general) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final target = _groups[widget.initialGroup.index].currentContext;
      if (target != null) {
        Scrollable.ensureVisible(
          target,
          duration: VitalMotion.duration(context, VitalMotion.detail),
          curve: VitalMotion.arrival,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final capabilities = settingsCapabilitiesFor(
      GoRouter.of(context),
      configured: ref.watch(settingsCapabilitiesProvider),
    );
    final sections = <Widget>[
      SettingsSection(
        title: t.screenSettingsGroupGeneral,
        icon: LucideIcons.slidersHorizontal,
        children: [
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
        children: [
          SettingsNavigationRow(
            icon: LucideIcons.database,
            label: t.featureVaultTitle,
            description: t.featureVaultDatabase,
            onPressed: () => context.push('/settings/storage'),
          ),
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
              icon: LucideIcons.hardDrive,
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
    return VitalSettingsPage(
      title: t.settings,
      hub: true,
      trailing: VitalIconButton(
        label: t.edit,
        icon: LucideIcons.pencil,
        onPressed: () => context.push('/profile'),
      ),
      children: [
        const _SettingsHero(),
        const SizedBox(height: 24),
        for (var index = 0; index < sections.length; index++) ...[
          if (index > 0) const SizedBox(height: 24),
          KeyedSubtree(key: _groups[index], child: sections[index]),
        ],
      ],
    );
  }
}

/// The saved local profile and factual storage badge, with the existing editor.
class _SettingsHero extends ConsumerWidget {
  const _SettingsHero();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final c = VitalColors(context);
    final people = ref.watch(profilesProvider);
    final person = people.value?.where((profile) => profile.isMe).firstOrNull;
    final name = person != null
        ? (person.name == 'Me' ? t.me : person.name)
        : people.hasError
        ? t.profileUnavailable
        : t.loadingRecords;
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 96,
            height: 96,
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: c.accent, width: 2),
              boxShadow: [
                BoxShadow(
                  color: c.accent.withValues(alpha: .16),
                  blurRadius: 10,
                ),
              ],
            ),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: c.accentSurface,
                shape: BoxShape.circle,
              ),
              child: Icon(LucideIcons.userRound, color: c.accent, size: 32),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            name,
            textAlign: TextAlign.center,
            style: VitalType.detailTitle.copyWith(color: c.ink),
          ),
          const SizedBox(height: 8),
          VitalBadge(
            t.screenSettingsVaultBadge,
            tone: VitalTone.positive,
            dot: true,
          ),
        ],
      ),
    );
  }
}
