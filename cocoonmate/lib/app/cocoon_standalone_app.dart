import 'dart:ui';

import 'package:cocoonmate_module/cocoonmate_module.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:lifemate_client/lifemate_client.dart';
import 'package:lifemate_ui/lifemate_ui.dart';

import 'cocoon_gate3_read_models.dart';

const cocoonAppVersion = '0.1.0+1';

typedef CocoonRuntimeLoader = Future<LifeMateRuntimeConfigSnapshot> Function();
typedef CocoonBootstrapLoader = Future<CocoonBootstrapSnapshot> Function();
typedef CocoonSignOut = Future<void> Function();
typedef CocoonOfflineBootstrapCache = Future<void> Function(
    CocoonBootstrapSnapshot snapshot);
typedef CocoonOfflineSnapshotLoader = Future<CocoonPregnancySnapshot?>
    Function();
typedef CocoonOfflineOwnerForget = Future<void> Function();

class CocoonStandaloneApp extends StatelessWidget {
  const CocoonStandaloneApp({
    required this.config,
    required this.authInitialized,
    super.key,
  });

  final AppConfig config;
  final bool authInitialized;

  Locale get _locale {
    final platform = PlatformDispatcher.instance.locale;
    return platform.languageCode == 'fa'
        ? const Locale('fa')
        : const Locale('en');
  }

  @override
  Widget build(BuildContext context) {
    final locale = _locale;
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'CocoonMate',
      theme: CocoonTheme.light(),
      locale: locale,
      supportedLocales: const [Locale('fa'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: _productionHome(config, authInitialized),
    );
  }

  static Widget _productionHome(AppConfig config, bool authInitialized) {
    if (!config.isConfigured) {
      return ConfigurationRequiredScreen(
        appName: 'CocoonMate',
        missingValues: config.missingOrInvalidValues,
      );
    }
    if (!authInitialized) {
      return const ConfigurationRequiredScreen(
        appName: 'CocoonMate',
        missingValues: ['SUPABASE_INITIALIZATION_FAILED'],
      );
    }
    return LifeMateExperienceGate(
      config: config,
      appName: 'CocoonMate',
      releaseVersion: cocoonAppVersion,
      logoAssetPath: 'assets/cocoonmate-logo.png',
      unauthenticatedBuilder: (context, _, appName, logoAssetPath) =>
          LifeMateSharedAuthExperience(
        appName: appName,
        logoAssetPath: logoAssetPath,
      ),
      authenticatedBuilder: (context, _) => CocoonAuthenticatedHost(
        config: config,
        locale: Localizations.localeOf(context),
      ),
    );
  }
}

class CocoonAuthenticatedHost extends StatefulWidget {
  const CocoonAuthenticatedHost({
    required this.config,
    required this.locale,
    this.runtimeLoader,
    this.bootstrapLoader,
    this.gate3ReadLoader,
    this.gate3MutationAdapter,
    this.signOut,
    this.offlineBootstrapCache,
    this.offlineSnapshotLoader,
    this.offlineOwnerForget,
    super.key,
  });

  final AppConfig config;
  final Locale locale;
  final CocoonRuntimeLoader? runtimeLoader;
  final CocoonBootstrapLoader? bootstrapLoader;
  final CocoonGate3ReadLoader? gate3ReadLoader;
  final CocoonGate3MutationAdapter? gate3MutationAdapter;
  final CocoonSignOut? signOut;
  final CocoonOfflineBootstrapCache? offlineBootstrapCache;
  final CocoonOfflineSnapshotLoader? offlineSnapshotLoader;
  final CocoonOfflineOwnerForget? offlineOwnerForget;

