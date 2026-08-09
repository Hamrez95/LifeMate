import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lifemate_client/lifemate_client.dart';

import '../../core/theme/app_style.dart';
import '../../core/utils/persian_date_utils.dart';

/// Visualizes the women-calendar owner together with every caregiver who has
/// active consent to view the shared women-calendar summary.
///
/// The owner always comes from the current WellMate profile. Caregiver photos
/// come from their own relationship projection, so one caregiver can never
/// replace another caregiver's avatar when multiple relationships are active.
class WomenCompanionPeopleHero extends StatelessWidget {
  const WomenCompanionPeopleHero({
    super.key,
    required this.currentProfile,
    required this.relationships,
  });

  final Map<String, dynamic> currentProfile;
  final List<Map<String, dynamic>> relationships;

  @override
  Widget build(BuildContext context) {
    final ownerName = _text(currentProfile['displayName']) ?? 'من';
    final ownerPhotoUrl = _text(currentProfile['profilePhotoUrl']);
    final ownerAvatarKey = _text(currentProfile['avatarKey']);
    final caregiverCount = relationships.length;
    final singleCaregiverName = caregiverCount == 1
        ? _text(relationships.first['caregiverDisplayName']) ?? 'همدم من'
        : null;

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [Color(0xFFF7E8FF), Color(0xFFFFEAF2), Color(0xFFFFF7EE)],
        ),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: Colors.white.withValues(alpha: 0.86)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x159D65C5),
            blurRadius: 24,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          const Row(
            children: [
              Icon(Icons.favorite_rounded, color: Color(0xFFE7598B), size: 19),
              SizedBox(width: 7),
              Expanded(
                child: Text(
                  'سلام عزیزِ من',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                ),
              ),
              Text(
                'امروز چطوری؟',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
              ),
            ],
          ),
          const SizedBox(height: 16),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Column(
                  children: [
                    LifeMateProfileAvatar(
                      key: const ValueKey('women-companion-owner-avatar'),
                      avatarKey: ownerAvatarKey,
                      photoUrl: ownerPhotoUrl,
                      radius: 34,
                    ),
                    const SizedBox(height: 6),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 100),
                      child: Text(
                        ownerName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
                Container(
                  width: 58,
                  height: 32,
                  margin: const EdgeInsets.symmetric(horizontal: 8),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Container(
                        height: 2,
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            colors: [Color(0xFFE69AC6), Color(0xFFAB8BE7)],
                          ),
                        ),
                      ),
                      const CircleAvatar(
                        radius: 14,
                        backgroundColor: Colors.white,
                        child: Icon(
                          Icons.favorite_rounded,
                          size: 15,
                          color: Color(0xFFD66AA1),
                        ),
                      ),
                    ],
                  ),
                ),
                Column(
                  children: [
                    _CaregiverAvatarStack(relationships: relationships),
                    const SizedBox(height: 6),
                    Text(
                      caregiverCount == 0
                          ? 'همدم من'
                          : caregiverCount == 1
                          ? singleCaregiverName!
                          : '${localizeDigits(context, caregiverCount)} مراقب',
                      key: const ValueKey('women-companion-caregiver-count'),
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            caregiverCount == 0
                ? 'هر زمان آماده بودی، می‌توانی یک همدم قابل اعتماد را با رضایت خودت متصل کنی.'
                : caregiverCount == 1
                ? '$singleCaregiverName فقط خلاصه‌هایی را می‌بیند که خودت برای اشتراک انتخاب کرده‌ای.'
                : '${localizeDigits(context, caregiverCount)} مراقب فقط خلاصه‌هایی را می‌بینند که خودت برای اشتراک انتخاب کرده‌ای.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              height: 1.55,
              color: Color(0xFF735C77),
              fontSize: 11.5,
            ),
          ),
        ],
      ),
    );
  }

  static String? _text(dynamic value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }
}

class _CaregiverAvatarStack extends StatelessWidget {
  const _CaregiverAvatarStack({required this.relationships});

  final List<Map<String, dynamic>> relationships;

  @override
  Widget build(BuildContext context) {
    if (relationships.isEmpty) {
      return const LifeMateProfileAvatar(
        avatarKey: 'caregiver_teal',
        radius: 34,
      );
    }

    const radius = 27.0;
    const overlapStep = 36.0;
    final visibleCount = math.min(relationships.length, 4);
    final extraCount = relationships.length - visibleCount;
    final slotCount = visibleCount + (extraCount > 0 ? 1 : 0);
    final width = radius * 2 + math.max(0, slotCount - 1) * overlapStep;

    return Semantics(
      container: true,
      label: '${relationships.length} مراقب دارای دسترسی تقویم بانوان',
      child: SizedBox(
        key: const ValueKey('women-companion-caregiver-stack'),
        width: width,
        height: radius * 2,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            for (var index = 0; index < visibleCount; index++)
              PositionedDirectional(
                start: index * overlapStep,
                top: 0,
                child: _RelationshipAvatar(
                  relationship: relationships[index],
                  radius: radius,
                ),
              ),
            if (extraCount > 0)
              PositionedDirectional(
                start: visibleCount * overlapStep,
                top: 0,
                child: Container(
                  width: radius * 2,
                  height: radius * 2,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF6ECFB),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 3),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x149D65C5),
                        blurRadius: 8,
                        offset: Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Text(
                    '+${localizeDigits(context, extraCount)}',
                    style: const TextStyle(
                      color: Color(0xFF7D5597),
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _RelationshipAvatar extends StatelessWidget {
  const _RelationshipAvatar({
    required this.relationship,
    required this.radius,
  });

  final Map<String, dynamic> relationship;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final id = relationship['id']?.toString() ??
        relationship['caregiverUserId']?.toString() ??
        relationship.hashCode.toString();
    final name = WomenCompanionPeopleHero._text(
          relationship['caregiverDisplayName'],
        ) ??
        'مراقب';
    final photoUrl = WomenCompanionPeopleHero._text(
      relationship['caregiverProfilePhotoUrl'],
    );
    final avatarKey = WomenCompanionPeopleHero._text(
      relationship['caregiverAvatarKey'],
    );

    return Semantics(
      image: true,
      label: 'تصویر پروفایل $name',
      child: Container(
        padding: const EdgeInsets.all(2),
        decoration: const BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Color(0x169D65C5),
              blurRadius: 7,
              offset: Offset(0, 3),
            ),
          ],
        ),
        child: LifeMateProfileAvatar(
          key: ValueKey('women-companion-caregiver-avatar-$id'),
          avatarKey: avatarKey == null ? 'caregiver_teal' : avatarKey,
          photoUrl: photoUrl,
          radius: radius - 2,
          showBorder: false,
        ),
      ),
    );
  }
}
