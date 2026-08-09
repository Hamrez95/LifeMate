import 'package:flutter/material.dart';
import 'package:lifemate_client/lifemate_client.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_style.dart';

class CareAccessSettingsScreen extends StatefulWidget {
  const CareAccessSettingsScreen({
    super.key,
    required this.relationship,
    this.managementApi,
  });

  final Map<String, dynamic> relationship;
  final LifeMateCareManagementApi? managementApi;

  @override
  State<CareAccessSettingsScreen> createState() =>
      _CareAccessSettingsScreenState();
}

class _CareAccessSettingsScreenState extends State<CareAccessSettingsScreen> {
  late final LifeMateCareManagementApi _managementApi =
      widget.managementApi ?? LifeMateCareManagementApi.fromEnvironment();

  bool _loading = true;
  bool _savingWomenCalendar = false;
  bool _savingHealthRecord = false;
  bool _womenCalendarEnabled = false;
  bool _canViewWomenCalendar = false;
  bool _canManageHealthRecord = false;
  String? _error;

  String get _relationshipId => widget.relationship['id'].toString();

  @override
  void initState() {
    super.initState();
    _canViewWomenCalendar = widget.relationship['canViewWomenCalendar'] == true;
    _load();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    String? errorMessage;
    try {
      if (LifeMateFeatureFlags.womenCalendarPilotEnabled) {
        final profile = await context
            .read<LifeMateApiClient>()
            .getWomenCalendarProfile();
        if (mounted) {
          setState(() => _womenCalendarEnabled = profile['enabled'] == true);
        }
      }
    } catch (error) {
      debugPrint('Care permission women profile load failed: $error');
      errorMessage = 'وضعیت تقویم بانوان دریافت نشد.';
    }

    try {
      final permission = await _managementApi.getRelationshipPermission(
        relationshipId: _relationshipId,
      );
      if (mounted) {
        setState(() {
          _canManageHealthRecord = permission['canManageHealthRecord'] == true;
        });
      }
    } catch (error) {
      debugPrint('Care health-record permission load failed: $error');
      errorMessage ??= 'وضعیت دسترسی پرونده سلامت دریافت نشد.';
    }

    if (mounted) {
      setState(() {
        _error = errorMessage;
        _loading = false;
      });
    }
  }

  Future<void> _setWomenCalendarAccess(bool value) async {
    if (_savingWomenCalendar) return;
    setState(() => _savingWomenCalendar = true);
    try {
      final updated = await context
          .read<LifeMateApiClient>()
          .updateCareRelationshipPermissions(
            relationshipId: _relationshipId,
            canViewWomenCalendar: value,
          );
      if (!mounted) return;
      setState(() {
        _canViewWomenCalendar = updated['canViewWomenCalendar'] == true;
      });
      LifeMateNotice.show(
        context,
        type: LifeMateNoticeType.success,
        title: value ? 'دسترسی فعال شد' : 'دسترسی غیرفعال شد',
        message: value
            ? 'خلاصه تقویم بانوان برای این مراقب قابل مشاهده است.'
            : 'تقویم بانوان دیگر برای این مراقب نمایش داده نمی‌شود.',
      );
    } catch (error) {
      debugPrint('Care women permission update failed: $error');
      if (mounted) {
        LifeMateNotice.show(
          context,
          type: LifeMateNoticeType.error,
          title: 'تغییر دسترسی انجام نشد',
          message: 'وضعیت تقویم بانوان ذخیره نشد. دوباره تلاش کنید.',
        );
      }
    } finally {
      if (mounted) setState(() => _savingWomenCalendar = false);
    }
  }

  Future<void> _setHealthRecordAccess(bool value) async {
    if (_savingHealthRecord) return;

    if (value) {
      final accepted = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _HealthRecordConsentDialog(
          caregiverName:
              widget.relationship['caregiverDisplayName']?.toString() ??
              'این مراقب',
        ),
      );
      if (accepted != true || !mounted) return;
    }

