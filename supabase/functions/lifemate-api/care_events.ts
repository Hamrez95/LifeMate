import { getLifeMateSql } from "./database_client.ts";
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
type CareEventRecurrenceUnit = "none" | "day" | "week" | "month" | "year";

export type CareEventRecurrence = {
  enabled: boolean;
  unit: CareEventRecurrenceUnit;
  interval: number;
  weekdays: number[];
  endDate: string | null;
};

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
  recurrence: CareEventRecurrence;
  patientReminderMinutesBefore: number;
  caregiverReminderMinutesBefore: number;
};

export function createCareEventStore(databaseUrl: string) {
  const sql = getLifeMateSql(databaseUrl);

  async function createCareEvent(
    patientUserId: string,
    body: Record<string, unknown>,
  ): Promise<Record<string, unknown>> {
    const input = normalizeCareEvent(body);
    const now = new Date();
    return await sql.begin(async (tx: any) => {
      const existingRows = await tx`
        select * from lifemate.care_events
        where patient_user_id = ${patientUserId}
          and client_request_id = ${input.clientRequestId}
        limit 1
      `;
      if (existingRows[0]) {
        if (!sameCareEvent(existingRows[0], input)) {
          throw new ApiError(
            409,
            "idempotency_key_reused",
            "clientRequestId was already used for a different care event.",
          );
        }
        return mapCareEvent(existingRows[0]);
      }

      const id = crypto.randomUUID();
      const rows = await tx`
        insert into lifemate.care_events
          (id, patient_user_id, client_request_id, event_type, title,
           provider_name, specialty, medication_name, dose_text,
           administration_route, reason, instructions, center_name,
           address_line, phone_number, scheduled_local_date,
           scheduled_local_time, time_zone, recurrence_unit,
           recurrence_interval, recurrence_weekdays, recurrence_end_date,
           patient_reminder_minutes_before,
           caregiver_reminder_minutes_before, status, version,
           created_at_utc, updated_at_utc)
        values
          (${id}, ${patientUserId}, ${input.clientRequestId},
           ${input.eventType}, ${input.title}, ${input.providerName},
           ${input.specialty}, ${input.medicationName}, ${input.doseText},
           ${input.administrationRoute}, ${input.reason}, ${input.instructions},
           ${input.centerName}, ${input.addressLine}, ${input.phoneNumber},
           ${input.scheduledLocalDate}, ${input.scheduledLocalTime},
           ${input.timeZone}, ${input.recurrence.unit},
           ${input.recurrence.interval}, ${input.recurrence.weekdays},
           ${input.recurrence.endDate}, ${input.patientReminderMinutesBefore},
           ${input.caregiverReminderMinutesBefore}, 'Scheduled', 1,
           ${now}, ${now})
        returning *
      `;
      await insertAudit(
        tx,
        patientUserId,
        "care_event.created",
        "care_event",
        id,
        { eventType: input.eventType },
      );
      return mapCareEvent(rows[0]);
    });
  }

  async function listCareEvents(
    patientUserId: string,
    fromValue: unknown,
    toValue: unknown,
  ): Promise<Record<string, unknown>[]> {
    const { fromDate, toDate } = normalizeRange(fromValue, toValue);
    return await selectCareEvents(patientUserId, fromDate, toDate);
  }

  async function listCareRecipientEvents(
    caregiverUserId: string,
    patientUserIdValue: unknown,
    fromValue: unknown,
    toValue: unknown,
  ): Promise<Record<string, unknown>[]> {
    const patientUserId = requiredUuid(patientUserIdValue, "patientUserId");
    const relationship = await sql`
      select id from lifemate.care_relationships
      where patient_user_id = ${patientUserId}
        and caregiver_user_id = ${caregiverUserId}
        and status = 'Active'
      limit 1
    `;
    if (!relationship[0]) {
      throw new ApiError(
        403,
        "care_access_denied",
        "An active care relationship is required.",
      );
    }
    const { fromDate, toDate } = normalizeRange(fromValue, toValue);
    return await selectCareEvents(patientUserId, fromDate, toDate);
  }

  async function selectCareEvents(
    patientUserId: string,
    fromDate: string,
    toDate: string,
  ): Promise<Record<string, unknown>[]> {
    // Select series whose base/recurrence window can intersect the requested
    // range, then deterministically expand only the bounded range in memory.
    const rows = await sql`
      select *
      from lifemate.care_events
      where patient_user_id = ${patientUserId}
        and status <> 'Cancelled'
        and scheduled_local_date <= ${toDate}::date
        and (
          recurrence_unit = 'none'
          or recurrence_end_date is null
          or recurrence_end_date >= ${fromDate}::date
        )
      order by scheduled_local_date, scheduled_local_time, id
      limit 200
    `;
    const expanded: Record<string, unknown>[] = [];
    for (const row of rows) {
      const recurrence = recurrenceFromRow(row);
      const dates = generateCareEventOccurrenceDates(
        dateString(row.scheduled_local_date),
        recurrence,
        fromDate,
        toDate,
      );
      for (const occurrenceDate of dates) {
        expanded.push(mapCareEvent(row, occurrenceDate));
      }
    }
    expanded.sort((left, right) => {
      const l =
        `${left.scheduledLocalDate} ${left.scheduledLocalTime} ${left.id}`;
      const r =
        `${right.scheduledLocalDate} ${right.scheduledLocalTime} ${right.id}`;
      return l.localeCompare(r);
    });
    return expanded.slice(0, 500);
  }

  return { createCareEvent, listCareEvents, listCareRecipientEvents };
}

