import {
  type CareRecurrenceRule,
  normalizeCareRecurrence,
  normalizeCareRecurrenceStartTime,
  recurrencePublicValue,
} from "./recurrence_contract.ts";

type Row = Record<string, any>;
type ApiErrorFactory = (status: number, code: string, message: string) => Error;
type Schedule = { dayOfWeek: string; localTime: string };
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
  schedules: Schedule[];
  recurrence: CareRecurrenceRule | null;
  recurrenceStartLocalTime: string | null;
  patientReminderMinutesBefore: number;
  caregiverReminderMinutesBefore: number;
  status: "Active" | "Stopped";
};

type StoreDependencies = {
  sql: any;
  // Retained for source compatibility with index.ts. This store normalizes the
  // raw payload itself so recurrence fields cannot be discarded by legacy code.
  normalizeTreatment: (
    body: Record<string, unknown>,
    editing: boolean,
  ) => unknown;
  apiError: ApiErrorFactory;
};

export function createPersonTreatmentManagementStore(
  dependencies: StoreDependencies,
) {
  const { sql, apiError } = dependencies;

  async function listTreatmentPlans(
    patientAppUserId: string,
  ): Promise<Record<string, unknown>[]> {
    const patientPersonId = await requireSelfPerson(
      sql,
      patientAppUserId,
      apiError,
    );
    const plans = await sql`
      select p.*, m.name as medication_name, m.strength_text, m.form,
             m.notes as medication_notes, m.version as medication_version
      from lifemate.treatment_plans p
      join lifemate.medications m
        on m.id = p.medication_id and m.owner_person_id = p.patient_person_id
      where p.patient_person_id = ${patientPersonId}::uuid
        and p.status <> 'Archived'
      order by p.updated_at_utc desc, p.id
      limit 100
    `;
    if (plans.length === 0) return [];
    const ids = plans.map((row: Row) => row.id);
    const schedules = await sql`
      select * from lifemate.treatment_schedules
      where treatment_plan_id in ${sql(ids)}
      order by day_of_week, local_time
    `;
    return plans.map((plan: Row) =>
      mapTreatmentPlan(
        plan,
        schedules.filter((schedule: Row) =>
          schedule.treatment_plan_id === plan.id
        ),
        patientAppUserId,
      )
    );
  }

  async function createTreatmentPlan(
    caregiverAppUserId: string,
    patientAppUserId: string,
    body: Record<string, unknown>,
  ): Promise<Record<string, unknown>> {
    const input = normalizeTreatmentBody(body, false, apiError);
    return await sql.begin(async (tx: any) => {
      const patientPersonId = await requireSelfPerson(
        tx,
        patientAppUserId,
        apiError,
      );
      const medicationId = crypto.randomUUID();
      const planId = crypto.randomUUID();
      const recurrenceJson = input.recurrence == null
        ? null
        : JSON.stringify(input.recurrence);
      const medicationRows = await tx`
        insert into lifemate.medications
          (id, owner_person_id, name, strength_text, form, notes, version,
           provenance_source, provenance_restricted, created_at_utc, updated_at_utc)
        values (${medicationId}::uuid, ${patientPersonId}::uuid,
          ${input.medicationName}, ${input.strengthText}, ${input.form}, null, 1,
          'CaregiverInput', false, now(), now())
        returning *
      `;
      const planRows = await tx`
        insert into lifemate.treatment_plans
          (id, patient_person_id, medication_id, dose_text, instructions,
           start_date, end_date, time_zone, recurrence_rule,
           recurrence_start_local_time, patient_reminder_minutes_before,
           caregiver_reminder_minutes_before, status, version,
           provenance_source, provenance_restricted, created_at_utc, updated_at_utc)
        values (${planId}::uuid, ${patientPersonId}::uuid, ${medicationId}::uuid,
          ${input.doseText}, ${input.instructions}, ${input.startDate}::date,
          ${input.endDate}::date, ${input.timeZone}, ${recurrenceJson}::jsonb,
          ${input.recurrenceStartLocalTime}::time,
          ${input.patientReminderMinutesBefore}, ${input.caregiverReminderMinutesBefore},
          'Active', 1, 'CaregiverInput', false, now(), now())
        returning *
      `;
      const schedules = await replaceSchedules(tx, planId, input);
      await insertAudit(
        tx,
        caregiverAppUserId,
        "caregiver.treatment_plan.created",
        planId,
      );
      return mapTreatmentPlan(
        withMedication(planRows[0], medicationRows[0]),
        schedules,
        patientAppUserId,
      );
    });
  }

  async function updateTreatmentPlan(
    caregiverAppUserId: string,
    patientAppUserId: string,
    treatmentPlanId: string,
    body: Record<string, unknown>,
  ): Promise<Record<string, unknown>> {
    const input = normalizeTreatmentBody(body, true, apiError);
    return await sql.begin(async (tx: any) => {
      const patientPersonId = await requireSelfPerson(
        tx,
        patientAppUserId,
        apiError,
      );
      const existingRows = await tx`
        select p.*, m.version as medication_version
        from lifemate.treatment_plans p
        join lifemate.medications m on m.id=p.medication_id
          and m.owner_person_id=p.patient_person_id
        where p.id=${treatmentPlanId}::uuid
          and p.patient_person_id=${patientPersonId}::uuid
        for update of p, m
      `;
      const existing = existingRows[0];
      if (!existing) {
        throw apiError(
          404,
          "treatment_plan_not_found",
          "Treatment plan was not found.",
        );
      }
      if (Number(existing.version) !== input.version) {
        throw apiError(
          409,
          "stale_treatment_plan",
          "Treatment plan has changed. Refresh and try again.",
        );
      }
      if (Number(existing.medication_version) !== input.medicationVersion) {
        throw apiError(
          409,
          "stale_medication",
          "Medication has changed. Refresh and try again.",
        );
      }

      const medicationRows = await tx`
        update lifemate.medications
        set name=${input.medicationName}, strength_text=${input.strengthText},
            form=${input.form}, provenance_source='CaregiverInput',
            version=version+1, updated_at_utc=now()
        where id=${existing.medication_id}::uuid
          and owner_person_id=${patientPersonId}::uuid
        returning *
      `;
      if (!medicationRows[0]) {
        throw apiError(
          409,
          "identity_person_mapping_conflict",
          "Medication ownership is inconsistent with the patient Person.",
        );
      }
      const recurrenceJson = input.recurrence == null
        ? null
        : JSON.stringify(input.recurrence);
      const planRows = await tx`
        update lifemate.treatment_plans
        set dose_text=${input.doseText}, instructions=${input.instructions},
            start_date=${input.startDate}::date, end_date=${input.endDate}::date,
            time_zone=${input.timeZone}, recurrence_rule=${recurrenceJson}::jsonb,
            recurrence_start_local_time=${input.recurrenceStartLocalTime}::time,
            patient_reminder_minutes_before=${input.patientReminderMinutesBefore},
            caregiver_reminder_minutes_before=${input.caregiverReminderMinutesBefore},
            status=${input.status}, provenance_source='CaregiverInput',
            version=version+1, updated_at_utc=now()
        where id=${treatmentPlanId}::uuid
          and patient_person_id=${patientPersonId}::uuid
        returning *
      `;
      if (!planRows[0]) {
        throw apiError(
          409,
          "identity_person_mapping_conflict",
          "Treatment ownership changed during the update.",
        );
      }
      await tx`
        delete from lifemate.dose_occurrences
        where treatment_plan_id=${treatmentPlanId}::uuid
          and patient_person_id=${patientPersonId}::uuid
          and status in ('Scheduled','Missed') and scheduled_at_utc >= now()
      `;
      await tx`delete from lifemate.treatment_schedules where treatment_plan_id=${treatmentPlanId}::uuid`;
      const schedules = await replaceSchedules(tx, treatmentPlanId, input);
      await insertAudit(
        tx,
        caregiverAppUserId,
        "caregiver.treatment_plan.updated",
        treatmentPlanId,
      );
      return mapTreatmentPlan(
        withMedication(planRows[0], medicationRows[0]),
        schedules,
        patientAppUserId,
      );
    });
  }

  async function archiveTreatmentPlan(
    caregiverAppUserId: string,
    patientAppUserId: string,
    treatmentPlanId: string,
    expectedVersion: number,
  ): Promise<void> {
    await sql.begin(async (tx: any) => {
      const patientPersonId = await requireSelfPerson(
        tx,
        patientAppUserId,
        apiError,
      );
      const rows = await tx`
        select * from lifemate.treatment_plans
        where id=${treatmentPlanId}::uuid and patient_person_id=${patientPersonId}::uuid
        for update
      `;
      const plan = rows[0];
      if (!plan) {
        throw apiError(
          404,
          "treatment_plan_not_found",
          "Treatment plan was not found.",
        );
      }
      if (Number(plan.version) !== expectedVersion) {
        throw apiError(
          409,
          "stale_treatment_plan",
          "Treatment plan has changed. Refresh and try again.",
        );
      }
      await tx`
        update lifemate.treatment_plans set status='Archived', version=version+1,
          provenance_source='CaregiverInput', updated_at_utc=now()
        where id=${treatmentPlanId}::uuid and patient_person_id=${patientPersonId}::uuid
      `;
      await tx`
        delete from lifemate.dose_occurrences
        where treatment_plan_id=${treatmentPlanId}::uuid
          and patient_person_id=${patientPersonId}::uuid
          and status in ('Scheduled','Missed') and scheduled_at_utc >= now()
      `;
      await insertAudit(
        tx,
        caregiverAppUserId,
        "caregiver.treatment_plan.archived",
        treatmentPlanId,
      );
    });
  }

  return {
    listTreatmentPlans,
    createTreatmentPlan,
    updateTreatmentPlan,
    archiveTreatmentPlan,
  };
}

