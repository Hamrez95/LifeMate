import 'package:flutter/material.dart';
import 'package:lifemate_client/lifemate_client.dart';
import 'package:lifemate_ui/lifemate_ui.dart';

const _profileBackground = Color(0xFFF4F8F5);
const _profileAccent = Color(0xFF2F8F73);
const _profileInk = Color(0xFF263238);
const _profileSecondary = Color(0xFF68737D);

class ProfileYouScreen extends StatelessWidget {
  const ProfileYouScreen({
    super.key,
    required this.apiClient,
    required this.isPersian,
    required this.onLocaleChanged,
    required this.onBack,
    required this.onNotifications,
    required this.onOpenWellMate,
    required this.onOpenCareMate,
    this.productSections = const <Widget>[],
  });

  final LifeMateApiClient apiClient;
  final bool isPersian;
  final ValueChanged<Locale> onLocaleChanged;
  final VoidCallback onBack;
  final VoidCallback onNotifications;
  final VoidCallback onOpenWellMate;
  final VoidCallback onOpenCareMate;
  final List<Widget> productSections;

  String t(String en, String fa) => isPersian ? fa : en;

  @override
  Widget build(BuildContext context) {
    const theme = LifeMateProfileThemeData(
      background: _profileBackground,
      accent: _profileAccent,
      titleColor: _profileInk,
      secondaryText: _profileSecondary,
      cardBackground: Colors.white,
    );
    // Product fonts are bundled by the embedded WellMate package. Dependency
    // fonts use Flutter's package-qualified family names in the host app.
    final fontFamily = isPersian
        ? 'packages/wellmate/Vazir'
        : 'packages/wellmate/Poppins';

    return LifeMateSharedProfileScreen(
      apiClient: apiClient,
      theme: theme,
      labels: LifeMateProfileLabels(
        personalInfo: t('Personal information', 'اطلاعات شخصی'),
        healthProfile: t('Health profile', 'پرونده سلامت'),
        careManagement: t('Care management', 'مدیریت مراقبت'),
        appSettings: t('App settings', 'تنظیمات برنامه'),
        referral: t('Referral code', 'کد معرف'),
        support: t('Support', 'پشتیبانی'),
        logout: t('Sign out', 'خروج از حساب'),
        subscriptionTitle: t('Membership', 'عضویت'),
        manageSubscriptions: t('Manage membership', 'مدیریت عضویت'),
        referralSubtitle: t('Coming soon', 'به‌زودی'),
        supportSubtitle: t(
          'Chat with LifeMate support',
          'گفت‌وگو با پشتیبانی LifeMate',
        ),
      ),
      fontFamily: fontFamily,
      appName: 'LifeMate',
      versionLabel: 'LifeMate 0.1.0+1',
      fallbackUserName: t('LifeMate user', 'کاربر LifeMate'),
      isPersian: isPersian,
      onBack: onBack,
      onNotifications: onNotifications,
      onEditProfile: () => _openEditor(context, theme, fontFamily),
      onHealthProfile: onOpenWellMate,
      onCareManagement: onOpenCareMate,
      onAppSettings: () => _showLanguageDialog(context, fontFamily),
      onReferral: () => _showNotice(
        context,
        t('Referral', 'معرفی دوستان'),
        t(
          'Referral tools are coming soon.',
          'امکانات معرفی دوستان به‌زودی آماده می‌شود.',
        ),
      ),
      onSupport: () => Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => LifeMateSupportChatScreen(
            productCode: 'lifemate',
            accent: _profileAccent,
            background: _profileBackground,
            isPersian: isPersian,
            fontFamily: fontFamily,
          ),
        ),
      ),
      onManageSubscriptions: () => _showMembership(context),
      feedbackBuilder: (_) => LifeMateFeedbackScreen(
        productCode: 'lifemate',
        appVersion: '0.1.0+1',
        accent: _profileAccent,
        background: _profileBackground,
        isPersian: isPersian,
        fontFamily: fontFamily,
      ),
      additionalActions: [
        LifeMateProfileAdditionalAction(
          key: const ValueKey('lifemate-profile-time-zone'),
          icon: Icons.schedule_rounded,
          iconColor: Colors.teal,
          label: t('Time zone and language', 'زبان و منطقه زمانی'),
          subtitle: t(
            'Edit your shared profile preferences',
            'ویرایش ترجیح‌های پروفایل مشترک',
          ),
          onTap: () => _openEditor(context, theme, fontFamily),
        ),
        LifeMateProfileAdditionalAction(
          key: const ValueKey('lifemate-profile-accessibility'),
          icon: Icons.accessibility_new_rounded,
          iconColor: Colors.deepPurple,
          label: t('Accessibility', 'دسترسی‌پذیری'),
          subtitle: MediaQuery.disableAnimationsOf(context)
              ? t('Reduced motion is active', 'کاهش حرکت فعال است')
              : t('Follows system preferences', 'پیرو تنظیمات سیستم'),
          onTap: () => _showAccessibility(context),
        ),
      ],
      additionalSections: productSections,
    );
  }

  void _openEditor(
    BuildContext context,
    LifeMateProfileThemeData theme,
    String fontFamily,
  ) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => _LifeMateProfileEditor(
          apiClient: apiClient,
          theme: theme,
          fontFamily: fontFamily,
          onLocaleChanged: onLocaleChanged,
        ),
      ),
    );
  }

  Future<void> _showLanguageDialog(
    BuildContext context,
    String fontFamily,
  ) async {
    final selected = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          t('Language', 'زبان'),
          style: TextStyle(fontFamily: fontFamily),
        ),
        content: RadioGroup<String>(
          groupValue: isPersian ? 'fa' : 'en',
          onChanged: (value) => Navigator.of(dialogContext).pop(value),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: const [
              RadioListTile<String>(value: 'fa', title: Text('فارسی')),
              RadioListTile<String>(value: 'en', title: Text('English')),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(t('Cancel', 'انصراف')),
          ),
        ],
      ),
    );
    if (selected != null) onLocaleChanged(Locale(selected));
  }

  void _showMembership(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: FutureBuilder<Map<String, dynamic>>(
          future: apiClient.getSubscriptionSnapshot(),
          builder: (context, state) => Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(24, 12, 24, 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  t('Membership', 'عضویت'),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                if (state.connectionState != ConnectionState.done)
                  const Center(child: CircularProgressIndicator())
                else if (state.hasError)
                  Text(
                    t(
                      'Membership could not be loaded.',
                      'وضعیت عضویت دریافت نشد.',
                    ),
                  )
                else
                  Text(_membershipSummary(state.data ?? const {})),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => Navigator.of(sheetContext).pop(),
                  child: Text(t('Close', 'بستن')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _membershipSummary(Map<String, dynamic> value) {
    for (final key in const [
      'status',
      'subscriptionStatus',
      'state',
      'planStatus',
    ]) {
      final status = value[key]?.toString().trim();
      if (status != null && status.isNotEmpty) return status;
    }
    for (final key in const ['planName', 'plan', 'offerName', 'productName']) {
      final plan = value[key]?.toString().trim();
      if (plan != null && plan.isNotEmpty) return plan;
    }
    return t('No active membership is available.', 'عضویت فعالی ثبت نشده است.');
  }

  void _showAccessibility(BuildContext context) {
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    _showNotice(
      context,
      t('Accessibility', 'دسترسی‌پذیری'),
      reducedMotion
          ? t(
              'The system requests reduced motion. LifeMate respects that setting.',
              'سیستم کاهش حرکت را فعال کرده است و LifeMate از این تنظیم پیروی می‌کند.',
            )
          : t(
              'LifeMate follows your system motion preference.',
              'LifeMate از ترجیح حرکت در تنظیمات سیستم پیروی می‌کند.',
            ),
    );
  }

  void _showNotice(BuildContext context, String title, String message) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(24, 12, 24, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(message),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => Navigator.of(sheetContext).pop(),
                child: Text(t('Close', 'بستن')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LifeMateProfileEditor extends StatelessWidget {
  const _LifeMateProfileEditor({
    required this.apiClient,
    required this.theme,
    required this.fontFamily,
    required this.onLocaleChanged,
  });

  final LifeMateApiClient apiClient;
  final LifeMateProfileThemeData theme;
  final String fontFamily;
  final ValueChanged<Locale> onLocaleChanged;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: theme.background,
    child: Column(
      children: [
        SafeArea(
          bottom: false,
          minimum: const EdgeInsets.fromLTRB(20, 10, 20, 6),
          child: Align(
            alignment: AlignmentDirectional.centerEnd,
            child: OutlinedButton.icon(
              key: const ValueKey('lifemate-account-security'),
              icon: const Icon(Icons.shield_outlined, size: 19),
              label: Text(
                LifeMateRuntimeLocale.select(
                  fa: 'امنیت حساب',
                  en: 'Account security',
                ),
              ),
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => LifeMateAccountSecurityScreen(
                    controller: lifeMateAccountSecurityControllerForApp(
                      'LifeMate',
                    ),
                    accent: _profileAccent,
                    background: _profileBackground,
                    ink: _profileInk,
                  ),
                ),
              ),
            ),
          ),
        ),
        Expanded(
          child: LifeMateSharedEditableProfileScreen(
            apiClient: apiClient,
            theme: theme,
            fontFamily: fontFamily,
            keyPrefix: 'lifemate-profile',
            onLocaleChanged: onLocaleChanged,
          ),
        ),
      ],
    ),
  );
}
