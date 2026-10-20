import 'package:shadcn_flutter/shadcn_flutter.dart';

ThemeData vitalTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final base = dark ? ColorSchemes.darkZinc : ColorSchemes.lightZinc;
  return ThemeData(
    radius: 1,
    typography: const Typography.geist(
      sans: TextStyle(fontFamily: 'NotoSans', height: 1.45),
      h1: TextStyle(
        fontSize: 30,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.8,
      ),
      h2: TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.5,
      ),
      h3: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.3,
      ),
      h4: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
    ),
    colorScheme: base.copyWith(
      background: () => Color(dark ? 0xFF101715 : 0xFFFFFFFF),
      foreground: () => Color(dark ? 0xFFE8F0EC : 0xFF182725),
      card: () => Color(dark ? 0xFF192420 : 0xFFF6F8F7),
      cardForeground: () => Color(dark ? 0xFFE8F0EC : 0xFF182725),
      popover: () => Color(dark ? 0xFF192420 : 0xFFFFFFFF),
      popoverForeground: () => Color(dark ? 0xFFE8F0EC : 0xFF182725),
      primary: () => Color(dark ? 0xFF96D1BB : 0xFF1A5C52),
      primaryForeground: () => Color(dark ? 0xFF102B22 : 0xFFFFFFFF),
      destructive: () => dark ? base.destructive : const Color(0xFFA62535),
      secondary: () => Color(dark ? 0xFF101B17 : 0xFFEDF2EF),
      secondaryForeground: () => Color(dark ? 0xFFE8F0EC : 0xFF182725),
      accent: () => Color(dark ? 0xFF1A3D33 : 0xFFDCEBE5),
      accentForeground: () => Color(dark ? 0xFFB0DFCC : 0xFF1A5C52),
      muted: () => Color(dark ? 0xFF14201B : 0xFFF2F5F3),
      mutedForeground: () => Color(dark ? 0xFFA7B6AE : 0xFF5B6B68),
      border: () => Color(dark ? 0xFF2D4036 : 0xFFDDE5E0),
      input: () => Color(dark ? 0xFF708A7C : 0xFF6B7D74),
      ring: () => Color(dark ? 0xFF96D1BB : 0xFF1A5C52),
    ),
  );
}
