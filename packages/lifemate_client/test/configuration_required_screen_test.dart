import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate_client/lifemate_client.dart';

void main() {
  tearDown(() => LifeMateRuntimeLocale.setLanguageCode('fa'));

  testWidgets('English setup guidance renders real line breaks', (
    tester,
  ) async {
    LifeMateRuntimeLocale.setLanguageCode('en');

    await tester.pumpWidget(
      const MaterialApp(
        home: ConfigurationRequiredScreen(
          appName: 'LifeMate',
          missingValues: ['SUPABASE_URL', 'LIFEMATE_API_BASE_URL'],
        ),
      ),
    );

    expect(
      find.text(
        'The following build-time values are required:\n'
        'SUPABASE_URL, LIFEMATE_API_BASE_URL',
      ),
      findsOneWidget,
    );
    expect(find.textContaining(r'\n'), findsNothing);
  });

  testWidgets('Persian setup guidance keeps its localized line break', (
    tester,
  ) async {
    LifeMateRuntimeLocale.setLanguageCode('fa');

    await tester.pumpWidget(
      const MaterialApp(
        home: ConfigurationRequiredScreen(
          appName: 'LifeMate',
          missingValues: ['SUPABASE_URL'],
        ),
      ),
    );

    expect(
      find.text('مقادیر build-time زیر لازم‌اند:\nSUPABASE_URL'),
      findsOneWidget,
    );
  });
}
