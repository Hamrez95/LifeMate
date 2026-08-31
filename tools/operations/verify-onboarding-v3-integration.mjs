import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const read = (relativePath) => readFile(path.join(root, relativePath), 'utf8');

async function main() {
  const [wellMain, careMain, auth, account, accountApi, profile] = await Promise.all([
    read('wellmate/lib/main.dart'),
    read('caremate/lib/main.dart'),
    read('packages/lifemate_ui/lib/src/shared_auth_experience.dart'),
    read('packages/lifemate_ui/lib/src/shared_account_onboarding.dart'),
    read('packages/lifemate_client/lib/src/account_onboarding_api.dart'),
    read('supabase/functions/lifemate-api/profile.ts'),
  ]);

  for (const appMain of [wellMain, careMain]) {
    assert.ok(appMain.includes('LifeMateSharedAuthExperience'));
    assert.ok(appMain.includes('LifeMateAccountOnboardingGate'));
  }
  for (const shared of [auth, account]) {
    assert.ok(shared.includes('LifeMateOnboardingScaffold'));
    assert.ok(!shared.includes('SingleChildScrollView'));
  }
  assert.ok(auth.includes('textDirection: TextDirection.ltr'));
  assert.ok(auth.includes('LifeMateAuth.sendPhoneOtp'));
  assert.ok(auth.includes('LifeMateAuth.verifyPhoneOtp'));
  assert.ok(account.includes('presentationIntent'));
  assert.ok(account.includes('_api.complete('));
  assert.ok(account.includes('displayName'));
  assert.ok(accountApi.includes("'/api/v1/me/profile'"));
  assert.ok(accountApi.includes("'completeOnboarding': true"));
  assert.ok(accountApi.includes("'presentationIntent': intent.wireValue"));
  assert.ok(profile.includes('presentation_intent'));
  assert.ok(profile.includes('profile.onboarding_completed'));
  assert.ok(profile.includes('core.person_profiles'));
  assert.ok(profile.includes('display_name'));
  assert.ok(profile.includes('presentation metadata'));

  const [wellGate, wellApi, notifications] = await Promise.all([
    read('wellmate/lib/screens/onboarding/wellmate_first_value_gate.dart'),
    read('wellmate/lib/screens/onboarding/wellmate_first_value_api.dart'),
    read('wellmate/lib/providers/contextual_notification_provider.dart'),
  ]);
  assert.ok(wellGate.includes('TabbedAddTreatmentScreen'));
  assert.ok(wellGate.includes('getTreatmentPlans()'));
  assert.ok(wellApi.includes('/api/v1/me/profile'));
  assert.ok(wellApi.includes('wellMateFirstValueState'));
  assert.ok(!wellApi.includes("'notificationPermission':"));
  assert.ok(!wellApi.includes("'relationshipId':"));
  assert.ok(notifications.includes('requestAfterExplanation'));
  assert.ok(notifications.includes('requestNotificationsPermission'));
  assert.ok(notifications.includes('requestExactAlarmsPermission'));

  const [womenEntry, womenScreen, womenApi, womenStore] = await Promise.all([
    read('wellmate/lib/screens/women_calendar/women_health_entry_screen.dart'),
    read('wellmate/lib/screens/women_calendar/women_health_activation_v3_screen.dart'),
    read('wellmate/lib/screens/women_calendar/women_health_activation_api.dart'),
    read('supabase/functions/lifemate-api/women_calendar_v3.ts'),
  ]);
  assert.ok(womenEntry.includes('getWomenCalendarProfile'));
  assert.ok(womenEntry.includes('WomenCompanionScreen'));
  assert.ok(womenScreen.includes('showAppDatePicker'));
  assert.ok(womenScreen.includes('LifeMateOnboardingTheme.womenHealth'));
  assert.ok(womenApi.includes('/api/v1/women-calendar/profile'));
  assert.ok(womenApi.includes('cycleLengthKnown'));
  assert.ok(womenApi.includes('periodLengthKnown'));
  assert.ok(womenApi.includes('regularity'));
  assert.ok(womenStore.includes('lifemate.women_calendar_profiles'));
  for (const privateField of [
    'fertilityIntent',
    'tryingToConceive',
    'pregnancyIntent',
    'privateNotes',
    'symptoms',
    'mood',
  ]) {
    assert.ok(womenStore.includes(`"${privateField}"`));
  }
  assert.ok(womenStore.includes('women_activation_private_field_forbidden'));

  const [careGate, aggregator, invitation] = await Promise.all([
    read('caremate/lib/screens/onboarding/caremate_relationship_v3_gate.dart'),
    read('caremate/lib/services/care_home_aggregator.dart'),
    read('supabase/functions/lifemate-api/person_invitation_acceptance.ts'),
  ]);
  assert.ok(careGate.includes('LifeMateCareRelationshipInvitationApi.fromEnvironment'));
  assert.ok(careGate.includes('preview(token: normalizedToken)'));
  assert.ok(careGate.includes("preview['relationshipType']"));
  assert.ok(careGate.includes('acceptCareInvitation(token: normalizedToken)'));
  assert.ok(!careGate.includes("'relationshipType': _relationshipHint"));
  assert.ok(!careGate.includes("'relationshipHint': _relationshipHint"));
  assert.ok(careGate.includes('getCareRelationships()'));
  assert.ok(careGate.includes('getCareRecipientWomenCalendar'));
  assert.ok(careGate.includes('viewFertilityEstimate'));
  assert.ok(careGate.includes('receiveFertilityNotifications'));
  assert.ok(!careGate.includes('CareHomeAggregator'));
  assert.ok(aggregator.includes("status']?.toString().toLowerCase() == 'active'"));
  assert.ok(aggregator.includes('CareCompanionHomeSummary.locked()'));
  for (const denial of [
    'self_invitation_not_allowed',
    'invitation_not_found',
    'invitation_expired',
    'invitation_contact_mismatch',
    'invitation_not_pending',
  ]) {
    assert.ok(invitation.includes(denial));
  }

  const productFlows = [wellGate, womenScreen, careGate];
  for (const source of productFlows) {
    assert.ok(source.includes('LifeMateOnboardingScaffold'));
    assert.ok(!source.includes('class LifeMateOnboardingScaffold'));
    assert.ok(!source.includes('SingleChildScrollView'));
    assert.ok(!source.includes('SharedPreferences'));
    assert.ok(!source.includes('Hive'));
  }

  console.log('PASS: Onboarding V3 cross-product integration contract');
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
