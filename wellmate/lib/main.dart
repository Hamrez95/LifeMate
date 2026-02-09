
import 'package:flutter/material.dart';
import 'package:wellmate/screens/home_screen.dart';

void main() {
	runApp(const WellMateApp());
}

class WellMateApp extends StatelessWidget {
	const WellMateApp({super.key});

	@override
	Widget build(BuildContext context) {
		return MaterialApp(
			debugShowCheckedModeBanner: false,
			title: 'WellMate',
			theme: ThemeData(
				fontFamily: 'Nunito', // Use a rounded, friendly font (add to pubspec.yaml)
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
			home: const HomeScreen(),
		);
	}
}
