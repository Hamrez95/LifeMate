import { getLifeMateSql } from "./database_client.ts";
import {
  ApiError,
  limitedOptional,
  requiredDate,
  requiredPositiveInt,
  requiredUuid,
  validateRange,
} from "./validation.ts";

type Row = Record<string, any>;

type DailyCheckIn = {
  date: string;
  mood: "Great" | "Good" | "Neutral" | "Low" | "Overwhelmed";
  energy: number;
  symptoms: string[];
  supportNeed: "None" | "Rest" | "Talk" | "Space" | "Warmth" | "Walk" | "Hug";
  privateNote: string | null;
  shareSummary: boolean;
};

const supportedSymptoms = new Set([
  "cramps",
  "headache",
  "bloating",
  "fatigue",
  "breast_tenderness",
  "back_pain",
  "sleep_change",
  "appetite_change",
]);

type DetailedPhase =
  | "period"
  | "follicular"
  | "fertile"
  | "ovulation"
  | "luteal"
  | "pms";

export type WomenCalendarEstimate = {
  cycleStart: string;
  cycleDay: number;
  cycleLength: number;
  periodLength: number;
  estimatedBleeding: boolean;
  phase: "period" | "post_period" | "cycle" | "pre_period";
  detailedPhase: DetailedPhase;
  ovulationDay: number;
  fertileWindowStartDay: number;
  fertileWindowEndDay: number;
  pmsStartDay: number;
  nextPeriodStart: string;
  daysUntilNextPeriod: number;
  algorithmVersion: "calendar-estimate-v1";
  confidence: "low" | "medium" | "high";
  cyclePattern: "insufficient_data" | "regular" | "variable";
  fertilityEstimateReliable: boolean;
};

const allowedMoods: Record<string, string> = {
  great: "Great",
  good: "Good",
  neutral: "Neutral",
  low: "Low",
  overwhelmed: "Overwhelmed",
};

const allowedSymptoms: Record<string, string> = {
  cramps: "Cramps",
  headache: "Headache",
  bloating: "Bloating",
  fatigue: "Fatigue",
  breast_tenderness: "BreastTenderness",
  back_pain: "BackPain",
  sleep_change: "SleepChange",
  appetite_change: "AppetiteChange",
  no_symptom: "NoSymptom",
};

