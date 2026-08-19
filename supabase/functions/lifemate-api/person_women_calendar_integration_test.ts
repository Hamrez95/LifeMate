import {
  assertEquals,
  assertNotEquals,
  assertRejects,
} from "jsr:@std/assert@1.0.14";
import postgres from "postgres";
import { closeLifeMateSqlClientsForTest } from "./database_client.ts";
import { createDataExportStore } from "./data_export.ts";
import { createWomenCalendarStore } from "./women_calendar.ts";
import { ApiError } from "./validation.ts";

const databaseUrl = Deno.env.get("TEST_DATABASE_URL");
if (!databaseUrl) {
  throw new Error(
    "TEST_DATABASE_URL is required for Person Women Calendar tests.",
  );
}

const fixtureSql = postgres(databaseUrl, {
  max: 1,
  prepare: false,
  idle_timeout: 5,
  connect_timeout: 5,
});

async function replaceBootstrapIdentity(
  appUserId: string,
  accountId: string,
  personId: string,
  authSubject: string,
): Promise<void> {
  await fixtureSql`
    insert into lifemate.app_users(id,auth_subject,status,created_at_utc,updated_at_utc)
    values (${appUserId}::uuid,${authSubject},'Active',now(),now())
  `;
  await fixtureSql`
    update identity.accounts
    set legacy_app_user_id=null,updated_at_utc=now()
    where id=${appUserId}::uuid
  `;
  await fixtureSql`
    insert into identity.accounts(id,legacy_app_user_id,status)
    values (${accountId}::uuid,${appUserId}::uuid,'Active')
  `;
  await fixtureSql`
    insert into core.persons(id,status,subject_category)
    values (${personId}::uuid,'Active','Adult')
  `;
  await fixtureSql`
    insert into core.account_person_links(account_id,person_id,link_type,status)
    values (${accountId}::uuid,${personId}::uuid,'Self','Active')
  `;
}

async function cleanupIdentity(
  appUserId: string,
  accountId: string,
  personId: string,
): Promise<void> {
  await fixtureSql`
    delete from core.account_person_links
    where account_id in (${appUserId}::uuid,${accountId}::uuid)
       or person_id in (${appUserId}::uuid,${personId}::uuid)
  `.catch(() => undefined);
  await fixtureSql`
    update identity.accounts
    set legacy_app_user_id=null,updated_at_utc=now()
    where id in (${appUserId}::uuid,${accountId}::uuid)
  `.catch(() => undefined);
  await fixtureSql`
    delete from identity.accounts
    where id in (${appUserId}::uuid,${accountId}::uuid)
  `.catch(() => undefined);
  await fixtureSql`
    delete from lifemate.app_users where id=${appUserId}::uuid
  `.catch(() => undefined);
  await fixtureSql`
    delete from core.persons
    where id in (${appUserId}::uuid,${personId}::uuid)
  `.catch(() => undefined);
}

