import postgres from "postgres";
import {
  ApiError,
  limitedOptional,
  requiredDate,
  requiredText,
  requiredTimeZone,
  requiredUuid,
  validateRange,
} from "./validation.ts";

type Row = Record<string, any>;
type Sql = ReturnType<typeof postgres>;

type CareEventInput = {
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
  patientReminderMinutesBefore: number;
  caregiverReminderMinutesBefore: number;
};

export function createCareEventStore(databaseUrl: string) {
  const sql = postgres(databaseUrl, {
    max: 2,
    idle_timeout: 20,
    connect_timeout: 10,
    prepare: false,
  });

  async function createCareEvent(
    patientUserId: string,
    body: Record<string, unknown>,
  ): Promise<Record<string, unknown>> {
    const input = normalizeCareEvent(body);
    const now = new Date();
    const id = crypto.randomUUID();

    return await sql.begin(async (tx: any) => {
      const inserted = await tx`
        insert into lifemate.care_events (
          id,
          patient_user_id,
          created_by_user_id,
          client_request_id,
          event_type,
          title,
          provider_name,
          specialty,
          medication_name,
          dose_text,
          administration_route,
          reason,
          instructions,
          center_name,
          address_line,
          phone_number,
          scheduled_local_date,
          scheduled_local_time,
          time_zone,
          patient_reminder_minutes_before,
          caregiver_reminder_minutes_before,
          status,
          completed_at_utc,
          version,
          created_at_utc,
          updated_at_utc
        ) values (
          ${id},
          ${patientUserId},
          ${patientUserId},
          ${input.clientRequestId},
          ${input.eventType},
          ${input.title},
          ${input.providerName},
          ${input.specialty},
          ${input.medicationName},
          ${input.doseText},
          ${input.administrationRoute},
          ${input.reason},
          ${input.instructions},
          ${input.centerName},
          ${input.addressLine},
          ${input.phoneNumber},
          ${input.scheduledLocalDate},
          ${input.scheduledLocalTime},
          ${input.timeZone},
          ${input.patientReminderMinutesBefore},
          ${input.caregiverReminderMinutesBefore},
          'Scheduled',
          null,
          1,
          ${now},
          ${now}
        )
        on conflict (patient_user_id, client_request_id) do nothing
        returning *
      `;

      if (inserted[0]) {
        await insertAudit(
          tx,
          patientUserId,
          "care_event.created",
          inserted[0].id,
          input.eventType,
        );
        return mapCareEvent(inserted[0]);
      }

      const existingRows = await tx`
        select *
        from lifemate.care_events
        where patient_user_id = ${patientUserId}
          and client_request_id = ${input.clientRequestId}
        limit 1
      `;
      const existing = existingRows[0];
      if (!existing || !matchesIdempotentRequest(existing, input)) {
        throw new ApiError(
          409,
          "idempotency_key_reused",
          "clientRequestId was already used for another care event.",
        );
      }
      return mapCareEvent(existing);
    });
  }

  async function listCareEvents(
    patientUserId: string,
    fromValue: unknown,
    toValue: unknown,
  ): Promise<Record<string, unknown>[]> {
    const { fromDate, toDate } = normalizeRange(fromValue, toValue);
    return await selectCareEvents(sql, patientUserId, fromDate, toDate);
  }

  async function listCareRecipientEvents(
    caregiverUserId: string,
    patientUserIdValue: unknown,
    fromValue: unknown,
    toValue: unknown,
  ): Promise<Record<string, unknown>[]> {
    const patientUserId = requiredUuid(patientUserIdValue, "patientUserId");
    const { fromDate, toDate } = normalizeRange(fromValue, toValue);
    const relationships = await sql`
      select id
      from lifemate.care_relationships
      where patient_user_id = ${patientUserId}
        and caregiver_user_id = ${caregiverUserId}
        and status = 'Active'
      limit 1
    `;
    if (!relationships[0]) {
      throw new ApiError(
        403,
        "care_access_denied",
        "Care access is not active.",
      );
    }
    return await selectCareEvents(sql, patientUserId, fromDate, toDate);
  }

  return {
    createCareEvent,
    listCareEvents,
    listCareRecipientEvents,
  };
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
  const medicationName = limitedOptional(
    body.medicationName,
    "medicationName",
    160,
  );
  if (eventType === "Injection" && !medicationName) {
    throw new ApiError(
      400,
      "invalid_medicationName",
      "medicationName is required for an injection.",
    );
  }

  return {
    clientRequestId: requiredUuid(body.clientRequestId, "clientRequestId"),
    eventType,
    title: requiredText(body.title, "title", 160),
    providerName: limitedOptional(body.providerName, "providerName", 160),
    specialty: limitedOptional(body.specialty, "specialty", 120),
    medicationName,
    doseText: limitedOptional(body.doseText, "doseText", 80),
    administrationRoute: limitedOptional(
      body.administrationRoute,
      "administrationRoute",
      80,
    ),
    reason: limitedOptional(body.reason, "reason", 500),
    instructions: limitedOptional(body.instructions, "instructions", 1000),
    centerName: limitedOptional(body.centerName, "centerName", 160),
    addressLine: limitedOptional(body.addressLine, "addressLine", 500),
    phoneNumber: limitedOptional(body.phoneNumber, "phoneNumber", 50),
    scheduledLocalDate,
    scheduledLocalTime,
    timeZone: requiredTimeZone(body.timeZone),
    patientReminderMinutesBefore: reminderMinutes(
      body.patientReminderMinutesBefore,
      "patientReminderMinutesBefore",
      30,
    ),
    caregiverReminderMinutesBefore: reminderMinutes(
      body.caregiverReminderMinutesBefore,
      "caregiverReminderMinutesBefore",
      60,
    ),
  };
}

