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
    return Stack(
      children: [
        LifeMateSharedEditableProfileScreen(
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
        ),
        PositionedDirectional(
          end: 20,
          bottom: 20,
          child: SafeArea(
            top: false,
            child: FloatingActionButton.extended(
              key: const ValueKey('caremate-account-security'),
              heroTag: 'caremate-account-security',
              backgroundColor: AppColors.darkBlue,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.shield_outlined),
              label: Text(
                LifeMateRuntimeLocale.select(
                  fa: 'امنیت حساب',
                  en: 'Account security',
                ),
              ),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => LifeMateAccountSecurityScreen(
                    controller: lifeMateAccountSecurityControllerForApp(
                      'CareMate',
                    ),
                    accent: AppColors.primaryBlue,
                    background: AppColors.background,
                    ink: AppColors.darkBlue,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
