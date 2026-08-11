import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:lifemate_client/lifemate_client.dart';
import 'package:provider/provider.dart';

import 'core/constants/app_colors.dart';
import 'core/localization/app_localizations.dart';
import 'core/localization/locale_provider.dart';
import 'providers/care_notification_provider.dart';
import 'screens/caremate_root_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await LifeMateSensitiveClipboardGuard.install();
  final config = AppConfig.fromEnvironment();
  var authInitialized = false;
  if (config.isConfigured) {
    try {
      authInitialized = await LifeMateBootstrap.initialize(config);
    } catch (_) {
      debugPrint('Supabase initialization failed.');
    }
  }

  final notificationProvider = CareNotificationProvider();
  try {
    await notificationProvider.initialize();
  } catch (_) {
    debugPrint('CareMate notification initialization failed.');
  }

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => LocaleProvider()),
        ChangeNotifierProvider.value(value: notificationProvider),
      ],
      child: CareMateApp(config: config, authInitialized: authInitialized),
    ),
  );
}

class CareMateApp extends StatelessWidget {
  const CareMateApp({
    super.key,
    this.home,
    this.config,
    this.authInitialized = false,
  });

  final Widget? home;
  final AppConfig? config;
  final bool authInitialized;

  @override
  Widget build(BuildContext context) {
    final localeProvider = Provider.of<LocaleProvider>(context);
    final isPersian = localeProvider.locale.languageCode == 'fa';
    final runtimeConfig = config ?? AppConfig.fromEnvironment();

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'CareMate',
      theme: ThemeData(
        fontFamily: isPersian ? 'Vazir' : 'Nunito',
        scaffoldBackgroundColor: AppColors.background,
        primaryColor: AppColors.primaryBlue,
        colorScheme: ColorScheme.fromSwatch().copyWith(
          primary: AppColors.primaryBlue,
          secondary: AppColors.primaryBlue,
        ),
        textTheme: const TextTheme(
          bodyLarge: TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
          bodyMedium: TextStyle(fontSize: 16),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFFF6F9FD),
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
            color: AppColors.primaryBlue,
            fontWeight: FontWeight.w800,
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 17,
            vertical: 18,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(
              color: AppColors.primaryBlue.withValues(alpha: 0.10),
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(
              color: AppColors.primaryBlue,
              width: 1.5,
            ),
          ),
        ),
        useMaterial3: true,
      ),
      locale: localeProvider.locale,
      supportedLocales: const [Locale('en'), Locale('fa')],
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: home ?? _productionHome(runtimeConfig, authInitialized),
    );
  }

  static Widget _productionHome(AppConfig config, bool authInitialized) {
    if (!config.isConfigured) {
      return ConfigurationRequiredScreen(
        appName: 'CareMate',
        missingValues: config.missingOrInvalidValues,
      );
    }
    if (!authInitialized) {
      return const ConfigurationRequiredScreen(
        appName: 'CareMate',
        missingValues: ['SUPABASE_INITIALIZATION_FAILED'],
      );
    }
    return LifeMateExperienceGate(
      config: config,
      appName: 'CareMate',
      logoAssetPath: 'assets/images/CareMateWithoutBack.png',
      authenticatedBuilder: (context, apiClient) =>
          _AuthenticatedCareMateShell(apiClient: apiClient),
    );
  }
}

class _AuthenticatedCareMateShell extends StatefulWidget {
  const _AuthenticatedCareMateShell({required this.apiClient});

  final LifeMateApiClient apiClient;

  @override
  State<_AuthenticatedCareMateShell> createState() =>
      _AuthenticatedCareMateShellState();
}

class _AuthenticatedCareMateShellState
    extends State<_AuthenticatedCareMateShell> {
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) {
    return Provider<LifeMateApiClient>.value(
      value: widget.apiClient,
      child: NavigatorPopHandler<void>(
        onPop: () => _navigatorKey.currentState?.pop<void>(),
        child: Navigator(
          key: _navigatorKey,
          onGenerateRoute: (_) => MaterialPageRoute<void>(
            builder: (_) => const CareMateRootShell(),
          ),
        ),
      ),
    );
  }
}
