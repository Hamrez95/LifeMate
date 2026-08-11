import 'package:flutter/material.dart';
import 'package:lifemate_client/lifemate_client.dart';
import 'package:lifemate_ui/lifemate_ui.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_version.dart';
import '../../core/theme/app_style.dart';
import '../../core/utils/string_extensions.dart';
import '../../core/widgets/medication_home_widget_service.dart';
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
    final api = context.read<LifeMateApiClient>();

    void open(Widget page) {
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
    }

    final sharedProfile = LifeMateSharedProfileScreen(
      apiClient: api,
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

    return ColoredBox(
      color: AppColors.background,
      child: Column(
        children: [
          Expanded(child: sharedProfile),
          SafeArea(
            top: false,
            minimum: const EdgeInsets.fromLTRB(24, 6, 24, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _AccountExportButton(
                  fontFamily: mainFont,
                  onPressed: () => showLifeMateAccountExportDialog(
                    context,
                    fontFamily: mainFont,
                  ),
                ),
                if (MedicationHomeWidgetService.isSupportedPlatform) ...[
                  const SizedBox(height: 8),
                  _MedicationWidgetProfileButton(
                    fontFamily: mainFont,
                    onPressed: () => _pinMedicationWidget(context, api),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pinMedicationWidget(
    BuildContext context,
    LifeMateApiClient api,
  ) async {
    try {
      await MedicationHomeWidgetService.refreshFromApi(api);
      final pinRequested = await MedicationHomeWidgetService.requestPin();
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(
            pinRequested
                ? 'پنجره افزودن ویجت باز شد؛ «افزودن» را بزنید.'
                : 'برای افزودن دستی، صفحه اصلی را نگه دارید و از بخش ویجت‌ها WellMate را انتخاب کنید.',
          ),
        ),
      );
    } catch (error) {
      debugPrint('WellMate medication widget pin failed: $error');
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('آماده‌سازی ویجت انجام نشد؛ دوباره تلاش کنید.'),
        ),
      );
    }
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
      hint: 'خروجی امن اطلاعات حساب و سلامت را از پنجره اشتراک گوشی دریافت می‌کند',
      child: Material(
        color: const Color(0xFFEAF8F1),
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          key: const ValueKey('wellmate-account-export'),
          borderRadius: BorderRadius.circular(20),
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(14, 11, 14, 11),
            child: Row(
              children: [
                const Icon(
                  Icons.file_download_outlined,
                  color: AppColors.primary,
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
                        'خروجی JSON فقط با درخواست خودت آماده می‌شود',
                        style: TextStyle(
                          fontFamily: fontFamily,
                          color: AppColors.textSecondary,
                          fontSize: 11.5,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_left_rounded, color: AppColors.primary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MedicationWidgetProfileButton extends StatelessWidget {
  const _MedicationWidgetProfileButton({
    required this.fontFamily,
    required this.onPressed,
  });

  final String fontFamily;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'افزودن ویجت مصرف به صفحه اصلی',
      hint: 'نمایش درمان بعدی و ثبت سریع مصرف از صفحه اصلی گوشی',
      child: Material(
        color: const Color(0xFFFFF4E9),
        borderRadius: BorderRadius.circular(22),
        elevation: 3,
        shadowColor: const Color(0x22E76D5B),
        child: InkWell(
          key: const ValueKey('wellmate-add-medication-widget'),
          borderRadius: BorderRadius.circular(22),
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(14, 12, 14, 12),
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFDDF2E5),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Image.asset(
                    'assets/images/WellMateWithoutBack.png',
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const Icon(
                      Icons.widgets_rounded,
                      color: Color(0xFF4AAE72),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'افزودن ویجت مصرف به صفحه اصلی',
                        style: TextStyle(
                          fontFamily: fontFamily,
                          color: const Color(0xFF182435),
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'نام درمان، دوز، ساعت و «مصرف کردم» همیشه جلوی چشم',
                        style: TextStyle(
                          fontFamily: fontFamily,
                          color: const Color(0xFF667085),
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          height: 1.45,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  width: 42,
                  height: 42,
                  decoration: const BoxDecoration(
                    color: Color(0xFFFF7362),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.add_rounded,
                    color: Colors.white,
                    size: 26,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
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
