part of '../cocoonmate_module.dart';

enum CocoonSettingsLoadState { loading, ready, error }

enum CocoonSettingsSyncState { synced, pending, unavailable }

class CocoonSettingsViewData {
  const CocoonSettingsViewData({
    required this.pregnancyLabel,
    required this.dueDateLabel,
    required this.datingSourceLabel,
    required this.remindersSummary,
    required this.sharingSummary,
    required this.languageLabel,
    required this.largeTextEnabled,
    required this.reducedMotionEnabled,
    required this.syncState,
    required this.syncSummary,
    required this.subscriptionSummary,
    required this.supportSummary,
    required this.privacyLegalSummary,
    required this.globalProfileLabel,
    this.cached = false,
    this.offline = false,
    this.cachedAtLabel,
  });

  /// Presentation-only pregnancy summary. Dating truth remains host-owned.
  final String pregnancyLabel;
  final String dueDateLabel;
  final String datingSourceLabel;
  final String remindersSummary;

  /// A host-computed summary only; it grants or revokes no access.
  final String sharingSummary;
  final String languageLabel;
  final bool largeTextEnabled;
  final bool reducedMotionEnabled;
  final CocoonSettingsSyncState syncState;
  final String syncSummary;
  final String subscriptionSummary;
  final String supportSummary;
  final String privacyLegalSummary;

  /// Label for the canonical LifeMate profile; no account truth is duplicated.
  final String globalProfileLabel;
  final bool cached;
  final bool offline;
  final String? cachedAtLabel;
}

class CocoonSettingsScreen extends StatelessWidget {
  const CocoonSettingsScreen({
    required this.fa,
    required this.state,
    required this.onRetry,
    required this.onOpenPregnancyDating,
    required this.onOpenReminders,
    required this.onOpenPrivacySharing,
    required this.onOpenLanguage,
    required this.onOpenAccessibility,
    required this.onReducedMotionChanged,
    required this.onOpenDataAndSync,
    required this.onOpenSubscription,
    required this.onOpenSupport,
    required this.onOpenPrivacyLegal,
    required this.onOpenGlobalProfile,
    this.data,
    super.key,
  });

  final bool fa;
  final CocoonSettingsLoadState state;
  final CocoonSettingsViewData? data;
  final VoidCallback onRetry;
  final VoidCallback? onOpenPregnancyDating;
  final VoidCallback? onOpenReminders;
  final VoidCallback? onOpenPrivacySharing;
  final VoidCallback? onOpenLanguage;
  final VoidCallback? onOpenAccessibility;
  final ValueChanged<bool>? onReducedMotionChanged;
  final VoidCallback? onOpenDataAndSync;
  final VoidCallback? onOpenSubscription;
  final VoidCallback? onOpenSupport;
  final VoidCallback? onOpenPrivacyLegal;
  final VoidCallback onOpenGlobalProfile;

  String t(String en, String faText) => fa ? faText : en;

