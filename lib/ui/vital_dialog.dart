import 'dart:math' as math;

import 'package:shadcn_flutter/shadcn_flutter.dart';

import 'vital_foundation.dart';
import 'vital_glass.dart';
import 'vital_motion.dart';

/// Workout-family dialog composition on the existing shadcn modal host.
/// Callers retain their route, focus, pending-write and dismissal guards.
class VitalDialog extends StatelessWidget {
  const VitalDialog({
    super.key,
    this.title,
    this.content,
    this.actions,
    this.leading,
    this.trailing,
    this.maxWidth = VitalLayout.dialogWidth,
    this.contentPadding,
    this.surfaceRadius = VitalLayout.sheetRadius,
    this.headerBodySpacing = 8,
    this.headerAlignment = CrossAxisAlignment.start,
    this.footerSpacing = 20,
  });

  final Widget? title, content, leading, trailing;
  final List<Widget>? actions;
  final double maxWidth;
  final EdgeInsetsGeometry? contentPadding;
  final double surfaceRadius, headerBodySpacing, footerSpacing;
  final CrossAxisAlignment headerAlignment;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final c = VitalColors(context);
    final hasHeader = title != null || leading != null || trailing != null;
    final hasActions = actions?.isNotEmpty ?? false;
    final scrollable =
        content is ScrollView || content is SingleChildScrollView;
    final padding =
        contentPadding?.resolve(Directionality.of(context)) ??
        EdgeInsets.all(media.textScaler.scale(14) >= 28 ? 16.0 : 24.0);
    final header = hasHeader
        ? Row(
            crossAxisAlignment: headerAlignment,
            children: [
              if (leading != null) ...[
                IconTheme.merge(
                  data: IconThemeData(size: 22, color: c.accent),
                  child: leading!,
                ),
                const SizedBox(width: 12),
              ],
              if (title != null)
                Expanded(
                  child: Semantics(
                    header: true,
                    namesRoute: true,
                    child: DefaultTextStyle.merge(
                      style: VitalType.dialogTitle.copyWith(color: c.ink),
                      child: title!,
                    ),
                  ),
                )
              else
                const Spacer(),
              if (trailing != null) ...[const SizedBox(width: 12), trailing!],
            ],
          )
        : null;

    return SafeArea(
      minimum: const EdgeInsets.all(16),
      child: AnimatedPadding(
        padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
        duration: VitalMotion.duration(context, VitalMotion.choice),
        curve: VitalMotion.arrival,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = math.min(maxWidth, constraints.maxWidth);
            final height = constraints.maxHeight;
            final body = Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (scrollable) ...[
                  if (header != null) ...[header, const SizedBox(height: 12)],
                  Flexible(fit: FlexFit.loose, child: content!),
                ] else if (header != null || content != null)
                  Flexible(
                    fit: FlexFit.loose,
                    child: SingleChildScrollView(
                      key: const ValueKey('vital-dialog-scroll'),
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          ?header,
                          if (header != null && content != null)
                            SizedBox(height: headerBodySpacing),
                          ?content,
                        ],
                      ),
                    ),
                  ),
                if (hasActions) ...[
                  SizedBox(height: footerSpacing),
                  VitalDialogActions(children: actions!),
                ],
              ],
            );
            return Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: width, maxHeight: height),
                child: SizedBox(
                  width: width,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(surfaceRadius),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: .22),
                          blurRadius: 26,
                          spreadRadius: -4,
                          offset: const Offset(0, 12),
                        ),
                      ],
                    ),
                    child: VitalGlassSurface(
                      role: VitalGlassRole.dialog,
                      borderRadius: BorderRadius.circular(surfaceRadius),
                      child: ModalContainer(
                        fillColor: Colors.transparent,
                        filled: false,
                        borderWidth: 0,
                        borderColor: Colors.transparent,
                        borderRadius: BorderRadius.circular(surfaceRadius),
                        padding: padding,
                        surfaceBlur: 0,
                        surfaceOpacity: 0,
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxHeight: math.max(0, height - padding.vertical),
                          ),
                          child: VitalControlScope(
                            child: FocusTraversalGroup(
                              child: DefaultTextStyle.merge(
                                style: VitalType.body.copyWith(color: c.muted),
                                child: body,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Keep the caller's action order and focus nodes; stack when a row cannot fit.
class VitalDialogActions extends StatelessWidget {
  const VitalDialogActions({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => OverflowBar(
    alignment: MainAxisAlignment.end,
    overflowAlignment: OverflowBarAlignment.end,
    spacing: 8,
    overflowSpacing: 8,
    children: children,
  );
}
