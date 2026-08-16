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
    return ColoredBox(
      color: AppColors.background,
      child: Column(
        children: [
          SafeArea(
            bottom: false,
            minimum: const EdgeInsets.fromLTRB(20, 10, 20, 6),
            child: Align(
              alignment: AlignmentDirectional.centerEnd,
              child: OutlinedButton.icon(
                key: const ValueKey('wellmate-account-security'),
                icon: const Icon(Icons.shield_outlined, size: 19),
                label: Text(
                  LifeMateRuntimeLocale.select(
                    fa: 'امنیت حساب',
                    en: 'Account security',
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.darkBlue,
                ),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => LifeMateAccountSecurityScreen(
                      controller: lifeMateAccountSecurityControllerForApp(
                        'WellMate',
                      ),
                      accent: AppColors.primary,
                      background: AppColors.background,
                      ink: AppColors.darkBlue,
                    ),
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: LifeMateSharedEditableProfileScreen(
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
            ),
          ),
        ],
      ),
    );
  }
}
