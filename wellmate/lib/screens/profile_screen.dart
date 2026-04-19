// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../localization/app_localizations.dart';
import '../localization/locale_provider.dart';

// 👇 این ایمپورت را برای اعمال تبدیل اعداد اضافه کنید 👇
import '../utils/string_extensions.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final localeProvider = Provider.of<LocaleProvider>(context);
    final isPersian = localeProvider.locale.languageCode == 'fa';
    final mainFont = isPersian ? 'Vazir' : 'Nunito';

    return Scaffold(
      backgroundColor: const Color(0xFFEAF2FB),
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                // Header
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 24, color: Color(0xFF7B93DB)),
                        onPressed: () => Navigator.of(context).pop(),
                        splashRadius: 24,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
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
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  CircleAvatar(
                                    radius: 36,
                                    backgroundColor: const Color(0xFFE2D4C8),
                                    child: Icon(Icons.person, size: 48, color: Colors.white),
                                  ),
                                  Positioned(
                                    bottom: 8,
                                    right: 8,
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        shape: BoxShape.circle,
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black.withOpacity(0.12),
                                            blurRadius: 8,
                                          ),
                                        ],
                                      ),
                                      child: Icon(Icons.camera_alt, size: 18, color: Color(0xFF7B93DB)),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              loc['profile_name'] ?? 'نام کاربر',
                              style: TextStyle(fontFamily: mainFont, fontSize: 22, fontWeight: FontWeight.bold, color: const Color(0xFF283054)),
                            ),
                            // 👇 تبدیل شماره تماس به فارسی 👇
                            Text(
                              (loc['profile_phone'] ?? '').toString().toPersianDigit(isPersian),
                              style: TextStyle(fontFamily: mainFont, fontSize: 15, color: const Color(0xFF7B93DB)),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.notifications_none_rounded, size: 24, color: Color(0xFF7B93DB)),
                        onPressed: () {},
                        splashRadius: 24,
                      ),
                    ],
                  ),
                ),
                // Subscription Card
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
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
                      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 18),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  loc['profile_no_subscription'] ?? 'اشتراکی ندارید',
                                  style: TextStyle(fontFamily: mainFont, fontSize: 15, color: const Color(0xFF283054)),
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    ElevatedButton(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(0xFF283054),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                        elevation: 0,
                                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                                      ),
                                      onPressed: () {},
                                      child: Text(loc['profile_buy_plan'] ?? 'خرید اشتراک', style: TextStyle(fontFamily: mainFont, fontSize: 14, color: Colors.white)),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(loc['profile_renew'] ?? 'تمدید', style: TextStyle(fontFamily: mainFont, fontSize: 14, color: Color(0xFF7B93DB))),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          // Crown Icon
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: const Color.fromARGB(64, 255, 191, 0),
                                  blurRadius: 16,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: const Icon(Icons.emoji_events_rounded, size: 36, color: Colors.amber),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                // Menu List
                Expanded( // استفاده از Expanded یا SingleChildScrollView برای جلوگیری از overflow در صفحه‌های کوچک
                  child: SingleChildScrollView(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
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
                            ),
                            const Divider(height: 1, indent: 60, endIndent: 20),
                            _ProfileMenuTile(
                              icon: Icons.assignment_rounded,
                              iconColor: Colors.orangeAccent,
                              label: loc['profile_health_profile'] ?? 'پروفایل سلامت',
                              mainFont: mainFont,
                            ),
                            const Divider(height: 1, indent: 60, endIndent: 20),
                            _ProfileMenuTile(
                              icon: Icons.group,
                              iconColor: Colors.green,
                              label: loc['profile_caregivers'] ?? 'مراقبین',
                              mainFont: mainFont,
                            ),
                            const Divider(height: 1, indent: 60, endIndent: 20),
                            _ProfileMenuTile(
                              icon: Icons.settings,
                              iconColor: Colors.purple,
                              label: loc['profile_app_settings'] ?? 'تنظیمات برنامه',
                              mainFont: mainFont,
                              onTap: () {
                                showDialog(
                                  context: context,
                                  builder: (context) => _LanguageDialog(mainFont: mainFont),
                                );
                              },
                            ),
                              const Divider(height: 1, indent: 60, endIndent: 20),
                            _ProfileMenuTile(
                              icon: Icons.card_giftcard,
                              iconColor: Colors.redAccent,
                              label: loc['profile_referral_code'] ?? 'کد معرفی',
                              mainFont: mainFont,
                            ),
                             const Divider(height: 1, indent: 60, endIndent: 20),
                            _ProfileMenuTile(
                              icon: Icons.support_agent,
                              iconColor: Colors.indigo,
                              label: loc['profile_support'] ?? 'پشتیبانی',
                              mainFont: mainFont,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                 // Footer - Log Out
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
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
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                        ),
                        icon: const Icon(Icons.logout, color: Colors.redAccent),
                        label: Text(
                          loc['profile_logout'] ?? 'Log Out', 
                          style: TextStyle(fontFamily: mainFont, fontSize: 16, color: Colors.redAccent, fontWeight: FontWeight.bold)
                        ),
                        onPressed: () {},
                      ),
                    ),
                  ),
                  
                  // Footer Message
                  Padding(
                    padding: const EdgeInsets.only(top: 8, bottom: 24),
                    // 👇 تبدیل اعداد نسخه اپلیکیشن به فارسی 👇
                    child: Text(
                      (loc['footer_message'] ?? 'Version 1.0.0').toString().toPersianDigit(isPersian), 
                      style: TextStyle(fontFamily: mainFont, fontSize: 12, color: const Color(0xFF7B93DB).withOpacity(0.7))
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileMenuTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String mainFont;
  final VoidCallback? onTap;

  const _ProfileMenuTile({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.mainFont,
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
      title: Text(label, style: TextStyle(fontFamily: mainFont, fontSize: 16, color: const Color(0xFF283054))),
      onTap: onTap,
    );
  }
}

class _LanguageDialog extends StatelessWidget {
  final String mainFont;
  const _LanguageDialog({required this.mainFont});

  @override
  Widget build(BuildContext context) {
    final localeProvider = Provider.of<LocaleProvider>(context);
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
          color: isSelected ? Colors.blue.withOpacity(0.1) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: isSelected ? Colors.blue : Colors.grey.shade300),
        ),
        child: Row(
          children: [
            Text(title, style: TextStyle(fontFamily: font, fontSize: 16, color: isSelected ? Colors.blue : Colors.black87)),
            const Spacer(),
            if (isSelected) const Icon(Icons.check_circle, color: Colors.blue),
          ],
        ),
      ),
    );
  }
}
