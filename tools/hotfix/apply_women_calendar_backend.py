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
        raise SystemExit(f'Expected snippet not found in {path}: {old[:120]!r}')
    target.write_text(text.replace(old, new, 1), encoding='utf-8')


write(
    'supabase/migrations/20260804130000_add_women_calendar_pilot.sql',
    r'''alter table lifemate.care_relationships
    add column if not exists can_view_women_calendar boolean not null default false;

create table if not exists lifemate.women_calendar_profiles (
    owner_user_id uuid primary key references lifemate.app_users(id) on delete cascade,
    enabled boolean not null default false,
    last_period_start date,
    cycle_length integer not null default 28,
    period_length integer not null default 5,
    reminders_enabled boolean not null default true,
    algorithm_version character varying(32) not null default 'calendar-estimate-v1',
    version integer not null default 1,
    created_at_utc timestamp with time zone not null,
    updated_at_utc timestamp with time zone not null,
    constraint ck_women_calendar_cycle_length check (cycle_length between 21 and 45),
    constraint ck_women_calendar_period_length check (
        period_length between 1 and 10 and period_length < cycle_length
    ),
    constraint ck_women_calendar_profile_version check (version > 0),
    constraint ck_women_calendar_enabled_start check (
        enabled = false or last_period_start is not null
    )
);

create table if not exists lifemate.women_calendar_episodes (
    id uuid primary key,
    owner_user_id uuid not null references lifemate.app_users(id) on delete cascade,
    started_on date not null,
    ended_on date,
    private_notes character varying(500),
    version integer not null default 1,
    created_at_utc timestamp with time zone not null,
    updated_at_utc timestamp with time zone not null,
    constraint ck_women_calendar_episode_range check (
        ended_on is null or ended_on >= started_on
    ),
    constraint ck_women_calendar_episode_version check (version > 0),
    constraint uq_women_calendar_episode_start unique (owner_user_id, started_on)
);

create index if not exists ix_women_calendar_episodes_owner_start
    on lifemate.women_calendar_episodes(owner_user_id, started_on desc);

create table if not exists lifemate.women_calendar_support_actions (
    id uuid primary key,
    patient_user_id uuid not null references lifemate.app_users(id) on delete cascade,
    caregiver_user_id uuid not null references lifemate.app_users(id) on delete cascade,
    relationship_id uuid not null references lifemate.care_relationships(id) on delete cascade,
    action_type character varying(32) not null,
    performed_at_utc timestamp with time zone not null,
    created_at_utc timestamp with time zone not null,
    constraint ck_women_calendar_support_action_type check (
        action_type in ('Hydration', 'Rest', 'Warmth', 'Chores')
    )
);

create index if not exists ix_women_calendar_support_patient_time
    on lifemate.women_calendar_support_actions(patient_user_id, performed_at_utc desc);

do $migration$
begin
    if exists (select 1 from pg_roles where rolname = 'anon') then
        execute 'revoke all privileges on table lifemate.women_calendar_profiles from anon';
        execute 'revoke all privileges on table lifemate.women_calendar_episodes from anon';
        execute 'revoke all privileges on table lifemate.women_calendar_support_actions from anon';
    end if;
    if exists (select 1 from pg_roles where rolname = 'authenticated') then
        execute 'revoke all privileges on table lifemate.women_calendar_profiles from authenticated';
        execute 'revoke all privileges on table lifemate.women_calendar_episodes from authenticated';
        execute 'revoke all privileges on table lifemate.women_calendar_support_actions from authenticated';
    end if;
    if exists (select 1 from pg_roles where rolname = 'service_role') then
        execute 'revoke all privileges on table lifemate.women_calendar_profiles from service_role';
        execute 'revoke all privileges on table lifemate.women_calendar_episodes from service_role';
        execute 'revoke all privileges on table lifemate.women_calendar_support_actions from service_role';
    end if;
end
$migration$;

comment on column lifemate.care_relationships.can_view_women_calendar is
'Owner-controlled, independent consent scope for the women calendar summary.';
comment on table lifemate.women_calendar_profiles is
'Owner-only women calendar settings and deterministic estimate inputs.';
comment on column lifemate.women_calendar_episodes.private_notes is
'Never returned to caregivers.';
''',
)

