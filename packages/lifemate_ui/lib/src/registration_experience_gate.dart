import 'package:flutter/widgets.dart';
import 'package:lifemate_client/lifemate_client.dart';

import 'demographics_experience.dart';
import 'shared_account_onboarding.dart' as account;
import 'shared_legal_privacy.dart';

/// Backward-compatible registration gate used by both WellMate and CareMate.
///
/// New registrations answer the canonical demographic step before the existing
/// account onboarding. Already-completed accounts are never blocked: the
/// demographic gate detects completed onboarding and passes through, leaving
/// NotCollected available for progressive profile completion.
class LifeMateAccountOnboardingGate extends StatelessWidget {
  const LifeMateAccountOnboardingGate({
    super.key,
    required this.child,
    this.api,
    this.legalPrivacyApi,
    this.demographicsApi,
    this.enableDemographics = true,
  });

  final Widget child;
  final LifeMateAccountOnboardingApi? api;
  final LifeMateLegalPrivacyApi? legalPrivacyApi;
  final LifeMateDemographicsApi? demographicsApi;
  /// Lets focused hosts test the canonical account/legal flow independently.
  /// Product entry points keep this enabled and always collect demographics.
  final bool enableDemographics;

  @override
  Widget build(BuildContext context) {
    final accountAndLegal = account.LifeMateAccountOnboardingGate(
      api: api,
      child: LifeMateLegalRegistrationGate(
        api: legalPrivacyApi,
        child: child,
      ),
    );
    if (!enableDemographics) return accountAndLegal;
    return LifeMateDemographicOnboardingGate(
      onboardingApi: api,
      demographicsApi: demographicsApi,
      child: accountAndLegal,
    );
  }
}