  @override
  Widget build(BuildContext context) {
    if (state == CocoonSettingsLoadState.loading) {
      return _CocoonSettingsLoading(fa: fa);
    }
    if (data == null) {
      return CocoonStatePage(
        icon: Icons.tune_rounded,
        eyebrow: t('Cocoon settings', 'تنظیمات کوکون'),
        title: t('Settings could not be refreshed', 'تنظیمات به‌روز نشد'),
        body: t(
          'No preference was changed. Try again when your connection is stable.',
          'هیچ ترجیحی تغییر نکرد؛ با اتصال پایدار دوباره تلاش کن.',
        ),
        action: t('Try again', 'تلاش دوباره'),
        onPressed: onRetry,
      );
    }

    return CustomScrollView(
      key: const PageStorageKey('cocoon-settings'),
      slivers: [
        SliverToBoxAdapter(
          child: CocoonPagePadding(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _SettingsHero(fa: fa, data: data!),
                if (data!.offline || data!.cached) ...[
                  const SizedBox(height: 14),
                  _SettingsFreshnessNotice(
                    fa: fa,
                    offline: data!.offline,
                    cachedAtLabel: data!.cachedAtLabel,
                    onRetry: onRetry,
                  ),
                ],
                if (state == CocoonSettingsLoadState.error) ...[
                  const SizedBox(height: 14),
                  _SettingsRefreshNotice(fa: fa, onRetry: onRetry),
                ],
                const SizedBox(height: 34),
                _SettingsSection(
                  title: t('Pregnancy', 'بارداری'),
                  supporting: t(
                    'Dating is shown from the protected pregnancy record.',
                    'تاریخ‌گذاری از پروندهٔ محافظت‌شدهٔ بارداری نمایش داده می‌شود.',
                  ),
                  children: [
                    _SettingsRow(
                      fa: fa,
                      icon: Icons.event_available_outlined,
                      title: t('Dating source', 'مبنای تاریخ‌گذاری'),
                      value: data!.datingSourceLabel,
                      onTap: onOpenPregnancyDating,
                    ),
                    _SettingsRow(
                      fa: fa,
                      icon: Icons.notifications_none_rounded,
                      title: t('Reminders', 'یادآورها'),
                      value: data!.remindersSummary,
                      onTap: onOpenReminders,
                      isLast: true,
                    ),
                  ],
                ),
                const SizedBox(height: 30),
                _SettingsSection(
                  title: t('Privacy & sharing', 'حریم خصوصی و اشتراک‌گذاری'),
                  supporting: t(
                    'Relationship and access are separate. Review exactly what is shared.',
                    'رابطه و دسترسی جدا هستند؛ دقیقاً ببین چه چیزهایی به اشتراک گذاشته شده‌اند.',
                  ),
                  children: [
                    _SettingsRow(
                      fa: fa,
                      icon: Icons.shield_outlined,
                      title: t('Sharing access', 'دسترسی‌های اشتراک‌گذاری'),
                      value: data!.sharingSummary,
                      onTap: onOpenPrivacySharing,
                      isLast: true,
                    ),
                  ],
                ),
                const SizedBox(height: 30),
                _SettingsSection(
                  title: t('Experience', 'تجربهٔ استفاده'),
                  children: [
                    _SettingsRow(
                      fa: fa,
                      icon: Icons.language_rounded,
                      title: t('Language', 'زبان'),
                      value: data!.languageLabel,
                      onTap: onOpenLanguage,
                    ),
                    _SettingsRow(
                      fa: fa,
                      icon: Icons.text_fields_rounded,
                      title: t('Text & accessibility', 'متن و دسترس‌پذیری'),
                      value: data!.largeTextEnabled
                          ? t('Larger text is on', 'متن درشت فعال است')
                          : t('System text size', 'اندازهٔ متن دستگاه'),
                      onTap: onOpenAccessibility,
                    ),
                    _SettingsSwitchRow(
                      title: t('Reduce motion', 'کاهش حرکت'),
                      supporting: t(
                        'Uses calmer transitions and progress effects.',
                        'گذارها و حرکت‌های پیشرفت آرام‌تر می‌شوند.',
                      ),
                      value: data!.reducedMotionEnabled,
                      onChanged: onReducedMotionChanged,
                    ),
                  ],
                ),
                const SizedBox(height: 30),
                _SettingsSection(
                  title: t('Data on this device', 'داده‌های این دستگاه'),
                  supporting: t(
                    'Saved copies are never presented as live server data.',
                    'نسخه‌های ذخیره‌شده هیچ‌وقت به‌جای دادهٔ زندهٔ سرور نمایش داده نمی‌شوند.',
                  ),
                  children: [
                    _SettingsRow(
                      fa: fa,
                      icon: _syncIcon(data!.syncState),
                      iconColor: _syncColor(data!.syncState),
                      title: t('Offline & sync', 'آفلاین و همگام‌سازی'),
                      value: data!.syncSummary,
                      onTap: onOpenDataAndSync,
                      isLast: true,
                    ),
                  ],
                ),
                const SizedBox(height: 30),
                _SettingsSection(
                  title: t('Membership & support', 'عضویت و پشتیبانی'),
                  supporting: t(
                    'Account and purchase details remain in shared LifeMate services.',
                    'اطلاعات حساب و خرید در سرویس‌های مشترک LifeMate مدیریت می‌شود.',
                  ),
                  children: [
                    _SettingsRow(
                      fa: fa,
                      icon: Icons.workspace_premium_outlined,
                      title: t('Cocoon membership', 'عضویت کوکون'),
                      value: data!.subscriptionSummary,
                      onTap: onOpenSubscription,
                    ),
                    _SettingsRow(
                      fa: fa,
                      icon: Icons.support_agent_outlined,
                      title: t('Help & report a problem', 'راهنما و گزارش مشکل'),
                      value: data!.supportSummary,
                      onTap: onOpenSupport,
                    ),
                    _SettingsRow(
                      fa: fa,
                      icon: Icons.policy_outlined,
                      title: t('Privacy & legal', 'حریم خصوصی و قوانین'),
                      value: data!.privacyLegalSummary,
                      onTap: onOpenPrivacyLegal,
                      isLast: true,
                    ),
                  ],
                ),
                const SizedBox(height: 36),
                _GlobalProfileLink(
                  fa: fa,
                  label: data!.globalProfileLabel,
                  onOpen: onOpenGlobalProfile,
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ),
      ],
    );
  }

  IconData _syncIcon(CocoonSettingsSyncState syncState) => switch (syncState) {
        CocoonSettingsSyncState.synced => Icons.cloud_done_outlined,
        CocoonSettingsSyncState.pending => Icons.cloud_upload_outlined,
        CocoonSettingsSyncState.unavailable => Icons.cloud_off_outlined,
      };

  Color _syncColor(CocoonSettingsSyncState syncState) => switch (syncState) {
        CocoonSettingsSyncState.synced => CocoonTheme.sageStrong,
        CocoonSettingsSyncState.pending => CocoonTheme.gold,
        CocoonSettingsSyncState.unavailable => CocoonTheme.muted,
      };
}

class _SettingsHero extends StatelessWidget {
  const _SettingsHero({required this.fa, required this.data});

  final bool fa;
  final CocoonSettingsViewData data;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsetsDirectional.fromSTEB(24, 24, 22, 22),
        decoration: BoxDecoration(
          color: CocoonTheme.lilac,
          borderRadius: BorderRadius.circular(30),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    fa ? 'تنظیمات همراه تو' : 'Your companion settings',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: CocoonTheme.coral,
                        ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    data.pregnancyLabel,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    data.dueDateLabel,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: CocoonTheme.muted,
                        ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            const CircleAvatar(
              radius: 27,
              backgroundColor: Colors.white,
              child: Icon(Icons.spa_outlined, color: CocoonTheme.coral),
            ),
          ],
        ),
      );
}

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({
    required this.title,
    required this.children,
    this.supporting,
  });

  final String title;
  final String? supporting;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CocoonSectionHeading(title: title, supporting: supporting),
          const SizedBox(height: 12),
          ...children,
        ],
      );
}

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    required this.fa,
    required this.icon,
    required this.title,
    required this.value,
    required this.onTap,
    this.iconColor = CocoonTheme.ink,
    this.isLast = false,
  });

  final bool fa;
  final IconData icon;
  final Color iconColor;
  final String title;
  final String value;
  final VoidCallback? onTap;
  final bool isLast;

  @override
  Widget build(BuildContext context) => Semantics(
        button: onTap != null,
        enabled: onTap != null,
        label: '$title، $value',
        child: Column(
          children: [
            InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(16),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 68),
                child: Padding(
                  padding: const EdgeInsetsDirectional.symmetric(
                    horizontal: 4,
                    vertical: 10,
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: const BoxDecoration(
                          color: CocoonTheme.warm,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(icon, size: 21, color: iconColor),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              value,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(color: CocoonTheme.muted),
                            ),
                          ],
                        ),
                      ),
                      if (onTap != null) ...[
                        const SizedBox(width: 8),
                        ExcludeSemantics(
                          child: Icon(
                            fa
                                ? Icons.chevron_left_rounded
                                : Icons.chevron_right_rounded,
                            color: CocoonTheme.muted,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            if (!isLast)
              const Padding(
                padding: EdgeInsetsDirectional.only(start: 60),
                child: Divider(height: 1),
              ),
          ],
        ),
      );
}

