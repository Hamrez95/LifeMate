import { getLifeMateSql } from "./database_client.ts";
import {
  expandLocalRecurrence,
  normalizeRecurrenceRule,
  type RecurrenceRule,
} from "./recurrence_schedule.ts";
import {
  ApiError,
  limitedOptional,
  requiredDate,
  requiredText,
  requiredTimeZone,
  requiredUuid,
  validateRange,
} from "./validation.ts";

type CareEventType = "Appointment" | "Injection";
type Row = Record<string, any>;

type CareEventInput = {
  clientRequestId: string;
  eventType: CareEventType;
  title: string;
  providerName: string | null;
  specialty: string | null;
  medicationName: string | null;
  doseText: string | null;
  administrationRoute: string | null;
  reason: string | null;
  instructions: string | null;
  centerName: string | null;
  addressLine: string | null;
  phoneNumber: string | null;
  scheduledLocalDate: string;
  scheduledLocalTime: string;
  timeZone: string;
  recurrence: RecurrenceRule | null;
  patientReminderMinutesBefore: number;
  caregiverReminderMinutesBefore: number;
};

async function requireSelfPerson(
  connection: any,
  appUserId: string,
): Promise<string> {
  const rows = await connection`
    select core.self_person_id_for_legacy_app_user(${appUserId}::uuid)::text as person_id
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

export function createPersonCareEventStoreV2(databaseUrl: string) {
  const sql = getLifeMateSql(databaseUrl);

  async function createCareEvent(
    patientAppUserId: string,
    body: Record<string, unknown>,
  ): Promise<Record<string, unknown>> {
    const input = normalizeCareEvent(body);
    return await sql.begin(async (tx: any) => {
      const patientPersonId = await requireSelfPerson(tx, patientAppUserId);
      const existing = await tx`
        select * from lifemate.care_events
        where patient_person_id = ${patientPersonId}::uuid
          and client_request_id = ${input.clientRequestId}::uuid
        limit 1
      `;
      if (existing[0]) {
        if (!sameCareEvent(existing[0], input)) {
          throw new ApiError(
            409,
            "idempotency_key_reused",
            "clientRequestId was already used for a different care event.",
          );
        }
        return mapCareEvent(existing[0], patientAppUserId);
      }

      const id = crypto.randomUUID();
      const recurrenceJson = input.recurrence == null
        ? null
        : JSON.stringify(input.recurrence);
      const rows = await tx`
        insert into lifemate.care_events
          (id, patient_person_id, created_by_user_id, client_request_id,
           event_type, title, provider_name, specialty, medication_name,
           dose_text, administration_route, reason, instructions, center_name,
           address_line, phone_number, scheduled_local_date,
           scheduled_local_time, time_zone,
           recurrence_unit, recurrence_interval, recurrence_weekdays,
           recurrence_end_date, recurrence_rule,
           patient_reminder_minutes_before, caregiver_reminder_minutes_before,
           status, version, created_at_utc, updated_at_utc)
        values
          (${id}::uuid, ${patientPersonId}::uuid, ${patientAppUserId}::uuid,
           ${input.clientRequestId}::uuid, ${input.eventType}, ${input.title},
           ${input.providerName}, ${input.specialty}, ${input.medicationName},
           ${input.doseText}, ${input.administrationRoute}, ${input.reason},
           ${input.instructions}, ${input.centerName}, ${input.addressLine},
           ${input.phoneNumber}, ${input.scheduledLocalDate}::date,
           ${input.scheduledLocalTime}::time, ${input.timeZone},
           'none', 1, array[]::smallint[], null, ${recurrenceJson}::jsonb,
           ${input.patientReminderMinutesBefore},
           ${input.caregiverReminderMinutesBefore}, 'Scheduled', 1, now(), now())
        returning *
      `;
      await insertAudit(tx, patientAppUserId, "care_event.created", id, {
        eventType: input.eventType,
        recurrenceVersion: input.recurrence?.version ?? null,
      });
      return mapCareEvent(rows[0], patientAppUserId);
    });
  }

  async function listCareEvents(
    patientAppUserId: string,
    fromValue: unknown,
    toValue: unknown,
  ): Promise<Record<string, unknown>[]> {
    const { fromDate, toDate } = normalizeRange(fromValue, toValue);
    const patientPersonId = await requireSelfPerson(sql, patientAppUserId);
    return await selectCareEvents(
      patientAppUserId,
      patientPersonId,
      fromDate,
      toDate,
    );
  }

  async function selectCareEvents(
    patientAppUserId: string,
    patientPersonId: string,
    fromDate: string,
    toDate: string,
  ): Promise<Record<string, unknown>[]> {
    const rows = await sql`
      select * from lifemate.care_events
      where patient_person_id = ${patientPersonId}::uuid
        and status <> 'Cancelled'
        and scheduled_local_date <= ${toDate}::date
        and (
          recurrence_rule is not null
          or recurrence_unit = 'none'
          or recurrence_end_date is null
          or recurrence_end_date >= ${fromDate}::date
        )
      order by scheduled_local_date, scheduled_local_time, id
      limit 200
    `;
    const expanded: Record<string, unknown>[] = [];
    for (const row of rows) {
      const recurrence = recurrenceFromRow(row);
      if (recurrence == null) {
        const local = `${dateString(row.scheduled_local_date)}T${
          timeString(row.scheduled_local_time)
        }:00`;
        if (local >= `${fromDate}T00:00:00` && local <= `${toDate}T23:59:59`) {
          expanded.push(mapCareEvent(row, patientAppUserId, local));
        }
        continue;
      }
      const startLocal = `${dateString(row.scheduled_local_date)}T${
        timeString(row.scheduled_local_time)
      }:00`;
      const values = expandLocalRecurrence(
        startLocal,
        recurrence,
        `${fromDate}T00:00:00`,
        `${toDate}T23:59:59`,
        500,
      );
      for (const local of values) {
        expanded.push(mapCareEvent(row, patientAppUserId, local));
      }
    }
    expanded.sort((left, right) =>
      String(left.scheduledAtUtc).localeCompare(String(right.scheduledAtUtc))
    );
    return expanded.slice(0, 500);
  }

  return { createCareEvent, listCareEvents };
}

function normalizeCareEvent(body: Record<string, unknown>): CareEventInput {
  const eventType = normalizeEventType(body.eventType);
  const scheduledLocalDate = requiredDate(
    body.scheduledLocalDate,
    "scheduledLocalDate",
  );
  const scheduledLocalTime = requiredLocalTime(
    body.scheduledLocalTime,
    "scheduledLocalTime",
  );
  const recurrence = normalizeRecurrenceRule(body.recurrence);
  if (
    recurrence?.endAt != null &&
    recurrence.endAt.slice(0, 10) < scheduledLocalDate
  ) {
    throw new ApiError(
      400,
      "invalid_recurrence_end",
      "Recurrence end cannot precede its start.",
    );
  }
  const medicationName = limitedOptional(
    body.medicationName,
    "medicationName",
    160,
  );
  if (eventType === "Injection" && !medicationName) {
    throw new ApiError(
      400,
      "invalid_medicationName",
      "medicationName is required for injection events.",
    );
  }
  return {
    clientRequestId: requiredUuid(body.clientRequestId, "clientRequestId"),
    eventType,
    title: requiredText(body.title, "title", 160),
    providerName: limitedOptional(body.providerName, "providerName", 160),
    specialty: limitedOptional(body.specialty, "specialty", 120),
    medicationName,
    doseText: limitedOptional(body.doseText, "doseText", 120),
    administrationRoute: normalizeAdministrationRoute(body.administrationRoute),
    reason: limitedOptional(body.reason, "reason", 500),
    instructions: limitedOptional(body.instructions, "instructions", 1000),
    centerName: limitedOptional(body.centerName, "centerName", 200),
    addressLine: limitedOptional(body.addressLine, "addressLine", 500),
    phoneNumber: limitedOptional(body.phoneNumber, "phoneNumber", 40),
    scheduledLocalDate,
    scheduledLocalTime,
    timeZone: requiredTimeZone(body.timeZone),
    recurrence,
    patientReminderMinutesBefore: normalizeReminderLeadTime(
      body.patientReminderMinutesBefore,
      "patientReminderMinutesBefore",
      30,
    ),
    caregiverReminderMinutesBefore: normalizeReminderLeadTime(
      body.caregiverReminderMinutesBefore,
      "caregiverReminderMinutesBefore",
      60,
    ),
  };
}

function recurrenceFromRow(row: Row): RecurrenceRule | null {
  if (row.recurrence_rule != null) {
    const value = typeof row.recurrence_rule === "string"
      ? JSON.parse(row.recurrence_rule)
      : row.recurrence_rule;
    return normalizeRecurrenceRule(value);
  }
  const unit = String(row.recurrence_unit ?? "none").toLowerCase();
  if (unit === "none") return null;
  return normalizeRecurrenceRule({
    version: 1,
    enabled: true,
    unit,
    interval: Number(row.recurrence_interval ?? 1),
    weekdays: Array.isArray(row.recurrence_weekdays)
      ? row.recurrence_weekdays.map(Number)
      : [],
    endDate: row.recurrence_end_date == null
      ? null
      : dateString(row.recurrence_end_date),
  });
}

function publicRecurrence(row: Row): Record<string, unknown> {
  const rule = recurrenceFromRow(row);
  if (rule == null) {
    return { version: 2, enabled: false };
  }
  return {
    version: rule.version,
    enabled: true,
    unit: rule.unit,
    interval: rule.interval,
    weekdays: rule.weekdays,
    endDate: rule.endAt == null
      ? null
      : rule.unit === "hour"
      ? rule.endAt
      : rule.endAt.slice(0, 10),
    maxOccurrences: rule.maxOccurrences,
  };
}

function sameCareEvent(row: Row, input: CareEventInput): boolean {
  const stored = recurrenceFromRow(row);
  return String(row.event_type) === input.eventType &&
    String(row.title) === input.title &&
    nullable(row.provider_name) === input.providerName &&
    nullable(row.specialty) === input.specialty &&
    nullable(row.medication_name) === input.medicationName &&
    nullable(row.dose_text) === input.doseText &&
    nullable(row.administration_route) === input.administrationRoute &&
    nullable(row.reason) === input.reason &&
    nullable(row.instructions) === input.instructions &&
    nullable(row.center_name) === input.centerName &&
    nullable(row.address_line) === input.addressLine &&
    nullable(row.phone_number) === input.phoneNumber &&
    dateString(row.scheduled_local_date) === input.scheduledLocalDate &&
    timeString(row.scheduled_local_time) === input.scheduledLocalTime &&
    String(row.time_zone) === input.timeZone &&
    JSON.stringify(stored) === JSON.stringify(input.recurrence) &&
    Number(row.patient_reminder_minutes_before ?? 30) ===
      input.patientReminderMinutesBefore &&
    Number(row.caregiver_reminder_minutes_before ?? 60) ===
      input.caregiverReminderMinutesBefore;
}

function mapCareEvent(
  row: Row,
  patientAppUserId: string,
  occurrenceLocal?: string,
): Record<string, unknown> {
  const baseLocal = `${dateString(row.scheduled_local_date)}T${
    timeString(row.scheduled_local_time)
  }:00`;
  const local = occurrenceLocal ?? baseLocal;
  const recurrence = recurrenceFromRow(row);
  const recurringOccurrence = recurrence != null && occurrenceLocal != null;
  const scheduledAtUtc = localDateTimeToUtc(local, String(row.time_zone));
  const storedStatus = String(row.status).toLowerCase();
  const status =
    storedStatus === "scheduled" && new Date(scheduledAtUtc) < new Date()
      ? "missed"
      : storedStatus;
  const occurrenceKey = local.replace("T", "@");
  return {
    id: recurringOccurrence ? `${row.id}:${occurrenceKey}` : String(row.id),
    seriesId: String(row.id),
    occurrenceId: `${row.id}:${occurrenceKey}`,
    patientUserId: patientAppUserId,
    eventType: String(row.event_type).toLowerCase(),
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
    scheduledLocalDate: local.slice(0, 10),
    scheduledLocalTime: local.slice(11, 16),
    scheduledAtUtc,
    timeZone: row.time_zone,
    recurrence: publicRecurrence(row),
    patientReminderMinutesBefore: Number(
      row.patient_reminder_minutes_before ?? 30,
    ),
    caregiverReminderMinutesBefore: Number(
      row.caregiver_reminder_minutes_before ?? 60,
    ),
    status,
    version: row.version,
    createdAtUtc: iso(row.created_at_utc),
    updatedAtUtc: iso(row.updated_at_utc),
  };
}

function normalizeRange(
  fromValue: unknown,
  toValue: unknown,
): { fromDate: string; toDate: string } {
  const fromDate = requiredDate(fromValue, "fromDate");
  const toDate = requiredDate(toValue, "toDate");
  validateRange(fromDate, toDate, 31);
  return { fromDate, toDate };
}

function normalizeEventType(value: unknown): CareEventType {
  const normalized = String(value ?? "").trim().toLowerCase();
  if (
    normalized === "appointment" || normalized === "visit" ||
    normalized === "checkup"
  ) return "Appointment";
  if (normalized === "injection") return "Injection";
  throw new ApiError(
    400,
    "invalid_eventType",
    "eventType must be appointment or injection.",
  );
}

function normalizeAdministrationRoute(value: unknown): string | null {
  const normalized = String(value ?? "").trim().toLowerCase();
  if (!normalized) return null;
  const routes: Record<string, string> = {
    intramuscular: "Intramuscular",
    subcutaneous: "Subcutaneous",
    intravenous: "Intravenous",
    other: "Other",
  };
  const route = routes[normalized];
  if (!route) {
    throw new ApiError(
      400,
      "invalid_administrationRoute",
      "Unsupported administration route.",
    );
  }
  return route;
}

function requiredLocalTime(value: unknown, field: string): string {
  const match = /^(\d{2}):(\d{2})(?::(\d{2}))?$/.exec(
    String(value ?? "").trim(),
  );
  if (
    !match || Number(match[1]) > 23 || Number(match[2]) > 59 ||
    Number(match[3] ?? 0) > 59
  ) {
    throw new ApiError(
      400,
      `invalid_${field}`,
      `${field} must be a valid HH:mm value.`,
    );
  }
  return `${match[1]}:${match[2]}`;
}

function normalizeReminderLeadTime(
  value: unknown,
  field: string,
  fallback: number,
): number {
  if (value == null || value === "") return fallback;
  const parsed = Number(value);
  if (!Number.isInteger(parsed) || parsed < 0 || parsed > 10080) {
    throw new ApiError(
      400,
      `invalid_${field}`,
      `${field} must be an integer between 0 and 10080 minutes.`,
    );
  }
  return parsed;
}

function localDateTimeToUtc(local: string, timeZone: string): string {
  const [datePart, timePart] = local.split("T");
  const [year, month, day] = datePart.split("-").map(Number);
  const [hour, minute, second] = timePart.split(":").map(Number);
  const targetAsUtc = Date.UTC(year, month - 1, day, hour, minute, second ?? 0);
  let guess = targetAsUtc;
  const formatter = new Intl.DateTimeFormat("en-CA", {
    timeZone,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit",
    hourCycle: "h23",
  });
  for (let attempt = 0; attempt < 4; attempt++) {
    const parts = Object.fromEntries(
      formatter.formatToParts(new Date(guess)).map((
        part,
      ) => [part.type, part.value]),
    );
    const represented = Date.UTC(
      Number(parts.year),
      Number(parts.month) - 1,
      Number(parts.day),
      Number(parts.hour),
      Number(parts.minute),
      Number(parts.second),
    );
    const delta = targetAsUtc - represented;
    guess += delta;
    if (Math.abs(delta) < 1000) break;
  }
  return new Date(guess).toISOString();
}

async function insertAudit(
  sql: any,
  actorUserId: string,
  action: string,
  resourceId: string,
  metadata: Record<string, unknown>,
): Promise<void> {
  await sql`
    insert into lifemate.audit_logs
      (id, actor_user_id, action, resource_type, resource_id, metadata_json, created_at_utc)
    values
      (${crypto.randomUUID()}::uuid, ${actorUserId}::uuid, ${action},
       'care_event', ${resourceId}::uuid, ${JSON.stringify(metadata)}, now())
  `;
}

function nullable(value: unknown): string | null {
  return value == null ? null : String(value);
}

function dateString(value: unknown): string {
  if (value instanceof Date) return value.toISOString().slice(0, 10);
  return String(value).slice(0, 10);
}

function timeString(value: unknown): string {
  return String(value).slice(0, 5);
}

function iso(value: unknown): string | null {
  if (value == null) return null;
  if (value instanceof Date) return value.toISOString();
  return new Date(String(value)).toISOString();
}
