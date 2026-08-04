import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:wellmate/core/widgets/wellmate_bottom_nav.dart';
import 'package:wellmate/localization/locale_provider.dart';
import 'package:wellmate/main.dart';
import 'package:wellmate/providers/settings_provider.dart';

void main() {
  testWidgets(
    'bottom navigation stays tappable and labelled on a small large-text screen',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final settings = SettingsProvider()..updateTextScale(1.5);
      int? tappedIndex;

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => LocaleProvider()),
            ChangeNotifierProvider.value(value: settings),
          ],
          child: WellMateApp(
            home: Scaffold(
              bottomNavigationBar: WellMateBottomNav(
                currentIndex: 4,
                womenCalendarEnabled: true,
                onTap: (index) => tappedIndex = index,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      for (var index = 0; index < 5; index += 1) {
        final item = find.byKey(ValueKey<String>('wellmate-nav-$index'));
        expect(item, findsOneWidget);
        expect(tester.getSize(item).height, greaterThanOrEqualTo(48));
      }
      expect(find.bySemanticsLabel('تقویم'), findsOneWidget);
      expect(find.bySemanticsLabel('افزودن درمان'), findsOneWidget);
      expect(find.bySemanticsLabel('تقویم بانوان'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey<String>('wellmate-nav-0')));
      await tester.pump();

      expect(tappedIndex, 0);
      expect(tester.takeException(), isNull);
    },
  );
}