class _SettingsSwitchRow extends StatelessWidget {
  const _SettingsSwitchRow({
    required this.title,
    required this.supporting,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String supporting;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) => Semantics(
        toggled: value,
        enabled: onChanged != null,
        label: '$title، $supporting',
        onTap: onChanged == null ? null : () => onChanged!(!value),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 72),
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(4, 10, 0, 10),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: const BoxDecoration(
                    color: CocoonTheme.warm,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.motion_photos_off_outlined,
                    size: 21,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 2),
                      Text(
                        supporting,
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(color: CocoonTheme.muted),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                ExcludeSemantics(
                  child: Switch(value: value, onChanged: onChanged),
                ),
              ],
            ),
          ),
        ),
      );
}

class _SettingsFreshnessNotice extends StatelessWidget {
  const _SettingsFreshnessNotice({
    required this.fa,
    required this.offline,
    required this.cachedAtLabel,
    required this.onRetry,
  });

  final bool fa;
  final bool offline;
  final String? cachedAtLabel;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final base = offline
        ? (fa
            ? 'اطلاعات ذخیره‌شده روی این دستگاه'
            : 'Information saved on this device')
        : (fa ? 'نسخهٔ ذخیره‌شده' : 'Saved copy');
    final message = cachedAtLabel == null ? base : '$base · $cachedAtLabel';
    return Semantics(
      liveRegion: true,
      label: message,
      child: Container(
        padding: const EdgeInsetsDirectional.fromSTEB(14, 10, 8, 10),
        decoration: BoxDecoration(
          color: CocoonTheme.sky,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.cloud_done_outlined,
              size: 20,
              color: CocoonTheme.skyStrong,
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                message,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: CocoonTheme.skyStrong,
                    ),
              ),
            ),
            TextButton(
              onPressed: onRetry,
              child: Text(fa ? 'به‌روزرسانی' : 'Refresh'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsRefreshNotice extends StatelessWidget {
  const _SettingsRefreshNotice({required this.fa, required this.onRetry});

  final bool fa;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Semantics(
        liveRegion: true,
        child: Container(
          padding: const EdgeInsetsDirectional.fromSTEB(14, 10, 8, 10),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF0DD),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              const Icon(Icons.sync_problem_rounded, color: CocoonTheme.gold),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  fa
                      ? 'به‌روزرسانی انجام نشد؛ همین اطلاعات حفظ شده است.'
                      : 'Refresh failed; these settings were kept.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              TextButton(
                onPressed: onRetry,
                child: Text(fa ? 'تلاش' : 'Retry'),
              ),
            ],
          ),
        ),
      );
}

