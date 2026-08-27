import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate_client/lifemate_client.dart';
import 'package:lifemate_ui/lifemate_ui.dart';

class _EmptySupportApi extends LifeMateSupportApi {
  _EmptySupportApi()
      : super(
          baseUri: Uri.parse('https://example.invalid'),
          accessToken: () async => 'test-token',
        );

  @override
  Future<LifeMateSupportConversation?> current({
    String? productCode,
    String category = 'general',
  }) async => null;
}

class _ExistingSupportApi extends LifeMateSupportApi {
  _ExistingSupportApi()
      : super(
          baseUri: Uri.parse('https://example.invalid'),
          accessToken: () async => 'test-token',
        );

  @override
  Future<LifeMateSupportConversation?> current({
    String? productCode,
    String category = 'general',
  }) async => LifeMateSupportConversation(
        id: '11111111-1111-4111-8111-111111111111',
        status: 'Resolved',
        productCode: productCode,
        lastActivityAtUtc: DateTime.utc(2026, 8, 27, 12),
      );

  @override
  Future<List<LifeMateSupportMessage>> messages(
    String conversationId, {
    String? afterAt,
    int limit = 50,
  }) async => [
        LifeMateSupportMessage(
          id: '22222222-2222-4222-8222-222222222222',
          body: 'Previous support reply',
          createdAtUtc: DateTime.utc(2026, 8, 27, 12),
          fromUser: false,
        ),
      ];

  @override
  Future<void> markRead(String conversationId, String messageId) async {}
}

void main() {
  testWidgets('support chat starts privacy-safe and accessible', (tester) async {
    final api = _EmptySupportApi();
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
    await tester.pumpAndSettle();

    expect(find.text('Online support'), findsOneWidget);
    expect(find.text('How can we help?'), findsOneWidget);
    expect(
      find.textContaining('Private health information is not attached automatically'),
      findsOneWidget,
    );
    expect(find.byTooltip('Attach image'), findsOneWidget);
    expect(find.bySemanticsLabel('Send message'), findsOneWidget);
  });

  testWidgets('support chat restores existing own thread on entry', (tester) async {
    final api = _ExistingSupportApi();
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
    await tester.pumpAndSettle();

    expect(find.text('Previous support reply'), findsOneWidget);
    expect(find.text('How can we help?'), findsNothing);
    expect(find.byTooltip('Refresh'), findsOneWidget);
  });
}
