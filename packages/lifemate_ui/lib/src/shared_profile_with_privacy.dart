import 'package:flutter/material.dart';
import 'package:lifemate_client/lifemate_client.dart';

import 'profile_theme.dart';
import 'shared_legal_privacy.dart';
import 'shared_profile_screen.dart' as legacy;

/// Backward-compatible shared profile surface with a canonical Privacy &
/// Preferences entry point for every LifeMate product.
class LifeMateSharedProfileScreen extends StatelessWidget {
  const LifeMateSharedProfileScreen({
    super.key,
    required this.apiClient,
    required this.theme,
    required this.labels,
    required this.fontFamily,
    required this.appName,
    required this.versionLabel,
    required this.fallbackUserName,
    required this.isPersian,
    required this.onNotifications,
    required this.onEditProfile,
    required this.onHealthProfile,
    required this.onCareManagement,
    required this.onAppSettings,
    required this.onReferral,
    required this.onSupport,
    required this.onManageSubscriptions,
    this.legalPrivacyApi,
  });

  final LifeMateApiClient apiClient;
  final LifeMateProfileThemeData theme;
  final LifeMateProfileLabels labels;
  final String fontFamily;
  final String appName;
  final String versionLabel;
  final String fallbackUserName;
  final bool isPersian;
  final VoidCallback onNotifications;
  final VoidCallback onEditProfile;
  final VoidCallback onHealthProfile;
  final VoidCallback onCareManagement;
  final VoidCallback onAppSettings;
  final VoidCallback onReferral;
  final VoidCallback onSupport;
  final VoidCallback onManageSubscriptions;
  final LifeMateLegalPrivacyApi? legalPrivacyApi;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: legacy.LifeMateSharedProfileScreen(
            apiClient: apiClient,
            theme: theme,
            labels: labels,
            fontFamily: fontFamily,
            appName: appName,
            versionLabel: versionLabel,
            fallbackUserName: fallbackUserName,
            isPersian: isPersian,
            onNotifications: onNotifications,
            onEditProfile: onEditProfile,
            onHealthProfile: onHealthProfile,
            onCareManagement: onCareManagement,
            onAppSettings: onAppSettings,
            onReferral: onReferral,
            onSupport: onSupport,
            onManageSubscriptions: onManageSubscriptions,
          ),
        ),
        SafeArea(
          top: false,
          minimum: const EdgeInsets.fromLTRB(24, 8, 24, 12),
          child: Semantics(
            button: true,
            label: LifeMateRuntimeLocale.select(
              fa: 'حریم خصوصی و ترجیحات ارتباطی',
              en: 'Privacy and communication preferences',
            ),
            child: OutlinedButton.icon(
              key: const ValueKey('profile-privacy-preferences'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
                foregroundColor: theme.accent,
                side: BorderSide(color: theme.accent.withValues(alpha: 0.25)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => LifeMatePrivacyPreferencesScreen(
                    api: legalPrivacyApi,
                    accent: theme.accent,
                    background: theme.background,
                  ),
                ),
              ),
              icon: const Icon(Icons.privacy_tip_outlined),
              label: Text(
                LifeMateRuntimeLocale.select(
                  fa: 'حریم خصوصی و ترجیحات',
                  en: 'Privacy & preferences',
                ),
                style: TextStyle(
                  fontFamily: fontFamily,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
