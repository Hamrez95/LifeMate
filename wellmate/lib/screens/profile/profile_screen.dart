import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:wellmate/providers/settings_provider.dart';
import '../../localization/app_localizations.dart';
import '../../localization/locale_provider.dart';
import '../../core/utils/string_extensions.dart';
import '../../core/theme/app_style.dart';
import '../../models/user_profile_model.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({Key? key}) : super(key: key);

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late UserProfileModel currentUser;

  @override
  void initState() {
    super.initState();
    // در آینده این اطلاعات از API یا دیتابیس لوکال دریافت می‌شود
    currentUser = UserProfileModel(
        id: '101',
        fullName: 'کاربر تستی',
        mobileNumber: '09123456789',
        email: 'test@gmail.com',
        avatarUrl: '../../assets/images/mother_avatar.png',
        joinDate: '2025',
        isPremium: true);
  }

  @override
  Widget build(BuildContext context) {
    // محصور کردن کل ویجت با Consumer برای واکنش به تغییرات SettingsProvider
    return Consumer<SettingsProvider>(
      builder: (context, settingsProvider, child) {
        final loc = AppLocalizations.of(context);
        final localeProvider = Provider.of<LocaleProvider>(context);
        final isPersian = localeProvider.locale.languageCode == 'fa';

        final displayName = currentUser.fullName.isNotEmpty
            ? currentUser.fullName
            : (loc['profile_name'] ?? 'نام کاربر');

        final displayPhone = currentUser.mobileNumber.isNotEmpty
            ? currentUser.mobileNumber
            : (loc['profile_phone'] ?? '');

        return Scaffold(
          backgroundColor: AppColors.background,
          body: SafeArea(
            child: Column(
              children: [
                // Header
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                        icon: Icon(Icons.arrow_back_ios_new_rounded,
                            size: 24, color: AppColors.primary),
                        onPressed: () => Navigator.of(context).pop(),
                        splashRadius: 24,
                      ),
                      Expanded(
                        child: Column(
                          children: [
                            // Profile Avatar
                            Container(
                              width: 80,
                              height: 80,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: AppColors.cardBackground,
                                boxShadow: [
                                  BoxShadow(
                                    color: AppColors.shadowDark,
                                    blurRadius: 15,
                                    offset: const Offset(4, 4),
                                  ),
                                  BoxShadow(
                                    color: AppColors.shadowLight,
                                    blurRadius: 15,
                                    offset: const Offset(-4, -4),
                                  ),
                                ],
                              ),
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  const CircleAvatar(
                                    radius: 36,
                                    backgroundColor: Color(0xFFE2D4C8),
                                    child: Icon(Icons.person,
                                        size: 48, color: Colors.white),
                                  ),
                                  Positioned(
                                    bottom: 0,
                                    right: 0,
                                    child: Container(
                                      padding: const EdgeInsets.all(4),
                                      decoration: BoxDecoration(
                                        color: AppColors.cardBackground,
                                        shape: BoxShape.circle,
                                        boxShadow: [
                                          BoxShadow(
                                            color: AppColors.shadowDark
                                                .withOpacity(0.5),
                                            blurRadius: 5,
                                          ),
                                        ],
                                      ),
                                      child: Icon(Icons.camera_alt,
                                          size: 16, color: AppColors.primary),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              displayName,
                              style: AppTextStyles.heading(context),
                            ),
                            Text(
                              displayPhone.toPersianDigit(isPersian),
                              style: AppTextStyles.caption(context).copyWith(
                                color: AppColors.primary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.notifications_none_rounded,
                            size: 24, color: AppColors.primary),
                        onPressed: () {},
                        splashRadius: 24,
                      ),
                    ],
                  ),
                ),

                // Subscription Card
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppColors.cardBackground,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.shadowDark,
                          blurRadius: 10,
                          offset: const Offset(4, 4),
                        ),
                        BoxShadow(
                          color: AppColors.shadowLight,
                          blurRadius: 10,
                          offset: const Offset(-4, -4),
                        ),
                      ],
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  currentUser.isPremium
                                      ? (loc['profile_active_subscription'] ??
                                          'اشتراک فعال است')
                                      : (loc['profile_no_subscription'] ??
                                          'اشتراکی ندارید'),
                                  style: AppTextStyles.body(context)
                                      .copyWith(fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    ElevatedButton(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: AppColors.primary,
                                        shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(12)),
                                        elevation: 0,
                                      ),
                                      onPressed: () {},
                                      child: Text(
                                        loc['profile_buy_plan'] ??
                                            'خرید اشتراک',
                                        style: AppTextStyles.button(context)
                                            .copyWith(
                                                color: Colors.white,
                                                fontSize: 13),
                                      ),
                                    ),
                                    if (currentUser.isPremium) ...[
                                      const SizedBox(width: 12),
                                      Text(
                                        loc['profile_renew'] ?? 'تمدید',
                                        style: AppTextStyles.body(context)
                                            .copyWith(color: AppColors.primary),
                                      ),
                                    ]
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: const BoxDecoration(
                              color: Color(0xFFFFF8E1),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.emoji_events_rounded,
                                size: 32, color: Colors.amber),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                // Menu List
                Expanded(
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 12),
                      child: Container(
                        decoration: BoxDecoration(
                          color: AppColors.cardBackground,
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.shadowDark,
                              blurRadius: 15,
                              offset: const Offset(4, 4),
                            ),
                          ],
                        ),
                        child: Column(
                          children: [
                            _ProfileMenuTile(
                              icon: Icons.person_outline,
                              iconColor: Colors.blueAccent,
                              label: loc['profile_personal_info'] ??
                                  'اطلاعات شخصی',
                            ),
                            const Divider(height: 1, indent: 60, endIndent: 20),
                            _ProfileMenuTile(
                              icon: Icons.assignment_outlined,
                              iconColor: Colors.orangeAccent,
                              label: loc['profile_health_profile'] ??
                                  'پروفایل سلامت',
                            ),
                            const Divider(height: 1, indent: 60, endIndent: 20),
                            _ProfileMenuTile(
                              icon: Icons.people_outline,
                              iconColor: Colors.green,
                              label: loc['profile_caregivers'] ?? 'مراقبین',
                            ),
                            const Divider(height: 1, indent: 60, endIndent: 20),
                            _ProfileMenuTile(
                              icon: Icons.settings_outlined,
                              iconColor: Colors.purple,
                              label: loc['profile_app_settings'] ??
                                  'تنظیمات برنامه',
                              onTap: () {
                                showDialog(
                                  context: context,
                                  builder: (context) => const _SettingsDialog(),
                                );
                              },
                            ),
                            const Divider(height: 1, indent: 60, endIndent: 20),
                            _ProfileMenuTile(
                              icon: Icons.card_giftcard_outlined,
                              iconColor: Colors.redAccent,
                              label: loc['profile_referral_code'] ?? 'کد معرفی',
                            ),
                            const Divider(height: 1, indent: 60, endIndent: 20),
                            _ProfileMenuTile(
                              icon: Icons.support_agent_outlined,
                              iconColor: Colors.indigo,
                              label: loc['profile_support'] ?? 'پشتیبانی',
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

                // Footer - Log Out
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                  child: Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: AppColors.cardBackground,
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.redAccent.withOpacity(0.1),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: TextButton.icon(
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18)),
                      ),
                      icon: const Icon(Icons.logout, color: Colors.redAccent),
                      label: Text(
                        loc['profile_logout'] ?? 'خروج از حساب',
                        style: AppTextStyles.button(context)
                            .copyWith(color: Colors.redAccent),
                      ),
                      onPressed: () {},
                    ),
                  ),
                ),

                // Footer Message
                Padding(
                  padding: const EdgeInsets.only(top: 4, bottom: 20),
                  child: Text(
                    (loc['footer_message'] ?? 'Version 1.0.0')
                        .toString()
                        .toPersianDigit(isPersian),
                    style: AppTextStyles.caption(context),
                  ),
                ),
              ],
            ),
          ),
        );
      }, // 👈 اینجا بسته شدن Consumer اصلاح شد
    );
  }
}

