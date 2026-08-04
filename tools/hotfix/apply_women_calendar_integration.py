from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def write(path: str, content: str) -> None:
    target = ROOT / path
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(content, encoding='utf-8')


def replace_once(path: str, old: str, new: str) -> None:
    target = ROOT / path
    text = target.read_text(encoding='utf-8')
    if old not in text:
        if new in text:
            return
        raise SystemExit(f'Expected snippet not found in {path}: {old[:140]!r}')
    target.write_text(text.replace(old, new, 1), encoding='utf-8')


write(
    'supabase/functions/lifemate-api/women_calendar_integration_test.ts',
    r'''import {
  assert,
  assertEquals,
  assertRejects,
} from "jsr:@std/assert@1.0.14";
import postgres from "postgres";
import {
  type AppIdentity,
  type AuthUser,
  createLifeMateDatabase,
} from "./database.ts";
import { ApiError } from "./validation.ts";
import { createWomenCalendarStore } from "./women_calendar.ts";

const databaseUrl = Deno.env.get("TEST_DATABASE_URL");
if (!databaseUrl) {
  throw new Error("TEST_DATABASE_URL is required for integration tests.");
}

const contactSecret = "integration-only-women-calendar-secret-32-bytes-minimum";

Deno.test({
  name: "women calendar owner consent caregiver and revoke journey is isolated",
  sanitizeOps: false,
  sanitizeResources: false,
  fn: async () => {
    const admin = postgres(databaseUrl, { max: 1, prepare: false });
    const db = createLifeMateDatabase(databaseUrl, contactSecret);
    const women = createWomenCalendarStore(databaseUrl);
    const suffix = crypto.randomUUID();
    const patientAuth = auth(`women-patient-${suffix}`, `wp-${suffix}@example.test`);
    const caregiverAuth = auth(
      `women-caregiver-${suffix}`,
      `wc-${suffix}@example.test`,
    );
    const unrelatedAuth = auth(
      `women-unrelated-${suffix}`,
      `wu-${suffix}@example.test`,
    );

    try {
      const patient = await bootstrap(db, patientAuth, "مالک تقویم");
      const caregiver = await bootstrap(db, caregiverAuth, "مراقب مجاز");
      const unrelated = await bootstrap(db, unrelatedAuth, "کاربر نامرتبط");

      const profile = await women.updateOwnerProfile(patient.appUserId, {
        version: 0,
        enabled: true,
        lastPeriodStart: "2026-08-01",
        cycleLength: 28,
        periodLength: 5,
        remindersEnabled: true,
      });
      assertEquals(profile.enabled, true);
      assertEquals(profile.version, 1);

      const episode = await women.createOwnerEpisode(patient.appUserId, {
        startedOn: "2026-08-01",
        endedOn: "2026-08-05",
        privateNotes: "owner-only secret note",
      });
      assertEquals(episode.privateNotes, "owner-only secret note");

      await assertApiError(
        () => women.getCareSummary(caregiver.appUserId, patient.appUserId),
        403,
        "women_calendar_access_denied",
      );

      const invitation = await db.createInvitation(patient, {
        contact: caregiverAuth.email,
        consentVersion: "care-patient-consent-v1",
        confirmConsent: true,
      });
      const relationship = await db.acceptInvitation(caregiver, {
        token: invitation.token,
        consentVersion: "care-caregiver-consent-v1",
        confirmConsent: true,
      });
      assertEquals(relationship.canViewWomenCalendar, false);

      await assertApiError(
        () => women.getCareSummary(caregiver.appUserId, patient.appUserId),
        403,
        "women_calendar_access_denied",
      );

      await assertApiError(
        () =>
          db.updateRelationshipPermissions(
            caregiver.appUserId,
            relationship.id,
            { canViewWomenCalendar: true },
          ),
        404,
        "relationship_not_found",
      );

      const permitted = await db.updateRelationshipPermissions(
        patient.appUserId,
        relationship.id,
        { canViewWomenCalendar: true },
      );
      assertEquals(permitted.canViewWomenCalendar, true);

      const summary = await women.getCareSummary(
        caregiver.appUserId,
        patient.appUserId,
      );
      assert(summary.estimate);
      const episodes = summary.episodes as Array<Record<string, unknown>>;
      assertEquals(episodes.length, 1);
      assertEquals("privateNotes" in episodes[0], false);

      await assertApiError(
        () => women.getCareSummary(unrelated.appUserId, patient.appUserId),
        403,
        "women_calendar_access_denied",
      );

      const support = await women.recordCareSupportAction(
        caregiver.appUserId,
        patient.appUserId,
        { actionType: "hydration" },
      );
      assertEquals(support.actionType, "hydration");

      await assertApiError(
        () =>
          women.recordCareSupportAction(
            caregiver.appUserId,
            patient.appUserId,
            { actionType: "medicine" },
          ),
        400,
        "invalid_women_calendar_support_action",
      );

      const current = await women.getOwnerProfile(patient.appUserId);
      await women.updateOwnerProfile(patient.appUserId, {
        version: current.version,
        enabled: false,
        lastPeriodStart: current.lastPeriodStart,
        cycleLength: current.cycleLength,
        periodLength: current.periodLength,
        remindersEnabled: current.remindersEnabled,
      });
      await assertApiError(
        () => women.getCareSummary(caregiver.appUserId, patient.appUserId),
        404,
        "women_calendar_not_active",
      );

      const disabled = await women.getOwnerProfile(patient.appUserId);
      await women.updateOwnerProfile(patient.appUserId, {
        version: disabled.version,
        enabled: true,
        lastPeriodStart: disabled.lastPeriodStart,
        cycleLength: disabled.cycleLength,
        periodLength: disabled.periodLength,
        remindersEnabled: disabled.remindersEnabled,
      });
      await db.revokeRelationship(patient.appUserId, relationship.id);
      await assertApiError(
        () => women.getCareSummary(caregiver.appUserId, patient.appUserId),
        403,
        "women_calendar_access_denied",
      );
    } finally {
      await admin`
        delete from lifemate.app_users
        where auth_subject in ${admin([
          patientAuth.id,
          caregiverAuth.id,
          unrelatedAuth.id,
        ])}
      `;
      await admin.end({ timeout: 5 });
    }
  },
});

function auth(id: string, email: string): AuthUser {
  return { id, email, phone: null, userMetadata: {} };
}

async function bootstrap(
  db: ReturnType<typeof createLifeMateDatabase>,
  authUser: AuthUser,
  displayName: string,
): Promise<AppIdentity> {
  const result = await db.bootstrapUser(authUser, {
    displayName,
    locale: "fa",
    timeZone: "Asia/Tehran",
  });
  const user = result.user as Record<string, unknown>;
  return { auth: authUser, appUserId: String(user.id) };
}

async function assertApiError(
  action: () => Promise<unknown>,
  status: number,
  code: string,
): Promise<void> {
  const error = await assertRejects(action, ApiError);
  assertEquals(error.status, status);
  assertEquals(error.code, code);
}
''',
)