write(
    'supabase/functions/lifemate-api/women_calendar.ts',
    r'''import postgres from "postgres";
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

  async function getOwnerProfile(userId: string): Promise<Record<string, unknown>> {
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
    const privateNotes = limitedOptional(body.privateNotes, "privateNotes", 500);
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
        throw new ApiError(404, "women_calendar_episode_not_found", "Episode not found.");
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
        throw new ApiError(404, "women_calendar_episode_not_found", "Episode not found.");
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
    throw new ApiError(400, "invalid_integer", `${field} must be non-negative.`);
  }
  return number;
}

function parseDateOnly(value: string): Date {
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(value);
  if (!match) throw new Error("Invalid date-only value.");
  return new Date(Date.UTC(Number(match[1]), Number(match[2]) - 1, Number(match[3])));
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
''',
)

write(
    'supabase/functions/lifemate-api/women_calendar_test.ts',
    r'''import {
  assertEquals,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import { calculateWomenCalendarEstimate } from "./women_calendar.ts";

Deno.test("women calendar estimate is deterministic without fertility claims", () => {
  const estimate = calculateWomenCalendarEstimate(
    "2026-08-01",
    28,
    5,
    new Date("2026-08-04T15:00:00Z"),
  );
  assertEquals(estimate.cycleDay, 4);
  assertEquals(estimate.estimatedBleeding, true);
  assertEquals(estimate.phase, "period");
  assertEquals(estimate.nextPeriodStart, "2026-08-29");
  assertEquals(estimate.daysUntilNextPeriod, 25);
  assertEquals(estimate.algorithmVersion, "calendar-estimate-v1");
});

Deno.test("women calendar estimate marks the pre-period window as an estimate", () => {
  const estimate = calculateWomenCalendarEstimate(
    "2026-08-01",
    28,
    5,
    new Date("2026-08-26T00:00:00Z"),
  );
  assertEquals(estimate.cycleDay, 26);
  assertEquals(estimate.phase, "pre_period");
  assertEquals(estimate.daysUntilNextPeriod, 3);
});
''',
)

write(
    'packages/lifemate_client/lib/src/women_calendar.dart',
    r'''class WomenCalendarEstimate {
  const WomenCalendarEstimate({
    required this.cycleStart,
    required this.today,
    required this.cycleDay,
    required this.cycleLength,
    required this.periodLength,
    required this.estimatedBleeding,
    required this.phase,
    required this.nextPeriodStart,
    required this.daysUntilNextPeriod,
  });

  final DateTime cycleStart;
  final DateTime today;
  final int cycleDay;
  final int cycleLength;
  final int periodLength;
  final bool estimatedBleeding;
  final WomenCalendarPhase phase;
  final DateTime nextPeriodStart;
  final int daysUntilNextPeriod;

  static WomenCalendarEstimate calculate({
    required DateTime lastPeriodStart,
    required int cycleLength,
    required int periodLength,
    DateTime? today,
  }) {
    if (cycleLength < 21 || cycleLength > 45) {
      throw ArgumentError.value(cycleLength, 'cycleLength');
    }
    if (periodLength < 1 || periodLength > 10 || periodLength >= cycleLength) {
      throw ArgumentError.value(periodLength, 'periodLength');
    }
    final start = _dateOnly(lastPeriodStart);
    final current = _dateOnly(today ?? DateTime.now());
    final rawDifference = current.difference(start).inDays;
    final cyclesElapsed = rawDifference < 0 ? 0 : rawDifference ~/ cycleLength;
    var cycleStart = start.add(Duration(days: cyclesElapsed * cycleLength));
    if (cycleStart.isAfter(current)) cycleStart = start;
    final cycleDay = current.difference(cycleStart).inDays + 1;
    final nextPeriodStart = cycleStart.add(Duration(days: cycleLength));
    final daysUntilNextPeriod = nextPeriodStart.difference(current).inDays.clamp(
          0,
          cycleLength,
        );
    final estimatedBleeding = cycleDay <= periodLength;
    final phase = estimatedBleeding
        ? WomenCalendarPhase.period
        : cycleDay <= periodLength + 4
            ? WomenCalendarPhase.postPeriod
            : daysUntilNextPeriod <= 5
                ? WomenCalendarPhase.prePeriod
                : WomenCalendarPhase.cycle;
    return WomenCalendarEstimate(
      cycleStart: cycleStart,
      today: current,
      cycleDay: cycleDay,
      cycleLength: cycleLength,
      periodLength: periodLength,
      estimatedBleeding: estimatedBleeding,
      phase: phase,
      nextPeriodStart: nextPeriodStart,
      daysUntilNextPeriod: daysUntilNextPeriod,
    );
  }

  bool isEstimatedPeriodDay(DateTime value) {
    final date = _dateOnly(value);
    final difference = date.difference(cycleStart).inDays;
    if (difference < 0) return false;
    final day = (difference % cycleLength) + 1;
    return day <= periodLength;
  }

  static DateTime _dateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);
}

enum WomenCalendarPhase { period, postPeriod, cycle, prePeriod }
''',
)

