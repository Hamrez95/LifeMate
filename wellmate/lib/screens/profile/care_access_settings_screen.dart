import 'package:flutter/material.dart';
import 'package:lifemate_client/lifemate_client.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_style.dart';
import 'women_companion_privacy_screen.dart';

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
  bool _savingHealthDocuments = false;
  bool _womenCalendarEnabled = false;
  bool _canViewWomenCalendar = false;
  bool _canManageHealthRecord = false;
  bool _canViewHealthDocuments = false;
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
      errorMessage = LifeMateRuntimeLocale.select(
        fa: LifeMateRuntimeLocale.select(
          fa: 'وضعیت تقویم بانوان دریافت نشد.',
          en: "The status of the women's calendar was not received.",
        ),
        en: "The status of the women's calendar was not received.",
      );
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
      errorMessage ??= LifeMateRuntimeLocale.select(
        fa: LifeMateRuntimeLocale.select(
          fa: 'وضعیت دسترسی پرونده سلامت دریافت نشد.',
          en: "The access status of the health record was not received.",
        ),
        en: "The access status of the health record was not received.",
      );
    }

    try {
  final permission = await context
      .read<LifeMateApiClient>()
      .getHealthDocumentSharingPermission(
        relationshipId: _relationshipId,
      );
  if (mounted) {
    setState(() {
      _canViewHealthDocuments =
          permission['canViewDocuments'] == true;
    });
  }
} catch (error) {
  debugPrint('Care document sharing permission load failed: $error');
  errorMessage ??= LifeMateRuntimeLocale.select(
    fa: 'وضعیت اشتراک مدارک پرونده سلامت دریافت نشد.',
    en: 'Health Record document sharing status could not be loaded.',
  );
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
        title: value
            ? LifeMateRuntimeLocale.select(
                fa: LifeMateRuntimeLocale.select(
                  fa: 'دسترسی فعال شد',
                  en: "Access enabled",
                ),
                en: "Access enabled",
              )
            : LifeMateRuntimeLocale.select(
                fa: LifeMateRuntimeLocale.select(
                  fa: 'دسترسی غیرفعال شد',
                  en: "Access disabled",
                ),
                en: "Access disabled",
              ),
        message: value
            ? LifeMateRuntimeLocale.select(
                fa: LifeMateRuntimeLocale.select(
                  fa: 'خلاصه تقویم بانوان برای این مراقب قابل مشاهده است.',
                  en: "A summary of the women's calendar is visible to this caregiver.",
                ),
                en: "A summary of the women's calendar is visible to this caregiver.",
              )
            : LifeMateRuntimeLocale.select(
                fa: LifeMateRuntimeLocale.select(
                  fa: 'تقویم بانوان دیگر برای این مراقب نمایش داده نمی‌شود.',
                  en: "The ladies calendar is no longer displayed for this caregiver.",
                ),
                en: "The ladies calendar is no longer displayed for this caregiver.",
              ),
      );
    } catch (error) {
      debugPrint('Care women permission update failed: $error');
      if (mounted) {
        LifeMateNotice.show(
          context,
          type: LifeMateNoticeType.error,
          title: LifeMateRuntimeLocale.select(
            fa: LifeMateRuntimeLocale.select(
              fa: 'تغییر دسترسی انجام نشد',
              en: "Access change failed",
            ),
            en: "Access change failed",
          ),
          message: LifeMateRuntimeLocale.select(
            fa: LifeMateRuntimeLocale.select(
              fa: 'وضعیت تقویم بانوان ذخیره نشد. دوباره تلاش کنید.',
              en: "The status of the women's calendar was not saved. Try again.",
            ),
            en: "The status of the women's calendar was not saved. Try again.",
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _savingWomenCalendar = false);
    }
  }

  Future<void> _setHealthDocumentAccess(bool value) async {
  if (_savingHealthDocuments) return;
  if (value) {
    final accepted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: Text(LifeMateRuntimeLocale.select(
          fa: 'اشتراک مدارک پرونده سلامت',
          en: 'Share Health Record documents',
        )),
        content: Text(LifeMateRuntimeLocale.select(
          fa: 'این مراقب فقط می‌تواند مدارک را مشاهده و دانلود کند. اجازه افزودن، ویرایش یا حذف مدرک داده نمی‌شود و هر زمان بخواهید می‌توانید این دسترسی را لغو کنید.',
          en: 'This caregiver can only view and download documents. They cannot add, edit or delete documents, and you can revoke access at any time.',
        )),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(LifeMateRuntimeLocale.select(
              fa: 'انصراف',
              en: 'Cancel',
            )),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(LifeMateRuntimeLocale.select(
              fa: 'تأیید و اشتراک',
              en: 'Confirm sharing',
            )),
          ),
        ],
      ),
    );
    if (accepted != true || !mounted) return;
  }

  setState(() => _savingHealthDocuments = true);
  try {
    final updated = await context
        .read<LifeMateApiClient>()
        .updateHealthDocumentSharingPermission(
          relationshipId: _relationshipId,
          enabled: value,
          confirmConsent: value,
        );
    if (!mounted) return;
    setState(() {
      _canViewHealthDocuments = updated['canViewDocuments'] == true;
    });
    LifeMateNotice.show(
      context,
      type: LifeMateNoticeType.success,
      title: LifeMateRuntimeLocale.select(
        fa: value ? 'اشتراک مدارک فعال شد' : 'اشتراک مدارک لغو شد',
        en: value ? 'Document sharing enabled' : 'Document sharing revoked',
      ),
      message: LifeMateRuntimeLocale.select(
        fa: value
            ? 'این مراقب اکنون دسترسی فقط‌خواندنی به مدارک دارد.'
            : 'صدور دسترسی جدید به مدارک برای این مراقب فوراً متوقف شد.',
        en: value
            ? 'This caregiver now has read-only document access.'
            : 'New document access for this caregiver has been stopped immediately.',
      ),
    );
  } on LifeMateApiException catch (error) {
    if (!mounted) return;
    LifeMateNotice.show(
      context,
      type: LifeMateNoticeType.error,
      title: LifeMateRuntimeLocale.select(
        fa: 'تغییر اشتراک انجام نشد',
        en: 'Sharing change failed',
      ),
      message: error.code == 'health_document_sharing_consent_required'
          ? LifeMateRuntimeLocale.select(
              fa: 'برای اشتراک مدارک، تأیید صریح شما لازم است.',
              en: 'Your explicit consent is required to share documents.',
            )
          : LifeMateRuntimeLocale.select(
              fa: 'اشتراک مدارک ذخیره نشد. دوباره تلاش کنید.',
              en: 'Document sharing was not saved. Try again.',
            ),
    );
  } finally {
    if (mounted) setState(() => _savingHealthDocuments = false);
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
              LifeMateRuntimeLocale.select(
                fa: LifeMateRuntimeLocale.select(
                  fa: 'این مراقب',
                  en: "This is careful",
                ),
                en: "This is careful",
              ),
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
        title: value
            ? LifeMateRuntimeLocale.select(
                fa: LifeMateRuntimeLocale.select(
                  fa: 'مدیریت پرونده فعال شد',
                  en: "File management is activated",
                ),
                en: "File management is activated",
              )
            : LifeMateRuntimeLocale.select(
                fa: LifeMateRuntimeLocale.select(
                  fa: 'مدیریت پرونده متوقف شد',
                  en: "Case management stopped",
                ),
                en: "Case management stopped",
              ),
        message: value
            ? LifeMateRuntimeLocale.select(
                fa: LifeMateRuntimeLocale.select(
                  fa: 'مراقب می‌تواند دارو، ویزیت و تزریق را اضافه، ویرایش یا حذف کند.',
                  en: "The caregiver can add, edit, or delete medications, visits, and injections.",
                ),
                en: "The caregiver can add, edit, or delete medications, visits, and injections.",
              )
            : LifeMateRuntimeLocale.select(
                fa: LifeMateRuntimeLocale.select(
                  fa: 'امکان تغییر درمان‌ها برای این مراقب فوراً متوقف شد.',
                  en: "The ability to change treatments for this caregiver was immediately stopped.",
                ),
                en: "The ability to change treatments for this caregiver was immediately stopped.",
              ),
      );
    } on LifeMateApiException catch (error) {
      if (!mounted) return;
      LifeMateNotice.show(
        context,
        type: LifeMateNoticeType.error,
        title: LifeMateRuntimeLocale.select(
          fa: LifeMateRuntimeLocale.select(
            fa: 'تغییر دسترسی انجام نشد',
            en: "Access change failed",
          ),
          en: "Access change failed",
        ),
        message: error.code == 'health_record_consent_required'
            ? LifeMateRuntimeLocale.select(
                fa: LifeMateRuntimeLocale.select(
                  fa: 'برای فعال‌سازی این دسترسی، تأیید آگاهانه شما لازم است.',
                  en: "Your informed consent is required to enable this access.",
                ),
                en: "Your informed consent is required to enable this access.",
              )
            : LifeMateRuntimeLocale.select(
                fa: LifeMateRuntimeLocale.select(
                  fa: 'دسترسی پرونده سلامت ذخیره نشد. دوباره تلاش کنید.',
                  en: "Access to the health record could not be saved. Try again.",
                ),
                en: "Access to the health record could not be saved. Try again.",
              ),
      );
    } catch (error) {
      debugPrint('Care health-record permission update failed: $error');
      if (mounted) {
        LifeMateNotice.show(
          context,
          type: LifeMateNoticeType.error,
          title: LifeMateRuntimeLocale.select(
            fa: LifeMateRuntimeLocale.select(
              fa: 'تغییر دسترسی انجام نشد',
              en: "Access change failed",
            ),
            en: "Access change failed",
          ),
          message: LifeMateRuntimeLocale.select(
            fa: LifeMateRuntimeLocale.select(
              fa: 'اتصال را بررسی کنید و دوباره تلاش کنید.',
              en: "Check the connection and try again.",
            ),
            en: "Check the connection and try again.",
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _savingHealthRecord = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final name =
        widget.relationship['caregiverDisplayName']?.toString() ??
        LifeMateRuntimeLocale.select(
          fa: LifeMateRuntimeLocale.select(fa: 'مراقب', en: "Caregiver"),
          en: "Careful",
        );
    final womenAvailable =
        LifeMateFeatureFlags.womenCalendarPilotEnabled && _womenCalendarEnabled;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        title: Text(
          LifeMateRuntimeLocale.select(
            fa: LifeMateRuntimeLocale.select(
              fa: 'تنظیمات دسترسی $name',
              en: "$name access settings",
            ),
            en: "$name access settings",
          ),
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(20, 8, 20, 28),
          children: [
            _PrivacyHero(name: name),
            SizedBox(height: 18),
            _PermissionCard(
              key: ValueKey('care-permission-medication'),
              icon: Icons.medication_rounded,
              accent: Color(0xFF2FB486),
              softColor: Color(0xFFE9F8F2),
              title: LifeMateRuntimeLocale.select(
                fa: LifeMateRuntimeLocale.select(
                  fa: 'برنامه و مصرف دارو',
                  en: "Program and drug use",
                ),
                en: "Program and drug use",
              ),
              subtitle: LifeMateRuntimeLocale.select(
                fa: LifeMateRuntimeLocale.select(
                  fa: 'دسترسی پایه رابطه مراقبتی برای مشاهده برنامه و وضعیت مصرف.',
                  en: "Basic access to the care relationship to view the application and consumption status.",
                ),
                en: "Basic access to the care relationship to view the application and consumption status.",
              ),
              value: true,
              enabled: false,
              badge: LifeMateRuntimeLocale.select(
                fa: LifeMateRuntimeLocale.select(fa: 'پایه', en: "base"),
                en: "base",
              ),
            ),
            SizedBox(height: 12),
            _PermissionCard(
              key: ValueKey('care-permission-women-calendar'),
              icon: Icons.calendar_month_rounded,
              accent: Color(0xFFE45D8F),
              softColor: Color(0xFFFFEEF4),
              title: LifeMateRuntimeLocale.select(
                fa: LifeMateRuntimeLocale.select(
                  fa: 'تقویم بانوان',
                  en: "Women's Calendar",
                ),
                en: "Women's calendar",
              ),
              subtitle: !LifeMateFeatureFlags.womenCalendarPilotEnabled
                  ? LifeMateRuntimeLocale.select(
                      fa: LifeMateRuntimeLocale.select(
                        fa: 'در این Build فعال نیست.',
                        en: "It is not active in this build.",
                      ),
                      en: "It is not active in this build.",
                    )
                  : !_womenCalendarEnabled
                  ? LifeMateRuntimeLocale.select(
                      fa: LifeMateRuntimeLocale.select(
                        fa: 'ابتدا تقویم بانوان را برای خودتان فعال کنید.',
                        en: "First, activate the women's calendar for yourself.",
                      ),
                      en: "First, activate the women's calendar for yourself.",
                    )
                  : LifeMateRuntimeLocale.select(
                      fa: LifeMateRuntimeLocale.select(
                        fa: 'نمایش خلاصه چرخه؛ یادداشت خصوصی هرگز به اشتراک گذاشته نمی‌شود.',
                        en: "cycle summary display; A private note is never shared.",
                      ),
                      en: "cycle summary display; A private note is never shared.",
                    ),
              value: _canViewWomenCalendar,
              enabled: !_loading && !_savingWomenCalendar && womenAvailable,
              onChanged: _setWomenCalendarAccess,
              loading: _savingWomenCalendar,
            ),
            if (womenAvailable) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                key: const ValueKey('open-companion-privacy-center'),
                onPressed: _loading
                    ? null
                    : () async {
                        await Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => WomenCompanionPrivacyScreen(
                              relationship: widget.relationship,
                            ),
                          ),
                        );
                        if (mounted) await _load();
                      },
                icon: const Icon(Icons.tune_rounded),
                label: Text(
                  LifeMateRuntimeLocale.select(
                    fa: 'جزئیات حریم خصوصی همدم',
                    en: 'Companion privacy details',
                  ),
                ),
              ),
            ],
            SizedBox(height: 12),
  _PermissionCard(
    key: ValueKey('care-permission-health-documents'),
    icon: Icons.description_rounded,
    accent: Color(0xFF397B70),
    softColor: Color(0xFFEAF7F2),
    title: LifeMateRuntimeLocale.select(
      fa: 'مدارک پرونده سلامت',
      en: 'Health Record documents',
    ),
    subtitle: LifeMateRuntimeLocale.select(
      fa: 'فقط مشاهده و دانلود مدارک؛ بدون اجازه افزودن، ویرایش یا حذف.',
      en: 'View and download only; no permission to add, edit or delete documents.',
    ),
    value: _canViewHealthDocuments,
    enabled: !_loading && !_savingHealthDocuments,
    onChanged: _setHealthDocumentAccess,
    loading: _savingHealthDocuments,
    isSensitive: true,
  ),
  SizedBox(height: 12),
  _PermissionCard(
    key: ValueKey('care-permission-health-record'),
              icon: Icons.folder_shared_rounded,
              accent: Color(0xFF6C74D9),
              softColor: Color(0xFFF0F1FF),
              title: LifeMateRuntimeLocale.select(
                fa: LifeMateRuntimeLocale.select(
                  fa: 'مشاهده و ویرایش پرونده سلامت',
                  en: "View and edit health records",
                ),
                en: "View and edit health records",
              ),
              subtitle: LifeMateRuntimeLocale.select(
                fa: LifeMateRuntimeLocale.select(
                  fa: 'اجازه مشاهده و مدیریت درمان‌ها؛ شامل افزودن، ویرایش و حذف دارو، ویزیت و تزریق.',
                  en: "Permission to view and manage treatments; including adding, editing and deleting drugs, visits and injections.",
                ),
                en: "Permission to view and manage treatments; including adding, editing and deleting drugs, visits and injections.",
              ),
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
      gradient: LinearGradient(
        begin: Alignment.topRight,
        end: Alignment.bottomLeft,
        colors: [Color(0xFFEAF7F2), Color(0xFFF3F5FF)],
      ),
      borderRadius: BorderRadius.circular(26),
      border: Border.all(color: Colors.white),
      boxShadow: [
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
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
          ),
          child: Icon(Icons.shield_outlined, color: Color(0xFF397B70)),
        ),
        SizedBox(width: 13),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                LifeMateRuntimeLocale.select(
                  fa: LifeMateRuntimeLocale.select(
                    fa: 'کنترل دسترسی دست شماست',
                    en: "Access control is yours",
                  ),
                  en: "Access control is yours",
                ),
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: AppColors.textPrimary,
                ),
              ),
              SizedBox(height: 6),
              Text(
                LifeMateRuntimeLocale.select(
                  fa: LifeMateRuntimeLocale.select(
                    fa: 'هر دسترسی برای $name مستقل فعال می‌شود. هر زمان بخواهید می‌توانید آن را خاموش کنید؛ قطع رابطه نیز همه دسترسی‌ها را متوقف می‌کند.',
                    en: "Each access is enabled for an independent $name. You can turn it off whenever you want; Disconnecting also stops all access.",
                  ),
                  en: "Each access is enabled for an independent $name. You can turn it off whenever you want; Disconnecting also stops all access.",
                ),
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
      title: Row(
        children: [
          CircleAvatar(
            backgroundColor: Color(0xFFFFF0E6),
            child: Icon(Icons.warning_amber_rounded, color: Color(0xFFD8752F)),
          ),
          SizedBox(width: 11),
          Expanded(
            child: Text(
              LifeMateRuntimeLocale.select(
                fa: LifeMateRuntimeLocale.select(
                  fa: 'تأیید دسترسی حساس',
                  en: "Sensitive access authentication",
                ),
                en: "Sensitive access authentication",
              ),
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
      content: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 430, maxHeight: 520),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                LifeMateRuntimeLocale.select(
                  fa: LifeMateRuntimeLocale.select(
                    fa: 'با فعال‌کردن «مشاهده و ویرایش پرونده سلامت»، شما با آگاهی به ${widget.caregiverName} اجازه می‌دهید برنامه‌های درمانی شما را مدیریت کند.',
                    en: "By enabling View and Edit Health Record, you are knowingly allowing ${widget.caregiverName} to manage your treatment plans.",
                  ),
                  en: "By enabling View and Edit Health Record, you are knowingly allowing ${widget.caregiverName} to manage your treatment plans.",
                ),
                style: TextStyle(height: 1.65),
              ),
              SizedBox(height: 14),
              _ConsentPoint(
                icon: Icons.visibility_outlined,
                text: LifeMateRuntimeLocale.select(
                  fa: LifeMateRuntimeLocale.select(
                    fa: 'مراقب می‌تواند داروها، ویزیت‌ها و تزریق‌های ثبت‌شده را مشاهده کند.',
                    en: "The caregiver can view recorded medications, visits, and injections.",
                  ),
                  en: "The caregiver can view recorded medications, visits, and injections.",
                ),
              ),
              _ConsentPoint(
                icon: Icons.edit_note_rounded,
                text: LifeMateRuntimeLocale.select(
                  fa: LifeMateRuntimeLocale.select(
                    fa: 'مراقب می‌تواند درمان جدید اضافه کند یا اطلاعات درمان‌های موجود را ویرایش کند.',
                    en: "Caregiver can add new treatment or edit existing treatment information.",
                  ),
                  en: "Caregiver can add new treatment or edit existing treatment information.",
                ),
              ),
              _ConsentPoint(
                icon: Icons.delete_outline_rounded,
                text: LifeMateRuntimeLocale.select(
                  fa: LifeMateRuntimeLocale.select(
                    fa: 'مراقب می‌تواند درمان را حذف کند؛ حذف در سیستم به‌صورت توقف/بایگانی امن ثبت می‌شود.',
                    en: "Caregiver can remove treatment; Deletion is recorded in the system as a safe stop/archive.",
                  ),
                  en: "Caregiver can remove treatment; Deletion is recorded in the system as a safe stop/archive.",
                ),
              ),
              _ConsentPoint(
                icon: Icons.notifications_active_outlined,
                text: LifeMateRuntimeLocale.select(
                  fa: LifeMateRuntimeLocale.select(
                    fa: 'این تغییرات می‌توانند روی برنامه روزانه، یادآورها و اطلاعاتی که در WellMate و CareMate می‌بینید اثر بگذارند.',
                    en: "These changes can affect the daily schedule, reminders, and information you see in WellMate and CareMate.",
                  ),
                  en: "These changes can affect the daily schedule, reminders, and information you see in WellMate and CareMate.",
                ),
              ),
              SizedBox(height: 10),
              Container(
                padding: EdgeInsets.all(13),
                decoration: BoxDecoration(
                  color: Color(0xFFFFF7E8),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  LifeMateRuntimeLocale.select(
                    fa: LifeMateRuntimeLocale.select(
                      fa: 'این دسترسی جایگزین نظر پزشک نیست. مسئولیت تصمیم برای اعطای این دسترسی و بررسی صحت تغییرات ثبت‌شده بر عهده شماست. می‌توانید هر زمان این دسترسی را غیرفعال کنید. برای امنیت، اعطا، لغو و تغییرات درمانی ثبت و قابل پیگیری هستند.',
                      en: "This access is not a substitute for a doctor's opinion. It is your responsibility to decide whether to grant this access and to verify the correctness of the recorded changes. You can disable this access at any time. For security, grants, cancellations and treatment changes are recorded and trackable.",
                    ),
                    en: "This access is not a substitute for a doctor's opinion. It is your responsibility to decide whether to grant this access and to verify the correctness of the recorded changes. You can disable this access at any time. For security, grants, cancellations and treatment changes are recorded and trackable.",
                  ),
                  style: TextStyle(
                    height: 1.65,
                    fontSize: 11.5,
                    color: Color(0xFF74552A),
                  ),
                ),
              ),
              SizedBox(height: 8),
              CheckboxListTile(
                key: ValueKey('health-record-consent-checkbox'),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: _accepted,
                onChanged: (value) =>
                    setState(() => _accepted = value ?? false),
                title: Text(
                  LifeMateRuntimeLocale.select(
                    fa: LifeMateRuntimeLocale.select(
                      fa: 'متوجه محدوده این دسترسی و امکان تغییر پرونده درمانی توسط مراقب هستم و با فعال‌سازی آن موافقم.',
                      en: "I understand the scope of this access and the possibility of changing the medical file by the caregiver, and I agree with its activation.",
                    ),
                    en: "I understand the scope of this access and the possibility of changing the medical file by the caregiver, and I agree with its activation.",
                  ),
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
          child: Text(
            LifeMateRuntimeLocale.select(
              fa: LifeMateRuntimeLocale.select(fa: 'انصراف', en: "opt out"),
              en: "opt out",
            ),
          ),
        ),
        FilledButton.icon(
          key: ValueKey('confirm-health-record-access'),
          onPressed: _accepted ? () => Navigator.pop(context, true) : null,
          icon: Icon(Icons.lock_open_rounded),
          label: Text(
            LifeMateRuntimeLocale.select(
              fa: LifeMateRuntimeLocale.select(
                fa: 'تأیید و فعال‌سازی',
                en: "Verification and activation",
              ),
              en: "Verification and activation",
            ),
          ),
          style: FilledButton.styleFrom(backgroundColor: Color(0xFF626BD1)),
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
          child: Text(text, style: const TextStyle(height: 1.55, fontSize: 12)),
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
    padding: EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Color(0xFFFFF0F1),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: Color(0xFFFFD6DA)),
    ),
    child: Row(
      children: [
        Icon(Icons.cloud_off_rounded, color: Color(0xFFD95D66)),
        SizedBox(width: 9),
        Expanded(child: Text(message)),
        TextButton(
          onPressed: onRetry,
          child: Text(
            LifeMateRuntimeLocale.select(
              fa: LifeMateRuntimeLocale.select(
                fa: 'تلاش دوباره',
                en: "Try again",
              ),
              en: "Try again",
            ),
          ),
        ),
      ],
    ),
  );
}

class _SecurityFooter extends StatelessWidget {
  const _SecurityFooter();

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.symmetric(horizontal: 5),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          Icons.info_outline_rounded,
          size: 18,
          color: AppColors.textSecondary,
        ),
        SizedBox(width: 8),
        Expanded(
          child: Text(
            LifeMateRuntimeLocale.select(
              fa: LifeMateRuntimeLocale.select(
                fa: 'دسترسی مدیریت پرونده فقط برای همان مراقب و همان رابطه فعال است و با خاموش‌کردن گزینه یا قطع رابطه متوقف می‌شود.',
                en: "Case management access is only active for the same carer and the same relationship and is stopped by turning off the option or disconnecting the relationship.",
              ),
              en: "Case management access is only active for the same carer and the same relationship and is stopped by turning off the option or disconnecting the relationship.",
            ),
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
