import { getLifeMateSql } from "./database_client.ts";
import { createPersonWomenCalendarStore as createBasePersonWomenCalendarStore } from "./person_women_calendar.ts";
import { ApiError, requiredUuid } from "./validation.ts";
import { calculateWomenCalendarEstimateFromEpisodes } from "./women_calendar_legacy.ts";

type Row = Record<string, any>;

const supportActions: Record<string, string> = {
  hydration: "Hydration",
  rest: "Rest",
  warmth: "Warmth",
  chores: "Chores",
  walk: "Walk",
  check_in: "CheckIn",
};

const storedSymptoms: Record<string, string> = {
  Cramps: "cramps",
  Headache: "headache",
  Bloating: "bloating",
  Fatigue: "fatigue",
  BreastTenderness: "breast_tenderness",
  BackPain: "back_pain",
  SleepChange: "sleep_change",
  AppetiteChange: "appetite_change",
  NoSymptom: "no_symptom",
};

async function resolveCarePeople(
  connection: any,
  caregiverAppUserId: string,
  patientAppUserId: string,
): Promise<{ caregiverPersonId: string; patientPersonId: string }> {
  const rows = await connection`
    select
      core.self_person_id_for_legacy_app_user(
        ${caregiverAppUserId}::uuid
      )::text as caregiver_person_id,
      core.self_person_id_for_legacy_app_user(
        ${patientAppUserId}::uuid
      )::text as patient_person_id
  `;
  const caregiverPersonId = rows[0]?.caregiver_person_id;
  if (typeof caregiverPersonId !== "string" || caregiverPersonId.length === 0) {
    throw new ApiError(
      409,
      "identity_person_mapping_missing",
      "The LifeMate person mapping is unavailable.",
    );
  }
  const patientPersonId = rows[0]?.patient_person_id;
  if (typeof patientPersonId !== "string" || patientPersonId.length === 0) {
    throw accessDenied();
  }
  return { caregiverPersonId, patientPersonId };
}

/**
 * Compose the Person-authoritative self store with canonical caregiver access.
 *
 * AppUser identifiers remain API/audit compatibility values in this stage.
 * Relationship authorization and all patient-owned Women Calendar reads use
 * canonical Person IDs, so caregiver access does not depend on identifier
 * equality across AppUser, Account and Person domains.
 */