export function generateCareEventOccurrenceDates(
  startDate: string,
  recurrence: CareEventRecurrence,
  fromDate: string,
  toDate: string,
): string[] {
  const start = parseDate(startDate);
  const from = parseDate(fromDate);
  const to = parseDate(toDate);
  const recurrenceEnd = recurrence.endDate == null
    ? to
    : minDate(parseDate(recurrence.endDate), to);
  if (to < from || recurrenceEnd < start || to < start) return [];
  if (!recurrence.enabled || recurrence.unit === "none") {
    return start >= from && start <= recurrenceEnd ? [formatDate(start)] : [];
  }

  const values = new Set<string>();
  if (recurrence.unit === "day") {
    for (
      let cursor = start, guard = 0;
      cursor <= recurrenceEnd && guard < 5000;
      cursor = addDays(cursor, recurrence.interval), guard++
    ) {
      if (cursor >= from) values.add(formatDate(cursor));
    }
  } else if (recurrence.unit === "week") {
    const allowed = new Set(
      recurrence.weekdays.length > 0
        ? recurrence.weekdays
        : [isoWeekday(start)],
    );
    let cursor = maxDate(start, from);
    for (let guard = 0; cursor <= recurrenceEnd && guard < 5000; guard++) {
      const daysFromStart = Math.floor(
        (cursor.getTime() - start.getTime()) / 86400000,
      );
      const weekIndex = Math.floor(daysFromStart / 7);
      if (
        weekIndex % recurrence.interval === 0 &&
        allowed.has(isoWeekday(cursor))
      ) {
        values.add(formatDate(cursor));
      }
      cursor = addDays(cursor, 1);
    }
  } else {
    const monthFactor = recurrence.unit === "year" ? 12 : 1;
    const maximum = recurrence.unit === "year" ? 400 : 2400;
    for (let occurrence = 0; occurrence < maximum; occurrence++) {
      const cursor = addMonthsClamped(
        start,
        occurrence * recurrence.interval * monthFactor,
      );
      if (cursor > recurrenceEnd) break;
      if (cursor >= from) values.add(formatDate(cursor));
    }
  }
  return [...values].sort();
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

function normalizeCareEvent(body: Record<string, unknown>): CareEventInput {
  const eventType = normalizeEventType(body.eventType);
  const title = requiredText(body.title, "title", 160);
  const scheduledLocalDate = requiredDate(
    body.scheduledLocalDate,
    "scheduledLocalDate",
  );
  const scheduledLocalTime = requiredLocalTime(
    body.scheduledLocalTime,
    "scheduledLocalTime",
  );
  const timeZone = requiredTimeZone(body.timeZone);
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
    title,
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
    timeZone,
    recurrence: normalizeRecurrence(body.recurrence, scheduledLocalDate),
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

function normalizeRecurrence(
  value: unknown,
  startDate: string,
): CareEventRecurrence {
  if (value == null) return noRecurrence();
  if (typeof value !== "object" || Array.isArray(value)) {
    throw new ApiError(
      400,
      "invalid_recurrence",
      "recurrence must be an object.",
    );
  }
  const record = value as Record<string, unknown>;
  if (record.enabled !== true) return noRecurrence();
  const unitAliases: Record<string, CareEventRecurrenceUnit> = {
    day: "day",
    days: "day",
    week: "week",
    weeks: "week",
    month: "month",
    months: "month",
    year: "year",
    years: "year",
  };
  const unit = unitAliases[String(record.unit ?? "").trim().toLowerCase()];
  if (!unit) {
    throw new ApiError(
      400,
      "invalid_recurrence_unit",
      "Unsupported recurrence unit.",
    );
  }
  const interval = Number(record.interval ?? 1);
  if (!Number.isInteger(interval) || interval < 1 || interval > 365) {
    throw new ApiError(
      400,
      "invalid_recurrence_interval",
      "recurrence interval must be between 1 and 365.",
    );
  }
  const rawWeekdays = record.weekdays ?? [];
  if (!Array.isArray(rawWeekdays)) {
    throw new ApiError(
      400,
      "invalid_recurrence_weekdays",
      "weekdays must be an array.",
    );
  }
  const weekdays = [...new Set(rawWeekdays.map(Number))].sort((a, b) => a - b);
  if (weekdays.some((day) => !Number.isInteger(day) || day < 1 || day > 7)) {
    throw new ApiError(
      400,
      "invalid_recurrence_weekdays",
      "weekdays must use ISO values 1..7.",
    );
  }
  const endDate = record.endDate == null
    ? null
    : requiredDate(record.endDate, "recurrence.endDate");
  if (endDate != null && endDate < startDate) {
    throw new ApiError(
      400,
      "invalid_recurrence_end",
      "recurrence end date cannot precede the start date.",
    );
  }
  return {
    enabled: true,
    unit,
    interval,
    weekdays: unit === "week" ? weekdays : [],
    endDate,
  };
}

function noRecurrence(): CareEventRecurrence {
  return {
    enabled: false,
    unit: "none",
    interval: 1,
    weekdays: [],
    endDate: null,
  };
}

function recurrenceFromRow(row: Record<string, any>): CareEventRecurrence {
  const unit = String(row.recurrence_unit ?? "none") as CareEventRecurrenceUnit;
  const weekdays = Array.isArray(row.recurrence_weekdays)
    ? row.recurrence_weekdays.map(Number).filter(Number.isInteger)
    : [];
  return {
    enabled: unit !== "none",
    unit,
    interval: Number(row.recurrence_interval ?? 1),
    weekdays,
    endDate: row.recurrence_end_date == null
      ? null
      : dateString(row.recurrence_end_date),
  };
}

function normalizeEventType(value: unknown): CareEventType {
  const normalized = String(value ?? "").trim().toLowerCase();
  if (normalized === "appointment" || normalized === "visit") {
    return "Appointment";
  }
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
  const match = /^(\d{2}):(\d{2})(?::\d{2})?$/.exec(String(value ?? "").trim());
  if (!match || Number(match[1]) > 23 || Number(match[2]) > 59) {
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

function sameCareEvent(
  row: Record<string, any>,
  input: CareEventInput,
): boolean {
  const recurrence = recurrenceFromRow(row);
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
    recurrence.unit === input.recurrence.unit &&
    recurrence.interval === input.recurrence.interval &&
    JSON.stringify(recurrence.weekdays) ===
      JSON.stringify(input.recurrence.weekdays) &&
    recurrence.endDate === input.recurrence.endDate &&
    Number(row.patient_reminder_minutes_before ?? 30) ===
      input.patientReminderMinutesBefore &&
    Number(row.caregiver_reminder_minutes_before ?? 60) ===
      input.caregiverReminderMinutesBefore;
}

function mapCareEvent(
  row: Record<string, any>,
  occurrenceDateValue?: string,
): Record<string, unknown> {
  const recurrence = recurrenceFromRow(row);
  const baseId = String(row.id);
  const occurrenceDate = occurrenceDateValue ??
    dateString(row.scheduled_local_date);
  const recurringOccurrence = recurrence.enabled && occurrenceDateValue != null;
  const scheduledAtUtc = localDateTimeToUtc(
    occurrenceDate,
    timeString(row.scheduled_local_time),
    String(row.time_zone),
  );
  const storedStatus = String(row.status).toLowerCase();
  const status =
    storedStatus === "scheduled" && new Date(scheduledAtUtc) < new Date()
      ? "missed"
      : storedStatus;
  return {
    id: recurringOccurrence ? `${baseId}:${occurrenceDate}` : baseId,
    seriesId: baseId,
    occurrenceId: `${baseId}:${occurrenceDate}`,
    patientUserId: row.patient_user_id,
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
    scheduledLocalDate: occurrenceDate,
    scheduledLocalTime: timeString(row.scheduled_local_time),
    scheduledAtUtc,
    timeZone: row.time_zone,
    recurrence,
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

function localDateTimeToUtc(
  date: string,
  time: string,
  timeZone: string,
): string {
  const [year, month, day] = date.split("-").map(Number);
  const [hour, minute] = time.split(":").map(Number);
  const targetAsUtc = Date.UTC(year, month - 1, day, hour, minute);
  let guess = targetAsUtc;
  const formatter = new Intl.DateTimeFormat("en-CA", {
    timeZone,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    hourCycle: "h23",
  });
  for (let attempt = 0; attempt < 3; attempt++) {
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
    );
    const delta = targetAsUtc - represented;
    guess += delta;
    if (Math.abs(delta) < 60_000) break;
  }
  return new Date(guess).toISOString();
}

function parseDate(value: string): Date {
  return new Date(`${value}T00:00:00.000Z`);
}

function formatDate(value: Date): string {
  return value.toISOString().slice(0, 10);
}

function addDays(value: Date, days: number): Date {
  return new Date(value.getTime() + days * 86400000);
}

function addMonthsClamped(value: Date, months: number): Date {
  const year = value.getUTCFullYear();
  const month = value.getUTCMonth();
  const day = value.getUTCDate();
  const first = new Date(Date.UTC(year, month + months, 1));
  const lastDay = new Date(
    Date.UTC(first.getUTCFullYear(), first.getUTCMonth() + 1, 0),
  )
    .getUTCDate();
  return new Date(
    Date.UTC(
      first.getUTCFullYear(),
      first.getUTCMonth(),
      Math.min(day, lastDay),
    ),
  );
}

function isoWeekday(value: Date): number {
  const day = value.getUTCDay();
  return day === 0 ? 7 : day;
}

function minDate(left: Date, right: Date): Date {
  return left <= right ? left : right;
}

function maxDate(left: Date, right: Date): Date {
  return left >= right ? left : right;
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

async function insertAudit(
  sql: any,
  actorUserId: string,
  action: string,
  entityType: string,
  entityId: string,
  metadata: Record<string, unknown>,
): Promise<void> {
  const metadataJson = JSON.stringify(metadata);
  await sql`
    insert into lifemate.audit_logs
      (id, actor_user_id, action, entity_type, entity_id, metadata_json,
       occurred_at_utc)
    values
      (${crypto.randomUUID()}, ${actorUserId}, ${action}, ${entityType},
       ${entityId}, ${metadataJson}, now())
  `;
}
