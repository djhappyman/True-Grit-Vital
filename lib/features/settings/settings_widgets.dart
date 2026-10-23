import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../l10n/app_localizations.dart';
import '../../ui/vital_ui.dart';

/// One authored settings group. Space carries the grouping between rows.
///
/// The optional icon and helper line use the shared, uncontained settings
/// section. Rows retain their own action and do not add nested card surfaces.
class SettingsSection extends StatelessWidget {
  const SettingsSection({
    super.key,
    required this.title,
    required this.children,
    this.icon,
    this.description,
  });

  final String title;
  final List<Widget> children;
  final IconData? icon;
  final String? description;

  @override
  Widget build(BuildContext context) => VitalSettingsSection(
    title: title,
    icon: icon,
    description: description,
    children: children,
  );
}

/// A destination row, not a toggle. The whole row is one semantic button and
/// one keyboard target; the trailing chevron shows that it opens a screen.
///
/// The optional leading icon is decorative; the label and helper carry the
/// meaning, so the row stays readable without it.
class SettingsNavigationRow extends StatelessWidget {
  const SettingsNavigationRow({
    super.key,
    required this.label,
    required this.description,
    required this.onPressed,
    this.icon,
  });
  final String label, description;
  final VoidCallback onPressed;
  final IconData? icon;
  @override
  Widget build(BuildContext context) => VitalSettingsRow(
    label: label,
    description: description,
    icon: icon,
    onPressed: onPressed,
  );
}

class _SettingsRowContent extends StatelessWidget {
  const _SettingsRowContent({
    required this.label,
    required this.description,
    this.icon,
    this.trailing,
  });
  final String label, description;
  final IconData? icon;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      if (icon != null) ...[
        VitalIconTile(icon!, size: 32, circular: true),
        const SizedBox(width: 12),
      ],
      Expanded(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: VitalSettingsType.item),
            const SizedBox(height: 4),
            Text(
              description,
              style: VitalSettingsType.detail.copyWith(
                color: VitalColors(context).muted,
              ),
            ),
          ],
        ),
      ),
      if (trailing != null) ...[const SizedBox(width: 12), trailing!],
    ],
  );
}

/// One visible one-word command with a context-rich accessible name.
///
/// The visible label stays short while assistive technology hears the person
/// and action, so repeated Delete/Archive buttons are not ambiguous.
class SettingsCommandButton extends StatelessWidget {
  const SettingsCommandButton({
    super.key,
    required this.label,
    required this.semanticLabel,
    required this.onPressed,
    this.destructive = false,
  });

  final String label, semanticLabel;
  final VoidCallback? onPressed;
  final bool destructive;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    enabled: onPressed != null,
    label: semanticLabel,
    onTap: onPressed,
    child: ExcludeSemantics(
      child: destructive
          ? VitalButton.destructive(onPressed: onPressed, child: Text(label))
          : VitalButton.secondary(onPressed: onPressed, child: Text(label)),
    ),
  );
}

/// A truthful inline result or explanation, announced once when it appears.
class SettingsNotice extends StatelessWidget {
  const SettingsNotice({
    super.key,
    required this.message,
    this.action,
    this.isError = false,
  });

  final String message;
  final Widget? action;
  final bool isError;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: VitalNotice(
      tone: isError ? VitalTone.danger : VitalTone.neutral,
      icon: isError ? LucideIcons.circleAlert : LucideIcons.info,
      action: action,
      child: Text(message),
    ),
  );
}

/// A capability that is not available yet, shown as a labelled preview.
///
/// It is deliberately neither a switch nor a button: nothing here writes a
/// setting, and no example value is presented as if it were saved. The row
/// keeps a 48px-plus reading target but exposes no action to assistive
/// technology.
class SettingsPreviewRow extends StatelessWidget {
  const SettingsPreviewRow({
    super.key,
    required this.label,
    required this.description,
    this.icon,
  });

  final String label;
  final String description;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return MergeSemantics(
      child: VitalSurfaceFrame(
        inset: true,
        radius: VitalLayout.sectionRadius,
        padding: const EdgeInsets.all(14),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final stacked =
                constraints.maxWidth < 280 ||
                MediaQuery.textScalerOf(context).scale(13) > 19;
            final badge = VitalBadge(
              t.screenSettingsPreviewBadge,
              compact: true,
            );
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _SettingsRowContent(
                  label: label,
                  description: description,
                  icon: icon,
                  trailing: stacked ? null : badge,
                ),
                if (stacked) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: badge,
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}
