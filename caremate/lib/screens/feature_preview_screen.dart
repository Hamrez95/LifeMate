// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:lifemate_client/lifemate_client.dart';
import 'package:provider/provider.dart';

import '../core/constants/app_colors.dart';
import '../widgets/care_profile_mask_selector.dart';
import '../widgets/caremate_bottom_nav.dart';
import '../widgets/custom_app_header.dart';
import 'calendar/calendar_screen.dart';
import 'dashboard_screen.dart';

/// Complete implementations of the three original CareMate navigation
/// destinations. Data that exists in the healthcare API is live; actions that
/// have no safe caregiver contract remain visible and explicitly disabled.
class CareMateFeaturePreviewScreen extends StatefulWidget {
  const CareMateFeaturePreviewScreen({
    required this.initialIndex,
    super.key,
    this.refreshToken = 0,
    this.onNavigationTap,
  }) : assert(initialIndex >= 1 && initialIndex <= 3);

  final int initialIndex;
  final int refreshToken;
  final ValueChanged<int>? onNavigationTap;

  @override
  State<CareMateFeaturePreviewScreen> createState() =>
      _CareMateFeaturePreviewScreenState();
}

class _CareMateFeaturePreviewScreenState
    extends State<CareMateFeaturePreviewScreen> {
  late int _currentIndex;
  bool _loading = true;
  bool _accepting = false;
  String? _error;
  String? _currentUserId;
  String? _selectedRelationshipId;
  List<Map<String, dynamic>> _relationships = const [];
  List<Map<String, dynamic>> _doses = const [];

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _refresh();
  }

  @override
  void didUpdateWidget(covariant CareMateFeaturePreviewScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshToken != widget.refreshToken) {
      _refresh();
    }
  }

  Map<String, dynamic>? get _selectedRelationship {
    for (final relationship in _relationships) {
      if (relationship['id']?.toString() == _selectedRelationshipId) {
        return relationship;
      }
    }
    return null;
  }

  String _relationshipName(Map<String, dynamic> relationship) {
    final name = relationship['patientDisplayName']?.toString().trim();
    return name == null || name.isEmpty ? 'فرد تحت مراقبت' : name;
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
      final values = await Future.wait([
        api.getCurrentUser(),
        api.getCareRelationships(),
      ]);
      final me = values[0] as Map<String, dynamic>;
      final allRelationships = values[1] as List<Map<String, dynamic>>;
      final user = me['user'] as Map<String, dynamic>? ?? const {};
      final userId = user['id']?.toString();
      final relationships = allRelationships
          .where(
            (item) =>
                item['status']?.toString() == 'active' &&
                item['caregiverUserId']?.toString() == userId,
          )
          .toList(growable: false);

      var selectedId = _selectedRelationshipId;
      if (!relationships.any((item) => item['id']?.toString() == selectedId)) {
        selectedId = relationships.isEmpty
            ? null
            : relationships.first['id']?.toString();
      }
      if (!mounted) return;
      setState(() {
        _currentUserId = userId;
        _relationships = relationships;
        _selectedRelationshipId = selectedId;
      });
      await _loadSelectedDoses();
    } on LifeMateApiException catch (error) {
      _setError(_friendlyApiError(error));
    } catch (error) {
      debugPrint('CareMate feature load failed: $error');
      _setError('اطلاعات مراقبت دریافت نشد. اتصال اینترنت را بررسی کنید.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadSelectedDoses() async {
    final relationship = _selectedRelationship;
    if (relationship == null) {
      if (mounted) setState(() => _doses = const []);
      return;
    }
    final now = DateTime.now();
    final doses = await context
        .read<LifeMateApiClient>()
        .getCareRecipientDoseOccurrences(
          patientUserId: relationship['patientUserId'].toString(),
          fromDate: now,
          toDate: now,
        );
    doses.sort((a, b) => _doseTime(a).compareTo(_doseTime(b)));
    if (mounted) setState(() => _doses = doses);
  }

  void _setError(String message) {
    if (!mounted) return;
    setState(() {
      _error = message;
      _loading = false;
    });
  }

  Future<void> _selectRelationship(String? relationshipId) async {
    if (relationshipId == null || relationshipId == _selectedRelationshipId) {
      return;
    }
    setState(() {
      _selectedRelationshipId = relationshipId;
      _doses = const [];
      _loading = true;
      _error = null;
    });
    try {
      await _loadSelectedDoses();
    } on LifeMateApiException catch (error) {
      _setError(_friendlyApiError(error));
    } catch (error) {
      debugPrint('CareMate profile switch failed: $error');
      _setError('وضعیت فرد تحت مراقبت دریافت نشد.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _showAcceptInvitation() async {
    final controller = TextEditingController();
    var consent = false;
    final token = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          title: const Text('پذیرش دعوت مراقبت'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'کدی را وارد کنید که بیمار مستقیماً برای شما ارسال کرده است.',
                style: TextStyle(height: 1.6),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: controller,
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
                value: consent,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                onChanged: (value) =>
                    setDialogState(() => consent = value ?? false),
                title: const Text(
                  'محدوده دسترسی مراقبتی و حریم خصوصی بیمار را می‌پذیرم.',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('انصراف'),
            ),
            FilledButton(
              onPressed: consent && controller.text.trim().isNotEmpty
                  ? () => Navigator.pop(dialogContext, controller.text.trim())
                  : null,
              child: const Text('پذیرش امن'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (token == null || !mounted) return;

    setState(() => _accepting = true);
    try {
      await context.read<LifeMateApiClient>().acceptCareInvitation(
        token: token,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('ارتباط مراقبتی فعال شد.')));
      await _refresh();
    } on LifeMateApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_friendlyApiError(error))));
    } finally {
      if (mounted) setState(() => _accepting = false);
    }
  }

  Future<void> _revokeRelationship(Map<String, dynamic> relationship) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text('لغو دسترسی مراقبتی'),
        content: Text(
          'دسترسی شما به اطلاعات ${_relationshipName(relationship)} فوراً لغو می‌شود.',
          style: const TextStyle(height: 1.6),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('انصراف'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('لغو دسترسی'),
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

  void _showAlerts() {
    final alerts = _doses
        .where(
          (dose) =>
              dose['status']?.toString() == 'missed' ||
              dose['status']?.toString() == 'skipped',
        )
        .toList(growable: false);
    if (alerts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('هشدار دارویی فعالی وجود ندارد.')),
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
              const Text(
                'هشدارهای دارویی امروز',
                style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 14),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * 0.55,
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: alerts.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, index) => _DoseCard(dose: alerts[index]),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _onNavigationTap(int index) {
    final shellNavigation = widget.onNavigationTap;
    if (shellNavigation != null) {
      shellNavigation(index);
      return;
    }
    if (index == _currentIndex) return;
    if (index == 0) {
      Navigator.of(context).pushReplacement(
        PageRouteBuilder<void>(
          pageBuilder: (_, __, ___) => const CalendarScreen(),
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
        ),
      );
      return;
    }
    if (index == 4) {
      Navigator.of(context).pushReplacement(
        PageRouteBuilder<void>(
          pageBuilder: (_, __, ___) => const DashboardScreen(),
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
        ),
      );
      return;
    }
    setState(() => _currentIndex = index);
  }

  _FeatureDefinition get _feature => switch (_currentIndex) {
    1 => const _FeatureDefinition(
      title: 'تغییر پروفایل',
      subtitle: 'انتخاب نقش فعال و تجربه متناسب با آن در CareMate',
      icon: Icons.switch_account_rounded,
      accent: Color(0xFF7B93DB),
      softBackground: Color(0xFFF2F4FF),
    ),
    2 => const _FeatureDefinition(
      title: 'مدیریت درمان',
      subtitle: 'مشاهده برنامه و وضعیت واقعی درمان فرد تحت مراقبت',
      icon: Icons.medical_services_rounded,
      accent: Color(0xFF5BA7E8),
      softBackground: Color(0xFFF0F8FF),
    ),
    _ => const _FeatureDefinition(
      title: 'مراقبت خانواده',
      subtitle: 'مدیریت امن ارتباط‌های مراقبتی و دسترسی‌ها',
      icon: Icons.family_restroom_rounded,
      accent: Color(0xFFE598D8),
      softBackground: Color(0xFFFFF3FC),
    ),
  };

  @override
  Widget build(BuildContext context) {
    final feature = _feature;
    final alerts = _doses.where((dose) {
      final status = dose['status']?.toString();
      return status == 'missed' || status == 'skipped';
    }).length;

    return Scaffold(
      backgroundColor: AppColors.background,
      extendBody: true,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            CustomAppHeader(
              onNotificationTap: _showAlerts,
              onSignOutTap: LifeMateAuth.signOut,
              showNotificationDot: alerts > 0,
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _refresh,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 130),
                  children: [
                    _FeatureHero(feature: feature),
                    const SizedBox(height: 18),
                    if (_error != null) ...[
                      _ErrorBanner(message: _error!, onRetry: _refresh),
                      const SizedBox(height: 16),
                    ],
                    if (_loading && _currentUserId == null)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 90),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else
                      switch (_currentIndex) {
                        1 => _buildProfileSelection(),
                        2 => _buildTreatmentManagement(feature),
                        _ => _buildFamilyCare(feature),
                      },
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: CareMateBottomNav(
        currentIndex: _currentIndex,
        onTap: _onNavigationTap,
        routeTreatmentScreen: widget.onNavigationTap == null,
      ),
    );
  }

  Widget _buildProfileSelection() {
    return const CareProfileMaskSelector();
  }

  Widget _buildTreatmentManagement(_FeatureDefinition feature) {
    final relationship = _selectedRelationship;
    if (relationship == null) {
      return _EmptyState(
        icon: Icons.medical_services_outlined,
        title: 'فردی برای نمایش درمان انتخاب نشده',
        description: 'ابتدا یک دعوت مراقبتی معتبر را بپذیرید.',
        actionLabel: 'رفتن به مراقبت خانواده',
        onAction: () => setState(() => _currentIndex = 3),
      );
    }
    final taken = _doses.where((d) => d['status'] == 'taken').length;
    final skipped = _doses.where((d) => d['status'] == 'skipped').length;
    final missed = _doses.where((d) => d['status'] == 'missed').length;
    final scheduled = _doses.where((d) => d['status'] == 'scheduled').length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SelectedPatientCard(
          relationship: relationship,
          relationships: _relationships,
          selectedId: _selectedRelationshipId,
          onChanged: _selectRelationship,
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(
              child: _MetricCard(
                label: 'مصرف‌شده',
                value: taken,
                icon: Icons.check_circle_rounded,
                color: const Color(0xFF36A269),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _MetricCard(
                label: 'در انتظار',
                value: scheduled,
                icon: Icons.schedule_rounded,
                color: AppColors.primaryBlue,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _MetricCard(
                label: 'ردشده',
                value: skipped,
                icon: Icons.block_rounded,
                color: Colors.orange,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _MetricCard(
                label: 'فراموش‌شده',
                value: missed,
                icon: Icons.warning_amber_rounded,
                color: Colors.redAccent,
              ),
            ),
          ],
        ),
        const SizedBox(height: 22),
        const _SectionTitle(
          title: 'برنامه امروز',
          subtitle: 'وضعیت‌ها مستقیماً از پایگاه داده LifeMate خوانده می‌شوند.',
        ),
        const SizedBox(height: 12),
        if (_loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 34),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_doses.isEmpty)
          const _InlineEmptyState(
            icon: Icons.event_available_rounded,
            text: 'برای امروز برنامه دارویی ثبت نشده است.',
          )
        else
          ..._doses.map(
            (dose) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _DoseCard(dose: dose),
            ),
          ),
        const SizedBox(height: 10),
        _DevelopmentCard(
          accent: feature.accent,
          icon: Icons.edit_calendar_rounded,
          title: 'ویرایش برنامه درمان',
          description:
              'CareMate در این نسخه مشاهده‌گر است. تغییر نسخه دارو یا زمان‌بندی باید توسط بیمار یا پزشک و با قرارداد Backend مجزا انجام شود.',
        ),
      ],
    );
  }

  Widget _buildFamilyCare(_FeatureDefinition feature) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _accepting ? null : _showAcceptInvitation,
            icon: _accepting
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.person_add_alt_1_rounded),
            label: const Text('پذیرش دعوت مراقبت'),
          ),
        ),
        const SizedBox(height: 20),
        const _SectionTitle(
          title: 'تیم مراقبت',
          subtitle:
              'روابط فعال و قابل لغو، بدون نمایش اطلاعات خارج از رضایت بیمار.',
        ),
        const SizedBox(height: 12),
        if (_relationships.isEmpty)
          const _InlineEmptyState(
            icon: Icons.group_off_rounded,
            text: 'هنوز ارتباط مراقبتی فعالی وجود ندارد.',
          )
        else
          ..._relationships.map(
            (relationship) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _RelationshipManagementCard(
                relationship: relationship,
                selected:
                    relationship['id']?.toString() == _selectedRelationshipId,
                onSelect: () =>
                    _selectRelationship(relationship['id']?.toString()),
                onRevoke: () => _revokeRelationship(relationship),
              ),
            ),
          ),
        const SizedBox(height: 8),
        _DevelopmentCard(
          accent: feature.accent,
          icon: Icons.insights_rounded,
          title: 'گزارش خانوادگی هفتگی',
          description:
              'صفحه گزارش و اشتراک‌گذاری مطابق طراحی محصول حفظ شده، اما تا ایجاد API گزارش و رضایت‌نامه اشتراک‌گذاری غیرفعال است.',
        ),
      ],
    );
  }

  static String _doseTime(Map<String, dynamic> dose) {
    final value = dose['scheduledLocalTime']?.toString() ?? '--:--';
    return value.length >= 5 ? value.substring(0, 5) : value;
  }

  static String _friendlyApiError(LifeMateApiException error) {
    switch (error.code) {
      case 'invalid_invitation_token':
        return 'کد دعوت نامعتبر یا منقضی شده است.';
      case 'care_access_denied':
        return 'دسترسی مراقبتی برای این بیمار فعال نیست.';
      default:
        return error.isUnauthorized
            ? 'نشست شما منقضی شده است. دوباره وارد شوید.'
            : 'درخواست انجام نشد. دوباره تلاش کنید.';
    }
  }
}

