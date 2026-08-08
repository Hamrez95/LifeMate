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
      expect(appointmentForm, findsOneWidget);
      expect(find.text('افزودن ویزیت'), findsOneWidget);
      await _expectFormScrolls(tester, appointmentForm);
      expect(tester.takeException(), isNull);

      await tester.tap(
        find.byKey(const ValueKey<String>('wellmate-care-type-2')),
      );
      await tester.pumpAndSettle();

      final injectionForm = find.byKey(
        const ValueKey<String>('wellmate-injection-form'),
      );
      expect(injectionForm, findsOneWidget);
      expect(find.text('افزودن تزریق'), findsOneWidget);
      await _expectFormScrolls(tester, injectionForm);
      expect(tester.takeException(), isNull);
    },
  );
}

Future<void> _expectFormScrolls(WidgetTester tester, Finder form) async {
  final scrollable = find
      .descendant(
        of: form,
        matching: find.byType(Scrollable),
        skipOffstage: false,
      )
      .first;
  expect(scrollable, findsOneWidget);

  final state = tester.state<ScrollableState>(scrollable);
  final before = state.position.pixels;
  await tester.drag(scrollable, const Offset(0, -320));
  await tester.pumpAndSettle();
  final after = state.position.pixels;

  expect(after, greaterThan(before));
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