write(
    'packages/lifemate_client/test/women_calendar_test.dart',
    r'''import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate_client/lifemate_client.dart';

void main() {
  test('calculates deterministic cycle day and next period estimate', () {
    final estimate = WomenCalendarEstimate.calculate(
      lastPeriodStart: DateTime(2026, 8, 1),
      cycleLength: 28,
      periodLength: 5,
      today: DateTime(2026, 8, 4),
    );

    expect(estimate.cycleDay, 4);
    expect(estimate.phase, WomenCalendarPhase.period);
    expect(estimate.estimatedBleeding, isTrue);
    expect(estimate.nextPeriodStart, DateTime(2026, 8, 29));
    expect(estimate.daysUntilNextPeriod, 25);
  });

  test('supports irregular user settings inside the bounded MVP range', () {
    final estimate = WomenCalendarEstimate.calculate(
      lastPeriodStart: DateTime(2026, 7, 20),
      cycleLength: 35,
      periodLength: 7,
      today: DateTime(2026, 8, 20),
    );

    expect(estimate.cycleDay, 32);
    expect(estimate.phase, WomenCalendarPhase.prePeriod);
    expect(estimate.daysUntilNextPeriod, 4);
    expect(estimate.isEstimatedPeriodDay(DateTime(2026, 8, 24)), isTrue);
  });
}
''',
)

replace_once(
    'packages/lifemate_client/lib/lifemate_client.dart',
    "export 'src/session_gate_secure.dart';\n",
    "export 'src/session_gate_secure.dart';\nexport 'src/women_calendar.dart';\n",
)

replace_once(
    'packages/lifemate_client/lib/src/feature_flags.dart',
    "  static const bool googleAuthEnabled = bool.fromEnvironment(\n    'ENABLE_GOOGLE_AUTH',\n    defaultValue: false,\n  );\n",
    "  static const bool googleAuthEnabled = bool.fromEnvironment(\n    'ENABLE_GOOGLE_AUTH',\n    defaultValue: false,\n  );\n\n  static const bool womenCalendarPilotEnabled = bool.fromEnvironment(\n    'ENABLE_WOMEN_CALENDAR_PILOT',\n    defaultValue: false,\n  );\n",
)

replace_once(
    'packages/lifemate_client/lib/src/lifemate_api_client.dart',
    "  Future<List<Map<String, dynamic>>> _getList(\n",
    r'''  Future<Map<String, dynamic>> getWomenCalendarProfile() async =>
      _asObject(
        await _send(
          'GET',
          '/api/v1/women-calendar/profile',
          retryable: true,
        ),
      );

  Future<Map<String, dynamic>> updateWomenCalendarProfile({
    required int version,
    required bool enabled,
    required DateTime? lastPeriodStart,
    required int cycleLength,
    required int periodLength,
    required bool remindersEnabled,
  }) async =>
      _asObject(
        await _send(
          'PATCH',
          '/api/v1/women-calendar/profile',
          body: {
            'version': version,
            'enabled': enabled,
            'lastPeriodStart':
                lastPeriodStart == null ? null : _date(lastPeriodStart),
            'cycleLength': cycleLength,
            'periodLength': periodLength,
            'remindersEnabled': remindersEnabled,
          },
        ),
      );

  Future<List<Map<String, dynamic>>> getWomenCalendarEpisodes() =>
      _getList('/api/v1/women-calendar/episodes');

  Future<Map<String, dynamic>> createWomenCalendarEpisode({
    required DateTime startedOn,
    DateTime? endedOn,
    String? privateNotes,
  }) async =>
      _asObject(
        await _send(
          'POST',
          '/api/v1/women-calendar/episodes',
          body: {
            'startedOn': _date(startedOn),
            'endedOn': endedOn == null ? null : _date(endedOn),
            'privateNotes': _emptyToNull(privateNotes),
          },
        ),
      );

  Future<Map<String, dynamic>> completeWomenCalendarEpisode({
    required String episodeId,
    required int version,
    required DateTime endedOn,
  }) async =>
      _asObject(
        await _send(
          'PATCH',
          '/api/v1/women-calendar/episodes/$episodeId',
          body: {
            'version': version,
            'endedOn': _date(endedOn),
          },
        ),
      );

  Future<void> deleteWomenCalendarEpisode({
    required String episodeId,
  }) async {
    await _send(
      'DELETE',
      '/api/v1/women-calendar/episodes/$episodeId',
    );
  }

  Future<Map<String, dynamic>> updateCareRelationshipPermissions({
    required String relationshipId,
    required bool canViewWomenCalendar,
  }) async =>
      _asObject(
        await _send(
          'PATCH',
          '/api/v1/care/relationships/$relationshipId/permissions',
          body: {
            'canViewWomenCalendar': canViewWomenCalendar,
          },
        ),
      );

  Future<Map<String, dynamic>> getCareRecipientWomenCalendar({
    required String patientUserId,
  }) async =>
      _asObject(
        await _send(
          'GET',
          '/api/v1/care/patients/$patientUserId/women-calendar',
          retryable: true,
        ),
      );

  Future<Map<String, dynamic>> recordCareRecipientWomenSupportAction({
    required String patientUserId,
    required String actionType,
  }) async =>
      _asObject(
        await _send(
          'POST',
          '/api/v1/care/patients/$patientUserId/women-calendar/support-actions',
          body: {'actionType': actionType.trim().toLowerCase()},
        ),
      );

  Future<List<Map<String, dynamic>>> _getList(
''',
)

