import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lifemate_client/lifemate_client.dart';

void main() {
  test('support message maps canonical backend fields without staff-only data', () {
    final message = LifeMateSupportMessage.fromJson({
      'messageId': 'm1',
      'body': 'پاسخ پشتیبانی',
      'createdAtUtc': '2026-08-27T12:00:00Z',
      'senderKind': 'Staff',
      'internalNote': 'must not be modeled',
    });
    expect(message.id, 'm1');
    expect(message.body, 'پاسخ پشتیبانی');
    expect(message.fromUser, isFalse);
  });

  test('support message fails closed when identity fields are missing', () {
    expect(
      () => LifeMateSupportMessage.fromJson({
        'body': 'hello',
        'createdAtUtc': '2026-08-27T12:00:00Z',
        'senderKind': 'User',
      }),
      throwsFormatException,
    );
  });

  test('current conversation maps only safe resume metadata', () async {
    final client = MockClient((request) async {
      expect(request.method, 'GET');
      expect(request.url.path, '/api/v1/support/conversations/current');
      expect(request.url.queryParameters['productCode'], 'wellmate');
      expect(request.url.queryParameters['category'], 'general');
      return http.Response(
        jsonEncode({
          'conversation': {
            'ticketId': '11111111-1111-4111-8111-111111111111',
            'status': 'Resolved',
            'productCode': 'wellmate',
            'lastActivityAtUtc': '2026-08-27T12:00:00Z',
            'internalNote': 'must not be modeled',
            'assignedStaffId': 'must-not-be-modeled',
          },
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    final api = LifeMateSupportApi(
      baseUri: Uri.parse('https://example.test'),
      accessToken: () async => 'token',
      client: client,
    );
    final conversation = await api.current(productCode: 'wellmate');
    expect(conversation?.id, '11111111-1111-4111-8111-111111111111');
    expect(conversation?.status, 'Resolved');
    expect(conversation?.productCode, 'wellmate');
  });

  test('open reuses only current product/category conversation', () async {
    final methods = <String>[];
    final paths = <String>[];
    final client = MockClient((request) async {
      methods.add(request.method);
      paths.add(request.url.path);
      if (request.method == 'GET') {
        expect(request.url.queryParameters['productCode'], 'caremate');
        expect(request.url.queryParameters['category'], 'billing_issue');
        return http.Response(
          jsonEncode({
            'conversation': {
              'ticketId': '11111111-1111-4111-8111-111111111111',
              'status': 'Open',
              'productCode': 'caremate',
              'lastActivityAtUtc': '2026-08-27T12:00:00Z',
            },
          }),
          200,
        );
      }
      expect(
        request.url.path,
        '/api/v1/support/conversations/11111111-1111-4111-8111-111111111111/messages',
      );
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      expect(body['clientMessageId'], '22222222-2222-4222-8222-222222222222');
      return http.Response(
        jsonEncode({
          'ticketId': '11111111-1111-4111-8111-111111111111',
          'messageId': '33333333-3333-4333-8333-333333333333',
          'replayed': false,
        }),
        201,
      );
    });
    final api = LifeMateSupportApi(
      baseUri: Uri.parse('https://example.test'),
      accessToken: () async => 'token',
      client: client,
    );
    final result = await api.open(
      productCode: 'caremate',
      category: 'billing_issue',
      body: 'resume this support thread',
      clientMessageId: '22222222-2222-4222-8222-222222222222',
    );
    expect(result['ticketId'], '11111111-1111-4111-8111-111111111111');
    expect(methods, ['GET', 'POST']);
    expect(paths, [
      '/api/v1/support/conversations/current',
      '/api/v1/support/conversations/11111111-1111-4111-8111-111111111111/messages',
    ]);
  });
}
