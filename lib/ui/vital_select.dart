import 'package:shadcn_flutter/shadcn_flutter.dart';

import 'vital_foundation.dart';
import 'vital_glass.dart';

/// Native shadcn selection with the same overlay surface as the app shell.
class VitalSelect<T> extends StatelessWidget {
  const VitalSelect({
    super.key,
    required this.label,
    required this.value,
    required this.values,
    required this.labelOf,
    required this.onChanged,
    this.enabled = true,
    this.groupOf,
    this.subtitleOf,
    this.selectedLabelOf,
    this.footerBuilder,
  });
  final String label;
  final T value;
  final List<T> values;
  final String Function(T) labelOf;
  final ValueChanged<T> onChanged;
  final bool enabled;
  final String Function(T)? groupOf, subtitleOf, selectedLabelOf;
  final WidgetBuilder? footerBuilder;

  @override
  Widget build(BuildContext context) => Semantics(
    label: label,
    child: Select<T>(
      value: value,
      enabled: enabled,
      constraints: const BoxConstraints(minHeight: 48, minWidth: 72),
      theme: SelectTheme(
        borderRadius: const BorderRadius.all(Radius.circular(999)),
        decoration: (context, states, decoration) {
          final c = VitalColors(context);
          if (c.dark || decoration is! BoxDecoration) return decoration;
          final focused = states.contains(WidgetState.focused);
          final hovered =
              states.contains(WidgetState.hovered) ||
              states.contains(WidgetState.pressed);
          return decoration.copyWith(
            color: states.contains(WidgetState.disabled)
                ? c.inputFill.withValues(alpha: .65)
                : hovered
                ? Color.alphaBlend(c.ink.withValues(alpha: .04), c.inputFill)
                : c.inputFill,
            border: Border.all(color: focused ? c.accent : Colors.transparent),
            boxShadow: const [],
          );
        },
      ),
      itemBuilder: (context, value) => Text(
        selectedLabelOf?.call(value) ?? labelOf(value),
        semanticsLabel: labelOf(value),
        style: VitalType.control,
      ),
      onChanged: !enabled
          ? null
          : (next) {
              if (next != null) onChanged(next);
            },
      popup: (context) => VitalGlassSurface(
        role: VitalGlassRole.menu,
        borderRadius: BorderRadius.circular(18),
        child: SelectPopup<T>(
          surfaceOpacity: 0,
          surfaceBlur: 0,
          items: SelectItemList(
            children: [
              for (var i = 0; i < values.length; i++) ...[
                if (groupOf != null &&
                    (i == 0 || groupOf!(values[i]) != groupOf!(values[i - 1])))
                  SelectLabel(
                    child: Padding(
                      padding: EdgeInsetsDirectional.only(
                        start: 4,
                        end: 4,
                        top: i == 0 ? 4 : 20,
                        bottom: 8,
                      ),
                      child: Semantics(
                        header: true,
                        child: Text(
                          groupOf!(values[i]),
                          style: VitalType.control.copyWith(
                            fontWeight: FontWeight.w700,
                            color: VitalColors(context).accent,
                          ),
                        ),
                      ),
                    ),
                  ),
                SelectItemButton<T>(
                  value: values[i],
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(labelOf(values[i])),
                      if (subtitleOf != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          subtitleOf!(values[i]),
                          style: VitalType.metadata.copyWith(
                            color: VitalColors(context).muted,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
              if (footerBuilder != null) Builder(builder: footerBuilder!),
            ],
          ),
        ),
      ),
    ),
  );
}
