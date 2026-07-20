import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:wellmate/localization/locale_provider.dart';
import 'package:wellmate/main.dart';
import 'package:wellmate/providers/medication_provider.dart';
import 'package:wellmate/providers/notification_provider.dart';
import 'package:wellmate/providers/settings_provider.dart';

void main() {
  testWidgets('WellMate app shell builds with its root providers',
      (WidgetTester tester) async {
    await tester.pumpWidget(
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

    await tester.pump();

    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.byType(WellMateApp), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
