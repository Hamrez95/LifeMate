import 'package:flutter/material.dart';

import 'relationship_invite_flow_screen.dart';

/// Primary WellMate caregiver invitation route.
///
/// Relationship classification and viewer-specific nickname are collected before
/// the invitation is created. Permissions remain a separate authorization layer.
class CareAccessPhoneScreen extends StatelessWidget {
  const CareAccessPhoneScreen({super.key});

  @override
  Widget build(BuildContext context) => const RelationshipInviteFlowScreen();
}
