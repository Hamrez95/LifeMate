import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('care page preserves caregiver initiated email request flow', () {
    final source = File('lib/screens/feature_preview_screen.dart').readAsStringSync();
    expect(source, contains('createCareRequest(email: email)'));
    expect(source, contains('getOutgoingCareRequests()'));
  });

  test('care card exposes phone request alongside email without SMS semantics', () {
    final source = File('lib/widgets/care_request_card.dart').readAsStringSync();
    expect(source, contains("Key('request-care-by-phone')"));
    expect(source, contains("Key('request-care-by-email')"));
    expect(source, contains('PhoneCareRequestApi.fromEnvironment().create'));
    expect(source, contains('درخواست مراقبت با شماره تلفن'));
    expect(source, contains('نتیجه مشخص نمی‌کند'));
    expect(source.toLowerCase(), isNot(contains('kavenegar')));
    expect(source.toLowerCase(), isNot(contains('sms')));
    expect(source.toLowerCase(), isNot(contains('invite token')));
  });

  test('phone request UI does not disclose target identity from response', () {
    final source = File('lib/widgets/care_request_card.dart').readAsStringSync();
    expect(source, isNot(contains("result['targetDisplayName']")));
    expect(source, isNot(contains("result['targetAccountId']")));
    expect(source, contains('در انتظار تأیید'));
  });
}