class _GlobalProfileLink extends StatelessWidget {
  const _GlobalProfileLink({
    required this.fa,
    required this.label,
    required this.onOpen,
  });

  final bool fa;
  final String label;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsetsDirectional.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: CocoonTheme.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              fa ? 'حساب LifeMate' : 'LifeMate account',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 5),
            Text(
              label,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: CocoonTheme.muted),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: onOpen,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(48, 48),
              ),
              icon: const Icon(Icons.open_in_new_rounded),
              label: Text(
                fa ? 'مدیریت در پروفایل اصلی' : 'Manage in global profile',
              ),
            ),
          ],
        ),
      );
}

class _CocoonSettingsLoading extends StatelessWidget {
  const _CocoonSettingsLoading({required this.fa});

  final bool fa;

  @override
  Widget build(BuildContext context) => Semantics(
        liveRegion: true,
        label: fa ? 'در حال بارگذاری تنظیمات' : 'Loading settings',
        child: SingleChildScrollView(
          padding: const EdgeInsetsDirectional.fromSTEB(20, 8, 20, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                height: 150,
                decoration: BoxDecoration(
                  color: CocoonTheme.lilac,
                  borderRadius: BorderRadius.circular(30),
                ),
              ),
              const SizedBox(height: 34),
              for (var section = 0; section < 3; section++) ...[
                Container(
                  width: 132,
                  height: 22,
                  alignment: AlignmentDirectional.centerStart,
                  child: const LinearProgressIndicator(
                    minHeight: 6,
                    color: CocoonTheme.coralSoft,
                    backgroundColor: CocoonTheme.warm,
                  ),
                ),
                const SizedBox(height: 14),
                for (var row = 0; row < 2; row++) ...[
                  const _SettingsLoadingRow(),
                  if (row == 0) const Divider(height: 1, indent: 60),
                ],
                const SizedBox(height: 28),
              ],
            ],
          ),
        ),
      );
}

class _SettingsLoadingRow extends StatelessWidget {
  const _SettingsLoadingRow();

  @override
  Widget build(BuildContext context) => const SizedBox(
        height: 68,
        child: Row(
          children: [
            CircleAvatar(radius: 21, backgroundColor: CocoonTheme.warm),
            SizedBox(width: 14),
            Expanded(
              child: LinearProgressIndicator(
                minHeight: 7,
                color: CocoonTheme.coralSoft,
                backgroundColor: CocoonTheme.warm,
              ),
            ),
          ],
        ),
      );
}
