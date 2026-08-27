import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate_client/lifemate_client.dart';

void main() {
  test('support message never exposes staff-only fields through model', () {
    final message = LifeMateSupportMessage.fromJson({
      'id': 'm1',
      'body': 'پاسخ پشتیبانی',
      'createdAtUtc': '2026-08-27T12:00:00Z',
      'senderType': 'Staff',
      'internalNote': 'must not be modeled',
    });
    expect(message.id, 'm1');
    expect(message.fromUser, isFalse);
  });
}
