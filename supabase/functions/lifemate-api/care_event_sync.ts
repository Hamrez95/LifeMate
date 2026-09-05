import { getLifeMateSql } from "./database_client.ts";
import { ApiError } from "./validation.ts";

type Row = Record<string, any>;

type SyncCursor = {
  updatedAtUtc: string;
  id: string;
};

const originCursor: SyncCursor = {
  updatedAtUtc: "1970-01-01T00:00:00.000Z",
  id: "00000000-0000-1000-8000-000000000000",
};

const uuidPattern =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export type LifeMateProjectionSyncChange = {
  recordKey: string;
  deleted: boolean;
  sourceRevision: string;
  sourceUpdatedAtUtc: string;
  payload: Record<string, unknown> | null;
};

export type LifeMateProjectionSyncPage = {
  nextCursor: string;
  hasMore: boolean;
  changes: LifeMateProjectionSyncChange[];
};

export function createCareEventSyncStore(databaseUrl: string) {
  const sql = getLifeMateSql(databaseUrl);

  async function pullOwnerCareEvents(
    appUserId: string,
    cursorValue: unknown,
    limitValue: unknown,
  ): Promise<LifeMateProjectionSyncPage> {
    const personId = await requireSelfPerson(sql, appUserId);
    const cursor = decodeSyncCursor(cursorValue);
    const limit = normalizeLimit(limitValue);
    const rows = await sql`
      select *
      from lifemate.care_events
      where patient_person_id = ${personId}::uuid
        and (
          updated_at_utc > ${cursor.updatedAtUtc}::timestamptz
          or (
            updated_at_utc = ${cursor.updatedAtUtc}::timestamptz
            and id > ${cursor.id}::uuid
          )
        )
      order by updated_at_utc, id
      limit ${limit + 1}
    `;

    const hasMore = rows.length > limit;
    const selected = rows.slice(0, limit);
    const tail = selected[selected.length - 1];
    const nextCursor = tail == null
      ? encodeSyncCursor(cursor)
      : encodeSyncCursor({
        updatedAtUtc: iso(tail.updated_at_utc),
        id: String(tail.id),
      });

    return {
      nextCursor,
      hasMore,
      changes: selected.map(mapChange),
    };
  }

  return { pullOwnerCareEvents };
}

export function encodeSyncCursor(cursor: SyncCursor): string {
  const updatedAtUtc = normalizeTimestamp(cursor.updatedAtUtc);
  const id = normalizeUuid(cursor.id, "cursor id");
  const json = JSON.stringify({ v: 1, updatedAtUtc, id });
  const encoded = btoa(json)
    .replaceAll("+", "-")
    .replaceAll("/", "_")
    .replace(/=+$/u, "");
  return `v1.${encoded}`;
}

export function decodeSyncCursor(value: unknown): SyncCursor {
  if (value == null || String(value).trim().length === 0) {
    return { ...originCursor };
  }
  const raw = String(value).trim();
  if (raw.length > 2048 || !raw.startsWith("v1.")) {
    throw invalidCursor();
  }
  try {
    const encoded = raw.slice(3).replaceAll("-", "+").replaceAll("_", "/");
    const padding = "=".repeat((4 - (encoded.length % 4)) % 4);
    const parsed = JSON.parse(atob(encoded + padding));
    if (parsed?.v !== 1) throw invalidCursor();
    return {
      updatedAtUtc: normalizeTimestamp(parsed.updatedAtUtc),
      id: normalizeUuid(parsed.id, "cursor id"),
    };
  } catch (error) {
    if (error instanceof ApiError) throw error;
    throw invalidCursor();
  }
}

function mapChange(row: Row): LifeMateProjectionSyncChange {
  const updatedAtUtc = iso(row.updated_at_utc);
  const deleted = String(row.status ?? "").toLowerCase() === "cancelled";
  return {
    recordKey: String(row.id),
    deleted,
    sourceRevision: String(row.version ?? 1),
    sourceUpdatedAtUtc: updatedAtUtc,
    payload: deleted ? null : mapPayload(row, updatedAtUtc),
  };
}

function mapPayload(
  row: Row,
  updatedAtUtc: string,
): Record<string, unknown> {
  const recurrenceUnit = String(row.recurrence_unit ?? "none").toLowerCase();
  return {
    id: String(row.id),
    seriesId: String(row.id),
    eventType: String(row.event_type ?? "").toLowerCase(),
    title: row.title,
    providerName: row.provider_name,
    specialty: row.specialty,
    medicationName: row.medication_name,
    doseText: row.dose_text,
    administrationRoute: row.administration_route == null
      ? null
      : String(row.administration_route).toLowerCase(),
    reason: row.reason,
    instructions: row.instructions,
    centerName: row.center_name,
    addressLine: row.address_line,
    phoneNumber: row.phone_number,
    scheduledLocalDate: dateString(row.scheduled_local_date),
    scheduledLocalTime: timeString(row.scheduled_local_time),
    timeZone: String(row.time_zone),
    recurrence: {
      enabled: recurrenceUnit !== "none",
      unit: recurrenceUnit,
      interval: Number(row.recurrence_interval ?? 1),
      weekdays: Array.isArray(row.recurrence_weekdays)
        ? row.recurrence_weekdays.map(Number).filter(Number.isInteger)
        : [],
      endDate: row.recurrence_end_date == null
        ? null
        : dateString(row.recurrence_end_date),
    },
    patientReminderMinutesBefore: Number(
      row.patient_reminder_minutes_before ?? 30,
    ),
    caregiverReminderMinutesBefore: Number(
      row.caregiver_reminder_minutes_before ?? 60,
    ),
    status: String(row.status ?? "scheduled").toLowerCase(),
    version: Number(row.version ?? 1),
    createdAtUtc: iso(row.created_at_utc),
    updatedAtUtc,
  };
}

async function requireSelfPerson(connection: any, appUserId: string) {
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

function normalizeLimit(value: unknown): number {
  if (value == null || String(value).trim().length === 0) return 100;
  const parsed = Number(value);
  if (!Number.isInteger(parsed) || parsed < 1 || parsed > 200) {
    throw new ApiError(
      400,
      "invalid_sync_limit",
      "Sync limit must be an integer between 1 and 200.",
    );
  }
  return parsed;
}

function normalizeTimestamp(value: unknown): string {
  const raw = String(value ?? "").trim();
  const parsed = new Date(raw);
  if (raw.length === 0 || Number.isNaN(parsed.getTime())) {
    throw invalidCursor();
  }
  return parsed.toISOString();
}

function normalizeUuid(value: unknown, field: string): string {
  const raw = String(value ?? "").trim().toLowerCase();
  if (!uuidPattern.test(raw)) {
    throw new ApiError(400, "invalid_sync_cursor", `Invalid ${field}.`);
  }
  return raw;
}

function invalidCursor(): ApiError {
  return new ApiError(
    400,
    "invalid_sync_cursor",
    "Sync cursor is invalid or unsupported.",
  );
}

function iso(value: unknown): string {
  return new Date(value as string | number | Date).toISOString();
}

function dateString(value: unknown): string {
  if (value instanceof Date) return value.toISOString().slice(0, 10);
  return String(value ?? "").slice(0, 10);
}

function timeString(value: unknown): string {
  const text = String(value ?? "");
  const match = /^(\d{2}:\d{2})/.exec(text);
  return match?.[1] ?? text;
}
