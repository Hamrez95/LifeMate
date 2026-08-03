import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate_client/lifemate_client.dart';
import 'package:provider/provider.dart';
import 'package:wellmate/screens/treatments/add_treatment_screen.dart';

void main() {
  testWidgets(
    'schedule tab keeps times and timezone usable on a small large-text screen',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        Provider<LifeMateApiClient>.value(
          value: _ProfileTimeZoneApiClient(),
          child: MaterialApp(
            home: Builder(
              builder: (context) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: const TextScaler.linear(1.5),
                ),
                child: Scaffold(
                  body: TabbedAddTreatmentScreen(onCreated: () {}),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        tester.takeException(),
        isNull,
        reason: 'The medicine tab overflowed before opening the schedule tab.',
      );

      await tester.tap(find.text('برنامه'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('add-treatment-time')), findsOneWidget);
      expect(find.text('منطقه زمانی'), findsOneWidget);
      expect(find.text('Europe/Berlin'), findsOneWidget);

      final layoutException = tester.takeException();
      if (layoutException != null) {
        debugDumpRenderTree();
        fail('The schedule tab overflowed after navigation: $layoutException');
      }
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
        'user': {
          'id': 'patient-1',
          'email': 'patient@example.com',
        },
        'profile': {
          'displayName': 'بیمار تست',
          'locale': 'fa',
          'timeZone': 'Europe/Berlin',
        },
      };
}
