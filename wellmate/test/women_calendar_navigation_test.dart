import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:wellmate/core/widgets/wellmate_bottom_nav.dart';
import 'package:wellmate/localization/locale_provider.dart';
import 'package:wellmate/main.dart';
import 'package:wellmate/providers/settings_provider.dart';

void main() {
  testWidgets('women calendar navigation is hidden before activation', (
    tester,
  ) async {
    await tester.pumpWidget(_navHarness(womenCalendarEnabled: false));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('wellmate-nav-3')), findsNothing);
    expect(find.bySemanticsLabel('تقویم بانوان'), findsNothing);
    expect(find.byKey(const ValueKey('wellmate-nav-4')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('women calendar navigation appears after activation', (
    tester,
  ) async {
    await tester.pumpWidget(_navHarness(womenCalendarEnabled: true));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('wellmate-nav-3')), findsOneWidget);
    expect(find.bySemanticsLabel('تقویم بانوان'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Widget _navHarness({required bool womenCalendarEnabled}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider(create: (_) => LocaleProvider()),
      ChangeNotifierProvider(create: (_) => SettingsProvider()),
    ],
    child: WellMateApp(
      home: Scaffold(
        bottomNavigationBar: WellMateBottomNav(
          currentIndex: 4,
          womenCalendarEnabled: womenCalendarEnabled,
          onTap: (_) {},
        ),
      ),
    ),
  );
}
