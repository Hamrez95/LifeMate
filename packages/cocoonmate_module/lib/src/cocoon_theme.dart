part of '../cocoonmate_module.dart';

class CocoonTheme {
  static const Color cream = Color(0xFFFFF8F1);
  static const Color coral = Color(0xFFE96F61);
  static const Color lilac = Color(0xFFECE4F8);
  static const Color sage = Color(0xFFE6EFE7);
  static const Color ink = Color(0xFF2E2A28);

  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: coral,
      brightness: Brightness.light,
      surface: cream,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: cream,
      visualDensity: VisualDensity.standard,
      cardTheme: const CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(24)),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 72,
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
    );
  }
}
