import 'package:flutter/services.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../ui/vital_ui.dart';

/// One authored settings group. Space carries the grouping; no divider rules.
class SettingsSection extends StatelessWidget {
  const SettingsSection({
    super.key,
    required this.title,
    required this.children,
  });

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) =>
      VitalPanel(title: title, gap: 8, children: children);
}

/// A destination row, not a toggle. The whole row is one semantic button and
/// one keyboard target; the trailing chevron shows that it opens a screen.
class SettingsNavigationRow extends StatefulWidget {
  const SettingsNavigationRow({
    super.key,
    required this.label,
    required this.description,
    required this.onPressed,
  });

  final String label;
  final String description;
  final VoidCallback onPressed;

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
