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
  });

  final Widget child;
  final LifeMateAccountOnboardingApi? api;
  final LifeMateLegalPrivacyApi? legalPrivacyApi;
  final LifeMateDemographicsApi? demographicsApi;

  @override
  Widget build(BuildContext context) {
    return LifeMateDemographicOnboardingGate(
      onboardingApi: api,
      demographicsApi: demographicsApi,
      child: account.LifeMateAccountOnboardingGate(
        api: api,
        child: LifeMateLegalRegistrationGate(
          api: legalPrivacyApi,
          child: child,
        ),
      ),
    );
  }
}