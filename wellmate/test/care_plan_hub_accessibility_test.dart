import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate_client/lifemate_client.dart';
import 'package:provider/provider.dart';
import 'package:wellmate/screens/treatments/care_plan_hub_screen.dart';

void main() {
  testWidgets(
    'care-plan hub keeps treatment visit and injection forms usable on a small large-text screen',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        Provider<LifeMateApiClient>.value(
          value: _CarePlanApiClient(),
          child: MaterialApp(
            home: Builder(
              builder: (context) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: const TextScaler.linear(1.5),
                ),
                child: Scaffold(
                  body: CarePlanHubScreen(onCreated: () {}),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      for (var index = 0; index < 3; index += 1) {
        final selector =
            find.byKey(ValueKey<String>('wellmate-care-type-$index'));
        expect(selector, findsOneWidget);
        expect(tester.getSize(selector).height, greaterThanOrEqualTo(52));
      }

      expect(find.text('افزودن دارو و برنامه درمان'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(
        find.byKey(const ValueKey<String>('wellmate-care-type-1')),
      );
      await tester.pumpAndSettle();

      final appointmentForm = find.byKey(
        const ValueKey<String>('wellmate-appointment-form'),
      );
      final appointmentScroll = find.descendant(
        of: appointmentForm,
        matching: find.byType(Scrollable),
      );
      expect(appointmentForm, findsOneWidget);
      expect(find.text('نام پزشک'), findsOneWidget);

      final address = find.descendant(
        of: appointmentForm,
        matching: find.text('آدرس کامل', skipOffstage: false),
      );
      await tester.scrollUntilVisible(
        address,
        260,
        scrollable: appointmentScroll,
      );
      expect(address, findsOneWidget);

      final timeZone = find.byKey(
        const ValueKey<String>('care-event-timezone'),
        skipOffstage: false,
      );
      await tester.scrollUntilVisible(
        timeZone,
        260,
        scrollable: appointmentScroll,
      );
      expect(
        find.byKey(
          const ValueKey<String>('care-event-date'),
          skipOffstage: false,
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(
          const ValueKey<String>('care-event-time'),
          skipOffstage: false,
        ),
        findsOneWidget,
      );
      expect(timeZone, findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(
        find.byKey(const ValueKey<String>('wellmate-care-type-2')),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey<String>('wellmate-injection-form')),
        findsOneWidget,
      );
      expect(find.text('دوز یا مقدار تزریق'), findsOneWidget);
      expect(find.text('روش تزریق'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}

class _CarePlanApiClient extends LifeMateApiClient {
  _CarePlanApiClient()
      : super(
          baseUri: Uri.parse('https://example.invalid'),
          accessToken: () => 'test-token',
        );

  @override
  Future<Map<String, dynamic>> getCurrentUser() async => {
        'user': {'id': 'patient-1'},
        'profile': {
          'displayName': 'بیمار تست',
          'locale': 'fa',
          'timeZone': 'Europe/Berlin',
        },
      };
}
