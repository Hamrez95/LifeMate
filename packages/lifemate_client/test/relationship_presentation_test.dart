import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate_client/lifemate_client.dart';

void main() {
  test('canonical relationship presentation values remain stable', () {
    expect(
      LifeMateRelationshipPresentationPolicy.fromRaw('partner').storageValue,
      'partner',
    );
    expect(
      LifeMateRelationshipPresentationPolicy.fromRaw('family').storageValue,
      'family',
    );
    expect(
      LifeMateRelationshipPresentationPolicy.fromRaw('child').storageValue,
      'child',
    );
    expect(
      LifeMateRelationshipPresentationPolicy.fromRaw('trusted_person').storageValue,
      'trusted_person',
    );
  });

  test('legacy relationship values normalize without breaking old data', () {
    expect(
      LifeMateRelationshipPresentationPolicy.fromRaw('spouse').storageValue,
      'partner',
    );
    expect(
      LifeMateRelationshipPresentationPolicy.fromRaw(
        'child_caring_for_parent',
      ).storageValue,
      'child',
    );
    expect(
      LifeMateRelationshipPresentationPolicy.fromRaw(
        'parent_caring_for_dependent',
      ).storageValue,
      'family',
    );
    expect(
      LifeMateRelationshipPresentationPolicy.fromRaw(
        'trusted_caregiver',
      ).storageValue,
      'trusted_person',
    );
  });

  test('partner prioritizes companion while family and child prioritize care', () {
    final partner = LifeMateRelationshipPresentationPolicy.fromRaw('partner');
    final family = LifeMateRelationshipPresentationPolicy.fromRaw('family');
    final child = LifeMateRelationshipPresentationPolicy.fromRaw('child');

    expect(
      partner.surfaceRank('companion'),
      lessThan(partner.surfaceRank('treatment_alerts')),
    );
    expect(
      family.surfaceRank('treatment_alerts'),
      lessThan(family.surfaceRank('companion')),
    );
    expect(
      child.surfaceRank('treatment_alerts'),
      lessThan(child.surfaceRank('companion')),
    );
  });

  test('Persian labels stay simple and canonical', () {
    expect(
      LifeMateRelationshipPresentationPolicy.fromRaw('partner')
          .relationshipLabel(isPersian: true),
      'پارتنر',
    );
    expect(
      LifeMateRelationshipPresentationPolicy.fromRaw('family')
          .relationshipLabel(isPersian: true),
      'خانواده',
    );
    expect(
      LifeMateRelationshipPresentationPolicy.fromRaw('child')
          .relationshipLabel(isPersian: true),
      'فرزند',
    );
  });

  test('unknown relationships use a neutral safe fallback', () {
    final policy = LifeMateRelationshipPresentationPolicy.fromRaw('legacy-role');

    expect(policy.kind, LifeMateRelationshipPresentationKind.unknown);
    expect(policy.relationshipLabel(isPersian: false), 'Care relationship');
  });

  test('viewer-specific nickname resolves before official identity', () {
    expect(
      resolveRelationshipDisplayName(
        presentationName: 'Mum',
        officialName: 'Mary Example',
        isPersian: false,
      ),
      'Mum',
    );
    expect(
      resolveRelationshipDisplayName(
        presentationName: '   ',
        officialName: 'Mary Example',
        isPersian: false,
      ),
      'Mary Example',
    );
  });

  test('presentation policy exposes no authorization or consent grant', () {
    final policy = LifeMateRelationshipPresentationPolicy.fromRaw('partner');
    final dynamic value = policy;
    expect(() => value.canViewWomenCalendar, throwsNoSuchMethodError);
    expect(() => value.permissions, throwsNoSuchMethodError);
    expect(() => value.consentScopes, throwsNoSuchMethodError);
  });
}
