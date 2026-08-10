import 'package:caremate/widgets/care_profile_mask_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('profile mask selector exposes active and future roles', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: CareProfileMaskSelector()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('مراقبت از خانواده'), findsOneWidget);
    expect(find.text('مراقبت از همسر'), findsOneWidget);
    expect(find.text('مراقبت از فرزند'), findsOneWidget);
    expect(find.text('مراقبت از بیماران'), findsOneWidget);
    expect(find.text('مراقبت از شاگردان'), findsOneWidget);
    expect(find.text('به‌زودی'), findsNWidgets(2));
    expect(find.text('پروفایل فعال: مراقبت از خانواده'), findsOneWidget);

    await tester.tap(find.text('مراقبت از همسر'));
    await tester.pumpAndSettle();

    expect(find.text('پروفایل فعال: مراقبت از همسر'), findsOneWidget);
    expect(find.text('تقویم بانوان با اجازه'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
