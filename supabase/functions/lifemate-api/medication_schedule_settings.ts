import { getLifeMateSql } from "./database_client.ts";
import {
  ApiError,
  normalizeOptional,
  requiredPositiveInt,
} from "./validation.ts";

type Row = Record<string, any>;

const maxSpacingMinutes = 1440;
const maxTimingNoteLength = 240;

export function requiredMedicationScheduleVersion(value: unknown): number {
  if (value === 0 || value === "0") return 0;
  return requiredPositiveInt(value, "version");
}

export function requiredMedicationScheduleBoolean(
  value: unknown,
  field: string,
): boolean {
  if (value !== true && value !== false) {
    throw new ApiError(
      400,
      `invalid_${field}`,
      `${field} must be a boolean.`,
    );
  }
  return value;
}

export function optionalMedicationScheduleLocalTime(
  value: unknown,
  field: string,
): string | null {
  const normalized = normalizeOptional(value);
  if (normalized == null) return null;
  if (!/^(?:[01]\d|2[0-3]):[0-5]\d(?::[0-5]\d)?$/.test(normalized)) {
    throw new ApiError(
      400,
      `invalid_${field}`,
      `${field} must be a local time.`,
    );
  }
  return normalized.length === 5 ? `${normalized}:00` : normalized;
}

export function requiredMedicationScheduleSpacing(
  value: unknown,
  field: string,
): number {
  const parsed = typeof value === "number" ? value : Number(value);
  if (!Number.isInteger(parsed) || parsed < 0 || parsed > maxSpacingMinutes) {
    throw new ApiError(
      400,
      `invalid_${field}`,
      `${field} must be an integer from 0 to ${maxSpacingMinutes}.`,
    );
  }
  return parsed;
}

export function optionalMedicationScheduleTimingNote(
  value: unknown,
): string | null {
  const normalized = normalizeOptional(value);
  if (normalized == null) return null;
  if (normalized.length > maxTimingNoteLength) {
    throw new ApiError(
      400,
      "invalid_timing_note",
      "timingNote is too long.",
    );
  }
  return normalized;
}

function mapTiming(row: Row): Record<string, unknown> {
  return {
    treatmentPlanId: row.id,
    treatmentPlanVersion: Number(row.plan_version),
    nearbyGroupingEnabled: row.nearby_grouping_enabled === true,
    timingLocked: row.timing_locked === true,
    manualSpacingBeforeMinutes: Number(
      row.manual_spacing_before_minutes ?? 0,
    ),
    manualSpacingAfterMinutes: Number(
      row.manual_spacing_after_minutes ?? 0,
    ),
    timingNote: row.timing_note ?? null,
    version: row.constraint_version == null
      ? 0
      : Number(row.constraint_version),
    updatedAtUtc: row.constraint_updated_at_utc == null
      ? null
      : new Date(row.constraint_updated_at_utc).toISOString(),
  };
}

