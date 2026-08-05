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
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: const TextScaler.linear(1.5)),
                child: Scaffold(body: CarePlanHubScreen(onCreated: () {})),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      for (var index = 0; index < 3; index += 1) {
        final selector = find.byKey(
          ValueKey<String>('wellmate-care-type-$index'),
        );
        expect(selector, findsOneWidget);
        expect(tester.getSize(selector).height, greaterThanOrEqualTo(52));
      }

      expect(find.text('افزودن درمان'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(
        find.byKey(const ValueKey<String>('wellmate-care-type-1')),
      );
      await tester.pumpAndSettle();

      final appointmentForm = find.byKey(
        const ValueKey<String>('wellmate-appointment-form'),
      );
      final appointmentScroll = find
          .descendant(
            of: appointmentForm,
            matching: find.byType(Scrollable),
            skipOffstage: false,
          )
          .first;
      expect(appointmentForm, findsOneWidget);

      await _dragUntilVisible(
        tester,
        scrollable: appointmentScroll,
        target: find.text('نام پزشک', skipOffstage: false),
      );
      expect(find.text('نام پزشک', skipOffstage: false), findsOneWidget);

      await _dragUntilVisible(
        tester,
        scrollable: appointmentScroll,
        target: find.text('آدرس کامل', skipOffstage: false),
      );
      expect(find.text('آدرس کامل', skipOffstage: false), findsOneWidget);

      final timeZone = find.byKey(
        const ValueKey<String>('care-event-timezone'),
        skipOffstage: false,
      );
      await _dragUntilVisible(
        tester,
        scrollable: appointmentScroll,
        target: timeZone,
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

      final injectionForm = find.byKey(
        const ValueKey<String>('wellmate-injection-form'),
      );
      expect(injectionForm, findsOneWidget);
      final injectionScroll = find
          .descendant(
            of: injectionForm,
            matching: find.byType(Scrollable),
            skipOffstage: false,
          )
          .first;
      await _dragUntilVisible(
        tester,
        scrollable: injectionScroll,
        target: find.text('دوز یا مقدار تزریق', skipOffstage: false),
      );
      expect(find.text('دوز یا مقدار تزریق', skipOffstage: false), findsOneWidget);
      expect(find.text('روش تزریق', skipOffstage: false), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}

Future<void> _dragUntilVisible(
  WidgetTester tester, {
  required Finder scrollable,
  required Finder target,
}) async {
  for (var attempt = 0; attempt < 12 && target.evaluate().isEmpty; attempt++) {
    await tester.drag(scrollable, const Offset(0, -180));
    await tester.pumpAndSettle();
  }
  expect(target, findsOneWidget);
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
