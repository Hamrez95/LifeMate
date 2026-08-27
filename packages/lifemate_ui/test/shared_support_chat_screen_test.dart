import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate_client/lifemate_client.dart';
import 'package:lifemate_ui/lifemate_ui.dart';

void main() {
  testWidgets('support chat starts privacy-safe and accessible', (tester) async {
    final api = LifeMateSupportApi(
      baseUri: Uri.parse('https://example.invalid'),
      accessToken: () async => 'test-token',
    );
    addTearDown(api.close);

    await tester.pumpWidget(
      MaterialApp(
        home: LifeMateSupportChatScreen(
          api: api,
          productCode: 'wellmate',
          accent: Colors.green,
          background: Colors.white,
          isPersian: false,
        ),
      ),
    );

    expect(find.text('Online support'), findsOneWidget);
    expect(find.text('How can we help?'), findsOneWidget);
    expect(
      find.textContaining('Private health information is not attached automatically'),
      findsOneWidget,
    );
    expect(find.byTooltip('Attach image'), findsOneWidget);
    expect(find.bySemanticsLabel('Send message'), findsOneWidget);
  });
}
