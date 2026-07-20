import 'package:caremate/core/localization/locale_provider.dart';
import 'package:caremate/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('CareMate app shell builds with its root provider',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => LocaleProvider(),
        child: const CareMateApp(),
      ),
    );

    await tester.pump();

    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.byType(CareMateApp), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
