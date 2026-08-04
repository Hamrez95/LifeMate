import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:wellmate/core/widgets/wellmate_bottom_nav.dart';
import 'package:wellmate/localization/locale_provider.dart';
import 'package:wellmate/main.dart';
import 'package:wellmate/providers/settings_provider.dart';

void main() {
  testWidgets('women calendar navigation is present and Persian labelled', (
    tester,
  ) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => LocaleProvider()),
          ChangeNotifierProvider(create: (_) => SettingsProvider()),
        ],
        child: WellMateApp(
          home: Scaffold(
            bottomNavigationBar: WellMateBottomNav(
              currentIndex: 4,
              womenCalendarEnabled: true,
              onTap: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('wellmate-nav-3')), findsOneWidget);
    expect(find.bySemanticsLabel('تقویم بانوان'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
