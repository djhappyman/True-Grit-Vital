import 'package:shadcn_flutter/shadcn_flutter.dart';

ThemeData vitalTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final base = dark ? ColorSchemes.darkZinc : ColorSchemes.lightZinc;
  return ThemeData(
    radius: 1,
    colorScheme: base.copyWith(
      background: () => Color(dark ? 0xFF181A1D : 0xFFFFFFFF),
      foreground: () => Color(dark ? 0xFFF1F3F5 : 0xFF202428),
      card: () => Color(dark ? 0xFF24272B : 0xFFF3F5F6),
      cardForeground: () => Color(dark ? 0xFFF1F3F5 : 0xFF202428),
      popover: () => Color(dark ? 0xFF24272B : 0xFFFFFFFF),
      popoverForeground: () => Color(dark ? 0xFFF1F3F5 : 0xFF202428),
      primary: () => Color(dark ? 0xFFA0D7BC : 0xFF24684F),
      primaryForeground: () => Color(dark ? 0xFF153326 : 0xFFFFFFFF),
      destructive: () => dark ? base.destructive : const Color(0xFFA62535),
      secondary: () => Color(dark ? 0xFF343A41 : 0xFFF3F5F6),
      secondaryForeground: () => Color(dark ? 0xFFF1F3F5 : 0xFF202428),
      accent: () => Color(dark ? 0xFF294537 : 0xFFE2F1E9),
      accentForeground: () => Color(dark ? 0xFFF1F3F5 : 0xFF202428),
      muted: () => Color(dark ? 0xFF24272B : 0xFFF3F5F6),
      mutedForeground: () => Color(dark ? 0xFFB4BAC2 : 0xFF58616B),
      border: () => Color(dark ? 0xFF3C4148 : 0xFFDEE2E6),
      input: () => Color(dark ? 0xFF3C4148 : 0xFFDEE2E6),
      ring: () => Color(dark ? 0xFFA0D7BC : 0xFF24684F),
    ),
  );
}
