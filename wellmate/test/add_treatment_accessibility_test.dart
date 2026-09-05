import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate_client/lifemate_client.dart';
import 'package:provider/provider.dart';
import 'package:wellmate/screens/treatments/add_treatment_screen.dart';

void main() {
  testWidgets(
    'single-page treatment form scrolls while its primary action stays reachable',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        Provider<LifeMateApiClient>.value(
          value: _ProfileTimeZoneApiClient(),
          child: MaterialApp(
            locale: const Locale('fa'),
            home: Builder(
              builder: (context) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: const TextScaler.linear(1.45)),
                child: Directionality(
                  textDirection: TextDirection.rtl,
                  child: Scaffold(
                    body: TabbedAddTreatmentScreen(onCreated: () {}),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final form = find.byKey(
        const ValueKey('wellmate-treatment-single-page-form'),
      );
      expect(form, findsOneWidget);
      expect(find.text('افزودن درمان'), findsOneWidget);
      expect(tester.takeException(), isNull);

      final scrollable = find.descendant(
        of: form,
        matching: find.byType(Scrollable),
        skipOffstage: false,
      );
      final addTime = find.byKey(
        const Key('add-treatment-time'),
        skipOffstage: false,
      );
      await tester.scrollUntilVisible(
        addTime,
        240,
        scrollable: scrollable.first,
      );
      expect(addTime, findsOneWidget);
      expect(find.text('منطقه زمانی', skipOffstage: false), findsOneWidget);
      expect(find.text('Europe/Berlin', skipOffstage: false), findsOneWidget);

      final submit = find.byKey(
        const Key('submit-treatment'),
        skipOffstage: false,
      );
      expect(submit, findsOneWidget);
      expect(tester.getRect(submit).bottom, lessThanOrEqualTo(640));
      expect(tester.takeException(), isNull);
    },
  );
}

class _ProfileTimeZoneApiClient extends LifeMateApiClient {
  _ProfileTimeZoneApiClient()
    : super(
        baseUri: Uri.parse('https://example.invalid'),
        accessToken: () => 'test-token',
      );

  @override
  Future<Map<String, dynamic>> getCurrentUser() async => {
    'user': {'id': 'patient-1', 'email': 'patient@example.com'},
    'profile': {
      'displayName': 'بیمار تست',
      'locale': 'fa',
      'timeZone': 'Europe/Berlin',
    },
  };
}
