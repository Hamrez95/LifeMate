import postgres from "postgres";
import {
  ApiError,
  limitedOptional,
  requiredDate,
  requiredPositiveInt,
  requiredUuid,
} from "./validation.ts";

type Row = Record<string, any>;

export type WomenCalendarEstimate = {
  cycleStart: string;
  cycleDay: number;
  cycleLength: number;
  periodLength: number;
  estimatedBleeding: boolean;
  phase: "period" | "post_period" | "cycle" | "pre_period";
  nextPeriodStart: string;
  daysUntilNextPeriod: number;
  algorithmVersion: "calendar-estimate-v1";
};

export function createWomenCalendarStore(databaseUrl: string) {
  const sql = postgres(databaseUrl, {
    max: 2,
    idle_timeout: 20,
    connect_timeout: 10,
    prepare: false,
  });

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
          throw new ApiError(
            409,
            "stale_women_calendar_profile",
            "Women calendar profile changed. Refresh and try again.",
          );
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
        throw new ApiError(
          409,
          "stale_women_calendar_profile",
          "Women calendar profile changed. Refresh and try again.",
        );
      }
      const rows = await tx`
        update lifemate.women_calendar_profiles
        set enabled = ${enabled}, last_period_start = ${lastPeriodStart},
            cycle_length = ${cycleLength}, period_length = ${periodLength},
            reminders_enabled = ${remindersEnabled}, version = version + 1,
            updated_at_utc = ${now}
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
    const endedOn = requiredDate(body.endedOn, "endedOn");
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
      const startedOn = dateString(existing.started_on);
      if (endedOn < startedOn) {
        throw new ApiError(
          400,
          "invalid_women_calendar_episode",
          "endedOn cannot precede startedOn.",
        );
      }
      const rows = await tx`
        update lifemate.women_calendar_episodes
        set ended_on = ${endedOn}, version = version + 1, updated_at_utc = now()
        where id = ${episodeId}
        returning *
      `;
      await insertAudit(
        tx,
        userId,
        "women_calendar.episode_completed",
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
        returning id
      `;
      if (!rows[0]) {
        throw new ApiError(
          404,
          "women_calendar_episode_not_found",
          "Episode not found.",
        );
      }
      await insertAudit(
        tx,
        userId,
        "women_calendar.episode_deleted",
        "women_calendar_episode",
        episodeId,
      );
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
    const profile = mapProfile(profiles[0]);
    return {
      profile: {
        enabled: profile.enabled,
        lastPeriodStart: profile.lastPeriodStart,
        cycleLength: profile.cycleLength,
        periodLength: profile.periodLength,
        algorithmVersion: profile.algorithmVersion,
      },
      estimate: profile.estimate,
      episodes: episodes.map(mapEpisodeCaregiver),
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
    getCareSummary,
    recordCareSupportAction,
  };
}

export function calculateWomenCalendarEstimate(
  lastPeriodStart: string,
  cycleLength: number,
  periodLength: number,
  todayValue = new Date(),
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
  const estimatedBleeding = cycleDay <= periodLength;
  const phase = estimatedBleeding
    ? "period"
    : cycleDay <= periodLength + 4
    ? "post_period"
    : daysUntilNextPeriod <= 5
    ? "pre_period"
    : "cycle";
  return {
    cycleStart: formatDateOnly(cycleStart),
    cycleDay,
    cycleLength,
    periodLength,
    estimatedBleeding,
    phase,
    nextPeriodStart: formatDateOnly(nextPeriodStart),
    daysUntilNextPeriod,
    algorithmVersion: "calendar-estimate-v1",
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

function mapEpisodeCaregiver(row: Row): Record<string, unknown> {
  return {
    id: row.id,
    startedOn: dateString(row.started_on),
    endedOn: row.ended_on == null ? null : dateString(row.ended_on),
    version: row.version,
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
