import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../ui/vital_foundation.dart';

ThemeData vitalTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final palette = VitalPalette(dark);
  final base = dark ? ColorSchemes.darkZinc : ColorSchemes.lightZinc;
  return ThemeData(
    radius: 1,
    typography: const Typography.geist(
      sans: VitalType.body,
      h1: VitalType.title,
      h2: VitalType.detailTitle,
      h3: VitalType.section,
      h4: VitalType.record,
    ),
    colorScheme: base.copyWith(
      background: () => palette.canvas,
      foreground: () => palette.ink,
      card: () => palette.surface,
      cardForeground: () => palette.ink,
      popover: () => palette.surface,
      popoverForeground: () => palette.ink,
      primary: () => palette.accent,
      primaryForeground: () => palette.accentInk,
      destructive: () => dark ? base.destructive : const Color(0xFFA62535),
      secondary: () => palette.inset,
      secondaryForeground: () => palette.ink,
      accent: () => palette.accentSurface,
      accentForeground: () => palette.accent,
      muted: () => palette.ink.withValues(alpha: .04),
      mutedForeground: () => palette.muted,
      border: () => palette.line,
      input: () => Color(dark ? 0xFF708A7C : 0xFF6B7D74),
      ring: () => palette.accent,
    ),
  );
}
