import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_localizations/flutter_localizations.dart'; // 👈 اضافه شد

import 'package:wellmate/providers/notification_provider.dart';
import 'package:wellmate/providers/settings_provider.dart';
import 'package:wellmate/screens/home/home_screen.dart';

// ایمپورت‌ها را چک کنید
import 'localization/locale_provider.dart';
import 'localization/app_localizations.dart'; // 👈 اضافه شد

void main() {
  runApp(
    ChangeNotifierProvider(
      create: (_) => LocaleProvider(),
      child: const WellMateApp(),
    ),
  );
}

class WellMateApp extends StatelessWidget {
  const WellMateApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => NotificationProvider()),
        ChangeNotifierProvider(create: (_) => LocaleProvider()),
        ChangeNotifierProvider(create: (_) => SettingsProvider()),
      ],
      child: Consumer2<LocaleProvider, SettingsProvider>(
        builder: (context, localeProvider, settingsProvider, child) {
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            locale: localeProvider.locale,

            // 👇 این بخش برای رفع ارور صفحه قرمز کاملاً ضروری است
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: const [
              Locale('en', ''),
              Locale('fa', ''),
            ],
            // 👆 پایان بخش لوکالیزیشن

            // این بخش سایز متن کل اپلیکیشن را مدیریت می‌کند
            builder: (context, child) {
              return MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler:
                      TextScaler.linear(settingsProvider.textScaleFactor),
                ),
                child: child!,
              );
            },
            home: const HomeScreen(),
          );
        },
      ),
    );
  }
}
