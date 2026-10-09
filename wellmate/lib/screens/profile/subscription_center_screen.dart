import 'package:flutter/material.dart';
import 'package:lifemate_client/lifemate_client.dart';
import 'package:lifemate_ui/lifemate_ui.dart' as shared;
import 'package:provider/provider.dart';

import '../../core/theme/app_style.dart';

/// WellMate's standalone route delegates to the same server-driven center used
/// by the LifeMate shell, preserving the existing Period-specific entry point.
class LifeMateSubscriptionCenterScreen extends StatelessWidget {
  const LifeMateSubscriptionCenterScreen({
    super.key,
    this.focusPeriod = false,
  });

  final bool focusPeriod;

  @override
  Widget build(BuildContext context) => shared.LifeMateSubscriptionCenterScreen(
        apiClient: context.read<LifeMateApiClient>(),
        focusPeriod: focusPeriod,
        accent: AppColors.primary,
      );
}
