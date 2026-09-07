import 'dart:ui';

import 'package:cocoonmate_module/cocoonmate_module.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:lifemate_client/lifemate_client.dart';
import 'package:lifemate_ui/lifemate_ui.dart';

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
  bool _refreshing = false;
  CocoonPregnancyOfflineOwnerCoordinator? _offlineOwnerCoordinator;
  String? _offlineOwnerLegacyAccountId;

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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => refresh());
  }

  @override
  void dispose() {
    _runtimeClient?.close();
    _pregnancyClient?.close();
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
  Widget build(BuildContext context) =>
      CocoonMateModule(config: CocoonModuleConfig(host: this));

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
      _apply(next, snapshot.personId.isEmpty ? null : snapshot.personId);
    } on LifeMateApiException catch (error) {
      if (error.isUnauthorized) {
        await _forgetOfflineOwner();
        await (widget.signOut?.call() ?? LifeMateAuth.signOut());
        _apply(CocoonEntryState.unauthenticated, null);
      } else if (error.statusCode == 0) {
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

  Future<bool> _cacheAuthoritativeBootstrap(
    CocoonBootstrapSnapshot snapshot,
  ) async {
    try {
      final injected = widget.offlineBootstrapCache;
      if (injected != null) {
        await injected(snapshot);
        return true;
      }
      final coordinator = _productionOfflineOwnerCoordinator();
      if (coordinator != null) {
        await coordinator.cacheAuthoritativeBootstrap(snapshot);
      }
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
        _apply(CocoonEntryState.offlineOwnerPregnancy, episode.motherPersonId);
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
      _offlinePregnancySnapshot = null;
    }
  }

  void _apply(CocoonEntryState state, String? personId) {
    if (!mounted) return;
    setState(() {
      _entryState = state;
      _personId = personId;
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
