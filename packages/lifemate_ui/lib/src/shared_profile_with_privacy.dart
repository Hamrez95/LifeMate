import 'package:flutter/material.dart';
import 'package:lifemate_client/lifemate_client.dart';

import 'companion_care_guidance.dart';
import 'demographics_experience.dart';
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
                Semantics(
                  button: true,
                  label: LifeMateRuntimeLocale.select(
                    fa: 'پیشنهادهای همراهی CareMate',
                    en: 'CareMate support guidance',
                  ),
                  child: OutlinedButton.icon(
                    key: const ValueKey('profile-companion-guidance'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                      foregroundColor: theme.accent,
                      side: BorderSide(
                        color: theme.accent.withValues(alpha: 0.25),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
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
                    icon: const Icon(Icons.volunteer_activism_outlined),
                    label: Text(
                      LifeMateRuntimeLocale.select(
                        fa: 'همراهی پیشنهادی',
                        en: 'Support guidance',
                      ),
                      style: TextStyle(
                        fontFamily: fontFamily,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
              ],
              if (feedbackBuilder != null) ...[
                Semantics(
                  button: true,
                  label: LifeMateRuntimeLocale.select(
                    fa: 'ارسال نظر و پیشنهاد',
                    en: 'Send feedback',
                  ),
                  child: OutlinedButton.icon(
                    key: const ValueKey('profile-feedback'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                      foregroundColor: theme.accent,
                      side: BorderSide(
                        color: theme.accent.withValues(alpha: 0.25),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(builder: feedbackBuilder!),
                    ),
                    icon: const Icon(Icons.rate_review_outlined),
                    label: Text(
                      LifeMateRuntimeLocale.select(
                        fa: 'نظر، پیشنهاد و گزارش مشکل',
                        en: 'Feedback & suggestions',
                      ),
                      style: TextStyle(
                        fontFamily: fontFamily,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
              ],
              Semantics(
                button: true,
                label: LifeMateRuntimeLocale.select(
                  fa: 'جنسیت و اطلاعات پایه',
                  en: 'Gender and demographics',
                ),
                child: OutlinedButton.icon(
                  key: const ValueKey('profile-demographics'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                    foregroundColor: theme.accent,
                    side: BorderSide(
                      color: theme.accent.withValues(alpha: 0.25),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => LifeMateDemographicsEditorScreen(
                        accent: theme.accent,
                        background: theme.background,
                      ),
                    ),
                  ),
                  icon: const Icon(Icons.badge_outlined),
                  label: Text(
                    LifeMateRuntimeLocale.select(
                      fa: 'جنسیت و اطلاعات پایه',
                      en: 'Gender & demographics',
                    ),
                    style: TextStyle(
                      fontFamily: fontFamily,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Semantics(
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
                    side: BorderSide(
                      color: theme.accent.withValues(alpha: 0.25),
                    ),
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
            ],
          ),
        ),
      ],
    );
  }
}