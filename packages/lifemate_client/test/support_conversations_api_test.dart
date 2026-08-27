import 'package:flutter_test/flutter_test.dart';
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
}
