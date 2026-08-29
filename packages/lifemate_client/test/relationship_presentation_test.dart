import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate_client/lifemate_client.dart';

void main() {
  test('partner aliases normalize to one versioned policy', () {
    final spouse = LifeMateRelationshipPresentationPolicy.fromRaw('spouse');
    final partner = LifeMateRelationshipPresentationPolicy.fromRaw('partner');

    expect(spouse.kind, LifeMateRelationshipPresentationKind.partner);
    expect(partner.storageValue, 'partner');
    expect(
      partner.copyVersion,
      LifeMateRelationshipPresentationPolicy.copyVersionCurrent,
    );
  });

  test('parent-care prioritizes treatment while partner prioritizes companion', () {
    final partner = LifeMateRelationshipPresentationPolicy.fromRaw('partner');
    final parentCare = LifeMateRelationshipPresentationPolicy.fromRaw(
      'child_caring_for_parent',
    );

    expect(
      partner.surfaceRank('companion'),
      lessThan(partner.surfaceRank('treatment_alerts')),
    );
    expect(
      parentCare.surfaceRank('treatment_alerts'),
      lessThan(parentCare.surfaceRank('companion')),
    );
  });

  test('unknown relationships use a neutral safe fallback', () {
    final policy = LifeMateRelationshipPresentationPolicy.fromRaw('legacy-role');

    expect(policy.kind, LifeMateRelationshipPresentationKind.unknown);
    expect(policy.relationshipLabel(isPersian: false), 'Care relationship');
    expect(
      policy.reminderTitle(
        personName: 'Sara',
        kindLabel: 'medication',
        isPersian: false,
      ),
      'Sara • medication reminder',
    );
  });

  test('caregiver and owner labels describe the same relationship from each side', () {
    final parentCare = LifeMateRelationshipPresentationPolicy.fromRaw(
      'child_caring_for_parent',
    );

    expect(
      parentCare.relationshipLabel(isPersian: true),
      'مراقبت از والد',
    );
    expect(
      parentCare.ownerRelationshipLabel(isPersian: true),
      'فرزندم از من مراقبت می‌کند',
    );
    expect(
      parentCare.ownerRelationshipLabel(isPersian: false),
      'My child cares for me',
    );
  });

  test('copy snapshots differ by relationship and locale', () {
    final partner = LifeMateRelationshipPresentationPolicy.fromRaw('partner');
    final parentCare = LifeMateRelationshipPresentationPolicy.fromRaw(
      'child_caring_for_parent',
    );

    expect(
      partner.companionHeading(personName: 'سارا', isPersian: true),
      'همراهی برای سارا',
    );
    expect(
      parentCare.companionHeading(personName: 'Mum', isPersian: false),
      'Care for Mum',
    );
    expect(
      partner.dailySummaryTitle(personName: 'Sara', isPersian: false),
      '☀️ Today with Sara',
    );
    expect(
      parentCare.dailySummaryTitle(personName: 'Mum', isPersian: false),
      '☀️ Today’s care for Mum',
    );
  });

  test('display alias resolves before official name without changing identity', () {
    expect(
      resolveRelationshipDisplayName(
        presentationName: 'مامان جون',
        officialName: 'Maryam Ahmadi',
        isPersian: true,
      ),
      'مامان جون',
    );
    expect(
      resolveRelationshipDisplayName(
        presentationName: ' ',
        officialName: 'Maryam Ahmadi',
        isPersian: true,
      ),
      'Maryam Ahmadi',
    );
    expect(
      resolveRelationshipDisplayName(
        presentationName: null,
        officialName: null,
        isPersian: false,
      ),
      'Person under care',
    );
  });

  test('presentation policy exposes copy and priority, never permission grants', () {
    final policy = LifeMateRelationshipPresentationPolicy.fromRaw('partner');

    expect(policy.storageValue, 'partner');
    expect(policy.surfacePriority, isNotEmpty);
    expect(
      policy.toString().toLowerCase(),
      isNot(contains('permission')),
    );
  });
}
