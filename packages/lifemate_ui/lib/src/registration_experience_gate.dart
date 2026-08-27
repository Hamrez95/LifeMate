import 'package:flutter/widgets.dart';
import 'package:lifemate_client/lifemate_client.dart';

import 'shared_account_onboarding.dart' as account;
import 'shared_legal_privacy.dart';

/// Backward-compatible registration gate used by both WellMate and CareMate.
///
/// Account onboarding remains responsible only for minimal profile/presentation
/// metadata. Before the authenticated product shell becomes reachable, the
/// canonical server-backed legal registration gate independently verifies the
/// current mandatory Terms/Privacy versions. Optional privacy preferences stay
/// outside registration and are never preselected.
class LifeMateAccountOnboardingGate extends StatelessWidget {
  const LifeMateAccountOnboardingGate({
    super.key,
    required this.child,
    this.api,
    this.legalPrivacyApi,
  });

  final Widget child;
  final LifeMateAccountOnboardingApi? api;
  final LifeMateLegalPrivacyApi? legalPrivacyApi;

  @override
  Widget build(BuildContext context) {
    return account.LifeMateAccountOnboardingGate(
      api: api,
      child: LifeMateLegalRegistrationGate(
        api: legalPrivacyApi,
        child: child,
      ),
    );
  }
}
