// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:wellmate/core/theme/app_style.dart';
import 'package:wellmate/localization/app_localizations.dart';
import 'package:wellmate/localization/locale_provider.dart';
import '../../core/utils/string_extensions.dart';
import 'package:wellmate/providers/settings_provider.dart'; // 👈 اضافه شدن پرووایدر تنظیمات
import 'package:lifemate_client/lifemate_client.dart';

import 'care_access_screen.dart';
import 'profile_destination_screens.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // 👈 استفاده از Consumer برای واکنش به تغییر سایز فونت
    return Consumer<SettingsProvider>(builder: (context, settings, child) {
      final loc = AppLocalizations.of(context);
      final localeProvider = Provider.of<LocaleProvider>(context);
      final isPersian = localeProvider.locale.languageCode == 'fa';
      final mainFont = isPersian ? 'Vazir' : 'Poppins';

      // دریافت ضریب تغییر سایز فونت از SettingsProvider
      final textScale = settings.textScaleFactor ?? 1.0;

      return Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(
          child: SingleChildScrollView(
            child: Column(
              children: [
                // ---------------- Header ----------------
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back_ios_new_rounded,
                            size: 24, color: AppColors.primaryBlue),
                        // 👈 دکمه بک حالا به درستی کار می‌کند چون صفحه Push شده است
                        onPressed: () => Navigator.of(context).pop(),
                        splashRadius: 24,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _CurrentUserIdentity(
                          mainFont: mainFont,
                          textScale: textScale,
                          isPersian: isPersian,
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.notifications_none_rounded,
                            size: 24, color: AppColors.primaryBlue),
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const NotificationCenterScreen(),
                          ),
                        ),
                        splashRadius: 24,
                      ),
                    ],
                  ),
                ),

                // ---------------- Subscription Card ----------------
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppColors.cardBackground,
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.07),
                          blurRadius: 16,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          vertical: 16, horizontal: 18),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  loc['profile_no_subscription'] ??
                                      'اشتراکی ندارید',
                                  style: TextStyle(
                                      fontFamily: mainFont,
                                      fontSize: 15 * textScale,
                                      color: AppColors.darkBlue),
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    ElevatedButton(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: AppColors.darkBlue,
                                        shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(12)),
                                        elevation: 0,
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 18, vertical: 8),
                                      ),
                                      onPressed: () => Navigator.of(context).push(
                                        MaterialPageRoute<void>(
                                          builder: (_) => const SubscriptionScreen(),
                                        ),
                                      ),
                                      child: Text(
                                          loc['profile_buy_plan'] ??
                                              'خرید اشتراک',
                                          style: TextStyle(
                                              fontFamily: mainFont,
                                              fontSize: 14 * textScale,
                                              color: Colors.white)),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(loc['profile_renew'] ?? 'تمدید',
                                        style: TextStyle(
                                            fontFamily: mainFont,
                                            fontSize: 14 * textScale,
                                            color: AppColors.primaryBlue)),
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
                              boxShadow: [
                                BoxShadow(
                                  color: Color.fromARGB(64, 255, 191, 0),
                                  blurRadius: 16,
                                  offset: Offset(0, 4),
                                ),
                              ],
                            ),
                            child: const Icon(Icons.emoji_events_rounded,
                                size: 36, color: Colors.amber),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                // ---------------- Menu List ----------------
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.07),
                          blurRadius: 16,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        const Divider(height: 1, indent: 60, endIndent: 20),
                        _ProfileMenuTile(
                          icon: Icons.person,
                          iconColor: Colors.blueAccent,
                          label: loc['profile_personal_info'] ?? 'اطلاعات شخصی',
                          mainFont: mainFont,
                          textScale: textScale,
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => const PersonalInformationScreen(),
                            ),
                          ),
                        ),
                        const Divider(height: 1, indent: 60, endIndent: 20),
                        _ProfileMenuTile(
                          icon: Icons.assignment_rounded,
                          iconColor: Colors.orangeAccent,
                          label:
                              loc['profile_health_profile'] ?? 'پرونده سلامت',
                          mainFont: mainFont,
                          textScale: textScale,
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => const HealthRecordScreen(),
                            ),
                          ),
                        ),
                        const Divider(height: 1, indent: 60, endIndent: 20),
                        _ProfileMenuTile(
                          icon: Icons.group,
                          iconColor: Colors.green,
                          label: loc['profile_caregivers'] ?? 'مراقبان',
                          mainFont: mainFont,
                          textScale: textScale,
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const CareAccessScreen(),
                            ),
                          ),
                        ),
                        const Divider(height: 1, indent: 60, endIndent: 20),
                        _ProfileMenuTile(
                          icon: Icons.settings,
                          iconColor: Colors.purple,
                          label:
                              loc['profile_app_settings'] ?? 'تنظیمات برنامه',
                          mainFont: mainFont,
                          textScale: textScale,
                          onTap: () {
                            showDialog(
                              context: context,
                              builder: (context) =>
                                  _SettingsDialog(mainFont: mainFont),
                            );
                          },
                        ),
                        const Divider(height: 1, indent: 60, endIndent: 20),
                        _ProfileMenuTile(
                          icon: Icons.card_giftcard,
                          iconColor: Colors.redAccent,
                          label: loc['profile_referral_code'] ?? 'کد معرف',
                          mainFont: mainFont,
                          textScale: textScale,
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => const ReferralScreen(),
                            ),
                          ),
                        ),
                        const Divider(height: 1, indent: 60, endIndent: 20),
                        _ProfileMenuTile(
                          icon: Icons.support_agent,
                          iconColor: Colors.indigo,
                          label: loc['profile_support'] ?? 'پشتیبانی',
                          mainFont: mainFont,
                          textScale: textScale,
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => const SupportScreen(),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // ---------------- Footer - Log Out ----------------
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                  child: Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.redAccent.withOpacity(0.12),
                          blurRadius: 16,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: TextButton.icon(
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        backgroundColor: Colors.transparent,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18)),
                      ),
                      icon: const Icon(Icons.logout, color: Colors.redAccent),
                      label: Text(loc['profile_logout'] ?? 'خروج از حساب',
                          style: TextStyle(
                              fontFamily: mainFont,
                              fontSize: 16 * textScale,
                              color: Colors.redAccent,
                              fontWeight: FontWeight.bold)),
                      onPressed: () => LifeMateAuth.signOut(),
                    ),
                  ),
                ),

                // ---------------- Footer Message ----------------
                Padding(
                  padding: const EdgeInsets.only(top: 8, bottom: 24),
                  child: Text(
                      (loc['footer_message'] ?? 'Version 1.0.0')
                          .toString()
                          .toPersianDigit(isPersian),
                      style: TextStyle(
                          fontFamily: mainFont,
                          fontSize: 12 * textScale,
                          color: AppColors.secondaryText.withOpacity(0.7))),
                ),
              ],
            ),
          ),
        ),
      );
    });
  }
}

