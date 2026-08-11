import { getLifeMateSql } from "./database_client.ts";
import { ApiError } from "./validation.ts";

type Row = Record<string, unknown>;

export function createAccountExportStore(databaseUrl: string) {
  const sql = getLifeMateSql(databaseUrl);

  async function resolveSelfPersonId(accountId: string): Promise<string> {
    const rows = await sql`
      select person_id
      from core.account_person_links
      where account_id=${accountId}::uuid
        and link_type='Self'
        and status='Active'
      order by created_at_utc, person_id
      limit 1
    `;
    const personId = rows[0]?.person_id;
    if (typeof personId !== "string") {
      throw new ApiError(
        409,
        "self_person_missing",
        "A self profile is required before exporting account data.",
      );
    }
    return personId;
  }

  async function exportAccount(accountId: string): Promise<Row> {
    const personId = await resolveSelfPersonId(accountId);

    // Keep every query explicitly scoped to the authenticated account or its
    // canonical self Person. Do not export internal auth subjects, contact
    // hashes/ciphertext, service credentials, audit implementation metadata, or
    // private data belonging only to a relationship counterpart.
    const account = await sql`
      select id, status, created_at_utc, updated_at_utc
      from lifemate.app_users
      where id=${accountId}::uuid
      limit 1
    `;
    const profile = await sql`
      select display_name, phone_number, email, locale, time_zone, avatar_key,
             version, created_at_utc, updated_at_utc
      from lifemate.user_profiles
      where user_id=${accountId}::uuid
      limit 1
    `;
    const externalIdentities = await sql`
      select provider, issuer, status, created_at_utc, last_authenticated_at_utc
      from identity.external_identities
      where account_id=${accountId}::uuid
      order by created_at_utc
    `;
    const medications = await sql`
      select id, name, strength_text, form, notes, version,
             provenance_source, created_at_utc, updated_at_utc
      from lifemate.medications
      where owner_person_id=${personId}::uuid
         or (owner_person_id is null and owner_user_id=${accountId}::uuid)
      order by created_at_utc, id
    `;
    const treatmentPlans = await sql`
      select id, medication_id, dose_text, instructions, start_date, end_date,
             time_zone, status, patient_reminder_minutes_before,
             caregiver_reminder_minutes_before, version, provenance_source,
             created_at_utc, updated_at_utc
      from lifemate.treatment_plans
      where patient_person_id=${personId}::uuid
         or (patient_person_id is null and patient_user_id=${accountId}::uuid)
      order by created_at_utc, id
    `;
    const treatmentSchedules = await sql`
      select s.id, s.treatment_plan_id, s.day_of_week, s.local_time,
             s.created_at_utc
      from lifemate.treatment_schedules s
      join lifemate.treatment_plans p on p.id=s.treatment_plan_id
      where p.patient_person_id=${personId}::uuid
         or (p.patient_person_id is null and p.patient_user_id=${accountId}::uuid)
      order by s.created_at_utc, s.id
    `;
    const doseOccurrences = await sql`
      select id, treatment_plan_id, treatment_schedule_id, scheduled_at_utc,
             scheduled_local_date, scheduled_local_time, time_zone, status,
             responded_at_utc, version, provenance_source,
             created_at_utc, updated_at_utc
      from lifemate.dose_occurrences
      where patient_person_id=${personId}::uuid
         or (patient_person_id is null and patient_user_id=${accountId}::uuid)
      order by scheduled_at_utc, id
    `;
    const careEvents = await sql`
      select id, event_type, title, provider_name, specialty, medication_name,
             dose_text, administration_route, reason, instructions, center_name,
             address_line, phone_number, scheduled_local_date,
             scheduled_local_time, time_zone, status, completed_at_utc,
             patient_reminder_minutes_before, caregiver_reminder_minutes_before,
             recurrence_unit, recurrence_interval, recurrence_weekdays,
             recurrence_end_date, version, provenance_source,
             created_at_utc, updated_at_utc
      from lifemate.care_events
      where patient_person_id=${personId}::uuid
         or (patient_person_id is null and patient_user_id=${accountId}::uuid)
      order by scheduled_local_date, scheduled_local_time, id
    `;
    const healthObservations = await sql`
      select h.id, h.observation_type, h.value_primary, h.value_secondary,
             h.unit_primary, h.unit_secondary, h.note, h.observed_at_utc,
             h.observed_local_date, h.time_zone, h.source_category,
             h.source_provider, a.code as source_application,
             h.version, h.created_at_utc, h.updated_at_utc
      from lifemate.health_observations h
      join ecosystem.applications a on a.id=h.source_application_id
      where h.person_id=${personId}::uuid
      order by h.observed_at_utc, h.id
    `;
    const womenProfiles = await sql`
      select enabled, last_period_start, cycle_length, period_length,
             reminders_enabled, algorithm_version, version,
             daily_check_in_date, daily_mood, daily_energy, daily_symptoms,
             daily_support_need, daily_private_note, share_daily_summary,
             created_at_utc, updated_at_utc
      from lifemate.women_calendar_profiles
      where owner_person_id=${personId}::uuid
         or (owner_person_id is null and owner_user_id=${accountId}::uuid)
      limit 1
    `;
    const womenEpisodes = await sql`
      select id, started_on, ended_on, private_notes, version,
             provenance_source, created_at_utc, updated_at_utc
      from lifemate.women_calendar_episodes
      where owner_person_id=${personId}::uuid
         or (owner_person_id is null and owner_user_id=${accountId}::uuid)
      order by started_on, id
    `;
    const womenDailyLogs = await sql`
      select id, logged_on, mood, energy_level, pain_level, symptoms,
             private_notes, share_summary_with_companion, version,
             provenance_source, created_at_utc, updated_at_utc
      from lifemate.women_calendar_daily_logs
      where owner_person_id=${personId}::uuid
         or (owner_person_id is null and owner_user_id=${accountId}::uuid)
      order by logged_on, id
    `;
    const relationships = await sql`
      select id,
             case when patient_user_id=${accountId}::uuid
                  then 'patient' else 'caregiver' end as own_role,
             status, patient_consent_version, patient_consented_at_utc,
             caregiver_consent_version, caregiver_consented_at_utc,
             revoked_at_utc, can_view_women_calendar,
             can_manage_health_record,
             health_record_management_consent_version,
             health_record_management_consented_at_utc,
             health_record_management_revoked_at_utc,
             created_at_utc, updated_at_utc
      from lifemate.care_relationships
      where patient_user_id=${accountId}::uuid
         or caregiver_user_id=${accountId}::uuid
      order by created_at_utc, id
    `;
    const privacyConsents = await sql`
      select document_type, document_version, granted_at_utc, revoked_at_utc,
             created_at_utc
      from lifemate.privacy_consents
      where user_id=${accountId}::uuid
      order by created_at_utc
    `;
    const consentRecords = await sql`
      select id, purpose, scope_key, data_categories, jurisdiction, source,
             status, granted_at_utc, revoked_at_utc, expires_at_utc,
             created_at_utc, updated_at_utc
      from consent.consent_records
      where subject_person_id=${personId}::uuid
         or actor_account_id=${accountId}::uuid
      order by created_at_utc, id
    `;
    const dataUseConsents = await sql`
      select id, purpose, data_categories, jurisdiction, policy_version, source,
             status, granted_at_utc, revoked_at_utc, expires_at_utc,
             created_at_utc, updated_at_utc
      from consent.data_use_consents
      where subject_person_id=${personId}::uuid
         or actor_account_id=${accountId}::uuid
      order by created_at_utc, id
    `;
    const deletionRequests = await sql`
      select id, status, requested_at_utc, processing_started_at_utc,
             completed_at_utc, retention_policy_version, reason_code
      from identity.account_deletion_requests
      where account_id=${accountId}::uuid
      order by requested_at_utc, id
    `;

    await sql`
      insert into lifemate.audit_logs(
        id, actor_user_id, action, resource_type, resource_id,
        metadata_json, created_at_utc)
      values(
        ${crypto.randomUUID()}::uuid,
        ${accountId}::uuid,
        'account.data_exported',
        'account',
        ${accountId}::uuid,
        ${JSON.stringify({ exportVersion: 1 })}::jsonb,
        now())
    `;

    return {
      exportVersion: 1,
      generatedAtUtc: new Date().toISOString(),
      dataSubject: { personId },
      account: account[0] ?? null,
      profile: profile[0] ?? null,
      externalIdentities,
      treatment: {
        medications,
        plans: treatmentPlans,
        schedules: treatmentSchedules,
        doseOccurrences,
        careEvents,
      },
      health: { observations: healthObservations },
      womenHealth: {
        profile: womenProfiles[0] ?? null,
        episodes: womenEpisodes,
        dailyLogs: womenDailyLogs,
      },
      care: { relationships },
      privacy: {
        legacyConsents: privacyConsents,
        consentRecords,
        dataUseConsents,
        accountDeletionRequests: deletionRequests,
      },
      exportNotes: [
        "Authentication secrets, access tokens, contact hashes/ciphertext and service-internal credentials are intentionally excluded.",
        "Relationship counterpart private profile fields are intentionally excluded; only the requesting user's relationship/consent state is included.",
      ],
    };
  }

  return { exportAccount };
}