async function replaceSchedules(
  tx: any,
  planId: string,
  input: TreatmentInput,
): Promise<Row[]> {
  const values: Schedule[] = input.recurrence == null
    ? input.schedules
    : [{ dayOfWeek: "recurrence", localTime: input.recurrenceStartLocalTime! }];
  const rows: Row[] = [];
  for (const schedule of values) {
    const inserted = await tx`
      insert into lifemate.treatment_schedules
        (id,treatment_plan_id,day_of_week,local_time,created_at_utc)
      values (${crypto.randomUUID()}::uuid,${planId}::uuid,
        ${schedule.dayOfWeek},${schedule.localTime}::time,now()) returning *
    `;
    rows.push(inserted[0]);
  }
  return rows;
}

function normalizeTreatmentBody(
  body: Record<string, unknown>,
  editing: boolean,
  error: ApiErrorFactory,
): TreatmentInput {
  const startDate = requiredDate(body.startDate, "startDate", error);
  const endDate = body.endDate == null || body.endDate === ""
    ? null
    : requiredDate(body.endDate, "endDate", error);
  if (endDate && endDate < startDate) {
    throw error(
      400,
      "invalid_treatment_plan",
      "End date cannot precede start date.",
    );
  }
  const recurrence = normalizeCareRecurrence(body.recurrence, error);
  const recurrenceStartLocalTime = recurrence == null
    ? null
    : normalizeCareRecurrenceStartTime(body.recurrenceStartLocalTime, error);
  if (recurrence?.endAt != null && recurrence.endAt.slice(0, 10) < startDate) {
    throw error(
      400,
      "invalid_recurrence_end",
      "Recurrence end cannot precede treatment start.",
    );
  }
  return {
    version: editing ? positiveInt(body.version, "version", error) : 1,
    medicationVersion: editing
      ? positiveInt(body.medicationVersion, "medicationVersion", error)
      : 1,
    medicationName: text(body.medicationName, "medicationName", 120, error),
    strengthText: optionalText(body.strengthText, 80, error),
    form: optionalText(body.form, 50, error),
    doseText: text(body.doseText, "doseText", 80, error),
    instructions: optionalText(body.instructions, 500, error),
    startDate,
    endDate,
    timeZone: text(body.timeZone, "timeZone", 80, error),
    schedules: recurrence == null
      ? normalizeSchedules(body.schedules, error)
      : [],
    recurrence,
    recurrenceStartLocalTime,
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
    status: normalizeStatus(body.status, error),
  };
}

