import 'package:caremate/core/localization/locale_provider.dart';
import 'package:caremate/main.dart';
import 'package:caremate/widgets/caremate_bottom_nav.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets(
    'bottom navigation stays tappable and labelled on a small large-text screen',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      int? tappedIndex;

      await tester.pumpWidget(
        ChangeNotifierProvider(
          create: (_) => LocaleProvider(),
          child: CareMateApp(
            home: Builder(
              builder: (context) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: const TextScaler.linear(1.5)),
                child: Scaffold(
                  bottomNavigationBar: CareMateBottomNav(
                    currentIndex: 4,
                    onTap: (index) => tappedIndex = index,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      for (var index = 0; index < 5; index += 1) {
        final item = find.byKey(ValueKey<String>('caremate-nav-$index'));
        expect(item, findsOneWidget);
        expect(tester.getSize(item).height, greaterThanOrEqualTo(48));
      }
      expect(find.bySemanticsLabel('تقویم'), findsOneWidget);
      expect(find.bySemanticsLabel('تغییر پروفایل'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey<String>('caremate-nav-0')));
      await tester.pump();

      expect(tappedIndex, 0);
      expect(tester.takeException(), isNull);
    },
  );
}
