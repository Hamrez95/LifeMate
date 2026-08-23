import 'package:flutter/material.dart';

import '../../core/theme/app_style.dart';
import 'care_access_screen.dart';

/// Compatibility route for older navigation entries.
///
/// Phone-based caregiver pairing is now initiated from CareMate as an in-app
/// care request. WellMate only reviews/approves requests and keeps the existing
/// Email + QR/manual management surface. No care-pairing SMS action lives here.
class CareAccessPhoneScreen extends StatelessWidget {
  const CareAccessPhoneScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: AppColors.background,
      body: CareAccessScreen(),
    );
  }
}
