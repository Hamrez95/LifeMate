// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../localization/app_localizations.dart';
import '../localization/locale_provider.dart';

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
                              loc['profile_name'],
                              style: TextStyle(fontFamily: mainFont, fontSize: 22, fontWeight: FontWeight.bold, color: const Color(0xFF283054)),
                            ),
                            Text(
                              loc['profile_phone'],
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
                                  loc['profile_no_subscription'],
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
                                      child: Text(loc['profile_buy_plan'], style: TextStyle(fontFamily: mainFont, fontSize: 14, color: Colors.white)),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(loc['profile_renew'], style: TextStyle(fontFamily: mainFont, fontSize: 14, color: Color(0xFF7B93DB))),
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
                Padding(
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
                        _ProfileMenuTile(
                          icon: Icons.person,
                          iconColor: Colors.blueAccent,
                          label: loc['profile_personal_info'],
                          mainFont: mainFont,
                        ),
                        _ProfileMenuTile(
                          icon: Icons.assignment_rounded,
                          iconColor: Colors.orangeAccent,
                          label: loc['profile_health_profile'],
                          mainFont: mainFont,
                        ),
                        _ProfileMenuTile(
                          icon: Icons.group,
                          iconColor: Colors.green,
                          label: loc['profile_caregivers'],
                          mainFont: mainFont,
                        ),
                        _ProfileMenuTile(
                          icon: Icons.settings,
                          iconColor: Colors.purple,
                          label: loc['profile_app_settings'],
                          mainFont: mainFont,
                          onTap: () {
                            showDialog(
                              context: context,
                              builder: (context) => _LanguageDialog(mainFont: mainFont),
                            );
                          },
                        ),
                        _ProfileMenuTile(
                          icon: Icons.card_giftcard,
                          iconColor: Colors.redAccent,
                          label: loc['profile_referral_code'],
                          mainFont: mainFont,
                        ),
                        _ProfileMenuTile(
                          icon: Icons.support_agent,
                          iconColor: Colors.indigo,
                          label: loc['profile_support'],
                          mainFont: mainFont,
                        ),
                      ],
                    ),
                  ),
                ),
                // Footer
                const Spacer(),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  child: Container(
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
                        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 24),
                        backgroundColor: Colors.transparent,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                      ),
                      icon: const Icon(Icons.logout, color: Colors.redAccent),
                      label: Text(loc['profile_logout'], style: TextStyle(fontFamily: mainFont, fontSize: 16, color: Colors.redAccent)),
                      onPressed: () {},
                    ),
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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      contentPadding: const EdgeInsets.all(24),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(loc['settings_language'], style: TextStyle(fontFamily: mainFont, fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          DropdownButton<String>(
            value: localeProvider.locale.languageCode,
            items: [
              DropdownMenuItem(value: 'en', child: Text('English', style: TextStyle(fontFamily: mainFont))),
              DropdownMenuItem(value: 'fa', child: Text('فارسی', style: TextStyle(fontFamily: 'Vazir'))),
            ],
            onChanged: (value) {
              if (value != null) {
                localeProvider.setLocale(Locale(value));
                Navigator.of(context).pop();
              }
            },
          ),
        ],
      ),
    );
  }
}
