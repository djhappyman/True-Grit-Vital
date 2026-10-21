import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../l10n/app_localizations.dart';
import 'vital_ui.dart';

/// A compact reference-style row that keeps complete text while it grows.
///
/// The leading icon is decorative; visible label text inside the row carries
/// the meaning. Wraps at narrow widths and large text scales instead of
/// truncating or shrinking. Provide [onPressed] when the whole row is one
/// action; [trailing] must then stay non-interactive (a badge, chip or
/// chevron), because the row itself becomes the single target.
class VitalCompactRow extends StatelessWidget {
  const VitalCompactRow({
    super.key,
    required this.title,
    this.subtitle,
    this.detail,
    this.icon,
    this.trailing,
    this.onPressed,
    this.focusNode,
  });

  /// The record, plan or entry name in full.
  final String title;

  /// One factual line beside the name, such as form and labelled strength.
  final String? subtitle;

  /// A further factual line, such as the schedule or stock state.
  final String? detail;

  /// Decorative leading icon rendered inside the shared icon tile.
  final IconData? icon;

  /// Small status at the row end; not a separate control when [onPressed] is
  /// set, and never a substitute for the visible text.
  final Widget? trailing;

  /// Makes the whole row one action with a 48px target and keyboard access.
  final VoidCallback? onPressed;

  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            VitalIconTile(icon!, size: 44),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    Text(title, style: VitalType.record),
                    ?trailing,
                  ],
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    subtitle!,
                    style: VitalType.metadata.copyWith(
                      color: colors.mutedForeground,
                    ),
                  ),
                ],
                if (detail != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    detail!,
                    style: VitalType.metadata.copyWith(
                      color: colors.mutedForeground,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
    if (onPressed == null) {
      return MergeSemantics(
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: VitalLayout.target),
          child: content,
        ),
      );
    }
    return MergeSemantics(
      child: Semantics(
        button: true,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: VitalLayout.target),
          child: Clickable(
            onPressed: onPressed,
            focusNode: focusNode,
            disableTransition: MediaQuery.disableAnimationsOf(context),
            decoration: WidgetStateProperty.resolveWith(
              (states) => BoxDecoration(
                borderRadius: const BorderRadius.all(Radius.circular(16)),
                color:
                    states.contains(WidgetState.hovered) ||
                        states.contains(WidgetState.pressed)
                    ? colors.accent
                    : Colors.transparent,
              ),
            ),
            child: content,
          ),
        ),
      ),
    );
  }
}

/// One labelled factual value with optional supporting text.
///
/// Pass `value: null` when the real value is unknown: the metric then shows a
/// localisable Unknown line, never zero or an invented equivalent. Amounts use
/// the shared tabular-figure quantity role so columns stay comparable.
class VitalMetric extends StatelessWidget {
  const VitalMetric({
    super.key,
    required this.label,
    this.value,
    this.detail,
    this.trailing,
  });

  /// The label that names what [value] measures.
  final String label;

  /// The complete formatted value, or null when genuinely unknown.
  final String? value;

  /// A supporting factual line, such as the exact unit context.
  final String? detail;

  /// Small status beside the value in the same wrapped line.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final t = AppLocalizations.of(context);
    final value = this.value;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: MergeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: VitalType.label),
            const SizedBox(height: 6),
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.end,
              spacing: 8,
              runSpacing: 6,
              children: [
                if (value == null)
                  Text(
                    t.designComponentsUnknown,
                    style: VitalType.body.copyWith(
                      color: colors.mutedForeground,
                    ),
                  )
                else
                  Text(value, style: VitalType.quantity),
                if (detail != null)
                  Text(
                    detail!,
                    style: VitalType.metadata.copyWith(
                      color: colors.mutedForeground,
                    ),
                  ),
                ?trailing,
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// A labelled factual proportion with an explicit denominator contract.
///
/// The bar is only drawn when a real value and total exist:
/// [VitalProgress.new] reports exactly the [fraction] the caller computed from
/// the same values shown as text (zero therefore stays an empty bar, never a
/// fake 100%), `.noTotal` states records that have no denominator at all, and
/// `.unknown` covers an existing denominator whose value is genuinely unknown.
/// Both text-only states render an authored [annotation] instead of a bar so
/// states stay visually and semantically distinct. Any actual overall amount
/// beyond the total is clamped for the bar width only; negative or
/// non-finite fractions paint as an empty bar. The visible text keeps the
/// exact numbers and any deficit wording.
class VitalProgress extends StatelessWidget {
  const VitalProgress({
    super.key,
    required this.label,
    required this.valueText,
    required this.totalText,
    required this.fraction,
    this.annotation,
  });

  /// Creates a progress holder whose real amount has no denominator, such as
  /// as-needed plans or a schedule with zero planned doses. [annotation] is
  /// the complete localised state; the component never invents a proportion.
  const VitalProgress.noTotal({
    super.key,
    required this.label,
    required String this.annotation,
  }) : valueText = null,
       totalText = null,
       fraction = null;

  /// Creates a progress holder with a denominator whose real amount is
  /// unknown, such as stock that has not been measured. [annotation] is the
  /// complete localised state; no bar is shown that could imply a value.
  const VitalProgress.unknown({
    super.key,
    required this.label,
    required String this.annotation,
  }) : valueText = null,
       totalText = null,
       fraction = null;

  /// The label naming what this progress measures, in full.
  final String label;

  /// The completed amount, already localised and exact.
  final String? valueText;

  /// The denominator with its unit, already localised and exact.
  final String? totalText;

  /// The caller-computed value/total from the same source as the shown text.
  final double? fraction;

  /// A further factual status, such as a run-out, low-stock or paused note.
  final String? annotation;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final fraction = this.fraction;
    final children = <Widget>[
      Text(
        label,
        style: VitalType.label.copyWith(color: colors.mutedForeground),
      ),
      if (valueText != null && totalText != null && fraction != null) ...[
        const SizedBox(height: 4),
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.end,
          spacing: 6,
          runSpacing: 4,
          children: [
            Text(valueText!, style: VitalType.quantity),
            Text(
              totalText!,
              style: VitalType.body.copyWith(color: colors.mutedForeground),
            ),
          ],
        ),
        const SizedBox(height: 10),
        LinearProgressIndicator(
          value: fraction.isFinite ? fraction.clamp(0.0, 1.0) : 0.0,
          theme: LinearProgressIndicatorTheme(
            minHeight: 10,
            borderRadius: BorderRadius.circular(999),
            disableAnimation: MediaQuery.disableAnimationsOf(context),
          ),
        ),
      ],
      if (fraction == null) ...[
        const SizedBox(height: 4),
        Text(annotation ?? '', style: VitalType.body),
      ],
      if (annotation != null && fraction != null) ...[
        const SizedBox(height: 10),
        Text(
          annotation!,
          style: VitalType.metadata.copyWith(color: colors.mutedForeground),
        ),
      ],
    ];
    return MergeSemantics(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: children,
      ),
    );
  }
}
