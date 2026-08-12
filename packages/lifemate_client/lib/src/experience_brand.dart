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
        primary: Color(0xFF448EF4),
        primaryDeep: Color(0xFF2167E8),
        secondary: Color(0xFF9BCBFF),
        background: Color(0xFFEAF3FF),
        backgroundDeep: Color(0xFFD9E9FF),
        softSurface: Color(0xFFF0F6FF),
        ink: Color(0xFF17366E),
        eyebrow: LifeMateRuntimeLocale.select(
          fa: LifeMateRuntimeLocale.select(
            fa: 'مراقبت خانوادگی',
            en: "Family care",
          ),
          en: "Family care",
        ),
        signInSubtitle: LifeMateRuntimeLocale.select(
          fa: LifeMateRuntimeLocale.select(
            fa: 'از اینکه برای مراقبت از خانواده به ما اعتماد کرده‌اید، خوشحالیم.',
            en: "We are glad that you have trusted us to take care of your family.",
          ),
          en: "We are glad that you have trusted us to take care of your family.",
        ),
        signUpSubtitle: LifeMateRuntimeLocale.select(
          fa: LifeMateRuntimeLocale.select(
            fa: 'برای مراقبت از عزیزانتان، یک حساب امن بسازید و با خیال آسوده ادامه دهید.',
            en: "To take care of your loved ones, create a secure account and continue with peace of mind.",
          ),
          en: "To take care of your loved ones, create a secure account and continue with peace of mind.",
        ),
        preparationSubtitle: LifeMateRuntimeLocale.select(
          fa: LifeMateRuntimeLocale.select(
            fa: 'در حال همگام‌سازی اطلاعات مراقبتی و اعضای خانواده…',
            en: "Syncing Caregiver and Family Member Information…",
          ),
          en: "Syncing Caregiver and Family Member Information…",
        ),
        heroIcon: Icons.favorite_rounded,
        accentIcon: Icons.favorite_rounded,
        decorativeIcon: Icons.volunteer_activism_rounded,
      );
    }
    return _BrandPalette(
      appName: appName,
      primary: Color(0xFF36B88A),
      primaryDeep: Color(0xFF199A70),
      secondary: Color(0xFF9BE2C7),
      background: Color(0xFFF1FBF6),
      backgroundDeep: Color(0xFFE0F5EB),
      softSurface: Color(0xFFF2FAF7),
      ink: Color(0xFF183A4D),
      eyebrow: LifeMateRuntimeLocale.select(
        fa: LifeMateRuntimeLocale.select(
          fa: 'برنامه درمان',
          en: "Treatment plan",
        ),
        en: "Treatment plan",
      ),
      signInSubtitle: LifeMateRuntimeLocale.select(
        fa: LifeMateRuntimeLocale.select(
          fa: 'برای یک مسیر درمانی روشن، آرام و هدفمند آماده شوید.',
          en: "Prepare for a clear, calm and purposeful treatment path.",
        ),
        en: "Prepare for a clear, calm and purposeful treatment path.",
      ),
      signUpSubtitle: LifeMateRuntimeLocale.select(
        fa: LifeMateRuntimeLocale.select(
          fa: 'سفر درمان خود را با آرامش آغاز کنید؛ برنامه شما همین‌جا شکل می‌گیرد.',
          en: "Begin your healing journey with peace; This is where your program takes shape.",
        ),
        en: "Begin your healing journey with peace; This is where your program takes shape.",
      ),
      preparationSubtitle: LifeMateRuntimeLocale.select(
        fa: LifeMateRuntimeLocale.select(
          fa: 'در حال آماده‌سازی برنامه درمان و همگام‌سازی اطلاعات شما…',
          en: "Preparing your treatment plan and syncing your data…",
        ),
        en: "Preparing your treatment plan and syncing your data…",
      ),
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
