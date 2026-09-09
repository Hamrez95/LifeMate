part of '../cocoonmate_module.dart';

abstract final class CocoonColors {
  static const canvas = Color(0xFFFFF8F2);
  static const surface = Color(0xFFFFFCF9);
  static const surfaceRaised = Colors.white;
  static const warm = Color(0xFFFFEEE5);
  static const coral = Color(0xFFC75C62);
  static const coralAction = Color(0xFFA8434D);
  static const coralSoft = Color(0xFFFFDCD8);
  static const lilac = Color(0xFF8765B4);
  static const lilacSoft = Color(0xFFF1EAF8);
  static const sage = Color(0xFFE4F1E9);
  static const sageStrong = Color(0xFF2F7258);
  static const sky = Color(0xFFE7F2F8);
  static const skyStrong = Color(0xFF316E91);
  static const attention = Color(0xFF8B5B13);
  static const attentionSoft = Color(0xFFFFF0D5);
  static const error = Color(0xFFA9382E);
  static const errorSoft = Color(0xFFFFE4E0);
  static const ink = Color(0xFF252B3A);
  static const muted = Color(0xFF5F6778);
  static const line = Color(0xFFE7DDD6);
  static const disabled = Color(0xFF9A9EAA);
}

abstract final class CocoonSpacing {
  static const double xxs = 4;
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 20;
  static const double xl = 24;
  static const double section = 32;
  static const double pageEnd = 36;
}

abstract final class CocoonRadii {
  static const double chip = 12;
  static const double control = 16;
  static const double card = 22;
  static const double hero = 28;
  static const double sheet = 30;
}

abstract final class CocoonElevation {
  static const subtle = <BoxShadow>[
    BoxShadow(color: Color(0x0F252B3A), blurRadius: 18, offset: Offset(0, 8)),
  ];
  static const hero = <BoxShadow>[
    BoxShadow(color: Color(0x18A8434D), blurRadius: 34, offset: Offset(0, 14)),
  ];
}

abstract final class CocoonMotion {
  static const fast = Duration(milliseconds: 140);
  static const standard = Duration(milliseconds: 220);
  static const slow = Duration(milliseconds: 320);
  static const entranceCurve = Curves.easeOutCubic;
  static const exitCurve = Curves.easeInCubic;

  static Duration duration(BuildContext context, Duration preferred) {
    return MediaQuery.maybeOf(context)?.disableAnimations ?? false
        ? Duration.zero
        : preferred;
  }
}

enum CocoonMedicalLevel { informational, attention, contactClinician, urgent }

class CocoonTheme {
  static const Color cream = CocoonColors.canvas;
  static const Color warm = CocoonColors.warm;
  static const Color coral = CocoonColors.coral;
  static const Color coralSoft = CocoonColors.coralSoft;
  static const Color lilac = CocoonColors.lilacSoft;
  static const Color sage = CocoonColors.sage;
  static const Color sageStrong = CocoonColors.sageStrong;
  static const Color sky = CocoonColors.sky;
  static const Color skyStrong = CocoonColors.skyStrong;
  static const Color gold = CocoonColors.attention;
  static const Color ink = CocoonColors.ink;
  static const Color muted = CocoonColors.muted;
  static const Color line = CocoonColors.line;
  static const String fontFamily = 'packages/cocoonmate_module/CocoonVazirmatn';

  static ThemeData light() {
    const scheme = ColorScheme.light(
      primary: CocoonColors.coralAction,
      onPrimary: Colors.white,
      primaryContainer: coralSoft,
      onPrimaryContainer: ink,
      secondary: CocoonColors.lilac,
      onSecondary: Colors.white,
      secondaryContainer: CocoonColors.lilacSoft,
      onSecondaryContainer: ink,
      tertiary: sageStrong,
      onTertiary: Colors.white,
      tertiaryContainer: sage,
      onTertiaryContainer: ink,
      error: CocoonColors.error,
      surface: CocoonColors.surface,
      onSurface: ink,
      outline: line,
      outlineVariant: Color(0xFFF1E8E2),
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: cream,
      visualDensity: VisualDensity.standard,
      splashFactory: InkRipple.splashFactory,
      fontFamily: fontFamily,
      fontFamilyFallback: const ['Roboto', 'Arial', 'sans-serif'],
      textTheme: const TextTheme(
        displaySmall: TextStyle(
          fontSize: 40,
          height: 1.12,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.8,
          color: ink,
        ),
        headlineSmall: TextStyle(
          fontSize: 24,
          height: 1.35,
          fontWeight: FontWeight.w700,
          color: ink,
        ),
        titleLarge: TextStyle(
          fontSize: 20,
          height: 1.4,
          fontWeight: FontWeight.w700,
          color: ink,
        ),
        titleMedium: TextStyle(
          fontSize: 17,
          height: 1.45,
          fontWeight: FontWeight.w600,
          color: ink,
        ),
        bodyLarge: TextStyle(fontSize: 16, height: 1.72, color: ink),
        bodyMedium: TextStyle(fontSize: 14, height: 1.65, color: ink),
        labelLarge: TextStyle(
          fontSize: 15,
          height: 1.35,
          fontWeight: FontWeight.w600,
        ),
        labelMedium: TextStyle(
          fontSize: 13,
          height: 1.4,
          fontWeight: FontWeight.w500,
          color: muted,
        ),
      ),
      cardTheme: const CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(CocoonRadii.card)),
          side: BorderSide(color: line),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 72,
        backgroundColor: CocoonColors.surfaceRaised,
        indicatorColor: coralSoft,
        labelTextStyle: WidgetStatePropertyAll(
          TextStyle(
            fontFamily: fontFamily,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 56),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(CocoonRadii.control),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: CocoonColors.surfaceRaised,
        contentPadding: const EdgeInsetsDirectional.all(CocoonSpacing.md),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(CocoonRadii.control),
          borderSide: const BorderSide(color: CocoonColors.line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(CocoonRadii.control),
          borderSide: const BorderSide(color: CocoonColors.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(CocoonRadii.control),
          borderSide: const BorderSide(
            color: CocoonColors.coralAction,
            width: 2,
          ),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: CocoonColors.surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(CocoonRadii.sheet),
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
          fontFamily: fontFamily,
          fontSize: 20,
          fontWeight: FontWeight.w800,
        ),
      ),
      dividerTheme: const DividerThemeData(color: line, thickness: 1),
    );
  }
}
