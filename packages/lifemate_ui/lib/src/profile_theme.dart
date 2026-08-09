import 'package:flutter/material.dart';

@immutable
class LifeMateProfileThemeData {
  const LifeMateProfileThemeData({
    required this.background,
    required this.accent,
    required this.titleColor,
    required this.secondaryText,
    this.cardBackground = Colors.white,
  });

  final Color background;
  final Color accent;
  final Color titleColor;
  final Color secondaryText;
  final Color cardBackground;
}

@immutable
class LifeMateProfileLabels {
  const LifeMateProfileLabels({
    required this.personalInfo,
    required this.healthProfile,
    required this.careManagement,
    required this.appSettings,
    required this.referral,
    required this.support,
    required this.logout,
    required this.subscriptionTitle,
    required this.manageSubscriptions,
    this.referralSubtitle,
    this.supportSubtitle,
  });

  final String personalInfo;
  final String healthProfile;
  final String careManagement;
  final String appSettings;
  final String referral;
  final String support;
  final String logout;
  final String subscriptionTitle;
  final String manageSubscriptions;
  final String? referralSubtitle;
  final String? supportSubtitle;
}