function normalizeSchedules(
  value: unknown,
  error: ApiErrorFactory,
): Schedule[] {
  if (!Array.isArray(value) || value.length === 0 || value.length > 28) {
    throw error(
      400,
      "invalid_schedules",
      "At least one treatment schedule is required.",
    );
  }
  const days = new Set([
    "sunday",
    "monday",
    "tuesday",
    "wednesday",
    "thursday",
    "friday",
    "saturday",
  ]);
  const seen = new Set<string>();
  return value.map((raw) => {
    if (!raw || typeof raw !== "object" || Array.isArray(raw)) {
      throw error(400, "invalid_schedules", "Schedule is invalid.");
    }
    const record = raw as Record<string, unknown>;
    const dayOfWeek = String(record.dayOfWeek ?? "").trim().toLowerCase();
    if (!days.has(dayOfWeek)) {
      throw error(400, "invalid_schedules", "Schedule day is invalid.");
    }
    const localTime = normalizeCareRecurrenceStartTime(record.localTime, error);
    const key = `${dayOfWeek}:${localTime}`;
    if (seen.has(key)) {
      throw error(400, "invalid_schedules", "Duplicate schedule.");
    }
    seen.add(key);
    return { dayOfWeek, localTime };
  });
}

function mapTreatmentPlan(
  row: Row,
  schedules: Row[],
  patientAppUserId: string,
): Record<string, unknown> {
  const recurrence = parseRecurrence(row.recurrence_rule);
  return {
    id: row.id,
    patientUserId: patientAppUserId,
    medication: {
      id: row.medication_id,
      name: row.medication_name,
      strengthText: row.strength_text,
      form: row.form,
      notes: row.medication_notes,
      version: Number(row.medication_version ?? 1),
    },
    doseText: row.dose_text,
    instructions: row.instructions,
    startDate: dateValue(row.start_date),
    endDate: row.end_date == null ? null : dateValue(row.end_date),
    timeZone: row.time_zone,
    schedules: schedules.filter((schedule) =>
      String(schedule.day_of_week) !== "recurrence"
    ).map((schedule) => ({
      id: schedule.id,
      dayOfWeek: schedule.day_of_week,
      localTime: timeValue(schedule.local_time),
    })),
    recurrence: recurrencePublicValue(recurrence),
    recurrenceStartLocalTime: row.recurrence_start_local_time == null
      ? null
      : timeValue(row.recurrence_start_local_time),
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

function parseRecurrence(value: unknown): CareRecurrenceRule | null {
  if (value == null) return null;
  const raw = typeof value === "string" ? JSON.parse(value) : value;
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) return null;
  const r = raw as Record<string, any>;
  if (r.enabled !== true) return null;
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
  appUserId: string,
  error: ApiErrorFactory,
): Promise<string> {
  const rows =
    await sql`select core.self_person_id_for_legacy_app_user(${appUserId}::uuid)::text as person_id`;
  const personId = rows[0]?.person_id;
  if (typeof personId !== "string" || personId.length === 0) {
    throw error(
      409,
      "identity_person_mapping_missing",
      "The patient Person mapping is unavailable.",
    );
  }
  return personId;
}

function withMedication(plan: Row, medication: Row): Row {
  return {
    ...plan,
    medication_name: medication.name,
    strength_text: medication.strength_text,
    form: medication.form,
    medication_notes: medication.notes,
    medication_version: medication.version,
  };
}
function dateValue(value: unknown): string {
  return value instanceof Date
    ? value.toISOString().slice(0, 10)
    : String(value).slice(0, 10);
}
function timeValue(value: unknown): string {
  return String(value).slice(0, 5);
}
function iso(value: unknown): string {
  return value instanceof Date
    ? value.toISOString()
    : new Date(String(value)).toISOString();
}
function positiveInt(
  value: unknown,
  field: string,
  error: ApiErrorFactory,
): number {
  const n = Number(value);
  if (!Number.isInteger(n) || n < 1) {
    throw error(400, `invalid_${field}`, `${field} must be positive.`);
  }
  return n;
}
function text(
  value: unknown,
  field: string,
  max: number,
  error: ApiErrorFactory,
): string {
  const s = String(value ?? "").trim();
  if (!s || s.length > max) {
    throw error(400, `invalid_${field}`, `${field} is invalid.`);
  }
  return s;
}
function optionalText(
  value: unknown,
  max: number,
  error: ApiErrorFactory,
): string | null {
  if (value == null) return null;
  const s = String(value).trim();
  if (!s) return null;
  if (s.length > max) {
    throw error(400, "invalid_text", "Text value is too long.");
  }
  return s;
}
function requiredDate(
  value: unknown,
  field: string,
  error: ApiErrorFactory,
): string {
  const s = String(value ?? "").trim();
  if (!/^\d{4}-\d{2}-\d{2}$/.test(s)) {
    throw error(400, `invalid_${field}`, `${field} must be YYYY-MM-DD.`);
  }
  const d = new Date(`${s}T00:00:00.000Z`);
  if (Number.isNaN(d.getTime()) || d.toISOString().slice(0, 10) !== s) {
    throw error(400, `invalid_${field}`, `${field} is invalid.`);
  }
  return s;
}
function reminder(
  value: unknown,
  fallback: number,
  error: ApiErrorFactory,
): number {
  if (value == null || value === "") return fallback;
  const n = Number(value);
  if (!Number.isInteger(n) || n < 0 || n > 10080) {
    throw error(
      400,
      "invalid_reminder",
      "Reminder lead time must be between 0 and 10080 minutes.",
    );
  }
  return n;
}
function normalizeStatus(
  value: unknown,
  error: ApiErrorFactory,
): "Active" | "Stopped" {
  const s = String(value ?? "active").trim().toLowerCase();
  if (s === "active") return "Active";
  if (s === "stopped" || s === "paused") return "Stopped";
  throw error(400, "invalid_treatment_status", "Treatment status is invalid.");
}
async function insertAudit(
  sql: any,
  actor: string,
  action: string,
  planId: string,
): Promise<void> {
  await sql`insert into lifemate.audit_logs (id,actor_user_id,action,resource_type,resource_id,metadata_json,created_at_utc) values (${crypto.randomUUID()}::uuid,${actor}::uuid,${action},'treatment_plan',${planId}::uuid,null,now())`;
}
