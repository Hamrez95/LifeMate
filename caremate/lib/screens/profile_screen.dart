// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:lifemate_client/lifemate_client.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_colors.dart';
import '../../core/localization/app_localizations.dart';
import '../../core/localization/locale_provider.dart';
import '../../core/utils/string_extensions.dart';
import 'feature_preview_screen.dart';
import 'profile_destination_screens.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final localeProvider = context.watch<LocaleProvider>();
    final isPersian = localeProvider.locale.languageCode == 'fa';
    final mainFont = isPersian ? 'Vazir' : 'Nunito';

    void openScreen(Widget destination) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => destination),
      );
    }


    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 24, color: AppColors.primaryBlue),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: _CurrentCareMateIdentity(mainFont: mainFont)),
                    const SizedBox(width: 8),
                    IconButton(
                      tooltip: 'اعلان‌های حساب',
                      icon: const Icon(Icons.notifications_none_rounded, size: 24, color: AppColors.primaryBlue),
                      onPressed: () => openScreen(const CareMateNotificationsScreen()),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.cardBackground,
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.07), blurRadius: 16, offset: const Offset(0, 4))],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 18),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                loc['profile_no_subscription'] ?? 'اشتراک مراقبتی',
                                style: TextStyle(fontFamily: mainFont, fontSize: 15, color: AppColors.darkBlue),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppColors.darkBlue,
                                      disabledBackgroundColor: AppColors.darkBlue.withOpacity(0.55),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                      elevation: 0,
                                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                    ),
                                    onPressed: () => openScreen(const CareMateSubscriptionScreen()),
                                    icon: const Icon(Icons.lock_outline_rounded, color: Colors.white, size: 16),
                                    label: Text(
                                      'در دست توسعه',
                                      style: TextStyle(fontFamily: mainFont, fontSize: 13, color: Colors.white),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Container(
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            boxShadow: [BoxShadow(color: Color.fromARGB(64, 255, 191, 0), blurRadius: 16, offset: Offset(0, 4))],
                          ),
                          child: const Icon(Icons.emoji_events_rounded, size: 36, color: Colors.amber),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.07), blurRadius: 16, offset: const Offset(0, 4))],
                  ),
                  child: Column(
                    children: [
                      _ProfileMenuTile(
                        icon: Icons.person,
                        iconColor: Colors.blueAccent,
                        label: loc['profile_personal_info'] ?? 'اطلاعات شخصی',
                        mainFont: mainFont,
                        subtitle: 'صفحه طراحی‌شده؛ ویرایش در دست توسعه',
                        onTap: () => openScreen(const CareMatePersonalInformationScreen()),
                      ),
                      const Divider(height: 1, indent: 60, endIndent: 20),
                      _ProfileMenuTile(
                        icon: Icons.assignment_rounded,
                        iconColor: Colors.orangeAccent,
                        label: loc['profile_health_profile'] ?? 'پرونده سلامت',
                        mainFont: mainFont,
                        subtitle: 'دسترسی مراقبتی محدود؛ در دست توسعه',
                        onTap: () => openScreen(const CareMateFeaturePreviewScreen(initialIndex: 2)),
                      ),
                      const Divider(height: 1, indent: 60, endIndent: 20),
                      _ProfileMenuTile(
                        icon: Icons.group,
                        iconColor: Colors.green,
                        label: loc['profile_caregivers'] ?? 'مراقبان',
                        mainFont: mainFont,
                        subtitle: 'روابط فعال از داشبورد قابل مشاهده‌اند',
                        onTap: () => openScreen(const CareMateFeaturePreviewScreen(initialIndex: 3)),
                      ),
                      const Divider(height: 1, indent: 60, endIndent: 20),
                      _ProfileMenuTile(
                        icon: Icons.settings,
                        iconColor: Colors.purple,
                        label: loc['profile_app_settings'] ?? 'تنظیمات برنامه',
                        mainFont: mainFont,
                        subtitle: 'زبان برنامه',
                        onTap: () {
                          showDialog<void>(context: context, builder: (_) => _LanguageDialog(mainFont: mainFont));
                        },
                      ),
                      const Divider(height: 1, indent: 60, endIndent: 20),
                      _ProfileMenuTile(
                        icon: Icons.card_giftcard,
                        iconColor: Colors.redAccent,
                        label: loc['profile_referral_code'] ?? 'کد معرف',
                        mainFont: mainFont,
                        subtitle: 'در دست توسعه',
                        onTap: () => openScreen(const CareMateReferralScreen()),
                      ),
                      const Divider(height: 1, indent: 60, endIndent: 20),
                      _ProfileMenuTile(
                        icon: Icons.support_agent,
                        iconColor: Colors.indigo,
                        label: loc['profile_support'] ?? 'پشتیبانی',
                        mainFont: mainFont,
                        subtitle: 'در دست توسعه',
                        onTap: () => openScreen(const CareMateSupportScreen()),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: [BoxShadow(color: Colors.redAccent.withOpacity(0.12), blurRadius: 16, offset: const Offset(0, 4))],
                  ),
                  child: TextButton.icon(
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                    ),
                    icon: const Icon(Icons.logout, color: Colors.redAccent),
                    label: Text(
                      loc['profile_logout'] ?? 'خروج از حساب',
                      style: TextStyle(fontFamily: mainFont, fontSize: 16, color: Colors.redAccent, fontWeight: FontWeight.bold),
                    ),
                    onPressed: LifeMateAuth.signOut,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 24),
                child: Text(
                  'CareMate 0.8.0-beta.3'.toPersianDigit(isPersian),
                  style: TextStyle(fontFamily: mainFont, fontSize: 12, color: AppColors.secondaryText.withOpacity(0.7)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CurrentCareMateIdentity extends StatefulWidget {
  const _CurrentCareMateIdentity({required this.mainFont});
  final String mainFont;
  @override
  State<_CurrentCareMateIdentity> createState() => _CurrentCareMateIdentityState();
}

class _CurrentCareMateIdentityState extends State<_CurrentCareMateIdentity> {
  late final Future<Map<String, dynamic>> _future;
  @override
  void initState() {
    super.initState();
    _future = context.read<LifeMateApiClient>().getCurrentUser();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: _future,
      builder: (context, snapshot) {
        final data = snapshot.data ?? const <String, dynamic>{};
        final user = data['user'] as Map<String, dynamic>? ?? const {};
        final profile = data['profile'] as Map<String, dynamic>? ?? const {};
        final name = profile['displayName']?.toString().trim();
        final email = user['email']?.toString() ?? '';
        return Column(
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 16, offset: const Offset(0, 4))],
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  const CircleAvatar(
                    radius: 36,
                    backgroundColor: AppColors.avatarBackground,
                    backgroundImage: AssetImage('assets/images/Caregiver.png'),
                  ),
                  Positioned(
                    bottom: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                      child: const Icon(Icons.lock_outline_rounded, size: 16, color: AppColors.primaryBlue),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              name == null || name.isEmpty ? 'کاربر CareMate' : name,
              textAlign: TextAlign.center,
              style: TextStyle(fontFamily: widget.mainFont, fontSize: 22, fontWeight: FontWeight.bold, color: AppColors.darkBlue),
            ),
            if (snapshot.connectionState == ConnectionState.waiting)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: SizedBox.square(dimension: 15, child: CircularProgressIndicator(strokeWidth: 2)),
              )
            else if (email.isNotEmpty)
              Text(
                email,
                textDirection: TextDirection.ltr,
                textAlign: TextAlign.center,
                style: TextStyle(fontFamily: widget.mainFont, fontSize: 13, color: AppColors.primaryBlue),
              ),
          ],
        );
      },
    );
  }
}

