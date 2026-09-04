import { getLifeMateSql } from "./database_client.ts";
import { createPersonWomenCalendarStore as createBaseWomenCalendarStore } from "./person_women_calendar_caregiver.ts";
import { ApiError } from "./validation.ts";

type Row = Record<string, any>;

const regularities = new Set(["Regular", "Irregular", "Unknown"]);

export function createWomenCalendarV3Store(databaseUrl: string) {
  const sql = getLifeMateSql(databaseUrl);
  const base = createBaseWomenCalendarStore(databaseUrl);

  async function getOwnerProfile(
    appUserId: string,
  ): Promise<Record<string, unknown>> {
    return decorate(
      await base.getOwnerProfile(appUserId),
      await metadata(appUserId),
    );
  }

  async function updateOwnerProfile(
    appUserId: string,
    body: Record<string, unknown>,
  ): Promise<Record<string, unknown>> {
    const isV3Activation = Object.hasOwn(body, "cycleLengthKnown") ||
      Object.hasOwn(body, "periodLengthKnown") ||
      Object.hasOwn(body, "regularity");
    if (!isV3Activation) {
      return decorate(
        await base.updateOwnerProfile(appUserId, body),
        await metadata(appUserId),
      );
    }

    forbidInitialPrivateInference(body);
    const version = nonNegativeInt(body.version, "version");
    const enabled = requiredBoolean(body.enabled, "enabled");
    const lastPeriodStart = requiredDateOrNull(
      body.lastPeriodStart,
      "lastPeriodStart",
    );
    if (enabled && lastPeriodStart == null) {
      throw new ApiError(
        400,
        "last_period_start_required",
        "lastPeriodStart is required when Women Health is activated.",
      );
    }
    const cycleLengthKnown = requiredBoolean(
      body.cycleLengthKnown,
      "cycleLengthKnown",
    );
    const periodLengthKnown = requiredBoolean(
      body.periodLengthKnown,
      "periodLengthKnown",
    );
    const regularity = requiredRegularity(body.regularity);
    const cycleLength = boundedInt(
      body.cycleLength,
      "cycleLength",
      21,
      45,
    );
    const periodLength = boundedInt(
      body.periodLength,
      "periodLength",
      1,
      10,
    );
    if (periodLength >= cycleLength) {
      throw new ApiError(
        400,
        "invalid_women_calendar_profile",
        "periodLength must be shorter than cycleLength.",
      );
    }
    const remindersEnabled = requiredBoolean(
      body.remindersEnabled,
      "remindersEnabled",
    );

    await sql.begin(async (tx: any) => {
      const personId = await selfPersonId(tx, appUserId);
      const existingRows = await tx`
        select id, version
        from lifemate.women_calendar_profiles
        where owner_person_id=${personId}::uuid
        for update
      `;
      const existing = existingRows[0];
      const now = new Date();
      if (!existing) {
        if (version !== 0) throw staleProfile();
        const compatibilityRows = await tx`
          select owner_person_id::text
          from lifemate.women_calendar_profiles
          where owner_user_id=${appUserId}::uuid
          for update
        `;
        if (compatibilityRows[0]) {
          throw new ApiError(
            409,
            "identity_person_mapping_conflict",
            "The Women Calendar owner mapping is inconsistent.",
          );
        }
        await tx`
          insert into lifemate.women_calendar_profiles
            (owner_person_id, enabled, last_period_start,
             cycle_length, period_length, reminders_enabled,
             cycle_length_known, period_length_known, regularity,
             algorithm_version, version, created_at_utc, updated_at_utc)
          values
            (${personId}::uuid, ${enabled}, ${lastPeriodStart},
             ${cycleLength}, ${periodLength}, ${remindersEnabled},
             ${cycleLengthKnown}, ${periodLengthKnown}, ${regularity},
             'calendar-estimate-v1', 1, ${now}, ${now})
        `;
        await audit(
          tx,
          appUserId,
          "women_calendar.profile_created",
          personId,
        );
      } else {
        if (Number(existing.version) !== version) throw staleProfile();
        await tx`
          update lifemate.women_calendar_profiles
          set enabled=${enabled},
              last_period_start=${lastPeriodStart},
              cycle_length=${cycleLength},
              period_length=${periodLength},
              reminders_enabled=${remindersEnabled},
              cycle_length_known=${cycleLengthKnown},
              period_length_known=${periodLengthKnown},
              regularity=${regularity},
              version=version+1,
              updated_at_utc=${now}
          where owner_person_id=${personId}::uuid
        `;
        await audit(
          tx,
          appUserId,
          enabled
            ? "women_calendar.profile_enabled_or_updated"
            : "women_calendar.profile_disabled",
          personId,
        );
      }
    });

    return await getOwnerProfile(appUserId);
  }

  return {
    ...base,
    getOwnerProfile,
    updateOwnerProfile,
  };

  async function metadata(appUserId: string): Promise<Row | null> {
    const personId = await selfPersonId(sql, appUserId);
    const rows = await sql`
      select cycle_length_known, period_length_known, regularity
      from lifemate.women_calendar_profiles
      where owner_person_id=${personId}::uuid
      limit 1
    `;
    return rows[0] ?? null;
  }
}

