import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:wellmate/core/widgets/wellmate_bottom_nav.dart';
import 'package:wellmate/localization/app_localizations.dart';
import 'package:wellmate/localization/locale_provider.dart';

void main() {
  testWidgets('women calendar navigation follows activation state', (
    tester,
  ) async {
    await tester.pumpWidget(_navHarness(womenCalendarEnabled: false));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('wellmate-nav-3')), findsOneWidget);
    expect(find.bySemanticsLabel('سلامت'), findsOneWidget);
    expect(find.bySemanticsLabel('تقویم بانوان'), findsNothing);
    expect(find.byKey(const ValueKey('wellmate-nav-4')), findsNothing);
    expect(find.byKey(const ValueKey('wellmate-nav-5')), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pumpWidget(_navHarness(womenCalendarEnabled: true));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('wellmate-nav-3')), findsOneWidget);
    expect(find.bySemanticsLabel('سلامت'), findsOneWidget);
    expect(find.bySemanticsLabel('تقویم بانوان'), findsOneWidget);
    expect(find.byKey(const ValueKey('wellmate-nav-4')), findsOneWidget);
    expect(find.byKey(const ValueKey('wellmate-nav-5')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Widget _navHarness({required bool womenCalendarEnabled}) {
  return ChangeNotifierProvider(
    create: (_) => LocaleProvider(),
    child: MaterialApp(
      key: ValueKey<bool>(womenCalendarEnabled),
      locale: const Locale('fa'),
      supportedLocales: const [Locale('fa'), Locale('en')],
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: Scaffold(
        bottomNavigationBar: WellMateBottomNav(
          currentIndex: 5,
          womenCalendarEnabled: womenCalendarEnabled,
          onTap: (_) {},
        ),
      ),
    ),
  );
}
