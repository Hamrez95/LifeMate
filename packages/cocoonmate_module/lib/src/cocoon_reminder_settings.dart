part of '../cocoonmate_module.dart';

enum CocoonReminderLoadState { loading, ready, error }

enum CocoonReminderPermissionState {
  rationale,
  granted,
  denied,
  blocked,
  unavailable,
}

enum CocoonReminderSaveState { idle, saving, queued, confirmed, error }

enum CocoonLockScreenPrivacy { private, descriptive }

@immutable
class CocoonReminderPreferences {
  const CocoonReminderPreferences({
    required this.weeklyUpdate,
    required this.dailyCheckIn,
    required this.lockScreenPrivacy,
  });

  final bool weeklyUpdate;
  final bool dailyCheckIn;
  final CocoonLockScreenPrivacy lockScreenPrivacy;

  CocoonReminderPreferences copyWith({
    bool? weeklyUpdate,
    bool? dailyCheckIn,
    CocoonLockScreenPrivacy? lockScreenPrivacy,
  }) =>
      CocoonReminderPreferences(
        weeklyUpdate: weeklyUpdate ?? this.weeklyUpdate,
        dailyCheckIn: dailyCheckIn ?? this.dailyCheckIn,
        lockScreenPrivacy: lockScreenPrivacy ?? this.lockScreenPrivacy,
      );
}

@immutable
class CocoonReminderSettingsViewData {
  const CocoonReminderSettingsViewData({
    required this.preferences,
    required this.permission,
    required this.appointmentSummary,
    required this.medicationSummary,
    this.cached = false,
    this.savedAtLabel,
  });

  final CocoonReminderPreferences preferences;
  final CocoonReminderPermissionState permission;
  final String appointmentSummary;
  final String medicationSummary;
  final bool cached;
  final String? savedAtLabel;
}

class CocoonReminderSettingsScreen extends StatefulWidget {
  const CocoonReminderSettingsScreen({
    required this.fa,
    required this.loadState,
    required this.saveState,
    required this.onRetry,
    required this.onSave,
    required this.onOpenAppointments,
    required this.onOpenMedications,
    this.data,
    this.onRequestPermission,
    this.onOpenSystemSettings,
    super.key,
  });

  final bool fa;
  final CocoonReminderLoadState loadState;
  final CocoonReminderSaveState saveState;
  final CocoonReminderSettingsViewData? data;
  final VoidCallback onRetry;
  final Future<void> Function(CocoonReminderPreferences preferences) onSave;
  final VoidCallback onOpenAppointments;
  final VoidCallback onOpenMedications;
  final VoidCallback? onRequestPermission;
  final VoidCallback? onOpenSystemSettings;

  @override
  State<CocoonReminderSettingsScreen> createState() =>
      _CocoonReminderSettingsScreenState();
}

