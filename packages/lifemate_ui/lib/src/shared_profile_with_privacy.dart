import 'package:flutter/material.dart';
import 'package:lifemate_client/lifemate_client.dart';

import 'companion_care_guidance.dart';
import 'profile_theme.dart';
import 'shared_legal_privacy.dart';
import 'shared_profile_screen.dart' as legacy;

/// Backward-compatible shared profile surface with canonical privacy and
/// optional product capabilities exposed through shared, themed entry points.
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
          child: Column(
            children: [
              if (_isCareMate) ...[
                _ProfileActionButton(
                  key: const ValueKey('profile-companion-guidance'),
                  theme: theme,
                  fontFamily: fontFamily,
                  icon: Icons.volunteer_activism_outlined,
                  label: LifeMateRuntimeLocale.select(
                    fa: 'همراهی پیشنهادی',
                    en: 'Support guidance',
                  ),
                  semanticsLabel: LifeMateRuntimeLocale.select(
                    fa: 'پیشنهادهای همراهی CareMate',
                    en: 'CareMate support guidance',
                  ),
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
                const SizedBox(height: 8),
              ],
              if (feedbackBuilder != null) ...[
                _ProfileActionButton(
                  key: const ValueKey('profile-feedback'),
                  theme: theme,
                  fontFamily: fontFamily,
                  icon: Icons.rate_review_outlined,
                  label: LifeMateRuntimeLocale.select(
                    fa: 'نظر، پیشنهاد و گزارش مشکل',
                    en: 'Feedback & suggestions',
                  ),
                  semanticsLabel: LifeMateRuntimeLocale.select(
                    fa: 'ارسال نظر و پیشنهاد',
                    en: 'Send feedback',
                  ),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: feedbackBuilder!),
                  ),
                ),
                const SizedBox(height: 8),
              ],
              _ProfileActionButton(
                key: const ValueKey('profile-privacy-preferences'),
                theme: theme,
                fontFamily: fontFamily,
                icon: Icons.privacy_tip_outlined,
                label: LifeMateRuntimeLocale.select(
                  fa: 'حریم خصوصی و ترجیحات',
                  en: 'Privacy & preferences',
                ),
                semanticsLabel: LifeMateRuntimeLocale.select(
                  fa: 'حریم خصوصی و ترجیحات ارتباطی',
                  en: 'Privacy and communication preferences',
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
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ProfileActionButton extends StatelessWidget {
  const _ProfileActionButton({
    super.key,
    required this.theme,
    required this.fontFamily,
    required this.icon,
    required this.label,
    required this.semanticsLabel,
    required this.onPressed,
  });

  final LifeMateProfileThemeData theme;
  final String fontFamily;
  final IconData icon;
  final String label;
  final String semanticsLabel;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: semanticsLabel,
    child: OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        foregroundColor: theme.accent,
        side: BorderSide(color: theme.accent.withValues(alpha: 0.25)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      onPressed: onPressed,
      icon: Icon(icon),
      label: Text(
        label,
        style: TextStyle(fontFamily: fontFamily, fontWeight: FontWeight.w800),
      ),
    ),
  );
}
