import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:lifemate_client/lifemate_client.dart';
import 'package:provider/provider.dart';

import 'core/constants/app_colors.dart';
import 'core/localization/app_localizations.dart';
import 'core/localization/locale_provider.dart';
import 'screens/dashboard_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final config = AppConfig.fromEnvironment();
  var authInitialized = false;
  if (config.isConfigured) {
    try {
      authInitialized = await LifeMateBootstrap.initialize(config);
    } catch (error, stackTrace) {
      debugPrint('Supabase initialization failed: $error\n$stackTrace');
    }
  }

  runApp(
    ChangeNotifierProvider(
      create: (_) => LocaleProvider(),
      child: CareMateApp(
        config: config,
        authInitialized: authInitialized,
      ),
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

  /// Allows tests to verify the application shell without network side effects.
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
        useMaterial3: true,
      ),
      locale: localeProvider.locale,
      supportedLocales: const [
        Locale('en'),
        Locale('fa'),
      ],
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: home ?? _productionHome(runtimeConfig, authInitialized),
    );
  }

  static Widget _productionHome(
    AppConfig config,
    bool authInitialized,
  ) {
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
          Provider<LifeMateApiClient>.value(
        value: apiClient,
        child: Navigator(
          onGenerateRoute: (_) => MaterialPageRoute<void>(
            builder: (_) => const DashboardScreen(),
          ),
        ),
      ),
    );
  }
}
