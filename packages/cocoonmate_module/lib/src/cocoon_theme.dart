part of '../cocoonmate_module.dart';

class CocoonTheme {
  static const Color cream = Color(0xFFFFFAF6);
  static const Color warm = Color(0xFFFFF1E7);
  static const Color coral = Color(0xFFD96055);
  static const Color coralSoft = Color(0xFFFFDCD4);
  static const Color lilac = Color(0xFFF0EAF7);
  static const Color sage = Color(0xFFE7F2EA);
  static const Color sageStrong = Color(0xFF39785F);
  static const Color sky = Color(0xFFE8F3FA);
  static const Color skyStrong = Color(0xFF39769C);
  static const Color gold = Color(0xFFB97826);
  static const Color ink = Color(0xFF263248);
  static const Color muted = Color(0xFF667085);
  static const Color line = Color(0xFFE9DED6);

  static ThemeData light() {
    const scheme = ColorScheme.light(
      primary: coral,
      onPrimary: Colors.white,
      primaryContainer: coralSoft,
      onPrimaryContainer: ink,
      secondary: sageStrong,
      onSecondary: Colors.white,
      secondaryContainer: sage,
      onSecondaryContainer: ink,
      tertiary: skyStrong,
      onTertiary: Colors.white,
      tertiaryContainer: sky,
      onTertiaryContainer: ink,
      error: Color(0xFFB42318),
      surface: cream,
      onSurface: ink,
      outline: line,
      outlineVariant: Color(0xFFF1E8E2),
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: cream,
      visualDensity: VisualDensity.standard,
      splashFactory: InkSparkle.splashFactory,
      textTheme: const TextTheme(
        displaySmall: TextStyle(
          fontSize: 38,
          height: 1.12,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.8,
          color: ink,
        ),
        headlineSmall: TextStyle(
          fontSize: 24,
          height: 1.35,
          fontWeight: FontWeight.w800,
          color: ink,
        ),
        titleLarge: TextStyle(
          fontSize: 20,
          height: 1.4,
          fontWeight: FontWeight.w800,
          color: ink,
        ),
        titleMedium: TextStyle(
          fontSize: 17,
          height: 1.45,
          fontWeight: FontWeight.w700,
          color: ink,
        ),
        bodyLarge: TextStyle(fontSize: 16, height: 1.7, color: ink),
        bodyMedium: TextStyle(fontSize: 14, height: 1.65, color: ink),
        labelLarge: TextStyle(
          fontSize: 15,
          height: 1.35,
          fontWeight: FontWeight.w700,
        ),
        labelMedium: TextStyle(
          fontSize: 13,
          height: 1.4,
          fontWeight: FontWeight.w600,
          color: muted,
        ),
      ),
      cardTheme: const CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(22)),
          side: BorderSide(color: line),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 68,
        backgroundColor: Color(0xFFFFFDFC),
        indicatorColor: coralSoft,
        labelTextStyle: WidgetStatePropertyAll(
          TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: cream,
        foregroundColor: ink,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: ink,
          fontSize: 20,
          fontWeight: FontWeight.w800,
        ),
      ),
      dividerTheme: const DividerThemeData(color: line, thickness: 1),
    );
  }
}
