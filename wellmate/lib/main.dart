import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'package:wellmate/providers/notification_provider.dart';
import 'package:wellmate/providers/settings_provider.dart';
import 'package:wellmate/screens/home/home_screen.dart';
import 'package:wellmate/core/theme/app_style.dart'; // 👈 مسیر AppColors و AppTextStyles (بررسی کنید درست باشد)

import 'localization/locale_provider.dart';
import 'localization/app_localizations.dart';

void main() {
  runApp(
    // 👈 انتقال همه Providerها به روت اصلی اپلیکیشن
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => NotificationProvider()),
        ChangeNotifierProvider(create: (_) => LocaleProvider()),
        ChangeNotifierProvider(create: (_) => SettingsProvider()),
      ],
      child: const WellMateApp(),
    ),
  );
}

class WellMateApp extends StatelessWidget {
  const WellMateApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer2<LocaleProvider, SettingsProvider>(
      builder: (context, localeProvider, settingsProvider, child) {
        // 👈 بررسی زبان فعلی برای تعیین فونت
        final isPersian = localeProvider.locale.languageCode == 'fa';

        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'WellMate',

          // 👇 اضافه شدن تم استاندارد و موبایلی مشابه CareMate
          theme: ThemeData(
            fontFamily: isPersian ? 'Vazir' : 'Nunito',
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
            Locale('fa', ''), // 👈 فارسی به عنوان اولین زبان (پیش‌فرض)
            Locale('en', ''),
          ],

          // 👇 حفظ ساختار تغییر سایز متن مخصوص WellMate
          builder: (context, child) {
            return MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(settingsProvider.textScaleFactor),
              ),
              child: child!,
            );
          },

          home: const HomeScreen(),
        );
      },
    );
  }
}
