import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate_client/lifemate_client.dart';
import 'package:lifemate_ui/lifemate_ui.dart';

class _FakeFeedbackApi extends LifeMateFeedbackApi {
  _FakeFeedbackApi()
      : super(
          baseUri: Uri.parse('https://example.invalid'),
          accessToken: () => 'test-token',
        );

  LifeMateFeedbackSubmission? lastSubmission;

  @override
  Future<Map<String, dynamic>> submit(
    LifeMateFeedbackSubmission submission,
  ) async {
    lastSubmission = submission;
    return {'itemId': 'feedback-1'};
  }
}

void main() {
  testWidgets('feedback screen does not preselect NPS or advocacy consent', (
    tester,
  ) async {
    final api = _FakeFeedbackApi();
    addTearDown(api.close);

    await tester.pumpWidget(
      MaterialApp(
        home: LifeMateFeedbackScreen(
          api: api,
          productCode: 'wellmate',
          appVersion: '0.9.0-internal.9+20',
          buildNumber: '20',
          accent: Colors.green,
          background: Colors.white,
          isPersian: false,
        ),
      ),
    );

    expect(find.text('Feedback'), findsWidgets);
    expect(find.byKey(const ValueKey('feedback-nps-10')), findsNothing);

    await tester.tap(find.text('Advocacy'));
    await tester.pump();

    final checkbox = tester.widget<CheckboxListTile>(
      find.byType(CheckboxListTile),
    );
    expect(checkbox.value, isFalse);
  });

  testWidgets('NPS submission sends explicit score and app context', (
    tester,
  ) async {
    final api = _FakeFeedbackApi();
    addTearDown(api.close);

    await tester.pumpWidget(
      MaterialApp(
        home: LifeMateFeedbackScreen(
          api: api,
          productCode: 'caremate',
          appVersion: '0.9.0-internal.9+20',
          buildNumber: '20',
          accent: Colors.blue,
          background: Colors.white,
          isPersian: false,
        ),
      ),
    );

    await tester.tap(find.text('NPS'));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('feedback-nps-8')));
    await tester.tap(find.byKey(const ValueKey('feedback-submit')));
    await tester.pumpAndSettle();

    expect(api.lastSubmission?.kind, LifeMateFeedbackKind.nps);
    expect(api.lastSubmission?.npsScore, 8);
    expect(api.lastSubmission?.productCode, 'caremate');
    expect(api.lastSubmission?.buildNumber, '20');
    expect(find.textContaining('Thanks for helping'), findsOneWidget);
  });
}