export function createPersonWomenCalendarCaregiverStore(databaseUrl: string) {
  const sql = getLifeMateSql(databaseUrl);
  const base = createBasePersonWomenCalendarStore(databaseUrl);

  async function getCareSummary(
    caregiverAppUserId: string,
    patientAppUserIdValue: unknown,
  ): Promise<Record<string, unknown>> {
    const patientAppUserId = requiredUuid(
      patientAppUserIdValue,
      "patientUserId",
    );
    const { caregiverPersonId, patientPersonId } = await resolveCarePeople(
      sql,
      caregiverAppUserId,
      patientAppUserId,
    );

    const relationshipRows = await sql`
      select id
      from lifemate.care_relationships
      where patient_person_id=${patientPersonId}::uuid
        and caregiver_person_id=${caregiverPersonId}::uuid
        and status='Active'
        and can_view_women_calendar=true
      limit 1
    `;
    if (!relationshipRows[0]) throw accessDenied();

    const profiles = await sql`
      select *
      from lifemate.women_calendar_profiles
      where owner_person_id=${patientPersonId}::uuid
        and enabled=true
      limit 1
    `;
    if (!profiles[0]) {
      throw new ApiError(
        404,
        "women_calendar_not_active",
        "Women calendar is not active for this patient.",
      );
    }

    const patientProfiles = await sql`
      select display_name,avatar_key
      from core.person_profiles
      where person_id=${patientPersonId}::uuid
      limit 1
    `;
    const episodes = await sql`
      select id,started_on,ended_on,version,created_at_utc,updated_at_utc
      from lifemate.women_calendar_episodes
      where owner_person_id=${patientPersonId}::uuid
      order by started_on desc,id
      limit 12
    `;
    const actions = await sql`
      select action_type,performed_at_utc
      from lifemate.women_calendar_support_actions
      where patient_person_id=${patientPersonId}::uuid
      order by performed_at_utc desc,id
      limit 20
    `;
    const sharedLogs = await sql`
      select logged_on,mood,energy_level,pain_level,symptoms,version,
             updated_at_utc
      from lifemate.women_calendar_daily_logs
      where owner_person_id=${patientPersonId}::uuid
        and share_summary_with_companion=true
        and logged_on >= current_date - interval '14 days'
      order by logged_on desc,id
      limit 1
    `;

    const profile = profiles[0];
    const lastPeriodStart = dateString(profile.last_period_start);
    const estimate = calculateWomenCalendarEstimateFromEpisodes(
      lastPeriodStart,
      Number(profile.cycle_length),
      Number(profile.period_length),
      episodes.map((episode: Row) => dateString(episode.started_on)),
    );
    const canonicalSharedLog = sharedLogs[0]
      ? mapDailyLogCompanion(sharedLogs[0])
      : null;
    const sharedDailySummary = canonicalSharedLog == null ? null : {
      date: canonicalSharedLog.loggedOn,
      mood: canonicalSharedLog.mood,
      energy: canonicalSharedLog.energyLevel,
      pain: canonicalSharedLog.painLevel,
      symptoms: canonicalSharedLog.symptoms,
    };
    const patientProfile = patientProfiles[0];

    return {
      patient: {
        displayName: patientProfile?.display_name ?? "LifeMate User",
        avatarKey: patientProfile?.avatar_key ?? "person_purple",
      },
      profile: {
        enabled: profile.enabled,
        lastPeriodStart,
        cycleLength: profile.cycle_length,
        periodLength: profile.period_length,
        algorithmVersion: profile.algorithm_version,
      },
      estimate,
      sharedDailySummary,
      episodes: episodes.map(mapEpisodeCaregiver),
      latestSharedDailyLog: canonicalSharedLog,
      supportActions: actions.map((row: Row) => ({
        actionType: String(row.action_type).toLowerCase(),
        performedAtUtc: iso(row.performed_at_utc),
      })),
    };
  }

  async function recordCareSupportAction(
    caregiverAppUserId: string,
    patientAppUserIdValue: unknown,
    body: Record<string, unknown>,
  ): Promise<Record<string, unknown>> {
    const patientAppUserId = requiredUuid(
      patientAppUserIdValue,
      "patientUserId",
    );
    const normalized = String(body.actionType ?? "").trim().toLowerCase();
    const actionType = supportActions[normalized];
    if (!actionType) {
      throw new ApiError(
        400,
        "invalid_women_calendar_support_action",
        "Unsupported support action.",
      );
    }

    const { caregiverPersonId, patientPersonId } = await resolveCarePeople(
      sql,
      caregiverAppUserId,
      patientAppUserId,
    );
    const relationshipRows = await sql`
      select id
      from lifemate.care_relationships
      where patient_person_id=${patientPersonId}::uuid
        and caregiver_person_id=${caregiverPersonId}::uuid
        and status='Active'
        and can_view_women_calendar=true
      limit 1
    `;
    if (!relationshipRows[0]) throw accessDenied();

    const profiles = await sql`
      select owner_person_id
      from lifemate.women_calendar_profiles
      where owner_person_id=${patientPersonId}::uuid
        and enabled=true
      limit 1
    `;
    if (!profiles[0]) {
      throw new ApiError(
        404,
        "women_calendar_not_active",
        "Women calendar is not active for this patient.",
      );
    }

    const id = crypto.randomUUID();
    const now = new Date();
    const rows = await sql`
      insert into lifemate.women_calendar_support_actions
        (id,patient_user_id,caregiver_user_id,relationship_id,
         action_type,performed_at_utc,created_at_utc,patient_person_id)
      values
        (${id}::uuid,${patientAppUserId}::uuid,${caregiverAppUserId}::uuid,
         ${relationshipRows[0].id}::uuid,${actionType},${now},${now},
         ${patientPersonId}::uuid)
      returning action_type,performed_at_utc
    `;
    await insertAudit(
      sql,
      caregiverAppUserId,
      "women_calendar.support_action_recorded",
      "women_calendar_support_action",
      id,
    );
    return {
      id,
      actionType: String(rows[0].action_type).toLowerCase(),
      performedAtUtc: iso(rows[0].performed_at_utc),
    };
  }

  return {
    ...base,
    getCareSummary,
    recordCareSupportAction,
  };
}

export {
  createPersonWomenCalendarCaregiverStore as createPersonWomenCalendarStore,
};

function accessDenied(): ApiError {
  return new ApiError(
    403,
    "women_calendar_access_denied",
    "Women calendar access is not active.",
  );
}

function mapEpisodeCaregiver(row: Row): Record<string, unknown> {
  return {
    id: row.id,
    startedOn: dateString(row.started_on),
    endedOn: row.ended_on == null ? null : dateString(row.ended_on),
    version: row.version,
  };
}

function mapDailyLogCompanion(row: Row): Record<string, unknown> {
  return {
    loggedOn: dateString(row.logged_on),
    mood: String(row.mood).toLowerCase(),
    energyLevel: row.energy_level,
    painLevel: row.pain_level,
    symptoms: normalizeStoredSymptoms(row.symptoms),
    version: row.version,
    updatedAtUtc: iso(row.updated_at_utc),
  };
}

function normalizeStoredSymptoms(value: unknown): string[] {
  if (!Array.isArray(value)) return [];
  return value
    .map((item) => storedSymptoms[String(item)])
    .filter((item): item is string => item != null);
}

async function insertAudit(
  connection: any,
  actorAppUserId: string,
  action: string,
  resourceType: string,
  resourceId: string,
): Promise<void> {
  await connection`
    insert into lifemate.audit_logs
      (id,actor_user_id,action,resource_type,resource_id,
       metadata_json,created_at_utc)
    values
      (${crypto.randomUUID()}::uuid,${actorAppUserId}::uuid,${action},
       ${resourceType},${resourceId}::uuid,null,now())
  `;
}

function iso(value: unknown): string {
  return value instanceof Date
    ? value.toISOString()
    : new Date(String(value)).toISOString();
}

function dateString(value: unknown): string {
  if (value instanceof Date) return value.toISOString().slice(0, 10);
  return String(value).slice(0, 10);
}
