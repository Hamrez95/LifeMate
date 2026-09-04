import { getLifeMateSql } from "./database_client.ts";
import {
  normalizeRecurrenceRule,
  normalizeRecurrenceStartLocalTime,
  type RecurrenceRule,
} from "./recurrence_schedule.ts";
import {
  ApiError,
  limitedOptional,
  normalizeSchedules,
  requiredDate,
  requiredText,
  requiredTimeZone,
  requiredUuid,
} from "./validation.ts";

type Row = Record<string, any>;

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

function mapMedication(row: Row): Record<string, unknown> {
  return {
    id: row.id,
    name: row.name,
    strengthText: row.strength_text,
    form: row.form,
    notes: row.notes,
    version: row.version,
    createdAtUtc: iso(row.created_at_utc),
    updatedAtUtc: iso(row.updated_at_utc),
  };
}

function recurrenceFromRow(row: Row): RecurrenceRule | null {
  if (row.recurrence_rule == null) return null;
  if (typeof row.recurrence_rule === "string") {
    try {
      return JSON.parse(row.recurrence_rule) as RecurrenceRule;
    } catch {
      return null;
    }
  }
  return row.recurrence_rule as RecurrenceRule;
}

function mapTreatmentPlan(
  row: Row,
  medication: Row,
  schedules: Row[],
  callerAppUserId: string,
): Record<string, unknown> {
  const recurrence = recurrenceFromRow(row);
  return {
    id: row.id,
    // Preserve the public compatibility contract without authorizing from or
    // depending on the stored legacy patient_user_id column.
    patientUserId: callerAppUserId,
    medication: mapMedication(medication),
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
    recurrence,
    recurrenceStartLocalTime:
      recurrence == null || row.recurrence_start_local_time == null
        ? null
        : timeString(row.recurrence_start_local_time),
    version: row.version,
    // The internal recurrence anchor is not exposed as a user-editable weekly
    // schedule. Legacy explicit schedules remain unchanged.
    schedules: schedules
      .filter((schedule) =>
        String(schedule.day_of_week).toLowerCase() !== "recurrence"
      )
      .map((schedule) => ({
        id: schedule.id,
        dayOfWeek: String(schedule.day_of_week).toLowerCase(),
        localTime: timeString(schedule.local_time),
      })),
    createdAtUtc: iso(row.created_at_utc),
    updatedAtUtc: iso(row.updated_at_utc),
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

async function insertAudit(
  connection: any,
  actorAppUserId: string,
  action: string,
  resourceType: string,
  resourceId: string,
): Promise<void> {
  await connection`
    insert into lifemate.audit_logs
      (id, actor_user_id, action, resource_type, resource_id,
       metadata_json, created_at_utc)
    values
      (${crypto.randomUUID()}, ${actorAppUserId}::uuid, ${action},
       ${resourceType}, ${resourceId}::uuid, null, now())
  `;
}

/** Treatment Plan ownership is authoritative on canonical Person. */
export function createPersonTreatmentPlanStore(databaseUrl: string) {
  const sql = getLifeMateSql(databaseUrl);

  async function createTreatmentPlan(
    appUserId: string,
    body: Record<string, unknown>,
  ): Promise<Record<string, unknown>> {
    const medicationId = requiredUuid(body.medicationId, "medicationId");
    const doseText = requiredText(body.doseText, "doseText", 80);
    const instructions = limitedOptional(
      body.instructions,
      "instructions",
      500,
    );
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
    const timeZone = requiredTimeZone(body.timeZone);
    const recurrence = normalizeRecurrenceRule(body.recurrence);
    const recurrenceStartLocalTime = recurrence == null
      ? null
      : normalizeRecurrenceStartLocalTime(body.recurrenceStartLocalTime);
    const schedules = recurrence == null
      ? normalizeSchedules(body.schedules)
      : [];
    if (
      recurrence?.endAt != null && recurrence.endAt.slice(0, 10) < startDate
    ) {
      throw new ApiError(
        400,
        "invalid_recurrence_end",
        "Recurrence end cannot precede the treatment start.",
      );
    }
    const patientReminderMinutesBefore = reminderMinutes(
      body.patientReminderMinutesBefore,
      "patientReminderMinutesBefore",
      30,
    );
    const caregiverReminderMinutesBefore = reminderMinutes(
      body.caregiverReminderMinutesBefore,
      "caregiverReminderMinutesBefore",
      60,
    );
    const now = new Date();

    return await sql.begin(async (tx: any) => {
      const personId = await requireSelfPerson(tx, appUserId);
      const medicationRows = await tx`
        select *
        from lifemate.medications
        where id = ${medicationId}::uuid
          and owner_person_id = ${personId}::uuid
        limit 1
      `;
      if (!medicationRows[0]) {
        throw new ApiError(
          400,
          "invalid_medication",
          "Medication does not belong to the user.",
        );
      }

      const planId = crypto.randomUUID();
      const recurrenceJson = recurrence == null
        ? null
        : JSON.stringify(recurrence);
      const planRows = await tx`
        insert into lifemate.treatment_plans
          (id, patient_person_id, medication_id, dose_text,
           instructions, start_date, end_date, time_zone,
           patient_reminder_minutes_before,
           caregiver_reminder_minutes_before,
           recurrence_rule, recurrence_start_local_time,
           status, version, created_at_utc, updated_at_utc)
        values
          (${planId}::uuid, ${personId}::uuid,
           ${medicationId}::uuid, ${doseText}, ${instructions}, ${startDate},
           ${endDate}, ${timeZone}, ${patientReminderMinutesBefore},
           ${caregiverReminderMinutesBefore},
           ${recurrenceJson}::jsonb, ${recurrenceStartLocalTime}::time,
           'Active', 1, ${now}, ${now})
        returning *
      `;

      const createdSchedules: Row[] = [];
      if (recurrence != null) {
        const rows = await tx`
          insert into lifemate.treatment_schedules
            (id, treatment_plan_id, day_of_week, local_time, created_at_utc)
          values
            (${crypto.randomUUID()}::uuid, ${planId}::uuid,
             'recurrence', ${recurrenceStartLocalTime}::time, ${now})
          returning *
        `;
        createdSchedules.push(rows[0]);
      } else {
        for (const schedule of schedules) {
          const rows = await tx`
            insert into lifemate.treatment_schedules
              (id, treatment_plan_id, day_of_week, local_time, created_at_utc)
            values
              (${crypto.randomUUID()}::uuid, ${planId}::uuid,
               ${schedule.dayOfWeek}, ${schedule.localTime}, ${now})
            returning *
          `;
          createdSchedules.push(rows[0]);
        }
      }

      await insertAudit(
        tx,
        appUserId,
        "treatment_plan.created",
        "treatment_plan",
        planId,
      );
      return mapTreatmentPlan(
        planRows[0],
        medicationRows[0],
        createdSchedules,
        appUserId,
      );
    });
  }

  async function listTreatmentPlans(
    appUserId: string,
  ): Promise<Record<string, unknown>[]> {
    const personId = await requireSelfPerson(sql, appUserId);
    const plans = await sql`
      select p.*, m.name, m.strength_text, m.form, m.notes,
             m.version as medication_version,
             m.created_at_utc as medication_created_at_utc,
             m.updated_at_utc as medication_updated_at_utc
      from lifemate.treatment_plans p
      join lifemate.medications m
        on m.id = p.medication_id
       and m.owner_person_id = p.patient_person_id
      where p.patient_person_id = ${personId}::uuid
        and p.status <> 'Archived'
      order by p.updated_at_utc desc, p.id
      limit 100
    `;
    if (plans.length === 0) return [];

    const planIds = plans.map((row: Row) => row.id);
    const schedules = await sql`
      select *
      from lifemate.treatment_schedules
      where treatment_plan_id in ${sql(planIds)}
      order by day_of_week, local_time
    `;
    return plans.map((row: Row) =>
      mapTreatmentPlan(
        row,
        {
          id: row.medication_id,
          name: row.name,
          strength_text: row.strength_text,
          form: row.form,
          notes: row.notes,
          version: row.medication_version,
          created_at_utc: row.medication_created_at_utc,
          updated_at_utc: row.medication_updated_at_utc,
        },
        schedules.filter((schedule: Row) =>
          schedule.treatment_plan_id === row.id
        ),
        appUserId,
      )
    );
  }

  return { createTreatmentPlan, listTreatmentPlans };
}
