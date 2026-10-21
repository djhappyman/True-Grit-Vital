import 'dart:math' as math;

import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../l10n/app_localizations.dart';
import 'vital_ui.dart';

export 'vital_foundation.dart';

/// Tokens transcribed from the saved Stitch 20 October HTML exports.
abstract final class StitchType {
  static const title = VitalType.title;
  static const heading = VitalType.section;
  static const name = VitalType.record;
  static const body = VitalType.body;
  static const caption = VitalType.metadata;
  static const label = VitalType.label;
  static const small = VitalType.micro;
}

/// Compatibility vocabulary backed by the app's one semantic theme.
class StitchColors extends VitalColors {
  StitchColors(super.context);
}

class StitchMark extends StatelessWidget {
  const StitchMark({super.key});
  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Container(
      width: 32,
      height: 32,
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: const Color(0xff1a5c52),
        borderRadius: BorderRadius.circular(10),
      ),
      child: const CustomPaint(painter: _StitchMarkPainter()),
    ),
  );
}

class _StitchMarkPainter extends CustomPainter {
  const _StitchMarkPainter();
  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final paint = Paint()
      ..color = const Color(0xff96d1bb)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round;
    final rect = Rect.fromCircle(
      center: center,
      radius: size.shortestSide * .43,
    );
    for (var i = 0; i < 4; i++) {
      canvas.drawArc(
        rect,
        i * math.pi / 2 + .22,
        math.pi / 2 - .44,
        false,
        paint,
      );
    }
    canvas.drawCircle(
      center,
      size.shortestSide * .17,
      Paint()..color = const Color(0xff96d1bb),
    );
  }

  @override
  bool shouldRepaint(_StitchMarkPainter oldDelegate) => false;
}

class StitchSurface extends StatelessWidget {
  const StitchSurface({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(VitalLayout.panelPadding),
    this.radius = VitalLayout.surfaceRadius,
    this.inset = false,
  });
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final bool inset;
  @override
  Widget build(BuildContext context) {
    return VitalSurfaceFrame(
      padding: padding,
      radius: radius,
      inset: inset,
      child: child,
    );
  }
}

class StitchScrollBody extends StatelessWidget {
  const StitchScrollBody({super.key, required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => VitalScrollBody(
    maxWidth: VitalLayout.compactWidth,
    contentKey: const ValueKey('stitch-scroll-content'),
    children: children,
  );
}

class StitchBadge extends StatelessWidget {
  const StitchBadge(
    this.label, {
    super.key,
    this.warning = false,
    this.dot = false,
  });
  final String label;
  final bool warning, dot;
  @override
  Widget build(BuildContext context) {
    return VitalBadge(
      label,
      tone: warning ? VitalTone.warning : VitalTone.positive,
      dot: dot,
      compact: true,
    );
  }
}

class StitchIcon extends StatelessWidget {
  const StitchIcon(
    this.icon, {
    super.key,
    this.size = 48,
    this.selected = false,
  });
  final IconData icon;
  final double size;
  final bool selected;
  @override
  Widget build(BuildContext context) {
    return VitalIconTile(icon, size: size, selected: selected, circular: true);
  }
}

/// shadcn buttons with the exact pill geometry and type scale of the export.
class StitchButton extends StatelessWidget {
  const StitchButton({
    super.key,
    required this.child,
    this.onPressed,
    this.icon,
    this.primary = false,
    this.quiet = false,
    this.warning = false,
    this.destructive = false,
    this.compact = false,
    this.focusNode,
  });
  final Widget child;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool primary, quiet, warning, compact, destructive;
  final FocusNode? focusNode;
  @override
  Widget build(BuildContext context) {
    return VitalControlStyle(
      tone: destructive
          ? VitalControlTone.danger
          : warning
          ? VitalControlTone.warning
          : primary
          ? VitalControlTone.primary
          : VitalControlTone.secondary,
      quiet: quiet,
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 12 : 18,
        vertical: compact ? 8 : 14,
      ),
      child: Button(
        style: ButtonVariance.ghost,
        onPressed: onPressed,
        focusNode: focusNode,
        disableTransition: MediaQuery.disableAnimationsOf(context),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: compact ? 32 : 20,
            minWidth: 12,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                ExcludeSemantics(child: Icon(icon, size: 18)),
                const SizedBox(width: 6),
              ],
              Flexible(child: child),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> showStitchPlaceholder(BuildContext context, String feature) {
  final t = AppLocalizations.of(context);
  return showVitalDialog<void>(
    context: context,
    builder: (context) => VitalDialog(
      title: Text(feature),
      content: Text(t.stitchPlaceholderBody),
      actions: [
        StitchButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(t.done),
        ),
      ],
    ),
  );
}