export function createMedicationScheduleSettingsStore(databaseUrl: string) {
  const sql = getLifeMateSql(databaseUrl);

  async function requireSelfPerson(appUserId: string, connection: any = sql) {
    const rows = await connection`
      select core.self_person_id_for_legacy_app_user(${appUserId}::uuid)::text as person_id
    `;
    const personId = rows[0]?.person_id;
    if (typeof personId !== "string" || personId.length === 0) {
      throw new ApiError(
        409,
        "identity_person_mapping_missing",
        "Person mapping is unavailable.",
      );
    }
    return personId;
  }

  async function requireIanaTimeZone(value: unknown): Promise<string> {
    const zone = normalizeOptional(value);
    if (zone == null || zone.length > 64) {
      throw new ApiError(400, "invalid_time_zone", "timeZone is invalid.");
    }
    const rows = await sql`
      select exists(
        select 1 from pg_timezone_names where name = ${zone}
      ) as valid
    `;
    if (rows[0]?.valid !== true) {
      throw new ApiError(
        400,
        "invalid_time_zone",
        "timeZone must be a valid IANA time zone.",
      );
    }
    return zone;
  }

  async function getPreferences(
    appUserId: string,
  ): Promise<Record<string, unknown>> {
    const personId = await requireSelfPerson(appUserId);
    const rows = await sql`
      select p.time_zone as profile_time_zone,
             s.time_zone, s.sleep_window_enabled,
             s.sleep_start_local_time::text, s.sleep_end_local_time::text,
             s.version, s.updated_at_utc
      from core.person_profiles p
      left join lifemate.medication_schedule_preferences s
        on s.owner_person_id = p.person_id
      where p.person_id = ${personId}::uuid
      limit 1
    `;
    if (!rows[0]) {
      throw new ApiError(404, "profile_missing", "Profile was not found.");
    }
    const row = rows[0];
    return {
      timeZone: row.time_zone ?? row.profile_time_zone,
      sleepWindowEnabled: row.sleep_window_enabled === true,
      sleepStartLocalTime: row.sleep_start_local_time ?? null,
      sleepEndLocalTime: row.sleep_end_local_time ?? null,
      version: row.version == null ? 0 : Number(row.version),
      updatedAtUtc: row.updated_at_utc == null
        ? null
        : new Date(row.updated_at_utc).toISOString(),
    };
  }

  async function updatePreferences(
    appUserId: string,
    body: Record<string, unknown>,
  ): Promise<Record<string, unknown>> {
    const expectedVersion = requiredMedicationScheduleVersion(body.version);
    const timeZone = await requireIanaTimeZone(body.timeZone);
    const enabled = requiredMedicationScheduleBoolean(
      body.sleepWindowEnabled,
      "sleep_window_enabled",
    );
    const start = optionalMedicationScheduleLocalTime(
      body.sleepStartLocalTime,
      "sleep_start_local_time",
    );
    const end = optionalMedicationScheduleLocalTime(
      body.sleepEndLocalTime,
      "sleep_end_local_time",
    );
    if (enabled && (start == null || end == null)) {
      throw new ApiError(
        400,
        "sleep_window_incomplete",
        "Enabled sleep preferences require both start and end times.",
      );
    }
    const personId = await requireSelfPerson(appUserId);
    const changed = await sql.begin(async (tx: any) => {
      if (expectedVersion === 0) {
        return await tx`
          insert into lifemate.medication_schedule_preferences
            (owner_person_id, time_zone, sleep_window_enabled,
             sleep_start_local_time, sleep_end_local_time, version,
             created_at_utc, updated_at_utc)
          values
            (${personId}::uuid, ${timeZone}, ${enabled},
             ${enabled ? start : null}::time, ${enabled ? end : null}::time,
             1, now(), now())
          on conflict (owner_person_id) do nothing
          returning version
        `;
      }
      return await tx`
        update lifemate.medication_schedule_preferences
        set time_zone = ${timeZone},
            sleep_window_enabled = ${enabled},
            sleep_start_local_time = ${enabled ? start : null}::time,
            sleep_end_local_time = ${enabled ? end : null}::time,
            version = version + 1,
            updated_at_utc = now()
        where owner_person_id = ${personId}::uuid
          and version = ${expectedVersion}
        returning version
      `;
    });
    if (!changed[0]) {
      throw new ApiError(
        409,
        "stale_schedule_preferences",
        "Schedule preferences changed. Refresh and try again.",
      );
    }
    return await getPreferences(appUserId);
  }

  async function listPlanTimings(
    appUserId: string,
  ): Promise<Record<string, unknown>[]> {
    const personId = await requireSelfPerson(appUserId);
    const rows = await sql`
      select p.id, p.version as plan_version, p.status,
             p.recurrence_rule, p.recurrence_start_local_time::text,
             m.name as medication_name, m.strength_text,
             c.nearby_grouping_enabled, c.timing_locked,
             c.manual_spacing_before_minutes, c.manual_spacing_after_minutes,
             c.timing_note, c.version as constraint_version,
             c.updated_at_utc as constraint_updated_at_utc
      from lifemate.treatment_plans p
      join lifemate.medications m
        on m.id = p.medication_id
       and m.owner_person_id = p.patient_person_id
      left join lifemate.treatment_plan_timing_constraints c
        on c.treatment_plan_id = p.id
       and c.owner_person_id = p.patient_person_id
      where p.patient_person_id = ${personId}::uuid
        and p.status = 'Active'
      order by p.updated_at_utc desc, p.id
      limit 100
    `;
    return rows.map((row: Row) => ({
      ...mapTiming(row),
      medicationName: row.medication_name,
      strengthText: row.strength_text ?? null,
      recurrence: row.recurrence_rule ?? null,
      recurrenceStartLocalTime: row.recurrence_start_local_time == null
        ? null
        : String(row.recurrence_start_local_time).slice(0, 5),
    }));
  }

  async function getPlanTiming(
    appUserId: string,
    treatmentPlanId: string,
  ): Promise<Record<string, unknown>> {
    const personId = await requireSelfPerson(appUserId);
    const rows = await sql`
      select p.id, p.version as plan_version,
             c.nearby_grouping_enabled, c.timing_locked,
             c.manual_spacing_before_minutes, c.manual_spacing_after_minutes,
             c.timing_note, c.version as constraint_version,
             c.updated_at_utc as constraint_updated_at_utc
      from lifemate.treatment_plans p
      left join lifemate.treatment_plan_timing_constraints c
        on c.treatment_plan_id = p.id
      where p.id = ${treatmentPlanId}::uuid
        and p.patient_person_id = ${personId}::uuid
      limit 1
    `;
    if (!rows[0]) {
      throw new ApiError(
        404,
        "treatment_plan_missing",
        "Treatment plan was not found.",
      );
    }
    return mapTiming(rows[0]);
  }

  async function updatePlanTiming(
    appUserId: string,
    treatmentPlanId: string,
    body: Record<string, unknown>,
  ): Promise<Record<string, unknown>> {
    const expectedVersion = requiredMedicationScheduleVersion(body.version);
    const expectedPlanVersion = requiredPositiveInt(
      body.treatmentPlanVersion,
      "treatmentPlanVersion",
    );
    const nearby = requiredMedicationScheduleBoolean(
      body.nearbyGroupingEnabled,
      "nearby_grouping_enabled",
    );
    const locked = requiredMedicationScheduleBoolean(
      body.timingLocked,
      "timing_locked",
    );
    const before = requiredMedicationScheduleSpacing(
      body.manualSpacingBeforeMinutes,
      "manual_spacing_before_minutes",
    );
    const after = requiredMedicationScheduleSpacing(
      body.manualSpacingAfterMinutes,
      "manual_spacing_after_minutes",
    );
    const note = optionalMedicationScheduleTimingNote(body.timingNote);
    const personId = await requireSelfPerson(appUserId);

    const changed = await sql.begin(async (tx: any) => {
      const plan = await tx`
        select version
        from lifemate.treatment_plans
        where id = ${treatmentPlanId}::uuid
          and patient_person_id = ${personId}::uuid
        for update
      `;
      if (!plan[0]) {
        throw new ApiError(
          404,
          "treatment_plan_missing",
          "Treatment plan was not found.",
        );
      }
      if (Number(plan[0].version) !== expectedPlanVersion) {
        throw new ApiError(
          409,
          "stale_treatment_plan",
          "Treatment plan changed. Refresh and try again.",
        );
      }
      if (expectedVersion === 0) {
        return await tx`
          insert into lifemate.treatment_plan_timing_constraints
            (treatment_plan_id, owner_person_id, nearby_grouping_enabled,
             timing_locked, manual_spacing_before_minutes,
             manual_spacing_after_minutes, timing_note, version,
             created_at_utc, updated_at_utc)
          values
            (${treatmentPlanId}::uuid, ${personId}::uuid, ${nearby}, ${locked},
             ${before}, ${after}, ${note}, 1, now(), now())
          on conflict (treatment_plan_id) do nothing
          returning version
        `;
      }
      return await tx`
        update lifemate.treatment_plan_timing_constraints
        set nearby_grouping_enabled = ${nearby},
            timing_locked = ${locked},
            manual_spacing_before_minutes = ${before},
            manual_spacing_after_minutes = ${after},
            timing_note = ${note},
            version = version + 1,
            updated_at_utc = now()
        where treatment_plan_id = ${treatmentPlanId}::uuid
          and owner_person_id = ${personId}::uuid
          and version = ${expectedVersion}
        returning version
      `;
    });
    if (!changed[0]) {
      throw new ApiError(
        409,
        "stale_timing_constraints",
        "Timing constraints changed. Refresh and try again.",
      );
    }
    return await getPlanTiming(appUserId, treatmentPlanId);
  }

  return {
    getPreferences,
    updatePreferences,
    listPlanTimings,
    getPlanTiming,
    updatePlanTiming,
  };
}
