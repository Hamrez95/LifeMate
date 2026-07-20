import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:wellmate/core/theme/app_style.dart';
import 'package:wellmate/providers/medication_provider.dart';
import 'package:wellmate/providers/notification_provider.dart';
import 'package:wellmate/providers/settings_provider.dart';
import 'package:wellmate/screens/home/home_screen.dart';

import 'localization/app_localizations.dart';
import 'localization/locale_provider.dart';

void main() {
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => NotificationProvider()),
        ChangeNotifierProvider(create: (_) => LocaleProvider()),
        ChangeNotifierProvider(create: (_) => SettingsProvider()),
        ChangeNotifierProvider(create: (_) => MedicationProvider()),
      ],
      child: const WellMateApp(),
    ),
  );
}

class WellMateApp extends StatelessWidget {
  const WellMateApp({super.key, this.home});

  /// Allows tests and future app shells to supply a side-effect-free root while
  /// production keeps the real home screen as the default.
  final Widget? home;

  @override
  Widget build(BuildContext context) {
    return Consumer2<LocaleProvider, SettingsProvider>(
      builder: (context, localeProvider, settingsProvider, child) {
        final isPersian = localeProvider.locale.languageCode == 'fa';

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
            useMaterial3: true,
          ),
          locale: localeProvider.locale,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [
            Locale('fa'),
            Locale('en'),
          ],
          builder: (context, child) {
            return MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler:
                    TextScaler.linear(settingsProvider.textScaleFactor),
              ),
              child: child!,
            );
          },
          home: home ?? const HomeScreen(),
        );
      },
    );
  }
}
