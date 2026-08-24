import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wellmate/screens/profile/incoming_care_request_card.dart';

void main() {
  testWidgets('incoming care request is touch-friendly on a small large-text screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    var accepted = 0;
    var rejected = 0;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('fa'),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: const TextScaler.linear(1.5),
          ),
          child: child!,
        ),
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(12),
            child: IncomingCareRequestCard(
              request: const {'requesterDisplayName': 'همسر من'},
              loading: false,
              onAccept: () => accepted += 1,
              onReject: () => rejected += 1,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final accept = find.byKey(const Key('incoming-care-request-accept'));
    final reject = find.byKey(const Key('incoming-care-request-reject'));
    expect(accept, findsOneWidget);
    expect(reject, findsOneWidget);
    expect(tester.getSize(accept).height, greaterThanOrEqualTo(48));
    expect(tester.getSize(reject).height, greaterThanOrEqualTo(48));
    expect(find.text('همسر من'), findsOneWidget);

    await tester.tap(reject);
    await tester.tap(accept);
    await tester.pump();
    expect(rejected, 1);
    expect(accepted, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('loading disables both care-request decisions', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: IncomingCareRequestCard(
            request: const {},
            loading: true,
            onAccept: () {},
            onReject: () {},
          ),
        ),
      ),
    );
    await tester.pump();

    final accept = tester.widget<FilledButton>(
      find.byKey(const Key('incoming-care-request-accept')),
    );
    final reject = tester.widget<OutlinedButton>(
      find.byKey(const Key('incoming-care-request-reject')),
    );
    expect(accept.onPressed, isNull);
    expect(reject.onPressed, isNull);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
