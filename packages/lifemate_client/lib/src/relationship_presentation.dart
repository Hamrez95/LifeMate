enum LifeMateRelationshipPresentationKind {
  partner,
  childCaringForParent,
  parentCaringForDependent,
  family,
  trustedCaregiver,
  unknown,
}

class LifeMateRelationshipPresentationPolicy {
  const LifeMateRelationshipPresentationPolicy._({
    required this.kind,
    required this.storageValue,
    required this.copyVersion,
  });

  final LifeMateRelationshipPresentationKind kind;
  final String storageValue;
  final String copyVersion;

  static const copyVersionCurrent = 'relationship-presentation-v1';

  factory LifeMateRelationshipPresentationPolicy.fromRaw(String? value) {
    final normalized = value?.trim().toLowerCase().replaceAll('-', '_') ?? '';
    return switch (normalized) {
      'partner' || 'spouse' => const LifeMateRelationshipPresentationPolicy._(
          kind: LifeMateRelationshipPresentationKind.partner,
          storageValue: 'partner',
          copyVersion: copyVersionCurrent,
        ),
      'child_caring_for_parent' || 'child_to_parent' =>
        const LifeMateRelationshipPresentationPolicy._(
          kind: LifeMateRelationshipPresentationKind.childCaringForParent,
          storageValue: 'child_caring_for_parent',
          copyVersion: copyVersionCurrent,
        ),
      'parent_caring_for_dependent' || 'parent_to_child' || 'parent_to_dependent' =>
        const LifeMateRelationshipPresentationPolicy._(
          kind: LifeMateRelationshipPresentationKind.parentCaringForDependent,
          storageValue: 'parent_caring_for_dependent',
          copyVersion: copyVersionCurrent,
        ),
      'family' || 'family_member' => const LifeMateRelationshipPresentationPolicy._(
          kind: LifeMateRelationshipPresentationKind.family,
          storageValue: 'family',
          copyVersion: copyVersionCurrent,
        ),
      'trusted_caregiver' || 'caregiver' =>
        const LifeMateRelationshipPresentationPolicy._(
          kind: LifeMateRelationshipPresentationKind.trustedCaregiver,
          storageValue: 'trusted_caregiver',
          copyVersion: copyVersionCurrent,
        ),
      _ => const LifeMateRelationshipPresentationPolicy._(
          kind: LifeMateRelationshipPresentationKind.unknown,
          storageValue: 'unknown',
          copyVersion: copyVersionCurrent,
        ),
    };
  }

  bool get isPartner => kind == LifeMateRelationshipPresentationKind.partner;

  String relationshipLabel({required bool isPersian}) => switch (kind) {
        LifeMateRelationshipPresentationKind.partner =>
          isPersian ? 'همسر / شریک زندگی' : 'Partner',
        LifeMateRelationshipPresentationKind.childCaringForParent =>
          isPersian ? 'مراقبت از والد' : 'Caring for a parent',
        LifeMateRelationshipPresentationKind.parentCaringForDependent =>
          isPersian ? 'مراقبت از فرزند یا وابسته' : 'Caring for a dependent',
        LifeMateRelationshipPresentationKind.family =>
          isPersian ? 'عضو خانواده' : 'Family member',
        LifeMateRelationshipPresentationKind.trustedCaregiver =>
          isPersian ? 'مراقب مورد اعتماد' : 'Trusted caregiver',
        LifeMateRelationshipPresentationKind.unknown =>
          isPersian ? 'رابطه مراقبتی' : 'Care relationship',
      };

  List<String> get surfacePriority => switch (kind) {
        LifeMateRelationshipPresentationKind.partner => const [
            'companion',
            'shared_wellbeing',
            'treatment_alerts',
            'care_events',
            'daily_summary',
            'contact',
          ],
        LifeMateRelationshipPresentationKind.childCaringForParent => const [
            'treatment_alerts',
            'care_events',
            'daily_summary',
            'contact',
            'companion',
          ],
        LifeMateRelationshipPresentationKind.parentCaringForDependent => const [
            'treatment_alerts',
            'care_events',
            'daily_summary',
            'contact',
            'companion',
          ],
        _ => const [
            'treatment_alerts',
            'care_events',
            'daily_summary',
            'contact',
            'companion',
          ],
      };

  String reminderTitle({
    required String personName,
    required String kindLabel,
    required bool isPersian,
  }) {
    if (isPersian) {
      return switch (kind) {
        LifeMateRelationshipPresentationKind.partner =>
          '$kindLabel $personName؛ یک یادآوری آرام',
        LifeMateRelationshipPresentationKind.childCaringForParent =>
          '$kindLabel $personName نزدیک است',
        LifeMateRelationshipPresentationKind.parentCaringForDependent =>
          '$kindLabel $personName نزدیک است',
        _ => '$kindLabel $personName',
      };
    }
    return switch (kind) {
      LifeMateRelationshipPresentationKind.partner =>
        '$personName • gentle $kindLabel reminder',
      LifeMateRelationshipPresentationKind.childCaringForParent =>
        '$personName • upcoming $kindLabel',
      LifeMateRelationshipPresentationKind.parentCaringForDependent =>
        '$personName • upcoming $kindLabel',
      _ => '$personName • $kindLabel reminder',
    };
  }

  String missedTitle({
    required String personName,
    required String itemLabel,
    required bool isPersian,
  }) {
    if (isPersian) {
      return switch (kind) {
        LifeMateRelationshipPresentationKind.partner =>
          'یک $itemLabel از $personName هنوز پیگیری نشده',
        LifeMateRelationshipPresentationKind.childCaringForParent =>
          '$itemLabel $personName نیاز به پیگیری دارد',
        LifeMateRelationshipPresentationKind.parentCaringForDependent =>
          '$itemLabel $personName نیاز به پیگیری دارد',
        _ => '$itemLabel $personName هنوز پیگیری نشده',
      };
    }
    return switch (kind) {
      LifeMateRelationshipPresentationKind.partner =>
        '$personName has an unfinished $itemLabel',
      LifeMateRelationshipPresentationKind.childCaringForParent =>
        '$personName needs follow-up for $itemLabel',
      LifeMateRelationshipPresentationKind.parentCaringForDependent =>
        '$personName needs follow-up for $itemLabel',
      _ => '$personName has an unfinished $itemLabel',
    };
  }

  String companionHeading({
    required String personName,
    required bool isPersian,
  }) => switch (kind) {
        LifeMateRelationshipPresentationKind.partner =>
          isPersian ? 'همراهی برای $personName' : 'Support for $personName',
        LifeMateRelationshipPresentationKind.childCaringForParent =>
          isPersian ? 'مراقبت از $personName' : 'Care for $personName',
        LifeMateRelationshipPresentationKind.parentCaringForDependent =>
          isPersian ? 'مراقبت از $personName' : 'Care for $personName',
        _ => isPersian ? 'مراقبت از $personName' : 'Care for $personName',
      };
}

String resolveRelationshipDisplayName({
  required String? presentationName,
  required String? officialName,
  required bool isPersian,
}) {
  final alias = presentationName?.trim();
  if (alias != null && alias.isNotEmpty) return alias;
  final official = officialName?.trim();
  if (official != null && official.isNotEmpty) return official;
  return isPersian ? 'فرد تحت مراقبت' : 'Person under care';
}
