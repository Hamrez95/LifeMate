// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:lifemate_client/lifemate_client.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_style.dart';
import '../../core/utils/string_extensions.dart';
import '../../localization/app_localizations.dart';
import '../../localization/locale_provider.dart';
import '../../providers/settings_provider.dart';
import 'care_access_screen.dart';
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
      Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => page),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 24),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 16,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    IconButton(
                      tooltip: 'بازگشت',
                      icon: const Icon(
                        Icons.arrow_back_ios_new_rounded,
                        size: 24,
                        color: AppColors.primaryBlue,
                      ),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _CurrentUserIdentity(
                        mainFont: mainFont,
                        isPersian: isPersian,
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      tooltip: 'اعلان‌ها',
                      icon: const Icon(
                        Icons.notifications_none_rounded,
                        size: 24,
                        color: AppColors.primaryBlue,
                      ),
                      onPressed: () => open(const NotificationCenterScreen()),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 8,
                ),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    vertical: 16,
                    horizontal: 18,
                  ),
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
                                fontSize: 15,
                                color: AppColors.darkBlue,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.darkBlue,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    elevation: 0,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 18,
                                      vertical: 8,
                                    ),
                                  ),
                                  onPressed: () =>
                                      open(const SubscriptionScreen()),
                                  child: Text(
                                    loc['profile_buy_plan'] ?? 'خرید اشتراک',
                                    style: TextStyle(
                                      fontFamily: mainFont,
                                      fontSize: 14,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                                Text(
                                  'در دست توسعه',
                                  style: TextStyle(
                                    fontFamily: mainFont,
                                    fontSize: 12,
                                    color: AppColors.primaryBlue,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Container(
                        padding: const EdgeInsets.all(5),
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
                        child: const Icon(
                          Icons.emoji_events_rounded,
                          size: 36,
                          color: Colors.amber,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 8,
                ),
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
                        label: loc['profile_personal_info'] ?? 'اطلاعات شخصی',
                        mainFont: mainFont,
                        onTap: () => open(const PersonalInformationScreen()),
                      ),
                      const Divider(height: 1, indent: 60, endIndent: 20),
                      _ProfileMenuTile(
                        icon: Icons.assignment_rounded,
                        iconColor: Colors.orangeAccent,
                        label:
                            loc['profile_health_profile'] ?? 'پرونده سلامت',
                        mainFont: mainFont,
                        onTap: () => open(const HealthRecordScreen()),
                      ),
                      const Divider(height: 1, indent: 60, endIndent: 20),
                      _ProfileMenuTile(
                        icon: Icons.group,
                        iconColor: Colors.green,
                        label: loc['profile_caregivers'] ?? 'مراقبان',
                        mainFont: mainFont,
                        onTap: () => open(const CareAccessScreen()),
                      ),
                      const Divider(height: 1, indent: 60, endIndent: 20),
                      _ProfileMenuTile(
                        icon: Icons.settings,
                        iconColor: Colors.purple,
                        label:
                            loc['profile_app_settings'] ?? 'تنظیمات برنامه',
                        mainFont: mainFont,
                        onTap: () => showDialog<void>(
                          context: context,
                          builder: (_) => _SettingsDialog(
                            mainFont: mainFont,
                          ),
                        ),
                      ),
                      const Divider(height: 1, indent: 60, endIndent: 20),
                      _ProfileMenuTile(
                        icon: Icons.card_giftcard,
                        iconColor: Colors.redAccent,
                        label: loc['profile_referral_code'] ?? 'کد معرف',
                        mainFont: mainFont,
                        subtitle: 'در دست توسعه',
                        onTap: () => open(const ReferralScreen()),
                      ),
                      const Divider(height: 1, indent: 60, endIndent: 20),
                      _ProfileMenuTile(
                        icon: Icons.support_agent,
                        iconColor: Colors.indigo,
                        label: loc['profile_support'] ?? 'پشتیبانی',
                        mainFont: mainFont,
                        subtitle: 'راهنما فعال؛ ارسال تیکت در دست توسعه',
                        onTap: () => open(const SupportScreen()),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 8,
                ),
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
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),
                    icon: const Icon(Icons.logout, color: Colors.redAccent),
                    label: Text(
                      loc['profile_logout'] ?? 'خروج از حساب',
                      style: TextStyle(
                        fontFamily: mainFont,
                        fontSize: 16,
                        color: Colors.redAccent,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    onPressed: LifeMateAuth.signOut,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'WellMate 0.8.0-beta.3'.toPersianDigit(isPersian),
                  style: TextStyle(
                    fontFamily: mainFont,
                    fontSize: 12,
                    color: AppColors.secondaryText.withOpacity(0.7),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CurrentUserIdentity extends StatefulWidget {
  const _CurrentUserIdentity({
    required this.mainFont,
    required this.isPersian,
  });

  final String mainFont;
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
        final data = snapshot.data ?? const <String, dynamic>{};
        final user = data['user'] as Map<String, dynamic>? ?? const {};
        final profile = data['profile'] as Map<String, dynamic>? ?? const {};
        final rawName = profile['displayName']?.toString().trim();
        final name = rawName == null || rawName.isEmpty
            ? 'کاربر LifeMate'
            : rawName;
        final phone = profile['phoneNumber']?.toString().trim() ?? '';
        final email = user['email']?.toString().trim() ?? '';
        final contact = phone.isNotEmpty ? phone : email;

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
              child: Stack(
                alignment: Alignment.center,
                children: [
                  const CircleAvatar(
                    radius: 36,
                    backgroundColor: Colors.transparent,
                    backgroundImage: AssetImage(
                      'assets/images/mother_avatar.png',
                    ),
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
                      child: const Icon(
                        Icons.camera_alt,
                        size: 16,
                        color: AppColors.primaryBlue,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            if (snapshot.connectionState != ConnectionState.done)
              const SizedBox.square(
                dimension: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else ...[
              Text(
                name,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: widget.mainFont,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: AppColors.darkBlue,
                ),
              ),
              if (contact.isNotEmpty)
                Text(
                  contact.toPersianDigit(widget.isPersian),
                  textAlign: TextAlign.center,
                  textDirection: TextDirection.ltr,
                  style: TextStyle(
                    fontFamily: widget.mainFont,
                    fontSize: 14,
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

class _ProfileMenuTile extends StatelessWidget {
  const _ProfileMenuTile({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.mainFont,
    required this.onTap,
    this.subtitle,
  });

  final IconData icon;
  final Color iconColor;
  final String label;
  final String mainFont;
  final VoidCallback onTap;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
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
      title: Text(
        label,
        style: TextStyle(
          fontFamily: mainFont,
          fontSize: 16,
          color: AppColors.darkBlue,
        ),
      ),
      subtitle: subtitle == null
          ? null
          : Text(
              subtitle!,
              style: TextStyle(
                fontFamily: mainFont,
                fontSize: 11,
                color: AppColors.textSecondary,
              ),
            ),
      trailing: const Icon(
        Icons.arrow_forward_ios_rounded,
        size: 14,
        color: Colors.grey,
      ),
      onTap: onTap,
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
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
      ),
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
              activeColor: AppColors.primaryBlue,
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
