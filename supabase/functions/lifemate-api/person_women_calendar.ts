import { getLifeMateSql } from "./database_client.ts";
import {
  ApiError,
  limitedOptional,
  requiredDate,
  requiredPositiveInt,
  requiredUuid,
  validateRange,
} from "./validation.ts";
import {
  assertCanonicalWomenDailyLogPayload,
  calculateWomenCalendarEstimate,
  calculateWomenCalendarEstimateFromEpisodes,
  createWomenCalendarStore as createLegacyWomenCalendarStore,
} from "./women_calendar_legacy.ts";

type Row = Record<string, any>;

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

async function requireSelfPerson(
  connection: any,
  appUserId: string,
): Promise<string> {
  const rows = await connection`
    select core.self_person_id_for_legacy_app_user(${appUserId}::uuid)::text
      as person_id
  `;
  const personId = rows[0]?.person_id;
  if (typeof personId !== "string" || personId.length === 0) {
    throw new ApiError(
      409,
      "identity_person_mapping_missing",
      "The LifeMate person mapping is unavailable.",
    );
  }
  return personId;
}

/**
 * Self-owned Women Calendar data is authorized by canonical Person.
 *
 * Person-authoritative profile writes no longer persist owner_user_id. The
 * legacy store remains available only as staged rollback compatibility while
 * the operational retirement/rehydration path is evidence-gated separately.
 */
