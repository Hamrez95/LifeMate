enum LifeMateRelationshipPresentationKind {
  partner,
  family,
  child,
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

  static const copyVersionCurrent = 'relationship-presentation-v2';

  factory LifeMateRelationshipPresentationPolicy.fromRaw(String? value) {
    final normalized = value?.trim().toLowerCase().replaceAll('-', '_') ?? '';
    return switch (normalized) {
      'partner' || 'spouse' => const LifeMateRelationshipPresentationPolicy._(
          kind: LifeMateRelationshipPresentationKind.partner,
          storageValue: 'partner',
          copyVersion: copyVersionCurrent,
        ),
      'child' || 'child_caring_for_parent' || 'child_to_parent' =>
        const LifeMateRelationshipPresentationPolicy._(
          kind: LifeMateRelationshipPresentationKind.child,
          storageValue: 'child',
          copyVersion: copyVersionCurrent,
        ),
      'family' ||
      'family_member' ||
      'parent_caring_for_dependent' ||
      'parent_to_child' ||
      'parent_to_dependent' ||
      'trusted_caregiver' ||
      'caregiver' => const LifeMateRelationshipPresentationPolicy._(
          kind: LifeMateRelationshipPresentationKind.family,
          storageValue: 'family',
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
          isPersian ? 'پارتنر' : 'Partner',
        LifeMateRelationshipPresentationKind.family =>
          isPersian ? 'خانواده' : 'Family',
        LifeMateRelationshipPresentationKind.child =>
          isPersian ? 'فرزند' : 'Child',
        LifeMateRelationshipPresentationKind.unknown =>
          isPersian ? 'رابطه مراقبتی' : 'Care relationship',
      };

  String ownerRelationshipLabel({required bool isPersian}) => switch (kind) {
        LifeMateRelationshipPresentationKind.partner =>
          isPersian ? 'پارتنر' : 'Partner',
        LifeMateRelationshipPresentationKind.family =>
          isPersian ? 'خانواده' : 'Family',
        LifeMateRelationshipPresentationKind.child =>
          isPersian ? 'فرزند' : 'Child',
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
        LifeMateRelationshipPresentationKind.family ||
        LifeMateRelationshipPresentationKind.child => const [
            'treatment_alerts',
            'care_events',
            'daily_summary',
            'contact',
            'companion',
          ],
        LifeMateRelationshipPresentationKind.unknown => const [
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
        LifeMateRelationshipPresentationKind.unknown => '$kindLabel $personName',
      };
    }
    return switch (kind) {
      LifeMateRelationshipPresentationKind.partner =>
        '$personName • gentle $kindLabel reminder',
      LifeMateRelationshipPresentationKind.family ||
      LifeMateRelationshipPresentationKind.child =>
        '$personName • upcoming $kindLabel',
      LifeMateRelationshipPresentationKind.unknown =>
        '$personName • $kindLabel reminder',
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
        LifeMateRelationshipPresentationKind.unknown =>
          '$itemLabel $personName هنوز پیگیری نشده',
      };
    }
    return switch (kind) {
      LifeMateRelationshipPresentationKind.partner =>
        '$personName has an unfinished $itemLabel',
      LifeMateRelationshipPresentationKind.family ||
      LifeMateRelationshipPresentationKind.child =>
        '$personName needs follow-up for $itemLabel',
      LifeMateRelationshipPresentationKind.unknown =>
        '$personName has an unfinished $itemLabel',
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
        LifeMateRelationshipPresentationKind.unknown => isPersian
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
        LifeMateRelationshipPresentationKind.unknown => isPersian
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
