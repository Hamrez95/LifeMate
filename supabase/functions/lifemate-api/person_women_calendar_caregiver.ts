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

const guidanceCategories = new Set([
  "general",
  "phase",
  "mood",
  "energy",
  "fertility",
]);
const phaseNotificationContentVersion = "companion-phase-notifications-v1";
const moodNotificationContentVersion = "companion-mood-notifications-v1";
const fertilityNotificationContentVersion =
  "companion-fertility-notifications-v1";

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

export function createPersonWomenCalendarCaregiverStore(databaseUrl: string) {
  const sql = getLifeMateSql(databaseUrl);
  const base = createBasePersonWomenCalendarStore(databaseUrl);

  async function resolveActiveRelationship(
    caregiverPersonId: string,
    patientPersonId: string,
  ): Promise<Row> {
    const rows = await sql`
      select r.id, r.caregiver_notifications_enabled,
             r.caregiver_lock_screen_detail, s.*
      from lifemate.care_relationships r
      left join lifemate.women_companion_privacy_scopes s on s.relationship_id = r.id
      where r.patient_person_id=${patientPersonId}::uuid
        and r.caregiver_person_id=${caregiverPersonId}::uuid
        and r.status='Active'
      limit 1
    `;
    if (!rows[0]) throw accessDenied();
    return rows[0];
  }

  async function requireCurrentMoodNotificationEntry(
    patientPersonId: string,
    guidanceId: string,
  ): Promise<void> {
    const match = guidanceId.match(
      /^notify\.mood\.(check_in|energy)\.(\d{4}-\d{2}-\d{2})$/,
    );
    if (!match) throw accessDenied();
    const [, trigger, expectedDate] = match;
    const rows = await sql`
      select logged_on,mood,energy_level,share_summary_with_companion,updated_at_utc
      from lifemate.women_calendar_daily_logs
      where owner_person_id=${patientPersonId}::uuid
      order by logged_on desc,id
      limit 1
    `;
    const row = rows[0];
    if (
      !row ||
      row.share_summary_with_companion !== true ||
      dateString(row.logged_on) !== expectedDate
    ) {
      throw accessDenied();
    }
    const updatedAt = new Date(String(row.updated_at_utc));
    if (
      !Number.isFinite(updatedAt.getTime()) ||
      Date.now() - updatedAt.getTime() > 8 * 60 * 60 * 1000 ||
      updatedAt.getTime() > Date.now() + 60_000
    ) {
      throw accessDenied();
    }
    const mood = String(row.mood ?? "").toLowerCase();
    const lowMood = mood === "low" || mood === "overwhelmed";
    if (trigger === "check_in" && !lowMood) throw accessDenied();
    if (
      trigger === "energy" &&
      (lowMood || Number(row.energy_level) > 2 || Number(row.energy_level) < 1)
    ) {
      throw accessDenied();
    }
  }

  async function requireCurrentFertilityNotificationEstimate(
    patientPersonId: string,
    guidanceId: string,
  ): Promise<void> {
    const match = guidanceId.match(
      /^notify\.fertility\.window\.(\d{4}-\d{2}-\d{2})$/,
    );
    if (!match) throw accessDenied();
    const expectedWindowStart = match[1];
    const profiles = await sql`
      select last_period_start,cycle_length,period_length
      from lifemate.women_calendar_profiles
      where owner_person_id=${patientPersonId}::uuid and enabled=true
      limit 1
    `;
    if (!profiles[0]) throw accessDenied();
    const episodes = await sql`
      select started_on
      from lifemate.women_calendar_episodes
      where owner_person_id=${patientPersonId}::uuid
      order by started_on asc
      limit 100
    `;
    const profile = profiles[0];
    const estimate = calculateWomenCalendarEstimateFromEpisodes(
      dateString(profile.last_period_start),
      Number(profile.cycle_length),
      Number(profile.period_length),
      episodes.map((episode: Row) => dateString(episode.started_on)),
    );
    const cycleDay = Number(estimate.cycleDay);
    const windowStart = Number(estimate.fertileWindowStartDay);
    const windowEnd = Number(estimate.fertileWindowEndDay);
    const estimatedWindowStart = Number.isFinite(windowStart)
      ? addDays(dateString(estimate.cycleStart), windowStart - 1)
      : null;
    if (
      estimatedWindowStart !== expectedWindowStart ||
      estimate.fertilityEstimateReliable !== true ||
      String(estimate.cyclePattern).toLowerCase() !== "regular" ||
      String(estimate.confidence).toLowerCase() === "low" ||
      !Number.isFinite(cycleDay) ||
      !Number.isFinite(windowStart) ||
      !Number.isFinite(windowEnd) ||
      cycleDay < windowStart ||
      cycleDay > windowEnd
    ) {
      throw accessDenied();
    }
  }

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
    const relationship = await resolveActiveRelationship(
      caregiverPersonId,
      patientPersonId,
    );
    const privacy = companionPrivacy(relationship);
    if (!Object.values(privacy).some(Boolean)) throw accessDenied();

    const profiles = await sql`
      select * from lifemate.women_calendar_profiles
      where owner_person_id=${patientPersonId}::uuid and enabled=true
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
      select display_name,avatar_key from core.person_profiles
      where person_id=${patientPersonId}::uuid limit 1
    `;
    const needsCycleEstimate = privacy.viewPhaseSummary ||
      privacy.viewPeriodTiming ||
      privacy.viewCalendarDetail ||
      privacy.viewFertilityEstimate;
    const episodes = needsCycleEstimate
      ? await sql`
        select id,started_on,ended_on,version,created_at_utc,updated_at_utc
        from lifemate.women_calendar_episodes
        where owner_person_id=${patientPersonId}::uuid
        order by started_on desc,id limit 100
      `
      : [];
    const actions = privacy.viewSharedWellbeing
      ? await sql`
        select action_type,performed_at_utc
        from lifemate.women_calendar_support_actions
        where relationship_id=${relationship.id}::uuid
          and patient_person_id=${patientPersonId}::uuid
        order by performed_at_utc desc,id limit 20
      `
      : [];
    const guidanceHistory = await sql`
      select guidance_id,shown_at_utc
      from lifemate.women_companion_guidance_history
      where relationship_id=${relationship.id}::uuid
        and patient_person_id=${patientPersonId}::uuid
        and caregiver_person_id=${caregiverPersonId}::uuid
      order by shown_at_utc desc,id limit 20
    `;
    const latestLogs = privacy.viewSharedWellbeing
      ? await sql`
        select logged_on,mood,energy_level,version,updated_at_utc,
               share_summary_with_companion
        from lifemate.women_calendar_daily_logs
        where owner_person_id=${patientPersonId}::uuid
          and logged_on >= current_date - interval '14 days'
        order by logged_on desc,id limit 1
      `
      : [];

    const profile = profiles[0];
    const lastPeriodStart = dateString(profile.last_period_start);
    const rawEstimate = calculateWomenCalendarEstimateFromEpisodes(
      lastPeriodStart,
      Number(profile.cycle_length),
      Number(profile.period_length),
      [...episodes]
        .sort((left: Row, right: Row) =>
          dateString(left.started_on).localeCompare(
            dateString(right.started_on),
          )
        )
        .map((episode: Row) => dateString(episode.started_on)),
    );
    const estimate = presentCycleEstimate(rawEstimate, privacy);
    const fertilityEstimate = presentFertilityEstimate(rawEstimate, privacy);
    const canonicalSharedLog =
      latestLogs[0]?.share_summary_with_companion === true
        ? mapDailyLogCompanion(latestLogs[0])
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
        algorithmVersion:
          privacy.viewPhaseSummary || privacy.viewFertilityEstimate
            ? profile.algorithm_version
            : null,
      },
      estimate,
      fertilityEstimate,
      sharedDailySummary: privacy.viewSharedWellbeing
        ? sharedDailySummary
        : null,
      episodes: privacy.viewCalendarDetail
        ? episodes.map(mapEpisodeCaregiver)
        : [],
      latestSharedDailyLog: privacy.viewSharedWellbeing
        ? canonicalSharedLog
        : null,
      supportActions: privacy.viewSharedWellbeing
        ? actions.map((row: Row) => ({
          actionType: String(row.action_type).toLowerCase(),
          performedAtUtc: iso(row.performed_at_utc),
        }))
        : [],
      guidanceHistory: guidanceHistory.map((row: Row) => ({
        guidanceId: String(row.guidance_id),
        shownAtUtc: iso(row.shown_at_utc),
      })),
    };
  }

  async function recordGuidanceImpression(
    caregiverAppUserId: string,
    patientAppUserIdValue: unknown,
    body: Record<string, unknown>,
  ): Promise<Record<string, unknown>> {
    const patientAppUserId = requiredUuid(
      patientAppUserIdValue,
      "patientUserId",
    );
    const guidanceId = String(body.guidanceId ?? "").trim();
    const contentVersion = String(body.contentVersion ?? "").trim();
    const category = String(body.category ?? "").trim().toLowerCase();
    if (guidanceId.length < 1 || guidanceId.length > 80) {
      throw new ApiError(
        400,
        "invalid_companion_guidance_id",
        "Invalid guidance id.",
      );
    }
    if (contentVersion.length < 1 || contentVersion.length > 40) {
      throw new ApiError(
        400,
        "invalid_companion_content_version",
        "Invalid content version.",
      );
    }
    if (!guidanceCategories.has(category)) {
      throw new ApiError(
        400,
        "invalid_companion_guidance_category",
        "Invalid guidance category.",
      );
    }
    assertNotificationMetadata(guidanceId, contentVersion, category);

    const { caregiverPersonId, patientPersonId } = await resolveCarePeople(
      sql,
      caregiverAppUserId,
      patientAppUserId,
    );
    const relationship = await resolveActiveRelationship(
      caregiverPersonId,
      patientPersonId,
    );
    if (
      guidanceId.startsWith("notify.") &&
      relationship.caregiver_notifications_enabled !== true
    ) {
      throw accessDenied();
    }
    const privacy = companionPrivacy(relationship);
    if (!guidanceAllowed(guidanceId, category, privacy)) throw accessDenied();
    if (guidanceId.startsWith("notify.mood.")) {
      await requireCurrentMoodNotificationEntry(patientPersonId, guidanceId);
    }
    if (guidanceId.startsWith("notify.fertility.")) {
      await requireCurrentFertilityNotificationEstimate(
        patientPersonId,
        guidanceId,
      );
    }

    const rows = await sql`
      insert into lifemate.women_companion_guidance_history
        (relationship_id,patient_person_id,caregiver_person_id,guidance_id,content_version,category)
      values
        (${relationship.id}::uuid,${patientPersonId}::uuid,${caregiverPersonId}::uuid,
         ${guidanceId},${contentVersion},${category})
      on conflict do nothing
      returning id,guidance_id,shown_at_utc
    `;
    if (!rows[0]) {
      throw new ApiError(
        409,
        "companion_notification_duplicate",
        "This companion notification was already recorded.",
      );
    }
    return {
      id: rows[0].id,
      guidanceId: rows[0].guidance_id,
      shownAtUtc: iso(rows[0].shown_at_utc),
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
    const relationship = await resolveActiveRelationship(
      caregiverPersonId,
      patientPersonId,
    );
    if (!companionPrivacy(relationship).viewSharedWellbeing) {
      throw accessDenied();
    }

    const profiles = await sql`
      select owner_person_id from lifemate.women_calendar_profiles
      where owner_person_id=${patientPersonId}::uuid and enabled=true limit 1
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
        (id,caregiver_user_id,relationship_id,action_type,performed_at_utc,created_at_utc,patient_person_id)
      values
        (${id}::uuid,${caregiverAppUserId}::uuid,${relationship.id}::uuid,
         ${actionType},${now},${now},${patientPersonId}::uuid)
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
    recordGuidanceImpression,
    recordCareSupportAction,
  };
}

export { createPersonWomenCalendarCaregiverStore as createPersonWomenCalendarStore };

type CompanionPrivacy = {
  viewPeriodTiming: boolean;
  viewPhaseSummary: boolean;
  viewSharedWellbeing: boolean;
  receiveMoodSupportNotifications: boolean;
  receivePhaseNotifications: boolean;
  viewFertilityEstimate: boolean;
  receiveFertilityNotifications: boolean;
  viewCalendarDetail: boolean;
};

function companionPrivacy(row: Row): CompanionPrivacy {
  return {
    viewPeriodTiming: row.view_period_timing === true,
    viewPhaseSummary: row.view_phase_summary === true,
    viewSharedWellbeing: row.view_shared_wellbeing === true,
    receiveMoodSupportNotifications:
      row.receive_mood_support_notifications === true,
    receivePhaseNotifications: row.receive_phase_notifications === true,
    viewFertilityEstimate: row.view_fertility_estimate === true,
    receiveFertilityNotifications: row.receive_fertility_notifications === true,
    viewCalendarDetail: row.view_calendar_detail === true,
  };
}

export function guidanceAllowed(
  guidanceId: string,
  category: string,
  privacy: CompanionPrivacy,
): boolean {
  if (guidanceId.startsWith("notify.phase.period_start.")) {
    return privacy.receivePhaseNotifications &&
      privacy.viewPhaseSummary &&
      privacy.viewPeriodTiming;
  }
  if (guidanceId.startsWith("notify.phase.")) {
    return privacy.receivePhaseNotifications && privacy.viewPhaseSummary;
  }
  if (guidanceId.startsWith("notify.mood.")) {
    return privacy.receiveMoodSupportNotifications &&
      privacy.viewSharedWellbeing;
  }
  if (guidanceId.startsWith("notify.fertility.")) {
    return privacy.viewFertilityEstimate &&
      privacy.receiveFertilityNotifications;
  }
  if (category === "fertility") return privacy.viewFertilityEstimate;
  if (category === "phase") return privacy.viewPhaseSummary;
  if (category === "mood" || category === "energy") {
    return privacy.viewSharedWellbeing;
  }
  return privacy.viewPhaseSummary || privacy.viewSharedWellbeing;
}

export function assertNotificationMetadata(
  guidanceId: string,
  contentVersion: string,
  category: string,
): void {
  if (guidanceId.startsWith("notify.phase.")) {
    if (
      category !== "phase" || contentVersion !== phaseNotificationContentVersion
    ) {
      throw invalidNotificationMetadata("Phase");
    }
    return;
  }
  if (guidanceId.startsWith("notify.mood.")) {
    if (
      category !== "mood" || contentVersion !== moodNotificationContentVersion
    ) {
      throw invalidNotificationMetadata("Wellbeing");
    }
    return;
  }
  if (guidanceId.startsWith("notify.fertility.")) {
    if (
      category !== "fertility" ||
      contentVersion !== fertilityNotificationContentVersion
    ) {
      throw invalidNotificationMetadata("Fertility");
    }
    return;
  }
  if (guidanceId.startsWith("notify.")) {
    throw invalidNotificationMetadata("Companion");
  }
}

function invalidNotificationMetadata(kind: string): ApiError {
  return new ApiError(
    400,
    "invalid_companion_notification_metadata",
    `${kind} notification metadata is invalid.`,
  );
}

export function presentCycleEstimate(
  estimate: any,
  privacy: CompanionPrivacy,
): Record<string, unknown> | null {
  const result: Record<string, unknown> = {};
  if (privacy.viewPhaseSummary) {
    const detailed = String(
      estimate.detailedPhase ?? estimate.phase ?? "cycle",
    );
    result.phase = estimate.phase;
    result.detailedPhase = !privacy.viewFertilityEstimate &&
        (detailed === "fertile" || detailed === "ovulation")
      ? "follicular"
      : detailed;
    result.confidence = estimate.confidence;
    result.cyclePattern = estimate.cyclePattern;
    result.algorithmVersion = estimate.algorithmVersion;
  }
  if (privacy.viewPeriodTiming) {
    result.cycleStart = estimate.cycleStart;
    result.cycleDay = estimate.cycleDay;
    result.estimatedBleeding = estimate.estimatedBleeding;
    result.nextPeriodStart = estimate.nextPeriodStart;
    result.daysUntilNextPeriod = estimate.daysUntilNextPeriod;
  }
  if (privacy.viewCalendarDetail) {
    result.cycleLength = estimate.cycleLength;
    result.periodLength = estimate.periodLength;
    result.pmsStartDay = estimate.pmsStartDay;
  }
  return Object.keys(result).length === 0 ? null : result;
}

export function presentFertilityEstimate(
  estimate: any,
  privacy: CompanionPrivacy,
): Record<string, unknown> | null {
  if (!privacy.viewFertilityEstimate) return null;
  const cycleDay = Number(estimate.cycleDay);
  const windowStartDay = Number(estimate.fertileWindowStartDay);
  const windowEndDay = Number(estimate.fertileWindowEndDay);
  const ovulationDay = estimate.ovulationDay == null
    ? null
    : Number(estimate.ovulationDay);
  const reliable = estimate.fertilityEstimateReliable === true &&
    String(estimate.cyclePattern).toLowerCase() === "regular" &&
    String(estimate.confidence).toLowerCase() !== "low" &&
    Number.isFinite(cycleDay) &&
    Number.isFinite(windowStartDay) &&
    Number.isFinite(windowEndDay) &&
    windowStartDay >= 1 &&
    windowEndDay >= windowStartDay;
  if (!reliable) {
    return {
      state: "unavailable",
      estimatedWindowStartOn: null,
      estimatedWindowEndOn: null,
      estimatedOvulationOn: null,
      fertilityEstimateReliable: false,
      confidence: estimate.confidence,
      cyclePattern: estimate.cyclePattern,
      algorithmVersion: estimate.algorithmVersion,
    };
  }
  const cycleStart = dateString(estimate.cycleStart);
  return {
    state: cycleDay >= windowStartDay && cycleDay <= windowEndDay
      ? "inside_estimated_window"
      : "outside_estimated_window",
    estimatedWindowStartOn: addDays(cycleStart, windowStartDay - 1),
    estimatedWindowEndOn: addDays(cycleStart, windowEndDay - 1),
    estimatedOvulationOn: ovulationDay != null && Number.isFinite(ovulationDay)
      ? addDays(cycleStart, ovulationDay - 1)
      : null,
    fertilityEstimateReliable: true,
    confidence: estimate.confidence,
    cyclePattern: estimate.cyclePattern,
    algorithmVersion: estimate.algorithmVersion,
  };
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
  // Intentionally narrow: private_notes, pain_level and symptoms are never
  // projected into the companion payload or notification engine.
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
      (id,actor_user_id,action,resource_type,resource_id,metadata_json,created_at_utc)
    values
      (${crypto.randomUUID()}::uuid,${actorAppUserId}::uuid,${action},
       ${resourceType},${resourceId}::uuid,null,now())
  `;
}

function addDays(value: string, days: number): string {
  const parsed = new Date(`${value}T00:00:00.000Z`);
  parsed.setUTCDate(parsed.getUTCDate() + days);
  return parsed.toISOString().slice(0, 10);
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
