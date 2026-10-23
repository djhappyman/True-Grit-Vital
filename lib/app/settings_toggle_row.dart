import 'package:flutter/services.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../ui/vital_ui.dart';

/// One semantic switch and one keyboard target for the whole shared row.
class SettingsToggleRow extends StatefulWidget {
  const SettingsToggleRow({
    super.key,
    required this.label,
    required this.description,
    required this.value,
    required this.onChanged,
    required this.reduceMotion,
    this.enabled = true,
  });

  final String label;
  final String description;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool reduceMotion;
  final bool enabled;

  @override
  State<SettingsToggleRow> createState() => _SettingsToggleRowState();
}

class _SettingsToggleRowState extends State<SettingsToggleRow> {
  bool _focused = false;

  void _toggle() {
    if (widget.enabled) widget.onChanged(!widget.value);
  }

  @override
  Widget build(BuildContext context) {
    final colours = Theme.of(context).colorScheme;
    final settings = VitalSettingsScope.maybeOf(context) != null;
    return Semantics(
      container: true,
      label: widget.label,
      hint: widget.description,
      toggled: widget.value,
      enabled: widget.enabled,
      onTap: widget.enabled ? _toggle : null,
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
                _toggle();
                return null;
              },
            ),
          },
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.enabled ? _toggle : null,
            child: AnimatedContainer(
              duration: widget.reduceMotion
                  ? Duration.zero
                  : VitalMotion.choice,
              curve: VitalMotion.geometry,
              constraints: const BoxConstraints(minHeight: 72),
              padding: EdgeInsets.symmetric(
                vertical: settings ? 14 : 16,
                horizontal: settings ? 2 : 12,
              ),
              decoration: BoxDecoration(
                color: settings ? Colors.transparent : colours.secondary,
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
                        Text(
                          widget.label,
                          style: settings
                              ? VitalSettingsType.item
                              : VitalType.label,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          widget.description,
                          style: settings
                              ? VitalSettingsType.detail.copyWith(
                                  color: colours.mutedForeground,
                                )
                              : TextStyle(color: colours.mutedForeground),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 20),
                  ExcludeFocus(
                    child: IgnorePointer(
                      child: Switch(
                        // Recreate at its final value when motion is reduced; the
                        // package switch otherwise always animates its thumb.
                        key: widget.reduceMotion
                            ? ValueKey(widget.value)
                            : null,
                        value: widget.value,
                        onChanged: widget.onChanged,
                      ),
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
