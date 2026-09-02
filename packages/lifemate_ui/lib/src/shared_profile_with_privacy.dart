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
    final actions = <Widget>[
      if (_isCareMate)
        _ProfileQuickAction(
          key: const ValueKey('profile-companion-guidance'),
          icon: Icons.volunteer_activism_outlined,
          label: context.tr('profile.companionGuidance.semantic'),
          accent: theme.accent,
          onPressed: () => Navigator.of(context).push(
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
        _ProfileQuickAction(
          key: const ValueKey('profile-feedback'),
          icon: Icons.rate_review_outlined,
          label: context.tr('profile.feedback.semantic'),
          accent: theme.accent,
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: feedbackBuilder!),
          ),
        ),
      _ProfileQuickAction(
        key: const ValueKey('profile-demographics'),
        icon: Icons.badge_outlined,
        label: context.tr('profile.demographics.semantic'),
        accent: theme.accent,
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => LifeMateDemographicsEditorScreen(
              accent: theme.accent,
              background: theme.background,
            ),
          ),
        ),
      ),
      _ProfileQuickAction(
        key: const ValueKey('profile-privacy-preferences'),
        icon: Icons.privacy_tip_outlined,
        label: context.tr('profile.privacy.semantic'),
        accent: theme.accent,
        onPressed: () => Navigator.of(context).push(
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
          minimum: const EdgeInsets.fromLTRB(24, 4, 24, 8),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: theme.cardBackground,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: theme.accent.withValues(alpha: 0.16),
              ),
            ),
            child: SizedBox(
              height: 58,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: actions
                    .map((action) => Expanded(child: action))
                    .toList(growable: false),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ProfileQuickAction extends StatelessWidget {
  const _ProfileQuickAction({
    super.key,
    required this.icon,
    required this.label,
    required this.accent,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final Color accent;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: Tooltip(
        message: label,
        child: IconButton(
          onPressed: onPressed,
          color: accent,
          iconSize: 25,
          visualDensity: VisualDensity.standard,
          icon: Icon(icon),
        ),
      ),
    );
  }
}
