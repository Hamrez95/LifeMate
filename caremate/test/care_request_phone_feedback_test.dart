import 'package:caremate/widgets/care_request_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('successful phone request keeps an awaiting-approval state visible', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    String? submittedPhone;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('fa'),
        home: Scaffold(
          body: SingleChildScrollView(
            child: CareRequestCard(
              loading: false,
              pendingRequests: const [],
              onRequest: () {},
              onCancel: (_) {},
              phoneRequestSubmit: (phone) async {
                submittedPhone = phone;
              },
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('request-care-by-phone')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('phone-care-request-input')),
      '09121234567',
    );
    await tester.pump();
    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    await tester.tap(find.byKey(const Key('phone-care-request-submit')));
    await tester.pumpAndSettle();

    expect(submittedPhone, '09121234567');
    expect(find.byKey(const Key('phone-care-request-success')), findsOneWidget);
    expect(find.textContaining('دسترسی هنوز فعال نشده'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
