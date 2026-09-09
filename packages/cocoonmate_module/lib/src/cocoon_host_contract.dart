part of '../cocoonmate_module.dart';

enum CocoonEntryState {
  loading,
  unauthenticated,
  runtimeUnavailable,
  notEnrolled,
  notEntitled,
  noPregnancy,
  activePregnancy,
  offlineOwnerPregnancy,
  offline,
}

abstract interface class CocoonHostContract {
  CocoonEntryState get entryState;
  Locale get locale;
  String? get personId;

  /// The active owner's canonical episode projection. Gestational week/day is
  /// presentation data and must be derived from this dating source of truth.
  CocoonPregnancySnapshot? get pregnancySnapshot;

  /// Last protected owner-only pregnancy projection used only when the host is
  /// in [CocoonEntryState.offlineOwnerPregnancy]. It is never entitlement,
  /// relationship or sharing authority.
  CocoonPregnancySnapshot? get offlinePregnancySnapshot;

  Future<void> refresh();
  Future<void> openLogin();
  Future<void> openCommerce();
  Future<void> beginPregnancySetup();
  Future<void> openGlobalProfile();
  void recordSafeEvent(String name);
}

/// UI-only presentation state. The host remains the owner of canonical care
/// events, durable execution, and any server reconciliation.
enum CocoonCalendarLoadState {
  loading,
  empty,
  populated,
  partial,
  error,
  offlineCached,
}

enum CocoonCalendarItemKind { appointment, reminder, milestone }

class CocoonCalendarItem {
  const CocoonCalendarItem({
    required this.id,
    required this.title,
    required this.dateLabel,
    required this.kind,
    this.timeLabel,
    this.supporting,
    this.pendingSync = false,
  });

  final String id;
  final String title;
  final String dateLabel;
  final CocoonCalendarItemKind kind;
  final String? timeLabel;
  final String? supporting;
  final bool pendingSync;
}

class CocoonModuleConfig {
  const CocoonModuleConfig({
    required this.host,
    this.initialTab = 0,
    this.timezone = 'UTC',
    this.pickPregnancyDate,
    this.activatePregnancy,
    this.calendarState = CocoonCalendarLoadState.empty,
    this.calendarItems = const [],
    this.calendarAsOfLocalDate,
    this.onOpenCalendarItem,
    this.onOpenCalendarWeek,
    this.onRetryCalendar,
    this.recordsState = CocoonRecordsState.empty,
    this.records = const [],
    this.onOpenRecord,
    this.onRetryRecords,
    this.onAddRecord,
    this.quickAddEnabled = const {},
    this.onOpenQuickAdd,
    this.checkInSyncState = CocoonCheckInSyncState.idle,
    this.onSubmitCheckIn,
    this.symptomOptions = const [],
    this.symptomCatalogState = CocoonSymptomCatalogState.ready,
    this.symptomSubmitState = CocoonSymptomSubmitState.idle,
    this.onRetrySymptomCatalog,
    this.onSubmitSymptom,
    this.onOpenMedicalAttention,
    this.measurementOptions = const [],
    this.measurementSubmitState = CocoonMeasurementSubmitState.idle,
    this.onSubmitMeasurement,
    this.medicationOptions = const [],
    this.medicationInitialTimeLabel = '',
    this.medicationSubmitState = CocoonMedicationSubmitState.idle,
    this.onPickMedicationTime,
    this.onSubmitMedication,
    this.reminderLoadState = CocoonReminderLoadState.loading,
    this.reminderSaveState = CocoonReminderSaveState.idle,
    this.reminderData,
    this.onRetryReminders,
    this.onSaveReminders,
    this.onRequestNotificationPermission,
    this.onOpenNotificationSettings,
    this.onOpenAppointmentReminders,
    this.onOpenMedicationReminders,
    this.safetyGuidanceState = CocoonSafetyGuidanceLoadState.unavailable,
    this.safetyGuidanceCopy,
    this.safetyGuidanceData,
    this.onRetrySafetyGuidance,
    this.onSafetyGuidanceAction,
    this.settingsState = CocoonSettingsLoadState.loading,
    this.settingsData,
    this.onRetrySettings,
    this.onOpenPregnancyDating,
    this.onOpenPrivacySharing,
    this.onOpenLanguage,
    this.onOpenAccessibility,
    this.onReducedMotionChanged,
    this.onOpenDataAndSync,
    this.onOpenSubscription,
    this.onOpenSupport,
    this.onOpenPrivacyLegal,
  });

