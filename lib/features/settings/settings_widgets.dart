import 'package:flutter/services.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../l10n/app_localizations.dart';
import '../../ui/vital_ui.dart';

/// One authored settings group. Space carries the grouping between rows.
///
/// The optional icon and helper line come from the shared panel composition, so
/// every group keeps one surface, radius and typography scale.
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
  Widget build(BuildContext context) => VitalPanel(
    title: title,
    icon: icon,
    description: description,
    gap: 8,
    children: children,
  );
}

/// A destination row, not a toggle. The whole row is one semantic button and
/// one keyboard target; the trailing chevron shows that it opens a screen.
///
/// The optional leading icon is decorative; the label and helper carry the
/// meaning, so the row stays readable without it.
class SettingsNavigationRow extends StatefulWidget {
  const SettingsNavigationRow({
    super.key,
    required this.label,
    required this.description,
    required this.onPressed,
    this.icon,
  });

  final String label;
  final String description;
  final VoidCallback onPressed;
  final IconData? icon;

  @override
  State<SettingsNavigationRow> createState() => _SettingsNavigationRowState();
}

class _SettingsNavigationRowState extends State<SettingsNavigationRow> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final colours = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: widget.label,
      hint: widget.description,
      onTap: widget.onPressed,
      child: ExcludeSemantics(
        child: FocusableActionDetector(
          onShowFocusHighlight: (value) => setState(() => _focused = value),
          mouseCursor: SystemMouseCursors.click,
          shortcuts: const {
            SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
            SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
          },
          actions: {
            ActivateIntent: CallbackAction<ActivateIntent>(
              onInvoke: (_) {
                widget.onPressed();
                return null;
              },
            ),
          },
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onPressed,
            child: Container(
              constraints: const BoxConstraints(minHeight: 72),
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
              decoration: BoxDecoration(
                color: colours.secondary,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: _focused ? colours.ring : const Color(0x00000000),
                  width: 2,
                ),
              ),
              child: Row(
                children: [
                  if (widget.icon != null) ...[
                    VitalIconTile(
                      widget.icon!,
                      size: 32,
                      selected: false,
                      circular: true,
                    ),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.label, style: VitalType.label),
                        const SizedBox(height: 4),
                        Text(
                          widget.description,
                          style: VitalType.metadata.copyWith(
                            color: colours.mutedForeground,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  ExcludeSemantics(
                    child: Icon(
                      LucideIcons.chevronRight,
                      color: colours.mutedForeground,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
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
    final colours = Theme.of(context).colorScheme;
    return MergeSemantics(
      child: Container(
        constraints: const BoxConstraints(minHeight: 72),
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
        decoration: BoxDecoration(
          color: colours.secondary,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          children: [
            if (icon != null) ...[
              VitalIconTile(icon!, size: 32, selected: false, circular: true),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: VitalType.label),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: VitalType.metadata.copyWith(
                      color: colours.mutedForeground,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            VitalBadge(t.screenSettingsPreviewBadge, compact: true),
          ],
        ),
      ),
    );
  }
}