function reminderMinutes(
  value: unknown,
  field: string,
  fallback: number,
): number {
  if (value == null || value === "") return fallback;
  const number = Number(value);
  if (!Number.isInteger(number) || number < 0 || number > 10080) {
    throw new ApiError(
      400,
      `invalid_${field}`,
      `${field} must be an integer between 0 and 10080.`,
    );
  }
  return number;
}

function normalizeEventType(value: unknown): "Appointment" | "Injection" {
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

function requiredLocalTime(value: unknown, field: string): string {
  const match = /^(\d{2}):(\d{2})(?::\d{2})?$/.exec(
    String(value ?? "").trim(),
  );
  if (!match) {
    throw new ApiError(400, `invalid_${field}`, `${field} must be HH:mm.`);
  }
  const hour = Number(match[1]);
  const minute = Number(match[2]);
  if (hour > 23 || minute > 59) {
    throw new ApiError(400, `invalid_${field}`, `${field} is invalid.`);
  }
  return `${match[1]}:${match[2]}`;
}

function normalizeRange(fromValue: unknown, toValue: unknown) {
  const fromDate = requiredDate(fromValue, "fromDate");
  const toDate = requiredDate(toValue, "toDate");
  validateRange(fromDate, toDate);
  return { fromDate, toDate };
}

async function selectCareEvents(
  sql: Sql,
  patientUserId: string,
  fromDate: string,
  toDate: string,
): Promise<Record<string, unknown>[]> {
  const rows = await sql`
    select *,
      case
        when status = 'Scheduled'
          and ((scheduled_local_date + scheduled_local_time) at time zone time_zone) < now()
        then 'Missed'
        else status
      end as effective_status,
      ((scheduled_local_date + scheduled_local_time) at time zone time_zone)
        as scheduled_at_utc
    from lifemate.care_events
    where patient_user_id = ${patientUserId}
      and scheduled_local_date between ${fromDate}::date and ${toDate}::date
      and status <> 'Cancelled'
    order by scheduled_local_date, scheduled_local_time, id
    limit 200
  `;
  return rows.map(mapCareEvent);
}

async function insertAudit(
  connection: any,
  actorUserId: string,
  action: string,
  resourceId: string,
  eventType: string,
): Promise<void> {
  await connection`
    insert into lifemate.audit_logs (
      id,
      actor_user_id,
      action,
      resource_type,
      resource_id,
      metadata_json,
      created_at_utc
    ) values (
      ${crypto.randomUUID()},
      ${actorUserId},
      ${action},
      'care_event',
      ${resourceId},
      ${JSON.stringify({ eventType })}::jsonb,
      now()
    )
  `;
}

function matchesIdempotentRequest(row: Row, input: CareEventInput): boolean {
  return row.event_type === input.eventType &&
    row.title === input.title &&
    dateString(row.scheduled_local_date) === input.scheduledLocalDate &&
    timeString(row.scheduled_local_time) === input.scheduledLocalTime &&
    row.time_zone === input.timeZone &&
    Number(row.patient_reminder_minutes_before ?? 30) ===
      input.patientReminderMinutesBefore &&
    Number(row.caregiver_reminder_minutes_before ?? 60) ===
      input.caregiverReminderMinutesBefore;
}

function mapCareEvent(row: Row): Record<string, unknown> {
  return {
    id: row.id,
    patientUserId: row.patient_user_id,
    createdByUserId: row.created_by_user_id,
    clientRequestId: row.client_request_id,
    eventType: String(row.event_type).toLowerCase(),
    title: row.title,
    providerName: row.provider_name,
    specialty: row.specialty,
    medicationName: row.medication_name,
    doseText: row.dose_text,
    administrationRoute: row.administration_route,
    reason: row.reason,
    instructions: row.instructions,
    centerName: row.center_name,
    addressLine: row.address_line,
    phoneNumber: row.phone_number,
    scheduledLocalDate: dateString(row.scheduled_local_date),
    scheduledLocalTime: timeString(row.scheduled_local_time),
    timeZone: row.time_zone,
    scheduledAtUtc: row.scheduled_at_utc == null
      ? null
      : iso(row.scheduled_at_utc),
    status: String(row.effective_status ?? row.status).toLowerCase(),
    patientReminderMinutesBefore: Number(
      row.patient_reminder_minutes_before ?? 30,
    ),
    caregiverReminderMinutesBefore: Number(
      row.caregiver_reminder_minutes_before ?? 60,
    ),
    version: row.version,
    completedAtUtc: row.completed_at_utc == null
      ? null
      : iso(row.completed_at_utc),
    createdAtUtc: iso(row.created_at_utc),
    updatedAtUtc: iso(row.updated_at_utc),
  };
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

function timeString(value: unknown): string {
  return String(value).slice(0, 5);
}
