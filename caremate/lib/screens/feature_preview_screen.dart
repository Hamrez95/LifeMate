// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:lifemate_client/lifemate_client.dart';
import 'package:provider/provider.dart';

import '../core/constants/app_colors.dart';
import '../widgets/care_profile_mask_selector.dart';
import '../widgets/care_request_card.dart';
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
  bool _requestingCare = false;
  String? _error;
  String? _currentUserId;
  String? _selectedRelationshipId;
  List<Map<String, dynamic>> _relationships = const [];
  List<Map<String, dynamic>> _outgoingCareRequests = const [];
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
    return name == null || name.isEmpty
        ? LifeMateRuntimeLocale.select(
            fa: LifeMateRuntimeLocale.select(
              fa: 'فرد تحت مراقبت',
              en: "Person under care",
            ),
            en: "Person under care",
          )
        : name;
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
        api.getOutgoingCareRequests(),
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
        _outgoingCareRequests = values[2] as List<Map<String, dynamic>>;
        _selectedRelationshipId = selectedId;
      });
      await _loadSelectedDoses();
    } on LifeMateApiException catch (error) {
      _setError(_friendlyApiError(error));
    } catch (error) {
      debugPrint('CareMate feature load failed: $error');
      _setError(
        LifeMateRuntimeLocale.select(
          fa: LifeMateRuntimeLocale.select(
            fa: 'اطلاعات مراقبت دریافت نشد. اتصال اینترنت را بررسی کنید.',
            en: "Care information not received. Check your internet connection.",
          ),
          en: "Care information not received. Check your internet connection.",
        ),
      );
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
      _setError(
        LifeMateRuntimeLocale.select(
          fa: LifeMateRuntimeLocale.select(
            fa: 'وضعیت فرد تحت مراقبت دریافت نشد.',
            en: "The status of the person under care was not received.",
          ),
          en: "The status of the person under care was not received.",
        ),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _showCareRequestSheet() async {
    final controller = TextEditingController();
    var consent = false;
    final email = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Container(
            padding: EdgeInsets.fromLTRB(22, 14, 22, 24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
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
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.black12,
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                  ),
                  SizedBox(height: 18),
                  Text(
                    LifeMateRuntimeLocale.select(
                      fa: LifeMateRuntimeLocale.select(
                        fa: 'درخواست مراقبت',
                        en: "Care request",
                      ),
                      en: "Care request",
                    ),
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
                  ),
                  SizedBox(height: 6),
                  Text(
                    LifeMateRuntimeLocale.select(
                      fa: LifeMateRuntimeLocale.select(
                        fa: 'ایمیل حساب WellMate فرد را وارد کنید. تا وقتی خودش تأیید نکند هیچ اطلاعاتی برای شما باز نمی‌شود.',
                        en: "Enter the person's WellMate account email. No information will be opened for you until he confirms it.",
                      ),
                      en: "Enter the person's WellMate account email. No information will be opened for you until he confirms it.",
                    ),
                    style: TextStyle(
                      height: 1.6,
                      color: AppColors.secondaryText,
                    ),
                  ),
                  SizedBox(height: 16),
                  TextField(
                    controller: controller,
                    keyboardType: TextInputType.emailAddress,
                    textDirection: TextDirection.ltr,
                    autocorrect: false,
                    onChanged: (_) => setSheetState(() {}),
                    decoration: InputDecoration(
                      labelText: LifeMateRuntimeLocale.select(
                        fa: LifeMateRuntimeLocale.select(
                          fa: 'ایمیل WellMate',
                          en: "Email WellMate",
                        ),
                        en: "Email WellMate",
                      ),
                      prefixIcon: Icon(Icons.alternate_email_rounded),
                      filled: true,
                      fillColor: Color(0xFFF3F7FC),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  CheckboxListTile(
                    value: consent,
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    onChanged: (value) =>
                        setSheetState(() => consent = value ?? false),
                    title: Text(
                      LifeMateRuntimeLocale.select(
                        fa: LifeMateRuntimeLocale.select(
                          fa: 'می‌دانم دسترسی فقط با رضایت خود فرد فعال می‌شود و هر زمان قابل لغو است.',
                          en: "I understand that access is activated only with the consent of the individual and can be canceled at any time.",
                        ),
                        en: "I understand that access is activated only with the consent of the individual and can be canceled at any time.",
                      ),
                      style: TextStyle(fontSize: 12.5, height: 1.55),
                    ),
                  ),
                  SizedBox(height: 4),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: consent && _looksLikeEmail(controller.text)
                          ? () => Navigator.pop(
                              sheetContext,
                              controller.text.trim(),
                            )
                          : null,
                      icon: Icon(Icons.send_rounded),
                      label: Text(
                        LifeMateRuntimeLocale.select(
                          fa: LifeMateRuntimeLocale.select(
                            fa: 'ارسال درخواست',
                            en: "Submit request",
                          ),
                          en: "Submit request",
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    controller.dispose();
    if (email == null || !mounted) return;

    setState(() => _requestingCare = true);
    try {
      await context.read<LifeMateApiClient>().createCareRequest(email: email);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            LifeMateRuntimeLocale.select(
              fa: LifeMateRuntimeLocale.select(
                fa: 'درخواست ارسال شد؛ منتظر تأیید در WellMate بمانید.',
                en: "Request sent; Wait for confirmation in WellMate.",
              ),
              en: "Request sent; Wait for confirmation in WellMate.",
            ),
          ),
        ),
      );
      await _refresh();
    } on LifeMateApiException catch (error) {
      if (!mounted) return;
      final message = switch (error.code) {
        'care_request_target_not_found' => LifeMateRuntimeLocale.select(
          fa: LifeMateRuntimeLocale.select(
            fa: 'حساب WellMate فعالی با این ایمیل پیدا نشد.',
            en: "No active WellMate account found with this email.",
          ),
          en: "No active WellMate account found with this email.",
        ),
        'care_request_already_pending' => LifeMateRuntimeLocale.select(
          fa: LifeMateRuntimeLocale.select(
            fa: 'برای این فرد یک درخواست در انتظار دارید.',
            en: "You have a pending request for this person.",
          ),
          en: "You have a pending request for this person.",
        ),
        'care_relationship_already_active' => LifeMateRuntimeLocale.select(
          fa: LifeMateRuntimeLocale.select(
            fa: 'شما همین حالا مراقب این فرد هستید.',
            en: "You are taking care of this person right now.",
          ),
          en: "You are taking care of this person right now.",
        ),
        'self_care_request_not_allowed' => LifeMateRuntimeLocale.select(
          fa: LifeMateRuntimeLocale.select(
            fa: 'نمی‌توانید برای حساب خودتان درخواست مراقبت بفرستید.',
            en: "You cannot submit maintenance requests for your own account.",
          ),
          en: "You cannot submit maintenance requests for your own account.",
        ),
        _ => _friendlyApiError(error),
      };
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) setState(() => _requestingCare = false);
    }
  }

  Future<void> _cancelCareRequest(Map<String, dynamic> request) async {
    final id = request['id']?.toString();
    if (id == null || id.isEmpty) return;
    try {
      await context.read<LifeMateApiClient>().revokeCareRequest(requestId: id);
      await _refresh();
    } on LifeMateApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_friendlyApiError(error))));
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
          title: Text(
            LifeMateRuntimeLocale.select(
              fa: LifeMateRuntimeLocale.select(
                fa: 'پذیرش دعوت مراقبت',
                en: "Accept the invitation to care",
              ),
              en: "Accept the invitation to care",
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                LifeMateRuntimeLocale.select(
                  fa: LifeMateRuntimeLocale.select(
                    fa: 'کدی را وارد کنید که بیمار مستقیماً برای شما ارسال کرده است.',
                    en: "Enter the code that the patient sent you directly.",
                  ),
                  en: "Enter the code that the patient sent you directly.",
                ),
                style: TextStyle(height: 1.6),
              ),
              SizedBox(height: 14),
              TextField(
                controller: controller,
                textDirection: TextDirection.ltr,
                autocorrect: false,
                onChanged: (_) => setDialogState(() {}),
                decoration: InputDecoration(
                  labelText: LifeMateRuntimeLocale.select(
                    fa: LifeMateRuntimeLocale.select(
                      fa: 'کد دعوت',
                      en: "invitation code",
                    ),
                    en: "invitation code",
                  ),
                  prefixIcon: Icon(Icons.vpn_key_rounded),
                  filled: true,
                  fillColor: Color(0xFFF6F9FD),
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
                title: Text(
                  LifeMateRuntimeLocale.select(
                    fa: LifeMateRuntimeLocale.select(
                      fa: 'محدوده دسترسی مراقبتی و حریم خصوصی بیمار را می‌پذیرم.',
                      en: "I accept the scope of care access and patient privacy.",
                    ),
                    en: "I accept the scope of care access and patient privacy.",
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(
                LifeMateRuntimeLocale.select(
                  fa: LifeMateRuntimeLocale.select(fa: 'انصراف', en: "opt out"),
                  en: "opt out",
                ),
              ),
            ),
            FilledButton(
              onPressed: consent && controller.text.trim().isNotEmpty
                  ? () => Navigator.pop(dialogContext, controller.text.trim())
                  : null,
              child: Text(
                LifeMateRuntimeLocale.select(
                  fa: LifeMateRuntimeLocale.select(
                    fa: 'پذیرش امن',
                    en: "Safe reception",
                  ),
                  en: "Safe reception",
                ),
              ),
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            LifeMateRuntimeLocale.select(
              fa: LifeMateRuntimeLocale.select(
                fa: 'ارتباط مراقبتی فعال شد.',
                en: "Care connection activated.",
              ),
              en: "Care connection activated.",
            ),
          ),
        ),
      );
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
        title: Text(
          LifeMateRuntimeLocale.select(
            fa: LifeMateRuntimeLocale.select(
              fa: 'لغو دسترسی مراقبتی',
              en: "Revoke maintenance access",
            ),
            en: "Revoke maintenance access",
          ),
        ),
        content: Text(
          LifeMateRuntimeLocale.select(
            fa: LifeMateRuntimeLocale.select(
              fa: 'دسترسی شما به اطلاعات ${_relationshipName(relationship)} فوراً لغو می‌شود.',
              en: "Your access to the ${_relationshipName(relationship)} information will be revoked immediately.",
            ),
            en: "Your access to the ${_relationshipName(relationship)} information will be revoked immediately.",
          ),
          style: TextStyle(height: 1.6),
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
                  fa: 'لغو دسترسی',
                  en: "Revoke access",
                ),
                en: "Revoke access",
              ),
            ),
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
        SnackBar(
          content: Text(
            LifeMateRuntimeLocale.select(
              fa: LifeMateRuntimeLocale.select(
                fa: 'هشدار دارویی فعالی وجود ندارد.',
                en: "There is no active drug warning.",
              ),
              en: "There is no active drug warning.",
            ),
          ),
        ),
      );
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        padding: EdgeInsets.fromLTRB(24, 18, 24, 28),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                LifeMateRuntimeLocale.select(
                  fa: LifeMateRuntimeLocale.select(
                    fa: 'هشدارهای دارویی امروز',
                    en: "Today's drug warnings",
                  ),
                  en: "Today's drug warnings",
                ),
                style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
              ),
              SizedBox(height: 14),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * 0.55,
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: alerts.length,
                  separatorBuilder: (_, __) => SizedBox(height: 10),
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
    1 => _FeatureDefinition(
      title: LifeMateRuntimeLocale.select(
        fa: LifeMateRuntimeLocale.select(
          fa: 'تغییر پروفایل',
          en: "Change profile",
        ),
        en: "Change profile",
      ),
      subtitle: LifeMateRuntimeLocale.select(
        fa: LifeMateRuntimeLocale.select(
          fa: 'انتخاب نقش فعال و تجربه متناسب با آن در CareMate',
          en: "Choose an active role and experience accordingly in CareMate",
        ),
        en: "Choose an active role and experience accordingly in CareMate",
      ),
      icon: Icons.switch_account_rounded,
      accent: Color(0xFF7B93DB),
      softBackground: Color(0xFFF2F4FF),
    ),
    2 => _FeatureDefinition(
      title: LifeMateRuntimeLocale.select(
        fa: LifeMateRuntimeLocale.select(
          fa: 'مدیریت درمان',
          en: "Treatment management",
        ),
        en: "Treatment management",
      ),
      subtitle: LifeMateRuntimeLocale.select(
        fa: LifeMateRuntimeLocale.select(
          fa: 'مشاهده برنامه و وضعیت واقعی درمان فرد تحت مراقبت',
          en: "Viewing the program and actual treatment status of the person under care",
        ),
        en: "Viewing the program and actual treatment status of the person under care",
      ),
      icon: Icons.medical_services_rounded,
      accent: Color(0xFF5BA7E8),
      softBackground: Color(0xFFF0F8FF),
    ),
    _ => _FeatureDefinition(
      title: LifeMateRuntimeLocale.select(
        fa: LifeMateRuntimeLocale.select(
          fa: 'مراقبت خانواده',
          en: "Family care",
        ),
        en: "Family care",
      ),
      subtitle: LifeMateRuntimeLocale.select(
        fa: LifeMateRuntimeLocale.select(
          fa: 'مدیریت امن ارتباط‌های مراقبتی و دسترسی‌ها',
          en: "Secure management of care communications and access",
        ),
        en: "Secure management of care communications and access",
      ),
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
        title: LifeMateRuntimeLocale.select(
          fa: LifeMateRuntimeLocale.select(
            fa: 'فردی برای نمایش درمان انتخاب نشده',
            en: "Individuals not selected to display treatment",
          ),
          en: "Individuals not selected to display treatment",
        ),
        description: LifeMateRuntimeLocale.select(
          fa: LifeMateRuntimeLocale.select(
            fa: 'ابتدا یک دعوت مراقبتی معتبر را بپذیرید.',
            en: "First, accept a valid care invitation.",
          ),
          en: "First, accept a valid care invitation.",
        ),
        actionLabel: LifeMateRuntimeLocale.select(
          fa: LifeMateRuntimeLocale.select(
            fa: 'رفتن به مراقبت خانواده',
            en: "Go to family care",
          ),
          en: "Go to family care",
        ),
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
        SizedBox(height: 18),
        Row(
          children: [
            Expanded(
              child: _MetricCard(
                label: LifeMateRuntimeLocale.select(
                  fa: LifeMateRuntimeLocale.select(
                    fa: 'مصرف‌شده',
                    en: "consumed",
                  ),
                  en: "consumed",
                ),
                value: taken,
                icon: Icons.check_circle_rounded,
                color: Color(0xFF36A269),
              ),
            ),
            SizedBox(width: 10),
            Expanded(
              child: _MetricCard(
                label: LifeMateRuntimeLocale.select(
                  fa: LifeMateRuntimeLocale.select(
                    fa: 'در انتظار',
                    en: "waiting",
                  ),
                  en: "waiting",
                ),
                value: scheduled,
                icon: Icons.schedule_rounded,
                color: AppColors.primaryBlue,
              ),
            ),
          ],
        ),
        SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _MetricCard(
                label: LifeMateRuntimeLocale.select(
                  fa: LifeMateRuntimeLocale.select(fa: 'ردشده', en: "rejected"),
                  en: "rejected",
                ),
                value: skipped,
                icon: Icons.block_rounded,
                color: Colors.orange,
              ),
            ),
            SizedBox(width: 10),
            Expanded(
              child: _MetricCard(
                label: LifeMateRuntimeLocale.select(
                  fa: LifeMateRuntimeLocale.select(
                    fa: 'فراموش‌شده',
                    en: "forgotten",
                  ),
                  en: "forgotten",
                ),
                value: missed,
                icon: Icons.warning_amber_rounded,
                color: Colors.redAccent,
              ),
            ),
          ],
        ),
        SizedBox(height: 22),
        _SectionTitle(
          title: LifeMateRuntimeLocale.select(
            fa: LifeMateRuntimeLocale.select(
              fa: 'برنامه امروز',
              en: "Today's program",
            ),
            en: "Today's program",
          ),
          subtitle: LifeMateRuntimeLocale.select(
            fa: LifeMateRuntimeLocale.select(
              fa: 'وضعیت‌ها مستقیماً از پایگاه داده LifeMate خوانده می‌شوند.',
              en: "Statuses are read directly from the LifeMate database.",
            ),
            en: "Statuses are read directly from the LifeMate database.",
          ),
        ),
        SizedBox(height: 12),
        if (_loading)
          Padding(
            padding: EdgeInsets.symmetric(vertical: 34),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_doses.isEmpty)
          _InlineEmptyState(
            icon: Icons.event_available_rounded,
            text: LifeMateRuntimeLocale.select(
              fa: LifeMateRuntimeLocale.select(
                fa: 'برای امروز برنامه دارویی ثبت نشده است.',
                en: "There is no medication program registered for today.",
              ),
              en: "There is no medication program registered for today.",
            ),
          )
        else
          ..._doses.map(
            (dose) => Padding(
              padding: EdgeInsets.only(bottom: 10),
              child: _DoseCard(dose: dose),
            ),
          ),
        SizedBox(height: 10),
        _DevelopmentCard(
          accent: feature.accent,
          icon: Icons.edit_calendar_rounded,
          title: LifeMateRuntimeLocale.select(
            fa: LifeMateRuntimeLocale.select(
              fa: 'ویرایش برنامه درمان',
              en: "Edit the treatment plan",
            ),
            en: "Edit the treatment plan",
          ),
          description: LifeMateRuntimeLocale.select(
            fa: LifeMateRuntimeLocale.select(
              fa: 'CareMate در این نسخه مشاهده‌گر است. تغییر نسخه دارو یا زمان‌بندی باید توسط بیمار یا پزشک و با قرارداد Backend مجزا انجام شود.',
              en: "CareMate is an observer in this version. Changing the drug prescription or schedule must be done by the patient or doctor with a separate backend contract.",
            ),
            en: "CareMate is an observer in this version. Changing the drug prescription or schedule must be done by the patient or doctor with a separate backend contract.",
          ),
        ),
      ],
    );
  }

  Widget _buildFamilyCare(_FeatureDefinition feature) {
    final pendingRequests = _outgoingCareRequests
        .where((request) => request['status']?.toString() == 'pending')
        .toList(growable: false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(
          title: LifeMateRuntimeLocale.select(
            fa: LifeMateRuntimeLocale.select(
              fa: 'افراد تحت مراقبت',
              en: "People under care",
            ),
            en: "People under care",
          ),
          subtitle: LifeMateRuntimeLocale.select(
            fa: LifeMateRuntimeLocale.select(
              fa: 'ارتباط‌های فعال شما؛ هر فرد فقط اطلاعات مجاز خودش را دارد.',
              en: "Your active connections; Each person has only his authorized information.",
            ),
            en: "Your active connections; Each person has only his authorized information.",
          ),
        ),
        SizedBox(height: 12),
        if (_relationships.isEmpty)
          _InlineEmptyState(
            icon: Icons.group_off_rounded,
            text: LifeMateRuntimeLocale.select(
              fa: LifeMateRuntimeLocale.select(
                fa: 'هنوز ارتباط مراقبتی فعالی وجود ندارد.',
                en: "There is no active care relationship yet.",
              ),
              en: "There is no active care relationship yet.",
            ),
          )
        else
          ..._relationships.map(
            (relationship) => Padding(
              padding: EdgeInsets.only(bottom: 12),
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
        SizedBox(height: 10),
        CareRequestCard(
          loading: _requestingCare,
          pendingRequests: pendingRequests,
          onRequest: _showCareRequestSheet,
          onCancel: _cancelCareRequest,
        ),
        SizedBox(height: 14),
        Container(
          padding: EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.82),
            borderRadius: BorderRadius.circular(22),
          ),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: Color(0xFFF1F5FF),
                child: Icon(
                  Icons.qr_code_rounded,
                  color: AppColors.primaryBlue,
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      LifeMateRuntimeLocale.select(
                        fa: LifeMateRuntimeLocale.select(
                          fa: 'دعوت از طرف WellMate داری؟',
                          en: "Do you have an invitation from WellMate?",
                        ),
                        en: "Do you have an invitation from WellMate?",
                      ),
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    SizedBox(height: 3),
                    Text(
                      LifeMateRuntimeLocale.select(
                        fa: LifeMateRuntimeLocale.select(
                          fa: 'کد یا QR دعوت را بپذیر تا ارتباط مراقبتی فعال شود.',
                          en: "Accept the invite code or QR to activate the care connection.",
                        ),
                        en: "Accept the invite code or QR to activate the care connection.",
                      ),
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.secondaryText,
                      ),
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: _accepting ? null : _showAcceptInvitation,
                child: Text(
                  LifeMateRuntimeLocale.select(
                    fa: LifeMateRuntimeLocale.select(
                      fa: 'پذیرش',
                      en: "acceptance",
                    ),
                    en: "acceptance",
                  ),
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: 8),
        _DevelopmentCard(
          accent: feature.accent,
          icon: Icons.insights_rounded,
          title: LifeMateRuntimeLocale.select(
            fa: LifeMateRuntimeLocale.select(
              fa: 'گزارش خانوادگی هفتگی',
              en: "Weekly family report",
            ),
            en: "Weekly family report",
          ),
          description: LifeMateRuntimeLocale.select(
            fa: LifeMateRuntimeLocale.select(
              fa: 'صفحه گزارش و اشتراک‌گذاری مطابق طراحی محصول حفظ شده، اما تا ایجاد API گزارش و رضایت‌نامه اشتراک‌گذاری غیرفعال است.',
              en: "The reporting and sharing page is preserved as per the product design, but is disabled until the reporting and sharing consent API is created.",
            ),
            en: "The reporting and sharing page is preserved as per the product design, but is disabled until the reporting and sharing consent API is created.",
          ),
        ),
      ],
    );
  }

  static bool _looksLikeEmail(String value) {
    final email = value.trim();
    final at = email.indexOf('@');
    return at > 0 && at < email.length - 3 && email.contains('.', at);
  }

  static String _doseTime(Map<String, dynamic> dose) {
    final value = dose['scheduledLocalTime']?.toString() ?? '--:--';
    return value.length >= 5 ? value.substring(0, 5) : value;
  }

  static String _friendlyApiError(LifeMateApiException error) {
    switch (error.code) {
      case 'invalid_invitation_token':
        return LifeMateRuntimeLocale.select(
          fa: LifeMateRuntimeLocale.select(
            fa: 'کد دعوت نامعتبر یا منقضی شده است.',
            en: "The invitation code is invalid or expired.",
          ),
          en: "The invitation code is invalid or expired.",
        );
      case 'care_access_denied':
        return LifeMateRuntimeLocale.select(
          fa: LifeMateRuntimeLocale.select(
            fa: 'دسترسی مراقبتی برای این بیمار فعال نیست.',
            en: "Care access is not active for this patient.",
          ),
          en: "Care access is not active for this patient.",
        );
      default:
        return error.isUnauthorized
            ? LifeMateRuntimeLocale.select(
                fa: LifeMateRuntimeLocale.select(
                  fa: 'نشست شما منقضی شده است. دوباره وارد شوید.',
                  en: "Your session has expired. Sign in again.",
                ),
                en: "Your session has expired. Sign in again.",
              )
            : LifeMateRuntimeLocale.select(
                fa: LifeMateRuntimeLocale.select(
                  fa: 'درخواست انجام نشد. دوباره تلاش کنید.',
                  en: "Request failed. Try again.",
                ),
                en: "Request failed. Try again.",
              );
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
    final displayName = name == null || name.isEmpty
        ? LifeMateRuntimeLocale.select(
            fa: LifeMateRuntimeLocale.select(
              fa: 'فرد تحت مراقبت',
              en: "Person under care",
            ),
            en: "Person under care",
          )
        : name;
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
                offset: Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: Color(0xFFEAF4FF),
                child: Text(
                  displayName.characters.first,
                  style: TextStyle(
                    color: AppColors.primaryBlue,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayName,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: AppColors.primaryText,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      LifeMateRuntimeLocale.select(
                        fa: LifeMateRuntimeLocale.select(
                          fa: 'دسترسی فعال مراقبتی',
                          en: "Active Care Access",
                        ),
                        en: "Active Care Access",
                      ),
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
      padding: EdgeInsets.all(18),
      decoration: AppColors.softDecoration(),
      child: Row(
        children: [
          CircleAvatar(
            radius: 26,
            backgroundColor: Color(0xFFEAF4FF),
            child: Icon(
              Icons.person_rounded,
              color: AppColors.primaryBlue,
              size: 30,
            ),
          ),
          SizedBox(width: 14),
          Expanded(
            child: DropdownButtonFormField<String>(
              value: selectedId,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: LifeMateRuntimeLocale.select(
                  fa: LifeMateRuntimeLocale.select(
                    fa: 'فرد تحت مراقبت',
                    en: "Person under care",
                  ),
                  en: "Person under care",
                ),
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
                            : LifeMateRuntimeLocale.select(
                                fa: LifeMateRuntimeLocale.select(
                                  fa: 'فرد تحت مراقبت',
                                  en: "Person under care",
                                ),
                                en: "Person under care",
                              ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(growable: false),
              onChanged: onChanged,
            ),
          ),
          if (name != null && name.isNotEmpty)
            Icon(Icons.verified_user_rounded, color: Color(0xFF36A269)),
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
        LifeMateRuntimeLocale.select(
          fa: LifeMateRuntimeLocale.select(fa: 'مصرف‌شده', en: "consumed"),
          en: "consumed",
        ),
        Icons.check_circle_rounded,
        Color(0xFF36A269),
        Color(0xFFEAF8F0),
      ),
      'skipped' => (
        LifeMateRuntimeLocale.select(
          fa: LifeMateRuntimeLocale.select(fa: 'ردشده', en: "rejected"),
          en: "rejected",
        ),
        Icons.block_rounded,
        Colors.orange,
        Color(0xFFFFF6E8),
      ),
      'missed' => (
        LifeMateRuntimeLocale.select(
          fa: LifeMateRuntimeLocale.select(fa: 'فراموش‌شده', en: "forgotten"),
          en: "forgotten",
        ),
        Icons.warning_amber_rounded,
        Colors.redAccent,
        Color(0xFFFFEEF0),
      ),
      _ => (
        LifeMateRuntimeLocale.select(
          fa: LifeMateRuntimeLocale.select(fa: 'در انتظار', en: "waiting"),
          en: "waiting",
        ),
        Icons.schedule_rounded,
        AppColors.primaryBlue,
        Color(0xFFEAF4FF),
      ),
    };
    final rawTime = dose['scheduledLocalTime']?.toString() ?? '--:--';
    final time = rawTime.length >= 5 ? rawTime.substring(0, 5) : rawTime;
    final medication = dose['medicationName']?.toString().trim();
    final doseText = dose['doseText']?.toString().trim();

    return Container(
      padding: EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryBlue.withOpacity(0.06),
            blurRadius: 14,
            offset: Offset(0, 5),
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
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  medication == null || medication.isEmpty
                      ? LifeMateRuntimeLocale.select(
                          fa: LifeMateRuntimeLocale.select(
                            fa: 'دارو',
                            en: "Medication",
                          ),
                          en: "medicine",
                        )
                      : medication,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: AppColors.primaryText,
                  ),
                ),
                if (doseText != null && doseText.isNotEmpty) ...[
                  SizedBox(height: 3),
                  Text(
                    doseText,
                    style: TextStyle(
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
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              SizedBox(height: 4),
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
    final displayName = name == null || name.isEmpty
        ? LifeMateRuntimeLocale.select(
            fa: LifeMateRuntimeLocale.select(
              fa: 'فرد تحت مراقبت',
              en: "Person under care",
            ),
            en: "Person under care",
          )
        : name;
    return Container(
      padding: EdgeInsets.all(16),
      decoration: AppColors.softDecoration(
        color: selected ? Color(0xFFF0F6FF) : Colors.white,
      ),
      child: Column(
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundColor: Color(0xFFEAF4FF),
                child: Icon(Icons.person_rounded, color: AppColors.primaryBlue),
              ),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayName,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: AppColors.primaryText,
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      LifeMateRuntimeLocale.select(
                        fa: LifeMateRuntimeLocale.select(
                          fa: 'رضایت مراقبتی فعال',
                          en: "Consent to active care",
                        ),
                        en: "Consent to active care",
                      ),
                      style: TextStyle(fontSize: 12, color: Color(0xFF36A269)),
                    ),
                  ],
                ),
              ),
              if (selected)
                Icon(Icons.check_circle_rounded, color: AppColors.primaryBlue),
            ],
          ),
          SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onSelect,
                  icon: Icon(Icons.visibility_outlined),
                  label: Text(
                    LifeMateRuntimeLocale.select(
                      fa: LifeMateRuntimeLocale.select(
                        fa: 'مشاهده',
                        en: "view",
                      ),
                      en: "view",
                    ),
                  ),
                ),
              ),
              SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.redAccent,
                  ),
                  onPressed: onRevoke,
                  icon: Icon(Icons.link_off_rounded),
                  label: Text(
                    LifeMateRuntimeLocale.select(
                      fa: LifeMateRuntimeLocale.select(
                        fa: 'لغو دسترسی',
                        en: "Revoke access",
                      ),
                      en: "Revoke access",
                    ),
                  ),
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
    padding: EdgeInsets.all(18),
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
            SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: AppColors.primaryText,
                ),
              ),
            ),
            Container(
              padding: EdgeInsets.symmetric(horizontal: 9, vertical: 5),
              decoration: BoxDecoration(
                color: Color(0xFFF0F2F5),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                LifeMateRuntimeLocale.select(
                  fa: LifeMateRuntimeLocale.select(
                    fa: 'در دست توسعه',
                    en: "Under development",
                  ),
                  en: "Under development",
                ),
                style: TextStyle(
                  fontSize: 10,
                  color: AppColors.secondaryText,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        SizedBox(height: 12),
        Text(
          description,
          style: TextStyle(height: 1.65, color: AppColors.secondaryText),
        ),
        SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: null,
            icon: Icon(Icons.lock_outline_rounded),
            label: Text(
              LifeMateRuntimeLocale.select(
                fa: LifeMateRuntimeLocale.select(
                  fa: 'فعلاً غیرفعال',
                  en: "Currently inactive",
                ),
                en: "Currently inactive",
              ),
            ),
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
    padding: EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.red.shade50,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: Colors.red.shade100),
    ),
    child: Row(
      children: [
        Icon(Icons.cloud_off_rounded, color: Colors.red.shade600),
        SizedBox(width: 10),
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
