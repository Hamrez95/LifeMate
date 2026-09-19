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
typedef CocoonOfflineBootstrapCache =
    Future<void> Function(CocoonBootstrapSnapshot snapshot);
typedef CocoonOfflineSnapshotLoader =
    Future<CocoonPregnancySnapshot?> Function();
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
      authenticatedBuilder: (context, api) => CocoonAuthenticatedHost(
        config: config,
        locale: Localizations.localeOf(context),
        treatmentApi: api,
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
    this.treatmentApi,
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
  /// The shared, durable WellMate client supplied by [LifeMateExperienceGate].
  /// Medication adherence never gets a Cocoon-specific mutation client.
  final LifeMateApiClient? treatmentApi;
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
  CocoonMedicationSubmitState _medicationSubmitState =
      CocoonMedicationSubmitState.idle;
  List<CocoonMedicationOption> _medicationOptions = const [];

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
  late final CocoonPregnancyTreatmentsApiClient? _treatmentContextClient =
      widget.bootstrapLoader == null
      ? CocoonPregnancyTreatmentsApiClient(
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
    _treatmentContextClient?.close();
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
      onRetryCalendar: () => _refreshGate3ReadModels(),
      recordsState: _recordsState,
      records: _records,
      onRetryRecords: () => _refreshGate3ReadModels(),
      checkInSyncState: _checkInSyncState,
      onSubmitCheckIn: _gate3MutationAdapter == null ? null : _submitCheckIn,
      medicationOptions: _medicationOptions,
      medicationInitialTime: _medicationLogTime(DateTime.now()),
      medicationSubmitState: _medicationSubmitState,
      onPickMedicationTime: _pickMedicationTime,
      onSubmitMedication:
          _medicationOptions.isEmpty ||
              widget.treatmentApi is! DurableLifeMateApiClient
          ? null
          : _submitMedication,
    ),
  );

  @override
  Future<void> refresh() async {
    if (_refreshing) return;
    _refreshing = true;
    if (mounted) setState(() => _entryState = CocoonEntryState.loading);
    try {
      final runtime =
          await (widget.runtimeLoader?.call() ??
              _runtimeClient!.load(forceRefresh: true));
      if (runtime.product != 'cocoonmate' ||
          runtime.platform.trim().isEmpty ||
          !runtime.isTrustedForUpdatePolicy(DateTime.now())) {
        _apply(CocoonEntryState.runtimeUnavailable, null);
        return;
      }

      final snapshot =
          await (widget.bootstrapLoader?.call() ??
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
      await _refreshTreatmentContext(DateTime.now());
    } catch (_) {
      _markGate3ReadModelsStale();
    } finally {
      _refreshingGate3 = false;
    }
  }

  Future<void> _refreshTreatmentContext(DateTime now) async {
    final client = _treatmentContextClient;
    if (client == null || _entryState != CocoonEntryState.activePregnancy) {
      return;
    }
    final localToday = DateTime(now.year, now.month, now.day);
    try {
      final context = await client.list(
        fromDate: localToday,
        toDate: localToday,
      );
      final plans = <String, CocoonPregnancyTreatmentPlanProjection>{
        for (final plan in context.typedTreatmentPlans) plan.id: plan,
      };
      final options = <CocoonMedicationOption>[];
      for (final occurrence in context.typedDoseOccurrences) {
        final plan = plans[occurrence.treatmentPlanId];
        if (plan == null) continue;
        final medication = [plan.medicationName, plan.strengthText]
            .whereType<String>()
            .where((value) => value.trim().isNotEmpty)
            .join(' ');
        final dose = [plan.doseText, occurrence.scheduledLocalTime]
            .where((value) => value.trim().isNotEmpty)
            .join(' · ');
        options.add(
          CocoonMedicationOption(
            doseOccurrenceId: occurrence.id,
            expectedVersion: occurrence.version,
            name: medication,
            doseLabel: dose,
          ),
        );
      }
      if (!mounted || _entryState != CocoonEntryState.activePregnancy) return;
      setState(() => _medicationOptions = List.unmodifiable(options));
    } on Object {
      // The shared treatment domain remains the source of truth. Do not show
      // stale or invented medication options if its authorized projection fails.
      if (mounted) setState(() => _medicationOptions = const []);
    }
  }

  CocoonMedicationLogTime _medicationLogTime(DateTime local) =>
      CocoonMedicationLogTime(
        label: MaterialLocalizations.of(context).formatTimeOfDay(
          TimeOfDay.fromDateTime(local),
        ),
        occurredAtUtc: local.toUtc(),
      );

  Future<CocoonMedicationLogTime?> _pickMedicationTime() async {
    final now = DateTime.now();
    final selected = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(now),
    );
    if (selected == null) return null;
    final local = DateTime(
      now.year,
      now.month,
      now.day,
      selected.hour,
      selected.minute,
    );
    return _medicationLogTime(local);
  }

  Future<void> _submitMedication(CocoonMedicationLogDraft draft) async {
    final api = widget.treatmentApi;
    if (api is! DurableLifeMateApiClient) {
      throw StateError('Shared durable treatment client is unavailable.');
    }
    if (mounted) {
      setState(
        () => _medicationSubmitState = CocoonMedicationSubmitState.submitting,
      );
    }
    try {
      final result = await api.reportDose(
        occurrenceId: draft.doseOccurrenceId,
        clientRequestId: LifeMateApiClient.createClientRequestId(),
        version: draft.expectedVersion,
        status: switch (draft.action) {
          CocoonMedicationLogAction.taken => 'taken',
          CocoonMedicationLogAction.skipped => 'skipped',
        },
        occurredAtUtc: draft.occurredAtUtc,
      );
      if (mounted) {
        setState(
          () => _medicationSubmitState = result['pendingSync'] == true
              ? CocoonMedicationSubmitState.queued
              : CocoonMedicationSubmitState.confirmed,
        );
      }
      await _refreshGate3ReadModels();
    } on LifeMateApiException catch (error) {
      if (mounted) {
        setState(
          () => _medicationSubmitState = error.statusCode == 0
              ? CocoonMedicationSubmitState.offline
              : CocoonMedicationSubmitState.error,
        );
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
      _medicationSubmitState = CocoonMedicationSubmitState.idle;
      _medicationOptions = const [];
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
