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

class CocoonModuleConfig {
  const CocoonModuleConfig({
    required this.host,
    this.initialTab = 0,
    this.timezone = 'UTC',
    this.pickPregnancyDate,
    this.activatePregnancy,
    this.recordsState = CocoonRecordsState.empty,
    this.records = const [],
    this.onOpenRecord,
    this.onRetryRecords,
    this.onAddRecord,
  });

  final CocoonHostContract host;
  final int initialTab;
  final String timezone;
  final Future<CocoonPregnancyDateSelection?> Function(
    CocoonDatingSource source,
  )? pickPregnancyDate;
  final Future<bool> Function(CocoonPregnancySetupDraft draft)?
      activatePregnancy;
  final CocoonRecordsState recordsState;
  final List<CocoonRecordViewData> records;
  final ValueChanged<CocoonRecordViewData>? onOpenRecord;
  final VoidCallback? onRetryRecords;
  final VoidCallback? onAddRecord;
}

class CocoonMateModule extends StatelessWidget {
  const CocoonMateModule({required this.config, super.key});

  final CocoonModuleConfig config;

  @override
  Widget build(BuildContext context) => CocoonShell(config: config);
}
