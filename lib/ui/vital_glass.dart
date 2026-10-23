import 'dart:math' as math;

import 'package:liquid_glass_widgets/liquid_glass_widgets.dart' as glass;
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// Shared with True Grit Workout's glass recipe, adapted to shadcn's palette.
/// Cards are painted; only chrome and overlays sample their backdrop.
enum VitalGlassRole { appBar, bottomBar, sheet, dialog, menu }

class VitalGlassScope extends InheritedWidget {
  const VitalGlassScope({
    super.key,
    required this.opaque,
    required super.child,
  });
  final bool opaque;
  static bool opaqueOf(BuildContext context) =>
      (context.dependOnInheritedWidgetOfExactType<VitalGlassScope>()?.opaque ??
          false) ||
      MediaQuery.highContrastOf(context);

  /// Light chrome and overlays use solid theme surfaces. The modal barrier
  /// can dim the page without showing through the sheet/dialog itself.
  static bool opaqueSurfaceOf(BuildContext context) =>
      Theme.of(context).brightness == Brightness.light || opaqueOf(context);
  @override
  bool updateShouldNotify(VitalGlassScope oldWidget) =>
      opaque != oldWidget.opaque;
}

abstract final class VitalGlassSettings {
  static glass.LiquidGlassSettings forRole(
    BuildContext context,
    VitalGlassRole role,
  ) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final opacity = switch (role) {
      VitalGlassRole.appBar || VitalGlassRole.bottomBar => dark ? .42 : .30,
      VitalGlassRole.sheet || VitalGlassRole.dialog => dark ? .30 : .22,
      VitalGlassRole.menu => dark ? .46 : .34,
    };
    return glass.LiquidGlassSettings(
      blur: role == VitalGlassRole.appBar || role == VitalGlassRole.bottomBar
          ? 6
          : 8,
      thickness: 0,
      glassColor: theme.colorScheme.card.withValues(alpha: opacity),
      lightAngle: math.pi * .75,
      lightIntensity: 0,
      ambientStrength: 0,
      saturation: 1,
      refractiveIndex: role == VitalGlassRole.bottomBar
          ? (dark ? 1.12 : 1.02)
          : role == VitalGlassRole.appBar
          ? .9
          : .55,
      chromaticAberration: 0,
      glowIntensity: 0,
      shadowElevation: 0,
      whitenStrength: 0,
    );
  }
}

