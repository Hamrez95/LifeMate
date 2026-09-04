import 'dart:ui';

import 'package:cocoonmate_module/cocoonmate_module.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:lifemate_client/lifemate_client.dart';
import 'package:lifemate_ui/lifemate_ui.dart';

const cocoonAppVersion = '0.1.0+1';

typedef CocoonRuntimeLoader = Future<LifeMateRuntimeConfigSnapshot> Function();
typedef CocoonBootstrapLoader = Future<CocoonBootstrapSnapshot> Function();

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
    super.key,
  });

  final AppConfig config;
  final Locale locale;
  final CocoonRuntimeLoader? runtimeLoader;
  final CocoonBootstrapLoader? bootstrapLoader;

  @override
  State<CocoonAuthenticatedHost> createState() =>
      _CocoonAuthenticatedHostState();
}

class _CocoonAuthenticatedHostState extends State<CocoonAuthenticatedHost>
    implements CocoonHostContract {
  CocoonEntryState _entryState = CocoonEntryState.loading;
  String? _personId;
  bool _refreshing = false;

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
  Widget build(BuildContext context) =>
      CocoonMateModule(config: CocoonModuleConfig(host: this));

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
      final next = resolveCocoonEntryState(snapshot);
      _apply(next, snapshot.personId.isEmpty ? null : snapshot.personId);
    } on LifeMateApiException catch (error) {
      if (error.isUnauthorized) {
        await LifeMateAuth.signOut();
        _apply(CocoonEntryState.unauthenticated, null);
      } else if (error.statusCode == 0) {
        _apply(CocoonEntryState.offline, _personId);
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

  void _apply(CocoonEntryState state, String? personId) {
    if (!mounted) return;
    setState(() {
      _entryState = state;
      _personId = personId;
    });
  }

  @override
  Future<void> openLogin() => LifeMateAuth.signOut();

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
  if (episode == null || episode.status != CocoonPregnancyEpisodeStatus.active) {
    return CocoonEntryState.noPregnancy;
  }
  return CocoonEntryState.activePregnancy;
}
