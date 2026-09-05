import { getLifeMateSql } from "./database_client.ts";
import {
  expandLocalRecurrence,
  normalizeRecurrenceRule,
} from "./recurrence_schedule.ts";
import {
  ApiError,
  normalizeDoseStatus,
  requiredDate,
  requiredPositiveInt,
  requiredTimestamp,
  requiredUuid,
  validateRange,
  validateReportedAt,
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

function mapDoseOccurrence(row: Row): Record<string, unknown> {
  return {
    id: row.id,
    treatmentPlanId: row.treatment_plan_id,
    treatmentScheduleId: row.treatment_schedule_id,
    scheduledAtUtc: iso(row.scheduled_at_utc),
    scheduledLocalDate: dateString(row.scheduled_local_date),
    scheduledLocalTime: timeString(row.scheduled_local_time),
    timeZone: row.time_zone,
    status: String(row.status).toLowerCase(),
    respondedAtUtc: row.responded_at_utc == null
      ? null
      : iso(row.responded_at_utc),
    patientReminderMinutesBefore: Number(
      row.patient_reminder_minutes_before ?? 30,
    ),
    caregiverReminderMinutesBefore: Number(
      row.caregiver_reminder_minutes_before ?? 60,
    ),
    version: row.version,
    createdAtUtc: iso(row.created_at_utc),
    updatedAtUtc: iso(row.updated_at_utc),
  };
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

/**
 * Materialize only the requested bounded local-date window. Legacy weekly
 * schedules retain their existing SQL path; versioned recurrence plans use the
 * canonical wall-clock expander and PostgreSQL performs IANA-zone conversion.
 */
async function materializeOccurrencesForPerson(
  sql: any,
  patientPersonId: string,
  fromDate: string,
  toDate: string,
): Promise<void> {
  await sql.begin(async (tx: any) => {
    // Backward-compatible path for all pre-#474 plans.
    await tx`
      insert into lifemate.dose_occurrences
        (id, patient_person_id, treatment_plan_id,
         treatment_schedule_id, scheduled_at_utc, scheduled_local_date,
         scheduled_local_time, time_zone, status, responded_at_utc, version,
         created_at_utc, updated_at_utc)
      select
        gen_random_uuid(), p.patient_person_id,
        p.id, s.id,
        ((day_value::date + s.local_time) at time zone p.time_zone),
        day_value::date, s.local_time, p.time_zone, 'Scheduled', null, 1,
        now(), now()
      from lifemate.treatment_plans p
      join lifemate.treatment_schedules s on s.treatment_plan_id = p.id
      cross join generate_series(
        ${fromDate}::date,
        ${toDate}::date,
        interval '1 day'
      ) as day_value
      where p.patient_person_id = ${patientPersonId}::uuid
        and p.status = 'Active'
        and p.recurrence_rule is null
        and day_value::date >= p.start_date
        and (p.end_date is null or day_value::date <= p.end_date)
        and extract(dow from day_value)::integer = case lower(s.day_of_week)
          when 'sunday' then 0
          when 'monday' then 1
          when 'tuesday' then 2
          when 'wednesday' then 3
          when 'thursday' then 4
          when 'friday' then 5
          when 'saturday' then 6
          else -1
        end
      on conflict (treatment_schedule_id, scheduled_at_utc) do nothing
    `;

    const recurringPlans = await tx`
      select p.id, p.start_date, p.end_date, p.time_zone,
             p.recurrence_rule, p.recurrence_start_local_time,
             s.id as anchor_schedule_id
      from lifemate.treatment_plans p
      join lifemate.treatment_schedules s
        on s.treatment_plan_id = p.id
       and lower(s.day_of_week) = 'recurrence'
      where p.patient_person_id = ${patientPersonId}::uuid
        and p.status = 'Active'
        and p.recurrence_rule is not null
        and p.start_date <= ${toDate}::date
        and (p.end_date is null or p.end_date >= ${fromDate}::date)
      order by p.id
      limit 100
    `;

    for (const plan of recurringPlans) {
      const rawRule = typeof plan.recurrence_rule === "string"
        ? JSON.parse(plan.recurrence_rule)
        : plan.recurrence_rule;
      const rule = normalizeRecurrenceRule(rawRule);
      if (rule == null) continue;
      const startDate = dateString(plan.start_date);
      const startTime = timeString(plan.recurrence_start_local_time);
      const startLocal = `${startDate}T${startTime}:00`;
      const localValues = expandLocalRecurrence(
        startLocal,
        rule,
        `${fromDate}T00:00:00`,
        `${toDate}T23:59:59`,
        1000,
      );
      for (const localValue of localValues) {
        const localDate = localValue.slice(0, 10);
        const localTime = localValue.slice(11, 19);
        await tx`
          insert into lifemate.dose_occurrences
            (id, patient_person_id, treatment_plan_id,
             treatment_schedule_id, scheduled_at_utc, scheduled_local_date,
             scheduled_local_time, time_zone, status, responded_at_utc, version,
             created_at_utc, updated_at_utc)
          values
            (gen_random_uuid(), ${patientPersonId}::uuid,
             ${plan.id}::uuid, ${plan.anchor_schedule_id}::uuid,
             (${localValue}::timestamp at time zone ${plan.time_zone}),
             ${localDate}::date, ${localTime}::time, ${plan.time_zone},
             'Scheduled', null, 1, now(), now())
          on conflict (treatment_schedule_id, scheduled_at_utc) do nothing
        `;
      }
    }

    await tx`
      update lifemate.dose_occurrences
      set status = 'Missed', version = version + 1, updated_at_utc = now()
      where patient_person_id = ${patientPersonId}::uuid
        and scheduled_local_date between ${fromDate}::date and ${toDate}::date
        and status = 'Scheduled'
        and scheduled_at_utc + interval '60 minutes' < now()
    `;
  });
}

export function createPersonDoseOccurrenceStore(databaseUrl: string) {
  const sql = getLifeMateSql(databaseUrl);

  async function listDoseOccurrences(
    patientAppUserId: string,
    fromValue: unknown,
    toValue: unknown,
  ): Promise<Record<string, unknown>[]> {
    const fromDate = requiredDate(fromValue, "fromDate");
    const toDate = requiredDate(toValue, "toDate");
    validateRange(fromDate, toDate);
    const patientPersonId = await requireSelfPerson(sql, patientAppUserId);
    await materializeOccurrencesForPerson(
      sql,
      patientPersonId,
      fromDate,
      toDate,
    );

    const rows = await sql`
      select o.*, p.patient_reminder_minutes_before,
             p.caregiver_reminder_minutes_before
      from lifemate.dose_occurrences o
      join lifemate.treatment_plans p
        on p.id = o.treatment_plan_id
       and p.patient_person_id = o.patient_person_id
      where o.patient_person_id = ${patientPersonId}::uuid
        and o.scheduled_local_date between ${fromDate}::date and ${toDate}::date
      order by o.scheduled_at_utc, o.id
    `;
    return rows.map(mapDoseOccurrence);
  }

  async function reportDose(
    patientAppUserId: string,
    occurrenceIdValue: unknown,
    body: Record<string, unknown>,
  ): Promise<Record<string, unknown>> {
    const occurrenceId = requiredUuid(occurrenceIdValue, "occurrenceId");
    const clientRequestId = requiredUuid(
      body.clientRequestId,
      "clientRequestId",
    );
    const expectedVersion = requiredPositiveInt(body.version, "version");
    const target = normalizeDoseStatus(body.status);
    const occurredAt = requiredTimestamp(body.occurredAtUtc, "occurredAtUtc");
    validateReportedAt(occurredAt);

    return await sql.begin(async (tx: any) => {
      const patientPersonId = await requireSelfPerson(tx, patientAppUserId);
      const rows = await tx`
        select *
        from lifemate.dose_occurrences
        where id = ${occurrenceId}::uuid
          and patient_person_id = ${patientPersonId}::uuid
        for update
      `;
      const occurrence = rows[0];
      if (!occurrence) {
        throw new ApiError(
          404,
          "dose_occurrence_not_found",
          "Dose was not found.",
        );
      }

      const existingEvents = await tx`
        select occurrence_id
        from lifemate.dose_adherence_events
        where actor_user_id = ${patientAppUserId}::uuid
          and client_request_id = ${clientRequestId}::uuid
        limit 1
      `;
      if (existingEvents[0]) {
        if (existingEvents[0].occurrence_id !== occurrenceId) {
          throw new ApiError(
            409,
            "idempotency_key_reused",
            "clientRequestId was already used for another dose.",
          );
        }
        return mapDoseOccurrence(occurrence);
      }

      if (occurrence.version !== expectedVersion) {
        throw new ApiError(
          409,
          "stale_dose_occurrence",
          "Dose has changed. Refresh and try again.",
        );
      }
      if (occurrence.status === "Cancelled") {
        throw new ApiError(
          409,
          "dose_not_reportable",
          "Cancelled dose cannot be reported.",
        );
      }
      if (occurrence.status === target) return mapDoseOccurrence(occurrence);

      const previous = occurrence.status;
      const eventType = previous === "Scheduled"
        ? target === "Taken" ? "Taken" : "Skipped"
        : "Corrected";
      const updated = await tx`
        update lifemate.dose_occurrences
        set status = ${target}, responded_at_utc = ${occurredAt},
            version = version + 1, updated_at_utc = now()
        where id = ${occurrenceId}::uuid
        returning *
      `;
      await tx`
        insert into lifemate.dose_adherence_events
          (id, occurrence_id, actor_user_id, client_request_id, event_type,
           previous_status, resulting_status, occurred_at_utc, recorded_at_utc)
        values
          (${crypto.randomUUID()}::uuid, ${occurrenceId}::uuid,
           ${patientAppUserId}::uuid, ${clientRequestId}::uuid, ${eventType},
           ${previous}, ${target}, ${occurredAt}, now())
      `;
      return mapDoseOccurrence(updated[0]);
    });
  }

  async function listCareDoseOccurrences(
    caregiverAppUserId: string,
    patientAppUserIdValue: unknown,
    fromValue: unknown,
    toValue: unknown,
  ): Promise<Record<string, unknown>[]> {
    const patientAppUserId = requiredUuid(
      patientAppUserIdValue,
      "patientUserId",
    );
    const fromDate = requiredDate(fromValue, "fromDate");
    const toDate = requiredDate(toValue, "toDate");
    validateRange(fromDate, toDate);

    const patientPersonId = await requireSelfPerson(sql, patientAppUserId);
    const caregiverPersonId = await requireSelfPerson(sql, caregiverAppUserId);
    const relationships = await sql`
      select id
      from lifemate.care_relationships
      where patient_person_id = ${patientPersonId}::uuid
        and caregiver_person_id = ${caregiverPersonId}::uuid
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

    await materializeOccurrencesForPerson(
      sql,
      patientPersonId,
      fromDate,
      toDate,
    );
    const rows = await sql`
      select o.*, m.name as medication_name, p.dose_text,
             p.patient_reminder_minutes_before,
             p.caregiver_reminder_minutes_before
      from lifemate.dose_occurrences o
      join lifemate.treatment_plans p
        on p.id = o.treatment_plan_id
       and p.patient_person_id = o.patient_person_id
      join lifemate.medications m
        on m.id = p.medication_id
       and m.owner_person_id = o.patient_person_id
      where o.patient_person_id = ${patientPersonId}::uuid
        and o.scheduled_local_date between ${fromDate}::date and ${toDate}::date
      order by o.scheduled_at_utc, o.id
    `;
    return rows.map((row: Row) => ({
      ...mapDoseOccurrence(row),
      medicationName: row.medication_name,
      doseText: row.dose_text,
    }));
  }

  return {
    listDoseOccurrences,
    reportDose,
    listCareDoseOccurrences,
  };
}
