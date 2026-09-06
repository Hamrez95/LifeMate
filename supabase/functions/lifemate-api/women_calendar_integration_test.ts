import { assert, assertEquals, assertRejects } from "jsr:@std/assert@1.0.14";
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
    const recentDailyLogDate = new Date(Date.now() - 24 * 60 * 60 * 1000)
      .toISOString()
      .slice(0, 10);
    const patientAuth = auth(
      `women-patient-${suffix}`,
      `wp-${suffix}@example.test`,
    );
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

      const correctedEpisode = await women.updateOwnerEpisode(
        patient.appUserId,
        episode.id,
        {
          version: episode.version,
          startedOn: "2026-08-02",
          endedOn: "2026-08-06",
          privateNotes: "corrected owner-only note",
        },
      );
      assertEquals(correctedEpisode.startedOn, "2026-08-02");
      assertEquals(correctedEpisode.endedOn, "2026-08-06");
      assertEquals(
        correctedEpisode.privateNotes,
        "corrected owner-only note",
      );
      const ownerEpisodes = await women.listOwnerEpisodes(patient.appUserId);
      assertEquals(ownerEpisodes.length, 1);
      assertEquals(ownerEpisodes[0].privateNotes, "corrected owner-only note");
      const leakedEpisodeAudit = await admin`
        select count(*)::int as count
        from lifemate.audit_logs as logs
        where actor_user_id = ${patient.appUserId}
          and to_jsonb(logs)::text ilike ${"%corrected owner-only note%"}
      `;
      assertEquals(leakedEpisodeAudit[0].count, 0);

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

      const privateDailyLog = await women.upsertOwnerDailyLog(
        patient.appUserId,
        {
          version: 0,
          loggedOn: recentDailyLogDate,
          mood: "low",
          energyLevel: 2,
          painLevel: 3,
          symptoms: ["cramps", "fatigue"],
          privateNotes: "daily note that must remain owner only",
          shareSummaryWithCompanion: false,
        },
      );
      assertEquals(privateDailyLog.version, 1);
      assertEquals(privateDailyLog.shareSummaryWithCompanion, false);
      assertEquals(
        privateDailyLog.privateNotes,
        "daily note that must remain owner only",
      );

      const privateReplay = await women.upsertOwnerDailyLog(
        patient.appUserId,
        {
          version: privateReplay.version,
          loggedOn: recentDailyLogDate,
          mood: "low",
          energyLevel: 2,
          painLevel: 2,
          symptoms: ["cramps"],
          privateNotes: "offline owner replay stays private",
        },
      );
      assertEquals(privateReplay.version, 2);
      assertEquals(privateReplay.mood, "low");
      assertEquals(privateReplay.energyLevel, 2);
      assertEquals(privateReplay.shareSummaryWithCompanion, false);

      const ownerDailyLogs = await women.listOwnerDailyLogs(
        patient.appUserId,
        recentDailyLogDate,
        recentDailyLogDate,
      );
      assertEquals(ownerDailyLogs.length, 1);
      assertEquals(
        ownerDailyLogs[0].privateNotes,
        "daily note that must remain owner only",
      );

      await assertApiError(
        () =>
          women.upsertOwnerDailyLog(patient.appUserId, {
            version: 0,
            loggedOn: recentDailyLogDate,
            mood: "good",
            energyLevel: 3,
            painLevel: 1,
            symptoms: ["no_symptom"],
            privateNotes: null,
            shareSummaryWithCompanion: false,
          }),
        409,
        "stale_women_calendar_daily_log",
      );

      const privateSummary = await women.getCareSummary(
        caregiver.appUserId,
        patient.appUserId,
      );
      assertEquals(privateSummary.latestSharedDailyLog, null);

      const sharedDailyLog = await women.upsertOwnerDailyLog(
        patient.appUserId,
        {
          version: privateDailyLog.version,
          loggedOn: recentDailyLogDate,
          mood: "good",
          energyLevel: 4,
          painLevel: 1,
          symptoms: ["fatigue"],
          privateNotes: "new private text must still never be shared",
          shareSummaryWithCompanion: true,
        },
      );
      assertEquals(sharedDailyLog.version, 3);
      assertEquals(sharedDailyLog.shareSummaryWithCompanion, true);

      const sharedPreservingReplay = await women.upsertOwnerDailyLog(
        patient.appUserId,
        {
          version: sharedDailyLog.version,
          loggedOn: recentDailyLogDate,
          mood: "good",
          energyLevel: 4,
          painLevel: 1,
          symptoms: ["fatigue"],
          privateNotes: "offline replay must preserve existing share true",
        },
      );
      assertEquals(sharedPreservingReplay.version, 4);
      assertEquals(sharedPreservingReplay.shareSummaryWithCompanion, true);

      const summary = await women.getCareSummary(
        caregiver.appUserId,
        patient.appUserId,
      );
      assert(summary.estimate);
      const episodes = summary.episodes as Array<Record<string, unknown>>;
      assertEquals(episodes.length, 1);
      assertEquals("privateNotes" in episodes[0], false);
      const sharedSummary = summary.latestSharedDailyLog as Record<
        string,
        unknown
      >;
      assertEquals(sharedSummary.mood, "good");
      assertEquals(sharedSummary.energyLevel, 4);
      assertEquals(sharedSummary.painLevel, 1);
      assertEquals(sharedSummary.symptoms, ["fatigue"]);
      assertEquals("privateNotes" in sharedSummary, false);
      assertEquals("shareSummaryWithCompanion" in sharedSummary, false);

      const leakedDailyAudit = await admin`
        select count(*)::int as count
        from lifemate.audit_logs as logs
        where actor_user_id = ${patient.appUserId}
          and to_jsonb(logs)::text ilike ${"%new private text must still never be shared%"}
      `;
      assertEquals(leakedDailyAudit[0].count, 0);

      await assertApiError(
        () => women.getCareSummary(unrelated.appUserId, patient.appUserId),
        403,
        "women_calendar_access_denied",
      );

      const hydration = await women.recordCareSupportAction(
        caregiver.appUserId,
        patient.appUserId,
        { actionType: "hydration" },
      );
      assertEquals(hydration.actionType, "hydration");

      const walk = await women.recordCareSupportAction(
        caregiver.appUserId,
        patient.appUserId,
        { actionType: "walk" },
      );
      assertEquals(walk.actionType, "walk");

      const checkIn = await women.recordCareSupportAction(
        caregiver.appUserId,
        patient.appUserId,
        { actionType: "check_in" },
      );
      assertEquals(checkIn.actionType, "checkin");

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

      await women.deleteOwnerEpisode(
        patient.appUserId,
        correctedEpisode.id,
      );
      assertEquals(
        (await women.listOwnerEpisodes(patient.appUserId)).length,
        0,
      );
      const profileAfterDelete = await women.getOwnerProfile(patient.appUserId);
      assertEquals(profileAfterDelete.enabled, true);
      assertEquals(profileAfterDelete.lastPeriodStart, "2026-08-02");
    } finally {
      const authSubjects = [
        patientAuth.id,
        caregiverAuth.id,
        unrelatedAuth.id,
      ];
      try {
        await cleanupWomenCalendarRun(admin, authSubjects);
        await cleanupWomenCalendarRun(admin, authSubjects);
      } finally {
        await admin.end({ timeout: 5 });
      }
    }
  },
});