  final CocoonHostContract host;
  final int initialTab;
  final String timezone;
  final Future<CocoonPregnancyDateSelection?> Function(
    CocoonDatingSource source,
  )? pickPregnancyDate;
  final Future<bool> Function(CocoonPregnancySetupDraft draft)?
      activatePregnancy;
  final CocoonCalendarLoadState calendarState;
  final List<CocoonCalendarItem> calendarItems;
  final DateTime? calendarAsOfLocalDate;
  final ValueChanged<CocoonCalendarItem>? onOpenCalendarItem;
  final ValueChanged<int>? onOpenCalendarWeek;
  final VoidCallback? onRetryCalendar;
  final CocoonRecordsState recordsState;
  final List<CocoonRecordViewData> records;
  final ValueChanged<CocoonRecordViewData>? onOpenRecord;
  final VoidCallback? onRetryRecords;
  final VoidCallback? onAddRecord;
  final Set<CocoonQuickAddKind> quickAddEnabled;
  final ValueChanged<CocoonQuickAddKind>? onOpenQuickAdd;
  final CocoonCheckInSyncState checkInSyncState;
  final Future<void> Function(CocoonCheckInDraft draft)? onSubmitCheckIn;
  final List<CocoonSymptomOption> symptomOptions;
  final CocoonSymptomCatalogState symptomCatalogState;
  final CocoonSymptomSubmitState symptomSubmitState;
  final VoidCallback? onRetrySymptomCatalog;
  final Future<void> Function(CocoonSymptomDraft draft)? onSubmitSymptom;
  final VoidCallback? onOpenMedicalAttention;
  final List<CocoonMeasurementOption> measurementOptions;
  final CocoonMeasurementSubmitState measurementSubmitState;
  final Future<void> Function(CocoonMeasurementDraft draft)?
      onSubmitMeasurement;
  final List<CocoonMedicationOption> medicationOptions;
  final String medicationInitialTimeLabel;
  final CocoonMedicationSubmitState medicationSubmitState;
  final Future<String?> Function()? onPickMedicationTime;
  final Future<void> Function(CocoonMedicationLogDraft draft)?
      onSubmitMedication;
  final CocoonReminderLoadState reminderLoadState;
  final CocoonReminderSaveState reminderSaveState;
  final CocoonReminderSettingsViewData? reminderData;
  final VoidCallback? onRetryReminders;
  final Future<void> Function(CocoonReminderPreferences preferences)?
      onSaveReminders;
  final VoidCallback? onRequestNotificationPermission;
  final VoidCallback? onOpenNotificationSettings;
  final VoidCallback? onOpenAppointmentReminders;
  final VoidCallback? onOpenMedicationReminders;
  final CocoonSafetyGuidanceLoadState safetyGuidanceState;
  final CocoonSafetyGuidanceCopy? safetyGuidanceCopy;
  final CocoonSafetyGuidanceViewData? safetyGuidanceData;
  final VoidCallback? onRetrySafetyGuidance;
  final ValueChanged<CocoonSafetyGuidanceItem>? onSafetyGuidanceAction;
  final CocoonSettingsLoadState settingsState;
  final CocoonSettingsViewData? settingsData;
  final VoidCallback? onRetrySettings;
  final VoidCallback? onOpenPregnancyDating;
  final VoidCallback? onOpenPrivacySharing;
  final VoidCallback? onOpenLanguage;
  final VoidCallback? onOpenAccessibility;
  final ValueChanged<bool>? onReducedMotionChanged;
  final VoidCallback? onOpenDataAndSync;
  final VoidCallback? onOpenSubscription;
  final VoidCallback? onOpenSupport;
  final VoidCallback? onOpenPrivacyLegal;
}

class CocoonMateModule extends StatelessWidget {
  const CocoonMateModule({required this.config, super.key});

  final CocoonModuleConfig config;

  @override
  Widget build(BuildContext context) => CocoonShell(config: config);
}
