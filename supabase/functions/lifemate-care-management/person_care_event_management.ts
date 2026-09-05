import {
  type CareRecurrenceRule,
  normalizeCareRecurrence,
  recurrencePublicValue,
} from "./recurrence_contract.ts";

type Row = Record<string, any>;
type ApiErrorFactory = (status: number, code: string, message: string) => Error;
type CareEventInput = {
  version: number;
  clientRequestId: string;
  eventType: "Appointment" | "Injection";
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
  recurrence: CareRecurrenceRule | null;
  patientReminderMinutesBefore: number;
  caregiverReminderMinutesBefore: number;
};
type StoreDependencies = {
  sql: any;
  normalizeCareEvent: (
    body: Record<string, unknown>,
    editing: boolean,
  ) => unknown;
  apiError: ApiErrorFactory;
};

export function createPersonCareEventManagementStore(
  dependencies: StoreDependencies,
) {
  const { sql, apiError } = dependencies;

  async function listCareEvents(
    patientAppUserId: string,
  ): Promise<Record<string, unknown>[]> {
    const personId = await requireSelfPerson(sql, patientAppUserId, apiError);
    const rows = await sql`
      select * from lifemate.care_events
      where patient_person_id=${personId}::uuid and status <> 'Cancelled'
      order by scheduled_local_date, scheduled_local_time, id limit 200
    `;
    return rows.map((row: Row) => mapCareEvent(row, patientAppUserId));
  }

  async function createCareEvent(
    caregiverAppUserId: string,
    patientAppUserId: string,
    body: Record<string, unknown>,
  ): Promise<Record<string, unknown>> {
    const input = normalizeBody(body, false, apiError);
    return await sql.begin(async (tx: any) => {
      const personId = await requireSelfPerson(tx, patientAppUserId, apiError);
      const existing = await tx`
        select * from lifemate.care_events
        where patient_person_id=${personId}::uuid
          and client_request_id=${input.clientRequestId}::uuid limit 1
      `;
      if (existing[0]) {
        if (!sameInput(existing[0], input)) {
          throw apiError(
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
          (id,patient_person_id,created_by_user_id,client_request_id,event_type,title,
           provider_name,specialty,medication_name,dose_text,administration_route,
           reason,instructions,center_name,address_line,phone_number,
           scheduled_local_date,scheduled_local_time,time_zone,
           recurrence_unit,recurrence_interval,recurrence_weekdays,recurrence_end_date,
           recurrence_rule,patient_reminder_minutes_before,caregiver_reminder_minutes_before,
           status,version,provenance_source,provenance_restricted,created_at_utc,updated_at_utc)
        values (${id}::uuid,${personId}::uuid,${caregiverAppUserId}::uuid,
          ${input.clientRequestId}::uuid,${input.eventType},${input.title},
          ${input.providerName},${input.specialty},${input.medicationName},${input.doseText},
          ${input.administrationRoute},${input.reason},${input.instructions},${input.centerName},
          ${input.addressLine},${input.phoneNumber},${input.scheduledLocalDate}::date,
          ${input.scheduledLocalTime}::time,${input.timeZone},'none',1,array[]::smallint[],null,
          ${recurrenceJson}::jsonb,${input.patientReminderMinutesBefore},
          ${input.caregiverReminderMinutesBefore},'Scheduled',1,'CaregiverInput',false,now(),now())
        returning *
      `;
      await insertAudit(
        tx,
        caregiverAppUserId,
        "caregiver.care_event.created",
        id,
        input.eventType,
      );
      return mapCareEvent(rows[0], patientAppUserId);
    });
  }

  async function updateCareEvent(
    caregiverAppUserId: string,
    patientAppUserId: string,
    eventId: string,
    body: Record<string, unknown>,
  ): Promise<Record<string, unknown>> {
    const input = normalizeBody(body, true, apiError);
    return await sql.begin(async (tx: any) => {
      const personId = await requireSelfPerson(tx, patientAppUserId, apiError);
      const existingRows = await tx`
        select * from lifemate.care_events
        where id=${eventId}::uuid and patient_person_id=${personId}::uuid for update
      `;
      const existing = existingRows[0];
      if (!existing) {
        throw apiError(
          404,
          "care_event_not_found",
          "Care event was not found.",
        );
      }
      if (Number(existing.version) !== input.version) {
        throw apiError(
          409,
          "stale_care_event",
          "Care event has changed. Refresh and try again.",
        );
      }
      if (String(existing.status) === "Cancelled") {
        throw apiError(
          409,
          "care_event_cancelled",
          "Cancelled event cannot be edited.",
        );
      }
      const recurrenceJson = input.recurrence == null
        ? null
        : JSON.stringify(input.recurrence);
      const rows = await tx`
        update lifemate.care_events set
          event_type=${input.eventType},title=${input.title},provider_name=${input.providerName},
          specialty=${input.specialty},medication_name=${input.medicationName},dose_text=${input.doseText},
          administration_route=${input.administrationRoute},reason=${input.reason},instructions=${input.instructions},
          center_name=${input.centerName},address_line=${input.addressLine},phone_number=${input.phoneNumber},
          scheduled_local_date=${input.scheduledLocalDate}::date,
          scheduled_local_time=${input.scheduledLocalTime}::time,time_zone=${input.timeZone},
          recurrence_rule=${recurrenceJson}::jsonb,
          recurrence_unit='none',recurrence_interval=1,recurrence_weekdays=array[]::smallint[],recurrence_end_date=null,
          patient_reminder_minutes_before=${input.patientReminderMinutesBefore},
          caregiver_reminder_minutes_before=${input.caregiverReminderMinutesBefore},
          provenance_source='CaregiverInput',version=version+1,updated_at_utc=now()
        where id=${eventId}::uuid and patient_person_id=${personId}::uuid returning *
      `;
      if (!rows[0]) {
        throw apiError(
          409,
          "identity_person_mapping_conflict",
          "Care Event ownership changed during the update.",
        );
      }
      await insertAudit(
        tx,
        caregiverAppUserId,
        "caregiver.care_event.updated",
        eventId,
        input.eventType,
      );
      return mapCareEvent(rows[0], patientAppUserId);
    });
  }

  async function cancelCareEvent(
    caregiverAppUserId: string,
    patientAppUserId: string,
    eventId: string,
    expectedVersion: number,
  ): Promise<void> {
    await sql.begin(async (tx: any) => {
      const personId = await requireSelfPerson(tx, patientAppUserId, apiError);
      const rows =
        await tx`select * from lifemate.care_events where id=${eventId}::uuid and patient_person_id=${personId}::uuid for update`;
      const event = rows[0];
      if (!event) {
        throw apiError(
          404,
          "care_event_not_found",
          "Care event was not found.",
        );
      }
      if (Number(event.version) !== expectedVersion) {
        throw apiError(
          409,
          "stale_care_event",
          "Care event has changed. Refresh and try again.",
        );
      }
      if (String(event.status) !== "Cancelled") {
        await tx`update lifemate.care_events set status='Cancelled',completed_at_utc=null,provenance_source='CaregiverInput',version=version+1,updated_at_utc=now() where id=${eventId}::uuid and patient_person_id=${personId}::uuid`;
      }
      await insertAudit(
        tx,
        caregiverAppUserId,
        "caregiver.care_event.cancelled",
        eventId,
      );
    });
  }

  return { listCareEvents, createCareEvent, updateCareEvent, cancelCareEvent };
}

function normalizeBody(
  body: Record<string, unknown>,
  editing: boolean,
  error: ApiErrorFactory,
): CareEventInput {
  const eventType = eventTypeValue(body.eventType, error);
  const medicationName = optionalText(body.medicationName, 160, error);
  if (eventType === "Injection" && !medicationName) {
    throw error(
      400,
      "invalid_medicationName",
      "medicationName is required for injection events.",
    );
  }
  const date = requiredDate(
    body.scheduledLocalDate,
    "scheduledLocalDate",
    error,
  );
  const recurrence = normalizeCareRecurrence(body.recurrence, error);
  if (recurrence?.endAt != null && recurrence.endAt.slice(0, 10) < date) {
    throw error(
      400,
      "invalid_recurrence_end",
      "Recurrence end cannot precede its start.",
    );
  }
  return {
    version: editing ? positiveInt(body.version, "version", error) : 1,
    clientRequestId: editing
      ? crypto.randomUUID()
      : uuid(body.clientRequestId, "clientRequestId", error),
    eventType,
    title: text(body.title, "title", 160, error),
    providerName: optionalText(body.providerName, 160, error),
    specialty: optionalText(body.specialty, 120, error),
    medicationName,
    doseText: optionalText(body.doseText, 120, error),
    administrationRoute: routeValue(body.administrationRoute, error),
    reason: optionalText(body.reason, 500, error),
    instructions: optionalText(body.instructions, 1000, error),
    centerName: optionalText(body.centerName, 200, error),
    addressLine: optionalText(body.addressLine, 500, error),
    phoneNumber: optionalText(body.phoneNumber, 40, error),
    scheduledLocalDate: date,
    scheduledLocalTime: localTime(
      body.scheduledLocalTime,
      "scheduledLocalTime",
      error,
    ),
    timeZone: text(body.timeZone, "timeZone", 80, error),
    recurrence,
    patientReminderMinutesBefore: reminder(
      body.patientReminderMinutesBefore,
      30,
      error,
    ),
    caregiverReminderMinutesBefore: reminder(
      body.caregiverReminderMinutesBefore,
      60,
      error,
    ),
  };
}

function mapCareEvent(
  row: Row,
  patientAppUserId: string,
): Record<string, unknown> {
  const recurrence = parseRecurrence(row.recurrence_rule);
  return {
    id: row.id,
    seriesId: row.id,
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
    scheduledLocalDate: dateValue(row.scheduled_local_date),
    scheduledLocalTime: timeValue(row.scheduled_local_time),
    timeZone: row.time_zone,
    recurrence: recurrencePublicValue(recurrence),
    patientReminderMinutesBefore: Number(
      row.patient_reminder_minutes_before ?? 30,
    ),
    caregiverReminderMinutesBefore: Number(
      row.caregiver_reminder_minutes_before ?? 60,
    ),
    status: String(row.status).toLowerCase(),
    version: Number(row.version),
    createdAtUtc: iso(row.created_at_utc),
    updatedAtUtc: iso(row.updated_at_utc),
  };
}

function sameInput(row: Row, input: CareEventInput): boolean {
  const stored = parseRecurrence(row.recurrence_rule);
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
    dateValue(row.scheduled_local_date) === input.scheduledLocalDate &&
    timeValue(row.scheduled_local_time) === input.scheduledLocalTime &&
    String(row.time_zone) === input.timeZone &&
    sameRecurrence(stored, input.recurrence) &&
    Number(row.patient_reminder_minutes_before ?? 30) ===
      input.patientReminderMinutesBefore &&
    Number(row.caregiver_reminder_minutes_before ?? 60) ===
      input.caregiverReminderMinutesBefore;
}
function sameRecurrence(
  a: CareRecurrenceRule | null,
  b: CareRecurrenceRule | null,
): boolean {
  if (a == null || b == null) return a === b;
  return a.version === b.version && a.unit === b.unit &&
    a.interval === b.interval && a.endAt === b.endAt &&
    a.maxOccurrences === b.maxOccurrences &&
    a.weekdays.length === b.weekdays.length &&
    a.weekdays.every((v, i) => v === b.weekdays[i]);
}
function parseRecurrence(value: unknown): CareRecurrenceRule | null {
  if (value == null) return null;
  const r = (typeof value === "string" ? JSON.parse(value) : value) as Record<
    string,
    any
  >;
  if (!r || r.enabled !== true) return null;
  return {
    version: Number(r.version ?? 2),
    enabled: true,
    unit: r.unit,
    interval: Number(r.interval ?? 1),
    weekdays: Array.isArray(r.weekdays) ? r.weekdays.map(Number) : [],
    endAt: r.endAt == null ? null : String(r.endAt),
    maxOccurrences: r.maxOccurrences == null ? null : Number(r.maxOccurrences),
  } as CareRecurrenceRule;
}
async function requireSelfPerson(
  sql: any,
  userId: string,
  error: ApiErrorFactory,
): Promise<string> {
  const rows =
    await sql`select core.self_person_id_for_legacy_app_user(${userId}::uuid)::text as person_id`;
  const id = rows[0]?.person_id;
  if (typeof id !== "string" || !id) {
    throw error(
      409,
      "identity_person_mapping_missing",
      "The patient Person mapping is unavailable.",
    );
  }
  return id;
}
function eventTypeValue(
  v: unknown,
  e: ApiErrorFactory,
): "Appointment" | "Injection" {
  const s = String(v ?? "").trim().toLowerCase();
  if (s === "appointment" || s === "visit" || s === "checkup") {
    return "Appointment";
  }
  if (s === "injection") return "Injection";
  throw e(400, "invalid_eventType", "Unsupported care event type.");
}
function routeValue(v: unknown, e: ApiErrorFactory): string | null {
  const s = String(v ?? "").trim().toLowerCase();
  if (!s) return null;
  const x: Record<string, string> = {
    intramuscular: "Intramuscular",
    subcutaneous: "Subcutaneous",
    intravenous: "Intravenous",
    other: "Other",
  };
  if (!x[s]) {
    throw e(
      400,
      "invalid_administrationRoute",
      "Unsupported administration route.",
    );
  }
  return x[s];
}
function text(v: unknown, f: string, m: number, e: ApiErrorFactory): string {
  const s = String(v ?? "").trim();
  if (!s || s.length > m) throw e(400, `invalid_${f}`, `${f} is invalid.`);
  return s;
}
function optionalText(
  v: unknown,
  m: number,
  e: ApiErrorFactory,
): string | null {
  if (v == null) return null;
  const s = String(v).trim();
  if (!s) return null;
  if (s.length > m) throw e(400, "invalid_text", "Text value is too long.");
  return s;
}
function requiredDate(v: unknown, f: string, e: ApiErrorFactory): string {
  const s = String(v ?? "").trim();
  if (!/^\d{4}-\d{2}-\d{2}$/.test(s)) {
    throw e(400, `invalid_${f}`, `${f} must be YYYY-MM-DD.`);
  }
  const d = new Date(`${s}T00:00:00.000Z`);
  if (Number.isNaN(d.getTime()) || d.toISOString().slice(0, 10) !== s) {
    throw e(400, `invalid_${f}`, `${f} is invalid.`);
  }
  return s;
}
function localTime(v: unknown, f: string, e: ApiErrorFactory): string {
  const m = /^(\d{2}):(\d{2})(?::\d{2})?$/.exec(String(v ?? "").trim());
  if (!m || Number(m[1]) > 23 || Number(m[2]) > 59) {
    throw e(400, `invalid_${f}`, `${f} must be HH:mm.`);
  }
  return `${m[1]}:${m[2]}`;
}
function reminder(v: unknown, d: number, e: ApiErrorFactory): number {
  if (v == null || v === "") return d;
  const n = Number(v);
  if (!Number.isInteger(n) || n < 0 || n > 10080) {
    throw e(
      400,
      "invalid_reminder",
      "Reminder lead time must be between 0 and 10080 minutes.",
    );
  }
  return n;
}
function positiveInt(v: unknown, f: string, e: ApiErrorFactory): number {
  const n = Number(v);
  if (!Number.isInteger(n) || n < 1) {
    throw e(400, `invalid_${f}`, `${f} must be positive.`);
  }
  return n;
}
function uuid(v: unknown, f: string, e: ApiErrorFactory): string {
  const s = String(v ?? "").trim();
  if (
    !/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
      .test(s)
  ) throw e(400, `invalid_${f}`, `${f} must be a UUID.`);
  return s;
}
function nullable(v: unknown): string | null {
  return v == null ? null : String(v);
}
function dateValue(v: unknown): string {
  return v instanceof Date
    ? v.toISOString().slice(0, 10)
    : String(v).slice(0, 10);
}
function timeValue(v: unknown): string {
  return String(v).slice(0, 5);
}
function iso(v: unknown): string {
  return v instanceof Date
    ? v.toISOString()
    : new Date(String(v)).toISOString();
}
async function insertAudit(
  sql: any,
  actor: string,
  action: string,
  eventId: string,
  eventType?: string,
): Promise<void> {
  const metadata = eventType == null ? null : JSON.stringify({ eventType });
  await sql`insert into lifemate.audit_logs (id,actor_user_id,action,resource_type,resource_id,metadata_json,created_at_utc) values (${crypto.randomUUID()}::uuid,${actor}::uuid,${action},'care_event',${eventId}::uuid,${metadata}::jsonb,now())`;
}
