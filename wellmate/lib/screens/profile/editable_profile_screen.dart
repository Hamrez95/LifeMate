import 'package:flutter/material.dart';
import 'package:lifemate_client/lifemate_client.dart';
import 'package:lifemate_ui/lifemate_ui.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_style.dart';

class EditableProfileScreen extends StatelessWidget {
  const EditableProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isPersian = Localizations.localeOf(context).languageCode == 'fa';
    return LifeMateSharedEditableProfileScreen(
      apiClient: context.read<LifeMateApiClient>(),
      theme: const LifeMateProfileThemeData(
        background: AppColors.background,
        accent: AppColors.primary,
        titleColor: AppColors.darkBlue,
        secondaryText: AppColors.textSecondary,
        cardBackground: AppColors.cardBackground,
      ),
      fontFamily: isPersian ? 'Vazir' : 'Poppins',
      keyPrefix: 'profile',
    );
  }
}
