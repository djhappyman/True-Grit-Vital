import 'vital_motion.dart';

import 'package:shadcn_flutter/shadcn_flutter.dart';

/// One source for the geometry used by both current and compatibility widgets.
abstract final class VitalLayout {
  static const double contentWidth = 640;
  static const double compactWidth = 576;
  static const double gutter = 16;
  static const double target = 48;
  static const double surfaceRadius = 24;
  static const double sectionRadius = 16;
  static const double sheetRadius = 32;
  static const double pillRadius = 999;
  static const double gap = 12;
  static const double sectionGap = 24;
  static const double panelPadding = 16;
}

/// Semantic roles transcribed from the saved Stitch typography.
abstract final class VitalType {
  static const title = TextStyle(
    fontFamily: 'StitchSans',
    fontSize: 28,
    height: 34 / 28,
    fontWeight: FontWeight.w600,
    letterSpacing: -.42,
  );
  static const detailTitle = TextStyle(
    fontFamily: 'StitchSans',
    fontSize: 24,
    height: 32 / 24,
    fontWeight: FontWeight.w600,
  );
  static const section = TextStyle(
    fontFamily: 'StitchSans',
    fontSize: 20,
    height: 1.4,
    fontWeight: FontWeight.w600,
    letterSpacing: -.1,
  );
  static const record = TextStyle(
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
  static const metadata = TextStyle(
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
  static const micro = TextStyle(
    fontFamily: 'StitchSans',
    fontSize: 11,
    height: 14 / 11,
    fontWeight: FontWeight.w500,
    letterSpacing: .22,
  );
  static const quantity = TextStyle(
    fontFamily: 'StitchSans',
    fontSize: 24,
    fontWeight: FontWeight.w600,
    height: 32 / 24,
    fontFeatures: [FontFeature.tabularFigures()],
  );
  static const metric = TextStyle(
    fontFamily: 'StitchSans',
    fontSize: 32,
    fontWeight: FontWeight.w600,
    height: 38 / 32,
    fontFeatures: [FontFeature.tabularFigures()],
  );
}

/// The palette feeds shadcn's theme; widgets read its semantic colours below.
class VitalPalette {
  const VitalPalette(this.dark);
  final bool dark;
  Color get canvas => Color(dark ? 0xff101715 : 0xffffffff);
  Color get surface => Color(dark ? 0xff192420 : 0xffffffff);
  Color get inset => Color(dark ? 0xff141e1b : 0xfff1f5f3);
  Color get ink => Color(dark ? 0xffe8f0ec : 0xff182725);
  Color get muted => Color(dark ? 0xffa7b6ae : 0xff60716c);
  Color get accent => Color(dark ? 0xff96d1bb : 0xff1a5c52);
  Color get accentInk => Color(dark ? 0xff101715 : 0xffffffff);
  Color get accentSurface => Color(dark ? 0xff173e35 : 0xffe4f0eb);
  Color get line => Color(dark ? 0xff23342e : 0xffe9efec);
  Color get amber => Color(dark ? 0xffffb873 : 0xff8b4b0b);
  Color get danger => Color(dark ? 0xfff87171 : 0xffa62535);
}

/// Semantic theme access shared by every surface and control family.
class VitalColors {
  VitalColors(BuildContext context)
    : dark = Theme.of(context).brightness == Brightness.dark,
      scheme = Theme.of(context).colorScheme;
  final bool dark;
  final ColorScheme scheme;
  Color get canvas => scheme.background;
  Color get surface => scheme.card;
  Color get inset => scheme.secondary;
  Color get ink => scheme.foreground;
  Color get muted => scheme.mutedForeground;
  Color get accent => scheme.primary;
  Color get accentInk => scheme.primaryForeground;
  Color get accentSurface => scheme.accent;
  Color get line => scheme.border;
  Color get amber => VitalPalette(dark).amber;
  Color get danger => VitalPalette(dark).danger;
}

/// Shared card renderer. Feature widgets compose it rather than copy its skin.
class VitalSurfaceFrame extends StatefulWidget {
  const VitalSurfaceFrame({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(VitalLayout.panelPadding),
    this.radius = VitalLayout.surfaceRadius,
    this.inset = false,
    this.sheet = false,
  });
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final bool inset, sheet;
  @override
  State<VitalSurfaceFrame> createState() => _VitalSurfaceFrameState();
}

class _VitalSurfaceFrameState extends State<VitalSurfaceFrame> {
  // Reparent the same content when bypassing AnimatedSize for reduced motion.
  // The pinned Flutter renderer cannot lay out a zero-duration AnimatedSize
  // whose child changes size without mutating itself during layout.
  final _contentKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final c = VitalColors(context);
    final content = KeyedSubtree(key: _contentKey, child: widget.child);
    return AnimatedContainer(
      duration: VitalMotion.duration(context, VitalMotion.theme),
      curve: VitalMotion.geometry,
      decoration: BoxDecoration(
        color: widget.inset ? c.inset : c.surface,
        borderRadius: BorderRadius.circular(widget.radius),
        border: c.dark ? null : Border.all(color: c.line.withValues(alpha: .7)),
        boxShadow: widget.inset
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(
                    alpha: c.dark ? (widget.sheet ? .2 : .12) : .025,
                  ),
                  blurRadius: widget.sheet ? 24 : 8,
                  offset: Offset(0, widget.sheet ? 8 : 3),
                ),
              ],
      ),
      padding: widget.padding,
      child: DefaultTextStyle.merge(
        style: VitalType.body.copyWith(color: c.ink),
        child: VitalMotion.reduced(context)
            ? content
            : AnimatedSize(
                duration: VitalMotion.expand,
                reverseDuration: VitalMotion.collapse,
                curve: VitalMotion.geometry,
                alignment: Alignment.topCenter,
                child: content,
              ),
      ),
    );
  }
}

