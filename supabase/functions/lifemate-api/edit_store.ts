import { getLifeMateSql } from "./database_client.ts";
import {
  ApiError,
  limitedOptional,
  normalizeSchedules,
  requiredDate,
  requiredPositiveInt,
  requiredText,
  requiredTimeZone,
  requiredUuid,
} from "./validation.ts";

type Row = Record<string, any>;

type TreatmentInput = {
  version: number;
  medicationVersion: number;
  medicationName: string;
  strengthText: string | null;
  form: string | null;
  doseText: string;
  instructions: string | null;
  startDate: string;
  endDate: string | null;
  timeZone: string;
  schedules: Array<{ dayOfWeek: string; localTime: string }>;
  patientReminderMinutesBefore: number;
  caregiverReminderMinutesBefore: number;
  status: "Active" | "Stopped";
};

type CareEventInput = {
  version: number;
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
  status: "Scheduled" | "Completed" | "Cancelled";
};

async function requireSelfPerson(
  connection: any,
  appUserId: string,
): Promise<string> {
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

/**
 * Healthcare edit ownership is authoritative on canonical Person.
 *
 * AppUser remains the public compatibility/actor context only. Ownership
 * predicates never depend on legacy *_user_id columns, which may be NULL for
 * newly created records after the staged identity-link retirement.
 */
export function createPersonEditStore(databaseUrl: string) {
  const sql = getLifeMateSql(databaseUrl);

  async function updateTreatmentPlan(
    appUserId: string,
    treatmentPlanIdValue: unknown,
    body: Record<string, unknown>,
  ): Promise<Record<string, unknown>> {
    const treatmentPlanId = requiredUuid(
      treatmentPlanIdValue,
      "treatmentPlanId",
    );
    const input = normalizeTreatment(body);

    return await sql.begin(async (tx: any) => {
      const personId = await requireSelfPerson(tx, appUserId);
      const existingRows = await tx`
        select p.*, m.name, m.strength_text, m.form,
               m.version as medication_version
        from lifemate.treatment_plans p
        join lifemate.medications m
          on m.id = p.medication_id
         and m.owner_person_id = p.patient_person_id
        where p.id = ${treatmentPlanId}::uuid
          and p.patient_person_id = ${personId}::uuid
        for update of p, m
      `;
      const existing = existingRows[0];
      if (!existing) {
        throw new ApiError(
          404,
          "treatment_plan_not_found",
          "Treatment plan was not found.",
        );
      }
      if (Number(existing.version) !== input.version) {
        throw new ApiError(
          409,
          "stale_treatment_plan",
          "Treatment plan has changed. Refresh and try again.",
        );
      }
      if (Number(existing.medication_version) !== input.medicationVersion) {
        throw new ApiError(
          409,
          "stale_medication",
          "Medication has changed. Refresh and try again.",
        );
      }

      const medicationRows = await tx`
        update lifemate.medications
        set name = ${input.medicationName},
            strength_text = ${input.strengthText},
            form = ${input.form},
            version = version + 1,
            updated_at_utc = now()
        where id = ${existing.medication_id}::uuid
          and owner_person_id = ${personId}::uuid
        returning *
      `;
      if (!medicationRows[0]) {
        throw new ApiError(
          404,
          "treatment_plan_not_found",
          "Treatment plan was not found.",
        );
      }

      const planRows = await tx`
        update lifemate.treatment_plans
        set dose_text = ${input.doseText},
            instructions = ${input.instructions},
            start_date = ${input.startDate},
            end_date = ${input.endDate},
            time_zone = ${input.timeZone},
            patient_reminder_minutes_before = ${input.patientReminderMinutesBefore},
            caregiver_reminder_minutes_before = ${input.caregiverReminderMinutesBefore},
            status = ${input.status},
            version = version + 1,
            updated_at_utc = now()
        where id = ${treatmentPlanId}::uuid
          and patient_person_id = ${personId}::uuid
        returning *
      `;
      if (!planRows[0]) {
        throw new ApiError(
          404,
          "treatment_plan_not_found",
          "Treatment plan was not found.",
        );
      }

      await tx`
        delete from lifemate.dose_occurrences
        where treatment_plan_id = ${treatmentPlanId}::uuid
          and patient_person_id = ${personId}::uuid
          and status in ('Scheduled', 'Missed')
          and scheduled_at_utc >= now()
      `;
      await tx`
        delete from lifemate.treatment_schedules
        where treatment_plan_id = ${treatmentPlanId}::uuid
      `;

      const schedules: Row[] = [];
      for (const schedule of input.schedules) {
        const rows = await tx`
          insert into lifemate.treatment_schedules
            (id, treatment_plan_id, day_of_week, local_time, created_at_utc)
          values
            (${crypto.randomUUID()}::uuid, ${treatmentPlanId}::uuid,
             ${schedule.dayOfWeek}, ${schedule.localTime}, now())
          returning *
        `;
        schedules.push(rows[0]);
      }

      await insertAudit(
        tx,
        appUserId,
        "treatment_plan.updated",
        "treatment_plan",
        treatmentPlanId,
      );
      return mapTreatmentPlan(
        planRows[0],
        medicationRows[0],
        schedules,
        appUserId,
      );
    });
  }

  async function getCareEvent(
    appUserId: string,
    careEventIdValue: unknown,
  ): Promise<Record<string, unknown>> {
    const careEventId = requiredUuid(careEventIdValue, "careEventId");
    const personId = await requireSelfPerson(sql, appUserId);
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
      where id = ${careEventId}::uuid
        and patient_person_id = ${personId}::uuid
      limit 1
    `;
    if (!rows[0]) {
      throw new ApiError(
        404,
        "care_event_not_found",
        "Care event was not found.",
      );
    }
    return mapCareEvent(rows[0], appUserId);
  }

  async function updateCareEvent(
    appUserId: string,
    careEventIdValue: unknown,
    body: Record<string, unknown>,
  ): Promise<Record<string, unknown>> {
    const careEventId = requiredUuid(careEventIdValue, "careEventId");
    const input = normalizeCareEvent(body);

    return await sql.begin(async (tx: any) => {
      const personId = await requireSelfPerson(tx, appUserId);
      const existingRows = await tx`
        select *
        from lifemate.care_events
        where id = ${careEventId}::uuid
          and patient_person_id = ${personId}::uuid
        for update
      `;
      const existing = existingRows[0];
      if (!existing) {
        throw new ApiError(
          404,
          "care_event_not_found",
          "Care event was not found.",
        );
      }
      if (Number(existing.version) !== input.version) {
        throw new ApiError(
          409,
          "stale_care_event",
          "Care event has changed. Refresh and try again.",
        );
      }

      const rows = await tx`
        update lifemate.care_events
        set event_type = ${input.eventType},
            title = ${input.title},
            provider_name = ${input.providerName},
            specialty = ${input.specialty},
            medication_name = ${input.medicationName},
            dose_text = ${input.doseText},
            administration_route = ${input.administrationRoute},
            reason = ${input.reason},
            instructions = ${input.instructions},
            center_name = ${input.centerName},
            address_line = ${input.addressLine},
            phone_number = ${input.phoneNumber},
            scheduled_local_date = ${input.scheduledLocalDate},
            scheduled_local_time = ${input.scheduledLocalTime},
            time_zone = ${input.timeZone},
            patient_reminder_minutes_before = ${input.patientReminderMinutesBefore},
            caregiver_reminder_minutes_before = ${input.caregiverReminderMinutesBefore},
            status = ${input.status},
            completed_at_utc = case
              when ${input.status} = 'Completed' then coalesce(completed_at_utc, now())
              else null
            end,
            version = version + 1,
            updated_at_utc = now()
        where id = ${careEventId}::uuid
          and patient_person_id = ${personId}::uuid
        returning *,
          case
            when status = 'Scheduled'
              and ((scheduled_local_date + scheduled_local_time) at time zone time_zone) < now()
            then 'Missed'
            else status
          end as effective_status,
          ((scheduled_local_date + scheduled_local_time) at time zone time_zone)
            as scheduled_at_utc
      `;
      if (!rows[0]) {
        throw new ApiError(
          404,
          "care_event_not_found",
          "Care event was not found.",
        );
      }
      await insertAudit(
        tx,
        appUserId,
        "care_event.updated",
        "care_event",
        careEventId,
      );
      return mapCareEvent(rows[0], appUserId);
    });
  }

  return { updateTreatmentPlan, getCareEvent, updateCareEvent };
}

function normalizeTreatment(body: Record<string, unknown>): TreatmentInput {
  const startDate = requiredDate(body.startDate, "startDate");
  const endDate = body.endDate == null
    ? null
    : requiredDate(body.endDate, "endDate");
  if (endDate && endDate < startDate) {
    throw new ApiError(
      400,
      "invalid_treatment_plan",
      "End date cannot precede start date.",
    );
  }
  return {
    version: requiredPositiveInt(body.version, "version"),
    medicationVersion: requiredPositiveInt(
      body.medicationVersion,
      "medicationVersion",
    ),
    medicationName: requiredText(body.medicationName, "medicationName", 120),
    strengthText: limitedOptional(body.strengthText, "strengthText", 80),
    form: limitedOptional(body.form, "form", 50),
    doseText: requiredText(body.doseText, "doseText", 80),
    instructions: limitedOptional(body.instructions, "instructions", 500),
    startDate,
    endDate,
    timeZone: requiredTimeZone(body.timeZone),
    schedules: normalizeSchedules(body.schedules),
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
    status: treatmentStatus(body.status),
  };
}

function normalizeCareEvent(body: Record<string, unknown>): CareEventInput {
  const eventType = careEventType(body.eventType);
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
    version: requiredPositiveInt(body.version, "version"),
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
    scheduledLocalDate: requiredDate(
      body.scheduledLocalDate,
      "scheduledLocalDate",
    ),
    scheduledLocalTime: requiredLocalTime(
      body.scheduledLocalTime,
      "scheduledLocalTime",
    ),
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
    status: careEventStatus(body.status),
  };
}

function treatmentStatus(value: unknown): "Active" | "Stopped" {
  const status = String(value ?? "active").trim().toLowerCase();
  if (status === "active") return "Active";
  if (status === "stopped" || status === "paused") return "Stopped";
  throw new ApiError(
    400,
    "invalid_treatment_status",
    "Treatment status must be active or stopped.",
  );
}

function careEventStatus(
  value: unknown,
): "Scheduled" | "Completed" | "Cancelled" {
  const status = String(value ?? "scheduled").trim().toLowerCase();
  if (status === "scheduled" || status === "missed") return "Scheduled";
  if (status === "completed") return "Completed";
  if (status === "cancelled" || status === "canceled") return "Cancelled";
  throw new ApiError(
    400,
    "invalid_care_event_status",
    "Care event status is invalid.",
  );
}

function careEventType(value: unknown): "Appointment" | "Injection" {
  const type = String(value ?? "").trim().toLowerCase();
  if (type === "appointment" || type === "visit") return "Appointment";
  if (type === "injection") return "Injection";
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
      (${crypto.randomUUID()}, ${actorUserId}::uuid, ${action}, ${resourceType},
       ${resourceId}::uuid, null, now())
  `;
}

function mapTreatmentPlan(
  row: Row,
  medication: Row,
  schedules: Row[],
  callerAppUserId: string,
): Record<string, unknown> {
  return {
    id: row.id,
    patientUserId: callerAppUserId,
    medication: {
      id: medication.id,
      name: medication.name,
      strengthText: medication.strength_text,
      form: medication.form,
      notes: medication.notes,
      version: medication.version,
      createdAtUtc: iso(medication.created_at_utc),
      updatedAtUtc: iso(medication.updated_at_utc),
    },
    doseText: row.dose_text,
    instructions: row.instructions,
    startDate: dateString(row.start_date),
    endDate: row.end_date == null ? null : dateString(row.end_date),
    timeZone: row.time_zone,
    status: String(row.status).toLowerCase(),
    patientReminderMinutesBefore: Number(
      row.patient_reminder_minutes_before ?? 30,
    ),
    caregiverReminderMinutesBefore: Number(
      row.caregiver_reminder_minutes_before ?? 60,
    ),
    version: row.version,
    schedules: schedules.map((schedule) => ({
      id: schedule.id,
      dayOfWeek: String(schedule.day_of_week).toLowerCase(),
      localTime: timeString(schedule.local_time),
    })),
    createdAtUtc: iso(row.created_at_utc),
    updatedAtUtc: iso(row.updated_at_utc),
  };
}

function mapCareEvent(
  row: Row,
  callerAppUserId: string,
): Record<string, unknown> {
  return {
    id: row.id,
    patientUserId: callerAppUserId,
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

export { createPersonEditStore as createEditStore };
