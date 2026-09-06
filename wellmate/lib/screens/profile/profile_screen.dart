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
import 'care_access_phone_screen.dart';
import 'editable_profile_screen.dart';
import 'profile_destination_screens.dart';
import 'subscription_center_screen.dart';

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
      theme: LifeMateProfileThemeData(
        background: AppColors.background,
        accent: AppColors.primary,
        titleColor: AppColors.darkBlue,
        secondaryText: AppColors.textSecondary,
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
              fa: LifeMateRuntimeLocale.select(fa: 'مراقبان', en: "Caregivers"),
              en: "Caregivers",
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
              fa: LifeMateRuntimeLocale.select(
                fa: 'کد معرف',
                en: "Identification code",
              ),
              en: "Identification code",
            ),
        support: loc['profile_support'] ?? 'پشتیبانی',
        logout: loc['profile_logout'] ?? 'خروج از حساب',
        subscriptionTitle:
            loc['profile_no_subscription'] ??
            (isPersian ? 'اشتراک' : 'Subscription'),
        manageSubscriptions:
            loc['profile_buy_plan'] ??
            (isPersian
                ? LifeMateRuntimeLocale.select(
                    fa: 'مدیریت اشتراک‌ها',
                    en: "Management of subscriptions",
                  )
                : 'Manage subscriptions'),
        referralSubtitle: isPersian
            ? LifeMateRuntimeLocale.select(
                fa: 'در دست توسعه',
                en: "Under development",
              )
            : 'Coming soon',
        supportSubtitle: isPersian
            ? LifeMateRuntimeLocale.select(
                fa: 'گفت‌وگوی مستقیم و امن با تیم پشتیبانی',
                en: "Secure direct chat with support",
              )
            : 'Secure direct chat with support',
      ),
      fontFamily: mainFont,
      appName: 'WellMate',
      versionLabel: 'WellMate $wellMateAppVersion'.toPersianDigit(isPersian),
      fallbackUserName: isPersian
          ? LifeMateRuntimeLocale.select(
              fa: 'کاربر LifeMate',
              en: "LifeMate user",
            )
          : 'LifeMate user',
      isPersian: isPersian,
      onNotifications: () => open(NotificationCenterScreen()),
      onEditProfile: () => open(EditableProfileScreen()),
      onHealthProfile: () => open(const HealthRecordScreen()),
      onCareManagement: () => open(
        LifeMateCareAccessInventoryScreen(
          apiClient: api,
          role: LifeMateCareAccessRole.patient,
          accent: AppColors.primary,
          background: AppColors.background,
          ink: AppColors.darkBlue,
          onManage: () => open(CareAccessPhoneScreen()),
        ),
      ),
      onAppSettings: () => showDialog<void>(
        context: context,
        builder: (_) => _SettingsDialog(mainFont: mainFont),
      ),
      onReferral: () => open(ReferralScreen()),
      onSupport: () => open(
        LifeMateSupportChatScreen(
          productCode: 'wellmate',
          accent: AppColors.primary,
          background: AppColors.background,
          isPersian: isPersian,
          fontFamily: mainFont,
        ),
      ),
      onManageSubscriptions: () => open(const LifeMateSubscriptionCenterScreen()),
      additionalActions: [
        LifeMateProfileAdditionalAction(
          key: const Key('profile-health-record-entry'),
          icon: Icons.folder_shared_rounded,
          iconColor: AppColors.primary,
          label: isPersian ? 'مدارک پرونده سلامت' : 'Health record documents',
          subtitle: isPersian
              ? 'نسخه، آزمایش و تصویرهای پزشکی'
              : 'Prescriptions, results and medical images',
          semanticLabel: isPersian
              ? 'ورود به مدارک پرونده سلامت'
              : 'Open health record documents',
          onTap: () => open(const HealthRecordScreen()),
        ),
      ],
      feedbackBuilder: (_) => LifeMateFeedbackScreen(
        productCode: 'wellmate',
        appVersion: wellMateAppVersion,
        buildNumber: wellMateAppVersion.contains('+')
            ? wellMateAppVersion.split('+').last
            : null,
        accent: AppColors.primary,
        background: AppColors.background,
        isPersian: isPersian,
        fontFamily: mainFont,
      ),
    );

    if (!MedicationHomeWidgetService.isSupportedPlatform) {
      return sharedProfile;
    }

    return ColoredBox(
      color: AppColors.background,
      child: Column(
        children: [
          Expanded(child: sharedProfile),
          SafeArea(
            top: false,
            minimum: const EdgeInsets.fromLTRB(24, 8, 24, 14),
            child: _MedicationWidgetProfileButton(
              fontFamily: mainFont,
              onPressed: () => _pinMedicationWidget(context, api),
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
                ? LifeMateRuntimeLocale.select(
                    fa: LifeMateRuntimeLocale.select(
                      fa: 'پنجره افزودن ویجت باز شد؛ «افزودن» را بزنید.',
                      en: "The add widget window is opened; Click \"Add\".",
                    ),
                    en: "The add widget window is opened; Click \"Add\".",
                  )
                : LifeMateRuntimeLocale.select(
                    fa: LifeMateRuntimeLocale.select(
                      fa: 'برای افزودن دستی، صفحه اصلی را نگه دارید و از بخش ویجت‌ها WellMate را انتخاب کنید.',
                      en: "To add manually, hold the home screen and select WellMate from the widgets section.",
                    ),
                    en: "To add manually, hold the home screen and select WellMate from the widgets section.",
                  ),
          ),
        ),
      );
    } catch (error) {
      debugPrint('WellMate medication widget pin failed: $error');
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(
            LifeMateRuntimeLocale.select(
              fa: LifeMateRuntimeLocale.select(
                fa: 'آماده‌سازی ویجت انجام نشد؛ دوباره تلاش کنید.',
                en: "Failed to prepare widget; Try again.",
              ),
              en: "Failed to prepare widget; Try again.",
            ),
          ),
        ),
      );
    }
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
      label: LifeMateRuntimeLocale.select(
        fa: LifeMateRuntimeLocale.select(
          fa: 'افزودن ویجت مصرف به صفحه اصلی',
          en: "Add consumption widget to home page",
        ),
        en: "Add consumption widget to home page",
      ),
      hint: LifeMateRuntimeLocale.select(
        fa: LifeMateRuntimeLocale.select(
          fa: 'نمایش درمان بعدی و ثبت سریع مصرف از صفحه اصلی گوشی',
          en: "Display the next treatment and record consumption quickly from the main screen of the phone",
        ),
        en: "Display the next treatment and record consumption quickly from the main screen of the phone",
      ),
      child: Material(
        color: Color(0xFFFFF4E9),
        borderRadius: BorderRadius.circular(22),
        elevation: 3,
        shadowColor: Color(0x22E76D5B),
        child: InkWell(
          key: ValueKey('wellmate-add-medication-widget'),
          borderRadius: BorderRadius.circular(22),
          onTap: onPressed,
          child: Padding(
            padding: EdgeInsetsDirectional.fromSTEB(14, 12, 14, 12),
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  padding: EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Color(0xFFDDF2E5),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Image.asset(
                    'assets/images/WellMateWithoutBack.png',
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) =>
                        Icon(Icons.widgets_rounded, color: Color(0xFF4AAE72)),
                  ),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        LifeMateRuntimeLocale.select(
                          fa: LifeMateRuntimeLocale.select(
                            fa: 'افزودن ویجت مصرف به صفحه اصلی',
                            en: "Add consumption widget to home page",
                          ),
                          en: "Add consumption widget to home page",
                        ),
                        style: TextStyle(
                          fontFamily: fontFamily,
                          color: Color(0xFF182435),
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        LifeMateRuntimeLocale.select(
                          fa: LifeMateRuntimeLocale.select(
                            fa: 'نام درمان، دوز، ساعت و «مصرف کردم» همیشه جلوی چشم',
                            en: "The name of the treatment, dose, time and \"I took it\" always in front of the eyes",
                          ),
                          en: "The name of the treatment, dose, time and \"I took it\" always in front of the eyes",
                        ),
                        style: TextStyle(
                          fontFamily: fontFamily,
                          color: Color(0xFF667085),
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          height: 1.45,
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(width: 10),
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: Color(0xFFFF7362),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.add_rounded, color: Colors.white, size: 26),
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
        LifeMateRuntimeLocale.select(
          fa: LifeMateRuntimeLocale.select(
            fa: 'تنظیمات برنامه',
            en: "Program settings",
          ),
          en: "Program settings",
        ),
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
              LifeMateRuntimeLocale.select(
                fa: LifeMateRuntimeLocale.select(fa: 'زبان', en: "language"),
                en: "language",
              ),
              style: TextStyle(
                fontFamily: widget.mainFont,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 10),
            SegmentedButton<String>(
              segments: [
                ButtonSegment(
                  value: 'fa',
                  label: Text(
                    LifeMateRuntimeLocale.select(
                      fa: LifeMateRuntimeLocale.select(
                        fa: 'فارسی',
                        en: "Farsi",
                      ),
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
            SizedBox(height: 24),
            Text(
              LifeMateRuntimeLocale.select(
                fa: LifeMateRuntimeLocale.select(
                  fa: 'اندازه متن',
                  en: "Text size",
                ),
                en: "Text size",
              ),
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
          child: Text(
            LifeMateRuntimeLocale.select(
              fa: LifeMateRuntimeLocale.select(fa: 'تمام', en: "all"),
              en: "all",
            ),
          ),
        ),
      ],
    );
  }
}
