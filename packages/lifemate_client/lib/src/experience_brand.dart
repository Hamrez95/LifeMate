part of 'lifemate_experience_gate.dart';

class _BrandPalette {
  const _BrandPalette({
    required this.appName,
    required this.primary,
    required this.primaryDeep,
    required this.secondary,
    required this.background,
    required this.backgroundDeep,
    required this.softSurface,
    required this.ink,
    required this.eyebrow,
    required this.signInSubtitle,
    required this.signUpSubtitle,
    required this.preparationSubtitle,
    required this.heroIcon,
    required this.accentIcon,
    required this.decorativeIcon,
  });

  factory _BrandPalette.forApp(String appName) {
    final careMate = appName.toLowerCase().contains('care');
    if (careMate) {
      return _BrandPalette(
        appName: appName,
        primary: const Color(0xFF448EF4),
        primaryDeep: const Color(0xFF2167E8),
        secondary: const Color(0xFF9BCBFF),
        background: const Color(0xFFEAF3FF),
        backgroundDeep: const Color(0xFFD9E9FF),
        softSurface: const Color(0xFFF0F6FF),
        ink: const Color(0xFF17366E),
        eyebrow: 'مراقبت خانوادگی',
        signInSubtitle:
            'از اینکه برای مراقبت از خانواده به ما اعتماد کرده‌اید، خوشحالیم.',
        signUpSubtitle:
            'برای مراقبت از عزیزانتان، یک حساب امن بسازید و با خیال آسوده ادامه دهید.',
        preparationSubtitle:
            'در حال همگام‌سازی اطلاعات مراقبتی و اعضای خانواده…',
        heroIcon: Icons.favorite_rounded,
        accentIcon: Icons.favorite_rounded,
        decorativeIcon: Icons.volunteer_activism_rounded,
      );
    }
    return _BrandPalette(
      appName: appName,
      primary: const Color(0xFF36B88A),
      primaryDeep: const Color(0xFF199A70),
      secondary: const Color(0xFF9BE2C7),
      background: const Color(0xFFF1FBF6),
      backgroundDeep: const Color(0xFFE0F5EB),
      softSurface: const Color(0xFFF2FAF7),
      ink: const Color(0xFF183A4D),
      eyebrow: 'برنامه درمان',
      signInSubtitle: 'برای یک مسیر درمانی روشن، آرام و هدفمند آماده شوید.',
      signUpSubtitle:
          'سفر درمان خود را با آرامش آغاز کنید؛ برنامه شما همین‌جا شکل می‌گیرد.',
      preparationSubtitle:
          'در حال آماده‌سازی برنامه درمان و همگام‌سازی اطلاعات شما…',
      heroIcon: Icons.health_and_safety_rounded,
      accentIcon: Icons.eco_rounded,
      decorativeIcon: Icons.health_and_safety_outlined,
    );
  }

  final String appName;
  final Color primary;
  final Color primaryDeep;
  final Color secondary;
  final Color background;
  final Color backgroundDeep;
  final Color softSurface;
  final Color ink;
  final String eyebrow;
  final String signInSubtitle;
  final String signUpSubtitle;
  final String preparationSubtitle;
  final IconData heroIcon;
  final IconData accentIcon;
  final IconData decorativeIcon;
}
