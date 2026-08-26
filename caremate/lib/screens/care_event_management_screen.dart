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
  const CareEventManagementScreen({
    super.key,
    this.managementApi,
    this.refreshToken = 0,
    this.onNavigationTap,
  });

  final LifeMateCareManagementApi? managementApi;
  final int refreshToken;
  final ValueChanged<int>? onNavigationTap;

  @override
  State<CareEventManagementScreen> createState() =>
      _CareEventManagementScreenState();
}

class _CareEventManagementScreenState extends State<CareEventManagementScreen> {
  late final LifeMateCareManagementApi _managementApi =
      widget.managementApi ?? LifeMateCareManagementApi.fromEnvironment();

  int _selectedType = 0;
  bool _loading = true;
  bool _backgroundRefreshing = false;
  bool _working = false;
  String? _error;
  String? _selectedRelationshipId;
  List<Map<String, dynamic>> _relationships = const [];
  List<Map<String, dynamic>> _plans = const [];
  List<Map<String, dynamic>> _events = const [];
  bool _canManageHealthRecord = false;

  @override
  void didUpdateWidget(covariant CareEventManagementScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshToken != widget.refreshToken) {
      _refresh(background: true);
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

  String get _patientUserId =>
      _selectedRelationship?['patientUserId']?.toString() ?? '';

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh({bool background = false}) async {
    if (mounted) {
      setState(() {
        if (_relationships.isEmpty) {
          _loading = true;
        } else if (background) {
          _backgroundRefreshing = true;
        }
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
      _setError(
        LifeMateRuntimeLocale.select(
          fa: LifeMateRuntimeLocale.select(
            fa: 'اطلاعات درمان دریافت نشد. اتصال اینترنت را بررسی کنید.',
            en: "Treatment information not received. Check your internet connection.",
          ),
          en: "Treatment information not received. Check your internet connection.",
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _backgroundRefreshing = false;
        });
      }
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
      _setError(
        LifeMateRuntimeLocale.select(
          fa: LifeMateRuntimeLocale.select(
            fa: 'برنامه فرد تحت مراقبت دریافت نشد.',
            en: "Caregiver application not received.",
          ),
          en: "Caregiver application not received.",
        ),
      );
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
      'health_record_management_denied' => LifeMateRuntimeLocale.select(
        fa: LifeMateRuntimeLocale.select(
          fa: 'اجازه مشاهده و ویرایش پرونده سلامت برای این مراقب فعال نیست.',
          en: "The permission to view and edit the health record is not active for this caregiver.",
        ),
        en: "The permission to view and edit the health record is not active for this caregiver.",
      ),
      'stale_treatment_plan' ||
      'stale_medication' ||
      'stale_care_event' => LifeMateRuntimeLocale.select(
        fa: LifeMateRuntimeLocale.select(
          fa: 'اطلاعات درمان تغییر کرده است. صفحه را تازه کنید و دوباره تلاش کنید.',
          en: "Treatment information has changed. Refresh the page and try again.",
        ),
        en: "Treatment information has changed. Refresh the page and try again.",
      ),
      'relationship_not_found' ||
      'care_access_denied' => LifeMateRuntimeLocale.select(
        fa: LifeMateRuntimeLocale.select(
          fa: 'رابطه مراقبتی فعال نیست یا دسترسی شما لغو شده است.',
          en: "The care relationship is not active or your access has been revoked.",
        ),
        en: "The care relationship is not active or your access has been revoked.",
      ),
      _ when error.isUnauthorized => LifeMateRuntimeLocale.select(
        fa: LifeMateRuntimeLocale.select(
          fa: 'نشست شما منقضی شده است. دوباره وارد شوید.',
          en: "Your session has expired. Sign in again.",
        ),
        en: "Your session has expired. Sign in again.",
      ),
      _ => LifeMateRuntimeLocale.select(
        fa: LifeMateRuntimeLocale.select(
          fa: 'درخواست انجام نشد. دوباره تلاش کنید.',
          en: "Request failed. Try again.",
        ),
        en: "Request failed. Try again.",
      ),
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
        title: LifeMateRuntimeLocale.select(
          fa: LifeMateRuntimeLocale.select(
            fa: 'تغییر ذخیره نشد',
            en: "The change was not saved",
          ),
          en: "The change was not saved",
        ),
        message: _friendlyError(error),
      );
      if (error.code.startsWith('stale_')) await _loadSelectedPatientData();
    } catch (error) {
      debugPrint('CareMate management mutation failed: $error');
      _notice(
        type: LifeMateNoticeType.error,
        title: LifeMateRuntimeLocale.select(
          fa: LifeMateRuntimeLocale.select(
            fa: 'تغییر ذخیره نشد',
            en: "The change was not saved",
          ),
          en: "The change was not saved",
        ),
        message: LifeMateRuntimeLocale.select(
          fa: LifeMateRuntimeLocale.select(
            fa: 'اتصال را بررسی کنید و دوباره تلاش کنید.',
            en: "Check the connection and try again.",
          ),
          en: "Check the connection and try again.",
        ),
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
            recurrence: draft.recurrence,
            recurrenceStartLocalTime: draft.recurrenceStartLocalTime,
          );
        },
        successTitle: LifeMateRuntimeLocale.select(
          fa: LifeMateRuntimeLocale.select(
            fa: 'دارو اضافه شد',
            en: "The drug was added",
          ),
          en: "The drug was added",
        ),
        successMessage: LifeMateRuntimeLocale.select(
          fa: LifeMateRuntimeLocale.select(
            fa: 'برنامه دارویی در پرونده سلامت ثبت شد.',
            en: "The drug program was recorded in the health record.",
          ),
          en: "The drug program was recorded in the health record.",
        ),
      );
      return;
    }