    setState(() => _savingHealthRecord = true);
    try {
      final updated = await _managementApi.updateHealthRecordPermission(
        relationshipId: _relationshipId,
        enabled: value,
        confirmConsent: value,
      );
      if (!mounted) return;
      setState(() {
        _canManageHealthRecord = updated['canManageHealthRecord'] == true;
      });
      LifeMateNotice.show(
        context,
        type: LifeMateNoticeType.success,
        title: value ? 'مدیریت پرونده فعال شد' : 'مدیریت پرونده متوقف شد',
        message: value
            ? 'مراقب می‌تواند دارو، ویزیت و تزریق را اضافه، ویرایش یا حذف کند.'
            : 'امکان تغییر درمان‌ها برای این مراقب فوراً متوقف شد.',
      );
    } on LifeMateApiException catch (error) {
      if (!mounted) return;
      LifeMateNotice.show(
        context,
        type: LifeMateNoticeType.error,
        title: 'تغییر دسترسی انجام نشد',
        message: error.code == 'health_record_consent_required'
            ? 'برای فعال‌سازی این دسترسی، تأیید آگاهانه شما لازم است.'
            : 'دسترسی پرونده سلامت ذخیره نشد. دوباره تلاش کنید.',
      );
    } catch (error) {
      debugPrint('Care health-record permission update failed: $error');
      if (mounted) {
        LifeMateNotice.show(
          context,
          type: LifeMateNoticeType.error,
          title: 'تغییر دسترسی انجام نشد',
          message: 'اتصال را بررسی کنید و دوباره تلاش کنید.',
        );
      }
    } finally {
      if (mounted) setState(() => _savingHealthRecord = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final name =
        widget.relationship['caregiverDisplayName']?.toString() ?? 'مراقب';
    final womenAvailable =
        LifeMateFeatureFlags.womenCalendarPilotEnabled && _womenCalendarEnabled;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        title: Text(
          'تنظیمات دسترسی $name',
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
          children: [
            _PrivacyHero(name: name),
            const SizedBox(height: 18),
            const _PermissionCard(
              key: ValueKey('care-permission-medication'),
              icon: Icons.medication_rounded,
              accent: Color(0xFF2FB486),
              softColor: Color(0xFFE9F8F2),
              title: 'برنامه و مصرف دارو',
              subtitle:
                  'دسترسی پایه رابطه مراقبتی برای مشاهده برنامه و وضعیت مصرف.',
              value: true,
              enabled: false,
              badge: 'پایه',
            ),
            const SizedBox(height: 12),
            _PermissionCard(
              key: const ValueKey('care-permission-women-calendar'),
              icon: Icons.calendar_month_rounded,
              accent: const Color(0xFFE45D8F),
              softColor: const Color(0xFFFFEEF4),
              title: 'تقویم بانوان',
              subtitle: !LifeMateFeatureFlags.womenCalendarPilotEnabled
                  ? 'در این Build فعال نیست.'
                  : !_womenCalendarEnabled
                  ? 'ابتدا تقویم بانوان را برای خودتان فعال کنید.'
                  : 'نمایش خلاصه چرخه؛ یادداشت خصوصی هرگز به اشتراک گذاشته نمی‌شود.',
              value: _canViewWomenCalendar,
              enabled: !_loading && !_savingWomenCalendar && womenAvailable,
              onChanged: _setWomenCalendarAccess,
              loading: _savingWomenCalendar,
            ),
            const SizedBox(height: 12),
            _PermissionCard(
              key: const ValueKey('care-permission-health-record'),
              icon: Icons.folder_shared_rounded,
              accent: const Color(0xFF6C74D9),
              softColor: const Color(0xFFF0F1FF),
              title: 'مشاهده و ویرایش پرونده سلامت',
              subtitle:
                  'اجازه مشاهده و مدیریت درمان‌ها؛ شامل افزودن، ویرایش و حذف دارو، ویزیت و تزریق.',
              value: _canManageHealthRecord,
              enabled: !_loading && !_savingHealthRecord,
              onChanged: _setHealthRecordAccess,
              loading: _savingHealthRecord,
              isSensitive: true,
            ),
            if (_error != null) ...[
              const SizedBox(height: 14),
              _InlineError(message: _error!, onRetry: _load),
            ],
            const SizedBox(height: 18),
            const _SecurityFooter(),
          ],
        ),
      ),
    );
  }
}

