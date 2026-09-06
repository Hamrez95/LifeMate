import {
  assertEquals,
  assertNotEquals,
  assertRejects,
} from "jsr:@std/assert@1.0.14";
import postgres from "postgres";
import { closeLifeMateSqlClientsForTest } from "./database_client.ts";
import { ApiError } from "./validation.ts";
import { createWomenCalendarStore } from "./women_calendar.ts";

const databaseUrl = Deno.env.get("TEST_DATABASE_URL");
if (!databaseUrl) {
  throw new Error(
    "TEST_DATABASE_URL is required for Person caregiver Women Calendar tests.",
  );
}

const fixtureSql = postgres(databaseUrl, {
  max: 1,
  prepare: false,
  idle_timeout: 5,
  connect_timeout: 5,
});

type IdentityFixture = {
  appUserId: string;
  accountId: string;
  personId: string;
};

async function createUnequalIdentity(
  displayName: string,
  avatarKey: string,
): Promise<IdentityFixture> {
  const appUserId = crypto.randomUUID();
  const accountId = crypto.randomUUID();
  const personId = crypto.randomUUID();
  assertNotEquals(appUserId, accountId);
  assertNotEquals(appUserId, personId);
  assertNotEquals(accountId, personId);

  await fixtureSql`
    insert into lifemate.app_users(id,auth_subject,status,created_at_utc,updated_at_utc)
    values (${appUserId}::uuid,${crypto.randomUUID()},'Active',now(),now())
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
  await fixtureSql`
    insert into core.person_profiles(
      person_id,display_name,locale,time_zone,avatar_key,
      created_at_utc,updated_at_utc
    ) values (
      ${personId}::uuid,${displayName},'en','UTC',${avatarKey},now(),now()
    )
    on conflict (person_id) do update
    set display_name=excluded.display_name,
        avatar_key=excluded.avatar_key,
        updated_at_utc=now()
  `;

  return { appUserId, accountId, personId };
}

async function cleanupIdentity(identity: IdentityFixture): Promise<void> {
  await fixtureSql`
    delete from core.person_profiles where person_id=${identity.personId}::uuid
  `.catch(() => undefined);
  await fixtureSql`
    delete from core.account_person_links
    where account_id in (${identity.appUserId}::uuid,${identity.accountId}::uuid)
       or person_id=${identity.personId}::uuid
  `.catch(() => undefined);
  await fixtureSql`
    update identity.accounts
    set legacy_app_user_id=null,updated_at_utc=now()
    where id in (${identity.appUserId}::uuid,${identity.accountId}::uuid)
  `.catch(() => undefined);
  await fixtureSql`
    delete from identity.accounts
    where id in (${identity.appUserId}::uuid,${identity.accountId}::uuid)
  `.catch(() => undefined);
  await fixtureSql`
    delete from lifemate.app_users where id=${identity.appUserId}::uuid
  `.catch(() => undefined);
  await fixtureSql`
    delete from core.persons where id=${identity.personId}::uuid
  `.catch(() => undefined);
}

function dateOffset(days: number): string {
  const value = new Date();
  value.setUTCHours(0, 0, 0, 0);
  value.setUTCDate(value.getUTCDate() + days);
  return value.toISOString().slice(0, 10);
}

Deno.test({
  name:
    "Women Calendar caregiver runtime authorizes and reads by canonical Person",
  sanitizeOps: false,
  sanitizeResources: false,
  fn: async () => {
    const patient = await createUnequalIdentity(
      "Canonical Patient",
      "person_purple",
    );
    const caregiver = await createUnequalIdentity(
      "Canonical Caregiver",
      "person_blue",
    );
    const unrelated = await createUnequalIdentity(
      "Unrelated Person",
      "person_green",
    );
    const women = createWomenCalendarStore(databaseUrl);
    const relationshipId = crypto.randomUUID();
    let episodeId: string | null = null;
    let supportActionId: string | null = null;

    try {
      await women.updateOwnerProfile(patient.appUserId, {
        version: 0,
        enabled: true,
        lastPeriodStart: dateOffset(-28),
        cycleLength: 28,
        periodLength: 5,
        remindersEnabled: true,
      });
      const episode = await women.createOwnerEpisode(patient.appUserId, {
        startedOn: dateOffset(-28),
        endedOn: dateOffset(-24),
        privateNotes: "caregiver must never see this episode note",
      });
      episodeId = String(episode.id);

      await women.upsertOwnerDailyLog(patient.appUserId, {
        version: 0,
        loggedOn: dateOffset(-1),
        mood: "low",
        energyLevel: 2,
        painLevel: 3,
        symptoms: ["cramps"],
        privateNotes: "unshared private daily note",
        shareSummaryWithCompanion: false,
      });
      await women.upsertOwnerDailyLog(patient.appUserId, {
        version: 0,
        loggedOn: dateOffset(0),
        mood: "good",
        energyLevel: 4,
        painLevel: 1,
        symptoms: ["fatigue"],
        privateNotes: "shared-row private note must still stay private",
        shareSummaryWithCompanion: true,
      });

      await fixtureSql`
        insert into lifemate.care_relationships(
          id,patient_user_id,caregiver_user_id,status,
          patient_consent_version,patient_consented_at_utc,
          caregiver_consent_version,caregiver_consented_at_utc,
          can_view_women_calendar,can_manage_health_record,
          created_at_utc,updated_at_utc
        ) values (
          ${relationshipId}::uuid,${patient.appUserId}::uuid,
          ${caregiver.appUserId}::uuid,'Active','patient-consent-v1',now(),
          'caregiver-consent-v1',now(),true,false,now(),now()
        )
      `;
      const relationship = await fixtureSql`
        select patient_person_id::text,caregiver_person_id::text
        from lifemate.care_relationships
        where id=${relationshipId}::uuid
      `;
      assertEquals(relationship[0].patient_person_id, patient.personId);
      assertEquals(relationship[0].caregiver_person_id, caregiver.personId);

      await fixtureSql`
        insert into lifemate.women_companion_privacy_scopes (
          relationship_id,
          view_period_timing,
          view_phase_summary,
          view_shared_wellbeing,
          view_calendar_detail,
          updated_by_user_id
        ) values (
          ${relationshipId}::uuid,
          true,
          true,
          true,
          true,
          ${patient.appUserId}::uuid
        )
      `;

      const supportSchema = await fixtureSql`
        select column_name,is_nullable
        from information_schema.columns
        where table_schema='lifemate'
          and table_name='women_calendar_support_actions'
          and column_name in ('patient_user_id','patient_person_id')
        order by column_name
      `;
      assertEquals(
        supportSchema.map((row) => ({
          column_name: String(row.column_name),
          is_nullable: String(row.is_nullable),
        })),
        [
          { column_name: "patient_person_id", is_nullable: "NO" },
          { column_name: "patient_user_id", is_nullable: "YES" },
        ],
      );

      const summary = await women.getCareSummary(
        caregiver.appUserId,
        patient.appUserId,
      );
      const patientSummary = summary.patient as Record<string, unknown>;
      assertEquals(patientSummary.displayName, "Canonical Patient");
      assertEquals(patientSummary.avatarKey, "person_purple");
      const episodes = summary.episodes as Array<Record<string, unknown>>;
      assertEquals(episodes.length, 1);
      assertEquals(episodes[0].id, episodeId);
      assertEquals("privateNotes" in episodes[0], false);
      const sharedLog = summary.latestSharedDailyLog as Record<string, unknown>;
      assertEquals(sharedLog.loggedOn, dateOffset(0));
      assertEquals(sharedLog.mood, "good");
      assertEquals("privateNotes" in sharedLog, false);
      const sharedSummary = summary.sharedDailySummary as Record<
        string,
        unknown
      >;
      assertEquals(sharedSummary.date, dateOffset(0));
      const encodedSummary = JSON.stringify(summary);
      assertEquals(
        encodedSummary.includes("unshared private daily note"),
        false,
      );
      assertEquals(
        encodedSummary.includes(
          "shared-row private note must still stay private",
        ),
        false,
      );
      assertEquals(
        encodedSummary.includes("caregiver must never see this episode note"),
        false,
      );

      await assertApiError(
        () => women.getCareSummary(unrelated.appUserId, patient.appUserId),
        403,
        "women_calendar_access_denied",
      );
      await assertApiError(
        () => women.getCareSummary(crypto.randomUUID(), patient.appUserId),
        409,
        "identity_person_mapping_missing",
      );

      await fixtureSql`
        update lifemate.care_relationships
        set can_view_women_calendar=false,updated_at_utc=now()
        where id=${relationshipId}::uuid
      `;
      const legacyFlagIgnored = await women.getCareSummary(
        caregiver.appUserId,
        patient.appUserId,
      );
      assertEquals(
        (legacyFlagIgnored.patient as Record<string, unknown>).displayName,
        "Canonical Patient",
      );

      await fixtureSql`
        update lifemate.women_companion_privacy_scopes
        set view_period_timing=false,
            view_phase_summary=false,
            view_shared_wellbeing=false,
            view_fertility_estimate=false,
            receive_phase_notifications=false,
            receive_mood_support_notifications=false,
            receive_fertility_notifications=false,
            view_calendar_detail=false,
            version=version+1,
            updated_by_user_id=${patient.appUserId}::uuid,
            updated_at_utc=now()
        where relationship_id=${relationshipId}::uuid
      `;
      await assertApiError(
        () => women.getCareSummary(caregiver.appUserId, patient.appUserId),
        403,
        "women_calendar_access_denied",
      );
      await fixtureSql`
        update lifemate.women_companion_privacy_scopes
        set view_period_timing=true,
            view_phase_summary=true,
            view_shared_wellbeing=true,
            view_calendar_detail=true,
            version=version+1,
            updated_by_user_id=${patient.appUserId}::uuid,
            updated_at_utc=now()
        where relationship_id=${relationshipId}::uuid
      `;

      const action = await women.recordCareSupportAction(
        caregiver.appUserId,
        patient.appUserId,
        { actionType: "check_in" },
      );
      supportActionId = String(action.id);
      assertEquals(action.actionType, "checkin");
      const persistedAction = await fixtureSql`
        select patient_user_id::text,caregiver_user_id::text,
               patient_person_id::text,relationship_id::text
        from lifemate.women_calendar_support_actions
        where id=${supportActionId}::uuid
      `;
      assertEquals(persistedAction[0].patient_user_id, null);
      assertEquals(persistedAction[0].caregiver_user_id, caregiver.appUserId);
      assertEquals(persistedAction[0].patient_person_id, patient.personId);
      assertEquals(persistedAction[0].relationship_id, relationshipId);

      const audit = await fixtureSql`
        select actor_user_id::text,action
        from lifemate.audit_logs
        where resource_type='women_calendar_support_action'
          and resource_id=${supportActionId}::uuid
      `;
      assertEquals(audit.length, 1);
      assertEquals(audit[0].actor_user_id, caregiver.appUserId);
      assertEquals(audit[0].action, "women_calendar.support_action_recorded");

      const afterAction = await women.getCareSummary(
        caregiver.appUserId,
        patient.appUserId,
      );
      const actions = afterAction.supportActions as Array<
        Record<string, unknown>
      >;
      assertEquals(actions.length >= 1, true);
      assertEquals(actions[0].actionType, "checkin");

      await fixtureSql`
        update lifemate.care_relationships
        set status='Revoked',revoked_by_user_id=${patient.appUserId}::uuid,
            revoked_at_utc=now(),updated_at_utc=now()
        where id=${relationshipId}::uuid
      `;
      await assertApiError(
        () => women.getCareSummary(caregiver.appUserId, patient.appUserId),
        403,
        "women_calendar_access_denied",
      );
      await assertApiError(
        () =>
          women.recordCareSupportAction(
            caregiver.appUserId,
            patient.appUserId,
            { actionType: "rest" },
          ),
        403,
        "women_calendar_access_denied",
      );
    } finally {
      await closeLifeMateSqlClientsForTest().catch(() => undefined);
      if (supportActionId) {
        await fixtureSql`
          delete from lifemate.women_calendar_support_actions
          where id=${supportActionId}::uuid
        `.catch(() => undefined);
      }
      await fixtureSql`
        delete from lifemate.care_relationships where id=${relationshipId}::uuid
      `.catch(() => undefined);
      await fixtureSql`
        delete from lifemate.women_calendar_daily_logs
        where owner_person_id=${patient.personId}::uuid
      `.catch(() => undefined);
      await fixtureSql`
        delete from lifemate.women_calendar_episodes
        where owner_person_id=${patient.personId}::uuid
      `.catch(() => undefined);
      await fixtureSql`
        delete from lifemate.women_calendar_profiles
        where owner_person_id=${patient.personId}::uuid
      `.catch(() => undefined);
      await fixtureSql`
        delete from lifemate.audit_logs
        where actor_user_id in (
          ${patient.appUserId}::uuid,${caregiver.appUserId}::uuid,
          ${unrelated.appUserId}::uuid
        )
      `.catch(() => undefined);
      await cleanupIdentity(patient);
      await cleanupIdentity(caregiver);
      await cleanupIdentity(unrelated);
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