  @override
  State<CocoonAuthenticatedHost> createState() =>
      _CocoonAuthenticatedHostState();
}

class _CocoonAuthenticatedHostState extends State<CocoonAuthenticatedHost>
    implements CocoonHostContract {
  CocoonEntryState _entryState = CocoonEntryState.loading;
  String? _personId;
  CocoonPregnancySnapshot? _offlinePregnancySnapshot;
  CocoonPregnancySnapshot? _pregnancySnapshot;
  bool _refreshing = false;
  bool _refreshingGate3 = false;
  CocoonPregnancyOfflineOwnerCoordinator? _offlineOwnerCoordinator;
  String? _offlineOwnerLegacyAccountId;
  CocoonGate3MutationAdapter? _gate3MutationAdapter;
  String? _gate3MutationOwnerLegacyAccountId;
  bool _ownsGate3MutationAdapter = false;

  CocoonCalendarLoadState _calendarState = CocoonCalendarLoadState.loading;
  List<CocoonCalendarItem> _calendarItems = const [];
  DateTime? _calendarAsOfLocalDate;
  CocoonRecordsState _recordsState = CocoonRecordsState.loading;
  List<CocoonRecordViewData> _records = const [];
  CocoonCheckInSyncState _checkInSyncState = CocoonCheckInSyncState.idle;
  CocoonApprovedSymptomCatalog? _symptomCatalog;
  CocoonSymptomCatalogState _symptomCatalogState =
      CocoonSymptomCatalogState.loading;
  CocoonSymptomSubmitState _symptomSubmitState = CocoonSymptomSubmitState.idle;
  CocoonMoodSubmitState _moodSubmitState = CocoonMoodSubmitState.idle;
  CocoonMeasurementSubmitState _measurementSubmitState =
      CocoonMeasurementSubmitState.idle;
  CocoonMeasurementHistoryState _measurementHistoryState =
      CocoonMeasurementHistoryState.loading;
  List<CocoonMeasurementHistoryItem> _measurementHistory = const [];
  List<CocoonMedicationOption> _medicationOptions = const [];
  CocoonMedicationSubmitState _medicationSubmitState =
      CocoonMedicationSubmitState.idle;

  late final LifeMateRemoteConfigClient? _runtimeClient =
      widget.runtimeLoader == null
          ? LifeMateRemoteConfigClient.fromEnvironment(
              product: 'cocoonmate',
              currentVersion: cocoonAppVersion,
            )
          : null;
  late final CocoonPregnancyApiClient? _pregnancyClient =
      widget.bootstrapLoader == null
          ? CocoonPregnancyApiClient(
              baseUri: widget.config.apiBaseUri,
              accessToken: () => LifeMateAuth.currentAccessToken,
            )
          : null;
  late final CocoonGate3ReadModelLoader? _gate3ReadModelLoader =
      widget.gate3ReadLoader == null && widget.bootstrapLoader == null
          ? CocoonGate3ReadModelLoader(
              baseUri: widget.config.apiBaseUri,
              accessToken: () => LifeMateAuth.currentAccessToken,
            )
          : null;
  late final CocoonPregnancyCalendarApiClient? _calendarMutationClient =
      widget.bootstrapLoader == null
          ? CocoonPregnancyCalendarApiClient(
              baseUri: widget.config.apiBaseUri,
              accessToken: () => LifeMateAuth.currentAccessToken,
            )
          : null;
  late final LifeMateEditApi? _calendarEditClient =
      widget.bootstrapLoader == null
          ? LifeMateEditApi(
              baseUri: widget.config.apiBaseUri,
              accessToken: () => LifeMateAuth.currentAccessToken,
            )
          : null;
  late final CocoonPregnancyTreatmentsApiClient? _treatmentsClient =
      widget.bootstrapLoader == null
          ? CocoonPregnancyTreatmentsApiClient(
              baseUri: widget.config.apiBaseUri,
              accessToken: () => LifeMateAuth.currentAccessToken,
            )
          : null;
  late final CocoonPregnancyMeasurementsApiClient? _measurementsHistoryClient =
      widget.bootstrapLoader == null
          ? CocoonPregnancyMeasurementsApiClient(
              baseUri: widget.config.apiBaseUri,
              accessToken: () => LifeMateAuth.currentAccessToken,
            )
          : null;
  late final CocoonPregnancyDailyApiClient? _dailyClient =
      widget.bootstrapLoader == null
          ? CocoonPregnancyDailyApiClient(
              baseUri: widget.config.apiBaseUri,
              accessToken: () => LifeMateAuth.currentAccessToken,
            )
          : null;
  late final LifeMateApiClient? _treatmentMutationClient =
      widget.bootstrapLoader == null
          ? LifeMateApiClient(
              baseUri: widget.config.apiBaseUri,
              accessToken: () => LifeMateAuth.currentAccessToken,
            )
          : null;

  @override
  void initState() {
    super.initState();
    _gate3MutationAdapter = widget.gate3MutationAdapter;
    WidgetsBinding.instance.addPostFrameCallback((_) => refresh());
  }

  @override
  void dispose() {
    _runtimeClient?.close();
    _pregnancyClient?.close();
    _gate3ReadModelLoader?.close();
    _calendarMutationClient?.close();
    _treatmentsClient?.close();
    _measurementsHistoryClient?.close();
    _dailyClient?.close();
    _treatmentMutationClient?.close();
    if (_ownsGate3MutationAdapter) _gate3MutationAdapter?.close();
    super.dispose();
  }

  @override
  CocoonEntryState get entryState => _entryState;

  @override
  Locale get locale => widget.locale;

  @override
  String? get personId => _personId;

  @override
  CocoonPregnancySnapshot? get offlinePregnancySnapshot =>
      _offlinePregnancySnapshot;

  @override
  CocoonPregnancySnapshot? get pregnancySnapshot => _pregnancySnapshot;

  @override
  Widget build(BuildContext context) => CocoonMateModule(
        config: CocoonModuleConfig(
          host: this,
          calendarState: _calendarState,
          calendarItems: _calendarItems,
          calendarAsOfLocalDate: _calendarAsOfLocalDate,
          timezone: _calendarTimeZone,
          onAddCalendarAppointment:
              _calendarMutationClient == null ? null : _openNewAppointment,
          onOpenCalendarItem:
              _calendarEditClient == null ? null : _openCalendarItem,
          onRetryCalendar: () => _refreshGate3ReadModels(),
          recordsState: _recordsState,
          records: _records,
          onOpenRecord: _openRecord,
          onRetryRecords: () => _refreshGate3ReadModels(),
          checkInSyncState: _checkInSyncState,
          onSubmitCheckIn:
              _gate3MutationAdapter == null ? null : _submitCheckIn,
          symptomOptions: _symptomOptions,
          symptomCatalogState: _symptomCatalogState,
          symptomSubmitState: _symptomSubmitState,
          onRetrySymptomCatalog: _refreshSymptomCatalog,
          onSubmitSymptom: _gate3MutationAdapter?.supportsSymptom == true &&
                  (_symptomCatalogState == CocoonSymptomCatalogState.ready ||
                      _symptomCatalogState ==
                          CocoonSymptomCatalogState.offlineReady)
              ? _submitSymptom
              : null,
          moodSubmitState: _moodSubmitState,
          onSubmitMood:
              _gate3MutationAdapter?.supportsMood == true ? _submitMood : null,
          measurementOptions: _measurementOptions,
          measurementSubmitState: _measurementSubmitState,
          onSubmitMeasurement:
              _gate3MutationAdapter == null ? null : _submitMeasurement,
          onOpenMeasurementHistory: _measurementsHistoryClient == null
              ? null
              : _openMeasurementHistory,
          medicationOptions: _medicationOptions,
          medicationSubmitState: _medicationSubmitState,
          onPickMedicationTime:
              _treatmentMutationClient == null ? null : _pickMedicationTime,
          onSubmitMedication:
              _treatmentMutationClient == null ? null : _submitMedication,
          onOpenTreatments: _treatmentsClient == null ? null : _openTreatments,
        ),
      );

  @override
  Future<void> refresh() async {
    if (_refreshing) return;
    _refreshing = true;
    if (mounted) setState(() => _entryState = CocoonEntryState.loading);
    try {
      final runtime = await (widget.runtimeLoader?.call() ??
          _runtimeClient!.load(forceRefresh: true));
      if (runtime.product != 'cocoonmate' ||
          runtime.platform.trim().isEmpty ||
          !runtime.isTrustedForUpdatePolicy(DateTime.now())) {
        _apply(CocoonEntryState.runtimeUnavailable, null);
        return;
      }

      final snapshot = await (widget.bootstrapLoader?.call() ??
          _pregnancyClient!.bootstrap(asOfDate: DateTime.now()));
      if (!await _cacheAuthoritativeBootstrap(snapshot)) return;
      final next = resolveCocoonEntryState(snapshot);
      _apply(
        next,
        snapshot.personId.isEmpty ? null : snapshot.personId,
        pregnancySnapshot: snapshot.activeEpisode == null
            ? null
            : CocoonPregnancySnapshot(
                contractVersion: snapshot.contractVersion,
                episode: snapshot.activeEpisode,
              ),
      );
      if (next == CocoonEntryState.activePregnancy) {
        await _refreshGate3ReadModels();
      } else {
        _clearGate3ReadModels();
      }
    } on LifeMateApiException catch (error) {
      if (error.isUnauthorized) {
        await _forgetOfflineOwner();
        await (widget.signOut?.call() ?? LifeMateAuth.signOut());
        _apply(CocoonEntryState.unauthenticated, null);
      } else if (error.statusCode == 0) {
        _markGate3ReadModelsStale();
        await _applyOfflineOwnerFallback();
      } else {
        _apply(CocoonEntryState.runtimeUnavailable, null);
      }
    } on FormatException {
      _apply(CocoonEntryState.runtimeUnavailable, null);
    } catch (_) {
      _apply(CocoonEntryState.runtimeUnavailable, null);
    } finally {
      _refreshing = false;
    }
  }

  Future<void> _refreshGate3ReadModels() async {
    if (_refreshingGate3 || _entryState != CocoonEntryState.activePregnancy) {
      return;
    }
    final injected = widget.gate3ReadLoader;
    final production = _gate3ReadModelLoader;
    if (injected == null && production == null) return;

    _refreshingGate3 = true;
    if (mounted && _calendarItems.isEmpty && _records.isEmpty) {
      setState(() {
        _calendarState = CocoonCalendarLoadState.loading;
        _recordsState = CocoonRecordsState.loading;
      });
    }
    try {
      final values = injected != null
          ? await injected(
              now: DateTime.now(),
              fa: widget.locale.languageCode == 'fa',
            )
          : await production!.load(
              now: DateTime.now(),
              fa: widget.locale.languageCode == 'fa',
            );
      if (!mounted || _entryState != CocoonEntryState.activePregnancy) return;
      setState(() {
        _calendarState = values.calendarState;
        _calendarItems = values.calendarItems;
        _calendarAsOfLocalDate = values.calendarAsOfLocalDate;
        _recordsState = values.recordsState;
        _records = values.records;
      });
      await _refreshMedicationOptions();
      await _refreshSymptomCatalog();
    } catch (_) {
      _markGate3ReadModelsStale();
    } finally {
      _refreshingGate3 = false;
    }
  }

  // CocoonMate's closed-beta locale is Iran. This is an explicit IANA zone in
  // the canonical care-event contract, never a device-specific abbreviation.
  // A future profile-settings slice will provide the owner's saved time zone.
  static const _calendarTimeZone = 'Asia/Tehran';

  Future<void> _openNewAppointment() async {
    if (!mounted || _calendarMutationClient == null) return;
    final now = DateTime.now();
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => Directionality(
          textDirection: widget.locale.languageCode == 'fa'
              ? TextDirection.rtl
              : TextDirection.ltr,
          child: CocoonAppointmentFormScreen(
            fa: widget.locale.languageCode == 'fa',
            submitState: CocoonAppointmentSubmitState.idle,
            initialDate: _appointmentDateSelection(now),
            initialTime: _appointmentTimeSelection(TimeOfDay.fromDateTime(now)),
            onPickDate: _pickAppointmentDate,
            onPickTime: _pickAppointmentTime,
            onSubmit: _submitAppointment,
          ),
        ),
      ),
    );
  }

  Future<CocoonAppointmentDateSelection?> _pickAppointmentDate() async {
    final now = DateTime.now();
    final selected = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
    );
    return selected == null ? null : _appointmentDateSelection(selected);
  }

  Future<CocoonAppointmentTimeSelection?> _pickAppointmentTime() async {
    final selected = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(DateTime.now()),
    );
    return selected == null ? null : _appointmentTimeSelection(selected);
  }

  CocoonAppointmentDateSelection _appointmentDateSelection(DateTime value) {
    final localizations = MaterialLocalizations.of(context);
    final date = DateUtils.dateOnly(value);
    return CocoonAppointmentDateSelection(
      localDate: date,
      displayLabel: localizations.formatMediumDate(date),
      semanticLabel: localizations.formatFullDate(date),
    );
  }

  CocoonAppointmentTimeSelection _appointmentTimeSelection(TimeOfDay time) {
    final localizations = MaterialLocalizations.of(context);
    return CocoonAppointmentTimeSelection(
      localTime: time,
      displayLabel: localizations.formatTimeOfDay(time),
      semanticLabel: localizations.formatTimeOfDay(
        time,
        alwaysUse24HourFormat: true,
      ),
    );
  }

  Future<void> _submitAppointment(CocoonAppointmentDraft draft) async {
    final client = _calendarMutationClient;
    if (client == null) {
      throw StateError('Canonical calendar client is unavailable.');
    }
    await client.createEvent(
      classification: switch (draft.kind) {
        CocoonAppointmentKind.checkup =>
          CocoonPregnancyCalendarClassification.checkup,
        CocoonAppointmentKind.ultrasound =>
          CocoonPregnancyCalendarClassification.ultrasound,
        CocoonAppointmentKind.lab =>
          CocoonPregnancyCalendarClassification.labTest,
        CocoonAppointmentKind.other =>
          CocoonPregnancyCalendarClassification.other,
      },
      careEvent: <String, dynamic>{
        'clientRequestId': LifeMateApiClient.createClientRequestId(),
        'eventType': 'appointment',
        'title': draft.title,
        'scheduledLocalDate': _careEventDate(draft.localDate),
        'scheduledLocalTime': _careEventTime(draft.localTime),
        'timeZone': _calendarTimeZone,
        'providerName': draft.provider,
        'centerName': draft.location,
        'patientReminderMinutesBefore': draft.reminderMinutes,
      }..removeWhere((_, value) => value == null),
    );
    await _refreshGate3ReadModels();
  }

  Future<void> _openCalendarItem(CocoonCalendarItem item) async {
    if (item.kind != CocoonCalendarItemKind.appointment ||
        _calendarEditClient == null ||
        !mounted) {
      return;
    }
    try {
      final event = await _calendarEditClient!.getCareEvent(eventId: item.id);
      if (!mounted) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => Directionality(
            textDirection: widget.locale.languageCode == 'fa'
                ? TextDirection.rtl
                : TextDirection.ltr,
            child: CocoonAppointmentDetailScreen(
              fa: widget.locale.languageCode == 'fa',
              canMutate: true,
              data: _appointmentDetailData(item, event),
              onEdit: () => _openEditAppointment(item, event),
              onCancel: () => _cancelAppointment(item.id),
            ),
          ),
        ),
      );
    } on LifeMateApiException {
      if (mounted) _refreshGate3ReadModels();
    }
  }

  CocoonAppointmentDetailViewData _appointmentDetailData(
    CocoonCalendarItem item,
    Map<String, dynamic> event,
  ) =>
      CocoonAppointmentDetailViewData(
        appointment: CocoonAppointmentViewData(
          id: item.id,
          title: event['title']?.toString().trim().isNotEmpty == true
              ? event['title'].toString()
              : item.title,
          dateLabel: item.dateLabel,
          timeLabel: item.timeLabel ?? '',
          status: switch (event['status']?.toString().toLowerCase()) {
            'completed' => CocoonAppointmentStatus.completed,
            'cancelled' => CocoonAppointmentStatus.cancelled,
            _ => CocoonAppointmentStatus.scheduled,
          },
          provider: _optionalText(event['providerName']),
          location: _optionalText(event['centerName']),
        ),
        reminderLabel: _reminderLabel(
          int.tryParse(
                  event['patientReminderMinutesBefore']?.toString() ?? '') ??
              30,
        ),
        address: _optionalText(event['addressLine']),
        phone: _optionalText(event['phoneNumber']),
        note: _optionalText(event['instructions']),
      );

  Future<void> _cancelAppointment(String eventId) async {
    final client = _calendarEditClient;
    if (client == null)
      throw StateError('Canonical calendar editor is unavailable.');
    await client.updateCareEventStatus(eventId: eventId, status: 'cancelled');
    await _refreshGate3ReadModels();
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _openEditAppointment(
    CocoonCalendarItem item,
    Map<String, dynamic> event,
  ) async {
    if (!mounted) return;
    final initial = _appointmentDraftFromEvent(item, event);
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => Directionality(
          textDirection: widget.locale.languageCode == 'fa'
              ? TextDirection.rtl
              : TextDirection.ltr,
          child: CocoonAppointmentFormScreen(
            fa: widget.locale.languageCode == 'fa',
            submitState: CocoonAppointmentSubmitState.idle,
            initialDate: _appointmentDateSelection(initial.localDate),
            initialTime: _appointmentTimeSelection(initial.localTime),
            initialDraft: initial,
            onPickDate: _pickAppointmentDate,
            onPickTime: _pickAppointmentTime,
            onSubmit: (draft) => _updateAppointment(item, event, draft),
          ),
        ),
      ),
    );
  }

  CocoonAppointmentDraft _appointmentDraftFromEvent(
    CocoonCalendarItem item,
    Map<String, dynamic> event,
  ) {
    final date =
        DateTime.tryParse(event['scheduledLocalDate']?.toString() ?? '') ??
            DateTime.now();
    final timeParts =
        (event['scheduledLocalTime']?.toString() ?? '00:00').split(':');
    final hour = int.tryParse(timeParts.first) ?? 0;
    final minute = timeParts.length > 1 ? int.tryParse(timeParts[1]) ?? 0 : 0;
    return CocoonAppointmentDraft(
      title: _optionalText(event['title']) ?? item.title,
      kind: switch (item.appointmentKind) {
        CocoonCalendarAppointmentKind.ultrasound =>
          CocoonAppointmentKind.ultrasound,
        CocoonCalendarAppointmentKind.lab => CocoonAppointmentKind.lab,
        _ => CocoonAppointmentKind.checkup,
      },
      dateLabel: item.dateLabel,
      timeLabel: item.timeLabel ?? '',
      localDate: DateUtils.dateOnly(date),
      localTime: TimeOfDay(hour: hour, minute: minute),
      reminderMinutes: int.tryParse(
              event['patientReminderMinutesBefore']?.toString() ?? '') ??
          30,
      provider: _optionalText(event['providerName']),
      location: _optionalText(event['centerName']),
    );
  }

  Future<void> _updateAppointment(
    CocoonCalendarItem item,
    Map<String, dynamic> current,
    CocoonAppointmentDraft draft,
  ) async {
    final client = _calendarEditClient;
    if (client == null)
      throw StateError('Canonical calendar editor is unavailable.');
    final version = int.tryParse(current['version']?.toString() ?? '');
    if (version == null)
      throw const FormatException('Canonical appointment version is missing.');
    await client.updateCareEvent(
      eventId: item.id,
      version: version,
      eventType: 'appointment',
      title: draft.title,
      providerName: draft.provider,
      specialty: _optionalText(current['specialty']),
      scheduledLocalDate: draft.localDate,
      scheduledLocalTime: _careEventTime(draft.localTime),
      timeZone: _optionalText(current['timeZone']) ?? _calendarTimeZone,
      patientReminderMinutesBefore: draft.reminderMinutes,
      caregiverReminderMinutesBefore: int.tryParse(
              current['caregiverReminderMinutesBefore']?.toString() ?? '') ??
          60,
      centerName: draft.location,
      addressLine: _optionalText(current['addressLine']),
      phoneNumber: _optionalText(current['phoneNumber']),
      reason: _optionalText(current['reason']),
      instructions: _optionalText(current['instructions']),
      status: current['status']?.toString().toLowerCase() == 'completed'
          ? 'completed'
          : 'scheduled',
    );
    await _refreshGate3ReadModels();
  }

  String _reminderLabel(int minutes) => switch (minutes) {
        0 =>
          widget.locale.languageCode == 'fa' ? 'بدون یادآوری' : 'No reminder',
        30 => widget.locale.languageCode == 'fa'
            ? '۳۰ دقیقه قبل'
            : '30 minutes before',
        60 =>
          widget.locale.languageCode == 'fa' ? '۱ ساعت قبل' : '1 hour before',
        _ => widget.locale.languageCode == 'fa'
            ? '$minutes دقیقه قبل'
            : '$minutes minutes before',
      };

  String? _optionalText(Object? value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? null : text;
  }

  String _careEventDate(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

  String _careEventTime(TimeOfDay value) =>
      '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';

  List<CocoonSymptomOption> get _symptomOptions =>
      _symptomCatalog?.entries
          .map(
            (entry) => CocoonSymptomOption(
              id: entry.code,
              label: entry.label,
              icon: Icons.healing_outlined,
            ),
          )
          .toList(growable: false) ??
      const [];

  Future<void> _refreshSymptomCatalog() async {
    final client = _dailyClient;
    if (client == null || _entryState != CocoonEntryState.activePregnancy) {
      return;
    }
    if (mounted) {
      setState(() => _symptomCatalogState = CocoonSymptomCatalogState.loading);
    }
    try {
      final locale = widget.locale.languageCode == 'fa' ? 'fa' : 'en';
      final catalog = await client.symptomCatalog(
        locale: locale,
      );
      if (!mounted || _entryState != CocoonEntryState.activePregnancy) return;
      setState(() {
        _symptomCatalog = catalog;
        _symptomCatalogState = catalog.entries.isEmpty
            ? CocoonSymptomCatalogState.empty
            : CocoonSymptomCatalogState.ready;
      });
      try {
        await _productionOfflineOwnerCoordinator()
            ?.cacheApprovedSymptomCatalog(locale: locale, catalog: catalog);
      } catch (_) {
        // The catalog is usable online even when protected cache persistence
        // is unavailable; do not fall back to an unprotected store.
      }
    } on LifeMateApiException catch (error) {
      if (!mounted) return;
      if (error.statusCode == 0) {
        await _restoreCachedSymptomCatalog();
      } else {
        setState(() => _symptomCatalogState = CocoonSymptomCatalogState.error);
      }
    } catch (_) {
      if (mounted)
        setState(() => _symptomCatalogState = CocoonSymptomCatalogState.error);
    }
  }

  Future<void> _restoreCachedSymptomCatalog() async {
    final locale = widget.locale.languageCode == 'fa' ? 'fa' : 'en';
    try {
      final catalog = await _productionOfflineOwnerCoordinator()
          ?.readCachedApprovedSymptomCatalog(locale: locale);
      if (!mounted || _entryState != CocoonEntryState.activePregnancy) return;
      setState(() {
        _symptomCatalog = catalog;
        _symptomCatalogState = catalog == null
            ? CocoonSymptomCatalogState.offline
            : catalog.entries.isEmpty
                ? CocoonSymptomCatalogState.empty
                : CocoonSymptomCatalogState.offlineReady;
      });
    } catch (_) {
      if (mounted) {
        setState(
            () => _symptomCatalogState = CocoonSymptomCatalogState.offline);
      }
    }
  }

  void _openRecord(CocoonRecordViewData record) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CocoonRecordDetailScreen(
          fa: widget.locale.languageCode == 'fa',
          record: record,
        ),
      ),
    );
  }

  Future<void> _refreshMedicationOptions() async {
    final client = _treatmentsClient;
    if (client == null || _entryState != CocoonEntryState.activePregnancy) {
      return;
    }
    final today = DateTime.now();
    try {
      final treatmentContext = await client.list(
        fromDate: DateTime(today.year, today.month, today.day),
        toDate: DateTime(today.year, today.month, today.day + 1),
      );
      final plans = {
        for (final plan in treatmentContext.typedTreatmentPlans) plan.id: plan,
      };
      final options = treatmentContext.typedDoseOccurrences
          .where((occurrence) => occurrence.status == 'scheduled')
          .map((occurrence) {
            final plan = plans[occurrence.treatmentPlanId];
            if (plan == null) return null;
            return CocoonMedicationOption(
              occurrenceId: occurrence.id,
              occurrenceVersion: occurrence.version,
              name: plan.medicationName,
              doseLabel: plan.doseText,
            );
          })
          .whereType<CocoonMedicationOption>()
          .toList(growable: false);
      if (mounted) setState(() => _medicationOptions = options);
    } catch (_) {
      if (mounted) setState(() => _medicationOptions = const []);
    }
  }

  Future<void> _openTreatments() async {
    final client = _treatmentsClient;
    if (client == null || !mounted) return;
    final now = DateTime.now();
    try {
      final treatmentContext = await client.list(
        fromDate: DateTime(now.year, now.month, now.day),
        toDate: DateTime(now.year, now.month, now.day + 1),
      );
      final next = {
        for (final occurrence in treatmentContext.typedDoseOccurrences)
          occurrence.treatmentPlanId: occurrence,
      };
      final items = treatmentContext.typedTreatmentPlans.map((plan) {
        final occurrence = next[plan.id];
        return CocoonActiveTreatmentViewData(
          id: plan.id,
          title: plan.medicationName,
          details: [plan.doseText, plan.strengthText]
              .whereType<String>()
              .where((value) => value.isNotEmpty)
              .join(' · '),
          nextDoseLabel: occurrence == null
              ? null
              : '${occurrence.scheduledLocalDate} · ${occurrence.scheduledLocalTime}',
          statusLabel: plan.status,
        );
      }).toList(growable: false);
      if (!mounted) return;
      Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => CocoonTreatmentsScreen(
          fa: widget.locale.languageCode == 'fa',
          state: items.isEmpty
              ? CocoonTreatmentsLoadState.empty
              : CocoonTreatmentsLoadState.ready,
          items: items,
          onRetry: _openTreatments,
          onOpenTreatment: (_) {},
        ),
      ));
    } on Object {
      if (!mounted) return;
      Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => CocoonTreatmentsScreen(
          fa: widget.locale.languageCode == 'fa',
          state: CocoonTreatmentsLoadState.error,
          items: const [],
          onRetry: _openTreatments,
          onOpenTreatment: (_) {},
        ),
      ));
    }
  }

  Future<void> _openMeasurementHistory() async {
    if (!mounted) return;
    await _refreshMeasurementHistory();
    if (!mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => Directionality(
          textDirection: widget.locale.languageCode == 'fa'
              ? TextDirection.rtl
              : TextDirection.ltr,
          child: CocoonMeasurementHistoryScreen(
            fa: widget.locale.languageCode == 'fa',
            state: _measurementHistoryState,
            items: _measurementHistory,
            onRetry: _openMeasurementHistory,
          ),
        ),
      ),
    );
  }

  Future<void> _refreshMeasurementHistory() async {
    final client = _measurementsHistoryClient;
    if (client == null || _entryState != CocoonEntryState.activePregnancy) {
      return;
    }
    if (mounted) {
      setState(() =>
          _measurementHistoryState = CocoonMeasurementHistoryState.loading);
    }
    final now = DateTime.now();
    try {
      final response = await client.list(
        fromDate: DateTime(now.year, now.month, now.day - 90),
        toDate: DateTime(now.year, now.month, now.day),
      );
      final items = response.items.map((observation) {
        final primary = observation.valuePrimary;
        final secondary = observation.valueSecondary;
        final value = primary == null
            ? ''
            : secondary == null
                ? '${_numberLabel(primary)} ${observation.unitPrimary ?? ''}'
                    .trim()
                : '${_numberLabel(primary)}/${_numberLabel(secondary)} ${observation.unitPrimary ?? observation.unitSecondary ?? ''}'
                    .trim();
        return CocoonMeasurementHistoryItem(
          id: observation.id,
          metricLabel: _measurementHistoryTitle(observation.observationType),
          recordedAtLabel: _careEventDate(observation.observedLocalDate),
          valueLabel: value,
          syncState: CocoonMeasurementHistorySyncState.confirmed,
        );
      }).toList(growable: false);
      if (mounted) {
        setState(() {
          _measurementHistory = items;
          _measurementHistoryState = items.isEmpty
              ? CocoonMeasurementHistoryState.empty
              : CocoonMeasurementHistoryState.ready;
        });
      }
    } on LifeMateApiException {
      if (mounted) {
        setState(() =>
            _measurementHistoryState = CocoonMeasurementHistoryState.error);
      }
    } catch (_) {
      if (mounted) {
        setState(() =>
            _measurementHistoryState = CocoonMeasurementHistoryState.error);
      }
    }
  }

  String _measurementHistoryTitle(String type) {
    final fa = widget.locale.languageCode == 'fa';
    return switch (type) {
      'weight' => fa ? 'وزن' : 'Weight',
      'blood_pressure' => fa ? 'فشار خون' : 'Blood pressure',
      'blood_glucose' => fa ? 'قند خون' : 'Blood glucose',
      _ => fa ? 'اندازه‌گیری' : 'Measurement',
    };
  }

  String _numberLabel(double value) => value == value.roundToDouble()
      ? value.toInt().toString()
      : value.toString();

  Future<DateTime?> _pickMedicationTime() async {
    final now = DateTime.now();
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(now),
    );
    if (picked == null) return null;
    return DateTime(
      now.year,
      now.month,
      now.day,
      picked.hour,
      picked.minute,
    ).toUtc();
  }

  Future<void> _submitMedication(CocoonMedicationLogDraft draft) async {
    final client = _treatmentMutationClient;
    if (client == null) {
      throw StateError('Shared treatment mutation client is unavailable.');
    }
    if (mounted) {
      setState(
        () => _medicationSubmitState = CocoonMedicationSubmitState.submitting,
      );
    }
    try {
      await client.reportDose(
        occurrenceId: draft.occurrenceId,
        clientRequestId: LifeMateApiClient.createClientRequestId(),
        version: draft.occurrenceVersion,
        status: switch (draft.action) {
          CocoonMedicationLogAction.taken => 'taken',
          CocoonMedicationLogAction.skipped => 'skipped',
        },
        occurredAtUtc: draft.occurredAtUtc,
      );
      await _refreshGate3ReadModels();
      if (mounted) {
        setState(
          () => _medicationSubmitState = CocoonMedicationSubmitState.confirmed,
        );
      }
    } on LifeMateApiException catch (error) {
      if (mounted) {
        setState(() {
          _medicationSubmitState = error.statusCode == 0
              ? CocoonMedicationSubmitState.offline
              : CocoonMedicationSubmitState.error;
        });
      }
      rethrow;
    } catch (_) {
      if (mounted) {
        setState(
          () => _medicationSubmitState = CocoonMedicationSubmitState.error,
        );
      }
      rethrow;
    }
  }

  Future<CocoonCheckInSubmitResult> _submitCheckIn(
    CocoonCheckInDraft draft,
  ) async {
    final adapter = _gate3MutationAdapter;
    if (adapter == null) {
      throw StateError('Gate-3 mutation adapter is unavailable.');
    }
    if (mounted) {
      setState(() => _checkInSyncState = CocoonCheckInSyncState.submitting);
    }
    try {
      final result = await adapter.submitCheckIn(
        feeling: switch (draft.feeling) {
          CocoonCheckInFeeling.comfortable =>
            CocoonPregnancyFeeling.comfortable,
          CocoonCheckInFeeling.mixed => CocoonPregnancyFeeling.mixed,
          CocoonCheckInFeeling.difficult => CocoonPregnancyFeeling.difficult,
        },
        energy: switch (draft.energy) {
          CocoonCheckInEnergy.low => CocoonPregnancyEnergy.low,
          CocoonCheckInEnergy.steady => CocoonPregnancyEnergy.steady,
          CocoonCheckInEnergy.high => CocoonPregnancyEnergy.high,
        },
      );
      if (result.disposition == CocoonGate3MutationDisposition.queued) {
        if (mounted) {
          setState(() => _checkInSyncState = CocoonCheckInSyncState.queued);
        }
        return CocoonCheckInSubmitResult.queued;
      }
      await _refreshGate3ReadModels();
      if (mounted) {
        setState(() => _checkInSyncState = CocoonCheckInSyncState.confirmed);
      }
      return CocoonCheckInSubmitResult.confirmed;
    } on LifeMateApiException catch (error) {
      if (mounted) {
        setState(() {
          _checkInSyncState = error.statusCode == 0
              ? CocoonCheckInSyncState.offline
              : CocoonCheckInSyncState.error;
        });
      }
      rethrow;
    } catch (_) {
      if (mounted) {
        setState(() => _checkInSyncState = CocoonCheckInSyncState.error);
      }
      rethrow;
    }
  }

  Future<void> _submitSymptom(CocoonSymptomDraft draft) async {
    final adapter = _gate3MutationAdapter;
    final catalog = _symptomCatalog;
    if (adapter == null || catalog == null) {
      throw StateError('Approved symptom catalog is unavailable.');
    }
    if (mounted) {
      setState(() => _symptomSubmitState = CocoonSymptomSubmitState.submitting);
    }
    try {
      final result = await adapter.submitSymptom(
        approvedCatalog: catalog,
        symptomCode: draft.symptomId,
        intensity: switch (draft.intensity) {
          CocoonSymptomIntensity.mild => CocoonPregnancySymptomIntensity.mild,
          CocoonSymptomIntensity.moderate =>
            CocoonPregnancySymptomIntensity.moderate,
          CocoonSymptomIntensity.strong =>
            CocoonPregnancySymptomIntensity.strong,
        },
        note: draft.note,
      );
      if (result.disposition == CocoonGate3MutationDisposition.queued) {
        if (mounted) {
          setState(() => _symptomSubmitState = CocoonSymptomSubmitState.queued);
        }
        return;
      }
      await _refreshGate3ReadModels();
      await _refreshMeasurementHistory();
      if (mounted) {
        setState(
            () => _symptomSubmitState = CocoonSymptomSubmitState.confirmed);
      }
    } on LifeMateApiException catch (error) {
      if (mounted) {
        setState(() {
          _symptomSubmitState = error.statusCode == 0
              ? CocoonSymptomSubmitState.offline
              : CocoonSymptomSubmitState.error;
        });
      }
      rethrow;
    } catch (_) {
      if (mounted) {
        setState(() => _symptomSubmitState = CocoonSymptomSubmitState.error);
      }
      rethrow;
    }
  }

  Future<void> _submitMood(CocoonMoodDraft draft) async {
    final adapter = _gate3MutationAdapter;
    if (adapter == null)
      throw StateError('Mood mutation adapter is unavailable.');
    if (mounted) {
      setState(() => _moodSubmitState = CocoonMoodSubmitState.submitting);
    }
    try {
      final result = await adapter.submitMood(
        mood: switch (draft.mood) {
          CocoonMood.veryLow => CocoonPregnancyMood.veryLow,
          CocoonMood.low => CocoonPregnancyMood.low,
          CocoonMood.neutral => CocoonPregnancyMood.neutral,
          CocoonMood.good => CocoonPregnancyMood.good,
          CocoonMood.veryGood => CocoonPregnancyMood.veryGood,
        },
      );
      if (result.disposition == CocoonGate3MutationDisposition.queued) {
        if (mounted)
          setState(() => _moodSubmitState = CocoonMoodSubmitState.queued);
        return;
      }
      await _refreshGate3ReadModels();
      if (mounted)
        setState(() => _moodSubmitState = CocoonMoodSubmitState.confirmed);
    } on LifeMateApiException catch (error) {
      if (mounted) {
        setState(() {
          _moodSubmitState = error.statusCode == 0
              ? CocoonMoodSubmitState.offline
              : CocoonMoodSubmitState.error;
        });
      }
      rethrow;
    } catch (_) {
      if (mounted)
        setState(() => _moodSubmitState = CocoonMoodSubmitState.error);
      rethrow;
    }
  }

  List<CocoonMeasurementOption> get _measurementOptions {
    final fa = widget.locale.languageCode == 'fa';
    String label(String en, String faValue) => fa ? faValue : en;
    CocoonMeasurementFieldSpec field(
      String id,
      String en,
      String faValue,
      String unit,
    ) =>
        CocoonMeasurementFieldSpec(
          id: id,
          label: label(en, faValue),
          unit: unit,
        );
    return [
      CocoonMeasurementOption(
        id: CocoonPregnancyMeasurementType.weight.wireValue,
        label: label('Weight', 'وزن'),
        icon: Icons.monitor_weight_outlined,
        fields: [field('primary', 'Weight', 'وزن', 'kg')],
      ),
      CocoonMeasurementOption(
        id: CocoonPregnancyMeasurementType.bloodPressure.wireValue,
        label: label('Blood pressure', 'فشار خون'),
        icon: Icons.favorite_outline_rounded,
        fields: [
          field('primary', 'Systolic', 'سیستولیک', 'mmHg'),
          field('secondary', 'Diastolic', 'دیاستولیک', 'mmHg'),
        ],
      ),
      CocoonMeasurementOption(
        id: CocoonPregnancyMeasurementType.bloodGlucose.wireValue,
        label: label('Blood glucose', 'قند خون'),
        icon: Icons.water_drop_outlined,
        fields: [field('primary', 'Glucose', 'قند خون', 'mg/dL')],
      ),
    ];
  }

  Future<void> _submitMeasurement(CocoonMeasurementDraft draft) async {
    final adapter = _gate3MutationAdapter;
    if (adapter == null) {
      throw StateError('Gate-3 mutation adapter is unavailable.');
    }
    CocoonPregnancyMeasurementType? type;
    for (final candidate in CocoonPregnancyMeasurementType.values) {
      if (candidate.wireValue == draft.metricId) {
        type = candidate;
        break;
      }
    }
    final primary = double.tryParse(draft.values['primary']?.trim() ?? '');
    final secondary = draft.values.containsKey('secondary')
        ? double.tryParse(draft.values['secondary']?.trim() ?? '')
        : null;
    if (type == null ||
        primary == null ||
        (draft.values.containsKey('secondary') && secondary == null)) {
      if (mounted) {
        setState(
          () => _measurementSubmitState = CocoonMeasurementSubmitState.error,
        );
      }
      throw ArgumentError(
        'Measurement draft is not a supported numeric observation.',
      );
    }
    if (mounted) {
      setState(
        () => _measurementSubmitState = CocoonMeasurementSubmitState.submitting,
      );
    }
    try {
      final result = await adapter.submitMeasurement(
        type: type,
        valuePrimary: primary,
        valueSecondary: secondary,
        note: draft.note,
      );
      if (result.disposition == CocoonGate3MutationDisposition.queued) {
        if (mounted) {
          setState(
            () => _measurementSubmitState = CocoonMeasurementSubmitState.queued,
          );
        }
        return;
      }
      await _refreshGate3ReadModels();
      if (mounted) {
        setState(
          () =>
              _measurementSubmitState = CocoonMeasurementSubmitState.confirmed,
        );
      }
    } on LifeMateApiException catch (error) {
      if (mounted) {
        setState(() {
          _measurementSubmitState = error.statusCode == 0
              ? CocoonMeasurementSubmitState.offline
              : CocoonMeasurementSubmitState.error;
        });
      }
      rethrow;
    } catch (_) {
      if (mounted) {
        setState(
          () => _measurementSubmitState = CocoonMeasurementSubmitState.error,
        );
      }
      rethrow;
    }
  }

  void _markGate3ReadModelsStale() {
    if (!mounted) return;
    setState(() {
      _calendarState = CocoonCalendarLoadState.error;
      _recordsState = CocoonRecordsState.error;
    });
  }

  void _clearGate3ReadModels() {
    if (!mounted) return;
    setState(() {
      _calendarState = CocoonCalendarLoadState.loading;
      _calendarItems = const [];
      _calendarAsOfLocalDate = null;
      _recordsState = CocoonRecordsState.loading;
      _records = const [];
      _checkInSyncState = CocoonCheckInSyncState.idle;
      _symptomCatalog = null;
      _symptomCatalogState = CocoonSymptomCatalogState.loading;
      _symptomSubmitState = CocoonSymptomSubmitState.idle;
      _moodSubmitState = CocoonMoodSubmitState.idle;
      _measurementSubmitState = CocoonMeasurementSubmitState.idle;
    });
  }

  Future<bool> _cacheAuthoritativeBootstrap(
    CocoonBootstrapSnapshot snapshot,
  ) async {
    try {
      final injected = widget.offlineBootstrapCache;
      if (injected != null) {
        await injected(snapshot);
        _ensureGate3MutationAdapter();
        return true;
      }
      final coordinator = _productionOfflineOwnerCoordinator();
      if (coordinator != null) {
        await coordinator.cacheAuthoritativeBootstrap(snapshot);
      }
      _ensureGate3MutationAdapter();
      return true;
    } on CocoonOfflineOwnerIdentityMismatchException {
      _apply(CocoonEntryState.runtimeUnavailable, null);
      return false;
    } on UnsupportedError {
      // Browser builds intentionally have no protected local health fallback.
      return true;
    } catch (_) {
      // Online authoritative state remains usable when device-protected cache
      // persistence is unavailable. Never replace/recreate local health data.
      recordSafeEvent('cocoon_offline_cache_unavailable');
      return true;
    }
  }

  Future<void> _applyOfflineOwnerFallback() async {
    try {
      final cached = widget.offlineSnapshotLoader != null
          ? await widget.offlineSnapshotLoader!.call()
          : await _productionOfflineOwnerCoordinator()
              ?.readCachedOwnerSnapshot();
      final episode = cached?.episode;
      if (cached != null &&
          episode != null &&
          episode.motherPersonId.trim().isNotEmpty &&
          episode.status == CocoonPregnancyEpisodeStatus.active) {
        _offlinePregnancySnapshot = cached;
        _ensureGate3MutationAdapter();
        _apply(
          CocoonEntryState.offlineOwnerPregnancy,
          episode.motherPersonId,
          pregnancySnapshot: cached,
        );
        return;
      }
    } on UnsupportedError {
      // Expected on web: no browser PHI fallback.
    } catch (_) {
      recordSafeEvent('cocoon_offline_cache_read_failed');
    }
    _apply(CocoonEntryState.offline, _personId);
  }

  CocoonPregnancyOfflineOwnerCoordinator? _productionOfflineOwnerCoordinator() {
    // Custom bootstrap loaders are test/host seams. They opt into offline cache
    // explicitly through the injected callbacks above and never touch global
    // Supabase state by accident.
    if (widget.bootstrapLoader != null) return null;
    final legacyAccountId = LifeMateAuth.currentAccountId?.trim();
    if (legacyAccountId == null || legacyAccountId.isEmpty) return null;
    if (_offlineOwnerCoordinator != null &&
        _offlineOwnerLegacyAccountId == legacyAccountId) {
      return _offlineOwnerCoordinator;
    }
    _offlineOwnerLegacyAccountId = legacyAccountId;
    _offlineOwnerCoordinator = CocoonPregnancyOfflineOwnerCoordinator(
      apiBaseUri: widget.config.apiBaseUri,
      legacyAccountId: legacyAccountId,
      accessToken: () => LifeMateAuth.currentAccessToken,
      identityResolver: () async {
        final client = LifeMateApiClient(
          baseUri: widget.config.apiBaseUri,
          accessToken: () => LifeMateAuth.currentAccessToken,
        );
        try {
          return await client.getCapabilities();
        } finally {
          client.close();
        }
      },
    );
    return _offlineOwnerCoordinator;
  }

  void _ensureGate3MutationAdapter() {
    final injected = widget.gate3MutationAdapter;
    if (injected != null) {
      _gate3MutationAdapter = injected;
      return;
    }
    if (widget.bootstrapLoader != null) return;
    final coordinator = _productionOfflineOwnerCoordinator();
    final legacyAccountId = _offlineOwnerLegacyAccountId;
    if (coordinator == null ||
        legacyAccountId == null ||
        legacyAccountId.isEmpty) {
      return;
    }
    if (_gate3MutationAdapter != null &&
        _gate3MutationOwnerLegacyAccountId == legacyAccountId) {
      return;
    }
    if (_ownsGate3MutationAdapter) _gate3MutationAdapter?.close();
    _gate3MutationAdapter = CocoonGate3MutationAdapter.production(
      baseUri: widget.config.apiBaseUri,
      accessToken: () => LifeMateAuth.currentAccessToken,
      offlineOwner: coordinator,
    );
    _gate3MutationOwnerLegacyAccountId = legacyAccountId;
    _ownsGate3MutationAdapter = true;
  }

  Future<void> _forgetOfflineOwner() async {
    try {
      final injected = widget.offlineOwnerForget;
      if (injected != null) {
        await injected();
      } else {
        await _productionOfflineOwnerCoordinator()?.forgetAdoptedOwner();
      }
    } on UnsupportedError {
      // No protected browser cache exists.
    } catch (_) {
      recordSafeEvent('cocoon_offline_identity_forget_failed');
    } finally {
      if (_ownsGate3MutationAdapter) _gate3MutationAdapter?.close();
      _gate3MutationAdapter = widget.gate3MutationAdapter;
      _gate3MutationOwnerLegacyAccountId = null;
      _ownsGate3MutationAdapter = false;
      _offlinePregnancySnapshot = null;
      _pregnancySnapshot = null;
      _clearGate3ReadModels();
    }
  }

  void _apply(
    CocoonEntryState state,
    String? personId, {
    CocoonPregnancySnapshot? pregnancySnapshot,
  }) {
    if (!mounted) return;
    setState(() {
      _entryState = state;
      _personId = personId;
      _pregnancySnapshot = pregnancySnapshot;
      if (state != CocoonEntryState.offlineOwnerPregnancy) {
        _offlinePregnancySnapshot = null;
      }
    });
  }

  @override
  Future<void> openLogin() async {
    await _forgetOfflineOwner();
    await LifeMateAuth.signOut();
  }

  @override
  Future<void> openCommerce() async {
    // #782 keeps Commerce authoritative. The subscription surface is mounted
    // by the host in a later product slice; never fabricate local entitlement.
    recordSafeEvent('cocoon_commerce_requested');
  }

  @override
  Future<void> beginPregnancySetup() async {
    // #788 owns episode activation. Keeping this action inert is safer than
    // creating a local pregnancy flag before the authoritative setup flow lands.
    recordSafeEvent('cocoon_pregnancy_setup_requested');
  }

  @override
  Future<void> openGlobalProfile() async {
    recordSafeEvent('cocoon_global_profile_requested');
  }

  @override
  void recordSafeEvent(String name) {
    // Event names only. No Person/Episode IDs, dates or reproductive facts.
  }
}

CocoonEntryState resolveCocoonEntryState(CocoonBootstrapSnapshot snapshot) {
  if (snapshot.personId.isEmpty ||
      snapshot.application.availability !=
          CocoonApplicationAvailability.available) {
    return CocoonEntryState.runtimeUnavailable;
  }

  if (snapshot.application.enrollmentState !=
      CocoonApplicationEnrollmentState.active) {
    return CocoonEntryState.notEnrolled;
  }

  final commerce = snapshot.commerceEligibility.state;
  if (commerce == CocoonCommerceEligibilityState.unavailable ||
      commerce == CocoonCommerceEligibilityState.error ||
      commerce == CocoonCommerceEligibilityState.unknown ||
      snapshot.entitlement.state == CocoonEntitlementState.unknown) {
    return CocoonEntryState.runtimeUnavailable;
  }

  if (snapshot.entitlement.state != CocoonEntitlementState.active ||
      commerce != CocoonCommerceEligibilityState.entitled) {
    return CocoonEntryState.notEntitled;
  }

  final episode = snapshot.activeEpisode;
  if (episode == null ||
      episode.status != CocoonPregnancyEpisodeStatus.active) {
    return CocoonEntryState.noPregnancy;
  }
  return CocoonEntryState.activePregnancy;
}