class _PrivacyHero extends StatelessWidget {
  const _PrivacyHero({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        begin: Alignment.topRight,
        end: Alignment.bottomLeft,
        colors: [Color(0xFFEAF7F2), Color(0xFFF3F5FF)],
      ),
      borderRadius: BorderRadius.circular(26),
      border: Border.all(color: Colors.white),
      boxShadow: const [
        BoxShadow(
          color: Color(0x0F203C55),
          blurRadius: 20,
          offset: Offset(0, 8),
        ),
      ],
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: const BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.shield_outlined, color: Color(0xFF397B70)),
        ),
        const SizedBox(width: 13),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'کنترل دسترسی دست شماست',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'هر دسترسی برای $name مستقل فعال می‌شود. هر زمان بخواهید می‌توانید آن را خاموش کنید؛ قطع رابطه نیز همه دسترسی‌ها را متوقف می‌کند.',
                style: const TextStyle(
                  height: 1.65,
                  fontSize: 12.5,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _PermissionCard extends StatelessWidget {
  const _PermissionCard({
    super.key,
    required this.icon,
    required this.accent,
    required this.softColor,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.enabled,
    this.onChanged,
    this.loading = false,
    this.badge,
    this.isSensitive = false,
  });

  final IconData icon;
  final Color accent;
  final Color softColor;
  final String title;
  final String subtitle;
  final bool value;
  final bool enabled;
  final ValueChanged<bool>? onChanged;
  final bool loading;
  final String? badge;
  final bool isSensitive;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: value
              ? accent.withValues(alpha: 0.28)
              : const Color(0xFFE8EDF2),
        ),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: value ? 0.09 : 0.04),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: softColor,
              borderRadius: BorderRadius.circular(17),
            ),
            child: Icon(icon, color: accent, size: 27),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 7,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w900,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    if (badge != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: softColor,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          badge!,
                          style: TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w800,
                            color: accent,
                          ),
                        ),
                      ),
                    if (isSensitive)
                      Icon(
                        Icons.verified_user_outlined,
                        size: 17,
                        color: accent,
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  style: const TextStyle(
                    height: 1.55,
                    fontSize: 11.5,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          if (loading)
            SizedBox.square(
              dimension: 28,
              child: CircularProgressIndicator(strokeWidth: 2.4, color: accent),
            )
          else
            Switch.adaptive(
              key: ValueKey<String>('permission-switch-$title'),
              value: value,
              onChanged: enabled ? onChanged : null,
              activeThumbColor: Colors.white,
              activeTrackColor: accent,
              inactiveThumbColor: Colors.white,
              inactiveTrackColor: const Color(0xFFD6DDE5),
            ),
        ],
      ),
    );
  }
}

class _HealthRecordConsentDialog extends StatefulWidget {
  const _HealthRecordConsentDialog({required this.caregiverName});

  final String caregiverName;

  @override
  State<_HealthRecordConsentDialog> createState() =>
      _HealthRecordConsentDialogState();
}