Deno.test({
  name:
    "Women Calendar self runtime and export authorize by Person while legacy columns cannot override ownership",
  sanitizeOps: false,
  sanitizeResources: false,
  fn: async () => {
    const ownerAppUserId = crypto.randomUUID();
    const ownerAccountId = crypto.randomUUID();
    const ownerPersonId = crypto.randomUUID();
    const ownerAuthSubject = crypto.randomUUID();
    const otherAppUserId = crypto.randomUUID();
    const otherAccountId = crypto.randomUUID();
    const otherPersonId = crypto.randomUUID();
    const otherAuthSubject = crypto.randomUUID();

    for (
      const [appUserId, accountId, personId] of [
        [ownerAppUserId, ownerAccountId, ownerPersonId],
        [otherAppUserId, otherAccountId, otherPersonId],
      ]
    ) {
      assertNotEquals(appUserId, accountId);
      assertNotEquals(appUserId, personId);
      assertNotEquals(accountId, personId);
    }

    const women = createWomenCalendarStore(databaseUrl);
    const exporter = createDataExportStore(databaseUrl);
    let episodeId: string | null = null;
    let dailyLogId: string | null = null;
    let relationshipId: string | null = null;
    let supportActionId: string | null = null;

    try {
      await replaceBootstrapIdentity(
        ownerAppUserId,
        ownerAccountId,
        ownerPersonId,
        ownerAuthSubject,
      );
      await replaceBootstrapIdentity(
        otherAppUserId,
        otherAccountId,
        otherPersonId,
        otherAuthSubject,
      );

      const profile = await women.updateOwnerProfile(ownerAppUserId, {
        version: 0,
        enabled: true,
        lastPeriodStart: "2031-04-01",
        cycleLength: 28,
        periodLength: 5,
        remindersEnabled: true,
      });
      assertEquals(profile.ownerUserId, ownerAppUserId);
      assertEquals(profile.version, 1);

      const episode = await women.createOwnerEpisode(ownerAppUserId, {
        startedOn: "2031-04-01",
        endedOn: "2031-04-05",
        privateNotes: "owner-person-only episode",
      });
      episodeId = String(episode.id);

      const dailyLog = await women.upsertOwnerDailyLog(ownerAppUserId, {
        version: 0,
        loggedOn: "2031-04-03",
        mood: "good",
        energyLevel: 4,
        painLevel: 1,
        symptoms: ["fatigue"],
        privateNotes: "owner-person-only daily note",
        shareSummaryWithCompanion: false,
      });
      dailyLogId = String(dailyLog.id);

      const persisted = await fixtureSql`
        select
          p.owner_user_id::text as profile_user_id,
          p.owner_person_id::text as profile_person_id,
          e.owner_user_id::text as episode_user_id,
          e.owner_person_id::text as episode_person_id,
          d.owner_user_id::text as daily_user_id,
          d.owner_person_id::text as daily_person_id
        from lifemate.women_calendar_profiles p
        join lifemate.women_calendar_episodes e
          on e.id=${episodeId}::uuid
        join lifemate.women_calendar_daily_logs d
          on d.id=${dailyLogId}::uuid
        where p.owner_person_id=${ownerPersonId}::uuid
      `;
      assertEquals(persisted.length, 1);
      assertEquals(persisted[0].profile_user_id, ownerAppUserId);
      assertEquals(persisted[0].profile_person_id, ownerPersonId);
      assertEquals(persisted[0].episode_user_id, null);
      assertEquals(persisted[0].episode_person_id, ownerPersonId);
      assertEquals(persisted[0].daily_user_id, null);
      assertEquals(persisted[0].daily_person_id, ownerPersonId);

      // Simulate a stale/misleading compatibility link. The canonical Person
      // must remain the sole self-authorization and export boundary.
      await fixtureSql`
        update lifemate.women_calendar_profiles
        set owner_user_id=${otherAppUserId}::uuid
        where owner_person_id=${ownerPersonId}::uuid
      `;
      await fixtureSql`
        update lifemate.women_calendar_episodes
        set owner_user_id=${otherAppUserId}::uuid
        where id=${episodeId}::uuid
      `;
      await fixtureSql`
        update lifemate.women_calendar_daily_logs
        set owner_user_id=${otherAppUserId}::uuid
        where id=${dailyLogId}::uuid
      `;

      const ownerProfile = await women.getOwnerProfile(ownerAppUserId);
      assertEquals(ownerProfile.ownerUserId, ownerAppUserId);
      assertEquals(ownerProfile.enabled, true);
      assertEquals(ownerProfile.lastPeriodStart, "2031-04-01");

      const ownerEpisodes = await women.listOwnerEpisodes(ownerAppUserId);
      assertEquals(ownerEpisodes.length, 1);
      assertEquals(ownerEpisodes[0].id, episodeId);
      assertEquals(ownerEpisodes[0].privateNotes, "owner-person-only episode");

      const ownerLogs = await women.listOwnerDailyLogs(
        ownerAppUserId,
        "2031-04-01",
        "2031-04-07",
      );
      assertEquals(ownerLogs.length, 1);
      assertEquals(ownerLogs[0].id, dailyLogId);
      assertEquals(ownerLogs[0].privateNotes, "owner-person-only daily note");

      // An unrelated Person must not gain self access merely because its AppUser
      // UUID appears in the legacy compatibility column.
      const unrelatedProfile = await women.getOwnerProfile(otherAppUserId);
      assertEquals(unrelatedProfile.ownerUserId, otherAppUserId);
      assertEquals(unrelatedProfile.enabled, false);
      assertEquals(unrelatedProfile.version, 0);
      assertEquals((await women.listOwnerEpisodes(otherAppUserId)).length, 0);
      assertEquals(
        (
          await women.listOwnerDailyLogs(
            otherAppUserId,
            "2031-04-01",
            "2031-04-07",
          )
        ).length,
        0,
      );

      relationshipId = crypto.randomUUID();
      supportActionId = crypto.randomUUID();
      await fixtureSql`
        insert into lifemate.care_relationships
          (id, patient_user_id, caregiver_user_id, status,
           patient_consent_version, patient_consented_at_utc,
           caregiver_consent_version, caregiver_consented_at_utc,
           can_view_women_calendar, can_manage_health_record,
           created_at_utc, updated_at_utc)
        values
          (${relationshipId}::uuid, ${otherAppUserId}::uuid,
           ${ownerAppUserId}::uuid, 'Active', 'test-patient-v1', now(),
           'test-caregiver-v1', now(), true, false, now(), now())
      `;
      await fixtureSql`
        insert into lifemate.women_calendar_support_actions
          (id, patient_user_id, caregiver_user_id, relationship_id,
           action_type, performed_at_utc, created_at_utc, patient_person_id)
        values
          (${supportActionId}::uuid, ${otherAppUserId}::uuid,
           ${ownerAppUserId}::uuid, ${relationshipId}::uuid,
           'CheckIn', now(), now(), ${ownerPersonId}::uuid)
      `;

      const exported = await exporter.exportAccountData(ownerAppUserId);
      assertEquals(exported.schemaVersion, "lifemate-portable-export-v1");
      const womenExport = exported.womenCalendar as Record<string, unknown>;
      const profiles = womenExport.profiles as Array<Record<string, unknown>>;
      const episodes = womenExport.episodes as Array<Record<string, unknown>>;
      const dailyLogs = womenExport.dailyLogs as Array<Record<string, unknown>>;
      const supportActions = womenExport.supportActionsReceived as Array<
        Record<string, unknown>
      >;
      assertEquals(profiles.length, 1);
      assertEquals(profiles[0].enabled, true);
      assertEquals(episodes.length, 1);
      assertEquals(episodes[0].id, episodeId);
      assertEquals(episodes[0].privateNotes, "owner-person-only episode");
      assertEquals(dailyLogs.length, 1);
      assertEquals(dailyLogs[0].id, dailyLogId);
      assertEquals(dailyLogs[0].privateNotes, "owner-person-only daily note");
      assertEquals(supportActions.length, 1);
      assertEquals(supportActions[0].id, supportActionId);
      assertEquals(supportActions[0].actionType, "CheckIn");
      const encodedWomenExport = JSON.stringify(womenExport);
      assertEquals(encodedWomenExport.includes(ownerPersonId), false);
      assertEquals(encodedWomenExport.includes(otherPersonId), false);
      assertEquals(encodedWomenExport.includes(ownerAccountId), false);
      assertEquals(encodedWomenExport.includes(otherAccountId), false);
      assertEquals(encodedWomenExport.includes(ownerAppUserId), false);
      assertEquals(encodedWomenExport.includes(otherAppUserId), false);

      await assertApiError(
        () =>
          women.updateOwnerEpisode(otherAppUserId, episodeId!, {
            version: episode.version,
            startedOn: "2031-04-02",
            endedOn: "2031-04-06",
            privateNotes: "forbidden",
          }),
        404,
        "women_calendar_episode_not_found",
      );
      await assertApiError(
        () => women.deleteOwnerEpisode(otherAppUserId, episodeId!),
        404,
        "women_calendar_episode_not_found",
      );

      const updatedEpisode = await women.updateOwnerEpisode(
        ownerAppUserId,
        episodeId,
        {
          version: episode.version,
          startedOn: "2031-04-02",
          endedOn: "2031-04-06",
          privateNotes: "updated through Person ownership",
        },
      );
      assertEquals(updatedEpisode.startedOn, "2031-04-02");
      assertEquals(
        updatedEpisode.privateNotes,
        "updated through Person ownership",
      );

      const updatedDailyLog = await women.upsertOwnerDailyLog(ownerAppUserId, {
        version: dailyLog.version,
        loggedOn: "2031-04-03",
        mood: "great",
        energyLevel: 5,
        painLevel: 0,
        symptoms: ["no_symptom"],
        privateNotes: "updated through Person ownership",
        shareSummaryWithCompanion: false,
      });
      assertEquals(updatedDailyLog.version, 2);
      assertEquals(updatedDailyLog.mood, "great");

      await assertApiError(
        () => women.getOwnerProfile(crypto.randomUUID()),
        409,
        "identity_person_mapping_missing",
      );

      await women.deleteOwnerEpisode(ownerAppUserId, episodeId);
      assertEquals((await women.listOwnerEpisodes(ownerAppUserId)).length, 0);
      episodeId = null;

      const auditRows = await fixtureSql`
        select actor_user_id::text, action
        from lifemate.audit_logs
        where actor_user_id in (${ownerAppUserId}::uuid,${otherAppUserId}::uuid)
          and action like 'women_calendar.%'
        order by created_at_utc, action
      `;
      assertEquals(auditRows.length >= 6, true);
      assertEquals(
        auditRows.every((row) => row.actor_user_id === ownerAppUserId),
        true,
      );
    } finally {
      await closeLifeMateSqlClientsForTest().catch(() => undefined);
      if (supportActionId) {
        await fixtureSql`
          delete from lifemate.women_calendar_support_actions
          where id=${supportActionId}::uuid
        `.catch(() => undefined);
      }
      if (relationshipId) {
        await fixtureSql`
          delete from lifemate.care_relationships
          where id=${relationshipId}::uuid
        `.catch(() => undefined);
      }
      await fixtureSql`
        delete from lifemate.women_calendar_daily_logs
        where owner_person_id in (${ownerPersonId}::uuid,${otherPersonId}::uuid)
           or id=${dailyLogId}::uuid
      `.catch(() => undefined);
      await fixtureSql`
        delete from lifemate.women_calendar_episodes
        where owner_person_id in (${ownerPersonId}::uuid,${otherPersonId}::uuid)
      `.catch(() => undefined);
      await fixtureSql`
        delete from lifemate.women_calendar_profiles
        where owner_person_id in (${ownerPersonId}::uuid,${otherPersonId}::uuid)
           or owner_user_id in (${ownerAppUserId}::uuid,${otherAppUserId}::uuid)
      `.catch(() => undefined);
      await fixtureSql`
        delete from lifemate.audit_logs
        where actor_user_id in (${ownerAppUserId}::uuid,${otherAppUserId}::uuid)
      `.catch(() => undefined);
      await cleanupIdentity(ownerAppUserId, ownerAccountId, ownerPersonId);
      await cleanupIdentity(otherAppUserId, otherAccountId, otherPersonId);
      await fixtureSql.end({ timeout: 1 }).catch(() => undefined);
    }
  },
});

async function assertApiError(
  action: () => Promise<unknown>,
  status: number,
  code: string,
): Promise<void> {
  const error = await assertRejects(action, ApiError);
  assertEquals(error.status, status);
  assertEquals(error.code, code);
}
