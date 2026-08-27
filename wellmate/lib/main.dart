import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:lifemate_client/lifemate_client.dart';
import 'package:lifemate_ui/lifemate_ui.dart';
import 'package:provider/provider.dart';
import 'package:wellmate/core/constants/app_version.dart';
import 'package:wellmate/core/state/wellmate_refresh.dart';
import 'package:wellmate/core/theme/app_style.dart';
import 'package:wellmate/core/widgets/medication_home_widget_service.dart';
import 'package:wellmate/providers/medication_provider.dart';
import 'package:wellmate/providers/notification_provider.dart';
import 'package:wellmate/providers/settings_provider.dart';
import 'package:wellmate/screens/home/home_screen.dart';

import 'localization/app_localizations.dart';
import 'localization/locale_provider.dart';

void main() {
  final config = AppConfig.fromEnvironment();
  final crashReporter = LifeMateCrashReporter(
    config: config,
    application: 'wellmate',
    releaseVersion: wellMateAppVersion,
  );

  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      crashReporter.installGlobalHandlers();

      var authInitialized = false;
      if (config.isConfigured) {
        try {
          authInitialized = await LifeMateBootstrap.initialize(config);
        } catch (error, stackTrace) {
          FlutterError.reportError(
            FlutterErrorDetails(
              exception: error,
              stack: stackTrace,
              library: 'wellmate.bootstrap',
              silent: true,
            ),
          );
          debugPrint('Supabase initialization failed.');
        }
      }
      final notificationProvider = NotificationProvider();
      try {
        await notificationProvider.initialize();
      } catch (error, stackTrace) {
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: error,
            stack: stackTrace,
            library: 'wellmate.notifications',
            silent: true,
          ),
        );
        debugPrint('Notification initialization failed.');
      }
      try {
        await MedicationHomeWidgetService.initializeInteractivity();
      } catch (error, stackTrace) {
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: error,
            stack: stackTrace,
            library: 'wellmate.widget',
            silent: true,
          ),
        );
        debugPrint('Medication widget interaction initialization failed.');
      }

      runApp(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: notificationProvider),
            ChangeNotifierProvider(create: (_) => LocaleProvider()),
            ChangeNotifierProvider(create: (_) => SettingsProvider()),
            ChangeNotifierProvider(create: (_) => MedicationProvider()),
          ],
          child: WellMateApp(config: config, authInitialized: authInitialized),
        ),
      );
    },
    (error, stackTrace) {
      unawaited(
        crashReporter.report(
          error,
          stackTrace,
          source: LifeMateCrashSource.zone,
          fatal: true,
        ),
      );
      if (kDebugMode) {
        debugPrint('Uncaught WellMate zone error (${error.runtimeType}).');
      }
    },
  );
}

class WellMateApp extends StatelessWidget {
  const WellMateApp({
    super.key,
    this.home,
    this.config,
    this.authInitialized = false,
  });

  /// Allows tests to supply a side-effect-free root.
  final Widget? home;
  final AppConfig? config;
  final bool authInitialized;

