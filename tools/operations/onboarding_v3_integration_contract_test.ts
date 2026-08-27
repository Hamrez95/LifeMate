import { assert, assertEquals } from "jsr:@std/assert@1.0.14";

const root = new URL("../../", import.meta.url);
const read = (path: string) => Deno.readTextFile(new URL(path, root));

Deno.test("WellMate and CareMate share V3 auth and account onboarding", async () => {
  const [wellMain, careMain, auth, account] = await Promise.all([
    read("wellmate/lib/main.dart"),
    read("caremate/lib/main.dart"),
    read("packages/lifemate_ui/lib/src/shared_auth_experience.dart"),
    read("packages/lifemate_ui/lib/src/shared_account_onboarding.dart"),
  ]);

  for (const main of [wellMain, careMain]) {
    assert(main.includes("LifeMateSharedAuthExperience"));
    assert(main.includes("LifeMateAccountOnboardingGate"));
  }
  assert(auth.includes("LifeMateOnboardingScaffold"));
  assert(account.includes("LifeMateOnboardingScaffold"));
  assert(!auth.includes("SingleChildScrollView"));
  assert(!account.includes("SingleChildScrollView"));
  assert(auth.includes("textDirection: TextDirection.ltr"));
  assert(auth.includes("LifeMateAuth.sendPhoneOtp"));
  assert(auth.includes("LifeMateAuth.verifyPhoneOtp"));
});

Deno.test("new-account display name persists canonically and intent is presentation metadata", async () => {
  const [account, profile] = await Promise.all([
    read("packages/lifemate_ui/lib/src/shared_account_onboarding.dart"),
    read("supabase/functions/lifemate-api/profile.ts"),
  ]);

  assert(account.includes("presentationIntent"));
  assert(account.includes("completeOnboarding"));
  assert(account.includes("displayName"));
  assert(profile.includes("presentation_intent"));
  assert(profile.includes("profile.onboarding_completed"));
  assert(profile.includes("core.person_profiles"));
  assert(profile.includes("display_name"));
  assert(profile.includes("presentation metadata"));
  assert(!profile.includes("presentationIntent = 'Authorized'"));
});

Deno.test("WellMate first value writes real treatment data and permission remains contextual", async () => {
  const [gate, api, notifications] = await Promise.all([
    read("wellmate/lib/screens/onboarding/wellmate_first_value_gate.dart"),
    read("wellmate/lib/screens/onboarding/wellmate_first_value_api.dart"),
    read("wellmate/lib/providers/contextual_notification_provider.dart"),
  ]);

  assert(gate.includes("TabbedAddTreatmentScreen"));
  assert(gate.includes("getTreatmentPlans()"));
  assert(api.includes("/api/v1/me/profile"));
  assert(api.includes("wellMateFirstValueState"));
  assert(!api.includes("notificationPermission"));
  assert(!api.includes("relationshipId"));
  assert(notifications.includes("requestAfterExplanation"));
  assert(notifications.includes("requestNotificationsPermission"));
  assert(notifications.includes("requestExactAlarmsPermission"));
});

Deno.test("Women Health activation drives canonical calendar profile and forbids fertility inference", async () => {
  const [entry, screen, api, store] = await Promise.all([
    read("wellmate/lib/screens/women_calendar/women_health_entry_screen.dart"),
    read("wellmate/lib/screens/women_calendar/women_health_activation_v3_screen.dart"),
    read("wellmate/lib/screens/women_calendar/women_health_activation_api.dart"),
    read("supabase/functions/lifemate-api/women_calendar_v3.ts"),
  ]);

  assert(entry.includes("getWomenCalendarProfile"));
  assert(entry.includes("WomenCompanionScreen"));
  assert(screen.includes("showAppDatePicker"));
  assert(screen.includes("LifeMateOnboardingTheme.womenHealth"));
  assert(api.includes("/api/v1/women-calendar/profile"));
  assert(api.includes("cycleLengthKnown"));
  assert(api.includes("periodLengthKnown"));
  assert(api.includes("regularity"));
  assert(store.includes("lifemate.women_calendar_profiles"));
  for (const privateField of [
    "fertilityIntent",
    "tryingToConceive",
    "pregnancyIntent",
    "privateNotes",
    "symptoms",
    "mood",
  ]) {
    assert(store.includes(`\"${privateField}\"`));
  }
  assert(store.includes("women_activation_private_field_forbidden"));
});

Deno.test("CareMate pairing grants nothing from relationship hint and accepted data is exact-scope gated", async () => {
  const [gate, aggregator, invitation] = await Promise.all([
    read("caremate/lib/screens/onboarding/caremate_relationship_v3_gate.dart"),
    read("caremate/lib/services/care_home_aggregator.dart"),
    read("supabase/functions/lifemate-api/person_invitation_acceptance.ts"),
  ]);

  assert(gate.includes("_relationshipHint"));
  assert(!gate.includes("'relationshipType': _relationshipHint"));
  assert(!gate.includes("'relationshipHint': _relationshipHint"));
  assert(gate.includes("getCareRelationships()"));
  assert(gate.includes("acceptCareInvitation"));
  assert(gate.includes("getCareRecipientWomenCalendar"));
  assert(gate.includes("viewFertilityEstimate"));
  assert(gate.includes("receiveFertilityNotifications"));
  assert(!gate.includes("CareHomeAggregator"));
  assert(aggregator.includes("status']?.toString().toLowerCase() == 'active'"));
  assert(aggregator.includes("CareCompanionHomeSummary.locked()"));
  for (const denial of [
    "self_invitation_not_allowed",
    "invitation_not_found",
    "invitation_expired",
    "invitation_contact_mismatch",
    "invitation_not_pending",
  ]) {
    assert(invitation.includes(denial));
  }
});

Deno.test("app-specific onboarding flows consume shared primitives instead of forking scaffold", async () => {
  const paths = [
    "wellmate/lib/screens/onboarding/wellmate_first_value_gate.dart",
    "wellmate/lib/screens/women_calendar/women_health_activation_v3_screen.dart",
    "caremate/lib/screens/onboarding/caremate_relationship_v3_gate.dart",
  ];
  const sources = await Promise.all(paths.map(read));
  for (const source of sources) {
    assert(source.includes("LifeMateOnboardingScaffold"));
    assert(!source.includes("class LifeMateOnboardingScaffold"));
    assert(!source.includes("SingleChildScrollView"));
    assert(!source.includes("SharedPreferences"));
    assert(!source.includes("Hive"));
  }
  assertEquals(sources.length, 3);
});
