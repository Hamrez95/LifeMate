import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate_client/lifemate_client.dart';

void main() {
  test('NotCollected remains a backward-compatible non-answer', () {
    final value = LifeMateDemographics.fromJson(const {
      'gender_identity': 'NotCollected',
      'gender_self_description': null,
      'sex_assigned_at_birth': 'NotCollected',
      'demographics_updated_at_utc': null,
    });

    expect(value.genderIdentity, LifeMateGenderIdentity.notCollected);
    expect(value.sexAssignedAtBirth, LifeMateSexAssignedAtBirth.notCollected);
    expect(value.hasExplicitAnswer, isFalse);
  });

  test('PreferNotToSay is an explicit valid answer', () {
    final value = LifeMateDemographics.fromJson(const {
      'gender_identity': 'PreferNotToSay',
      'gender_self_description': null,
      'sex_assigned_at_birth': 'PreferNotToSay',
      'demographics_updated_at_utc': '2026-08-31T00:00:00Z',
    });

    expect(value.genderIdentity, LifeMateGenderIdentity.preferNotToSay);
    expect(
      value.sexAssignedAtBirth,
      LifeMateSexAssignedAtBirth.preferNotToSay,
    );
    expect(value.hasExplicitAnswer, isTrue);
  });

  test('self-described gender preserves description', () {
    final value = LifeMateDemographics.fromJson(const {
      'gender_identity': 'SelfDescribe',
      'gender_self_description': 'My description',
      'sex_assigned_at_birth': 'Female',
      'demographics_updated_at_utc': '2026-08-31T00:00:00Z',
    });

    expect(value.genderIdentity, LifeMateGenderIdentity.selfDescribe);
    expect(value.genderSelfDescription, 'My description');
    expect(value.hasExplicitAnswer, isTrue);
  });
}
