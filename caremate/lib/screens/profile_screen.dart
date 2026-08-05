import 'package:flutter/material.dart';
import 'package:lifemate_client/lifemate_client.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_version.dart';
import '../../core/localization/app_localizations.dart';
import '../../core/localization/locale_provider.dart';
import '../../core/utils/string_extensions.dart';
import 'editable_profile_screen.dart';
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
        child: Column(
          children: [
            _ProfileTopBar(
              mainFont: mainFont,
              onNotifications: () =>
                  openScreen(const CareMateNotificationsScreen()),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                child: Column(
                  children: [
                    _CurrentCareMateIdentity(mainFont: mainFont),
                    const SizedBox(height: 12),
                    _SubscriptionCard(
                      mainFont: mainFont,
                      title: loc['profile_no_subscription'] ??
                          'اشتراک مراقبتی',
                      onTap: () =>
                          openScreen(const CareMateSubscriptionScreen()),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      clipBehavior: Clip.antiAlias,
                      decoration: _cardDecoration(),
                      child: Column(
                        children: [
                          _ProfileMenuTile(
                            icon: Icons.person_outline_rounded,
                            iconColor: AppColors.primaryBlue,
                            label: loc['profile_personal_info'] ??
                                'اطلاعات شخصی',
                            mainFont: mainFont,
                            subtitle: 'ویرایش نام، تصویر و اطلاعات حساب',
                            onTap: () => openScreen(
                              const CareMateEditableProfileScreen(),
                            ),
                          ),
                          const _MenuDivider(),
                          _ProfileMenuTile(
                            icon: Icons.assignment_outlined,
                            iconColor: Colors.orangeAccent,
                            label: loc['profile_health_profile'] ??
                                'پرونده سلامت',
                            mainFont: mainFont,
                            subtitle: 'مشاهده اطلاعات مجاز فرد تحت مراقبت',
                            onTap: () => openScreen(
                              const CareMateFeaturePreviewScreen(
                                initialIndex: 2,
                              ),
                            ),
                          ),
                          const _MenuDivider(),
                          _ProfileMenuTile(
                            icon: Icons.family_restroom_rounded,
                            iconColor: const Color(0xFF43A574),
                            label: loc['profile_caregivers'] ?? 'مراقبت خانواده',
                            mainFont: mainFont,
                            subtitle: 'روابط مراقبتی و محدوده دسترسی‌ها',
                            onTap: () => openScreen(
                              const CareMateFeaturePreviewScreen(
                                initialIndex: 3,
                              ),
                            ),
                          ),
                          const _MenuDivider(),
                          _ProfileMenuTile(
                            icon: Icons.tune_rounded,
                            iconColor: const Color(0xFF8B72D6),
                            label: loc['profile_app_settings'] ??
                                'تنظیمات برنامه',
                            mainFont: mainFont,
                            subtitle: 'زبان و نمایش برنامه',
                            onTap: () => showDialog<void>(
                              context: context,
                              builder: (_) =>
                                  _LanguageDialog(mainFont: mainFont),
                            ),
                          ),
                          const _MenuDivider(),
                          _ProfileMenuTile(
                            icon: Icons.card_giftcard_rounded,
                            iconColor: const Color(0xFFE06B7B),
                            label: loc['profile_referral_code'] ?? 'کد معرف',
                            mainFont: mainFont,
                            subtitle: 'در دست توسعه',
                            onTap: () =>
                                openScreen(const CareMateReferralScreen()),
                          ),
                          const _MenuDivider(),
                          _ProfileMenuTile(
                            icon: Icons.support_agent_rounded,
                            iconColor: const Color(0xFF5B69B2),
                            label: loc['profile_support'] ?? 'پشتیبانی',
                            mainFont: mainFont,
                            subtitle: 'راهنما و پاسخ پرسش‌های متداول',
                            onTap: () =>
                                openScreen(const CareMateSupportScreen()),
                          ),
                          const _MenuDivider(),
                          _ProfileMenuTile(
                            key: const ValueKey<String>(
                              'caremate-profile-sign-out',
                            ),
                            icon: Icons.logout_rounded,
                            iconColor: Colors.redAccent,
                            label: loc['profile_logout'] ?? 'خروج از حساب',
                            mainFont: mainFont,
                            subtitle: 'پایان‌دادن امن نشست روی این دستگاه',
                            destructive: true,
                            showChevron: false,
                            onTap: () {
                              _confirmSignOut(context, mainFont);
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'CareMate $careMateAppVersion'.toPersianDigit(isPersian),
                      style: TextStyle(
                        fontFamily: mainFont,
                        fontSize: 11,
                        color: AppColors.secondaryText.withValues(alpha: 0.72),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Future<void> _confirmSignOut(
    BuildContext context,
    String mainFont,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text(
          'خروج از حساب؟',
          style: TextStyle(fontFamily: mainFont, fontWeight: FontWeight.w900),
        ),
        content: Text(
          'برای ورود دوباره باید ایمیل و رمز عبور خود را وارد کنید.',
          style: TextStyle(fontFamily: mainFont, height: 1.6),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('انصراف'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('خروج امن'),
          ),
        ],
      ),
    );
    if (confirmed == true) await LifeMateAuth.signOut();
  }

  static BoxDecoration _cardDecoration() => BoxDecoration(
        color: Colors.white.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: AppColors.primaryBlue.withValues(alpha: 0.06),
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryBlue.withValues(alpha: 0.07),
            blurRadius: 22,
            offset: const Offset(0, 9),
          ),
        ],
      );
}

class _ProfileTopBar extends StatelessWidget {
  const _ProfileTopBar({
    required this.mainFont,
    required this.onNotifications,
  });

  final String mainFont;
  final VoidCallback onNotifications;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
      child: Row(
        children: [
          IconButton.filledTonal(
            tooltip: 'بازگشت',
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'پروفایل',
              style: TextStyle(
                fontFamily: mainFont,
                fontSize: 21,
                fontWeight: FontWeight.w900,
                color: AppColors.darkBlue,
              ),
            ),
          ),
          IconButton.filledTonal(
            tooltip: 'اعلان‌های حساب',
            onPressed: onNotifications,
            icon: const Icon(Icons.notifications_none_rounded, size: 22),
          ),
        ],
      ),
    );
  }
}

class _SubscriptionCard extends StatelessWidget {
  const _SubscriptionCard({
    required this.mainFont,
    required this.title,
    required this.onTap,
  });

  final String mainFont;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Ink(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: AlignmentDirectional.topStart,
              end: AlignmentDirectional.bottomEnd,
              colors: [Color(0xFFF4F8FF), Color(0xFFEAF3FF)],
            ),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: AppColors.primaryBlue.withValues(alpha: 0.10),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.86),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(
                  Icons.workspace_premium_rounded,
                  color: Color(0xFFE4A52C),
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontFamily: mainFont,
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        color: AppColors.darkBlue,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'امکانات پایه مراقبت در نسخه آزمایشی فعال است',
                      style: TextStyle(
                        fontFamily: mainFont,
                        fontSize: 11,
                        color: AppColors.secondaryText,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.80),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'آزمایشی',
                  style: TextStyle(
                    fontFamily: mainFont,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: AppColors.primaryBlue,
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

class _CurrentCareMateIdentity extends StatefulWidget {
  const _CurrentCareMateIdentity({required this.mainFont});

  final String mainFont;

  @override
  State<_CurrentCareMateIdentity> createState() =>
      _CurrentCareMateIdentityState();
}

class _CurrentCareMateIdentityState extends State<_CurrentCareMateIdentity> {
  late Future<Map<String, dynamic>> _future;

  @override
  void initState() {
    super.initState();
    _future = context.read<LifeMateApiClient>().getCurrentUser();
  }

  Future<void> _openEditor() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const CareMateEditableProfileScreen(),
      ),
    );
    if (!mounted) return;
    setState(() {
      _future = context.read<LifeMateApiClient>().getCurrentUser();
    });
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
        final email = profile['email']?.toString().trim().isNotEmpty == true
            ? profile['email'].toString()
            : user['email']?.toString() ?? '';

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(17),
          decoration: ProfileScreen._cardDecoration(),
          child: Row(
            children: [
              InkWell(
                onTap: _openEditor,
                customBorder: const CircleBorder(),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    LifeMateProfileAvatar(
                      avatarKey: profile['avatarKey']?.toString(),
                      radius: 36,
                    ),
                    PositionedDirectional(
                      end: -3,
                      bottom: -3,
                      child: Container(
                        width: 25,
                        height: 25,
                        decoration: BoxDecoration(
                          color: AppColors.primaryBlue,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                        child: const Icon(
                          Icons.edit_rounded,
                          size: 13,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 15),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name == null || name.isEmpty ? 'کاربر CareMate' : name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: widget.mainFont,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: AppColors.darkBlue,
                      ),
                    ),
                    const SizedBox(height: 4),
                    if (snapshot.connectionState == ConnectionState.waiting)
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    else if (email.isNotEmpty)
                      Text(
                        email,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textDirection: TextDirection.ltr,
                        style: TextStyle(
                          fontFamily: widget.mainFont,
                          fontSize: 11,
                          color: AppColors.secondaryText,
                        ),
                      ),
                    const SizedBox(height: 7),
                    Text(
                      'برای ویرایش تصویر و اطلاعات حساب لمس کنید',
                      style: TextStyle(
                        fontFamily: widget.mainFont,
                        fontSize: 10,
                        color: AppColors.primaryBlue,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'ویرایش پروفایل',
                onPressed: _openEditor,
                icon: const Icon(Icons.chevron_left_rounded),
                color: AppColors.primaryBlue,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _MenuDivider extends StatelessWidget {
  const _MenuDivider();

  @override
  Widget build(BuildContext context) => Divider(
        height: 1,
        thickness: 1,
        indent: 66,
        endIndent: 16,
        color: AppColors.primaryBlue.withValues(alpha: 0.06),
      );
}

class _ProfileMenuTile extends StatelessWidget {
  const _ProfileMenuTile({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.mainFont,
    required this.onTap,
    this.subtitle,
    this.destructive = false,
    this.showChevron = true,
  });

  final IconData icon;
  final Color iconColor;
  final String label;
  final String mainFont;
  final String? subtitle;
  final VoidCallback onTap;
  final bool destructive;
  final bool showChevron;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: destructive
          ? Colors.redAccent.withValues(alpha: 0.025)
          : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.11),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: iconColor, size: 21),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontFamily: mainFont,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: destructive
                            ? Colors.redAccent
                            : AppColors.darkBlue,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: mainFont,
                          fontSize: 10,
                          color: destructive
                              ? Colors.redAccent.withValues(alpha: 0.72)
                              : AppColors.secondaryText,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (showChevron)
                Icon(
                  Directionality.of(context) == TextDirection.rtl
                      ? Icons.chevron_left_rounded
                      : Icons.chevron_right_rounded,
                  size: 20,
                  color: AppColors.secondaryText.withValues(alpha: 0.72),
                ),
            ],
          ),
        ),
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
      title: Text(
        loc['settings_language'] ?? 'Select Language',
        style: TextStyle(fontFamily: mainFont, fontWeight: FontWeight.bold),
      ),
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
          const SizedBox(height: 10),
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
  const _LanguageOption({
    required this.title,
    required this.font,
    required this.isSelected,
    required this.onTap,
  });

  final String title;
  final String font;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 14),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primaryBlue.withValues(alpha: 0.09)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? AppColors.primaryBlue : Colors.grey.shade300,
          ),
        ),
        child: Row(
          children: [
            Text(
              title,
              style: TextStyle(
                fontFamily: font,
                fontSize: 15,
                color: isSelected ? AppColors.primaryBlue : Colors.black87,
              ),
            ),
            const Spacer(),
            if (isSelected)
              const Icon(
                Icons.check_circle_rounded,
                color: AppColors.primaryBlue,
                size: 21,
              ),
          ],
        ),
      ),
    );
  }
}
