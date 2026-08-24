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
    const medicationRows = await claimMedication(
      sql,
      caregiverPersonId,
      relationshipId,
    );
    const careEventRows = await claimCareEvents(
      sql,
      caregiverPersonId,
      relationshipId,
    );
    return [...medicationRows, ...careEventRows]
      .map(mapNotification)
      .sort(compareRecordedAt);
  }

  async function history(
    caregiverAppUserId: string,
    relationshipIdValue: unknown,
  ): Promise<Record<string, unknown>[]> {
    const caregiverPersonId = await requireSelfPerson(sql, caregiverAppUserId);
    const relationshipId = requiredUuid(relationshipIdValue, "relationshipId");
    const medicationRows = await medicationHistory(
      sql,
      caregiverPersonId,
      relationshipId,
    );
    const careEventRows = await careEventHistory(
      sql,
      caregiverPersonId,
      relationshipId,
    );
    return [...medicationRows, ...careEventRows]
      .map(mapNotification)
      .sort(compareRecordedAt)
      .reverse()
      .slice(0, 50);
  }

  return { claim, history };
}

async function claimMedication(
  sql: any,
  caregiverPersonId: string,
  relationshipId: string,
): Promise<Row[]> {
  return await sql`
    with candidates as materialized (
      select
        'adherence:' || e.id::text as source_key,
        e.id::text as source_event_id,
        'medication'::text as source_kind,
        r.id::text as relationship_id,
        r.patient_user_id::text as patient_user_id,
        profile.display_name as patient_display_name,
        m.name as item_name,
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
       and receipt.source_key = 'adherence:' || e.id::text
      where receipt.id is null
        and o.status = 'Taken'
        and e.resulting_status = 'Taken'
        and e.event_type in ('Taken','Corrected')
        and r.caregiver_notifications_enabled = true
        and r.caregiver_completion_mode in ('all','important','after_missed')
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
        caregiver_person_id,relationship_id,source_key,
        source_adherence_event_id,source_care_event_id,claimed_at_utc
      )
      select
        ${caregiverPersonId}::uuid,c.relationship_id::uuid,c.source_key,
        c.source_event_id::uuid,null,now()
      from candidates c
      on conflict(caregiver_person_id, source_key) do nothing
      returning source_key
    )
    select c.*
    from candidates c
    join inserted i on i.source_key = c.source_key
    order by c.recorded_at_utc, c.source_event_id
  `;
}

async function claimCareEvents(
  sql: any,
  caregiverPersonId: string,
  relationshipId: string,
): Promise<Row[]> {
  return await sql`
    with candidates as materialized (
      select
        'care-event:' || event.id::text || ':' || event.completed_at_utc::text
          as source_key,
        event.id::text as source_event_id,
        lower(event.event_type)::text as source_kind,
        r.id::text as relationship_id,
        r.patient_user_id::text as patient_user_id,
        profile.display_name as patient_display_name,
        coalesce(event.medication_name,event.title) as item_name,
        coalesce(event.dose_text,'') as dose_text,
        case
          when ((event.scheduled_local_date + event.scheduled_local_time)
                at time zone event.time_zone) < event.completed_at_utc
          then 'missed'
          else 'scheduled'
        end as previous_status,
        'completed'::text as resulting_status,
        'completed'::text as event_type,
        event.completed_at_utc as occurred_at_utc,
        event.updated_at_utc as recorded_at_utc,
        r.caregiver_lock_screen_detail
      from lifemate.care_events event
      join lifemate.care_relationships r
        on r.id = ${relationshipId}::uuid
       and r.patient_person_id = event.patient_person_id
       and r.caregiver_person_id = ${caregiverPersonId}::uuid
       and r.status = 'Active'
       and r.patient_consented_at_utc is not null
       and r.caregiver_consented_at_utc is not null
      join core.person_profiles profile
        on profile.person_id = event.patient_person_id
      left join lifemate.caregiver_completion_notification_receipts receipt
        on receipt.caregiver_person_id = ${caregiverPersonId}::uuid
       and receipt.source_key =
         'care-event:' || event.id::text || ':' || event.completed_at_utc::text
      where receipt.id is null
        and event.status = 'Completed'
        and event.completed_at_utc is not null
        and event.event_type in ('Appointment','Injection')
        and r.caregiver_notifications_enabled = true
        and r.caregiver_completion_mode in ('all','important','after_missed')
        and (
          r.caregiver_completion_mode in ('all','important')
          or ((event.scheduled_local_date + event.scheduled_local_time)
              at time zone event.time_zone) < event.completed_at_utc
        )
        and event.completed_at_utc >= now() - interval '24 hours'
        and event.updated_at_utc >= event.completed_at_utc
        and event.updated_at_utc - event.completed_at_utc <= interval '15 minutes'
      order by event.completed_at_utc, event.id
      limit 20
    ), inserted as (
      insert into lifemate.caregiver_completion_notification_receipts(
        caregiver_person_id,relationship_id,source_key,
        source_adherence_event_id,source_care_event_id,claimed_at_utc
      )
      select
        ${caregiverPersonId}::uuid,c.relationship_id::uuid,c.source_key,
        null,c.source_event_id::uuid,now()
      from candidates c
      on conflict(caregiver_person_id, source_key) do nothing
      returning source_key
    )
    select c.*
    from candidates c
    join inserted i on i.source_key = c.source_key
    order by c.recorded_at_utc, c.source_event_id
  `;
}