export function createPersonWomenCalendarStore(databaseUrl: string) {
  const sql = getLifeMateSql(databaseUrl);
  const legacy = createLegacyWomenCalendarStore(databaseUrl);

  async function getOwnerProfile(
    appUserId: string,
  ): Promise<Record<string, unknown>> {
    const personId = await requireSelfPerson(sql, appUserId);
    const rows = await sql`
      select * from lifemate.women_calendar_profiles
      where owner_person_id = ${personId}::uuid
      limit 1
    `;
    if (!rows[0]) return defaultProfile(appUserId);
    const episodes = await sql`
      select started_on from lifemate.women_calendar_episodes
      where owner_person_id = ${personId}::uuid
      order by started_on asc
      limit 100
    `;
    return mapProfileWithEpisodeHistory(rows[0], episodes, appUserId);
  }

  async function updateOwnerProfile(
    appUserId: string,
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
      const personId = await requireSelfPerson(tx, appUserId);
      const existingRows = await tx`
        select * from lifemate.women_calendar_profiles
        where owner_person_id = ${personId}::uuid
        for update
      `;
      const existing = existingRows[0];
      let row: Row;
      if (!existing) {
        if (expectedVersion !== 0) throw staleProfile();
        const compatibilityRows = await tx`
          select owner_person_id::text
          from lifemate.women_calendar_profiles
          where owner_user_id = ${appUserId}::uuid
          for update
        `;
        if (compatibilityRows[0]) {
          throw identityConflict();
        }
        const rows = await tx`
          insert into lifemate.women_calendar_profiles
            (owner_person_id, enabled, last_period_start,
             cycle_length, period_length, reminders_enabled,
             algorithm_version, version, created_at_utc, updated_at_utc)
          values
            (${personId}::uuid, ${enabled}, ${lastPeriodStart}, ${cycleLength},
             ${periodLength}, ${remindersEnabled}, 'calendar-estimate-v1', 1,
             ${now}, ${now})
          returning *
        `;
        row = rows[0];
        await insertAudit(
          tx,
          appUserId,
          "women_calendar.profile_created",
          "women_calendar_profile",
          personId,
        );
      } else {
        if (Number(existing.version) !== expectedVersion) throw staleProfile();
        const rows = await tx`
          update lifemate.women_calendar_profiles
          set enabled = ${enabled}, last_period_start = ${lastPeriodStart},
              cycle_length = ${cycleLength}, period_length = ${periodLength},
              reminders_enabled = ${remindersEnabled},
              version = version + 1, updated_at_utc = ${now}
          where owner_person_id = ${personId}::uuid
          returning *
        `;
        row = rows[0];
        await insertAudit(
          tx,
          appUserId,
          enabled
            ? "women_calendar.profile_enabled_or_updated"
            : "women_calendar.profile_disabled",
          "women_calendar_profile",
          personId,
        );
      }
      const episodes = await tx`
        select started_on from lifemate.women_calendar_episodes
        where owner_person_id = ${personId}::uuid
        order by started_on asc
        limit 100
      `;
      return mapProfileWithEpisodeHistory(row, episodes, appUserId);
    });
  }

  async function listOwnerEpisodes(
    appUserId: string,
  ): Promise<Record<string, unknown>[]> {
    const personId = await requireSelfPerson(sql, appUserId);
    const rows = await sql`
      select * from lifemate.women_calendar_episodes
      where owner_person_id = ${personId}::uuid
      order by started_on desc, id
      limit 100
    `;
    return rows.map(mapEpisodeOwner);
  }

  async function createOwnerEpisode(
    appUserId: string,
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
      const personId = await requireSelfPerson(tx, appUserId);
      const overlaps = await tx`
        select id from lifemate.women_calendar_episodes
        where owner_person_id = ${personId}::uuid
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
          (id, owner_user_id, owner_person_id, started_on, ended_on,
           private_notes, version, created_at_utc, updated_at_utc)
        values
          (${id}::uuid, ${appUserId}::uuid, ${personId}::uuid,
           ${startedOn}::date, ${endedOn}::date, ${privateNotes}, 1,
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
        where owner_person_id = ${personId}::uuid
      `;
      await insertAudit(
        tx,
        appUserId,
        "women_calendar.episode_created",
        "women_calendar_episode",
        id,
      );
      return mapEpisodeOwner(rows[0]);
    });
  }

  async function updateOwnerEpisode(
    appUserId: string,
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
      const personId = await requireSelfPerson(tx, appUserId);
      const existingRows = await tx`
        select * from lifemate.women_calendar_episodes
        where id = ${episodeId}::uuid
          and owner_person_id = ${personId}::uuid
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
      if (Number(existing.version) !== expectedVersion) {
        throw new ApiError(
          409,
          "stale_women_calendar_episode",
          "Period episode changed. Refresh and try again.",
        );
      }
      const overlaps = await tx`
        select id from lifemate.women_calendar_episodes
        where owner_person_id = ${personId}::uuid
          and id <> ${episodeId}::uuid
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
        set started_on = ${startedOn}::date, ended_on = ${endedOn}::date,
            private_notes = ${privateNotes}, version = version + 1,
            updated_at_utc = now()
        where id = ${episodeId}::uuid
          and owner_person_id = ${personId}::uuid
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
        where owner_person_id = ${personId}::uuid
      `;
      await insertAudit(
        tx,
        appUserId,
        "women_calendar.episode_updated",
        "women_calendar_episode",
        episodeId,
      );
      return mapEpisodeOwner(rows[0]);
    });
  }

  async function deleteOwnerEpisode(
    appUserId: string,
    episodeIdValue: unknown,
  ): Promise<void> {
    const episodeId = requiredUuid(episodeIdValue, "episodeId");
    await sql.begin(async (tx: any) => {
      const personId = await requireSelfPerson(tx, appUserId);
      const rows = await tx`
        delete from lifemate.women_calendar_episodes
        where id = ${episodeId}::uuid
          and owner_person_id = ${personId}::uuid
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
                    where owner_person_id = ${personId}::uuid
                  ),
                  last_period_start
                )
              else last_period_start
            end,
            version = version + 1,
            updated_at_utc = now()
        where owner_person_id = ${personId}::uuid
      `;
      await insertAudit(
        tx,
        appUserId,
        "women_calendar.episode_deleted",
        "women_calendar_episode",
        episodeId,
      );
    });
  }

  async function listOwnerDailyLogs(
    appUserId: string,
    fromValue: unknown,
    toValue: unknown,
  ): Promise<Record<string, unknown>[]> {
    const fromDate = requiredDate(fromValue, "fromDate");
    const toDate = requiredDate(toValue, "toDate");
    validateRange(fromDate, toDate, 90);
    const personId = await requireSelfPerson(sql, appUserId);
    const rows = await sql`
      select * from lifemate.women_calendar_daily_logs
      where owner_person_id = ${personId}::uuid
        and logged_on between ${fromDate}::date and ${toDate}::date
      order by logged_on desc, id
      limit 180
    `;
    return rows.map(mapDailyLogOwner);
  }

  async function upsertOwnerDailyLog(
    appUserId: string,
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
    const shareSummaryProvided = Object.hasOwn(
      body,
      "shareSummaryWithCompanion",
    );
    const shareSummaryWithCompanion = shareSummaryProvided
      ? requiredBoolean(
        body.shareSummaryWithCompanion,
        "shareSummaryWithCompanion",
      )
      : null;
    const now = new Date();

    return await sql.begin(async (tx: any) => {
      const personId = await requireSelfPerson(tx, appUserId);
      const existingRows = await tx`
        select * from lifemate.women_calendar_daily_logs
        where owner_person_id = ${personId}::uuid
          and logged_on = ${loggedOn}::date
        for update
      `;
      const existing = existingRows[0];
      let row: Row;
      if (!existing) {
        if (expectedVersion !== 0) throw staleDailyLog();
        const id = crypto.randomUUID();
        const rows = await tx`
          insert into lifemate.women_calendar_daily_logs
            (id, owner_user_id, owner_person_id, logged_on, mood,
             energy_level, pain_level, symptoms, private_notes,
             share_summary_with_companion, version,
             created_at_utc, updated_at_utc)
          values
            (${id}::uuid, ${appUserId}::uuid, ${personId}::uuid,
             ${loggedOn}::date, ${mood}, ${energyLevel}, ${painLevel},
             ${symptoms}, ${privateNotes}, ${shareSummaryWithCompanion ?? false},
             1, ${now}, ${now})
          returning *
        `;
        row = rows[0];
        await insertAudit(
          tx,
          appUserId,
          "women_calendar.daily_log_created",
          "women_calendar_daily_log",
          id,
        );
      } else {
        if (Number(existing.version) !== expectedVersion) throw staleDailyLog();
        const rows = await tx`
          update lifemate.women_calendar_daily_logs
          set mood = ${mood}, energy_level = ${energyLevel},
              pain_level = ${painLevel}, symptoms = ${symptoms},
              private_notes = ${privateNotes},
              share_summary_with_companion = ${shareSummaryWithCompanion},
              version = version + 1, updated_at_utc = ${now}
          where id = ${existing.id}::uuid
            and owner_person_id = ${personId}::uuid
          returning *
        `;
        row = rows[0];
        await insertAudit(
          tx,
          appUserId,
          "women_calendar.daily_log_updated",
          "women_calendar_daily_log",
          String(existing.id),
        );
      }
      return mapDailyLogOwner(row);
    });
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
    getCareSummary: legacy.getCareSummary,
    recordCareSupportAction: legacy.recordCareSupportAction,
  };
}

function mapProfileWithEpisodeHistory(
  row: Row,
  episodeRows: Row[],
  callerAppUserId: string,
): Record<string, unknown> {
  const lastPeriodStart = row.last_period_start == null
    ? null
    : dateString(row.last_period_start);
  const estimate = row.enabled === true && lastPeriodStart != null
    ? calculateWomenCalendarEstimateFromEpisodes(
      lastPeriodStart,
      Number(row.cycle_length),
      Number(row.period_length),
      episodeRows.map((episode) => dateString(episode.started_on)),
    )
    : null;
  return {
    ownerUserId: callerAppUserId,
    enabled: row.enabled,
    lastPeriodStart,
    cycleLength: row.cycle_length,
    periodLength: row.period_length,
    remindersEnabled: row.reminders_enabled,
    algorithmVersion: row.algorithm_version,
    version: row.version,
    estimate,
    dailyCheckIn: null,
    createdAtUtc: iso(row.created_at_utc),
    updatedAtUtc: iso(row.updated_at_utc),
  };
}

function defaultProfile(appUserId: string): Record<string, unknown> {
  return {
    ownerUserId: appUserId,
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
      (${crypto.randomUUID()}::uuid, ${actorUserId}::uuid, ${action},
       ${resourceType}, ${resourceId}::uuid, null, now())
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

function identityConflict(): ApiError {
  return new ApiError(
    409,
    "identity_person_mapping_conflict",
    "The Women Calendar owner mapping is inconsistent.",
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

function iso(value: unknown): string {
  return value instanceof Date
    ? value.toISOString()
    : new Date(String(value)).toISOString();
}

function dateString(value: unknown): string {
  if (value instanceof Date) return value.toISOString().slice(0, 10);
  return String(value).slice(0, 10);
}

// Keep the direct estimate export reachable through this module for callers
// that import the Person store during staged migration tests.
export { calculateWomenCalendarEstimate };