replace_once(
    'supabase/functions/lifemate-api/deno.json',
    'profile_integration_test.ts",\n',
    'profile_integration_test.ts women_calendar_test.ts women_calendar_integration_test.ts",\n',
)
replace_once(
    'supabase/functions/lifemate-api/deno.json',
    'profile_test.ts",\n',
    'profile_test.ts women_calendar_test.ts",\n',
)
replace_once(
    'supabase/functions/lifemate-api/deno.json',
    'profile_integration_test.ts"\n',
    'profile_integration_test.ts women_calendar_integration_test.ts"\n',
)

replace_once(
    '.github/workflows/edge-api.yml',
    "-eq 4",
    "-eq 5",
)
replace_once(
    '.github/workflows/edge-api.yml',
    '''            supabase/migrations/20260804003000_add_user_profile_version.sql\n''',
    '''            supabase/migrations/20260804003000_add_user_profile_version.sql \\\n            supabase/migrations/20260804130000_add_women_calendar_pilot.sql\n''',
)
replace_once(
    '.github/workflows/edge-api.yml',
    "          grep -q 'user_profiles_version_positive' ../../migrations/20260804003000_add_user_profile_version.sql\n",
    "          grep -q 'user_profiles_version_positive' ../../migrations/20260804003000_add_user_profile_version.sql\n          grep -q 'can_view_women_calendar boolean not null default false' ../../migrations/20260804130000_add_women_calendar_pilot.sql\n          grep -q 'privateNotes' women_calendar_integration_test.ts\n",
)

print('Women calendar integration journey and canonical CI patch applied.')
