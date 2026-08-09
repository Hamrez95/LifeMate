import 'package:flutter/material.dart';
import 'package:lifemate_client/lifemate_client.dart';
import 'package:provider/provider.dart';

import '../core/constants/app_colors.dart';
import '../core/utils/persian_date_utils.dart';
import '../widgets/caremate_bottom_nav.dart';
import '../widgets/custom_app_header.dart';
import 'calendar/calendar_screen.dart';
import 'dashboard_screen.dart';
import 'feature_preview_screen.dart';

part 'care_event_management_forms.dart';

class CareEventManagementScreen extends StatefulWidget {
  const CareEventManagementScreen({super.key, this.managementApi});

  final LifeMateCareManagementApi? managementApi;

  @override
  State<CareEventManagementScreen> createState() =>
      _CareEventManagementScreenState();
}

class _CareEventManagementScreenState extends State<CareEventManagementScreen> {
  late final LifeMateCareManagementApi _managementApi =
      widget.managementApi ?? LifeMateCareManagementApi.fromEnvironment();

  int _selectedType = 0;
  bool _loading = true;
  bool _working = false;
  String? _error;
  String? _selectedRelationshipId;
  List<Map<String, dynamic>> _relationships = const [];
  List<Map<String, dynamic>> _plans = const [];
  List<Map<String, dynamic>> _events = const [];
  bool _canManageHealthRecord = false;

  Map<String, dynamic>? get _selectedRelationship {
    for (final relationship in _relationships) {
      if (relationship['id']?.toString() == _selectedRelationshipId) {
        return relationship;
      }
    }
    return null;
  }

  String get _patientUserId =>
      _selectedRelationship?['patientUserId']?.toString() ?? '';