class _ProfileMenuTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final VoidCallback? onTap;

  const _ProfileMenuTile({
    required this.icon,
    required this.iconColor,
    required this.label,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      leading: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: iconColor.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: iconColor, size: 22),
      ),
      title: Text(
        label,
        style: AppTextStyles.body(context),
      ),
      trailing: const Icon(Icons.arrow_forward_ios_rounded,
          size: 16, color: Colors.grey),
      onTap: onTap,
    );
  }
}

class _SettingsDialog extends StatefulWidget {
  const _SettingsDialog();

  @override
  State<_SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<_SettingsDialog> {
  late double _textSize;

  @override
  void initState() {
    super.initState();
    // 👈 خواندن مقدار فعلی تنظیمات هنگام باز شدن دیالوگ
    _textSize =
        Provider.of<SettingsProvider>(context, listen: false).textScaleFactor ??
            1.0;
  }

  @override
  Widget build(BuildContext context) {
    final localeProvider = Provider.of<LocaleProvider>(context);
    final settingsProvider =
        Provider.of<SettingsProvider>(context, listen: false);
    final loc = AppLocalizations.of(context);

    return AlertDialog(
      backgroundColor: AppColors.cardBackground,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: Text(loc['profile_app_settings'] ?? 'تنظیمات',
          style: AppTextStyles.heading(context)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('زبان (Language)', style: AppTextStyles.body(context)),
          const SizedBox(height: 12),
          _LanguageOption(
            title: 'English',
            isSelected: localeProvider.locale.languageCode == 'en',
            onTap: () {
              localeProvider.setLocale(const Locale('en'));
              Navigator.of(context).pop();
            },
          ),
          const SizedBox(height: 8),
          _LanguageOption(
            title: 'فارسی',
            isSelected: localeProvider.locale.languageCode == 'fa',
            onTap: () {
              localeProvider.setLocale(const Locale('fa'));
              Navigator.of(context).pop();
            },
          ),
          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 12),
          Text('اندازه متن (Text Size)', style: AppTextStyles.body(context)),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.text_fields, size: 16, color: Colors.grey),
              Expanded(
                child: Slider(
                  value: _textSize,
                  min: 0.8,
                  max: 1.5,
                  divisions: 3,
                  activeColor: AppColors.primary,
                  onChanged: (val) {
                    setState(() {
                      _textSize = val;
                    });
                    // 👈 این خط اسلایدر رو واقعاً به پرووایدرت وصل می‌کنه
                    // اگر متد آپدیتت تو پرووایدر اسم دیگه‌ای داره، فقط همین خط رو عوض کن
                    settingsProvider.updateTextScale(val);
                  },
                ),
              ),
              const Icon(Icons.text_fields, size: 24, color: Colors.grey),
            ],
          ),
        ],
      ),
    );
  }
}

class _LanguageOption extends StatelessWidget {
  final String title;
  final bool isSelected;
  final VoidCallback onTap;

  const _LanguageOption({
    required this.title,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primary.withOpacity(0.1)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: isSelected ? AppColors.primary : Colors.grey.shade300),
        ),
        child: Row(
          children: [
            Text(title,
                style: AppTextStyles.body(context).copyWith(
                    color: isSelected
                        ? AppColors.primary
                        : AppColors.textPrimary)),
            const Spacer(),
            if (isSelected) Icon(Icons.check_circle, color: AppColors.primary),
          ],
        ),
      ),
    );
  }
}
