import { getLifeMateSql } from "./database_client.ts";
import { ApiError } from "./validation.ts";

type Row = Record<string, any>;

export function createWomenInsightPreferencesStore(databaseUrl: string) {
  const sql = getLifeMateSql(databaseUrl);

  async function get(appUserId: string): Promise<Record<string, unknown>> {
    const personId = await selfPersonId(sql, appUserId);
    const rows = await sql`
      select * from lifemate.women_cycle_insight_preferences
      where owner_person_id=${personId}::uuid limit 1
    `;
    return rows[0] ? map(rows[0]) : defaults();
  }

  async function update(
    appUserId: string,
    raw: Record<string, unknown>,
  ): Promise<Record<string, unknown>> {
    const expectedVersion = nonNegativeInt(raw.version ?? 0, "version");
    const insightsEnabled = requiredBoolean(raw.insightsEnabled, "insightsEnabled");
    const notificationsEnabled = requiredBoolean(raw.notificationsEnabled, "notificationsEnabled");
    const expectedPeriodNotifications = requiredBoolean(
      raw.expectedPeriodNotifications,
      "expectedPeriodNotifications",
    );
    const loggingReminderNotifications = requiredBoolean(
      raw.loggingReminderNotifications,
      "loggingReminderNotifications",
    );
    const frequencyMode = String(raw.frequencyMode ?? "").trim().toLowerCase();
    if (!new Set(["low", "balanced", "high"]).has(frequencyMode)) {
      throw new ApiError(400, "invalid_cycle_insight_frequency", "Unsupported Cycle Insight frequency.");
    }

    return await sql.begin(async (tx: any) => {
      const personId = await selfPersonId(tx, appUserId);
      const existing = await tx`
        select * from lifemate.women_cycle_insight_preferences
        where owner_person_id=${personId}::uuid for update
      `;
      if (!existing[0]) {
        if (expectedVersion !== 0) throw stale();
        const rows = await tx`
          insert into lifemate.women_cycle_insight_preferences(
            owner_person_id,insights_enabled,notifications_enabled,
            expected_period_notifications,logging_reminder_notifications,
            frequency_mode,version,created_at_utc,updated_at_utc
          ) values(
            ${personId}::uuid,${insightsEnabled},${notificationsEnabled},
            ${expectedPeriodNotifications},${loggingReminderNotifications},
            ${frequencyMode},1,now(),now()
          ) returning *
        `;
        return map(rows[0]);
      }
      if (Number(existing[0].version) !== expectedVersion) throw stale();
      const rows = await tx`
        update lifemate.women_cycle_insight_preferences set
          insights_enabled=${insightsEnabled},
          notifications_enabled=${notificationsEnabled},
          expected_period_notifications=${expectedPeriodNotifications},
          logging_reminder_notifications=${loggingReminderNotifications},
          frequency_mode=${frequencyMode},version=version+1,updated_at_utc=now()
        where owner_person_id=${personId}::uuid returning *
      `;
      return map(rows[0]);
    });
  }

  return { get, update };
}

function defaults(): Record<string, unknown> {
  return {
    insightsEnabled: true,
    notificationsEnabled: false,
    expectedPeriodNotifications: true,
    loggingReminderNotifications: true,
    frequencyMode: "balanced",
    version: 0,
  };
}

function map(row: Row): Record<string, unknown> {
  return {
    insightsEnabled: row.insights_enabled !== false,
    notificationsEnabled: row.notifications_enabled === true,
    expectedPeriodNotifications: row.expected_period_notifications !== false,
    loggingReminderNotifications: row.logging_reminder_notifications !== false,
    frequencyMode: String(row.frequency_mode ?? "balanced"),
    version: Number(row.version ?? 0),
  };
}

async function selfPersonId(connection: any, appUserId: string): Promise<string> {
  const rows = await connection`
    select core.self_person_id_for_legacy_app_user(${appUserId}::uuid)::text as person_id
  `;
  const value = rows[0]?.person_id;
  if (typeof value !== "string" || value.length === 0) {
    throw new ApiError(409, "identity_person_mapping_missing", "The LifeMate person mapping is unavailable.");
  }
  return value;
}

function requiredBoolean(value: unknown, field: string): boolean {
  if (typeof value !== "boolean") throw new ApiError(400, "invalid_boolean", `${field} must be boolean.`);
  return value;
}
function nonNegativeInt(value: unknown, field: string): number {
  const number = Number(value);
  if (!Number.isInteger(number) || number < 0) throw new ApiError(400, "invalid_integer", `${field} must be non-negative.`);
  return number;
}
function stale(): ApiError {
  return new ApiError(409, "stale_cycle_insight_preferences", "Cycle Insight preferences changed. Refresh and try again.");
}