    final medication =
        plan['medication'] as Map<String, dynamic>? ??
        const <String, dynamic>{};
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
          recurrence: draft.recurrence,
          recurrenceStartLocalTime: draft.recurrenceStartLocalTime,
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
      successTitle: LifeMateRuntimeLocale.select(
        fa: LifeMateRuntimeLocale.select(
          fa: 'دارو ویرایش شد',
          en: "The medicine was edited",
        ),
        en: "The medicine was edited",
      ),
      successMessage: LifeMateRuntimeLocale.select(
        fa: LifeMateRuntimeLocale.select(
          fa: 'تغییرات برنامه دارویی ذخیره شد.',
          en: "Medication schedule changes saved.",
        ),
        en: "Medication schedule changes saved.",
      ),
    );
  }

  Future<void> _deleteMedication(Map<String, dynamic> plan) async {
    final confirmed = await _confirmDelete(
      title: LifeMateRuntimeLocale.select(
        fa: LifeMateRuntimeLocale.select(
          fa: 'حذف برنامه دارویی؟',
          en: "Delete the drug program?",
        ),
        en: "Delete the drug program?",
      ),
      message: LifeMateRuntimeLocale.select(
        fa: LifeMateRuntimeLocale.select(
          fa: 'این برنامه از درمان‌های فعال خارج می‌شود و نوبت‌های آینده آن حذف می‌شوند. سابقه تغییر برای پیگیری امنیتی نگه داشته می‌شود.',
          en: "This program will be removed from active treatments and future appointments will be removed. Change history is kept for security tracking.",
        ),
        en: "This program will be removed from active treatments and future appointments will be removed. Change history is kept for security tracking.",
      ),
    );
    if (!confirmed || !mounted) return;
    await _runMutation(
      () => _managementApi.deleteTreatmentPlan(
        patientUserId: _patientUserId,
        treatmentPlanId: plan['id'].toString(),
        version: _asInt(plan['version'], 1),
      ),
      successTitle: LifeMateRuntimeLocale.select(
        fa: LifeMateRuntimeLocale.select(
          fa: 'برنامه دارویی حذف شد',
          en: "The drug program was removed",
        ),
        en: "The drug program was removed",
      ),
      successMessage: LifeMateRuntimeLocale.select(
        fa: LifeMateRuntimeLocale.select(
          fa: 'این درمان دیگر در برنامه فعال بیمار نیست.',
          en: "This treatment is no longer on the patient's active schedule.",
        ),
        en: "This treatment is no longer on the patient's active schedule.",
      ),
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
            recurrence: draft.recurrence,
          );
        },
        successTitle: eventType == 'injection'
            ? LifeMateRuntimeLocale.select(
                fa: LifeMateRuntimeLocale.select(
                  fa: 'تزریق اضافه شد',
                  en: "injection was added",
                ),
                en: "injection was added",
              )
            : LifeMateRuntimeLocale.select(
                fa: LifeMateRuntimeLocale.select(
                  fa: 'ویزیت اضافه شد',
                  en: "Visit added",
                ),
                en: "Visit added",
              ),
        successMessage: LifeMateRuntimeLocale.select(
          fa: LifeMateRuntimeLocale.select(
            fa: 'نوبت جدید در پرونده سلامت ثبت شد.',
            en: "The new appointment was registered in the health file.",
          ),
          en: "The new appointment was registered in the health file.",
        ),
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
          recurrence: draft.recurrence,
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
      successTitle: eventType == 'injection'
          ? LifeMateRuntimeLocale.select(
              fa: LifeMateRuntimeLocale.select(
                fa: 'تزریق ویرایش شد',
                en: "The injection was edited",
              ),
              en: "The injection was edited",
            )
          : LifeMateRuntimeLocale.select(
              fa: LifeMateRuntimeLocale.select(
                fa: 'ویزیت ویرایش شد',
                en: "The visit was edited",
              ),
              en: "The visit was edited",
            ),
      successMessage: LifeMateRuntimeLocale.select(
        fa: LifeMateRuntimeLocale.select(
          fa: 'تغییرات نوبت ذخیره شد.',
          en: "Turn changes saved.",
        ),
        en: "Turn changes saved.",
      ),
    );
  }

  Future<void> _deleteCareEvent(Map<String, dynamic> event) async {
    final type = event['eventType']?.toString() == 'injection'
        ? LifeMateRuntimeLocale.select(
            fa: LifeMateRuntimeLocale.select(fa: 'تزریق', en: "Injection"),
            en: "Injection",
          )
        : LifeMateRuntimeLocale.select(
            fa: LifeMateRuntimeLocale.select(fa: 'ویزیت', en: "Appointment"),
            en: "visit",
          );
    final confirmed = await _confirmDelete(
      title: LifeMateRuntimeLocale.select(
        fa: LifeMateRuntimeLocale.select(fa: 'حذف $type؟', en: "Delete $type?"),
        en: "Delete $type?",
      ),
      message: LifeMateRuntimeLocale.select(
        fa: LifeMateRuntimeLocale.select(
          fa: 'این نوبت از برنامه فعال حذف می‌شود. سابقه تغییر برای پیگیری امنیتی نگه داشته می‌شود.',
          en: "This turn will be removed from the active program. Change history is kept for security tracking.",
        ),
        en: "This turn will be removed from the active program. Change history is kept for security tracking.",
      ),
    );
    if (!confirmed || !mounted) return;
    await _runMutation(
      () => _managementApi.deleteCareEvent(
        patientUserId: _patientUserId,
        eventId: event['seriesId']?.toString() ?? event['id'].toString(),
        version: _asInt(event['version'], 1),
      ),
      successTitle: LifeMateRuntimeLocale.select(
        fa: LifeMateRuntimeLocale.select(
          fa: '$type حذف شد',
          en: "$type removed",
        ),
        en: "$type removed",
      ),
      successMessage: LifeMateRuntimeLocale.select(
        fa: LifeMateRuntimeLocale.select(
          fa: 'این نوبت دیگر در برنامه فعال بیمار نیست.',
          en: "This appointment is no longer in the patient's active schedule.",
        ),
        en: "This appointment is no longer in the patient's active schedule.",
      ),
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
        icon: Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
        title: Text(title),
        content: Text(message, style: TextStyle(height: 1.65)),
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
                fa: LifeMateRuntimeLocale.select(fa: 'حذف', en: "Delete"),
                en: "remove",
              ),
            ),
          ),
        ],
      ),
    );
    return result == true;
  }

  void _onNavigationTap(int index) {
    final shellNavigation = widget.onNavigationTap;
    if (shellNavigation != null) {
      shellNavigation(index);
      return;
    }
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
        relationship?['patientDisplayName']?.toString() ??
        LifeMateRuntimeLocale.select(
          fa: LifeMateRuntimeLocale.select(
            fa: 'فرد تحت مراقبت',
            en: "Person under care",
          ),
          en: "Person under care",
        );

    final filteredEvents = _events
        .where((event) {
          final type = event['eventType']?.toString();
          return _selectedType == 0
              ? type == 'appointment'
              : type == 'injection';
        })
        .toList(growable: false);

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
            if (_backgroundRefreshing) LinearProgressIndicator(minHeight: 2),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _refresh,
                child: ListView(
                  physics: AlwaysScrollableScrollPhysics(),
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: EdgeInsets.fromLTRB(20, 8, 20, 128),
                  children: [
                    Text(
                      LifeMateRuntimeLocale.select(
                        fa: LifeMateRuntimeLocale.select(
                          fa: 'مدیریت پرونده سلامت',
                          en: "Health case management",
                        ),
                        en: "Health case management",
                      ),
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: AppColors.primaryText,
                      ),
                    ),
                    SizedBox(height: 5),
                    Text(
                      _canManageHealthRecord
                          ? LifeMateRuntimeLocale.select(
                              fa: LifeMateRuntimeLocale.select(
                                fa: 'با اجازه صریح بیمار، می‌توانید دارو، ویزیت و تزریق را اضافه، ویرایش یا حذف کنید.',
                                en: "With the patient's express permission, you can add, edit, or delete medications, visits, and injections.",
                              ),
                              en: "With the patient's express permission, you can add, edit, or delete medications, visits, and injections.",
                            )
                          : LifeMateRuntimeLocale.select(
                              fa: LifeMateRuntimeLocale.select(
                                fa: 'دسترسی ویرایش فقط با اجازه صریح بیمار از WellMate فعال می‌شود.',
                                en: "Editing access is enabled only with the patient's express permission from WellMate.",
                              ),
                              en: "Editing access is enabled only with the patient's express permission from WellMate.",
                            ),
                      style: TextStyle(
                        color: AppColors.secondaryText,
                        height: 1.55,
                      ),
                    ),
                    SizedBox(height: 16),
                    _PatientSelector(
                      relationships: _relationships,
                      selectedId: _selectedRelationshipId,
                      onChanged: _loading ? null : _selectRelationship,
                    ),
                    SizedBox(height: 16),
                    _TypeSelector(
                      selectedIndex: _selectedType,
                      onChanged: (index) =>
                          setState(() => _selectedType = index),
                    ),
                    SizedBox(height: 18),
                    if (_error != null) ...[
                      _ErrorCard(message: _error!, onRetry: _refresh),
                      SizedBox(height: 16),
                    ],
                    if (_loading && _relationships.isEmpty)
                      Padding(
                        padding: EdgeInsets.symmetric(vertical: 80),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else if (relationship == null)
                      _NoPatientState()
                    else if (!_canManageHealthRecord)
                      _LockedManagementCard(patientName: patientName)
                    else ...[
                      _GrantedPermissionCard(patientName: patientName),
                      SizedBox(height: 16),
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
        routeTreatmentScreen: widget.onNavigationTap == null,
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
    final items = [
      (
        Icons.medical_services_rounded,
        LifeMateRuntimeLocale.select(
          fa: LifeMateRuntimeLocale.select(fa: 'ویزیت', en: "Appointment"),
          en: "visit",
        ),
      ),
      (
        Icons.medication_rounded,
        LifeMateRuntimeLocale.select(
          fa: LifeMateRuntimeLocale.select(fa: 'دارو', en: "Medication"),
          en: "medicine",
        ),
      ),
      (
        Icons.vaccines_rounded,
        LifeMateRuntimeLocale.select(
          fa: LifeMateRuntimeLocale.select(fa: 'تزریق', en: "Injection"),
          en: "Injection",
        ),
      ),
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
                        color: selected
                            ? Colors.white
                            : AppColors.secondaryText,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        items[index].$2,
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                          color: selected
                              ? Colors.white
                              : AppColors.secondaryText,
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
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: relationships.isEmpty
          ? ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(
                backgroundColor: Color(0xFFEAF4FF),
                child: Icon(
                  Icons.person_search_rounded,
                  color: AppColors.primaryBlue,
                ),
              ),
              title: Text(
                LifeMateRuntimeLocale.select(
                  fa: LifeMateRuntimeLocale.select(
                    fa: 'فرد تحت مراقبت انتخاب نشده',
                    en: "Caregiver not selected",
                  ),
                  en: "Caregiver not selected",
                ),
              ),
              subtitle: Text(
                LifeMateRuntimeLocale.select(
                  fa: LifeMateRuntimeLocale.select(
                    fa: 'ابتدا دعوت معتبر بیمار را بپذیرید.',
                    en: "First, accept the patient's valid invitation.",
                  ),
                  en: "First, accept the patient's valid invitation.",
                ),
              ),
            )
          : DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: selectedId,
                isExpanded: true,
                borderRadius: BorderRadius.circular(18),
                icon: Icon(Icons.keyboard_arrow_down_rounded),
                items: relationships
                    .map(
                      (relationship) => DropdownMenuItem<String>(
                        value: relationship['id']?.toString(),
                        child: Text(
                          relationship['patientDisplayName']?.toString() ??
                              LifeMateRuntimeLocale.select(
                                fa: LifeMateRuntimeLocale.select(
                                  fa: 'فرد تحت مراقبت',
                                  en: "Person under care",
                                ),
                                en: "Person under care",
                              ),
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontWeight: FontWeight.w800),
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
    key: ValueKey('caremate-health-management-locked'),
    padding: EdgeInsets.all(20),
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topRight,
        end: Alignment.bottomLeft,
        colors: [Color(0xFFF4F1FF), Color(0xFFEAF4FF)],
      ),
      borderRadius: BorderRadius.circular(26),
      border: Border.all(color: Color(0xFFD9D7F7)),
    ),
    child: Column(
      children: [
        CircleAvatar(
          radius: 27,
          backgroundColor: Colors.white,
          child: Icon(Icons.lock_rounded, color: Color(0xFF6C74D9), size: 28),
        ),
        SizedBox(height: 14),
        Text(
          LifeMateRuntimeLocale.select(
            fa: LifeMateRuntimeLocale.select(
              fa: 'اجازه مدیریت پرونده فعال نیست',
              en: "File management permission is not enabled",
            ),
            en: "File management permission is not enabled",
          ),
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
        ),
        SizedBox(height: 7),
        Text(
          LifeMateRuntimeLocale.select(
            fa: LifeMateRuntimeLocale.select(
              fa: '$patientName باید در WellMate از «تنظیمات دسترسی» گزینه «مشاهده و ویرایش پرونده سلامت» را با تأیید آگاهانه فعال کند.',
              en: "$patientName must enable the \"View and Edit Health Record\" option in WellMate from \"Access Settings\" with informed consent.",
            ),
            en: "$patientName must enable the \"View and Edit Health Record\" option in WellMate from \"Access Settings\" with informed consent.",
          ),
          textAlign: TextAlign.center,
          style: TextStyle(height: 1.65, color: AppColors.secondaryText),
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
    key: ValueKey('caremate-health-management-granted'),
    padding: EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Color(0xFFEAF8F2),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: Color(0xFFC8EEDD)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.verified_user_rounded, color: Color(0xFF21855F)),
        SizedBox(width: 10),
        Expanded(
          child: Text(
            LifeMateRuntimeLocale.select(
              fa: LifeMateRuntimeLocale.select(
                fa: 'اجازه صریح $patientName فعال است. هر تغییر با حساب شما ثبت می‌شود و بیمار می‌تواند هر زمان این دسترسی را لغو کند.',
                en: "$patientName explicit permission is enabled. Any changes are registered with your account and the patient can revoke this access at any time.",
              ),
              en: "$patientName explicit permission is enabled. Any changes are registered with your account and the patient can revoke this access at any time.",
            ),
            style: TextStyle(height: 1.55, color: Color(0xFF256349)),
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
        title: LifeMateRuntimeLocale.select(
          fa: LifeMateRuntimeLocale.select(fa: 'داروها', en: "Medications"),
          en: "Medicines",
        ),
        actionLabel: LifeMateRuntimeLocale.select(
          fa: LifeMateRuntimeLocale.select(
            fa: 'افزودن دارو',
            en: "Addition of medicine",
          ),
          en: "Addition of medicine",
        ),
        working: working,
        onAdd: onAdd,
      ),
      SizedBox(height: 12),
      if (plans.isEmpty)
        _InlineEmpty(
          text: LifeMateRuntimeLocale.select(
            fa: LifeMateRuntimeLocale.select(
              fa: 'برنامه دارویی فعالی ثبت نشده است.',
              en: "No active medication program has been registered.",
            ),
            en: "No active medication program has been registered.",
          ),
        )
      else
        ...plans.map(
          (plan) => Padding(
            padding: EdgeInsets.only(bottom: 10),
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
          icon: injection
              ? Icons.vaccines_rounded
              : Icons.medical_services_rounded,
          title: injection
              ? LifeMateRuntimeLocale.select(
                  fa: LifeMateRuntimeLocale.select(
                    fa: 'تزریق‌ها',
                    en: "Injections",
                  ),
                  en: "Injections",
                )
              : LifeMateRuntimeLocale.select(
                  fa: LifeMateRuntimeLocale.select(
                    fa: 'ویزیت‌ها',
                    en: "Appointments",
                  ),
                  en: "visits",
                ),
          actionLabel: injection
              ? LifeMateRuntimeLocale.select(
                  fa: LifeMateRuntimeLocale.select(
                    fa: 'افزودن تزریق',
                    en: "Add injection",
                  ),
                  en: "Add injection",
                )
              : LifeMateRuntimeLocale.select(
                  fa: LifeMateRuntimeLocale.select(
                    fa: 'افزودن ویزیت',
                    en: "Add a visit",
                  ),
                  en: "Add a visit",
                ),
          working: working,
          onAdd: onAdd,
        ),
        SizedBox(height: 12),
        if (events.isEmpty)
          _InlineEmpty(
            text: injection
                ? LifeMateRuntimeLocale.select(
                    fa: LifeMateRuntimeLocale.select(
                      fa: 'تزریق فعالی در این بازه ثبت نشده است.',
                      en: "No active injection has been registered in this period.",
                    ),
                    en: "No active injection has been registered in this period.",
                  )
                : LifeMateRuntimeLocale.select(
                    fa: LifeMateRuntimeLocale.select(
                      fa: 'ویزیت فعالی در این بازه ثبت نشده است.',
                      en: "No active visits have been registered in this period.",
                    ),
                    en: "No active visits have been registered in this period.",
                  ),
          )
        else
          ...events.map(
            (event) => Padding(
              padding: EdgeInsets.only(bottom: 10),
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
        plan['medication'] as Map<String, dynamic>? ??
        const <String, dynamic>{};
    final schedules = plan['schedules'] as List<dynamic>? ?? const [];
    final times = schedules
        .map((item) => item is Map ? item['localTime']?.toString() : null)
        .whereType<String>()
        .toSet()
        .join(
          LifeMateRuntimeLocale.select(
            fa: LifeMateRuntimeLocale.select(fa: '، ', en: ","),
            en: ",",
          ),
        );
    return _ManagementCard(
      key: ValueKey('caremate-plan-${plan['id']}'),
      icon: Icons.medication_rounded,
      iconColor: Color(0xFF2D9B74),
      title:
          medication['name']?.toString() ??
          LifeMateRuntimeLocale.select(
            fa: LifeMateRuntimeLocale.select(fa: 'دارو', en: "Medication"),
            en: "medicine",
          ),
      subtitle: [plan['doseText']?.toString(), times.isEmpty ? null : times]
          .whereType<String>()
          .where((value) => value.trim().isNotEmpty)
          .join(' • '),
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
      iconColor: injection ? Color(0xFFD96570) : AppColors.primaryBlue,
      title:
          event['title']?.toString() ??
          (injection
              ? LifeMateRuntimeLocale.select(
                  fa: LifeMateRuntimeLocale.select(
                    fa: 'تزریق',
                    en: "Injection",
                  ),
                  en: "Injection",
                )
              : LifeMateRuntimeLocale.select(
                  fa: LifeMateRuntimeLocale.select(
                    fa: 'ویزیت',
                    en: "Appointment",
                  ),
                  en: "visit",
                )),
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
        SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: TextStyle(fontWeight: FontWeight.w900)),
              if (subtitle.trim().isNotEmpty) ...[
                SizedBox(height: 5),
                Text(
                  subtitle,
                  style: TextStyle(
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
          key: ValueKey('caremate-edit-treatment'),
          tooltip: LifeMateRuntimeLocale.select(
            fa: LifeMateRuntimeLocale.select(fa: 'ویرایش', en: "Edit"),
            en: "Edit",
          ),
          onPressed: working ? null : onEdit,
          icon: Icon(Icons.edit_outlined),
        ),
        IconButton(
          key: ValueKey('caremate-delete-treatment'),
          tooltip: LifeMateRuntimeLocale.select(
            fa: LifeMateRuntimeLocale.select(fa: 'حذف', en: "Delete"),
            en: "remove",
          ),
          onPressed: working ? null : onDelete,
          color: Colors.redAccent,
          icon: Icon(Icons.delete_outline_rounded),
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
  Widget build(BuildContext context) => _InlineEmpty(
    text: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(
        fa: 'برای مدیریت درمان، ابتدا یک بیمار را با دعوت و رضایت معتبر متصل کنید.',
        en: "To manage treatment, first connect a patient with valid invitation and consent.",
      ),
      en: "To manage treatment, first connect a patient with valid invitation and consent.",
    ),
  );
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Color(0xFFFFF0F1),
      borderRadius: BorderRadius.circular(18),
    ),
    child: Row(
      children: [
        Icon(Icons.error_outline_rounded, color: Colors.redAccent),
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
