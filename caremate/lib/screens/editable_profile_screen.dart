import 'package:flutter/material.dart';
import 'package:lifemate_client/lifemate_client.dart';
import 'package:lifemate_ui/lifemate_ui.dart';
import 'package:provider/provider.dart';

import '../core/constants/app_colors.dart';

class CareMateEditableProfileScreen extends StatelessWidget {
  const CareMateEditableProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isPersian = Localizations.localeOf(context).languageCode == 'fa';
    return LifeMateSharedEditableProfileScreen(
      apiClient: context.read<LifeMateApiClient>(),
      theme: const LifeMateProfileThemeData(
        background: AppColors.background,
        accent: AppColors.primaryBlue,
        titleColor: AppColors.darkBlue,
        secondaryText: AppColors.secondaryText,
        cardBackground: AppColors.cardBackground,
      ),
      fontFamily: isPersian ? 'Vazir' : 'Poppins',
      keyPrefix: 'care-profile',
    );
  }
}
