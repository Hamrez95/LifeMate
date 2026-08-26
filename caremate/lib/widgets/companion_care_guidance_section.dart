import 'package:flutter/material.dart';
import 'package:lifemate_client/lifemate_client.dart';
import 'package:provider/provider.dart';

import '../models/care_home_snapshot.dart';
import '../services/companion_care_engine.dart';
import 'companion_care_guidance_card.dart';

class CompanionCareGuidanceSection extends StatelessWidget {
  const CompanionCareGuidanceSection({
    super.key,
    required this.summary,
    required this.isPersian,
    required this.font,
    required this.onRevoked,
    required this.onSupportRequested,
  });

  final CareCompanionHomeSummary summary;
  final bool isPersian;
  final TextStyle font;
  final VoidCallback onRevoked;
  final VoidCallback onSupportRequested;

  @override
  Widget build(BuildContext context) {
    final relationship = summary.relationship;
    if (relationship == null) return const SizedBox.shrink();
    return CompanionCareGuidanceCard(
      summary: summary,
      isPersian: isPersian,
      font: font,
      onRevoked: onRevoked,
      onSupportRequested: onSupportRequested,
      recordImpression: (guidance) => context
          .read<WomenCompanionApi>()
          .recordGuidanceImpression(
            patientUserId: relationship.patientUserId,
            guidanceId: guidance.id,
            contentVersion: guidance.contentVersion,
            category: guidance.category,
          ),
    );
  }
}
