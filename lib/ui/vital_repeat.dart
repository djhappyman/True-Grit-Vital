import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import 'vital_ui.dart';
import '../l10n/app_localizations.dart';

/// Workout-family weekday pills. Domain rules remain with the calling feature.
class VitalWeekdayPicker extends StatelessWidget {
  const VitalWeekdayPicker({
    super.key,
    required this.selected,
    required this.onChanged,
    this.enabled = true,
  });
  final Set<int> selected;
  final ValueChanged<Set<int>> onChanged;
  final bool enabled;
  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context).toString();
    final c = VitalColors(context);
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (var day = 1; day <= 7; day++)
          Semantics(
            label: DateFormat.EEEE(locale).format(DateTime(2024, 1, day)),
            selected: selected.contains(day),
            child: IntrinsicWidth(
              child: VitalPress(
                enabled: enabled,
                child: Clickable(
                  onPressed: !enabled
                      ? null
                      : () {
                          HapticFeedback.selectionClick();
                          final next = Set<int>.from(selected);
                          if (!next.add(day)) next.remove(day);
                          onChanged(next);
                        },
                  child: AnimatedContainer(
                    duration: VitalMotion.duration(context, VitalMotion.choice),
                    curve: VitalMotion.arrival,
                    constraints: const BoxConstraints(
                      minHeight: 48,
                      minWidth: 48,
                    ),
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: selected.contains(day)
                          ? c.accent.withValues(alpha: .16)
                          : c.dark
                          ? Theme.of(context).colorScheme.secondary
                                .withValues(alpha: .18)
                          : Color.alphaBlend(
                              c.muted.withValues(alpha: .10),
                              c.canvas,
                            ),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      DateFormat.E(locale).format(DateTime(2024, 1, day)),
                      style: VitalType.label.copyWith(
                        fontWeight: FontWeight.w800,
                        color: selected.contains(day) ? c.accent : c.muted,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Bounded stepper with editable digits; invalid draft text is never replaced
/// until the person explicitly steps or types a new value.
class VitalRepeatStepper extends StatelessWidget {
  const VitalRepeatStepper({
    super.key,
    required this.label,
    required this.controller,
    this.min = 1,
    this.max = 999,
    this.enabled = true,
  });
  final String label;
  final TextEditingController controller;
  final int min, max;
  final bool enabled;
  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<TextEditingValue>(
        valueListenable: controller,
        builder: (context, _, _) {
          final current = int.tryParse(controller.text);
          void step(int delta) {
            HapticFeedback.selectionClick();
            controller.text =
                (current == null ? min : (current + delta).clamp(min, max))
                    .toString();
          }

          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final controls = Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    VitalIconButton(
                      label: AppLocalizations.of(context).repeatDecrease(label),
                      icon: LucideIcons.minus,
                      onPressed: enabled && (current == null || current > min)
                          ? () => step(-1)
                          : null,
                    ),
                    SizedBox(
                      width: 64,
                      child: Semantics(
                        label: label,
                        child: TextField(
                          controller: controller,
                          enabled: enabled,
                          keyboardType: TextInputType.number,
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                    VitalIconButton(
                      label: AppLocalizations.of(context).repeatIncrease(label),
                      icon: LucideIcons.plus,
                      onPressed: enabled && (current == null || current < max)
                          ? () => step(1)
                          : null,
                    ),
                  ],
                );
                return constraints.maxWidth < 300 ||
                        MediaQuery.textScalerOf(context).scale(14) > 21
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(label, style: VitalType.label),
                          controls,
                        ],
                      )
                    : Row(
                        children: [
                          Expanded(child: Text(label, style: VitalType.body)),
                          const SizedBox(width: 8),
                          controls,
                        ],
                      );
              },
            ),
          );
        },
      );
}

/// Matching geometry/fade when repeat-specific fields change.
class VitalRepeatTransition extends StatelessWidget {
  const VitalRepeatTransition({
    super.key,
    required this.value,
    required this.child,
  });
  final String value;
  final Widget child;
  @override
  Widget build(BuildContext context) => AnimatedSize(
    duration: VitalMotion.duration(context, VitalMotion.expand),
    curve: VitalMotion.arrival,
    alignment: Alignment.topCenter,
    child: AnimatedSwitcher(
      duration: VitalMotion.duration(context, VitalMotion.choice),
      switchInCurve: VitalMotion.arrival,
      switchOutCurve: VitalMotion.departure,
      layoutBuilder: (current, previous) => Stack(
        alignment: Alignment.topCenter,
        children: [
          for (final old in previous)
            IgnorePointer(
              child: ExcludeSemantics(
                child: FocusScope(canRequestFocus: false, child: old),
              ),
            ),
          ?current,
        ],
      ),
      child: KeyedSubtree(key: ValueKey(value), child: child),
    ),
  );
}
