import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lifemate_client/lifemate_client.dart';

import 'profile_theme.dart';

@immutable
class LifeMateProfileMenuItem {
  const LifeMateProfileMenuItem({
    this.key,
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.onTap,
    this.subtitle,
  });

  final Key? key;
  final IconData icon;
  final Color iconColor;
  final String label;
  final String? subtitle;
  final VoidCallback onTap;
}

class LifeMateSharedProfileScreen extends StatelessWidget {
  const LifeMateSharedProfileScreen({
    super.key,
    required this.apiClient,
    required this.theme,
    required this.labels,
    required this.fontFamily,
    required this.appName,
    required this.versionLabel,
    required this.fallbackUserName,
    required this.isPersian,
    required this.onNotifications,
    required this.onEditProfile,
    required this.onHealthProfile,
    required this.onCareManagement,
    required this.onAppSettings,
    required this.onReferral,
    required this.onSupport,
    required this.onManageSubscriptions,
    this.additionalMenuItems = const <LifeMateProfileMenuItem>[],
  });

  final LifeMateApiClient apiClient;
  final LifeMateProfileThemeData theme;
  final LifeMateProfileLabels labels;
  final String fontFamily;
  final String appName;
  final String versionLabel;
  final String fallbackUserName;
  final bool isPersian;
  final VoidCallback onNotifications;
  final VoidCallback onEditProfile;
  final VoidCallback onHealthProfile;
  final VoidCallback onCareManagement;
  final VoidCallback onAppSettings;
  final VoidCallback onReferral;
  final VoidCallback onSupport;
  final VoidCallback onManageSubscriptions;
  final List<LifeMateProfileMenuItem> additionalMenuItems;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const ValueKey('lifemate-shared-profile-layout'),
      backgroundColor: theme.background,
      body: SafeArea(
        child: SingleChildScrollView(
          key: const ValueKey('lifemate-shared-profile-scroll'),
          padding: const EdgeInsets.only(bottom: 24),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    IconButton(
                      tooltip: LifeMateRuntimeLocale.select(
                        fa: LifeMateRuntimeLocale.select(
                          fa: 'بازگشت',
                          en: "Back",
                        ),
                        en: "return",
                      ),
                      icon: Icon(
                        Icons.arrow_back_ios_new_rounded,
                        size: 24,
                        color: theme.accent,
                      ),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _CurrentUserIdentity(
                        apiClient: apiClient,
                        theme: theme,
                        fontFamily: fontFamily,
                        isPersian: isPersian,
                        fallbackUserName: fallbackUserName,
                        onEditProfile: onEditProfile,
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      tooltip: LifeMateRuntimeLocale.select(
                        fa: LifeMateRuntimeLocale.select(
                          fa: 'اعلان‌ها',
                          en: "Notifications",
                        ),
                        en: "Notifications",
                      ),
                      icon: Icon(
                        Icons.notifications_none_rounded,
                        size: 24,
                        color: theme.accent,
                      ),
                      onPressed: onNotifications,
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                child: _SubscriptionCard(
                  theme: theme,
                  fontFamily: fontFamily,
                  title: labels.subscriptionTitle,
                  actionLabel: labels.manageSubscriptions,
                  onTap: onManageSubscriptions,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                child: Container(
                  decoration: BoxDecoration(
                    color: theme.cardBackground,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.07),
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
                        label: labels.personalInfo,
                        fontFamily: fontFamily,
                        titleColor: theme.titleColor,
                        secondaryText: theme.secondaryText,
                        onTap: onEditProfile,
                      ),
                      const Divider(height: 1, indent: 60, endIndent: 20),
                      _ProfileMenuTile(
                        icon: Icons.assignment_rounded,
                        iconColor: Colors.orangeAccent,
                        label: labels.healthProfile,
                        fontFamily: fontFamily,
                        titleColor: theme.titleColor,
                        secondaryText: theme.secondaryText,
                        onTap: onHealthProfile,
                      ),
                      const Divider(height: 1, indent: 60, endIndent: 20),
                      _ProfileMenuTile(
                        key: const ValueKey('profile-care-management'),
                        icon: Icons.group,
                        iconColor: Colors.green,
                        label: labels.careManagement,
                        fontFamily: fontFamily,
                        titleColor: theme.titleColor,
                        secondaryText: theme.secondaryText,
                        onTap: onCareManagement,
                      ),
                      const Divider(height: 1, indent: 60, endIndent: 20),
                      _ProfileMenuTile(
                        icon: Icons.settings,
                        iconColor: Colors.purple,
                        label: labels.appSettings,
                        fontFamily: fontFamily,
                        titleColor: theme.titleColor,
                        secondaryText: theme.secondaryText,
                        onTap: onAppSettings,
                      ),
                      const Divider(height: 1, indent: 60, endIndent: 20),
                      _ProfileMenuTile(
                        icon: Icons.card_giftcard,
                        iconColor: Colors.redAccent,
                        label: labels.referral,
                        subtitle: labels.referralSubtitle,
                        fontFamily: fontFamily,
                        titleColor: theme.titleColor,
                        secondaryText: theme.secondaryText,
                        onTap: onReferral,
                      ),
                      const Divider(height: 1, indent: 60, endIndent: 20),
                      _ProfileMenuTile(
                        icon: Icons.support_agent,
                        iconColor: Colors.indigo,
                        label: labels.support,
                        subtitle: labels.supportSubtitle,
                        fontFamily: fontFamily,
                        titleColor: theme.titleColor,
                        secondaryText: theme.secondaryText,
                        onTap: onSupport,
                      ),
                      for (final item in additionalMenuItems) ...[
                        const Divider(height: 1, indent: 60, endIndent: 20),
                        _ProfileMenuTile(
                          key: item.key,
                          icon: item.icon,
                          iconColor: item.iconColor,
                          label: item.label,
                          subtitle: item.subtitle,
                          fontFamily: fontFamily,
                          titleColor: theme.titleColor,
                          secondaryText: theme.secondaryText,
                          onTap: item.onTap,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                child: OutlinedButton.icon(
                  key: ValueKey('${appName.toLowerCase()}-data-export'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                    foregroundColor: theme.accent,
                    side: BorderSide(
                      color: theme.accent.withValues(alpha: 0.24),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  icon: const Icon(Icons.download_for_offline_outlined),
                  label: Text(
                    LifeMateRuntimeLocale.select(
                      fa: 'دریافت نسخه‌ای از داده‌های من',
                      en: 'Export my data',
                    ),
                    style: TextStyle(
                      fontFamily: fontFamily,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  onPressed: () => _exportPersonalData(context),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                child: OutlinedButton.icon(
                  key: ValueKey('${appName.toLowerCase()}-account-deletion'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                    foregroundColor: Colors.redAccent,
                    side: BorderSide(
                      color: Colors.redAccent.withValues(alpha: 0.28),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  icon: const Icon(Icons.delete_forever_outlined),
                  label: Text(
                    LifeMateRuntimeLocale.select(
                      fa: LifeMateRuntimeLocale.select(
                        fa: 'حذف حساب و داده‌های شخصی',
                        en: "Delete account and personal data",
                      ),
                      en: "Delete account and personal data",
                    ),
                    style: TextStyle(
                      fontFamily: fontFamily,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  onPressed: () => showLifeMateAccountDeletionDialog(
                    context,
                    apiClient: apiClient,
                    fontFamily: fontFamily,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: theme.cardBackground,
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.redAccent.withValues(alpha: 0.12),
                        blurRadius: 16,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: TextButton.icon(
                    key: ValueKey('${appName.toLowerCase()}-profile-sign-out'),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),
                    icon: const Icon(Icons.logout, color: Colors.redAccent),
                    label: Text(
                      labels.logout,
                      style: TextStyle(
                        fontFamily: fontFamily,
                        fontSize: 16,
                        color: Colors.redAccent,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    onPressed: () => _confirmSignOut(context),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  versionLabel,
                  style: TextStyle(
                    fontFamily: fontFamily,
                    fontSize: 12,
                    color: theme.secondaryText.withValues(alpha: 0.7),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _exportPersonalData(BuildContext context) async {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    try {
      final exported = await apiClient.exportAccountData();
      final encoded = const JsonEncoder.withIndent('  ').convert(exported);
      if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          title: Text(
            LifeMateRuntimeLocale.select(
              fa: 'خروجی داده‌ها آماده است',
              en: 'Your data export is ready',
            ),
            style: TextStyle(
              fontFamily: fontFamily,
              fontWeight: FontWeight.w900,
            ),
          ),
          content: Text(
            LifeMateRuntimeLocale.select(
              fa: 'این فایل متنی شامل اطلاعات شخصی و سلامت شماست. فقط در محل امن نگهش دارید. با انتخاب «کپی JSON»، کل خروجی در کلیپ‌بورد دستگاه قرار می‌گیرد.',
              en: 'This JSON contains your personal and health information. Keep it only in a safe place. Choosing Copy JSON places the complete export on this device clipboard.',
            ),
            style: TextStyle(fontFamily: fontFamily, height: 1.6),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(
                LifeMateRuntimeLocale.select(fa: 'بستن', en: 'Close'),
              ),
            ),
            FilledButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: encoded));
                if (dialogContext.mounted) Navigator.pop(dialogContext);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        LifeMateRuntimeLocale.select(
                          fa: 'خروجی JSON در کلیپ‌بورد کپی شد.',
                          en: 'The JSON export was copied to the clipboard.',
                        ),
                      ),
                    ),
                  );
                }
              },
              icon: const Icon(Icons.copy_all_outlined),
              label: Text(
                LifeMateRuntimeLocale.select(fa: 'کپی JSON', en: 'Copy JSON'),
              ),
            ),
          ],
        ),
      );
    } on LifeMateApiException catch (error) {
      if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } catch (_) {
      if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            LifeMateRuntimeLocale.select(
              fa: 'دریافت خروجی انجام نشد؛ اتصال را بررسی و دوباره تلاش کنید.',
              en: 'Data export failed. Check your connection and try again.',
            ),
          ),
        ),
      );
    }
  }

  Future<void> _confirmSignOut(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text(
          LifeMateRuntimeLocale.select(
            fa: LifeMateRuntimeLocale.select(
              fa: 'خروج از حساب؟',
              en: "Sign out?",
            ),
            en: "Sign out?",
          ),
          style: TextStyle(fontFamily: fontFamily, fontWeight: FontWeight.w900),
        ),
        content: Text(
          LifeMateRuntimeLocale.select(
            fa: LifeMateRuntimeLocale.select(
              fa: 'برای ورود دوباره باید اطلاعات ورود خود را وارد کنید.',
              en: "You must enter your login information to log in again.",
            ),
            en: "You must enter your login information to log in again.",
          ),
          style: TextStyle(fontFamily: fontFamily, height: 1.6),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(
              LifeMateRuntimeLocale.select(
                fa: LifeMateRuntimeLocale.select(fa: 'انصراف', en: "opt out"),
                en: "opt out",
              ),
            ),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(
              LifeMateRuntimeLocale.select(
                fa: LifeMateRuntimeLocale.select(
                  fa: 'خروج امن',
                  en: "safe exit",
                ),
                en: "safe exit",
              ),
            ),
          ),
        ],
      ),
    );
    if (confirmed == true) await LifeMateAuth.signOut();
  }
}

class _SubscriptionCard extends StatelessWidget {
  const _SubscriptionCard({
    required this.theme,
    required this.fontFamily,
    required this.title,
    required this.actionLabel,
    required this.onTap,
  });

  final LifeMateProfileThemeData theme;
  final String fontFamily;
  final String title;
  final String actionLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('lifemate-subscription-card'),
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 18),
      decoration: BoxDecoration(
        color: theme.cardBackground,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.07),
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
                  title,
                  style: TextStyle(
                    fontFamily: fontFamily,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: theme.titleColor,
                  ),
                ),
                const SizedBox(height: 8),
                ElevatedButton(
                  key: const ValueKey('manage-subscriptions-button'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: theme.accent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 8,
                    ),
                  ),
                  onPressed: onTap,
                  child: Text(
                    actionLabel,
                    style: TextStyle(
                      fontFamily: fontFamily,
                      fontSize: 14,
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
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
    );
  }
}

class _CurrentUserIdentity extends StatefulWidget {
  const _CurrentUserIdentity({
    required this.apiClient,
    required this.theme,
    required this.fontFamily,
    required this.isPersian,
    required this.fallbackUserName,
    required this.onEditProfile,
  });

  final LifeMateApiClient apiClient;
  final LifeMateProfileThemeData theme;
  final String fontFamily;
  final bool isPersian;
  final String fallbackUserName;
  final VoidCallback onEditProfile;

  @override
  State<_CurrentUserIdentity> createState() => _CurrentUserIdentityState();
}

class _CurrentUserIdentityState extends State<_CurrentUserIdentity> {
  late Future<Map<String, dynamic>> _currentUser;

  @override
  void initState() {
    super.initState();
    _currentUser = widget.apiClient.getCurrentUser();
    LifeMateProfileRefresh.revision.addListener(_reloadIdentity);
  }

  void _reloadIdentity() {
    if (!mounted) return;
    setState(() => _currentUser = widget.apiClient.getCurrentUser());
  }

  void _openEditor() {
    widget.onEditProfile();
  }

  @override
  void dispose() {
    LifeMateProfileRefresh.revision.removeListener(_reloadIdentity);
    super.dispose();
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
            ? widget.fallbackUserName
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
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  InkWell(
                    onTap: _openEditor,
                    customBorder: const CircleBorder(),
                    child: LifeMateProfileAvatar(
                      avatarKey: profile['avatarKey']?.toString(),
                      photoUrl: profile['profilePhotoUrl']?.toString(),
                      radius: 36,
                    ),
                  ),
                  PositionedDirectional(
                    bottom: 0,
                    end: 0,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.12),
                            blurRadius: 8,
                          ),
                        ],
                      ),
                      child: Icon(
                        Icons.camera_alt,
                        size: 16,
                        color: widget.theme.accent,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            if (snapshot.connectionState != ConnectionState.done)
              SizedBox.square(
                dimension: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: widget.theme.accent,
                ),
              )
            else ...[
              Text(
                name,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: widget.fontFamily,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: widget.theme.titleColor,
                ),
              ),
              if (contact.isNotEmpty)
                Text(
                  _localizeDigits(contact, widget.isPersian),
                  textAlign: TextAlign.center,
                  textDirection: TextDirection.ltr,
                  style: TextStyle(
                    fontFamily: widget.fontFamily,
                    fontSize: 14,
                    color: widget.theme.accent,
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
    super.key,
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.fontFamily,
    required this.titleColor,
    required this.secondaryText,
    required this.onTap,
    this.subtitle,
  });

  final IconData icon;
  final Color iconColor;
  final String label;
  final String fontFamily;
  final Color titleColor;
  final Color secondaryText;
  final VoidCallback onTap;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: iconColor.withValues(alpha: 0.15),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: iconColor.withValues(alpha: 0.25),
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
            fontFamily: fontFamily,
            fontSize: 16,
            color: titleColor,
          ),
        ),
        subtitle: subtitle == null
            ? null
            : Text(
                subtitle!,
                style: TextStyle(
                  fontFamily: fontFamily,
                  fontSize: 11,
                  color: secondaryText,
                ),
              ),
        trailing: const Icon(
          Icons.arrow_forward_ios_rounded,
          size: 14,
          color: Colors.grey,
        ),
        onTap: onTap,
      ),
    );
  }
}

String _localizeDigits(String value, bool persian) =>
    persian ? LifeMateNumbers.toPersian(value) : LifeMateNumbers.toLatin(value);