class _FeatureHero extends StatelessWidget {
  const _FeatureHero({required this.feature});
  final _FeatureDefinition feature;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(22),
    decoration: BoxDecoration(
      color: feature.softBackground,
      borderRadius: BorderRadius.circular(28),
      boxShadow: [
        BoxShadow(
          color: feature.accent.withOpacity(0.12),
          blurRadius: 22,
          offset: const Offset(0, 10),
        ),
      ],
    ),
    child: Row(
      children: [
        Container(
          width: 66,
          height: 66,
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: feature.accent.withOpacity(0.15),
                blurRadius: 14,
              ),
            ],
          ),
          child: Icon(feature.icon, color: feature.accent, size: 34),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                feature.title,
                style: const TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.w800,
                  color: AppColors.primaryText,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                feature.subtitle,
                style: const TextStyle(
                  height: 1.55,
                  color: AppColors.secondaryText,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.subtitle});
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        title,
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w800,
          color: AppColors.primaryText,
        ),
      ),
      const SizedBox(height: 4),
      Text(
        subtitle,
        style: const TextStyle(height: 1.5, color: AppColors.secondaryText),
      ),
    ],
  );
}

class _RelationshipSelectionCard extends StatelessWidget {
  const _RelationshipSelectionCard({
    required this.relationship,
    required this.selected,
    required this.onTap,
  });