async function medicationHistory(
  sql: any,
  caregiverPersonId: string,
  relationshipId: string,
): Promise<Row[]> {
  return await sql`
    select
      receipt.source_key,
      e.id::text as source_event_id,
      'medication'::text as source_kind,
      r.id::text as relationship_id,
      r.patient_user_id::text as patient_user_id,
      profile.display_name as patient_display_name,
      m.name as item_name,
      p.dose_text,
      e.previous_status,e.resulting_status,e.event_type,
      e.occurred_at_utc,e.recorded_at_utc,
      r.caregiver_lock_screen_detail
    from lifemate.caregiver_completion_notification_receipts receipt
    join lifemate.dose_adherence_events e
      on e.id = receipt.source_adherence_event_id
     and receipt.source_key = 'adherence:' || e.id::text
    join lifemate.dose_occurrences o on o.id = e.occurrence_id
    join lifemate.treatment_plans p
      on p.id = o.treatment_plan_id and p.patient_person_id = o.patient_person_id
    join lifemate.medications m
      on m.id = p.medication_id and m.owner_person_id = o.patient_person_id
    join lifemate.care_relationships r
      on r.id = ${relationshipId}::uuid
     and r.id = receipt.relationship_id
     and r.patient_person_id = o.patient_person_id
     and r.caregiver_person_id = ${caregiverPersonId}::uuid
     and r.status = 'Active'
     and r.patient_consented_at_utc is not null
     and r.caregiver_consented_at_utc is not null
    join core.person_profiles profile on profile.person_id = o.patient_person_id
    where receipt.caregiver_person_id = ${caregiverPersonId}::uuid
      and o.status = 'Taken'
      and e.resulting_status = 'Taken'
    order by receipt.claimed_at_utc desc
    limit 50
  `;
}

async function careEventHistory(
  sql: any,
  caregiverPersonId: string,
  relationshipId: string,
): Promise<Row[]> {
  return await sql`
    select
      receipt.source_key,
      event.id::text as source_event_id,
      lower(event.event_type)::text as source_kind,
      r.id::text as relationship_id,
      r.patient_user_id::text as patient_user_id,
      profile.display_name as patient_display_name,
      coalesce(event.medication_name,event.title) as item_name,
      coalesce(event.dose_text,'') as dose_text,
      case
        when ((event.scheduled_local_date + event.scheduled_local_time)
              at time zone event.time_zone) < event.completed_at_utc
        then 'missed'
        else 'scheduled'
      end as previous_status,
      'completed'::text as resulting_status,
      'completed'::text as event_type,
      event.completed_at_utc as occurred_at_utc,
      event.updated_at_utc as recorded_at_utc,
      r.caregiver_lock_screen_detail
    from lifemate.caregiver_completion_notification_receipts receipt
    join lifemate.care_events event
      on event.id = receipt.source_care_event_id
     and receipt.source_key =
       'care-event:' || event.id::text || ':' || event.completed_at_utc::text
    join lifemate.care_relationships r
      on r.id = ${relationshipId}::uuid
     and r.id = receipt.relationship_id
     and r.patient_person_id = event.patient_person_id
     and r.caregiver_person_id = ${caregiverPersonId}::uuid
     and r.status = 'Active'
     and r.patient_consented_at_utc is not null
     and r.caregiver_consented_at_utc is not null
    join core.person_profiles profile on profile.person_id = event.patient_person_id
    where receipt.caregiver_person_id = ${caregiverPersonId}::uuid
      and event.status = 'Completed'
      and event.completed_at_utc is not null
    order by receipt.claimed_at_utc desc
    limit 50
  `;
}

function mapNotification(row: Row): Record<string, unknown> {
  return {
    sourceKey: row.source_key,
    sourceEventId: row.source_event_id,
    kind: row.source_kind,
    relationshipId: row.relationship_id,
    patientUserId: row.patient_user_id,
    patientDisplayName: row.patient_display_name ?? "LifeMate User",
    itemName: row.item_name ?? "Treatment",
    medicationName: row.source_kind === "medication" ? row.item_name : null,
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

function compareRecordedAt(
  left: Record<string, unknown>,
  right: Record<string, unknown>,
): number {
  return String(left.recordedAtUtc).localeCompare(String(right.recordedAtUtc));
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
