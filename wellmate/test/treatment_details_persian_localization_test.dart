import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate_client/lifemate_client.dart';
import 'package:provider/provider.dart';
import 'package:wellmate/screens/treatments/treatments_screen.dart';

void main() {
  testWidgets('treatment details renders Jalali dates and Persian digits', (
    tester,
  ) async {
    await tester.pumpWidget(
      Provider<LifeMateApiClient>.value(
        value: _TreatmentApi(),
        child: const MaterialApp(
          locale: Locale('fa'),
          supportedLocales: [Locale('fa'), Locale('en')],
          localizationsDelegates: [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: TreatmentsScreen(refreshToken: 0),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('سیتریزین'), findsOneWidget);
    expect(find.textContaining('۲۱:۰۰'), findsOneWidget);
    await tester.tap(find.text('سیتریزین'));
    await tester.pumpAndSettle();

    expect(find.text('۱۰'), findsOneWidget);
    expect(find.text('۱ قرص'), findsOneWidget);
    expect(find.text('۱۴۰۵/۰۵/۱۳'), findsOneWidget);
    expect(find.text('۱۴۰۵/۰۶/۳۰'), findsOneWidget);
    expect(find.text('۲۱:۰۰'), findsWidgets);
    expect(find.text('2026-08-04'), findsNothing);
    expect(find.text('2026-09-21'), findsNothing);
  });
}

class _TreatmentApi extends LifeMateApiClient {
  _TreatmentApi()
    : super(
        baseUri: Uri.parse('https://example.invalid'),
        accessToken: () => 'test-token',
      );

  @override
  Future<List<Map<String, dynamic>>> getTreatmentPlans() async => [
    {
      'id': 'plan-1',
      'status': 'active',
      'doseText': '1 قرص',
      'instructions': 'بعدش سوار موتور نشو',
      'startDate': '2026-08-04',
      'endDate': '2026-09-21',
      'medication': {'name': 'سیتریزین', 'strengthText': '10'},
      'schedules': [
        {'dayOfWeek': 'friday', 'localTime': '21:00:00'},
        {'dayOfWeek': 'monday', 'localTime': '21:00:00'},
      ],
    },
  ];
}
