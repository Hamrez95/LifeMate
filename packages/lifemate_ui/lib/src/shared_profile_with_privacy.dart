import 'package:flutter/material.dart';
import 'package:lifemate_client/lifemate_client.dart';

import 'companion_care_guidance.dart';
import 'demographics_experience.dart';
import 'localization.dart';
import 'profile_theme.dart';
import 'shared_legal_privacy.dart';
import 'shared_profile_screen.dart' as legacy;

/// Backward-compatible shared profile surface with canonical privacy and
/// optional feedback entry points for LifeMate products.
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
    this.feedbackBuilder,
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
  final WidgetBuilder? feedbackBuilder;

  bool get _isCareMate => appName.trim().toLowerCase() == 'caremate';

  @override
  Widget build(BuildContext context) {
    final supplementalActions = <legacy.LifeMateProfileAdditionalAction>[
      if (_isCareMate)
        legacy.LifeMateProfileAdditionalAction(
          key: const ValueKey('profile-companion-guidance'),
          icon: Icons.volunteer_activism_outlined,
          iconColor: Colors.teal,
          label: context.tr('profile.companionGuidance.label'),
          semanticLabel: context.tr('profile.companionGuidance.semantic'),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => LifeMateCompanionCareScreen(
                apiClient: apiClient,
                accent: theme.accent,
                background: theme.background,
              ),
            ),
          ),
        ),
      if (feedbackBuilder != null)
        legacy.LifeMateProfileAdditionalAction(
          key: const ValueKey('profile-feedback'),
          icon: Icons.rate_review_outlined,
          iconColor: Colors.deepOrange,
          label: context.tr('profile.feedback.label'),
          semanticLabel: context.tr('profile.feedback.semantic'),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: feedbackBuilder!),
          ),
        ),
      legacy.LifeMateProfileAdditionalAction(
        key: const ValueKey('profile-demographics'),
        icon: Icons.badge_outlined,
        iconColor: Colors.blueGrey,
        label: context.tr('profile.demographics.title'),
        semanticLabel: context.tr('profile.demographics.semantic'),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => LifeMateDemographicsEditorScreen(
              accent: theme.accent,
              background: theme.background,
            ),
          ),
        ),
      ),
      legacy.LifeMateProfileAdditionalAction(
        key: const ValueKey('profile-privacy-preferences'),
        icon: Icons.privacy_tip_outlined,
        iconColor: Colors.indigo,
        label: context.tr('profile.privacy.label'),
        semanticLabel: context.tr('profile.privacy.semantic'),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => LifeMatePrivacyPreferencesScreen(
              api: legalPrivacyApi,
              accent: theme.accent,
              background: theme.background,
            ),
          ),
        ),
      ),
    ];

    return legacy.LifeMateSharedProfileScreen(
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
      additionalActions: supplementalActions,
    );
  }
}