export function createWomenCalendarStore(databaseUrl: string) {
  const sql = getLifeMateSql(databaseUrl);

  async function getOwnerProfile(
    userId: string,
  ): Promise<Record<string, unknown>> {
    const rows = await sql`
      select * from lifemate.women_calendar_profiles
      where owner_user_id = ${userId}
      limit 1
    `;
    return rows[0] ? mapProfile(rows[0]) : defaultProfile(userId);
  }

  async function updateOwnerProfile(
    userId: string,
    body: Record<string, unknown>,
  ): Promise<Record<string, unknown>> {
    const enabled = requiredBoolean(body.enabled, "enabled");
    const lastPeriodStart = body.lastPeriodStart == null
      ? null
      : requiredDate(body.lastPeriodStart, "lastPeriodStart");
    const cycleLength = boundedInt(body.cycleLength, "cycleLength", 21, 45);
    const periodLength = boundedInt(body.periodLength, "periodLength", 1, 10);
    if (periodLength >= cycleLength) {
      throw new ApiError(
        400,
        "invalid_women_calendar_profile",
        "periodLength must be shorter than cycleLength.",
      );
    }
    if (enabled && lastPeriodStart == null) {
      throw new ApiError(
        400,
        "last_period_start_required",
        "lastPeriodStart is required when the profile is enabled.",
      );
    }
    const remindersEnabled = requiredBoolean(
      body.remindersEnabled,
      "remindersEnabled",
    );
    const expectedVersion = nonNegativeInt(body.version, "version");
    assertCanonicalWomenDailyLogPayload(body);
    const now = new Date();

    return await sql.begin(async (tx: any) => {
      const existingRows = await tx`
        select * from lifemate.women_calendar_profiles
        where owner_user_id = ${userId}
        for update
      `;
      const existing = existingRows[0];
      if (!existing) {
        if (expectedVersion !== 0) {
          throw staleProfile();
        }
        const rows = await tx`
          insert into lifemate.women_calendar_profiles
            (owner_user_id, enabled, last_period_start, cycle_length,
             period_length, reminders_enabled, algorithm_version, version,
             created_at_utc, updated_at_utc)
          values
            (${userId}, ${enabled}, ${lastPeriodStart}, ${cycleLength},
             ${periodLength}, ${remindersEnabled}, 'calendar-estimate-v1', 1,
             ${now}, ${now})
          returning *
        `;
        await insertAudit(
          tx,
          userId,
          "women_calendar.profile_created",
          "women_calendar_profile",
          userId,
        );
        return mapProfile(rows[0]);
      }
      if (existing.version !== expectedVersion) {
        throw staleProfile();
      }

      const rows = await tx`
        update lifemate.women_calendar_profiles
        set enabled = ${enabled}, last_period_start = ${lastPeriodStart},
            cycle_length = ${cycleLength}, period_length = ${periodLength},
            reminders_enabled = ${remindersEnabled},
            version = version + 1, updated_at_utc = ${now}
        where owner_user_id = ${userId}
        returning *
      `;
      await insertAudit(
        tx,
        userId,
        enabled
          ? "women_calendar.profile_enabled_or_updated"
          : "women_calendar.profile_disabled",
        "women_calendar_profile",
        userId,
      );
      return mapProfile(rows[0]);
    });
  }

  async function listOwnerEpisodes(
    userId: string,
  ): Promise<Record<string, unknown>[]> {
    const rows = await sql`
      select * from lifemate.women_calendar_episodes
      where owner_user_id = ${userId}
      order by started_on desc, id
      limit 100
    `;
    return rows.map(mapEpisodeOwner);
  }

  async function createOwnerEpisode(
    userId: string,
    body: Record<string, unknown>,
  ): Promise<Record<string, unknown>> {
    const startedOn = requiredDate(body.startedOn, "startedOn");
    const endedOn = body.endedOn == null
      ? null
      : requiredDate(body.endedOn, "endedOn");
    if (endedOn != null && endedOn < startedOn) {
      throw new ApiError(
        400,
        "invalid_women_calendar_episode",
        "endedOn cannot precede startedOn.",
      );
    }
    const privateNotes = limitedOptional(
      body.privateNotes,
      "privateNotes",
      500,
    );
    const endBoundary = endedOn ?? startedOn;
    const now = new Date();

    return await sql.begin(async (tx: any) => {
      const overlaps = await tx`
        select id from lifemate.women_calendar_episodes
        where owner_user_id = ${userId}
          and started_on <= ${endBoundary}::date
          and coalesce(ended_on, started_on) >= ${startedOn}::date
        limit 1
      `;
      if (overlaps[0]) {
        throw new ApiError(
          409,
          "women_calendar_episode_overlap",
          "Period episode overlaps an existing episode.",
        );
      }
      const id = crypto.randomUUID();
      const rows = await tx`
        insert into lifemate.women_calendar_episodes
          (id, owner_user_id, started_on, ended_on, private_notes, version,
           created_at_utc, updated_at_utc)
        values
          (${id}, ${userId}, ${startedOn}, ${endedOn}, ${privateNotes}, 1,
           ${now}, ${now})
        returning *
      `;
      await tx`
        update lifemate.women_calendar_profiles
        set last_period_start = case
              when last_period_start is null or last_period_start < ${startedOn}::date
                then ${startedOn}::date
              else last_period_start
            end,
            version = version + 1,
            updated_at_utc = ${now}
        where owner_user_id = ${userId}
      `;
      await insertAudit(
        tx,
        userId,
        "women_calendar.episode_created",
        "women_calendar_episode",
        id,
      );
      return mapEpisodeOwner(rows[0]);
    });
  }

  async function updateOwnerEpisode(
    userId: string,
    episodeIdValue: unknown,
    body: Record<string, unknown>,
  ): Promise<Record<string, unknown>> {
    const episodeId = requiredUuid(episodeIdValue, "episodeId");
    const expectedVersion = requiredPositiveInt(body.version, "version");
    const startedOn = requiredDate(body.startedOn, "startedOn");
    const endedOn = body.endedOn == null
      ? null
      : requiredDate(body.endedOn, "endedOn");
    if (endedOn != null && endedOn < startedOn) {
      throw new ApiError(
        400,
        "invalid_women_calendar_episode",
        "endedOn cannot precede startedOn.",
      );
    }
    const privateNotes = limitedOptional(
      body.privateNotes,
      "privateNotes",
      500,
    );
    const endBoundary = endedOn ?? startedOn;

    return await sql.begin(async (tx: any) => {
      const existingRows = await tx`
        select * from lifemate.women_calendar_episodes
        where id = ${episodeId} and owner_user_id = ${userId}
        for update
      `;
      const existing = existingRows[0];
      if (!existing) {
        throw new ApiError(
          404,
          "women_calendar_episode_not_found",
          "Episode not found.",
        );
      }
      if (existing.version !== expectedVersion) {
        throw new ApiError(
          409,
          "stale_women_calendar_episode",
          "Period episode changed. Refresh and try again.",
        );
      }
      const overlaps = await tx`
        select id from lifemate.women_calendar_episodes
        where owner_user_id = ${userId}
          and id <> ${episodeId}
          and started_on <= ${endBoundary}::date
          and coalesce(ended_on, started_on) >= ${startedOn}::date
        limit 1
      `;
      if (overlaps[0]) {
        throw new ApiError(
          409,
          "women_calendar_episode_overlap",
          "Period episode overlaps an existing episode.",
        );
      }
      const rows = await tx`
        update lifemate.women_calendar_episodes
        set started_on = ${startedOn}, ended_on = ${endedOn},
            private_notes = ${privateNotes}, version = version + 1,
            updated_at_utc = now()
        where id = ${episodeId}
        returning *
      `;
      await tx`
        update lifemate.women_calendar_profiles
        set last_period_start = case
              when last_period_start = ${dateString(existing.started_on)}::date
                then ${startedOn}::date
              else last_period_start
            end,
            version = version + 1,
            updated_at_utc = now()
        where owner_user_id = ${userId}
      `;
      await insertAudit(
        tx,
        userId,
        "women_calendar.episode_updated",
        "women_calendar_episode",
        episodeId,
      );
      return mapEpisodeOwner(rows[0]);
    });
  }

  async function deleteOwnerEpisode(
    userId: string,
    episodeIdValue: unknown,
  ): Promise<void> {
    const episodeId = requiredUuid(episodeIdValue, "episodeId");
    await sql.begin(async (tx: any) => {
      const rows = await tx`
        delete from lifemate.women_calendar_episodes
        where id = ${episodeId} and owner_user_id = ${userId}
        returning id, started_on
      `;
      if (!rows[0]) {
        throw new ApiError(
          404,
          "women_calendar_episode_not_found",
          "Episode not found.",
        );
      }
      await tx`
        update lifemate.women_calendar_profiles
        set last_period_start = case
              when last_period_start = ${dateString(rows[0].started_on)}::date
                then coalesce(
              (
                select max(started_on)
                from lifemate.women_calendar_episodes
                where owner_user_id = ${userId}
              ),
              last_period_start
            )
              else last_period_start
            end,
            version = version + 1,
            updated_at_utc = now()
        where owner_user_id = ${userId}
      `;
      await insertAudit(
        tx,
        userId,
        "women_calendar.episode_deleted",
        "women_calendar_episode",
        episodeId,
      );
    });
  }

  async function listOwnerDailyLogs(
    userId: string,
    fromValue: unknown,
    toValue: unknown,
  ): Promise<Record<string, unknown>[]> {
    const fromDate = requiredDate(fromValue, "fromDate");
    const toDate = requiredDate(toValue, "toDate");
    validateRange(fromDate, toDate, 90);
    const rows = await sql`
      select * from lifemate.women_calendar_daily_logs
      where owner_user_id = ${userId}
        and logged_on between ${fromDate}::date and ${toDate}::date
      order by logged_on desc, id
      limit 180
    `;
    return rows.map(mapDailyLogOwner);
  }

  async function upsertOwnerDailyLog(
    userId: string,
    body: Record<string, unknown>,
  ): Promise<Record<string, unknown>> {
    const expectedVersion = nonNegativeInt(body.version, "version");
    const loggedOn = requiredDate(body.loggedOn, "loggedOn");
    const mood = normalizeMood(body.mood);
    const energyLevel = boundedInt(body.energyLevel, "energyLevel", 1, 5);
    const painLevel = boundedInt(body.painLevel, "painLevel", 0, 5);
    const symptoms = normalizeSymptoms(body.symptoms);
    const privateNotes = limitedOptional(
      body.privateNotes,
      "privateNotes",
      500,
    );
    const shareSummaryWithCompanion = requiredBoolean(
      body.shareSummaryWithCompanion,
      "shareSummaryWithCompanion",
    );
    const now = new Date();

    return await sql.begin(async (tx: any) => {
      const existingRows = await tx`
        select * from lifemate.women_calendar_daily_logs
        where owner_user_id = ${userId} and logged_on = ${loggedOn}::date
        for update
      `;
      const existing = existingRows[0];
      let row: Row;
      if (!existing) {
        if (expectedVersion !== 0) throw staleDailyLog();
        const id = crypto.randomUUID();
        const rows = await tx`
          insert into lifemate.women_calendar_daily_logs
            (id, owner_user_id, logged_on, mood, energy_level, pain_level,
             symptoms, private_notes, share_summary_with_companion, version,
             created_at_utc, updated_at_utc)
          values
            (${id}, ${userId}, ${loggedOn}, ${mood}, ${energyLevel},
             ${painLevel}, ${symptoms}, ${privateNotes},
             ${shareSummaryWithCompanion}, 1, ${now}, ${now})
          returning *
        `;
        row = rows[0];
        await insertAudit(
          tx,
          userId,
          "women_calendar.daily_log_created",
          "women_calendar_daily_log",
          id,
        );
      } else {
        if (existing.version !== expectedVersion) throw staleDailyLog();
        const rows = await tx`
          update lifemate.women_calendar_daily_logs
          set mood = ${mood}, energy_level = ${energyLevel},
              pain_level = ${painLevel}, symptoms = ${symptoms},
              private_notes = ${privateNotes},
              share_summary_with_companion = ${shareSummaryWithCompanion},
              version = version + 1, updated_at_utc = ${now}
          where id = ${existing.id}
          returning *
        `;
        row = rows[0];
        await insertAudit(
          tx,
          userId,
          "women_calendar.daily_log_updated",
          "women_calendar_daily_log",
          existing.id,
        );
      }
      return mapDailyLogOwner(row);
    });
  }

  async function getCareSummary(
    caregiverUserId: string,
    patientUserIdValue: unknown,
  ): Promise<Record<string, unknown>> {
    const patientUserId = requiredUuid(patientUserIdValue, "patientUserId");
    const relationshipRows = await sql`
      select id from lifemate.care_relationships
      where patient_user_id = ${patientUserId}
        and caregiver_user_id = ${caregiverUserId}
        and status = 'Active'
        and can_view_women_calendar = true
      limit 1
    `;
    if (!relationshipRows[0]) {
      throw new ApiError(
        403,
        "women_calendar_access_denied",
        "Women calendar access is not active.",
      );
    }
    const profiles = await sql`
      select * from lifemate.women_calendar_profiles
      where owner_user_id = ${patientUserId} and enabled = true
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
      select display_name, avatar_key
      from lifemate.user_profiles
      where user_id = ${patientUserId}
      limit 1
    `;
    const episodes = await sql`
      select id, started_on, ended_on, version, created_at_utc, updated_at_utc
      from lifemate.women_calendar_episodes
      where owner_user_id = ${patientUserId}
      order by started_on desc, id
      limit 12
    `;
    const actions = await sql`
      select action_type, performed_at_utc
      from lifemate.women_calendar_support_actions
      where patient_user_id = ${patientUserId}
      order by performed_at_utc desc, id
      limit 20
    `;
    const sharedLogs = await sql`
      select logged_on, mood, energy_level, pain_level, symptoms, version,
             updated_at_utc
      from lifemate.women_calendar_daily_logs
      where owner_user_id = ${patientUserId}
        and share_summary_with_companion = true
        and logged_on >= current_date - interval '14 days'
      order by logged_on desc, id
      limit 1
    `;
    const profile = mapProfile(profiles[0]);
    const estimate = calculateWomenCalendarEstimateFromEpisodes(
      dateString(profiles[0].last_period_start),
      profiles[0].cycle_length,
      profiles[0].period_length,
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
        lastPeriodStart: profile.lastPeriodStart,
        cycleLength: profile.cycleLength,
        periodLength: profile.periodLength,
        algorithmVersion: profile.algorithmVersion,
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
    caregiverUserId: string,
    patientUserIdValue: unknown,
    body: Record<string, unknown>,
  ): Promise<Record<string, unknown>> {
    const patientUserId = requiredUuid(patientUserIdValue, "patientUserId");
    const normalized = String(body.actionType ?? "").trim().toLowerCase();
    const actionType = ({
      hydration: "Hydration",
      rest: "Rest",
      warmth: "Warmth",
      chores: "Chores",
      walk: "Walk",
      check_in: "CheckIn",
    } as Record<string, string>)[normalized];
    if (!actionType) {
      throw new ApiError(
        400,
        "invalid_women_calendar_support_action",
        "Unsupported support action.",
      );
    }
    const relationshipRows = await sql`
      select id from lifemate.care_relationships
      where patient_user_id = ${patientUserId}
        and caregiver_user_id = ${caregiverUserId}
        and status = 'Active'
        and can_view_women_calendar = true
      limit 1
    `;
    if (!relationshipRows[0]) {
      throw new ApiError(
        403,
        "women_calendar_access_denied",
        "Women calendar access is not active.",
      );
    }
    const profiles = await sql`
      select owner_user_id from lifemate.women_calendar_profiles
      where owner_user_id = ${patientUserId} and enabled = true
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
        (id, patient_user_id, caregiver_user_id, relationship_id,
         action_type, performed_at_utc, created_at_utc)
      values
        (${id}, ${patientUserId}, ${caregiverUserId}, ${relationshipRows[0].id},
         ${actionType}, ${now}, ${now})
      returning *
    `;
    await insertAudit(
      sql,
      caregiverUserId,
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
    getOwnerProfile,
    updateOwnerProfile,
    listOwnerEpisodes,
    createOwnerEpisode,
    updateOwnerEpisode,
    deleteOwnerEpisode,
    listOwnerDailyLogs,
    upsertOwnerDailyLog,
    getCareSummary,
    recordCareSupportAction,
  };
}

export function assertCanonicalWomenDailyLogPayload(
  body: Record<string, unknown>,
): void {
  if (Object.prototype.hasOwnProperty.call(body, "dailyCheckIn")) {
    throw new ApiError(
      400,
      "women_calendar_daily_log_endpoint_required",
      "Daily wellbeing state must use /api/v1/women-calendar/daily-logs.",
    );
  }
}

export function calculateWomenCalendarEstimate(
  lastPeriodStart: string,
  cycleLength: number,
  periodLength: number,
  todayValue = new Date(),
): WomenCalendarEstimate {
  return calculateCalendarCore(
    lastPeriodStart,
    cycleLength,
    periodLength,
    todayValue,
    "low",
    "insufficient_data",
    false,
  );
}

export function calculateWomenCalendarEstimateFromEpisodes(
  lastPeriodStart: string,
  configuredCycleLength: number,
  periodLength: number,
  periodStarts: string[],
  todayValue = new Date(),
): WomenCalendarEstimate {
  const assessment = assessCycleHistory(periodStarts, configuredCycleLength);
  const reliable =
    assessment.pattern === "regular" && assessment.confidence !== "low";
  return calculateCalendarCore(
    lastPeriodStart,
    assessment.representativeCycleLength,
    periodLength,
    todayValue,
    assessment.confidence,
    assessment.pattern,
    reliable,
  );
}

function calculateCalendarCore(
  lastPeriodStart: string,
  cycleLength: number,
  periodLength: number,
  todayValue: Date,
  confidence: "low" | "medium" | "high",
  cyclePattern: "insufficient_data" | "regular" | "variable",
  fertilityEstimateReliable: boolean,
): WomenCalendarEstimate {
  const start = parseDateOnly(lastPeriodStart);
  const today = new Date(Date.UTC(
    todayValue.getUTCFullYear(),
    todayValue.getUTCMonth(),
    todayValue.getUTCDate(),
  ));
  const rawDiff = Math.floor((today.getTime() - start.getTime()) / 86_400_000);
  const cyclesElapsed = rawDiff < 0 ? 0 : Math.floor(rawDiff / cycleLength);
  let cycleStart = addDays(start, cyclesElapsed * cycleLength);
  if (cycleStart > today) cycleStart = start;
  const cycleDay = Math.max(
    1,
    Math.floor((today.getTime() - cycleStart.getTime()) / 86_400_000) + 1,
  );
  const nextPeriodStart = addDays(cycleStart, cycleLength);
  const daysUntilNextPeriod = Math.max(
    0,
    Math.floor((nextPeriodStart.getTime() - today.getTime()) / 86_400_000),
  );
  const ovulationDay = clamp(
    cycleLength - 14,
    periodLength + 2,
    cycleLength - 5,
  );
  const fertileWindowStartDay = clamp(
    ovulationDay - 5,
    periodLength + 1,
    ovulationDay,
  );
  const fertileWindowEndDay = clamp(
    ovulationDay + 1,
    ovulationDay,
    cycleLength,
  );
  const pmsStartDay = clamp(
    cycleLength - 4,
    fertileWindowEndDay + 1,
    cycleLength,
  );
  const rawDetailedPhase = phaseForCycleDay(
    cycleDay,
    periodLength,
    ovulationDay,
    fertileWindowStartDay,
    fertileWindowEndDay,
    pmsStartDay,
  );
  const detailedPhase: DetailedPhase = !fertilityEstimateReliable &&
      (rawDetailedPhase === "fertile" || rawDetailedPhase === "ovulation")
    ? (cycleDay <= ovulationDay ? "follicular" : "luteal")
    : rawDetailedPhase;
  const estimatedBleeding = detailedPhase === "period";
  const phase = detailedPhase === "period"
    ? "period"
    : detailedPhase === "follicular"
    ? "post_period"
    : detailedPhase === "pms"
    ? "pre_period"
    : "cycle";
  return {
    cycleStart: formatDateOnly(cycleStart),
    cycleDay,
    cycleLength,
    periodLength,
    estimatedBleeding,
    phase,
    detailedPhase,
    ovulationDay,
    fertileWindowStartDay,
    fertileWindowEndDay,
    pmsStartDay,
    nextPeriodStart: formatDateOnly(nextPeriodStart),
    daysUntilNextPeriod,
    algorithmVersion: "calendar-estimate-v1",
    confidence,
    cyclePattern,
    fertilityEstimateReliable,
  };
}

function assessCycleHistory(
  periodStarts: string[],
  configuredCycleLength: number,
): {
  pattern: "insufficient_data" | "regular" | "variable";
  confidence: "low" | "medium" | "high";
  representativeCycleLength: number;
} {
  const starts = Array.from(new Set(periodStarts))
    .map(parseDateOnly)
    .sort((a, b) => a.getTime() - b.getTime());
  const intervals: number[] = [];
  for (let index = 1; index < starts.length; index++) {
    const days = Math.round(
      (starts[index].getTime() - starts[index - 1].getTime()) / 86_400_000,
    );
    if (days >= 15 && days <= 90) intervals.push(days);
  }
  if (intervals.length < 2) {
    return {
      pattern: "insufficient_data",
      confidence: "low",
      representativeCycleLength: configuredCycleLength,
    };
  }
  const usable = intervals.filter((value) => value >= 21 && value <= 45);
  const source = usable.length === 0 ? intervals : usable;
  const sorted = [...source].sort((a, b) => a - b);
  const middle = Math.floor(sorted.length / 2);
  const representativeCycleLength = sorted.length % 2 === 1
    ? sorted[middle]
    : Math.round((sorted[middle - 1] + sorted[middle]) / 2);
  const minimum = Math.min(...intervals);
  const maximum = Math.max(...intervals);
  const spread = maximum - minimum;
  const variable = spread > 7 || intervals.some((value) => value < 21 || value > 45);
  if (variable) {
    return {
      pattern: "variable",
      confidence: "low",
      representativeCycleLength: clamp(representativeCycleLength, 21, 45),
    };
  }
  return {
    pattern: "regular",
    confidence: intervals.length >= 3 && spread <= 4 ? "high" : "medium",
    representativeCycleLength,
  };
}

function mapProfile(row: Row): Record<string, any> {
  const lastPeriodStart = row.last_period_start == null
    ? null
    : dateString(row.last_period_start);
  return {
    ownerUserId: row.owner_user_id,
    enabled: row.enabled,
    lastPeriodStart,
    cycleLength: row.cycle_length,
    periodLength: row.period_length,
    remindersEnabled: row.reminders_enabled,
    algorithmVersion: row.algorithm_version,
    version: row.version,
    estimate: row.enabled && lastPeriodStart != null
      ? calculateWomenCalendarEstimate(
        lastPeriodStart,
        row.cycle_length,
        row.period_length,
      )
      : null,
    dailyCheckIn: null,
    createdAtUtc: iso(row.created_at_utc),
    updatedAtUtc: iso(row.updated_at_utc),
  };
}

function defaultProfile(userId: string): Record<string, unknown> {
  return {
    ownerUserId: userId,
    enabled: false,
    lastPeriodStart: null,
    cycleLength: 28,
    periodLength: 5,
    remindersEnabled: true,
    algorithmVersion: "calendar-estimate-v1",
    version: 0,
    estimate: null,
    dailyCheckIn: null,
    createdAtUtc: null,
    updatedAtUtc: null,
  };
}

function dailyCheckInFromRow(row: Row): DailyCheckIn | null {
  if (row.daily_check_in_date == null || row.daily_mood == null) return null;
  const rawSymptoms = Array.isArray(row.daily_symptoms)
    ? row.daily_symptoms
    : [];
  return {
    date: dateString(row.daily_check_in_date),
    mood: String(row.daily_mood) as DailyCheckIn["mood"],
    energy: Number(row.daily_energy ?? 3),
    symptoms: rawSymptoms.map((value: unknown) => String(value).toLowerCase()),
    supportNeed: String(
      row.daily_support_need ?? "None",
    ) as DailyCheckIn["supportNeed"],
    privateNote: row.daily_private_note == null
      ? null
      : String(row.daily_private_note),
    shareSummary: row.share_daily_summary === true,
  };
}

function parseDailyCheckIn(value: unknown): DailyCheckIn | null {
  if (value == null) return null;
  if (typeof value !== "object" || Array.isArray(value)) {
    throw new ApiError(
      400,
      "invalid_women_calendar_daily_check_in",
      "dailyCheckIn must be an object or null.",
    );
  }
  const object = value as Record<string, unknown>;
  const date = requiredDate(object.date, "dailyCheckIn.date");
  const moodMap: Record<string, DailyCheckIn["mood"]> = {
    great: "Great",
    good: "Good",
    neutral: "Neutral",
    low: "Low",
    overwhelmed: "Overwhelmed",
  };
  const mood = moodMap[String(object.mood ?? "").trim().toLowerCase()];
  if (!mood) {
    throw new ApiError(
      400,
      "invalid_women_calendar_mood",
      "Unsupported mood value.",
    );
  }
  const energy = boundedInt(object.energy, "dailyCheckIn.energy", 1, 5);
  const rawSymptoms = object.symptoms ?? [];
  if (!Array.isArray(rawSymptoms)) {
    throw new ApiError(
      400,
      "invalid_women_calendar_symptoms",
      "dailyCheckIn.symptoms must be an array.",
    );
  }
  const symptoms = [
    ...new Set(
      rawSymptoms.map((item) => String(item).trim().toLowerCase()),
    ),
  ];
  if (
    symptoms.length > 8 || symptoms.some((item) => !supportedSymptoms.has(item))
  ) {
    throw new ApiError(
      400,
      "invalid_women_calendar_symptoms",
      "Unsupported or excessive symptom values.",
    );
  }
  const supportMap: Record<string, DailyCheckIn["supportNeed"]> = {
    none: "None",
    rest: "Rest",
    talk: "Talk",
    space: "Space",
    warmth: "Warmth",
    walk: "Walk",
    hug: "Hug",
  };
  const supportNeed = supportMap[
    String(object.supportNeed ?? "none").trim().toLowerCase()
  ];
  if (!supportNeed) {
    throw new ApiError(
      400,
      "invalid_women_calendar_support_need",
      "Unsupported support need.",
    );
  }
  return {
    date,
    mood,
    energy,
    symptoms,
    supportNeed,
    privateNote: limitedOptional(
      object.privateNote,
      "dailyCheckIn.privateNote",
      500,
    ),
    shareSummary: object.shareSummary == null
      ? false
      : requiredBoolean(object.shareSummary, "dailyCheckIn.shareSummary"),
  };
}

function mapEpisodeOwner(row: Row): Record<string, unknown> {
  return {
    id: row.id,
    startedOn: dateString(row.started_on),
    endedOn: row.ended_on == null ? null : dateString(row.ended_on),
    privateNotes: row.private_notes,
    version: row.version,
    createdAtUtc: iso(row.created_at_utc),
    updatedAtUtc: iso(row.updated_at_utc),
  };
}

function mapEpisodeCaregiver(row: Row): Record<string, unknown> {
  return {
    id: row.id,
    startedOn: dateString(row.started_on),
    endedOn: row.ended_on == null ? null : dateString(row.ended_on),
    version: row.version,
  };
}

function mapDailyLogOwner(row: Row): Record<string, unknown> {
  return {
    id: row.id,
    loggedOn: dateString(row.logged_on),
    mood: String(row.mood).toLowerCase(),
    energyLevel: row.energy_level,
    painLevel: row.pain_level,
    symptoms: normalizeStoredSymptoms(row.symptoms),
    privateNotes: row.private_notes,
    shareSummaryWithCompanion: row.share_summary_with_companion === true,
    version: row.version,
    createdAtUtc: iso(row.created_at_utc),
    updatedAtUtc: iso(row.updated_at_utc),
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

async function insertAudit(
  connection: any,
  actorUserId: string,
  action: string,
  resourceType: string,
  resourceId: string,
): Promise<void> {
  await connection`
    insert into lifemate.audit_logs
      (id, actor_user_id, action, resource_type, resource_id,
       metadata_json, created_at_utc)
    values
      (${crypto.randomUUID()}, ${actorUserId}, ${action}, ${resourceType},
       ${resourceId}, null, now())
  `;
}

function staleProfile(): ApiError {
  return new ApiError(
    409,
    "stale_women_calendar_profile",
    "Women calendar profile changed. Refresh and try again.",
  );
}

function staleDailyLog(): ApiError {
  return new ApiError(
    409,
    "stale_women_calendar_daily_log",
    "Daily log changed. Refresh and try again.",
  );
}

function requiredBoolean(value: unknown, field: string): boolean {
  if (typeof value !== "boolean") {
    throw new ApiError(400, "invalid_boolean", `${field} must be a boolean.`);
  }
  return value;
}

function boundedInt(
  value: unknown,
  field: string,
  min: number,
  max: number,
): number {
  const number = Number(value);
  if (!Number.isInteger(number) || number < min || number > max) {
    throw new ApiError(400, "invalid_integer", `${field} is out of range.`);
  }
  return number;
}

function nonNegativeInt(value: unknown, field: string): number {
  const number = Number(value);
  if (!Number.isInteger(number) || number < 0) {
    throw new ApiError(
      400,
      "invalid_integer",
      `${field} must be non-negative.`,
    );
  }
  return number;
}

function normalizeMood(value: unknown): string {
  const normalized = String(value ?? "").trim().toLowerCase();
  const mood = allowedMoods[normalized];
  if (!mood) {
    throw new ApiError(
      400,
      "invalid_women_calendar_mood",
      "Unsupported mood value.",
    );
  }
  return mood;
}

function normalizeSymptoms(value: unknown): string[] {
  if (!Array.isArray(value) || value.length > 8) {
    throw new ApiError(
      400,
      "invalid_women_calendar_symptoms",
      "symptoms must be an array with at most 8 items.",
    );
  }
  const result = new Set<string>();
  for (const item of value) {
    const mapped = allowedSymptoms[String(item ?? "").trim().toLowerCase()];
    if (!mapped) {
      throw new ApiError(
        400,
        "invalid_women_calendar_symptoms",
        "Unsupported symptom value.",
      );
    }
    result.add(mapped);
  }
  if (result.has("NoSymptom") && result.size > 1) {
    throw new ApiError(
      400,
      "invalid_women_calendar_symptoms",
      "NoSymptom cannot be combined with other symptoms.",
    );
  }
  return [...result];
}

function normalizeStoredSymptoms(value: unknown): string[] {
  if (!Array.isArray(value)) return [];
  const reverse = new Map(
    Object.entries(allowedSymptoms).map(([key, stored]) => [stored, key]),
  );
  return value
    .map((item) => reverse.get(String(item)))
    .filter((item): item is string => item != null);
}

function phaseForCycleDay(
  cycleDay: number,
  periodLength: number,
  ovulationDay: number,
  fertileWindowStartDay: number,
  fertileWindowEndDay: number,
  pmsStartDay: number,
): DetailedPhase {
  if (cycleDay <= periodLength) return "period";
  if (cycleDay < fertileWindowStartDay) return "follicular";
  if (cycleDay === ovulationDay) return "ovulation";
  if (cycleDay <= fertileWindowEndDay) return "fertile";
  if (cycleDay >= pmsStartDay) return "pms";
  return "luteal";
}

function clamp(value: number, min: number, max: number): number {
  return Math.min(Math.max(value, min), max);
}

function parseDateOnly(value: string): Date {
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(value);
  if (!match) throw new Error("Invalid date-only value.");
  return new Date(
    Date.UTC(Number(match[1]), Number(match[2]) - 1, Number(match[3])),
  );
}

function addDays(value: Date, days: number): Date {
  return new Date(value.getTime() + days * 86_400_000);
}

function formatDateOnly(value: Date): string {
  return value.toISOString().slice(0, 10);
}

function dateString(value: unknown): string {
  if (value instanceof Date) return value.toISOString().slice(0, 10);
  return String(value).slice(0, 10);
}

function iso(value: unknown): string {
  return value instanceof Date
    ? value.toISOString()
    : new Date(String(value)).toISOString();
}