replace_once(
    'supabase/functions/lifemate-api/index.ts',
    'import { createProfileStore } from "./profile.ts";\n',
    'import { createProfileStore } from "./profile.ts";\nimport { createWomenCalendarStore } from "./women_calendar.ts";\n',
)
replace_once(
    'supabase/functions/lifemate-api/index.ts',
    'const careEvents = createCareEventStore(databaseUrl);\n',
    'const careEvents = createCareEventStore(databaseUrl);\nconst womenCalendar = createWomenCalendarStore(databaseUrl);\nconst womenCalendarPilotEnabled =\n  (Deno.env.get("ENABLE_WOMEN_CALENDAR_PILOT") ?? "false").toLowerCase() ===\n    "true";\n',
)
replace_once(
    'supabase/functions/lifemate-api/index.ts',
    '''  if (request.method === "GET" && path === "/api/v1/medications") {\n''',
    r'''  if (request.method === "GET" && path === "/api/v1/women-calendar/profile") {
    requireWomenCalendarPilot();
    return json(await womenCalendar.getOwnerProfile(identity.appUserId));
  }
  if (request.method === "PATCH" && path === "/api/v1/women-calendar/profile") {
    requireWomenCalendarPilot();
    enforceRateLimit(`women-calendar-profile:${identity.appUserId}`, 20, 60 * 60_000);
    return json(
      await womenCalendar.updateOwnerProfile(
        identity.appUserId,
        await readJsonObject(request),
      ),
    );
  }
  if (request.method === "GET" && path === "/api/v1/women-calendar/episodes") {
    requireWomenCalendarPilot();
    return json(await womenCalendar.listOwnerEpisodes(identity.appUserId));
  }
  if (request.method === "POST" && path === "/api/v1/women-calendar/episodes") {
    requireWomenCalendarPilot();
    enforceRateLimit(`women-calendar-episode:${identity.appUserId}`, 30, 60 * 60_000);
    return json(
      await womenCalendar.createOwnerEpisode(
        identity.appUserId,
        await readJsonObject(request),
      ),
      201,
    );
  }
  const womenEpisodeMatch = path.match(
    /^\/api\/v1\/women-calendar\/episodes\/([0-9a-f-]{36})$/i,
  );
  if (request.method === "PATCH" && womenEpisodeMatch) {
    requireWomenCalendarPilot();
    return json(
      await womenCalendar.updateOwnerEpisode(
        identity.appUserId,
        womenEpisodeMatch[1],
        await readJsonObject(request),
      ),
    );
  }
  if (request.method === "DELETE" && womenEpisodeMatch) {
    requireWomenCalendarPilot();
    await womenCalendar.deleteOwnerEpisode(
      identity.appUserId,
      womenEpisodeMatch[1],
    );
    return new Response(null, { status: 204, headers: corsHeaders });
  }

  if (request.method === "GET" && path === "/api/v1/medications") {
''',
)
replace_once(
    'supabase/functions/lifemate-api/index.ts',
    '''  const relationshipMatch = path.match(\n    /^\\/api\\/v1\\/care\\/relationships\\/([0-9a-f-]{36})$/i,\n  );\n''',
    r'''  const relationshipPermissionMatch = path.match(
    /^\/api\/v1\/care\/relationships\/([0-9a-f-]{36})\/permissions$/i,
  );
  if (request.method === "PATCH" && relationshipPermissionMatch) {
    requireWomenCalendarPilot();
    enforceRateLimit(`care-permissions:${identity.appUserId}`, 30, 60 * 60_000);
    return json(
      await db.updateRelationshipPermissions(
        identity.appUserId,
        relationshipPermissionMatch[1],
        await readJsonObject(request),
      ),
    );
  }

  const relationshipMatch = path.match(
    /^\/api\/v1\/care\/relationships\/([0-9a-f-]{36})$/i,
  );
''',
)
replace_once(
    'supabase/functions/lifemate-api/index.ts',
    '''  throw new ApiError(404, "route_not_found", "API route was not found.");\n''',
    r'''  const careWomenCalendarMatch = path.match(
    /^\/api\/v1\/care\/patients\/([0-9a-f-]{36})\/women-calendar$/i,
  );
  if (request.method === "GET" && careWomenCalendarMatch) {
    requireWomenCalendarPilot();
    return json(
      await womenCalendar.getCareSummary(
        identity.appUserId,
        careWomenCalendarMatch[1],
      ),
    );
  }
  const careWomenSupportMatch = path.match(
    /^\/api\/v1\/care\/patients\/([0-9a-f-]{36})\/women-calendar\/support-actions$/i,
  );
  if (request.method === "POST" && careWomenSupportMatch) {
    requireWomenCalendarPilot();
    enforceRateLimit(`women-calendar-support:${identity.appUserId}`, 30, 60 * 60_000);
    return json(
      await womenCalendar.recordCareSupportAction(
        identity.appUserId,
        careWomenSupportMatch[1],
        await readJsonObject(request),
      ),
      201,
    );
  }

  throw new ApiError(404, "route_not_found", "API route was not found.");
''',
)
replace_once(
    'supabase/functions/lifemate-api/index.ts',
    '''function isPostgresConflict(error: unknown): boolean {\n''',
    r'''function requireWomenCalendarPilot(): void {
  if (!womenCalendarPilotEnabled) {
    throw new ApiError(
      404,
      "women_calendar_feature_disabled",
      "Women calendar pilot is disabled.",
    );
  }
}

function isPostgresConflict(error: unknown): boolean {
''',
)