class _ProfileMenuTile extends StatelessWidget {
  const _ProfileMenuTile({required this.icon, required this.iconColor, required this.label, required this.mainFont, this.subtitle, this.onTap});
  final IconData icon;
  final Color iconColor;
  final String label;
  final String mainFont;
  final String? subtitle;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: ListTile(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: iconColor.withOpacity(0.15),
          shape: BoxShape.circle,
          boxShadow: [BoxShadow(color: iconColor.withOpacity(0.25), blurRadius: 8, offset: const Offset(0, 4))],
        ),
        child: Icon(icon, color: iconColor, size: 24),
      ),
      title: Text(label, style: TextStyle(fontFamily: mainFont, fontSize: 16, color: AppColors.darkBlue)),
      subtitle: subtitle == null
          ? null
          : Text(subtitle!, style: TextStyle(fontFamily: mainFont, fontSize: 11, color: AppColors.secondaryText)),
      trailing: const Icon(Icons.chevron_right_rounded, size: 20),
        onTap: onTap,
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
    final loc = AppLocalizations.of(context);
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: Text(loc['settings_language'] ?? 'Select Language', style: TextStyle(fontFamily: mainFont, fontWeight: FontWeight.bold)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _LanguageOption(
            title: 'English',
            font: mainFont,
            isSelected: localeProvider.locale.languageCode == 'en',
            onTap: () {
              localeProvider.setLocale(const Locale('en'));
              Navigator.of(context).pop();
            },
          ),
          const SizedBox(height: 12),
          _LanguageOption(
            title: 'فارسی',
            font: 'Vazir',
            isSelected: localeProvider.locale.languageCode == 'fa',
            onTap: () {
              localeProvider.setLocale(const Locale('fa'));
              Navigator.of(context).pop();
            },
          ),
        ],
      ),
    );
  }
}

class _LanguageOption extends StatelessWidget {
  const _LanguageOption({required this.title, required this.font, required this.isSelected, required this.onTap});
  final String title;
  final String font;
  final bool isSelected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primaryBlue.withOpacity(0.1) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: isSelected ? AppColors.primaryBlue : Colors.grey.shade300),
        ),
        child: Row(
          children: [
            Text(title, style: TextStyle(fontFamily: font, fontSize: 16, color: isSelected ? AppColors.primaryBlue : Colors.black87)),
            const Spacer(),
            if (isSelected) const Icon(Icons.check_circle, color: AppColors.primaryBlue),
          ],
        ),
      ),
    );
  }
}