  @override
  void initState() {
    super.initState();
    _refresh();
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
      final current = values[0] as Map<String, dynamic>;
      final currentUser = current['user'] as Map<String, dynamic>? ?? const {};
      final currentUserId = currentUser['id']?.toString();
      final relationships = (values[1] as List<Map<String, dynamic>>)
          .where(
            (item) =>
                item['status']?.toString() == 'active' &&
                item['caregiverUserId']?.toString() == currentUserId,
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
        _relationships = relationships;
        _selectedRelationshipId = selectedId;
      });
      await _loadSelectedPatientData();
    } on LifeMateApiException catch (error) {
      _setError(_friendlyError(error));
    } catch (error) {
      debugPrint('CareMate management load failed: $error');
      _setError('اطلاعات درمان دریافت نشد. اتصال اینترنت را بررسی کنید.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadSelectedPatientData() async {
    final relationship = _selectedRelationship;
    if (relationship == null) {
      if (mounted) {
        setState(() {
          _plans = const [];
          _events = const [];
          _canManageHealthRecord = false;
        });
      }
      return;
    }

    final permission = await _managementApi.getRelationshipPermission(
      relationshipId: relationship['id'].toString(),
    );
    final canManage = permission['canManageHealthRecord'] == true;
    if (!canManage) {
      if (mounted) {
        setState(() {
          _plans = const [];
          _events = const [];
          _canManageHealthRecord = false;
        });
      }
      return;
    }

    final patientUserId = relationship['patientUserId'].toString();
    final values = await Future.wait([
      _managementApi.getTreatmentPlans(patientUserId: patientUserId),
      _managementApi.getCareEvents(patientUserId: patientUserId),
    ]);
    if (!mounted) return;
    setState(() {
      _canManageHealthRecord = true;
      _plans = values[0] as List<Map<String, dynamic>>;
      _events = (values[1] as List<Map<String, dynamic>>)
          .where((event) => event['status']?.toString() != 'cancelled')
          .toList(growable: false);
    });
  }

  Future<void> _selectRelationship(String? id) async {
    if (id == null || id == _selectedRelationshipId) return;
    setState(() {
      _selectedRelationshipId = id;
      _loading = true;
      _error = null;
      _plans = const [];
      _events = const [];
      _canManageHealthRecord = false;
    });
    try {
      await _loadSelectedPatientData();
    } on LifeMateApiException catch (error) {
      _setError(_friendlyError(error));
    } catch (error) {
      debugPrint('CareMate patient switch failed: $error');
      _setError('برنامه فرد تحت مراقبت دریافت نشد.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _setError(String message) {
    if (!mounted) return;
    setState(() {
      _error = message;
      _loading = false;
    });
  }

  String _friendlyError(LifeMateApiException error) {
    return switch (error.code) {
      'health_record_management_denied' =>
        'اجازه مشاهده و ویرایش پرونده سلامت برای این مراقب فعال نیست.',
      'stale_treatment_plan' || 'stale_medication' || 'stale_care_event' =>
        'اطلاعات درمان تغییر کرده است. صفحه را تازه کنید و دوباره تلاش کنید.',
      'relationship_not_found' || 'care_access_denied' =>
        'رابطه مراقبتی فعال نیست یا دسترسی شما لغو شده است.',
      _ when error.isUnauthorized => 'نشست شما منقضی شده است. دوباره وارد شوید.',
      _ => 'درخواست انجام نشد. دوباره تلاش کنید.',
    };
  }

  void _notice({
    required LifeMateNoticeType type,
    required String title,
    required String message,
  }) {
    if (!mounted) return;
    LifeMateNotice.show(context, type: type, title: title, message: message);
  }

  Future<void> _runMutation(
    Future<void> Function() mutation, {
    required String successTitle,
    required String successMessage,
  }) async {
    if (_working) return;
    setState(() => _working = true);
    try {
      await mutation();
      _notice(
        type: LifeMateNoticeType.success,
        title: successTitle,
        message: successMessage,
      );
      await _loadSelectedPatientData();
    } on LifeMateApiException catch (error) {
      _notice(
        type: LifeMateNoticeType.error,
        title: 'تغییر ذخیره نشد',
        message: _friendlyError(error),
      );
      if (error.code.startsWith('stale_')) await _loadSelectedPatientData();
    } catch (error) {
      debugPrint('CareMate management mutation failed: $error');
      _notice(
        type: LifeMateNoticeType.error,
        title: 'تغییر ذخیره نشد',
        message: 'اتصال را بررسی کنید و دوباره تلاش کنید.',
      );
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _openMedicationForm([Map<String, dynamic>? plan]) async {
    final patientId = _patientUserId;
    if (patientId.isEmpty || !_canManageHealthRecord) return;
    final draft = await showModalBottomSheet<_MedicationDraft>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _MedicationFormSheet(plan: plan),
    );
    if (draft == null || !mounted) return;

    if (plan == null) {
      await _runMutation(
        () async {
          await _managementApi.createTreatmentPlan(
            patientUserId: patientId,
            medicationName: draft.medicationName,
            strengthText: draft.strengthText,
            form: draft.form,
            doseText: draft.doseText,
            instructions: draft.instructions,
            startDate: draft.startDate,
            endDate: draft.endDate,
            timeZone: 'Asia/Tehran',
            schedules: draft.schedules,
          );
        },
        successTitle: 'دارو اضافه شد',
        successMessage: 'برنامه دارویی در پرونده سلامت ثبت شد.',
      );
      return;
    }

    final medication =
        plan['medication'] as Map<String, dynamic>? ?? const <String, dynamic>{};
    await _runMutation(
      () async {
        await _managementApi.updateTreatmentPlan(
          patientUserId: patientId,
          treatmentPlanId: plan['id'].toString(),
          version: _asInt(plan['version'], 1),
          medicationVersion: _asInt(medication['version'], 1),
          medicationName: draft.medicationName,
          strengthText: draft.strengthText,
          form: draft.form,
          doseText: draft.doseText,
          instructions: draft.instructions,
          startDate: draft.startDate,
          endDate: draft.endDate,
          timeZone: plan['timeZone']?.toString() ?? 'Asia/Tehran',
          schedules: draft.schedules,
          patientReminderMinutesBefore: _asInt(
            plan['patientReminderMinutesBefore'],
            LifeMateReminderLeadTimes.defaultPatientMinutes,
          ),
          caregiverReminderMinutesBefore: _asInt(
            plan['caregiverReminderMinutesBefore'],
            LifeMateReminderLeadTimes.defaultCaregiverMinutes,
          ),
          status: plan['status']?.toString() ?? 'active',
        );
      },
      successTitle: 'دارو ویرایش شد',
      successMessage: 'تغییرات برنامه دارویی ذخیره شد.',
    );
  }

  Future<void> _deleteMedication(Map<String, dynamic> plan) async {
    final confirmed = await _confirmDelete(
      title: 'حذف برنامه دارویی؟',
      message:
          'این برنامه از درمان‌های فعال خارج می‌شود و نوبت‌های آینده آن حذف می‌شوند. سابقه تغییر برای پیگیری امنیتی نگه داشته می‌شود.',
    );
    if (!confirmed || !mounted) return;
    await _runMutation(
      () => _managementApi.deleteTreatmentPlan(
        patientUserId: _patientUserId,
        treatmentPlanId: plan['id'].toString(),
        version: _asInt(plan['version'], 1),
      ),
      successTitle: 'برنامه دارویی حذف شد',
      successMessage: 'این درمان دیگر در برنامه فعال بیمار نیست.',
    );
  }

  Future<void> _openCareEventForm(
    String eventType, [
    Map<String, dynamic>? event,
  ]) async {
    final patientId = _patientUserId;
    if (patientId.isEmpty || !_canManageHealthRecord) return;
    final draft = await showModalBottomSheet<_CareEventDraft>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CareEventFormSheet(eventType: eventType, event: event),
    );
    if (draft == null || !mounted) return;

    if (event == null) {
      await _runMutation(
        () async {
          await _managementApi.createCareEvent(
            patientUserId: patientId,
            clientRequestId: LifeMateApiClient.createClientRequestId(),
            eventType: eventType,
            title: draft.title,
            providerName: draft.providerName,
            specialty: draft.specialty,
            medicationName: eventType == 'injection'
                ? draft.medicationName
                : null,
            doseText: eventType == 'injection' ? draft.doseText : null,
            administrationRoute: eventType == 'injection'
                ? draft.administrationRoute
                : null,
            reason: draft.reason,
            instructions: draft.instructions,
            centerName: draft.centerName,
            addressLine: draft.addressLine,
            phoneNumber: draft.phoneNumber,
            scheduledLocalDate: draft.date,
            scheduledLocalTime: draft.time,
            timeZone: 'Asia/Tehran',
          );
        },
        successTitle: eventType == 'injection' ? 'تزریق اضافه شد' : 'ویزیت اضافه شد',
        successMessage: 'نوبت جدید در پرونده سلامت ثبت شد.',
      );
      return;
    }

    final eventId = event['seriesId']?.toString() ?? event['id'].toString();
    await _runMutation(
      () async {
        await _managementApi.updateCareEvent(
          patientUserId: patientId,
          eventId: eventId,
          version: _asInt(event['version'], 1),
          eventType: eventType,
          title: draft.title,
          providerName: draft.providerName,
          specialty: draft.specialty,
          medicationName: eventType == 'injection'
              ? draft.medicationName
              : null,
          doseText: eventType == 'injection' ? draft.doseText : null,
          administrationRoute: eventType == 'injection'
              ? draft.administrationRoute
              : null,
          reason: draft.reason,
          instructions: draft.instructions,
          centerName: draft.centerName,
          addressLine: draft.addressLine,
          phoneNumber: draft.phoneNumber,
          scheduledLocalDate: draft.date,
          scheduledLocalTime: draft.time,
          timeZone: event['timeZone']?.toString() ?? 'Asia/Tehran',
          patientReminderMinutesBefore: _asInt(
            event['patientReminderMinutesBefore'],
            LifeMateReminderLeadTimes.defaultPatientMinutes,
          ),
          caregiverReminderMinutesBefore: _asInt(
            event['caregiverReminderMinutesBefore'],
            LifeMateReminderLeadTimes.defaultCaregiverMinutes,
          ),
        );
      },
      successTitle: eventType == 'injection' ? 'تزریق ویرایش شد' : 'ویزیت ویرایش شد',
      successMessage: 'تغییرات نوبت ذخیره شد.',
    );
  }

  Future<void> _deleteCareEvent(Map<String, dynamic> event) async {
    final type = event['eventType']?.toString() == 'injection'
        ? 'تزریق'
        : 'ویزیت';
    final confirmed = await _confirmDelete(
      title: 'حذف $type؟',
      message:
          'این نوبت از برنامه فعال حذف می‌شود. سابقه تغییر برای پیگیری امنیتی نگه داشته می‌شود.',
    );
    if (!confirmed || !mounted) return;
    await _runMutation(
      () => _managementApi.deleteCareEvent(
        patientUserId: _patientUserId,
        eventId: event['seriesId']?.toString() ?? event['id'].toString(),
        version: _asInt(event['version'], 1),
      ),
      successTitle: '$type حذف شد',
      successMessage: 'این نوبت دیگر در برنامه فعال بیمار نیست.',
    );
  }

  Future<bool> _confirmDelete({
    required String title,
    required String message,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
        title: Text(title),
        content: Text(message, style: const TextStyle(height: 1.65)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('انصراف'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    return result == true;
  }

  void _onNavigationTap(int index) {
    if (index == 2) return;
    final Widget destination = switch (index) {
      0 => const CalendarScreen(),
      4 => const DashboardScreen(),
      _ => CareMateFeaturePreviewScreen(initialIndex: index),
    };
    Navigator.of(context).pushReplacement(
      PageRouteBuilder<void>(
        pageBuilder: (_, __, ___) => destination,
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final relationship = _selectedRelationship;
    final patientName =
        relationship?['patientDisplayName']?.toString() ?? 'فرد تحت مراقبت';

    final filteredEvents = _events.where((event) {
      final type = event['eventType']?.toString();
      return _selectedType == 0 ? type == 'appointment' : type == 'injection';
    }).toList(growable: false);

    return Scaffold(
      backgroundColor: AppColors.background,
      extendBody: true,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            CustomAppHeader(
              onNotificationTap: () {},
              onSignOutTap: LifeMateAuth.signOut,
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _refresh,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 128),
                  children: [
                    const Text(
                      'مدیریت پرونده سلامت',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: AppColors.primaryText,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      _canManageHealthRecord
                          ? 'با اجازه صریح بیمار، می‌توانید دارو، ویزیت و تزریق را اضافه، ویرایش یا حذف کنید.'
                          : 'دسترسی ویرایش فقط با اجازه صریح بیمار از WellMate فعال می‌شود.',
                      style: const TextStyle(
                        color: AppColors.secondaryText,
                        height: 1.55,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _PatientSelector(
                      relationships: _relationships,
                      selectedId: _selectedRelationshipId,
                      onChanged: _loading ? null : _selectRelationship,
                    ),
                    const SizedBox(height: 16),
                    _TypeSelector(
                      selectedIndex: _selectedType,
                      onChanged: (index) => setState(() => _selectedType = index),
                    ),
                    const SizedBox(height: 18),
                    if (_error != null) ...[
                      _ErrorCard(message: _error!, onRetry: _refresh),
                      const SizedBox(height: 16),
                    ],
                    if (_loading)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 80),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else if (relationship == null)
                      const _NoPatientState()
                    else if (!_canManageHealthRecord)
                      _LockedManagementCard(patientName: patientName)
                    else ...[
                      _GrantedPermissionCard(patientName: patientName),
                      const SizedBox(height: 16),
                      switch (_selectedType) {
                        1 => _MedicationWorkspace(
                          plans: _plans,
                          working: _working,
                          onAdd: () => _openMedicationForm(),
                          onEdit: _openMedicationForm,
                          onDelete: _deleteMedication,
                        ),
                        0 => _CareEventWorkspace(
                          type: 'appointment',
                          events: filteredEvents,
                          working: _working,
                          onAdd: () => _openCareEventForm('appointment'),
                          onEdit: (event) =>
                              _openCareEventForm('appointment', event),
                          onDelete: _deleteCareEvent,
                        ),
                        _ => _CareEventWorkspace(
                          type: 'injection',
                          events: filteredEvents,
                          working: _working,
                          onAdd: () => _openCareEventForm('injection'),
                          onEdit: (event) =>
                              _openCareEventForm('injection', event),
                          onDelete: _deleteCareEvent,
                        ),
                      },
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: CareMateBottomNav(
        currentIndex: 2,
        onTap: _onNavigationTap,
      ),
    );
  }
}

class _TypeSelector extends StatelessWidget {
  const _TypeSelector({required this.selectedIndex, required this.onChanged});

  final int selectedIndex;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    const items = [
      (Icons.medical_services_rounded, 'ویزیت'),
      (Icons.medication_rounded, 'دارو'),
      (Icons.vaccines_rounded, 'تزریق'),
    ];
    return Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryBlue.withValues(alpha: 0.08),
            blurRadius: 18,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: Row(
        children: List.generate(items.length, (index) {
          final selected = selectedIndex == index;
          return Expanded(
            child: Semantics(
              button: true,
              selected: selected,
              label: items[index].$2,
              child: InkWell(
                key: ValueKey('caremate-care-type-$index'),
                borderRadius: BorderRadius.circular(17),
                onTap: () => onChanged(index),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  constraints: const BoxConstraints(minHeight: 58),
                  decoration: BoxDecoration(
                    color: selected
                        ? AppColors.primaryBlue
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(17),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        items[index].$1,
                        size: 21,
                        color: selected ? Colors.white : AppColors.secondaryText,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        items[index].$2,
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                          color: selected ? Colors.white : AppColors.secondaryText,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

class _PatientSelector extends StatelessWidget {
  const _PatientSelector({
    required this.relationships,
    required this.selectedId,
    required this.onChanged,
  });

  final List<Map<String, dynamic>> relationships;
  final String? selectedId;
  final ValueChanged<String?>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: relationships.isEmpty
          ? const ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(
                backgroundColor: Color(0xFFEAF4FF),
                child: Icon(Icons.person_search_rounded, color: AppColors.primaryBlue),
              ),
              title: Text('فرد تحت مراقبت انتخاب نشده'),
              subtitle: Text('ابتدا دعوت معتبر بیمار را بپذیرید.'),
            )
          : DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: selectedId,
                isExpanded: true,
                borderRadius: BorderRadius.circular(18),
                icon: const Icon(Icons.keyboard_arrow_down_rounded),
                items: relationships
                    .map(
                      (relationship) => DropdownMenuItem<String>(
                        value: relationship['id']?.toString(),
                        child: Text(
                          relationship['patientDisplayName']?.toString() ??
                              'فرد تحت مراقبت',
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                    )
                    .toList(growable: false),
                onChanged: onChanged,
              ),
            ),
    );
  }
}

class _LockedManagementCard extends StatelessWidget {
  const _LockedManagementCard({required this.patientName});

  final String patientName;

  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('caremate-health-management-locked'),
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        begin: Alignment.topRight,
        end: Alignment.bottomLeft,
        colors: [Color(0xFFF4F1FF), Color(0xFFEAF4FF)],
      ),
      borderRadius: BorderRadius.circular(26),
      border: Border.all(color: const Color(0xFFD9D7F7)),
    ),
    child: Column(
      children: [
        const CircleAvatar(
          radius: 27,
          backgroundColor: Colors.white,
          child: Icon(Icons.lock_rounded, color: Color(0xFF6C74D9), size: 28),
        ),
        const SizedBox(height: 14),
        const Text(
          'اجازه مدیریت پرونده فعال نیست',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 7),
        Text(
          '$patientName باید در WellMate از «تنظیمات دسترسی» گزینه «مشاهده و ویرایش پرونده سلامت» را با تأیید آگاهانه فعال کند.',
          textAlign: TextAlign.center,
          style: const TextStyle(height: 1.65, color: AppColors.secondaryText),
        ),
      ],
    ),
  );
}

class _GrantedPermissionCard extends StatelessWidget {
  const _GrantedPermissionCard({required this.patientName});

  final String patientName;

  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('caremate-health-management-granted'),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: const Color(0xFFEAF8F2),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: const Color(0xFFC8EEDD)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.verified_user_rounded, color: Color(0xFF21855F)),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            'اجازه صریح $patientName فعال است. هر تغییر با حساب شما ثبت می‌شود و بیمار می‌تواند هر زمان این دسترسی را لغو کند.',
            style: const TextStyle(height: 1.55, color: Color(0xFF256349)),
          ),
        ),
      ],
    ),
  );
}

class _MedicationWorkspace extends StatelessWidget {
  const _MedicationWorkspace({
    required this.plans,
    required this.working,
    required this.onAdd,
    required this.onEdit,
    required this.onDelete,
  });

  final List<Map<String, dynamic>> plans;
  final bool working;
  final VoidCallback onAdd;
  final ValueChanged<Map<String, dynamic>> onEdit;
  final ValueChanged<Map<String, dynamic>> onDelete;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      _WorkspaceHeader(
        icon: Icons.medication_rounded,
        title: 'داروها',
        actionLabel: 'افزودن دارو',
        working: working,
        onAdd: onAdd,
      ),
      const SizedBox(height: 12),
      if (plans.isEmpty)
        const _InlineEmpty(text: 'برنامه دارویی فعالی ثبت نشده است.')
      else
        ...plans.map(
          (plan) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _TreatmentPlanCard(
              plan: plan,
              working: working,
              onEdit: () => onEdit(plan),
              onDelete: () => onDelete(plan),
            ),
          ),
        ),
    ],
  );
}

class _CareEventWorkspace extends StatelessWidget {
  const _CareEventWorkspace({
    required this.type,
    required this.events,
    required this.working,
    required this.onAdd,
    required this.onEdit,
    required this.onDelete,
  });

  final String type;
  final List<Map<String, dynamic>> events;
  final bool working;
  final VoidCallback onAdd;
  final ValueChanged<Map<String, dynamic>> onEdit;
  final ValueChanged<Map<String, dynamic>> onDelete;

  @override
  Widget build(BuildContext context) {
    final injection = type == 'injection';
    return Column(
      children: [
        _WorkspaceHeader(
          icon: injection ? Icons.vaccines_rounded : Icons.medical_services_rounded,
          title: injection ? 'تزریق‌ها' : 'ویزیت‌ها',
          actionLabel: injection ? 'افزودن تزریق' : 'افزودن ویزیت',
          working: working,
          onAdd: onAdd,
        ),
        const SizedBox(height: 12),
        if (events.isEmpty)
          _InlineEmpty(
            text: injection
                ? 'تزریق فعالی در این بازه ثبت نشده است.'
                : 'ویزیت فعالی در این بازه ثبت نشده است.',
          )
        else
          ...events.map(
            (event) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _CareEventCard(
                event: event,
                working: working,
                onEdit: () => onEdit(event),
                onDelete: () => onDelete(event),
              ),
            ),
          ),
      ],
    );
  }
}

class _WorkspaceHeader extends StatelessWidget {
  const _WorkspaceHeader({
    required this.icon,
    required this.title,
    required this.actionLabel,
    required this.working,
    required this.onAdd,
  });

  final IconData icon;
  final String title;
  final String actionLabel;
  final bool working;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      CircleAvatar(
        backgroundColor: const Color(0xFFEAF4FF),
        child: Icon(icon, color: AppColors.primaryBlue),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: Text(
          title,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
        ),
      ),
      FilledButton.icon(
        key: ValueKey('caremate-add-$title'),
        onPressed: working ? null : onAdd,
        icon: const Icon(Icons.add_rounded, size: 18),
        label: Text(actionLabel),
      ),
    ],
  );
}

