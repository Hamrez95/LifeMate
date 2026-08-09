import 'package:flutter/material.dart';
import 'package:lifemate_client/lifemate_client.dart';
import 'package:lifemate_ui/lifemate_ui.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_version.dart';
import '../../core/theme/app_style.dart';
import '../../core/utils/string_extensions.dart';
import '../../localization/app_localizations.dart';
import '../../localization/locale_provider.dart';
import '../../providers/settings_provider.dart';
import 'care_access_screen.dart';
import 'editable_profile_screen.dart';
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
        accent: AppColors.primary,
        titleColor: AppColors.darkBlue,
        secondaryText: AppColors.textSecondary,
        cardBackground: AppColors.cardBackground,
      ),
      labels: LifeMateProfileLabels(
        personalInfo: loc['profile_personal_info'] ?? 'اطلاعات شخصی',
        healthProfile: loc['profile_health_profile'] ?? 'پرونده سلامت',
        careManagement: loc['profile_caregivers'] ?? 'مراقبان',
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
      appName: 'WellMate',
      versionLabel: 'WellMate $wellMateAppVersion'.toPersianDigit(isPersian),
      fallbackUserName: isPersian ? 'کاربر LifeMate' : 'LifeMate user',
      isPersian: isPersian,
      onNotifications: () => open(const NotificationCenterScreen()),
      onEditProfile: () => open(const EditableProfileScreen()),
      onHealthProfile: () => open(const HealthRecordScreen()),
      onCareManagement: () => open(const CareAccessScreen()),
      onAppSettings: () => showDialog<void>(
        context: context,
        builder: (_) => _SettingsDialog(mainFont: mainFont),
      ),
      onReferral: () => open(const ReferralScreen()),
      onSupport: () => open(const SupportScreen()),
      onManageSubscriptions: () => open(const SubscriptionScreen()),
    );
  }
}

class _SettingsDialog extends StatefulWidget {
  const _SettingsDialog({required this.mainFont});

  final String mainFont;

  @override
  State<_SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<_SettingsDialog> {
  late double _textSize;

  @override
  void initState() {
    super.initState();
    _textSize = context.read<SettingsProvider>().textScaleFactor;
  }

  @override
  Widget build(BuildContext context) {
    final localeProvider = context.watch<LocaleProvider>();
    final settingsProvider = context.read<SettingsProvider>();
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: Text(
        'تنظیمات برنامه',
        style: TextStyle(
          fontFamily: widget.mainFont,
          fontWeight: FontWeight.bold,
        ),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'زبان',
              style: TextStyle(
                fontFamily: widget.mainFont,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'fa', label: Text('فارسی')),
                ButtonSegment(value: 'en', label: Text('English')),
              ],
              selected: {localeProvider.locale.languageCode},
              onSelectionChanged: (values) {
                localeProvider.setLocale(Locale(values.first));
              },
            ),
            const SizedBox(height: 24),
            Text(
              'اندازه متن',
              style: TextStyle(
                fontFamily: widget.mainFont,
                fontWeight: FontWeight.bold,
              ),
            ),
            Slider(
              value: _textSize,
              min: 0.8,
              max: 1.5,
              divisions: 7,
              label: _textSize.toStringAsFixed(1),
              activeColor: AppColors.primary,
              onChanged: (value) {
                setState(() => _textSize = value);
                settingsProvider.updateTextScale(value);
              },
            ),
          ],
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('تمام'),
        ),
      ],
    );
  }
}
