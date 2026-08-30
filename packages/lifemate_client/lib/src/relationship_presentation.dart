enum LifeMateRelationshipPresentationKind {
  partner,
  family,
  child,
  friend,
  trustedPerson,
  doctor,
  nurse,
  professionalCaregiver,
  therapistSpecialist,
  other,
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

  static const copyVersionCurrent = 'relationship-presentation-v3';

  factory LifeMateRelationshipPresentationPolicy.fromRaw(String? value) {
    final normalized = value
            ?.trim()
            .toLowerCase()
            .replaceAll('-', '_')
            .replaceAll(' ', '_') ??
        '';
    final canonical = switch (normalized) {
      'partner' || 'spouse' => ('partner', LifeMateRelationshipPresentationKind.partner),
      'child' || 'child_caring_for_parent' || 'child_to_parent' =>
        ('child', LifeMateRelationshipPresentationKind.child),
      'family' || 'family_member' || 'parent_caring_for_dependent' ||
      'parent_to_child' || 'parent_to_dependent' =>
        ('family', LifeMateRelationshipPresentationKind.family),
      'friend' => ('friend', LifeMateRelationshipPresentationKind.friend),
      'trusted_person' || 'trusted_contact' || 'trusted_caregiver' =>
        ('trusted_person', LifeMateRelationshipPresentationKind.trustedPerson),
      'doctor' || 'physician' => ('doctor', LifeMateRelationshipPresentationKind.doctor),
      'nurse' => ('nurse', LifeMateRelationshipPresentationKind.nurse),
      'professional_caregiver' || 'caregiver' || 'professional_carer' =>
        ('professional_caregiver', LifeMateRelationshipPresentationKind.professionalCaregiver),
      'therapist' || 'specialist' || 'therapist_specialist' =>
        ('therapist_specialist', LifeMateRelationshipPresentationKind.therapistSpecialist),
      'other' => ('other', LifeMateRelationshipPresentationKind.other),
      _ => ('unknown', LifeMateRelationshipPresentationKind.unknown),
    };
    return LifeMateRelationshipPresentationPolicy._(
      kind: canonical.$2,
      storageValue: canonical.$1,
      copyVersion: copyVersionCurrent,
    );
  }

  bool get isPartner => kind == LifeMateRelationshipPresentationKind.partner;

  String relationshipLabel({required bool isPersian}) => switch (kind) {
        LifeMateRelationshipPresentationKind.partner =>
          isPersian ? 'پارتنر' : 'Partner',
        LifeMateRelationshipPresentationKind.family =>
          isPersian ? 'خانواده' : 'Family',
        LifeMateRelationshipPresentationKind.child =>
          isPersian ? 'فرزند' : 'Child',
        LifeMateRelationshipPresentationKind.friend =>
          isPersian ? 'دوست' : 'Friend',
        LifeMateRelationshipPresentationKind.trustedPerson =>
          isPersian ? 'فرد مورد اعتماد' : 'Trusted person',
        LifeMateRelationshipPresentationKind.doctor =>
          isPersian ? 'پزشک' : 'Doctor',
        LifeMateRelationshipPresentationKind.nurse =>
          isPersian ? 'پرستار' : 'Nurse',
        LifeMateRelationshipPresentationKind.professionalCaregiver =>
          isPersian ? 'مراقب حرفه‌ای' : 'Professional caregiver',
        LifeMateRelationshipPresentationKind.therapistSpecialist =>
          isPersian ? 'درمانگر / متخصص' : 'Therapist / specialist',
        LifeMateRelationshipPresentationKind.other =>
          isPersian ? 'سایر' : 'Other',
        LifeMateRelationshipPresentationKind.unknown =>
          isPersian ? 'رابطه مراقبتی' : 'Care relationship',
      };

  String ownerRelationshipLabel({required bool isPersian}) =>
      relationshipLabel(isPersian: isPersian);

  List<String> get surfacePriority => switch (kind) {
        LifeMateRelationshipPresentationKind.partner => const [
            'companion',
            'shared_wellbeing',
            'treatment_alerts',
            'care_events',
            'daily_summary',
            'contact',
          ],
        _ => const [
            'treatment_alerts',
            'care_events',
            'daily_summary',
            'contact',
            'companion',
          ],
      };

  int surfaceRank(String surface) {
    final index = surfacePriority.indexOf(surface);
    return index < 0 ? 999 : index;
  }

  String reminderTitle({
    required String personName,
    required String kindLabel,
    required bool isPersian,
  }) {
    if (isPersian) {
      return switch (kind) {
        LifeMateRelationshipPresentationKind.partner =>
          '$kindLabel $personName؛ یک یادآوری آرام',
        LifeMateRelationshipPresentationKind.family ||
        LifeMateRelationshipPresentationKind.child =>
          '$kindLabel $personName نزدیک است',
        _ => '$kindLabel $personName',
      };
    }
    return switch (kind) {
      LifeMateRelationshipPresentationKind.partner =>
        '$personName • gentle $kindLabel reminder',
      LifeMateRelationshipPresentationKind.family ||
      LifeMateRelationshipPresentationKind.child =>
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
          'یک $itemLabel $personName هنوز پیگیری نشده',
        LifeMateRelationshipPresentationKind.family ||
        LifeMateRelationshipPresentationKind.child =>
          '$itemLabel $personName نیاز به پیگیری دارد',
        _ => '$itemLabel $personName هنوز پیگیری نشده',
      };
    }
    return switch (kind) {
      LifeMateRelationshipPresentationKind.partner =>
        '$personName has an unfinished $itemLabel',
      LifeMateRelationshipPresentationKind.family ||
      LifeMateRelationshipPresentationKind.child =>
        '$personName needs follow-up for $itemLabel',
      _ => '$personName has an unfinished $itemLabel',
    };
  }

  String completionTitle({
    required String personName,
    required bool isPersian,
  }) => switch (kind) {
        LifeMateRelationshipPresentationKind.partner => isPersian
            ? '💚 یک خبر خوب از $personName'
            : '💚 A reassuring update from $personName',
        LifeMateRelationshipPresentationKind.family => isPersian
            ? '💚 به‌روزرسانی مراقبت $personName'
            : '💚 Care update for $personName',
        LifeMateRelationshipPresentationKind.child => isPersian
            ? '💚 وضعیت درمان $personName'
            : '💚 $personName care update',
        _ => isPersian
            ? '💚 به‌روزرسانی مراقبت $personName'
            : '💚 Care update for $personName',
      };

  String dailySummaryTitle({
    required String personName,
    required bool isPersian,
  }) => switch (kind) {
        LifeMateRelationshipPresentationKind.partner => isPersian
            ? '☀️ امروزِ $personName'
            : '☀️ Today with $personName',
        LifeMateRelationshipPresentationKind.family ||
        LifeMateRelationshipPresentationKind.child => isPersian
            ? '☀️ خلاصه مراقبت امروز $personName'
            : '☀️ Today’s care for $personName',
        _ => isPersian
            ? '☀️ وضعیت امروز $personName'
            : '☀️ Today for $personName',
      };

  String companionHeading({
    required String personName,
    required bool isPersian,
  }) => switch (kind) {
        LifeMateRelationshipPresentationKind.partner =>
          isPersian ? 'همراهی برای $personName' : 'Support for $personName',
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