  @override
  Widget build(BuildContext context) {
    return Consumer2<LocaleProvider, SettingsProvider>(
      builder: (context, localeProvider, settingsProvider, child) {
        final isPersian = localeProvider.locale.languageCode == 'fa';
        final runtimeConfig = config ?? AppConfig.fromEnvironment();

        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'WellMate',
          theme: ThemeData(
            fontFamily: isPersian ? 'Vazir' : 'Poppins',
            scaffoldBackgroundColor: AppColors.background,
            primaryColor: AppColors.primary,
            colorScheme: ColorScheme.fromSwatch().copyWith(
              primary: AppColors.primary,
              secondary: AppColors.primary,
            ),
            inputDecorationTheme: InputDecorationTheme(
              filled: true,
              fillColor: const Color(0xFFF8FCFA),
              floatingLabelBehavior: FloatingLabelBehavior.always,
              alignLabelWithHint: true,
              hintStyle: const TextStyle(
                color: Color(0xFF8B95A3),
                fontWeight: FontWeight.w400,
              ),
              labelStyle: const TextStyle(
                color: Color(0xFF667085),
                fontWeight: FontWeight.w600,
              ),
              floatingLabelStyle: TextStyle(
                color: AppColors.primary,
                fontWeight: FontWeight.w800,
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 17,
                vertical: 17,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(
                  color: AppColors.primary.withValues(alpha: 0.10),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(
                  color: AppColors.primary,
                  width: 1.5,
                ),
              ),
            ),
            useMaterial3: true,
          ),
          locale: localeProvider.locale,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [Locale('fa'), Locale('en')],
          builder: (context, child) {
            final appChild = child ?? const SizedBox.shrink();
            return Directionality(
              textDirection: isPersian ? TextDirection.rtl : TextDirection.ltr,
              child: MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: TextScaler.linear(
                    settingsProvider.textScaleFactor,
                  ),
                ),
                child: appChild,
              ),
            );
          },
          home: home ?? _productionHome(runtimeConfig, authInitialized),
        );
      },
    );
  }

  static Widget _productionHome(AppConfig config, bool authInitialized) {
    if (!config.isConfigured) {
      return ConfigurationRequiredScreen(
        appName: 'WellMate',
        missingValues: config.missingOrInvalidValues,
      );
    }
    if (!authInitialized) {
      return const ConfigurationRequiredScreen(
        appName: 'WellMate',
        missingValues: ['SUPABASE_INITIALIZATION_FAILED'],
      );
    }
    return LifeMateExperienceGate(
      config: config,
      appName: 'WellMate',
      logoAssetPath: 'assets/images/WellMateWithoutBack.png',
      unauthenticatedBuilder: (context, _, appName, logoAssetPath) =>
          LifeMateSharedAuthExperience(
            appName: appName,
            logoAssetPath: logoAssetPath,
          ),
      authenticatedBuilder: (context, apiClient) =>
          _AuthenticatedWellMateShell(apiClient: apiClient),
    );
  }
}

class _AuthenticatedWellMateShell extends StatefulWidget {
  const _AuthenticatedWellMateShell({required this.apiClient});

  final LifeMateApiClient apiClient;

  @override
  State<_AuthenticatedWellMateShell> createState() =>
      _AuthenticatedWellMateShellState();
}

class _AuthenticatedWellMateShellState
    extends State<_AuthenticatedWellMateShell>
    with WidgetsBindingObserver {
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  final WellMateNavigationRefreshObserver _refreshObserver =
      WellMateNavigationRefreshObserver();
  Timer? _widgetSyncTimer;
  bool _widgetSyncInFlight = false;

  @override
  void initState() {
    super.initState();
    context.read<NotificationProvider>().attachApiClient(widget.apiClient);
    WidgetsBinding.instance.addObserver(this);
    WellMateRefreshSignal.revision.addListener(_scheduleMedicationWidgetSync);
    scheduleMicrotask(_scheduleMedicationWidgetSync);
    _widgetSyncTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => _scheduleMedicationWidgetSync(),
    );
  }

  @override
  void didUpdateWidget(covariant _AuthenticatedWellMateShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.apiClient, widget.apiClient)) {
      final notifications = context.read<NotificationProvider>();
      notifications.detachApiClient(oldWidget.apiClient);
      notifications.attachApiClient(widget.apiClient);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _scheduleMedicationWidgetSync();
    }
  }

  void _scheduleMedicationWidgetSync() {
    unawaited(_syncMedicationWidget());
  }

  Future<void> _syncMedicationWidget() async {
    if (_widgetSyncInFlight ||
        !MedicationHomeWidgetService.isSupportedPlatform) {
      return;
    }
    _widgetSyncInFlight = true;
    try {
      if (!await MedicationHomeWidgetService.hasInstalledWidget()) return;
      await MedicationHomeWidgetService.refreshFromApi(widget.apiClient);
    } catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'wellmate.widget.sync',
          silent: true,
        ),
      );
    } finally {
      _widgetSyncInFlight = false;
    }
  }

  @override
  void dispose() {
    context.read<NotificationProvider>().detachApiClient(widget.apiClient);
    _widgetSyncTimer?.cancel();
    WellMateRefreshSignal.revision.removeListener(
      _scheduleMedicationWidgetSync,
    );
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Provider<LifeMateApiClient>.value(
      value: widget.apiClient,
      child: NavigatorPopHandler<void>(
        onPop: () => _navigatorKey.currentState?.pop<void>(),
        child: Navigator(
          key: _navigatorKey,
          observers: [_refreshObserver],
          onGenerateRoute: (_) =>
              MaterialPageRoute<void>(builder: (_) => const HomeScreen()),
        ),
      ),
    );
  }
}