class _ProfileMenuTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String mainFont;
  final double textScale;
  final VoidCallback? onTap;

  const _ProfileMenuTile({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.mainFont,
    required this.textScale,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: iconColor.withOpacity(0.15),
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: iconColor.withOpacity(0.25),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Icon(icon, color: iconColor, size: 24),
      ),
      title: Text(label,
          style: TextStyle(
              fontFamily: mainFont,
              fontSize: 16 * textScale,
              color: AppColors.darkBlue)),
      trailing: onTap == null
          ? const Text(
              'به‌زودی',
              style: TextStyle(fontSize: 11, color: Colors.grey),
            )
          : const Icon(
              Icons.arrow_forward_ios_rounded,
              size: 14,
              color: Colors.grey,
            ),
      onTap: onTap,
    );
  }
}

class _CurrentUserIdentity extends StatefulWidget {
  const _CurrentUserIdentity({
    required this.mainFont,
    required this.textScale,
    required this.isPersian,
  });

  final String mainFont;
  final double textScale;
  final bool isPersian;

  @override
  State<_CurrentUserIdentity> createState() => _CurrentUserIdentityState();
}

class _CurrentUserIdentityState extends State<_CurrentUserIdentity> {
  late final Future<Map<String, dynamic>> _currentUser;

  @override
  void initState() {
    super.initState();
    _currentUser = context.read<LifeMateApiClient>().getCurrentUser();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: _currentUser,
      builder: (context, snapshot) {
        final profile =
            snapshot.data?['profile'] as Map<String, dynamic>? ?? const {};
        final name = profile['displayName']?.toString() ?? 'کاربر LifeMate';
        final contact = profile['phoneNumber']?.toString().trim().isNotEmpty ==
                true
            ? profile['phoneNumber'].toString()
            : profile['email']?.toString() ?? '';

        return Column(
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.08),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const Icon(
                Icons.person_rounded,
                size: 44,
                color: AppColors.primaryBlue,
              ),
            ),
            const SizedBox(height: 8),
            if (snapshot.connectionState != ConnectionState.done)
              const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else ...[
              Text(
                name,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: widget.mainFont,
                  fontSize: 22 * widget.textScale,
                  fontWeight: FontWeight.bold,
                  color: AppColors.darkBlue,
                ),
              ),
              if (contact.isNotEmpty)
                Text(
                  contact.toPersianDigit(widget.isPersian),
                  textDirection: TextDirection.ltr,
                  style: TextStyle(
                    fontFamily: widget.mainFont,
                    fontSize: 15 * widget.textScale,
                    color: AppColors.primaryBlue,
                  ),
                ),
            ],
          ],
        );
      },
    );
  }
}