type AdminSql = ReturnType<typeof postgres>;

async function cleanupWomenCalendarRun(
  admin: AdminSql,
  authSubjects: string[],
): Promise<void> {
  const userRows = await admin`
    select id
    from lifemate.app_users
    where auth_subject in ${admin(authSubjects)}
  `;
  const userIds = userRows.map((row) => String(row.id));
  if (userIds.length === 0) return;

  await admin.begin(async (tx: any) => {
    await tx`
      delete from lifemate.women_calendar_support_actions
      where patient_user_id in ${tx(userIds)}
         or caregiver_user_id in ${tx(userIds)}
    `;
    await tx`
      delete from lifemate.women_calendar_daily_logs
      where owner_user_id in ${tx(userIds)}
    `;
    await tx`
      delete from lifemate.women_calendar_episodes
      where owner_user_id in ${tx(userIds)}
    `;
    await tx`
      delete from lifemate.women_calendar_profiles
      where owner_user_id in ${tx(userIds)}
    `;
    await tx`
      delete from lifemate.care_events
      where patient_user_id in ${tx(userIds)}
         or created_by_user_id in ${tx(userIds)}
    `;
    await tx`
      delete from lifemate.dose_adherence_events
      where actor_user_id in ${tx(userIds)}
         or occurrence_id in (
           select id
           from lifemate.dose_occurrences
           where patient_user_id in ${tx(userIds)}
         )
    `;
    await tx`
      delete from lifemate.dose_occurrences
      where patient_user_id in ${tx(userIds)}
    `;
    await tx`
      delete from lifemate.treatment_schedules
      where treatment_plan_id in (
        select id
        from lifemate.treatment_plans
        where patient_user_id in ${tx(userIds)}
      )
    `;
    await tx`
      delete from lifemate.treatment_plans
      where patient_user_id in ${tx(userIds)}
    `;
    await tx`
      delete from lifemate.medications
      where owner_user_id in ${tx(userIds)}
    `;
    await tx`
      delete from lifemate.care_relationships
      where patient_user_id in ${tx(userIds)}
         or caregiver_user_id in ${tx(userIds)}
         or revoked_by_user_id in ${tx(userIds)}
    `;
    await tx`
      delete from lifemate.care_invitations
      where inviter_user_id in ${tx(userIds)}
         or responded_by_user_id in ${tx(userIds)}
    `;
    await tx`
      delete from lifemate.privacy_consents
      where user_id in ${tx(userIds)}
    `;
    await tx`
      delete from lifemate.audit_logs
      where actor_user_id in ${tx(userIds)}
    `;
    await tx`
      delete from lifemate.user_profiles
      where user_id in ${tx(userIds)}
    `;
    await tx`
      delete from lifemate.app_users
      where id in ${tx(userIds)}
    `;
  });
}

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