/// The package's brightness must follow shadcn rather than a Material fallback.
class VitalGlassTheme extends StatelessWidget {
  const VitalGlassTheme({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => glass.GlassTheme(
    data: glass.GlassThemeData(
      brightness: Theme.of(context).brightness,
      light: const glass.GlassThemeVariant(
        quality: glass.GlassQuality.standard,
      ),
      dark: const glass.GlassThemeVariant(quality: glass.GlassQuality.standard),
    ),
    child: child,
  );
}

/// Borderless, bounded live glass. Overscan hides the Standard shader's rim,
/// matching Workout's AppLargeAreaGlass without copying its Material controls.
class VitalGlassSurface extends StatelessWidget {
  const VitalGlassSurface({
    super.key,
    required this.child,
    required this.role,
    this.borderRadius = const BorderRadius.all(Radius.circular(28)),
    this.padding = EdgeInsets.zero,
    this.progress = 1,
  });
  final Widget child;
  final VitalGlassRole role;
  final BorderRadius borderRadius;
  final EdgeInsetsGeometry padding;
  final double progress;

  @override
  Widget build(BuildContext context) {
    final opaque = VitalGlassScope.opaqueSurfaceOf(context);
    final colors = Theme.of(context).colorScheme;
    final solidColor = switch (role) {
      VitalGlassRole.sheet ||
      VitalGlassRole.dialog ||
      VitalGlassRole.menu => colors.popover,
      VitalGlassRole.appBar || VitalGlassRole.bottomBar => colors.card,
    };
    final amount = progress.clamp(0.0, 1.0);
    const overscan = 3.0;
    return ClipRRect(
      borderRadius: borderRadius,
      child: Stack(
        fit: StackFit.passthrough,
        children: [
          if (amount > .001)
            Positioned.fill(
              child: IgnorePointer(
                child: Opacity(
                  opacity: amount,
                  child: opaque
                      ? ColoredBox(color: solidColor)
                      : Stack(
                          children: [
                            Positioned(
                              left: -overscan,
                              top: -overscan,
                              right: -overscan,
                              bottom: -overscan,
                              child: glass.GlassContainer(
                                padding: EdgeInsets.zero,
                                useOwnLayer: true,
                                quality: glass.GlassQuality.standard,
                                allowElevation: false,
                                clipBehavior: Clip.hardEdge,
                                shape: glass.LiquidRoundedSuperellipse(
                                  borderRadius: borderRadius.topLeft.x == 0
                                      ? 0
                                      : borderRadius.topLeft.x + overscan,
                                ),
                                settings: VitalGlassSettings.forRole(
                                  context,
                                  role,
                                ),
                                child: const SizedBox.expand(),
                              ),
                            ),
                          ],
                        ),
                ),
              ),
            ),
          Padding(padding: padding, child: child),
        ],
      ),
    );
  }
}

/// The same inexpensive fill, edge vignette and double rim used by Workout.
/// It deliberately contains no BackdropFilter or per-card shader.
class VitalFauxGlassSurface extends StatelessWidget {
  const VitalFauxGlassSurface({
    super.key,
    required this.child,
    required this.color,
    required this.borderColor,
    required this.borderRadius,
    this.padding = EdgeInsets.zero,
    this.inset = false,
  });
  final Widget child;
  final Color color, borderColor;
  final BorderRadius borderRadius;
  final EdgeInsetsGeometry padding;
  final bool inset;
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final opaque = VitalGlassScope.opaqueOf(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        boxShadow: inset || opaque
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: dark ? .08 : .07),
                  blurRadius: dark ? 12 : 18,
                  spreadRadius: dark ? -5 : -8,
                  offset: Offset(0, dark ? 6 : 10),
                ),
              ],
      ),
      child: CustomPaint(
        painter: _FauxGlassPainter(
          color: color,
          borderColor: borderColor,
          radius: borderRadius,
          dark: dark,
          opaque: opaque,
          inset: inset,
        ),
        child: ClipRRect(
          borderRadius: borderRadius,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

class _FauxGlassPainter extends CustomPainter {
  const _FauxGlassPainter({
    required this.color,
    required this.borderColor,
    required this.radius,
    required this.dark,
    required this.opaque,
    required this.inset,
  });
  final Color color, borderColor;
  final BorderRadius radius;
  final bool dark, opaque, inset;
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final shape = radius.toRRect(rect);
    final fill = opaque || inset
        ? color
        : Color.alphaBlend(
            Colors.black.withValues(alpha: dark ? .08 : .012),
            color.withValues(alpha: dark ? .11 : .78),
          );
    canvas.drawRRect(shape, Paint()..color = fill);
    if (!opaque && !inset) {
      canvas.save();
      canvas.clipRRect(shape);
      canvas.drawRect(
        rect,
        Paint()
          ..shader = RadialGradient(
            colors: [
              Colors.transparent,
              Colors.transparent,
              Colors.black.withValues(alpha: dark ? .026 : .010),
            ],
            stops: const [.82, .94, 1],
          ).createShader(rect),
      );
      canvas.restore();
    }
    canvas.drawRRect(
      shape.deflate(.35),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = .7
        ..color = opaque
            ? borderColor
            : borderColor.withValues(alpha: dark ? .30 : .32),
    );
    if (!opaque && rect.width > 2 && rect.height > 2) {
      canvas.drawRRect(
        radius.toRRect(rect.deflate(1)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = .45
          ..color = Colors.white.withValues(alpha: dark ? .010 : .48),
      );
    }
  }

  @override
  bool shouldRepaint(_FauxGlassPainter oldDelegate) =>
      color != oldDelegate.color ||
      borderColor != oldDelegate.borderColor ||
      radius != oldDelegate.radius ||
      dark != oldDelegate.dark ||
      opaque != oldDelegate.opaque ||
      inset != oldDelegate.inset;
}