class _TreatmentPlanCard extends StatelessWidget {
  const _TreatmentPlanCard({
    required this.plan,
    required this.working,
    required this.onEdit,
    required this.onDelete,
  });

  final Map<String, dynamic> plan;
  final bool working;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final medication =
        plan['medication'] as Map<String, dynamic>? ?? const <String, dynamic>{};
    final schedules = plan['schedules'] as List<dynamic>? ?? const [];
    final times = schedules
        .map((item) => item is Map ? item['localTime']?.toString() : null)
        .whereType<String>()
        .toSet()
        .join('، ');
    return _ManagementCard(
      key: ValueKey('caremate-plan-${plan['id']}'),
      icon: Icons.medication_rounded,
      iconColor: const Color(0xFF2D9B74),
      title: medication['name']?.toString() ?? 'دارو',
      subtitle: [
        plan['doseText']?.toString(),
        times.isEmpty ? null : times,
      ].whereType<String>().where((value) => value.trim().isNotEmpty).join(' • '),
      working: working,
      onEdit: onEdit,
      onDelete: onDelete,
    );
  }
}

class _CareEventCard extends StatelessWidget {
  const _CareEventCard({
    required this.event,
    required this.working,
    required this.onEdit,
    required this.onDelete,
  });

  final Map<String, dynamic> event;
  final bool working;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final injection = event['eventType']?.toString() == 'injection';
    final rawDate = event['scheduledLocalDate']?.toString() ?? '';
    final parsedDate = DateTime.tryParse(rawDate);
    final date = parsedDate == null
        ? localizeDigits(context, rawDate)
        : formatAppDate(context, parsedDate);
    final rawTime = event['scheduledLocalTime']?.toString() ?? '--:--';
    final time = localizeDigits(
      context,
      rawTime.length >= 5 ? rawTime.substring(0, 5) : rawTime,
    );
    return _ManagementCard(
      key: ValueKey('caremate-event-${event['id']}'),
      icon: injection ? Icons.vaccines_rounded : Icons.medical_services_rounded,
      iconColor: injection ? const Color(0xFFD96570) : AppColors.primaryBlue,
      title: event['title']?.toString() ?? (injection ? 'تزریق' : 'ویزیت'),
      subtitle: '$date • $time${_detailSuffix(event)}',
      working: working,
      onEdit: onEdit,
      onDelete: onDelete,
    );
  }

  String _detailSuffix(Map<String, dynamic> event) {
    final center = event['centerName']?.toString().trim();
    return center == null || center.isEmpty ? '' : ' • $center';
  }
}

