import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('WellMate English profile labels use concise product copy', () {
    final values = jsonDecode(
      File('lib/localization/en.json').readAsStringSync(),
    ) as Map<String, dynamic>;

    expect(values['profile_personal_info'], 'Personal information');
    expect(values['profile_health_profile'], 'Health profile');
    expect(values['profile_caregivers'], 'Caregivers');
    expect(values['profile_app_settings'], 'App settings');
    expect(values['profile_referral_code'], 'Referral code');
    expect(values['profile_support'], 'Support');
    expect(values['profile_logout'], 'Sign out');

    expect(values.values, isNot(contains('Identification code')));
    expect(values.values, isNot(contains('Program settings')));
    expect(values.values, isNot(contains('health file')));
  });
}