class _CocoonReminderSettingsScreenState
    extends State<CocoonReminderSettingsScreen> {
  CocoonReminderPreferences? _draft;

  bool get _busy => widget.saveState == CocoonReminderSaveState.saving;
  String t(String en, String fa) => widget.fa ? fa : en;

  @override
  void initState() {
    super.initState();
    _draft = widget.data?.preferences;
  }

  @override
  void didUpdateWidget(CocoonReminderSettingsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.data?.preferences != widget.data?.preferences && !_busy) {
      _draft = widget.data?.preferences;
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
            title: Text(t('Reminders & privacy', 'یادآورها و حریم خصوصی'))),
        body: SafeArea(
          bottom: false,
          child: switch (widget.loadState) {
            CocoonReminderLoadState.loading => _ReminderLoading(fa: widget.fa),
            CocoonReminderLoadState.error => CocoonStatePage(
                icon: Icons.notifications_off_outlined,
                eyebrow: t('Reminders', 'یادآورها'),
                title: t(
                  'Could not load reminder settings',
                  'تنظیمات یادآورها بارگذاری نشد',
                ),
                body: t(
                  'Your existing reminders have not been changed.',
                  'یادآورهای فعلی تو تغییری نکرده‌اند.',
                ),
                action: t('Try again', 'تلاش دوباره'),
                onPressed: widget.onRetry,
              ),
            CocoonReminderLoadState.ready when widget.data != null =>
              _ready(widget.data!),
            _ => CocoonStatePage(
                icon: Icons.notifications_none_rounded,
                eyebrow: t('Reminders', 'یادآورها'),
                title: t('Settings unavailable', 'تنظیمات در دسترس نیست'),
                body: t(
                  'Try again when your connection is stable.',
                  'وقتی اتصال پایدار شد دوباره تلاش کن.',
                ),
                action: t('Refresh', 'به‌روزرسانی'),
                onPressed: widget.onRetry,
              ),
          },
        ),
        bottomNavigationBar:
            widget.loadState == CocoonReminderLoadState.ready &&
                    widget.data != null
                ? _bottomAction
                : null,
      );

  Widget _ready(CocoonReminderSettingsViewData data) {
    final preferences = _draft ?? data.preferences;
    return CustomScrollView(
      key: const PageStorageKey('cocoon-reminder-settings'),
      slivers: [
        SliverToBoxAdapter(
          child: CocoonPagePadding(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _ReminderHero(fa: widget.fa),
                if (data.cached) ...[
                  const SizedBox(height: 12),
                  _ReminderCachedStatus(
                    fa: widget.fa,
                    savedAtLabel: data.savedAtLabel,
                  ),
                ],
                if (widget.saveState != CocoonReminderSaveState.idle) ...[
                  const SizedBox(height: 12),
                  _ReminderSaveStatus(
                    fa: widget.fa,
                    state: widget.saveState,
                  ),
                ],
                const SizedBox(height: 24),
                _PermissionPanel(
                  fa: widget.fa,
                  state: data.permission,
                  onRequestPermission: widget.onRequestPermission,
                  onOpenSystemSettings: widget.onOpenSystemSettings,
                ),
                const SizedBox(height: 30),
                CocoonSectionHeading(
                  title: t('Gentle routine', 'همراهی روزمره'),
                  supporting: t(
                    'Choose only the updates that feel useful.',
                    'فقط یادآورهایی را روشن کن که واقعاً به کارت می‌آیند.',
                  ),
                ),
                const SizedBox(height: 12),
                _ReminderToggle(
                  icon: Icons.auto_awesome_outlined,
                  title: t('Weekly pregnancy update', 'مرور هفتگی بارداری'),
                  supporting: t(
                    'A short update when a new pregnancy week begins',
                    'یک مرور کوتاه با شروع هفته جدید بارداری',
                  ),
                  value: preferences.weeklyUpdate,
                  enabled: !_busy,
                  onChanged: (value) => _update(
                    preferences.copyWith(weeklyUpdate: value),
                  ),
                ),
                const Divider(height: 1, indent: 58),
                _ReminderToggle(
                  icon: Icons.favorite_outline_rounded,
                  title: t('Daily check-in', 'حال‌سنجی روزانه'),
                  supporting: t(
                    'A quiet invitation to record how you feel',
                    'یک دعوت آرام برای ثبت حال امروز',
                  ),
                  value: preferences.dailyCheckIn,
                  enabled: !_busy,
                  onChanged: (value) => _update(
                    preferences.copyWith(dailyCheckIn: value),
                  ),
                ),
                const SizedBox(height: 30),
                CocoonSectionHeading(
                  title: t('Care reminders', 'یادآورهای مراقبتی'),
                  supporting: t(
                    'Times stay with their original appointment or medication record.',
                    'زمان هر یادآور در همان قرار یا داروی اصلی مدیریت می‌شود.',
                  ),
                ),
                const SizedBox(height: 12),
                _CanonicalReminderLink(
                  fa: widget.fa,
                  icon: Icons.calendar_month_outlined,
                  title: t('Appointments', 'قرارها و ویزیت‌ها'),
                  summary: data.appointmentSummary,
                  onTap: widget.onOpenAppointments,
                ),
                const SizedBox(height: 10),
                _CanonicalReminderLink(
                  fa: widget.fa,
                  icon: Icons.medication_outlined,
                  title: t('Medications', 'داروها'),
                  summary: data.medicationSummary,
                  onTap: widget.onOpenMedications,
                ),
                const SizedBox(height: 30),
                CocoonSectionHeading(
                  title: t('Lock screen privacy', 'حریم خصوصی صفحه قفل'),
                  supporting: t(
                    'See exactly how a reminder can appear before saving.',
                    'قبل از ذخیره ببین یادآور چطور نمایش داده می‌شود.',
                  ),
                ),
                const SizedBox(height: 12),
                _PrivacyChoice(
                  fa: widget.fa,
                  value: preferences.lockScreenPrivacy,
                  enabled: !_busy,
                  onChanged: (value) =>
                      _update(preferences.copyWith(lockScreenPrivacy: value)),
                ),
                const SizedBox(height: 14),
                _NotificationPreview(
                  fa: widget.fa,
                  privacy: preferences.lockScreenPrivacy,
                ),
                const SizedBox(height: 22),
                _PartnerPrivacyNote(fa: widget.fa),
                const SizedBox(height: 28),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget get _bottomAction {
    final draft = _draft ?? widget.data!.preferences;
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsetsDirectional.fromSTEB(20, 11, 20, 14),
        decoration: const BoxDecoration(
          color: Color(0xFFFFFDFC),
          border: Border(top: BorderSide(color: CocoonTheme.line)),
        ),
        child: FilledButton.icon(
          onPressed: _busy ? null : () => widget.onSave(draft),
          icon: _busy
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.check_rounded),
          label: Text(
            _busy ? t('Saving…', 'در حال ذخیره…') : t('Save', 'ذخیره تنظیمات'),
          ),
        ),
      ),
    );
  }

  void _update(CocoonReminderPreferences preferences) =>
      setState(() => _draft = preferences);
}

class _ReminderHero extends StatelessWidget {
  const _ReminderHero({required this.fa});
  final bool fa;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsetsDirectional.all(22),
        decoration: BoxDecoration(
          color: CocoonTheme.lilac,
          borderRadius: BorderRadius.circular(28),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const CircleAvatar(
              radius: 27,
              backgroundColor: Colors.white,
              child: Icon(
                Icons.notifications_active_outlined,
                color: CocoonTheme.coral,
                size: 28,
              ),
            ),
            const SizedBox(width: 15),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    fa
                        ? 'به‌موقع، آرام و تحت کنترل تو'
                        : 'Timely, gentle, in your control',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 5),
                  Text(
                    fa
                        ? 'یادآورها کمک می‌کنند چیزی از قلم نیفتد؛ هر زمان بخواهی می‌توانی تغییرشان بدهی.'
                        : 'Reminders help you stay oriented, and you can change them at any time.',
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(color: CocoonTheme.muted),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
}

class _PermissionPanel extends StatelessWidget {
  const _PermissionPanel({
    required this.fa,
    required this.state,
    required this.onRequestPermission,
    required this.onOpenSystemSettings,
  });

  final bool fa;
  final CocoonReminderPermissionState state;
  final VoidCallback? onRequestPermission;
  final VoidCallback? onOpenSystemSettings;

  @override
  Widget build(BuildContext context) {
    final (icon, color, background, title, body, action, callback) =
        switch (state) {
      CocoonReminderPermissionState.rationale => (
          Icons.notifications_none_rounded,
          CocoonTheme.skyStrong,
          CocoonTheme.sky,
          fa ? 'اجازه اعلان‌ها خاموش است' : 'Notifications are off',
          fa
              ? 'برای دریافت یادآورها، اجازه اعلان CocoonMate را روشن کن.'
              : 'Allow CocoonMate notifications to receive reminders.',
          fa ? 'فعال‌کردن اعلان‌ها' : 'Allow notifications',
          onRequestPermission,
        ),
      CocoonReminderPermissionState.granted => (
          Icons.check_circle_outline_rounded,
          CocoonTheme.sageStrong,
          CocoonTheme.sage,
          fa ? 'اعلان‌ها آماده‌اند' : 'Notifications are ready',
          fa
              ? 'یادآورهای روشن می‌توانند در زمان تنظیم‌شده نمایش داده شوند.'
              : 'Enabled reminders can appear at their scheduled time.',
          null,
          null,
        ),
      CocoonReminderPermissionState.denied => (
          Icons.notifications_off_outlined,
          CocoonTheme.gold,
          const Color(0xFFFFF2D9),
          fa ? 'اعلان‌ها اجازه ندارند' : 'Notifications are not allowed',
          fa
              ? 'می‌توانی دوباره اجازه بدهی؛ تنظیماتت همین‌جا حفظ می‌شود.'
              : 'You can allow them again; your choices remain here.',
          fa ? 'دوباره تلاش کن' : 'Try again',
          onRequestPermission,
        ),
      CocoonReminderPermissionState.blocked => (
          Icons.settings_outlined,
          CocoonTheme.gold,
          const Color(0xFFFFF2D9),
          fa
              ? 'اعلان‌ها در تنظیمات دستگاه مسدودند'
              : 'Notifications are blocked in device settings',
          fa
              ? 'برای دریافت یادآورها، اعلان‌ها را از تنظیمات دستگاه فعال کن.'
              : 'Enable notifications in device settings to receive reminders.',
          fa ? 'بازکردن تنظیمات دستگاه' : 'Open device settings',
          onOpenSystemSettings,
        ),
      CocoonReminderPermissionState.unavailable => (
          Icons.info_outline_rounded,
          CocoonTheme.muted,
          const Color(0xFFF2F4F7),
          fa
              ? 'اعلان روی این دستگاه در دسترس نیست'
              : 'Notifications are unavailable on this device',
          fa
              ? 'هنوز می‌توانی ترجیحاتت را برای بعد ذخیره کنی.'
              : 'You can still save your preferences for later.',
          null,
          null,
        ),
    };
    return Semantics(
      liveRegion: true,
      container: true,
      child: Container(
        padding: const EdgeInsetsDirectional.all(16),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 3),
                  Text(body, style: Theme.of(context).textTheme.bodyMedium),
                  if (action != null && callback != null) ...[
                    const SizedBox(height: 8),
                    TextButton(onPressed: callback, child: Text(action)),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReminderToggle extends StatelessWidget {
  const _ReminderToggle({
    required this.icon,
    required this.title,
    required this.supporting,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String supporting;
  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => SwitchListTile.adaptive(
        contentPadding: const EdgeInsetsDirectional.fromSTEB(12, 7, 8, 7),
        secondary: CircleAvatar(
          backgroundColor: CocoonTheme.warm,
          foregroundColor: CocoonTheme.coral,
          child: Icon(icon, size: 21),
        ),
        title: Text(title),
        subtitle: Padding(
          padding: const EdgeInsetsDirectional.only(top: 3),
          child: Text(supporting),
        ),
        value: value,
        onChanged: enabled ? onChanged : null,
      );
}

class _CanonicalReminderLink extends StatelessWidget {
  const _CanonicalReminderLink({
    required this.fa,
    required this.icon,
    required this.title,
    required this.summary,
    required this.onTap,
  });

  final bool fa;
  final IconData icon;
  final String title;
  final String summary;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: '$title، $summary',
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Ink(
            padding: const EdgeInsetsDirectional.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: CocoonTheme.line),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: CocoonTheme.sage,
                  foregroundColor: CocoonTheme.sageStrong,
                  child: Icon(icon, size: 21),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 2),
                      Text(
                        summary,
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(color: CocoonTheme.muted),
                      ),
                    ],
                  ),
                ),
                ExcludeSemantics(
                  child: Icon(
                    fa
                        ? Icons.chevron_left_rounded
                        : Icons.chevron_right_rounded,
                    color: CocoonTheme.muted,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}

class _PrivacyChoice extends StatelessWidget {
  const _PrivacyChoice({
    required this.fa,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final bool fa;
  final CocoonLockScreenPrivacy value;
  final bool enabled;
  final ValueChanged<CocoonLockScreenPrivacy> onChanged;

  @override
  Widget build(BuildContext context) => Column(
        children: [
          _PrivacyOption(
            title: fa ? 'خصوصی' : 'Private',
            supporting: fa
                ? 'فقط نام CocoonMate نمایش داده می‌شود'
                : 'Only the CocoonMate name is shown',
            icon: Icons.lock_outline_rounded,
            selected: value == CocoonLockScreenPrivacy.private,
            enabled: enabled,
            onTap: () => onChanged(CocoonLockScreenPrivacy.private),
          ),
          const SizedBox(height: 9),
          _PrivacyOption(
            title: fa ? 'توضیح‌دار' : 'Descriptive',
            supporting: fa
                ? 'نوع و زمان یادآور روی صفحه قفل دیده می‌شود'
                : 'Reminder type and time appear on the lock screen',
            icon: Icons.visibility_outlined,
            selected: value == CocoonLockScreenPrivacy.descriptive,
            enabled: enabled,
            onTap: () => onChanged(CocoonLockScreenPrivacy.descriptive),
          ),
        ],
      );
}

class _PrivacyOption extends StatelessWidget {
  const _PrivacyOption({
    required this.title,
    required this.supporting,
    required this.icon,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final String title;
  final String supporting;
  final IconData icon;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        selected: selected,
        button: true,
        enabled: enabled,
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(18),
          child: Ink(
            padding: const EdgeInsetsDirectional.all(14),
            decoration: BoxDecoration(
              color: selected ? CocoonTheme.coralSoft : Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: selected ? CocoonTheme.coral : CocoonTheme.line,
              ),
            ),
            child: Row(
              children: [
                Icon(icon,
                    color: selected ? CocoonTheme.coral : CocoonTheme.muted),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 2),
                      Text(supporting),
                    ],
                  ),
                ),
                Radio<CocoonLockScreenPrivacy>(
                  value: selected
                      ? CocoonLockScreenPrivacy.private
                      : CocoonLockScreenPrivacy.descriptive,
                  groupValue: selected ? CocoonLockScreenPrivacy.private : null,
                  onChanged: enabled ? (_) => onTap() : null,
                ),
              ],
            ),
          ),
        ),
      );
}

class _NotificationPreview extends StatelessWidget {
  const _NotificationPreview({required this.fa, required this.privacy});
  final bool fa;
  final CocoonLockScreenPrivacy privacy;

  @override
  Widget build(BuildContext context) {
    final private = privacy == CocoonLockScreenPrivacy.private;
    return Semantics(
      container: true,
      label:
          fa ? 'پیش‌نمایش اعلان صفحه قفل' : 'Lock-screen notification preview',
      child: Container(
        padding: const EdgeInsetsDirectional.all(18),
        decoration: BoxDecoration(
          color: CocoonTheme.ink,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Container(
          padding: const EdgeInsetsDirectional.all(15),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: .94),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const CircleAvatar(
                radius: 19,
                backgroundColor: CocoonTheme.coralSoft,
                child: Icon(Icons.spa_outlined,
                    color: CocoonTheme.coral, size: 20),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('CocoonMate',
                        style: Theme.of(context).textTheme.labelLarge),
                    const SizedBox(height: 2),
                    Text(
                      private
                          ? (fa
                              ? 'یک یادآور برای تو آماده است'
                              : 'A reminder is ready for you')
                          : (fa
                              ? 'یادآوری قرار فردا، ساعت ۱۰'
                              : 'Appointment reminder tomorrow at 10:00'),
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
              Text(
                fa ? 'اکنون' : 'now',
                style: Theme.of(context)
                    .textTheme
                    .labelMedium
                    ?.copyWith(fontSize: 11),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PartnerPrivacyNote extends StatelessWidget {
  const _PartnerPrivacyNote({required this.fa});
  final bool fa;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsetsDirectional.all(16),
        decoration: BoxDecoration(
          color: CocoonTheme.sky,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.people_outline_rounded,
                color: CocoonTheme.skyStrong),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                fa
                    ? 'یادآورها به‌طور خودکار با همسر یا همراهت به اشتراک گذاشته نمی‌شوند. اشتراک‌گذاری فقط با انتخاب و رضایت جداگانه انجام می‌شود.'
                    : 'Reminders are never shared automatically with a partner or caregiver. Sharing requires a separate, explicit choice.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          ],
        ),
      );
}

class _ReminderCachedStatus extends StatelessWidget {
  const _ReminderCachedStatus({required this.fa, this.savedAtLabel});
  final bool fa;
  final String? savedAtLabel;

  @override
  Widget build(BuildContext context) => Semantics(
        liveRegion: true,
        child: Container(
          padding: const EdgeInsetsDirectional.symmetric(
              horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF2D9),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              const Icon(Icons.cloud_off_outlined,
                  color: CocoonTheme.gold, size: 20),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  savedAtLabel == null
                      ? (fa
                          ? 'آخرین تنظیمات ذخیره‌شده روی دستگاه'
                          : 'Last settings saved on this device')
                      : (fa
                          ? 'ذخیره‌شده روی دستگاه • $savedAtLabel'
                          : 'Saved on this device • $savedAtLabel'),
                ),
              ),
            ],
          ),
        ),
      );
}

class _ReminderSaveStatus extends StatelessWidget {
  const _ReminderSaveStatus({required this.fa, required this.state});
  final bool fa;
  final CocoonReminderSaveState state;

  @override
  Widget build(BuildContext context) {
    final (icon, color, text) = switch (state) {
      CocoonReminderSaveState.saving => (
          Icons.sync_rounded,
          CocoonTheme.skyStrong,
          fa ? 'در حال ذخیره تنظیمات…' : 'Saving settings…',
        ),
      CocoonReminderSaveState.queued => (
          Icons.schedule_rounded,
          CocoonTheme.gold,
          fa ? 'تغییرات در صف همگام‌سازی است' : 'Changes are queued for sync',
        ),
      CocoonReminderSaveState.confirmed => (
          Icons.check_circle_outline_rounded,
          CocoonTheme.sageStrong,
          fa ? 'تنظیمات ذخیره شد' : 'Settings saved',
        ),
      CocoonReminderSaveState.error => (
          Icons.error_outline_rounded,
          Theme.of(context).colorScheme.error,
          fa ? 'ذخیره انجام نشد؛ دوباره تلاش کن' : 'Could not save; try again',
        ),
      CocoonReminderSaveState.idle => (
          Icons.check_rounded,
          CocoonTheme.muted,
          ''
        ),
    };
    return Semantics(
      liveRegion: true,
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}

class _ReminderLoading extends StatelessWidget {
  const _ReminderLoading({required this.fa});
  final bool fa;

  @override
  Widget build(BuildContext context) => Semantics(
        label:
            fa ? 'در حال بارگذاری تنظیمات یادآور' : 'Loading reminder settings',
        child: SingleChildScrollView(
          child: CocoonPagePadding(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  height: 142,
                  decoration: BoxDecoration(
                    color: CocoonTheme.lilac,
                    borderRadius: BorderRadius.circular(28),
                  ),
                ),
                const SizedBox(height: 28),
                for (var index = 0; index < 4; index++) ...[
                  Container(
                    height: 72,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: CocoonTheme.line),
                    ),
                  ),
                  const SizedBox(height: 11),
                ],
              ],
            ),
          ),
        ),
      );
}
