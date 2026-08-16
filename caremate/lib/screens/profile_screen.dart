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

    return LifeMateSharedProfileScreen(
      apiClient: api,
      theme: LifeMateProfileThemeData(
        background: AppColors.background,
        accent: AppColors.primaryBlue,
        titleColor: AppColors.darkBlue,
        secondaryText: AppColors.secondaryText,
        cardBackground: AppColors.cardBackground,
      ),
      labels: LifeMateProfileLabels(
        personalInfo:
            loc['profile_personal_info'] ??
            LifeMateRuntimeLocale.select(
              fa: LifeMateRuntimeLocale.select(
                fa: 'اطلاعات شخصی',
                en: "Personal information",
              ),
              en: "Personal information",
            ),
        healthProfile:
            loc['profile_health_profile'] ??
            LifeMateRuntimeLocale.select(
              fa: LifeMateRuntimeLocale.select(
                fa: 'پرونده سلامت',
                en: "health file",
              ),
              en: "health file",
            ),
        careManagement:
            loc['profile_caregivers'] ??
            LifeMateRuntimeLocale.select(
              fa: LifeMateRuntimeLocale.select(
                fa: 'مدیریت افراد تحت مراقبت',
                en: "Management of people under care",
              ),
              en: "Management of people under care",
            ),
        appSettings:
            loc['profile_app_settings'] ??
            LifeMateRuntimeLocale.select(
              fa: LifeMateRuntimeLocale.select(
                fa: 'تنظیمات برنامه',
                en: "Program settings",
              ),
              en: "Program settings",
            ),
        referral:
            loc['profile_referral_code'] ??
            LifeMateRuntimeLocale.select(
              fa: 'کد معرف',
              en: "Identification code",
            ),
        support: loc['profile_support'] ?? 'پشتیبانی',
        logout: loc['profile_logout'] ?? 'خروج از حساب',
        subscriptionTitle:
            loc['profile_no_subscription'] ??
            (isPersian ? 'اشتراک' : 'Subscription'),
        manageSubscriptions:
            loc['profile_buy_plan'] ??
            (isPersian ? 'مدیریت اشتراک‌ها' : 'Manage subscriptions'),
        referralSubtitle: isPersian
            ? LifeMateRuntimeLocale.select(
                fa: 'در دست توسعه',
                en: "Under development",
              )
            : 'Coming soon',
        supportSubtitle: isPersian
            ? LifeMateRuntimeLocale.select(
                fa: 'راهنما فعال؛ ارسال تیکت در دست توسعه',
                en: "active guide; Submit ticket under development",
              )
            : 'Help is available; ticketing is coming soon',
      ),
      fontFamily: mainFont,
      appName: 'CareMate',
      versionLabel: 'CareMate $careMateAppVersion'.toPersianDigit(isPersian),
      fallbackUserName: isPersian
          ? LifeMateRuntimeLocale.select(
              fa: 'کاربر LifeMate',
              en: "LifeMate user",
            )
          : 'LifeMate user',
      isPersian: isPersian,
      onNotifications: () => open(CareMateNotificationsScreen()),
      onEditProfile: () => open(CareMateEditableProfileScreen()),
      onHealthProfile: () =>
          open(CareMateFeaturePreviewScreen(initialIndex: 2)),
      onCareManagement: () => open(
        LifeMateCareAccessInventoryScreen(
          apiClient: api,
          role: LifeMateCareAccessRole.caregiver,
          accent: AppColors.primaryBlue,
          background: AppColors.background,
          ink: AppColors.darkBlue,
          onManage: () => open(CareMateFeaturePreviewScreen(initialIndex: 3)),
        ),
      ),
      onAppSettings: () => showDialog<void>(
        context: context,
        builder: (_) => _LanguageDialog(mainFont: mainFont),
      ),
      onReferral: () => open(CareMateReferralScreen()),
      onSupport: () => open(CareMateSupportScreen()),
      onManageSubscriptions: () => open(CareMateSubscriptionScreen()),
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
        segments: [
          ButtonSegment(
            value: 'fa',
            label: Text(
              LifeMateRuntimeLocale.select(
                fa: LifeMateRuntimeLocale.select(fa: 'فارسی', en: "Farsi"),
                en: "Farsi",
              ),
            ),
          ),
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
          child: Text(
            isPersian
                ? LifeMateRuntimeLocale.select(fa: 'تمام', en: "all")
                : 'Done',
          ),
        ),
      ],
    );
  }
}