  final Map<String, dynamic> relationship;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final name = relationship['patientDisplayName']?.toString().trim();
    final displayName = name == null || name.isEmpty ? 'فرد تحت مراقبت' : name;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFFF0F6FF) : Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: selected
                  ? AppColors.primaryBlue.withOpacity(0.55)
                  : Colors.transparent,
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.primaryBlue.withOpacity(0.08),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: const Color(0xFFEAF4FF),
                child: Text(
                  displayName.characters.first,
                  style: const TextStyle(
                    color: AppColors.primaryBlue,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayName,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: AppColors.primaryText,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'دسترسی فعال مراقبتی',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.secondaryText,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                selected
                    ? Icons.check_circle_rounded
                    : Icons.radio_button_unchecked_rounded,
                color: selected ? AppColors.primaryBlue : Colors.black26,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SelectedPatientCard extends StatelessWidget {
  const _SelectedPatientCard({
    required this.relationship,
    required this.relationships,
    required this.selectedId,
    required this.onChanged,
  });
  final Map<String, dynamic> relationship;
  final List<Map<String, dynamic>> relationships;
  final String? selectedId;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final name = relationship['patientDisplayName']?.toString().trim();
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: AppColors.softDecoration(),
      child: Row(
        children: [
          const CircleAvatar(
            radius: 26,
            backgroundColor: Color(0xFFEAF4FF),
            child: Icon(
              Icons.person_rounded,
              color: AppColors.primaryBlue,
              size: 30,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: DropdownButtonFormField<String>(
              value: selectedId,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'فرد تحت مراقبت',
                border: InputBorder.none,
              ),
              items: relationships
                  .map(
                    (item) => DropdownMenuItem<String>(
                      value: item['id']?.toString(),
                      child: Text(
                        item['patientDisplayName']
                                    ?.toString()
                                    .trim()
                                    .isNotEmpty ==
                                true
                            ? item['patientDisplayName'].toString()
                            : 'فرد تحت مراقبت',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(growable: false),
              onChanged: onChanged,
            ),
          ),
          if (name != null && name.isNotEmpty)
            const Icon(Icons.verified_user_rounded, color: Color(0xFF36A269)),
        ],
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });
  final String label;
  final int value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: AppColors.softDecoration(),
    child: Column(
      children: [
        Icon(icon, color: color),
        const SizedBox(height: 7),
        Text(
          '$value',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w900,
            color: color,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 11, color: AppColors.secondaryText),
        ),
      ],
    ),
  );
}

class _DoseCard extends StatelessWidget {
  const _DoseCard({required this.dose});
  final Map<String, dynamic> dose;

  @override
  Widget build(BuildContext context) {
    final status = dose['status']?.toString() ?? 'scheduled';
    final state = switch (status) {
      'taken' => (
        'مصرف‌شده',
        Icons.check_circle_rounded,
        const Color(0xFF36A269),
        const Color(0xFFEAF8F0),
      ),
      'skipped' => (
        'ردشده',
        Icons.block_rounded,
        Colors.orange,
        const Color(0xFFFFF6E8),
      ),
      'missed' => (
        'فراموش‌شده',
        Icons.warning_amber_rounded,
        Colors.redAccent,
        const Color(0xFFFFEEF0),
      ),
      _ => (
        'در انتظار',
        Icons.schedule_rounded,
        AppColors.primaryBlue,
        const Color(0xFFEAF4FF),
      ),
    };
    final rawTime = dose['scheduledLocalTime']?.toString() ?? '--:--';
    final time = rawTime.length >= 5 ? rawTime.substring(0, 5) : rawTime;
    final medication = dose['medicationName']?.toString().trim();
    final doseText = dose['doseText']?.toString().trim();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryBlue.withOpacity(0.06),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: state.$4,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(state.$2, color: state.$3),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  medication == null || medication.isEmpty
                      ? 'دارو'
                      : medication,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: AppColors.primaryText,
                  ),
                ),
                if (doseText != null && doseText.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    doseText,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.secondaryText,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                time,
                textDirection: TextDirection.ltr,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              Text(
                state.$1,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: state.$3,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RelationshipManagementCard extends StatelessWidget {
  const _RelationshipManagementCard({
    required this.relationship,
    required this.selected,
    required this.onSelect,
    required this.onRevoke,
  });
  final Map<String, dynamic> relationship;
  final bool selected;
  final VoidCallback onSelect;
  final VoidCallback onRevoke;

  @override
  Widget build(BuildContext context) {
    final name = relationship['patientDisplayName']?.toString().trim();
    final displayName = name == null || name.isEmpty ? 'فرد تحت مراقبت' : name;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: AppColors.softDecoration(
        color: selected ? const Color(0xFFF0F6FF) : Colors.white,
      ),
      child: Column(
        children: [
          Row(
            children: [
              const CircleAvatar(
                backgroundColor: Color(0xFFEAF4FF),
                child: Icon(Icons.person_rounded, color: AppColors.primaryBlue),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayName,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        color: AppColors.primaryText,
                      ),
                    ),
                    const SizedBox(height: 3),
                    const Text(
                      'رضایت مراقبتی فعال',
                      style: TextStyle(fontSize: 12, color: Color(0xFF36A269)),
                    ),
                  ],
                ),
              ),
              if (selected)
                const Icon(
                  Icons.check_circle_rounded,
                  color: AppColors.primaryBlue,
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onSelect,
                  icon: const Icon(Icons.visibility_outlined),
                  label: const Text('مشاهده'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.redAccent,
                  ),
                  onPressed: onRevoke,
                  icon: const Icon(Icons.link_off_rounded),
                  label: const Text('لغو دسترسی'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DevelopmentCard extends StatelessWidget {
  const _DevelopmentCard({
    required this.accent,
    required this.icon,
    required this.title,
    required this.description,
  });
  final Color accent;
  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
    decoration: AppColors.softDecoration(),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: accent.withOpacity(0.12),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(icon, color: accent),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: AppColors.primaryText,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
              decoration: BoxDecoration(
                color: const Color(0xFFF0F2F5),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text(
                'در دست توسعه',
                style: TextStyle(
                  fontSize: 10,
                  color: AppColors.secondaryText,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          description,
          style: const TextStyle(height: 1.65, color: AppColors.secondaryText),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: null,
            icon: const Icon(Icons.lock_outline_rounded),
            label: const Text('فعلاً غیرفعال'),
          ),
        ),
      ],
    ),
  );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.description,
    required this.actionLabel,
    required this.onAction,
  });
  final IconData icon;
  final String title;
  final String description;
  final String actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(24),
    decoration: AppColors.softDecoration(),
    child: Column(
      children: [
        Icon(icon, size: 58, color: AppColors.primaryBlue),
        const SizedBox(height: 14),
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: AppColors.primaryText,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          description,
          textAlign: TextAlign.center,
          style: const TextStyle(height: 1.6, color: AppColors.secondaryText),
        ),
        const SizedBox(height: 18),
        FilledButton(onPressed: onAction, child: Text(actionLabel)),
      ],
    ),
  );
}

class _InlineEmptyState extends StatelessWidget {
  const _InlineEmptyState({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(22),
    decoration: AppColors.softDecoration(),
    child: Column(
      children: [
        Icon(icon, size: 42, color: AppColors.primaryBlue),
        const SizedBox(height: 10),
        Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.secondaryText),
        ),
      ],
    ),
  );
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message, required this.onRetry});
  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.red.shade50,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: Colors.red.shade100),
    ),
    child: Row(
      children: [
        Icon(Icons.cloud_off_rounded, color: Colors.red.shade600),
        const SizedBox(width: 10),
        Expanded(child: Text(message)),
        TextButton(onPressed: onRetry, child: const Text('تلاش دوباره')),
      ],
    ),
  );
}

class _FeatureDefinition {
  const _FeatureDefinition({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accent,
    required this.softBackground,
  });
  final String title;
  final String subtitle;
  final IconData icon;
  final Color accent;
  final Color softBackground;
}
