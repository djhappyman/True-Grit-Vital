import 'package:shadcn_flutter/shadcn_flutter.dart';

import 'vital_foundation.dart';
import 'vital_motion.dart';

/// One destination or contextual action, using Workout's soft action-row shape.
class VitalNavigationRow extends StatelessWidget {
  const VitalNavigationRow({
    super.key,
    required this.label,
    required this.onPressed,
    this.description,
    this.icon,
    this.focusNode,
  });
  final String label;
  final String? description;
  final IconData? icon;
  final VoidCallback onPressed;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final c = VitalColors(context);
    return Semantics(
      label: label,
      hint: description,
      button: true,
      onTap: onPressed,
      child: ExcludeSemantics(
        child: VitalControlStyle(
          radius: 18,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          child: Button(
            style: ButtonVariance.ghost,
            focusNode: focusNode,
            onPressed: onPressed,
            disableTransition: VitalMotion.reduced(context),
            child: Row(
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 20, color: c.accent),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: VitalType.control.copyWith(color: c.ink),
                      ),
                      if (description != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          description!,
                          style: VitalType.metadata.copyWith(color: c.muted),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Icon(LucideIcons.chevronRight, size: 18, color: c.muted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