replace_once(
    'supabase/functions/lifemate-api/database.ts',
    '''  async function revokeRelationship(\n''',
    r'''  async function updateRelationshipPermissions(
    userId: string,
    relationshipIdValue: unknown,
    body: Record<string, unknown>,
  ): Promise<Record<string, unknown>> {
    const relationshipId = requiredUuid(relationshipIdValue, "relationshipId");
    if (typeof body.canViewWomenCalendar !== "boolean") {
      throw new ApiError(
        400,
        "invalid_care_permission",
        "canViewWomenCalendar must be a boolean.",
      );
    }
    return await sql.begin(async (tx: any) => {
      const existingRows = await tx`
        select * from lifemate.care_relationships
        where id = ${relationshipId}
          and patient_user_id = ${userId}
          and status = 'Active'
        for update
      `;
      const existing = existingRows[0];
      if (!existing) {
        throw new ApiError(
          404,
          "relationship_not_found",
          "Active owner relationship was not found.",
        );
      }
      const rows = await tx`
        update lifemate.care_relationships
        set can_view_women_calendar = ${body.canViewWomenCalendar},
            updated_at_utc = now()
        where id = ${relationshipId}
        returning *
      `;
      await insertAudit(
        tx,
        userId,
        "care_relationship.permissions_updated",
        "care_relationship",
        relationshipId,
      );
      return await mapRelationship(tx, rows[0]);
    });
  }

  async function revokeRelationship(
''',
)
replace_once(
    'supabase/functions/lifemate-api/database.ts',
    '''    listRelationships,\n    revokeRelationship,\n''',
    '''    listRelationships,\n    updateRelationshipPermissions,\n    revokeRelationship,\n''',
)
replace_once(
    'supabase/functions/lifemate-api/database.ts',
    '''    status: String(row.status).toLowerCase(),\n    patientConsentedAtUtc: iso(row.patient_consented_at_utc),\n''',
    '''    status: String(row.status).toLowerCase(),\n    canViewWomenCalendar: row.can_view_women_calendar === true,\n    patientConsentedAtUtc: iso(row.patient_consented_at_utc),\n''',
)

print('Women calendar backend, API client and domain patch applied.')
