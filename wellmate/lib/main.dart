import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:lifemate_client/lifemate_client.dart';
import 'package:provider/provider.dart';
import 'package:wellmate/core/state/wellmate_refresh.dart';
import 'package:wellmate/core/theme/app_style.dart';
import 'package:wellmate/providers/medication_provider.dart';
import 'package:wellmate/providers/notification_provider.dart';
import 'package:wellmate/providers/settings_provider.dart';
import 'package:wellmate/screens/home/home_screen.dart';

import 'localization/app_localizations.dart';
import 'localization/locale_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final config = AppConfig.fromEnvironment();
  var authInitialized = false;
  if (config.isConfigured) {
    try {
      authInitialized = await LifeMateBootstrap.initialize(config);
    } catch (_) {
      debugPrint('Supabase initialization failed.');
    }
  }
  final notificationProvider = NotificationProvider();
  try {
    await notificationProvider.initialize();
  } catch (_) {
    debugPrint('Notification initialization failed.');
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
            return MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(settingsProvider.textScaleFactor),
              ),
              child: child!,
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
    extends State<_AuthenticatedWellMateShell> {
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  final WellMateNavigationRefreshObserver _refreshObserver =
      WellMateNavigationRefreshObserver();

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