// ---------------- دیالوگ تنظیمات (ترکیب زبان و سایز فونت) ----------------
class _SettingsDialog extends StatefulWidget {
  final String mainFont;
  const _SettingsDialog({required this.mainFont});

  @override
  State<_SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<_SettingsDialog> {
  late double _textSize;

  @override
  void initState() {
    super.initState();
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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: Text(loc['profile_app_settings'] ?? 'تنظیمات برنامه',
          style: TextStyle(
              fontFamily: widget.mainFont, fontWeight: FontWeight.bold)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // بخش انتخاب زبان
          Text('زبان (Language)',
              style: TextStyle(
                  fontFamily: widget.mainFont,
                  fontWeight: FontWeight.bold,
                  fontSize: 14)),
          const SizedBox(height: 12),
          _LanguageOption(
            title: 'English',
            font: widget.mainFont,
            isSelected: localeProvider.locale.languageCode == 'en',
            onTap: () {
              localeProvider.setLocale(const Locale('en'));
              Navigator.of(context).pop();
            },
          ),
          const SizedBox(height: 8),
          _LanguageOption(
            title: 'فارسی',
            font: 'Vazir',
            isSelected: localeProvider.locale.languageCode == 'fa',
            onTap: () {
              localeProvider.setLocale(const Locale('fa'));
              Navigator.of(context).pop();
            },
          ),

          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 16),

          // بخش تغییر سایز متن
          Text('اندازه متن (Text Size)',
              style: TextStyle(
                  fontFamily: widget.mainFont,
                  fontWeight: FontWeight.bold,
                  fontSize: 14)),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.format_size, size: 16, color: Colors.grey),
              Expanded(
                child: Slider(
                  value: _textSize,
                  min: 0.8,
                  max: 1.5,
                  divisions: 3,
                  activeColor: AppColors.primaryBlue,
                  inactiveColor: AppColors.primaryBlue.withOpacity(0.2),
                  onChanged: (val) {
                    setState(() {
                      _textSize = val;
                    });
                    settingsProvider.updateTextScale(val);
                  },
                ),
              ),
              const Icon(Icons.format_size, size: 26, color: Colors.grey),
            ],
          ),
        ],
      ),
    );
  }
}

class _LanguageOption extends StatelessWidget {
  final String title;
  final String font;
  final bool isSelected;
  final VoidCallback onTap;

  const _LanguageOption({
    required this.title,
    required this.font,
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
              ? AppColors.primaryBlue.withOpacity(0.1)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: isSelected ? AppColors.primaryBlue : Colors.grey.shade300),
        ),
        child: Row(
          children: [
            Text(title,
                style: TextStyle(
                    fontFamily: font,
                    fontSize: 16,
                    color:
                        isSelected ? AppColors.primaryBlue : Colors.black87)),
            const Spacer(),
            if (isSelected)
              const Icon(Icons.check_circle, color: AppColors.primaryBlue),
          ],
        ),
      ),
    );
  }
}
