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

type StoreDependencies = {
  sql: any;
  normalizeTreatment: (
    body: Record<string, unknown>,
    editing: boolean,
  ) => TreatmentInput;
  apiError: (status: number, code: string, message: string) => Error;
};

async function requireSelfPerson(
  sql: any,
  patientAppUserId: string,
  apiError: StoreDependencies["apiError"],
): Promise<string> {
  const rows = await sql`
    select core.self_person_id_for_legacy_app_user(
      ${patientAppUserId}::uuid
    )::text as person_id
  `;
  const personId = rows[0]?.person_id;
  if (typeof personId !== "string" || personId.length === 0) {
    throw apiError(
      409,
      "identity_person_mapping_missing",
      "The patient Person mapping is unavailable.",
    );
  }
  return personId;
}

function iso(value: unknown): string {
  return value instanceof Date
    ? value.toISOString()
    : new Date(String(value)).toISOString();
}

function dateValue(value: unknown): string {
  if (value instanceof Date) return value.toISOString().slice(0, 10);
  return String(value).slice(0, 10);
}

function timeValue(value: unknown): string {
  return String(value).slice(0, 5);
}

function mapTreatmentPlan(
  row: Row,
  schedules: Row[],
  patientAppUserId: string,
): Record<string, unknown> {
  return {
    id: row.id,
    // Public compatibility projection only. Ownership/authorization below is
    // exclusively patient_person_id / owner_person_id.
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
    schedules: schedules.map((schedule) => ({
      id: schedule.id,
      dayOfWeek: schedule.day_of_week,
      localTime: timeValue(schedule.local_time),
    })),
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

async function insertAudit(
  sql: any,
  caregiverAppUserId: string,
  action: string,
  treatmentPlanId: string,
): Promise<void> {
  await sql`
    insert into lifemate.audit_logs
      (id, actor_user_id, action, resource_type, resource_id,
       metadata_json, created_at_utc)
    values
      (${crypto.randomUUID()}::uuid, ${caregiverAppUserId}::uuid, ${action},
       'treatment_plan', ${treatmentPlanId}::uuid, null, now())
  `;
}

/**
 * Caregiver-managed Treatment data boundary.
 *
 * Relationship consent/permission remains in the existing Care Management
 * route guard for this staged slice. Once authorized, all medication/treatment
 * data selection and mutation is canonical Person-only. The requested patient
 * AppUser is retained only as an API response projection and as input to the
 * explicit Self-Person resolver.
 */
export function createPersonTreatmentManagementStore(
  dependencies: StoreDependencies,
) {
  const { sql, normalizeTreatment, apiError } = dependencies;

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
        on m.id = p.medication_id
       and m.owner_person_id = p.patient_person_id
      where p.patient_person_id = ${patientPersonId}::uuid
        and p.status <> 'Archived'
      order by p.updated_at_utc desc, p.id
      limit 100
    `;
    if (plans.length === 0) return [];
    const ids = plans.map((row: Row) => row.id);
    const schedules = await sql`
      select *
      from lifemate.treatment_schedules
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
    const input = normalizeTreatment(body, false);
    return await sql.begin(async (tx: any) => {
      const patientPersonId = await requireSelfPerson(
        tx,
        patientAppUserId,
        apiError,
      );
      const medicationId = crypto.randomUUID();
      const planId = crypto.randomUUID();
      const now = new Date();

      const medicationRows = await tx`
        insert into lifemate.medications
          (id, owner_person_id, name, strength_text, form, notes, version,
           provenance_source, provenance_restricted,
           created_at_utc, updated_at_utc)
        values
          (${medicationId}::uuid, ${patientPersonId}::uuid,
           ${input.medicationName}, ${input.strengthText}, ${input.form}, null, 1,
           'CaregiverInput', false, ${now}, ${now})
        returning *
      `;

      const planRows = await tx`
        insert into lifemate.treatment_plans
          (id, patient_person_id, medication_id, dose_text, instructions,
           start_date, end_date, time_zone,
           patient_reminder_minutes_before, caregiver_reminder_minutes_before,
           status, version, provenance_source, provenance_restricted,
           created_at_utc, updated_at_utc)
        values
          (${planId}::uuid, ${patientPersonId}::uuid, ${medicationId}::uuid,
           ${input.doseText}, ${input.instructions}, ${input.startDate}::date,
           ${input.endDate}::date, ${input.timeZone},
           ${input.patientReminderMinutesBefore},
           ${input.caregiverReminderMinutesBefore},
           'Active', 1, 'CaregiverInput', false, ${now}, ${now})
        returning *
      `;

      const schedules: Row[] = [];
      for (const schedule of input.schedules) {
        const rows = await tx`
          insert into lifemate.treatment_schedules
            (id, treatment_plan_id, day_of_week, local_time, created_at_utc)
          values
            (${crypto.randomUUID()}::uuid, ${planId}::uuid,
             ${schedule.dayOfWeek}, ${schedule.localTime}::time, ${now})
          returning *
        `;
        schedules.push(rows[0]);
      }

      await insertAudit(
        tx,
        caregiverAppUserId,
        "caregiver.treatment_plan.created",
        planId,
      );
      return mapTreatmentPlan(
        {
          ...planRows[0],
          medication_name: medicationRows[0].name,
          strength_text: medicationRows[0].strength_text,
          form: medicationRows[0].form,
          medication_notes: medicationRows[0].notes,
          medication_version: medicationRows[0].version,
        },
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
    const input = normalizeTreatment(body, true);
    return await sql.begin(async (tx: any) => {
      const patientPersonId = await requireSelfPerson(
        tx,
        patientAppUserId,
        apiError,
      );
      const existingRows = await tx`
        select p.*, m.name as medication_name, m.strength_text, m.form,
               m.version as medication_version
        from lifemate.treatment_plans p
        join lifemate.medications m
          on m.id = p.medication_id
         and m.owner_person_id = p.patient_person_id
        where p.id = ${treatmentPlanId}::uuid
          and p.patient_person_id = ${patientPersonId}::uuid
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
        set name = ${input.medicationName},
            strength_text = ${input.strengthText},
            form = ${input.form},
            provenance_source = 'CaregiverInput',
            version = version + 1,
            updated_at_utc = now()
        where id = ${existing.medication_id}::uuid
          and owner_person_id = ${patientPersonId}::uuid
        returning *
      `;
      if (!medicationRows[0]) {
        throw apiError(
          409,
          "identity_person_mapping_conflict",
          "Medication ownership is inconsistent with the patient Person.",
        );
      }

      const planRows = await tx`
        update lifemate.treatment_plans
        set dose_text = ${input.doseText},
            instructions = ${input.instructions},
            start_date = ${input.startDate}::date,
            end_date = ${input.endDate}::date,
            time_zone = ${input.timeZone},
            patient_reminder_minutes_before =
              ${input.patientReminderMinutesBefore},
            caregiver_reminder_minutes_before =
              ${input.caregiverReminderMinutesBefore},
            status = ${input.status},
            provenance_source = 'CaregiverInput',
            version = version + 1,
            updated_at_utc = now()
        where id = ${treatmentPlanId}::uuid
          and patient_person_id = ${patientPersonId}::uuid
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
        where treatment_plan_id = ${treatmentPlanId}::uuid
          and patient_person_id = ${patientPersonId}::uuid
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
             ${schedule.dayOfWeek}, ${schedule.localTime}::time, now())
          returning *
        `;
        schedules.push(rows[0]);
      }

      await insertAudit(
        tx,
        caregiverAppUserId,
        "caregiver.treatment_plan.updated",
        treatmentPlanId,
      );
      return mapTreatmentPlan(
        {
          ...planRows[0],
          medication_name: medicationRows[0].name,
          strength_text: medicationRows[0].strength_text,
          form: medicationRows[0].form,
          medication_notes: medicationRows[0].notes,
          medication_version: medicationRows[0].version,
        },
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
        select *
        from lifemate.treatment_plans
        where id = ${treatmentPlanId}::uuid
          and patient_person_id = ${patientPersonId}::uuid
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
        update lifemate.treatment_plans
        set status = 'Archived', version = version + 1,
            provenance_source = 'CaregiverInput', updated_at_utc = now()
        where id = ${treatmentPlanId}::uuid
          and patient_person_id = ${patientPersonId}::uuid
      `;
      await tx`
        delete from lifemate.dose_occurrences
        where treatment_plan_id = ${treatmentPlanId}::uuid
          and patient_person_id = ${patientPersonId}::uuid
          and status in ('Scheduled', 'Missed')
          and scheduled_at_utc >= now()
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
