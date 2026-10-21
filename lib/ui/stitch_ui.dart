import 'dart:math' as math;

import 'package:flutter/material.dart' show showDialog;
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../l10n/app_localizations.dart';
import 'vital_ui.dart';

/// Tokens transcribed from the saved Stitch 20 October HTML exports.
abstract final class StitchType {
  static const title = TextStyle(
    fontFamily: 'StitchSans',
    fontSize: 28,
    height: 34 / 28,
    fontWeight: FontWeight.w600,
    letterSpacing: -.42,
  );
  static const heading = TextStyle(
    fontFamily: 'StitchSans',
    fontSize: 20,
    height: 1.4,
    fontWeight: FontWeight.w600,
    letterSpacing: -.1,
  );
  static const name = TextStyle(
    fontFamily: 'StitchSans',
    fontSize: 17,
    height: 24 / 17,
    fontWeight: FontWeight.w600,
  );
  static const body = TextStyle(
    fontFamily: 'StitchSans',
    fontSize: 14,
    fontWeight: FontWeight.w400,
    height: 20 / 14,
  );
  static const caption = TextStyle(
    fontFamily: 'StitchSans',
    fontSize: 12,
    fontWeight: FontWeight.w400,
    height: 16 / 12,
    letterSpacing: .12,
  );
  static const label = TextStyle(
    fontFamily: 'StitchSans',
    fontSize: 13,
    height: 18 / 13,
    fontWeight: FontWeight.w500,
    letterSpacing: .13,
  );
  static const small = TextStyle(
    fontFamily: 'StitchSans',
    fontSize: 11,
    height: 14 / 11,
    fontWeight: FontWeight.w500,
    letterSpacing: .22,
  );
}

class StitchColors {
  StitchColors(BuildContext context)
    : dark = Theme.of(context).brightness == Brightness.dark;
  final bool dark;
  Color get canvas => Color(dark ? 0xff101715 : 0xffffffff);
  Color get surface => Color(dark ? 0xff192420 : 0xffffffff);
  Color get inset => Color(dark ? 0xff141e1b : 0xfff1f5f3);
  Color get ink => Color(dark ? 0xffe8f0ec : 0xff182725);
  Color get muted => Color(dark ? 0xffa7b6ae : 0xff647570);
  Color get accent => Color(dark ? 0xff96d1bb : 0xff1a5c52);
  Color get accentInk => Color(dark ? 0xff101715 : 0xffffffff);
  Color get accentSurface => Color(dark ? 0xff173e35 : 0xffe4f0eb);
  Color get line => Color(dark ? 0xff23342e : 0xffe9efec);
  Color get amber => Color(dark ? 0xffffb873 : 0xff8b4b0b);
  Color get danger => Color(dark ? 0xfff87171 : 0xffa62535);
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
    this.padding = const EdgeInsets.all(16),
    this.radius = 24,
    this.inset = false,
  });
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final bool inset;
  @override
  Widget build(BuildContext context) {
    final c = StitchColors(context);
    return Container(
      decoration: BoxDecoration(
        color: inset ? c.inset : c.surface,
        borderRadius: BorderRadius.circular(radius),
        border: c.dark ? null : Border.all(color: c.line.withValues(alpha: .7)),
        boxShadow: inset
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: c.dark ? .12 : .025),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
      ),
      padding: padding,
      child: DefaultTextStyle.merge(
        style: StitchType.body.copyWith(color: c.ink),
        child: child,
      ),
    );
  }
}

class StitchScrollBody extends StatelessWidget {
  const StitchScrollBody({super.key, required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: SingleChildScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 576),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            child: Column(
              key: const ValueKey('stitch-scroll-content'),
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          ),
        ),
      ),
    ),
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
    final c = StitchColors(context);
    final ink = warning ? c.amber : c.accent;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: warning ? c.amber.withValues(alpha: .14) : c.accentSurface,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dot) ...[
            Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(color: ink, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: Text(label, style: StitchType.small.copyWith(color: ink)),
          ),
        ],
      ),
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
    final c = StitchColors(context);
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: selected ? c.accentSurface : c.inset,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: size / 2, color: c.accent),
      ),
    );
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
    final c = StitchColors(context);
    final ink = destructive
        ? c.danger
        : warning
        ? c.amber
        : primary
        ? c.accentInk
        : c.ink;
    return ButtonStyleOverride(
      padding: (_, _, _) => EdgeInsets.symmetric(
        horizontal: compact ? 12 : 18,
        vertical: compact ? 8 : 14,
      ),
      decoration: (_, states, decoration) => decoration is BoxDecoration
          ? decoration.copyWith(
              color: primary
                  ? c.accent
                  : quiet
                  ? Colors.transparent
                  : c.inset,
              border: Border.all(color: Colors.transparent),
              borderRadius: BorderRadius.circular(999),
              boxShadow: const [],
            )
          : decoration,
      textStyle: (_, _, _) =>
          StitchType.label.copyWith(color: ink, fontWeight: FontWeight.w600),
      iconTheme: (_, _, theme) => theme.copyWith(color: ink, size: 18),
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
  return showDialog<void>(
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