class _ManagementCard extends StatelessWidget {
  const _ManagementCard({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.working,
    required this.onEdit,
    required this.onDelete,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final bool working;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(21),
      boxShadow: [
        BoxShadow(
          color: AppColors.primaryBlue.withValues(alpha: 0.05),
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
            color: iconColor.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(15),
          ),
          child: Icon(icon, color: iconColor),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
              if (subtitle.trim().isNotEmpty) ...[
                const SizedBox(height: 5),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: AppColors.secondaryText,
                    fontSize: 11.5,
                    height: 1.4,
                  ),
                ),
              ],
            ],
          ),
        ),
        IconButton(
          key: const ValueKey('caremate-edit-treatment'),
          tooltip: 'ویرایش',
          onPressed: working ? null : onEdit,
          icon: const Icon(Icons.edit_outlined),
        ),
        IconButton(
          key: const ValueKey('caremate-delete-treatment'),
          tooltip: 'حذف',
          onPressed: working ? null : onDelete,
          color: Colors.redAccent,
          icon: const Icon(Icons.delete_outline_rounded),
        ),
      ],
    ),
  );
}

class _InlineEmpty extends StatelessWidget {
  const _InlineEmpty({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: const TextStyle(color: AppColors.secondaryText),
    ),
  );
}

class _NoPatientState extends StatelessWidget {
  const _NoPatientState();

  @override
  Widget build(BuildContext context) => const _InlineEmpty(
    text: 'برای مدیریت درمان، ابتدا یک بیمار را با دعوت و رضایت معتبر متصل کنید.',
  );
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: const Color(0xFFFFF0F1),
      borderRadius: BorderRadius.circular(18),
    ),
    child: Row(
      children: [
        const Icon(Icons.error_outline_rounded, color: Colors.redAccent),
        const SizedBox(width: 9),
        Expanded(child: Text(message)),
        TextButton(onPressed: onRetry, child: const Text('تلاش دوباره')),
      ],
    ),
  );
}