function decorate(
  profile: Record<string, unknown>,
  row: Row | null,
): Record<string, unknown> {
  return {
    ...profile,
    cycleLengthKnown: row?.cycle_length_known ?? null,
    periodLengthKnown: row?.period_length_known ?? null,
    regularity: row?.regularity == null
      ? null
      : String(row.regularity).toLowerCase(),
    // Explicitly no fertility intent/status is derived by activation.
    activationDataQuality: row == null
      ? "insufficient"
      : row.cycle_length_known === true && row.period_length_known === true
      ? "configured"
      : "partial",
  };
}

async function selfPersonId(
  connection: any,
  appUserId: string,
): Promise<string> {
  const rows = await connection`
    select core.self_person_id_for_legacy_app_user(${appUserId}::uuid)::text
      as person_id
  `;
  const value = rows[0]?.person_id;
  if (typeof value !== "string" || value.length === 0) {
    throw new ApiError(
      409,
      "identity_person_mapping_missing",
      "The LifeMate person mapping is unavailable.",
    );
  }
  return value;
}

async function audit(
  connection: any,
  actorUserId: string,
  action: string,
  personId: string,
): Promise<void> {
  await connection`
    insert into lifemate.audit_logs
      (id, actor_user_id, action, resource_type, resource_id,
       metadata_json, created_at_utc)
    values
      (${crypto.randomUUID()}::uuid, ${actorUserId}::uuid, ${action},
       'women_calendar_profile', ${personId}::uuid, null, now())
  `;
}

function forbidInitialPrivateInference(body: Record<string, unknown>): void {
  for (
    const field of [
      "mood",
      "symptoms",
      "privateNotes",
      "fertilityIntent",
      "tryingToConceive",
      "pregnancyIntent",
    ]
  ) {
    if (Object.hasOwn(body, field)) {
      throw new ApiError(
        400,
        "women_activation_private_field_forbidden",
        `${field} is not part of Women Health activation.`,
      );
    }
  }
}

function requiredBoolean(value: unknown, field: string): boolean {
  if (typeof value !== "boolean") {
    throw new ApiError(400, "invalid_boolean", `${field} must be a boolean.`);
  }
  return value;
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

function requiredRegularity(value: unknown): string {
  const raw = String(value ?? "").trim().toLowerCase();
  const normalized = raw.length === 0
    ? ""
    : raw[0].toUpperCase() + raw.slice(1);
  if (!regularities.has(normalized)) {
    throw new ApiError(
      400,
      "invalid_women_calendar_regularity",
      "regularity must be regular, irregular, or unknown.",
    );
  }
  return normalized;
}

function requiredDateOrNull(value: unknown, field: string): string | null {
  if (value == null) return null;
  const text = String(value).trim();
  if (!/^\d{4}-\d{2}-\d{2}$/.test(text)) {
    throw new ApiError(400, "invalid_date", `${field} must be YYYY-MM-DD.`);
  }
  const date = new Date(`${text}T00:00:00Z`);
  if (
    Number.isNaN(date.getTime()) || date.toISOString().slice(0, 10) !== text
  ) {
    throw new ApiError(400, "invalid_date", `${field} is invalid.`);
  }
  return text;
}

function staleProfile(): ApiError {
  return new ApiError(
    409,
    "stale_women_calendar_profile",
    "Women calendar profile changed. Refresh and try again.",
  );
}
