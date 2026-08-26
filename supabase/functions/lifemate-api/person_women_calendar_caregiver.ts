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
 * AppUser identifiers remain API/audit compatibility values where they carry
 * an independent actor meaning. Relationship authorization and all
 * patient-owned Women Calendar reads/writes use canonical Person IDs. In
 * particular, new support actions no longer persist the patient's AppUser id;
 * caregiver_user_id remains deliberate caregiver actor/audit provenance.
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
      select r.id, s.*
      from lifemate.care_relationships r
      left join lifemate.women_companion_privacy_scopes s on s.relationship_id = r.id
      where r.patient_person_id=${patientPersonId}::uuid
        and r.caregiver_person_id=${caregiverPersonId}::uuid
        and r.status='Active'
        and r.can_view_women_calendar=true
      limit 1
    `;
    if (!relationshipRows[0]) throw accessDenied();
    const privacy = companionPrivacy(relationshipRows[0]);
    if (!Object.values(privacy).some(Boolean)) throw accessDenied();

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
    const episodes = privacy.viewCalendarDetail || privacy.viewPeriodTiming
      ? await sql`
        select id,started_on,ended_on,version,created_at_utc,updated_at_utc
        from lifemate.women_calendar_episodes
        where owner_person_id=${patientPersonId}::uuid
        order by started_on desc,id limit 12
      `
      : [];
    const actions = await sql`
      select action_type,performed_at_utc
      from lifemate.women_calendar_support_actions
      where patient_person_id=${patientPersonId}::uuid
      order by performed_at_utc desc,id
      limit 20
    `;
    const sharedLogs = privacy.viewSharedWellbeing
      ? await sql`
        select logged_on,mood,energy_level,version,updated_at_utc
        from lifemate.women_calendar_daily_logs
        where owner_person_id=${patientPersonId}::uuid
          and share_summary_with_companion=true
          and logged_on >= current_date - interval '14 days'
        order by logged_on desc,id limit 1
      `
      : [];

    const profile = profiles[0];
    const lastPeriodStart = dateString(profile.last_period_start);
    const rawEstimate = calculateWomenCalendarEstimateFromEpisodes(
      lastPeriodStart, Number(profile.cycle_length), Number(profile.period_length),
      episodes.map((episode: Row) => dateString(episode.started_on)),
    );
    const estimate = presentEstimate(rawEstimate, privacy);
    const canonicalSharedLog = sharedLogs[0]
      ? mapDailyLogCompanion(sharedLogs[0])
      : null;
    const sharedDailySummary = canonicalSharedLog == null ? null : {
      date: canonicalSharedLog.loggedOn,
      mood: canonicalSharedLog.mood,
      energy: canonicalSharedLog.energyLevel,
    };
    const patientProfile = patientProfiles[0];

    return {
      patient: {
        displayName: patientProfile?.display_name ?? "LifeMate User",
        avatarKey: patientProfile?.avatar_key ?? "person_purple",
      },
      privacyScopes: privacy,
      profile: {
        enabled: profile.enabled,
        lastPeriodStart: privacy.viewPeriodTiming ? lastPeriodStart : null,
        cycleLength: privacy.viewCalendarDetail ? profile.cycle_length : null,
        periodLength: privacy.viewCalendarDetail ? profile.period_length : null,
        algorithmVersion: privacy.viewPhaseSummary ? profile.algorithm_version : null,
      },
      estimate,
      sharedDailySummary: privacy.viewSharedWellbeing ? sharedDailySummary : null,
      episodes: privacy.viewCalendarDetail
        ? episodes.map(mapEpisodeCaregiver)
        : [],
      latestSharedDailyLog: privacy.viewSharedWellbeing ? canonicalSharedLog : null,
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
      select r.id, s.*
      from lifemate.care_relationships r
      left join lifemate.women_companion_privacy_scopes s on s.relationship_id = r.id
      where r.patient_person_id=${patientPersonId}::uuid
        and r.caregiver_person_id=${caregiverPersonId}::uuid
        and r.status='Active' and r.can_view_women_calendar=true
      limit 1
    `;
    if (!relationshipRows[0] || !companionPrivacy(relationshipRows[0]).viewSharedWellbeing) throw accessDenied();

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
        (id,caregiver_user_id,relationship_id,action_type,
         performed_at_utc,created_at_utc,patient_person_id)
      values
        (${id}::uuid,${caregiverAppUserId}::uuid,
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


type CompanionPrivacy = {
  viewPeriodTiming: boolean; viewPhaseSummary: boolean; viewSharedWellbeing: boolean;
  receiveMoodSupportNotifications: boolean; receivePhaseNotifications: boolean;
  viewFertilityEstimate: boolean; receiveFertilityNotifications: boolean; viewCalendarDetail: boolean;
};
function companionPrivacy(row: Row): CompanionPrivacy {
  return {
    viewPeriodTiming: row.view_period_timing === true, viewPhaseSummary: row.view_phase_summary === true,
    viewSharedWellbeing: row.view_shared_wellbeing === true,
    receiveMoodSupportNotifications: row.receive_mood_support_notifications === true,
    receivePhaseNotifications: row.receive_phase_notifications === true,
    viewFertilityEstimate: row.view_fertility_estimate === true,
    receiveFertilityNotifications: row.receive_fertility_notifications === true,
    viewCalendarDetail: row.view_calendar_detail === true,
  };
}
function presentEstimate(estimate: any, privacy: CompanionPrivacy): Record<string, unknown> | null {
  if (privacy.viewFertilityEstimate) return estimate;
  if (!privacy.viewPhaseSummary) return null;
  return Object.fromEntries(Object.entries(estimate).filter(([key]) =>
    !/fertil|ovulat/i.test(key),
  ));
}

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
  // The query intentionally selects only shareable wellbeing fields. Keep this
  // projection narrow so private notes, pain and symptom details cannot leak
  // through a future mapper change.
  return {
    loggedOn: dateString(row.logged_on),
    mood: String(row.mood).toLowerCase(),
    energyLevel: row.energy_level,
    version: row.version,
    updatedAtUtc: iso(row.updated_at_utc),
  };
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
