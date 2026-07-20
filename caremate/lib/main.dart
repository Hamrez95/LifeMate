import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'core/constants/app_colors.dart';
import 'core/localization/app_localizations.dart';
import 'core/localization/locale_provider.dart';
import 'screens/dashboard_screen.dart';

void main() {
  runApp(
    ChangeNotifierProvider(
      create: (_) => LocaleProvider(),
      child: const CareMateApp(),
    ),
  );
}

class CareMateApp extends StatelessWidget {
  const CareMateApp({super.key, this.home});

  /// Allows tests to verify the application shell without starting dashboard
  /// polling. Production continues to use [DashboardScreen] by default.
  final Widget? home;

  @override
  Widget build(BuildContext context) {
    final localeProvider = Provider.of<LocaleProvider>(context);
    final isPersian = localeProvider.locale.languageCode == 'fa';

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
      home: home ?? const DashboardScreen(),
    );
  }
}
