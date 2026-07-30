// ignore_for_file: deprecated_member_use

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lifemate_client/lifemate_client.dart';
import 'package:provider/provider.dart';

import '../core/constants/app_colors.dart';
import '../core/localization/locale_provider.dart';
import '../core/utils/string_extensions.dart';
import '../widgets/caremate_bottom_nav.dart';
import '../widgets/custom_app_header.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  bool _loading = true;
  bool _accepting = false;
  String? _error;
  String? _currentUserId;
  String? _selectedRelationshipId;
  Map<String, dynamic> _currentUser = const {};
  List<Map<String, dynamic>> _relationships = const [];
  List<Map<String, dynamic>> _doses = const [];
  Timer? _clockTimer;

  @override
  void initState() {
    super.initState();
    _refresh();
    _clockTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final api = context.read<LifeMateApiClient>();
      final results = await Future.wait([
        api.getCurrentUser(),
        api.getCareRelationships(),
      ]);
      final currentUser = results[0] as Map<String, dynamic>;
      final relationships = results[1] as List<Map<String, dynamic>>;
      final user = currentUser['user'] as Map<String, dynamic>? ?? const {};
      final currentUserId = user['id']?.toString();
      final caregiverRelationships = relationships
          .where(
            (relationship) =>
                relationship['status']?.toString() == 'active' &&
                relationship['caregiverUserId']?.toString() == currentUserId,
          )
          .toList(growable: false);

      var selectedId = _selectedRelationshipId;
      if (!caregiverRelationships.any(
        (relationship) => relationship['id']?.toString() == selectedId,
      )) {
        selectedId = caregiverRelationships.isEmpty
            ? null
            : caregiverRelationships.first['id']?.toString();
      }

      if (!mounted) return;
      setState(() {
        _currentUser = currentUser;
        _currentUserId = currentUserId;
        _relationships = caregiverRelationships;
        _selectedRelationshipId = selectedId;
      });
      await _loadSelectedDoses();
    } on LifeMateApiException catch (error) {
      _setError(_friendlyApiError(error));
    } catch (error) {
      debugPrint('CareMate refresh failed: $error');
      _setError('اطلاعات مراقبت دریافت نشد. اتصال اینترنت را بررسی کنید.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadSelectedDoses() async {
    final selected = _selectedRelationship;
    if (selected == null) {
      if (mounted) setState(() => _doses = const []);
      return;
    }

    final today = DateTime.now();
    final doses = await context
        .read<LifeMateApiClient>()
        .getCareRecipientDoseOccurrences(
          patientUserId: selected['patientUserId'].toString(),
          fromDate: today,
          toDate: today,
        );
    doses.sort((a, b) => _doseTime(a).compareTo(_doseTime(b)));
    if (mounted) setState(() => _doses = doses);
  }

  Map<String, dynamic>? get _selectedRelationship {
    for (final relationship in _relationships) {
      if (relationship['id']?.toString() == _selectedRelationshipId) {
        return relationship;
      }
    }
    return null;
  }

  void _setError(String message) {
    if (!mounted) return;
    setState(() {
      _error = message;
      _loading = false;
    });
  }

  Future<void> _selectRelationship(String? relationshipId) async {
    setState(() {
      _selectedRelationshipId = relationshipId;
      _loading = true;
      _error = null;
    });
    try {
      await _loadSelectedDoses();
    } on LifeMateApiException catch (error) {
      _setError(_friendlyApiError(error));
    } catch (error) {
      debugPrint('CareMate patient switch failed: $error');
      _setError('وضعیت بیمار دریافت نشد.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _showAcceptInvitation() async {
    final tokenController = TextEditingController();
    var confirmed = false;
    final token = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          title: const Row(
            children: [
              Icon(Icons.family_restroom_rounded,
                  color: AppColors.primaryBlue),
              SizedBox(width: 10),
              Expanded(child: Text('پذیرش دعوت مراقبت')),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'کد دعوت را فقط زمانی وارد کنید که بیمار آن را مستقیماً برای شما فرستاده باشد.',
              ),
              const SizedBox(height: 16),
              TextField(
                controller: tokenController,
                textDirection: TextDirection.ltr,
                autocorrect: false,
                onChanged: (_) => setDialogState(() {}),
                decoration: InputDecoration(
                  labelText: 'کد دعوت',
                  prefixIcon: const Icon(Icons.vpn_key_rounded),
                  filled: true,
                  fillColor: const Color(0xFFF6F9FD),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: confirmed,
                onChanged: (value) =>
                    setDialogState(() => confirmed = value ?? false),
                title: const Text(
                  'می‌پذیرم اطلاعات این بیمار را فقط در محدوده مراقبت مجاز مشاهده کنم.',
                ),
                controlAffinity: ListTileControlAffinity.leading,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('انصراف'),
            ),
            FilledButton(
              onPressed: confirmed && tokenController.text.trim().isNotEmpty
                  ? () => Navigator.pop(
                        dialogContext,
                        tokenController.text.trim(),
                      )
                  : null,
              child: const Text('پذیرش امن'),
            ),
          ],
        ),
      ),
    );
    tokenController.dispose();
    if (token == null || !mounted) return;

    setState(() => _accepting = true);
    try {
      await context
          .read<LifeMateApiClient>()
          .acceptCareInvitation(token: token);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('دعوت مراقبت با موفقیت پذیرفته شد.')),
      );
      await _refresh();
    } on LifeMateApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_friendlyApiError(error)),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _accepting = false);
    }
  }

  Future<void> _revokeSelectedRelationship() async {
    final relationship = _selectedRelationship;
    if (relationship == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
        title: const Text('قطع دسترسی مراقبت؟'),
        content: const Text(
          'پس از قطع دسترسی، دیگر وضعیت داروهای این بیمار را مشاهده نمی‌کنید. بیمار می‌تواند بعداً دعوت جدیدی بسازد.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('انصراف'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('قطع دسترسی'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _loading = true);
    try {
      await context.read<LifeMateApiClient>().revokeCareRelationship(
            relationshipId: relationship['id'].toString(),
          );
      await _refresh();
    } on LifeMateApiException catch (error) {
      _setError(_friendlyApiError(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showComingSoon(String feature) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$feature در دست توسعه است و در این نسخه غیرفعال شده.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _onNavigationTap(int index) {
    if (index == 4) return;
    const labels = ['تقویم مراقبت', 'تغییر پروفایل', 'مدیریت درمان', 'مراقبت خانواده'];
    _showComingSoon(labels[index]);
  }

  void _showDoseAlerts() {
    final alertDoses = _doses
        .where((dose) =>
            dose['status']?.toString() == 'missed' ||
            dose['status']?.toString() == 'skipped')
        .toList(growable: false);
    if (alertDoses.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('در حال حاضر هشدار دارویی فعالی وجود ندارد.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        padding: const EdgeInsets.fromLTRB(24, 18, 24, 28),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 42,
                  height: 5,
                  decoration: BoxDecoration(
                    color: Colors.black12,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'هشدارهای دارویی امروز',
                style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 14),
              ...alertDoses.map(
                (dose) => _DoseListTile(dose: dose, compact: true),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showAccountSheet() {
    final user = _currentUser['user'] as Map<String, dynamic>? ?? const {};
    final profile =
        _currentUser['profile'] as Map<String, dynamic>? ?? const {};
    final displayName = profile['displayName']?.toString().trim();
    final email = user['email']?.toString() ?? '';

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.fromLTRB(24, 18, 24, 28),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: AppColors.background,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: AppColors.primaryBlue.withOpacity(0.15),
                    width: 2,
                  ),
                ),
                child: const Icon(
                  Icons.person_rounded,
                  size: 38,
                  color: AppColors.primaryBlue,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                displayName == null || displayName.isEmpty
                    ? 'کاربر CareMate'
                    : displayName,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (email.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  email,
                  textDirection: TextDirection.ltr,
                  style: const TextStyle(color: AppColors.secondaryText),
                ),
              ],
              const SizedBox(height: 22),
              ListTile(
                leading: const Icon(Icons.manage_accounts_outlined,
                    color: AppColors.primaryBlue),
                title: const Text('ویرایش اطلاعات حساب'),
                subtitle: const Text('در دست توسعه'),
                enabled: false,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                tileColor: const Color(0xFFF6F9FD),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    Navigator.pop(context);
                    await LifeMateAuth.signOut();
                  },
                  icon: const Icon(Icons.logout_rounded),
                  label: const Text('خروج از حساب'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final localeProvider = context.watch<LocaleProvider>();
    final isPersian = localeProvider.locale.languageCode == 'fa';
    final mainFont = TextStyle(
      fontFamily: isPersian ? 'Vazir' : 'Poppins',
      color: AppColors.primaryText,
    );
    final selected = _selectedRelationship;
    final patientName =
        selected?['patientDisplayName']?.toString().trim().isNotEmpty == true
            ? selected!['patientDisplayName'].toString()
            : 'فرد تحت مراقبت';
    final taken = _doses.where((dose) => dose['status'] == 'taken').length;
    final skipped = _doses.where((dose) => dose['status'] == 'skipped').length;
    final missed = _doses.where((dose) => dose['status'] == 'missed').length;
    final alerts = skipped + missed;

    return Scaffold(
      backgroundColor: AppColors.background,
      extendBody: true,
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.only(bottom: 120),
            children: [
              CustomAppHeader(
                onNotificationTap: _showDoseAlerts,
                onProfileTap: _showAccountSheet,
                onSignOutTap: LifeMateAuth.signOut,
                showNotificationDot: alerts > 0,
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 10, 24, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_error != null) ...[
                      _ErrorBanner(message: _error!, onRetry: _refresh),
                      const SizedBox(height: 16),
                    ],
                    _CareRecipientSelector(
                      relationships: _relationships,
                      selectedRelationshipId: _selectedRelationshipId,
                      loading: _loading,
                      accepting: _accepting,
                      onChanged: _selectRelationship,
                      onAcceptInvitation: _showAcceptInvitation,
                      font: mainFont,
                    ),
                    const SizedBox(height: 24),
                    if (_loading && _currentUserId == null)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 80),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else if (_relationships.isEmpty)
                      _EmptyCareState(
                        onAccept: _showAcceptInvitation,
                        font: mainFont,
                      )
                    else ...[
                      _TreatmentQueueCard(
                        doses: _doses,
                        patientName: patientName,
                        loading: _loading,
                        isPersian: isPersian,
                        font: mainFont,
                      ),
                      const SizedBox(height: 24),
                      Row(
                        children: [
                          Expanded(
                            child: _FeaturePreviewCard(
                              title: 'حال خانواده',
                              description: 'ثبت حال روحی و ارتباط روزانه',
                              icon: Icons.favorite_rounded,
                              accent: const Color(0xFFE598D8),
                              background: const Color(0xFFFFF3FC),
                              onTap: () => _showComingSoon('حال خانواده'),
                              font: mainFont,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: _FeaturePreviewCard(
                              title: 'سلامت خانواده',
                              description: 'علائم حیاتی و گزارش روند سلامت',
                              icon: Icons.monitor_heart_rounded,
                              accent: const Color(0xFF5BA7E8),
                              background: const Color(0xFFF0F8FF),
                              onTap: () => _showComingSoon('سلامت خانواده'),
                              font: mainFont,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      _SectionTitle(
                        title: 'خلاصه امروز',
                        actionLabel: 'قطع دسترسی',
                        onAction: _revokeSelectedRelationship,
                        font: mainFont,
                      ),
                      const SizedBox(height: 12),
                      _ProgressSummaryCard(
                        total: _doses.length,
                        taken: taken,
                        skipped: skipped,
                        missed: missed,
                        isPersian: isPersian,
                        font: mainFont,
                      ),
                      const SizedBox(height: 24),
                      _SectionTitle(
                        title: 'برنامه دارویی امروز',
                        font: mainFont,
                      ),
                      const SizedBox(height: 12),
                      if (_loading)
                        const Padding(
                          padding: EdgeInsets.all(32),
                          child: Center(child: CircularProgressIndicator()),
                        )
                      else if (_doses.isEmpty)
                        const _NoDosesState()
                      else
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: AppColors.softDecoration(),
                          child: Column(
                            children: _doses
                                .map((dose) => _DoseListTile(dose: dose))
                                .toList(growable: false),
                          ),
                        ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: CareMateBottomNav(
        currentIndex: 4,
        onTap: _onNavigationTap,
      ),
    );
  }

  static String _friendlyApiError(LifeMateApiException error) {
    switch (error.code) {
      case 'care_access_denied':
        return 'دسترسی مراقبت لغو شده است. فهرست را تازه‌سازی کنید.';
      case 'invitation_contact_mismatch':
        return 'این دعوت برای حساب دیگری صادر شده است.';
      case 'invitation_expired':
        return 'مهلت این دعوت تمام شده است؛ از بیمار دعوت جدید بخواهید.';
      case 'invitation_not_found':
        return 'کد دعوت معتبر نیست.';
      default:
        return error.isUnauthorized
            ? 'نشست شما منقضی شده است. دوباره وارد شوید.'
            : 'درخواست انجام نشد. دوباره تلاش کنید.';
    }
  }

  static String _doseTime(Map<String, dynamic> dose) {
    final raw = dose['scheduledLocalTime']?.toString() ?? '--:--';
    return raw.length >= 5 ? raw.substring(0, 5) : raw;
  }
}

class _CareRecipientSelector extends StatelessWidget {
  const _CareRecipientSelector({
    required this.relationships,
    required this.selectedRelationshipId,
    required this.loading,
    required this.accepting,
    required this.onChanged,
    required this.onAcceptInvitation,
    required this.font,
  });

  final List<Map<String, dynamic>> relationships;
  final String? selectedRelationshipId;
  final bool loading;
  final bool accepting;
  final ValueChanged<String?> onChanged;
  final VoidCallback onAcceptInvitation;
  final TextStyle font;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.92),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryBlue.withOpacity(0.07),
            blurRadius: 18,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: const BoxDecoration(
              color: Color(0xFFEAF4FF),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.family_restroom_rounded,
              color: AppColors.primaryBlue,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: relationships.isEmpty
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'خانواده من',
                        style: font.copyWith(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'هنوز فردی متصل نیست',
                        style: font.copyWith(
                          fontSize: 12,
                          color: AppColors.secondaryText,
                        ),
                      ),
                    ],
                  )
                : DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: selectedRelationshipId,
                      isExpanded: true,
                      borderRadius: BorderRadius.circular(18),
                      icon: const Icon(Icons.keyboard_arrow_down_rounded),
                      items: relationships
                          .map(
                            (relationship) => DropdownMenuItem<String>(
                              value: relationship['id'].toString(),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    relationship['patientDisplayName']
                                            ?.toString() ??
                                        'فرد تحت مراقبت',
                                    overflow: TextOverflow.ellipsis,
                                    style: font.copyWith(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  Text(
                                    'دسترسی مراقبتی فعال',
                                    style: font.copyWith(
                                      fontSize: 11,
                                      color: AppColors.secondaryText,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                          .toList(growable: false),
                      onChanged: loading ? null : onChanged,
                    ),
                  ),
          ),
          const SizedBox(width: 10),
          IconButton.filledTonal(
            tooltip: 'افزودن فرد با کد دعوت',
            onPressed: accepting ? null : onAcceptInvitation,
            icon: accepting
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.person_add_alt_1_rounded),
          ),
        ],
      ),
    );
  }
}

class _TreatmentQueueCard extends StatelessWidget {
  const _TreatmentQueueCard({
    required this.doses,
    required this.patientName,
    required this.loading,
    required this.isPersian,
    required this.font,
  });

  final List<Map<String, dynamic>> doses;
  final String patientName;
  final bool loading;
  final bool isPersian;
  final TextStyle font;

  @override
  Widget build(BuildContext context) {
    final pending = doses
        .where((dose) => dose['status']?.toString() == 'scheduled')
        .toList(growable: false);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryBlue.withOpacity(0.06),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: loading
          ? const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator()),
            )
          : pending.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEAF8F0),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.task_alt_rounded,
                          color: Color(0xFF36A269),
                          size: 32,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'درمان در انتظار دیگری برای امروز نیست',
                        textAlign: TextAlign.center,
                        style: font.copyWith(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF267B50),
                        ),
                      ),
                    ],
                  ),
                )
              : Column(
                  children: [
                    _TreatmentRow(
                      label: 'درمان فعلی',
                      dose: pending.first,
                      patientName: patientName,
                      current: true,
                      isPersian: isPersian,
                      font: font,
                    ),
                    if (pending.length > 1) ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: Divider(color: Colors.grey.shade200, height: 1),
                      ),
                      _TreatmentRow(
                        label: 'درمان بعدی',
                        dose: pending[1],
                        patientName: patientName,
                        current: false,
                        isPersian: isPersian,
                        font: font,
                      ),
                    ],
                  ],
                ),
    );
  }
}

