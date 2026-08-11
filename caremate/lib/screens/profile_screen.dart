import 'package:flutter/material.dart';
import 'package:lifemate_client/lifemate_client.dart';
import 'package:lifemate_ui/lifemate_ui.dart';
import 'package:provider/provider.dart';

import '../core/constants/app_colors.dart';
import '../core/constants/app_version.dart';
import '../core/localization/app_localizations.dart';
import '../core/localization/locale_provider.dart';
import '../core/utils/string_extensions.dart';
import 'editable_profile_screen.dart';
import 'feature_preview_screen.dart';
import 'profile_destination_screens.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final localeProvider = context.watch<LocaleProvider>();
    final isPersian = localeProvider.locale.languageCode == 'fa';
    final mainFont = isPersian ? 'Vazir' : 'Poppins';
    final api = context.read<LifeMateApiClient>();

    void open(Widget page) {
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
    }

    final sharedProfile = LifeMateSharedProfileScreen(
      apiClient: api,
      theme: const LifeMateProfileThemeData(
        background: AppColors.background,
        accent: AppColors.primaryBlue,
        titleColor: AppColors.darkBlue,
        secondaryText: AppColors.secondaryText,
        cardBackground: AppColors.cardBackground,
      ),
      labels: LifeMateProfileLabels(
        personalInfo: loc['profile_personal_info'] ?? 'اطلاعات شخصی',
        healthProfile: loc['profile_health_profile'] ?? 'پرونده سلامت',
        careManagement:
            loc['profile_caregivers'] ?? 'مدیریت افراد تحت مراقبت',
        appSettings: loc['profile_app_settings'] ?? 'تنظیمات برنامه',
        referral: loc['profile_referral_code'] ?? 'کد معرف',
        support: loc['profile_support'] ?? 'پشتیبانی',
        logout: loc['profile_logout'] ?? 'خروج از حساب',
        subscriptionTitle:
            loc['profile_no_subscription'] ??
            (isPersian ? 'اشتراک' : 'Subscription'),
        manageSubscriptions:
            loc['profile_buy_plan'] ??
            (isPersian ? 'مدیریت اشتراک‌ها' : 'Manage subscriptions'),
        referralSubtitle: isPersian ? 'در دست توسعه' : 'Coming soon',
        supportSubtitle: isPersian
            ? 'راهنما فعال؛ ارسال تیکت در دست توسعه'
            : 'Help is available; ticketing is coming soon',
      ),
      fontFamily: mainFont,
      appName: 'CareMate',
      versionLabel: 'CareMate $careMateAppVersion'.toPersianDigit(isPersian),
      fallbackUserName: isPersian ? 'کاربر LifeMate' : 'LifeMate user',
      isPersian: isPersian,
      onNotifications: () => open(const CareMateNotificationsScreen()),
      onEditProfile: () => open(const CareMateEditableProfileScreen()),
      onHealthProfile: () => open(
        const CareMateFeaturePreviewScreen(initialIndex: 2),
      ),
      onCareManagement: () => open(
        const CareMateFeaturePreviewScreen(initialIndex: 3),
      ),
      onAppSettings: () => showDialog<void>(
        context: context,
        builder: (_) => _LanguageDialog(mainFont: mainFont),
      ),
      onReferral: () => open(const CareMateReferralScreen()),
      onSupport: () => open(const CareMateSupportScreen()),
      onManageSubscriptions: () => open(const CareMateSubscriptionScreen()),
    );

    return ColoredBox(
      color: AppColors.background,
      child: Column(
        children: [
          Expanded(child: sharedProfile),
          SafeArea(
            top: false,
            minimum: const EdgeInsets.fromLTRB(24, 6, 24, 12),
            child: _AccountExportButton(
              fontFamily: mainFont,
              onPressed: () => showLifeMateAccountExportDialog(
                context,
                fontFamily: mainFont,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AccountExportButton extends StatelessWidget {
  const _AccountExportButton({
    required this.fontFamily,
    required this.onPressed,
  });

  final String fontFamily;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'دریافت نسخه داده‌های من',
      hint: 'خروجی امن اطلاعات حساب را از پنجره اشتراک گوشی دریافت می‌کند',
      child: Material(
        color: const Color(0xFFEEF5FF),
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          key: const ValueKey('caremate-account-export'),
          borderRadius: BorderRadius.circular(20),
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(14, 11, 14, 11),
            child: Row(
              children: [
                const Icon(
                  Icons.file_download_outlined,
                  color: AppColors.primaryBlue,
                  size: 27,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'دریافت نسخه داده‌های من',
                        style: TextStyle(
                          fontFamily: fontFamily,
                          color: AppColors.darkBlue,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'فقط داده‌های متعلق به حساب و پروفایل خودت',
                        style: TextStyle(
                          fontFamily: fontFamily,
                          color: AppColors.secondaryText,
                          fontSize: 11.5,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.chevron_left_rounded,
                  color: AppColors.primaryBlue,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LanguageDialog extends StatelessWidget {
  const _LanguageDialog({required this.mainFont});

  final String mainFont;

  @override
  Widget build(BuildContext context) {
    final localeProvider = context.watch<LocaleProvider>();
    final isPersian = localeProvider.locale.languageCode == 'fa';
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: Text(
        isPersian ? 'زبان' : 'Language',
        style: TextStyle(fontFamily: mainFont, fontWeight: FontWeight.bold),
      ),
      content: SegmentedButton<String>(
        segments: const [
          ButtonSegment(value: 'fa', label: Text('فارسی')),
          ButtonSegment(value: 'en', label: Text('English')),
        ],
        selected: {localeProvider.locale.languageCode},
        onSelectionChanged: (values) {
          localeProvider.setLocale(Locale(values.first));
        },
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(isPersian ? 'تمام' : 'Done'),
        ),
      ],
    );
  }
}
