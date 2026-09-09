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
} from "./validation.ts";

type Row = Record<string, any>;

export type TreatmentCreateTestHooks = {
  afterMedicationPersisted?: () => void | Promise<void>;
};

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

function mapTreatmentPlan(
  row: Row,
  medication: Row,
  schedules: Row[],
  callerAppUserId: string,
): Record<string, unknown> {
  const recurrence = recurrenceFromRow(row);
  return {
    id: row.id,
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

/**
 * Creates the medication (or reuses its canonical row) and treatment plan in a
 * single database transaction. The HTTP idempotency coordinator wraps this
 * whole operation, so a retry cannot leave an orphan medication behind.
 */
export function createPersonTreatmentCreateStore(
  databaseUrl: string,
  testHooks: TreatmentCreateTestHooks = {},
) {
  const sql = getLifeMateSql(databaseUrl);

  async function createTreatment(
    appUserId: string,
    body: Record<string, unknown>,
  ): Promise<Record<string, unknown>> {
    const rawMedication = body.medication;
    if (
      rawMedication == null || typeof rawMedication !== "object" ||
      Array.isArray(rawMedication)
    ) {
      throw new ApiError(
        400,
        "invalid_medication",
        "medication must be an object.",
      );
    }
    const medication = rawMedication as Record<string, unknown>;
    const medicationName = requiredText(medication.name, "name", 120);
    const medicationStrength = limitedOptional(
      medication.strengthText,
      "strengthText",
      80,
    );
    const medicationForm = limitedOptional(medication.form, "form", 50);
    const medicationNotes = limitedOptional(medication.notes, "notes", 500);

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

      // Serialize medication identity/quota decisions per Person. This closes
      // the race where two concurrent logical treatment creates could both see
      // no canonical medication and insert duplicates before either committed.
      await tx`
        select pg_advisory_xact_lock(hashtextextended(${personId}::text, 0))
      `;

      const existingMedicationRows = await tx`
        select *
        from lifemate.medications
        where owner_person_id=${personId}::uuid
          and lower(btrim(name))=lower(btrim(${medicationName}::text))
          and lower(coalesce(btrim(strength_text),''))=
              lower(coalesce(btrim(${medicationStrength}::text),''))
          and lower(coalesce(btrim(form),''))=
              lower(coalesce(btrim(${medicationForm}::text),''))
        order by created_at_utc,id
        limit 1
      `;

      let medicationRow: Row;
      if (existingMedicationRows[0]) {
        medicationRow = existingMedicationRows[0] as Row;
      } else {
        const countRows = await tx`
          select count(*)::integer as count
          from lifemate.medications
          where owner_person_id=${personId}::uuid
        `;
        try {
          await tx`
            select commerce.assert_free_quota(
              ${appUserId}::uuid,
              'free.medications.max',
              ${Number(countRows[0]?.count ?? 0)}::integer
            )
          `;
        } catch (error) {
          if (
            String((error as Record<string, unknown>)?.message ?? "").includes(
              "premium_required_quota_reached",
            )
          ) {
            throw new ApiError(
              403,
              "premium_required_quota_reached",
              "Premium is required to add another active medication.",
            );
          }
          throw error;
        }

        const medicationId = crypto.randomUUID();
        const rows = await tx`
          insert into lifemate.medications
            (id,owner_person_id,name,strength_text,form,notes,version,
             created_at_utc,updated_at_utc)
          values
            (${medicationId}::uuid,${personId}::uuid,${medicationName},
             ${medicationStrength},${medicationForm},${medicationNotes},1,
             ${now},${now})
          returning *
        `;
        medicationRow = rows[0] as Row;
        await insertAudit(
          tx,
          appUserId,
          "medication.created",
          "medication",
          medicationId,
        );
        await testHooks.afterMedicationPersisted?.();
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
           ${String(medicationRow.id)}::uuid, ${doseText}, ${instructions},
           ${startDate}, ${endDate}, ${timeZone},
           ${patientReminderMinutesBefore},
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
        createdSchedules.push(rows[0] as Row);
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
          createdSchedules.push(rows[0] as Row);
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
        planRows[0] as Row,
        medicationRow,
        createdSchedules,
        appUserId,
      );
    });
  }

  return { createTreatment };
}