class _HealthRecordConsentDialogState
    extends State<_HealthRecordConsentDialog> {
  bool _accepted = false;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      title: const Row(
        children: [
          CircleAvatar(
            backgroundColor: Color(0xFFFFF0E6),
            child: Icon(Icons.warning_amber_rounded, color: Color(0xFFD8752F)),
          ),
          SizedBox(width: 11),
          Expanded(
            child: Text(
              'تأیید دسترسی حساس',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 430, maxHeight: 520),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'با فعال‌کردن «مشاهده و ویرایش پرونده سلامت»، شما با آگاهی به ${widget.caregiverName} اجازه می‌دهید برنامه‌های درمانی شما را مدیریت کند.',
                style: const TextStyle(height: 1.65),
              ),
              const SizedBox(height: 14),
              const _ConsentPoint(
                icon: Icons.visibility_outlined,
                text:
                    'مراقب می‌تواند داروها، ویزیت‌ها و تزریق‌های ثبت‌شده را مشاهده کند.',
              ),
              const _ConsentPoint(
                icon: Icons.edit_note_rounded,
                text:
                    'مراقب می‌تواند درمان جدید اضافه کند یا اطلاعات درمان‌های موجود را ویرایش کند.',
              ),
              const _ConsentPoint(
                icon: Icons.delete_outline_rounded,
                text:
                    'مراقب می‌تواند درمان را حذف کند؛ حذف در سیستم به‌صورت توقف/بایگانی امن ثبت می‌شود.',
              ),
              const _ConsentPoint(
                icon: Icons.notifications_active_outlined,
                text:
                    'این تغییرات می‌توانند روی برنامه روزانه، یادآورها و اطلاعاتی که در WellMate و CareMate می‌بینید اثر بگذارند.',
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(13),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF7E8),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Text(
                  'این دسترسی جایگزین نظر پزشک نیست. مسئولیت تصمیم برای اعطای این دسترسی و بررسی صحت تغییرات ثبت‌شده بر عهده شماست. می‌توانید هر زمان این دسترسی را غیرفعال کنید. برای امنیت، اعطا، لغو و تغییرات درمانی ثبت و قابل پیگیری هستند.',
                  style: TextStyle(
                    height: 1.65,
                    fontSize: 11.5,
                    color: Color(0xFF74552A),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              CheckboxListTile(
                key: const ValueKey('health-record-consent-checkbox'),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: _accepted,
                onChanged: (value) =>
                    setState(() => _accepted = value ?? false),
                title: const Text(
                  'متوجه محدوده این دسترسی و امکان تغییر پرونده درمانی توسط مراقب هستم و با فعال‌سازی آن موافقم.',
                  style: TextStyle(
                    height: 1.55,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('انصراف'),
        ),
        FilledButton.icon(
          key: const ValueKey('confirm-health-record-access'),
          onPressed: _accepted ? () => Navigator.pop(context, true) : null,
          icon: const Icon(Icons.lock_open_rounded),
          label: const Text('تأیید و فعال‌سازی'),
          style: FilledButton.styleFrom(backgroundColor: const Color(0xFF626BD1)),
        ),
      ],
    );
  }
}

class _ConsentPoint extends StatelessWidget {
  const _ConsentPoint({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 9),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 19, color: const Color(0xFF626BD1)),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(height: 1.55, fontSize: 12),
          ),
        ),
      ],
    ),
  );
}

class _InlineError extends StatelessWidget {
  const _InlineError({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: const Color(0xFFFFF0F1),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: const Color(0xFFFFD6DA)),
    ),
    child: Row(
      children: [
        const Icon(Icons.cloud_off_rounded, color: Color(0xFFD95D66)),
        const SizedBox(width: 9),
        Expanded(child: Text(message)),
        TextButton(onPressed: onRetry, child: const Text('تلاش دوباره')),
      ],
    ),
  );
}

class _SecurityFooter extends StatelessWidget {
  const _SecurityFooter();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 5),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(
          Icons.info_outline_rounded,
          size: 18,
          color: AppColors.textSecondary,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'دسترسی مدیریت پرونده فقط برای همان مراقب و همان رابطه فعال است و با خاموش‌کردن گزینه یا قطع رابطه متوقف می‌شود.',
            style: TextStyle(
              height: 1.55,
              fontSize: 10.5,
              color: AppColors.textSecondary.withValues(alpha: 0.9),
            ),
          ),
        ),
      ],
    ),
  );
}
