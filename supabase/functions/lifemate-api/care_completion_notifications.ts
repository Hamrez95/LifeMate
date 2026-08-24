import { getLifeMateSql } from "./database_client.ts";
import { ApiError, requiredUuid } from "./validation.ts";

type Row = Record<string, any>;

export function createCareCompletionNotificationStore(databaseUrl: string) {
  const sql = getLifeMateSql(databaseUrl);

  async function claim(
    caregiverAppUserId: string,
    relationshipIdValue: unknown,
  ): Promise<Record<string, unknown>[]> {
    const caregiverPersonId = await requireSelfPerson(sql, caregiverAppUserId);
    const relationshipId = requiredUuid(relationshipIdValue, "relationshipId");
    const rows = await sql`
      with candidates as materialized (
        select
          e.id::text as source_event_id,
          r.id::text as relationship_id,
          r.patient_user_id::text as patient_user_id,
          profile.display_name as patient_display_name,
          m.name as medication_name,
          p.dose_text,
          e.previous_status,
          e.resulting_status,
          e.event_type,
          e.occurred_at_utc,
          e.recorded_at_utc,
          r.caregiver_lock_screen_detail
        from lifemate.dose_adherence_events e
        join lifemate.dose_occurrences o
          on o.id = e.occurrence_id
        join lifemate.treatment_plans p
          on p.id = o.treatment_plan_id
         and p.patient_person_id = o.patient_person_id
        join lifemate.medications m
          on m.id = p.medication_id
         and m.owner_person_id = o.patient_person_id
        join lifemate.care_relationships r
          on r.id = ${relationshipId}::uuid
         and r.patient_person_id = o.patient_person_id
         and r.caregiver_person_id = ${caregiverPersonId}::uuid
         and r.status = 'Active'
         and r.patient_consented_at_utc is not null
         and r.caregiver_consented_at_utc is not null
        join core.person_profiles profile
          on profile.person_id = o.patient_person_id
        left join lifemate.caregiver_completion_notification_receipts receipt
          on receipt.caregiver_person_id = ${caregiverPersonId}::uuid
         and receipt.source_adherence_event_id = e.id
        where receipt.id is null
          and o.status = 'Taken'
          and e.resulting_status = 'Taken'
          and e.event_type in ('Taken','Corrected')
          and r.caregiver_notifications_enabled = true
          and r.caregiver_completion_mode in ('all','after_missed')
          and (
            r.caregiver_completion_mode = 'all'
            or lower(e.previous_status) in ('missed','skipped')
          )
          and e.recorded_at_utc >= now() - interval '24 hours'
          and e.recorded_at_utc >= e.occurred_at_utc
          and e.recorded_at_utc - e.occurred_at_utc <= interval '15 minutes'
        order by e.recorded_at_utc, e.id
        limit 20
      ), inserted as (
        insert into lifemate.caregiver_completion_notification_receipts(
          caregiver_person_id,
          relationship_id,
          source_adherence_event_id,
          claimed_at_utc
        )
        select
          ${caregiverPersonId}::uuid,
          c.relationship_id::uuid,
          c.source_event_id::uuid,
          now()
        from candidates c
        on conflict(caregiver_person_id, source_adherence_event_id) do nothing
        returning source_adherence_event_id::text as source_event_id
      )
      select c.*
      from candidates c
      join inserted i on i.source_event_id = c.source_event_id
      order by c.recorded_at_utc, c.source_event_id
    `;
    return rows.map(mapNotification);
  }

  async function history(
    caregiverAppUserId: string,
    relationshipIdValue: unknown,
  ): Promise<Record<string, unknown>[]> {
    const caregiverPersonId = await requireSelfPerson(sql, caregiverAppUserId);
    const relationshipId = requiredUuid(relationshipIdValue, "relationshipId");
    const rows = await sql`
      select
        e.id::text as source_event_id,
        r.id::text as relationship_id,
        r.patient_user_id::text as patient_user_id,
        profile.display_name as patient_display_name,
        m.name as medication_name,
        p.dose_text,
        e.previous_status,
        e.resulting_status,
        e.event_type,
        e.occurred_at_utc,
        e.recorded_at_utc,
        r.caregiver_lock_screen_detail
      from lifemate.caregiver_completion_notification_receipts receipt
      join lifemate.dose_adherence_events e
        on e.id = receipt.source_adherence_event_id
      join lifemate.dose_occurrences o
        on o.id = e.occurrence_id
      join lifemate.treatment_plans p
        on p.id = o.treatment_plan_id
       and p.patient_person_id = o.patient_person_id
      join lifemate.medications m
        on m.id = p.medication_id
       and m.owner_person_id = o.patient_person_id
      join lifemate.care_relationships r
        on r.id = ${relationshipId}::uuid
       and r.id = receipt.relationship_id
       and r.patient_person_id = o.patient_person_id
       and r.caregiver_person_id = ${caregiverPersonId}::uuid
       and r.status = 'Active'
       and r.patient_consented_at_utc is not null
       and r.caregiver_consented_at_utc is not null
      join core.person_profiles profile
        on profile.person_id = o.patient_person_id
      where receipt.caregiver_person_id = ${caregiverPersonId}::uuid
        and o.status = 'Taken'
        and e.resulting_status = 'Taken'
      order by receipt.claimed_at_utc desc, e.id desc
      limit 50
    `;
    return rows.map(mapNotification);
  }

  return { claim, history };
}

function mapNotification(row: Row): Record<string, unknown> {
  return {
    sourceEventId: row.source_event_id,
    relationshipId: row.relationship_id,
    patientUserId: row.patient_user_id,
    patientDisplayName: row.patient_display_name ?? "LifeMate User",
    medicationName: row.medication_name ?? "Medication",
    doseText: row.dose_text ?? "",
    previousStatus: String(row.previous_status ?? "").toLowerCase(),
    resultingStatus: String(row.resulting_status ?? "").toLowerCase(),
    eventType: String(row.event_type ?? "").toLowerCase(),
    evidenceClass: "self_reported",
    occurredAtUtc: iso(row.occurred_at_utc),
    recordedAtUtc: iso(row.recorded_at_utc),
    lockScreenDetail: String(row.caregiver_lock_screen_detail ?? "limited"),
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

function iso(value: unknown): string {
  return value instanceof Date
    ? value.toISOString()
    : new Date(String(value)).toISOString();
}