class _TreatmentRow extends StatelessWidget {
  const _TreatmentRow({
    required this.label,
    required this.dose,
    required this.patientName,
    required this.current,
    required this.isPersian,
    required this.font,
  });

  final String label;
  final Map<String, dynamic> dose;
  final String patientName;
  final bool current;
  final bool isPersian;
  final TextStyle font;

  @override
  Widget build(BuildContext context) {
    final rawTime = dose['scheduledLocalTime']?.toString() ?? '--:--';
    final time = rawTime.length >= 5 ? rawTime.substring(0, 5) : rawTime;
    final medication = dose['medicationName']?.toString() ?? 'دارو';
    final doseText = dose['doseText']?.toString() ?? '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: font.copyWith(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: AppColors.secondaryText,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            CircleAvatar(
              radius: 25,
              backgroundColor: const Color(0xFFEAF4FF),
              child: Text(
                patientName.characters.first,
                style: font.copyWith(
                  color: AppColors.primaryBlue,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    patientName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: font.copyWith(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    doseText.isEmpty ? medication : '$medication • $doseText',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: font.copyWith(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (current) ...[
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFEEF0),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      _timeLeft(time).toPersianDigit(isPersian),
                      style: font.copyWith(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: Colors.red.shade400,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                ],
                Row(
                  children: [
                    Icon(
                      Icons.access_time_rounded,
                      size: 14,
                      color: Colors.grey.shade400,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      time.toPersianDigit(isPersian),
                      textDirection: TextDirection.ltr,
                      style: font.copyWith(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  static String _timeLeft(String targetTime) {
    try {
      final now = DateTime.now();
      final parts = targetTime.split(':');
      final target = DateTime(
        now.year,
        now.month,
        now.day,
        int.parse(parts[0]),
        int.parse(parts[1]),
      );
      final difference = target.difference(now);
      if (difference.isNegative) return 'زمانش رسیده';
      if (difference.inHours > 0) {
        return '${difference.inHours} ساعت و ${difference.inMinutes % 60} دقیقه';
      }
      return '${difference.inMinutes} دقیقه';
    } catch (_) {
      return '-';
    }
  }
}

class _FeaturePreviewCard extends StatelessWidget {
  const _FeaturePreviewCard({
    required this.title,
    required this.description,
    required this.icon,
    required this.accent,
    required this.background,
    required this.onTap,
    required this.font,
  });

  final String title;
  final String description;
  final IconData icon;
  final Color accent;
  final Color background;
  final VoidCallback onTap;
  final TextStyle font;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Container(
          height: 190,
          padding: const EdgeInsets.all(16),
          decoration: AppColors.softDecoration(color: background),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.78),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: accent),
              ),
              const SizedBox(height: 14),
              Text(
                title,
                style: font.copyWith(
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 7),
              Expanded(
                child: Text(
                  description,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: font.copyWith(
                    fontSize: 11,
                    height: 1.45,
                    color: Colors.grey.shade600,
                  ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.8),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'در دست توسعه',
                  style: font.copyWith(
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    color: accent,
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

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({
    required this.title,
    required this.font,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final TextStyle font;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: font.copyWith(fontSize: 17, fontWeight: FontWeight.w900),
          ),
        ),
        if (actionLabel != null && onAction != null)
          TextButton.icon(
            onPressed: onAction,
            icon: const Icon(Icons.link_off_rounded, size: 17),
            label: Text(actionLabel!),
          ),
      ],
    );
  }
}

class _ProgressSummaryCard extends StatelessWidget {
  const _ProgressSummaryCard({
    required this.total,
    required this.taken,
    required this.skipped,
    required this.missed,
    required this.isPersian,
    required this.font,
  });

  final int total;
  final int taken;
  final int skipped;
  final int missed;
  final bool isPersian;
  final TextStyle font;

  @override
  Widget build(BuildContext context) {
    final progress = total == 0 ? 0.0 : taken / total;
    final percent = '${(progress * 100).round()}٪'.toPersianDigit(isPersian);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: AppColors.softDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                percent,
                style: font.copyWith(
                  fontSize: 21,
                  fontWeight: FontWeight.w900,
                  color: const Color(0xFF2A8B5A),
                ),
              ),
              const Spacer(),
              Text(
                '$taken از $total دوز مصرف شده'.toPersianDigit(isPersian),
                style: font.copyWith(
                  fontSize: 12,
                  color: AppColors.secondaryText,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 12,
              backgroundColor: const Color(0xFFE7EDF3),
              valueColor:
                  const AlwaysStoppedAnimation<Color>(Color(0xFF6FCF97)),
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _StatusPill(
                label: 'مصرف‌شده $taken'.toPersianDigit(isPersian),
                color: const Color(0xFF36A269),
              ),
              _StatusPill(
                label: 'مصرف‌نشده $skipped'.toPersianDigit(isPersian),
                color: Colors.orange,
              ),
              _StatusPill(
                label: 'فراموش‌شده $missed'.toPersianDigit(isPersian),
                color: Colors.redAccent,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _DoseListTile extends StatelessWidget {
  const _DoseListTile({required this.dose, this.compact = false});

  final Map<String, dynamic> dose;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final status = dose['status']?.toString() ?? 'scheduled';
    String label;
    IconData icon;
    Color color;
    switch (status) {
      case 'taken':
        label = 'مصرف شده';
        icon = Icons.check_circle_rounded;
        color = const Color(0xFF36A269);
      case 'skipped':
        label = 'مصرف نشده';
        icon = Icons.remove_circle_rounded;
        color = Colors.orange;
      case 'missed':
        label = 'فراموش‌شده';
        icon = Icons.error_rounded;
        color = Colors.redAccent;
      default:
        label = 'در انتظار';
        icon = Icons.schedule_rounded;
        color = AppColors.primaryBlue;
    }
    final rawTime = dose['scheduledLocalTime']?.toString() ?? '--:--';
    final time = rawTime.length >= 5 ? rawTime.substring(0, 5) : rawTime;

    return Container(
      margin: EdgeInsets.only(bottom: compact ? 8 : 5),
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 10 : 8,
        vertical: compact ? 8 : 5,
      ),
      decoration: BoxDecoration(
        color: compact ? color.withOpacity(0.05) : Colors.transparent,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  dose['medicationName']?.toString() ?? 'دارو',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 3),
                Text(
                  '${dose['doseText'] ?? ''} • $time',
                  textDirection: TextDirection.rtl,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyCareState extends StatelessWidget {
  const _EmptyCareState({required this.onAccept, required this.font});

  final VoidCallback onAccept;
  final TextStyle font;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 38, 24, 38),
      decoration: AppColors.softDecoration(),
      child: Column(
        children: [
          Container(
            width: 90,
            height: 90,
            decoration: const BoxDecoration(
              color: Color(0xFFEAF4FF),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.health_and_safety_outlined,
              size: 50,
              color: AppColors.primaryBlue,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'هنوز فردی به مراقبت شما متصل نیست',
            textAlign: TextAlign.center,
            style: font.copyWith(fontSize: 19, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 9),
          Text(
            'کد دعوتی را که بیمار در WellMate ساخته است وارد کنید تا اطلاعات مجاز مراقبتی نمایش داده شود.',
            textAlign: TextAlign.center,
            style: font.copyWith(
              fontSize: 13,
              height: 1.55,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: onAccept,
            icon: const Icon(Icons.vpn_key_rounded),
            label: const Text('واردکردن کد دعوت'),
          ),
        ],
      ),
    );
  }
}

class _NoDosesState extends StatelessWidget {
  const _NoDosesState();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(28),
      decoration: AppColors.softDecoration(),
      child: const Column(
        children: [
          Icon(
            Icons.event_available_rounded,
            size: 48,
            color: AppColors.primaryBlue,
          ),
          SizedBox(height: 10),
          Text(
            'برای امروز دوز فعالی ثبت نشده است.',
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF1F2),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.red.withOpacity(0.12)),
      ),
      child: Row(
        children: [
          const Icon(Icons.cloud_off_rounded, color: Colors.redAccent),
          const SizedBox(width: 10),
          Expanded(child: Text(message)),
          TextButton(onPressed: onRetry, child: const Text('تلاش دوباره')),
        ],
      ),
    );
  }
}
