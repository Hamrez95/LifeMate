import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

// ایمپورت‌های خودتان را چک کنید که مسیر درست باشد
import 'screens/home_screen.dart'; 
import 'localization/locale_provider.dart';
import 'localization/app_localizations.dart';

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
    final localeProvider = Provider.of<LocaleProvider>(context);
    
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'WellMate',
      theme: ThemeData(
        fontFamily: 'Nunito',
        scaffoldBackgroundColor: const Color(0xFFF5F8FF),
        primaryColor: const Color(0xFF4A90E2),
        colorScheme: ColorScheme.fromSwatch().copyWith(
          primary: const Color(0xFF4A90E2),
          secondary: const Color(0xFF4A90E2),
        ),
        textTheme: const TextTheme(
          bodyLarge: TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
          bodyMedium: TextStyle(fontSize: 16),
        ),
        useMaterial3: true,
      ),
      // تنظیمات زبان
      locale: localeProvider.locale,
      supportedLocales: const [
        Locale('en'),
        Locale('fa'),
      ],
      // نکته مهم: کلمه const را از ابتدای لیست زیر حذف کردم تا ارور برطرف شود
      localizationsDelegates: [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      // جهت چیدمان (راست‌چین برای فارسی)
      builder: (context, child) {
        final dir = localeProvider.locale.languageCode == 'fa' 
            ? TextDirection.rtl 
            : TextDirection.ltr;
        return Directionality(textDirection: dir, child: child!);
      },
      home: const HomeScreen(),
    );
  }
}