enum VitalControlTone { primary, secondary, warning, danger, destructive }

/// One shadcn style resolver, including disabled/pending presentation and shape.
class VitalControlStyle extends StatelessWidget {
  const VitalControlStyle({
    super.key,
    required this.child,
    this.tone = VitalControlTone.secondary,
    this.quiet = false,
    this.isLoading = false,
    this.padding = const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
  });
  final Widget child;
  final VitalControlTone tone;
  final bool quiet, isLoading;
  final EdgeInsetsGeometry padding;
  @override
  Widget build(BuildContext context) {
    final c = VitalColors(context);
    final ink = switch (tone) {
      VitalControlTone.primary => c.accentInk,
      VitalControlTone.warning => c.amber,
      VitalControlTone.danger => c.danger,
      VitalControlTone.destructive => Colors.white,
      VitalControlTone.secondary => c.ink,
    };
    final fill = tone == VitalControlTone.primary
        ? c.accent
        : tone == VitalControlTone.destructive
        ? c.scheme.destructive
        : quiet
        ? Colors.transparent
        : c.inset;
    return VitalPress(
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minHeight: VitalLayout.target,
          minWidth: VitalLayout.target,
        ),
        child: ButtonStyleOverride(
          padding: (_, _, _) => padding,
          decoration: (_, states, decoration) {
            if (decoration is! BoxDecoration) return decoration;
            final disabled =
                states.contains(WidgetState.disabled) && !isLoading;
            return decoration.copyWith(
              color: disabled ? c.inset : fill,
              border: Border.all(
                color: disabled ? c.muted : Colors.transparent,
              ),
              borderRadius: BorderRadius.circular(VitalLayout.pillRadius),
              boxShadow: const [],
            );
          },
          textStyle: (_, states, _) => VitalType.label.copyWith(
            color: states.contains(WidgetState.disabled) && !isLoading
                ? c.muted
                : ink,
            fontWeight: FontWeight.w600,
          ),
          iconTheme: (_, states, theme) => theme.copyWith(
            color: states.contains(WidgetState.disabled) && !isLoading
                ? c.muted
                : ink,
            size: 18,
          ),
          child: child,
        ),
      ),
    );
  }
}
