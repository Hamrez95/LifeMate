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

    void open(Widget page) {
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
    }

    return LifeMateSharedProfileScreen(
      apiClient: context.read<LifeMateApiClient>(),
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
            loc['profile_no_subscription'] ?? (isPersian ? 'اشتراک' : 'Subscription'),
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
