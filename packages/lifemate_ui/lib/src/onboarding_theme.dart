import 'package:flutter/material.dart';

enum LifeMateOnboardingBrand { shared, wellMate, womenHealth, careMate }

@immutable
class LifeMateOnboardingTheme {
  const LifeMateOnboardingTheme({
    required this.brand,
    required this.background,
    required this.surface,
    required this.surfaceAlt,
    required this.ink,
    required this.muted,
    required this.primary,
    required this.secondary,
    required this.soft,
    required this.border,
    required this.success,
    required this.error,
  });

  final LifeMateOnboardingBrand brand;
  final Color background;
  final Color surface;
  final Color surfaceAlt;
  final Color ink;
  final Color muted;
  final Color primary;
  final Color secondary;
  final Color soft;
  final Color border;
  final Color success;
  final Color error;

  static const shared = LifeMateOnboardingTheme(
    brand: LifeMateOnboardingBrand.shared,
    background: Color(0xFFFAF7F2),
    surface: Color(0xFFFFFFFF),
    surfaceAlt: Color(0xFFF2ECE5),
    ink: Color(0xFF25232A),
    muted: Color(0xFF69636D),
    primary: Color(0xFF51475A),
    secondary: Color(0xFFB98B64),
    soft: Color(0xFFEEE8F0),
    border: Color(0xFFDED6CF),
    success: Color(0xFF237A5A),
    error: Color(0xFFB4473F),
  );

  static const wellMate = LifeMateOnboardingTheme(
    brand: LifeMateOnboardingBrand.wellMate,
    background: Color(0xFFF3F8F5),
    surface: Color(0xFFFFFFFF),
    surfaceAlt: Color(0xFFE8F4ED),
    ink: Color(0xFF1F302A),
    muted: Color(0xFF617169),
    primary: Color(0xFF12835F),
    secondary: Color(0xFF62B996),
    soft: Color(0xFFDFF2E9),
    border: Color(0xFFCFE2D7),
    success: Color(0xFF12835F),
    error: Color(0xFFB4473F),
  );

  static const womenHealth = LifeMateOnboardingTheme(
    brand: LifeMateOnboardingBrand.womenHealth,
    background: Color(0xFFFFF9F4),
    surface: Color(0xFFFFFFFF),
    surfaceAlt: Color(0xFFF6EEFA),
    ink: Color(0xFF3D3542),
    muted: Color(0xFF756B77),
    primary: Color(0xFFC83B60),
    secondary: Color(0xFF8765B4),
    soft: Color(0xFFFCE5EC),
    border: Color(0xFFEAD7E2),
    success: Color(0xFF387E72),
    error: Color(0xFFB4473F),
  );

  static const careMate = LifeMateOnboardingTheme(
    brand: LifeMateOnboardingBrand.careMate,
    background: Color(0xFFF3F7FC),
    surface: Color(0xFFFFFFFF),
    surfaceAlt: Color(0xFFE6EFFA),
    ink: Color(0xFF263754),
    muted: Color(0xFF5F7088),
    primary: Color(0xFF3272B7),
    secondary: Color(0xFF73A9E4),
    soft: Color(0xFFE1EDFA),
    border: Color(0xFFCCDDEF),
    success: Color(0xFF237A6A),
    error: Color(0xFFB4473F),
  );

  static LifeMateOnboardingTheme forBrand(LifeMateOnboardingBrand brand) {
    return switch (brand) {
      LifeMateOnboardingBrand.shared => shared,
      LifeMateOnboardingBrand.wellMate => wellMate,
      LifeMateOnboardingBrand.womenHealth => womenHealth,
      LifeMateOnboardingBrand.careMate => careMate,
    };
  }
}

abstract final class LifeMateOnboardingMetrics {
  static const double screenGutter = 24;
  static const double compactGap = 8;
  static const double contentGap = 16;
  static const double sectionGap = 24;
  static const double majorGap = 32;
  static const double controlRadius = 18;
  static const double cardRadius = 22;
  static const double ctaHeight = 56;
  static const double inputHeight = 58;
  static const double minTouchTarget = 48;
  static const double progressHeight = 4;
}
