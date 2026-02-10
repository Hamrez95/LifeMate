
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:caremate/screens/dashboard_screen.dart';
import 'package:caremate/localization/app_localizations.dart';
import 'package:provider/provider.dart';
import 'package:caremate/localization/locale_provider.dart';

void main() {
	runApp(
		ChangeNotifierProvider(
			create: (_) => LocaleProvider(),
			child: const CareMateApp(),
		),
	);
}

class CareMateApp extends StatelessWidget {
	const CareMateApp({super.key});

	@override
	Widget build(BuildContext context) {
		final localeProvider = Provider.of<LocaleProvider>(context);
		return MaterialApp(
			debugShowCheckedModeBanner: false,
			title: 'CareMate',
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
			home: const DashboardScreen(),
		);
	}
}
