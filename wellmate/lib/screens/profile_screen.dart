import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
// اطمینان حاصل کنید مسیر ایمپورت‌ها درست باشد
import '../localization/app_localizations.dart'; 
import '../localization/locale_provider.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // نکته: اگر از flutter_gen استفاده می‌کنید، معمولا دسترسی به صورت loc.profile_name است
    // اما من طبق کد شما دسترسی را به صورت loc['key'] حفظ کردم.
    final loc = AppLocalizations.of(context);
    final localeProvider = Provider.of<LocaleProvider>(context);
    final isPersian = localeProvider.locale.languageCode == 'fa';
    final mainFont = isPersian ? 'Vazir' : 'Nunito';

    return Scaffold(
      backgroundColor: const Color(0xFFEAF2FB),
      appBar: AppBar(
        title: Text(loc['app_bar_title'] ?? 'Profile', style: TextStyle(fontFamily: mainFont, color: Colors.black)),
        centerTitle: true,
        backgroundColor: const Color(0xFFEAF2FB),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 24, color: Color(0xFF7B93DB)),
          onPressed: () => Navigator.of(context).pop(),
          splashRadius: 24,
        ),
        actions: [
           IconButton(
            icon: const Icon(Icons.notifications_none_rounded, size: 24, color: Color(0xFF7B93DB)),
            onPressed: () {},
            splashRadius: 24,
            tooltip: loc['notification_title'] ?? 'Notifications',
          ),
        ],
      ),
      body: SafeArea(
        child: Stack(
          children: [
            SingleChildScrollView( // اضافه شده برای جلوگیری از ارور بیرون زدگی در گوشی‌های کوچک
              child: Column(
                children: [
                  // Header
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
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
                              const CircleAvatar(
                                radius: 36,
                                backgroundColor: Color(0xFFE2D4C8),
                                child: Icon(Icons.person, size: 48, color: Colors.white),
                              ),
                              Positioned(
                                bottom: 0,
                                right: 0,
                                child: Container(
                                  padding: const EdgeInsets.all(4),
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
                                  child: const Icon(Icons.camera_alt, size: 14, color: Color(0xFF7B93DB)),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          loc['profile_name'] ?? 'User Name',
                          style: TextStyle(fontFamily: mainFont, fontSize: 22, fontWeight: FontWeight.bold, color: const Color(0xFF283054)),
                        ),
                        Text(
                          loc['profile_phone'] ?? '0912***',
                          style: TextStyle(fontFamily: mainFont, fontSize: 15, color: const Color(0xFF7B93DB)),
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
                                    loc['subscription_card_message'] ?? 'No Active Subscription',
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
                                        child: Text(loc['buy_plan_button'] ?? 'Buy Plan', style: TextStyle(fontFamily: mainFont, fontSize: 14, color: Colors.white)),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(loc['renew_button'] ?? 'Renew', style: TextStyle(fontFamily: mainFont, fontSize: 14, color: const Color(0xFF7B93DB))),
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
                                    color: Colors.amber.withOpacity(0.25),
                                    blurRadius: 16,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(8.0),
                                child: const Icon(Icons.emoji_events_rounded, size: 32, color: Colors.amber),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  // Menu List
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
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
                          _ProfileMenuTile(
                            icon: Icons.person,
                            iconColor: Colors.blueAccent,
                            label: loc['personal_info_title'] ?? 'Personal Info',
                            mainFont: mainFont,
                          ),
                          const Divider(height: 1, indent: 60, endIndent: 20),
                          _ProfileMenuTile(
                            icon: Icons.assignment_rounded,
                            iconColor: Colors.orangeAccent,
                            label: loc['health_profile_title'] ?? 'Health Profile',
                            mainFont: mainFont,
                          ),
                          const Divider(height: 1, indent: 60, endIndent: 20),
                          _ProfileMenuTile(
                            icon: Icons.group,
                            iconColor: Colors.green,
                            label: loc['caregivers_title'] ?? 'Caregivers',
                            mainFont: mainFont,
                          ),
                          const Divider(height: 1, indent: 60, endIndent: 20),
                          _ProfileMenuTile(
                            icon: Icons.settings,
                            iconColor: Colors.purple,
                            label: loc['app_settings_title'] ?? 'App Settings',
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
                            label: loc['referral_code_title'] ?? 'Referral Code',
                            mainFont: mainFont,
                          ),
                          const Divider(height: 1, indent: 60, endIndent: 20),
                          _ProfileMenuTile(
                            icon: Icons.support_agent,
                            iconColor: Colors.indigo,
                            label: loc['support_title'] ?? 'Support',
                            mainFont: mainFont,
                          ),
                        ],
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
                          loc['logout_button'] ?? 'Log Out', 
                          style: TextStyle(fontFamily: mainFont, fontSize: 16, color: Colors.redAccent, fontWeight: FontWeight.bold)
                        ),
                        onPressed: () {},
                      ),
                    ),
                  ),
                  
                  // Footer Message
                  Padding(
                    padding: const EdgeInsets.only(top: 8, bottom: 24),
                    child: Text(
                      loc['footer_message'] ?? 'Version 1.0.0', 
                      style: TextStyle(fontFamily: mainFont, fontSize: 12, color: const Color(0xFF7B93DB).withOpacity(0.7))
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------- Helper Widgets ----------------

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
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: iconColor.withOpacity(0.1),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: iconColor, size: 22),
      ),
      title: Text(label, style: TextStyle(fontFamily: mainFont, fontSize: 16, color: const Color(0xFF283054), fontWeight: FontWeight.w500)),
      trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16, color: Colors.grey),
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
      title: Text(loc['language_dialog_title'] ?? 'Select Language', style: TextStyle(fontFamily: mainFont, fontWeight: FontWeight.bold)),
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
