import { createContactPointReader } from "./contact_points.ts";
import { getLifeMateSql } from "./database_client.ts";
import { ApiError } from "./validation.ts";

type Row = Record<string, unknown>;

export const portableExportSchemaVersion = "lifemate-portable-export-v1";
export const portableExportRowLimit = 20_000;
export const portableExportMaximumBytes = 8 * 1024 * 1024;

export function createDataExportStore(databaseUrl: string) {
  const sql = getLifeMateSql(databaseUrl);
  const contactReader = createContactPointReader();

  async function exportAccountData(appUserId: string): Promise<Row> {
    const users = await sql`
      select id, status, created_at_utc, updated_at_utc
      from lifemate.app_users
      where id = ${appUserId}
      limit 1
    `;
    if (!users[0]) {
      throw new ApiError(404, "account_not_found", "Account was not found.");
    }

    // Keep the export sequential. The Edge runtime intentionally owns one
    // bounded SQL connection per isolate; a user-triggered export must not fan
    // out into parallel database work and steal capacity from critical writes.
    const accountRows = await sql`
      select id, status, home_region, created_at_utc, updated_at_utc
      from identity.accounts
      where legacy_app_user_id = ${appUserId}
      limit 1
    `;
    const accountId = typeof accountRows[0]?.id === "string"
      ? accountRows[0].id
      : null;

    // Healthcare ownership has crossed the canonical Account -> Self Person
    // boundary. Do not silently fall back to legacy owner-user columns when the
    // mapping is unavailable: an incomplete or mis-scoped privacy export is a
    // fail-closed condition. The canonical Person identifier is authorization
    // context only and is not added to the portable export payload.
    const personRows = await sql`
      select core.self_person_id_for_legacy_app_user(${appUserId}::uuid)::text
        as person_id
    `;
    const personId = typeof personRows[0]?.person_id === "string"
      ? personRows[0].person_id
      : null;
    if (!personId) {
      throw new ApiError(
        409,
        "identity_person_mapping_missing",
        "The LifeMate person mapping is unavailable.",
      );
    }

    const profiles = await bounded(
      "profile",
      sql`
        select display_name, phone_number, email, locale, time_zone, avatar_key,
               (profile_photo_path is not null) as has_profile_photo,
               version, created_at_utc, updated_at_utc
        from lifemate.user_profiles
        where user_id = ${appUserId}
        order by id
        limit ${portableExportRowLimit + 1}
      `,
    );
    if (profiles[0]) {
      const legacyPhone = stringOrNull(profiles[0].phone_number);
      const legacyEmail = stringOrNull(profiles[0].email);
      // Keep these reads sequential for the same single-connection invariant as
      // the rest of the portable export. `legacy` remains dependency-free;
      // protected prefer/contact-only modes reuse the exact Profile reader.
      profiles[0].phone_number = await contactReader.readForProfile(
        sql,
        appUserId,
        "Phone",
        legacyPhone,
      );
      profiles[0].email = await contactReader.readForProfile(
        sql,
        appUserId,
        "Email",
        legacyEmail,
      );
    }

    const contactPoints = accountId == null ? [] : await bounded(
      "contact_points",
      sql`
          select kind, status, verified_at_utc, created_at_utc, updated_at_utc
          from identity.contact_points
          where account_id = ${accountId}
          order by created_at_utc, id
          limit ${portableExportRowLimit + 1}
        `,
    );

    const externalIdentities = accountId == null ? [] : await bounded(
      "external_identities",
      sql`
          select provider, issuer, status, created_at_utc,
                 last_authenticated_at_utc
          from identity.external_identities
          where account_id = ${accountId}
          order by created_at_utc, id
          limit ${portableExportRowLimit + 1}
        `,
    );

    const enrollments = accountId == null ? [] : await bounded(
      "app_enrollments",
      sql`
          select a.code as application_code, a.display_name as application_name,
                 e.status, e.enrolled_at_utc, e.last_active_at_utc
          from ecosystem.app_enrollments e
          join ecosystem.applications a on a.id = e.application_id
          where e.account_id = ${accountId}
          order by e.enrolled_at_utc, e.id
          limit ${portableExportRowLimit + 1}
        `,
    );

    const deletionRequests = accountId == null ? [] : await bounded(
      "account_deletion_requests",
      sql`
          select status, requested_at_utc, processing_started_at_utc,
                 completed_at_utc, retention_policy_version, reason_code
          from identity.account_deletion_requests
          where account_id = ${accountId}
          order by requested_at_utc, id
          limit ${portableExportRowLimit + 1}
        `,
    );

    const medications = await bounded(
      "medications",
      sql`
        select id, name, strength_text, form, notes, version,
               provenance_source, provenance_restricted,
               created_at_utc, updated_at_utc
        from lifemate.medications
        where owner_person_id = ${personId}::uuid
        order by created_at_utc, id
        limit ${portableExportRowLimit + 1}
      `,
    );

    const treatmentPlans = await bounded(
      "treatment_plans",
      sql`
        select id, medication_id, dose_text, instructions, start_date, end_date,
               time_zone, status, patient_reminder_minutes_before,
               caregiver_reminder_minutes_before, version,
               provenance_source, provenance_restricted,
               created_at_utc, updated_at_utc
        from lifemate.treatment_plans
        where patient_person_id = ${personId}::uuid
        order by created_at_utc, id
        limit ${portableExportRowLimit + 1}
      `,
    );

    const treatmentSchedules = await bounded(
      "treatment_schedules",
      sql`
        select s.id, s.treatment_plan_id, s.day_of_week, s.local_time,
               s.created_at_utc
        from lifemate.treatment_schedules s
        join lifemate.treatment_plans p on p.id = s.treatment_plan_id
        where p.patient_person_id = ${personId}::uuid
        order by s.created_at_utc, s.id
        limit ${portableExportRowLimit + 1}
      `,
    );

    const doseOccurrences = await bounded(
      "dose_occurrences",
      sql`
        select id, treatment_plan_id, treatment_schedule_id, scheduled_at_utc,
               scheduled_local_date, scheduled_local_time, time_zone, status,
               responded_at_utc, version, provenance_source,
               provenance_restricted, created_at_utc, updated_at_utc
        from lifemate.dose_occurrences
        where patient_person_id = ${personId}::uuid
        order by scheduled_at_utc, id
        limit ${portableExportRowLimit + 1}
      `,
    );

    const adherenceEvents = await bounded(
      "dose_adherence_events",
      sql`
        select e.id, e.occurrence_id,
               (e.actor_user_id = ${appUserId}) as actor_was_self,
               e.event_type, e.previous_status, e.resulting_status,
               e.occurred_at_utc, e.recorded_at_utc,
               e.provenance_source, e.provenance_restricted
        from lifemate.dose_adherence_events e
        join lifemate.dose_occurrences o on o.id = e.occurrence_id
        where o.patient_person_id = ${personId}::uuid
        order by e.recorded_at_utc, e.id
        limit ${portableExportRowLimit + 1}
      `,
    );

    const careEvents = await bounded(
      "care_events",
      sql`
        select id, client_request_id, event_type, title, provider_name,
               specialty, medication_name, dose_text, administration_route,
               reason, instructions, center_name, address_line, phone_number,
               scheduled_local_date, scheduled_local_time, time_zone, status,
               completed_at_utc, version, patient_reminder_minutes_before,
               caregiver_reminder_minutes_before, recurrence_unit,
               recurrence_interval, recurrence_weekdays, recurrence_end_date,
               provenance_source, provenance_restricted,
               (created_by_user_id = ${appUserId}) as created_by_self,
               created_at_utc, updated_at_utc
        from lifemate.care_events
        where patient_person_id = ${personId}::uuid
        order by created_at_utc, id
        limit ${portableExportRowLimit + 1}
      `,
    );

    const healthObservations = await bounded(
      "health_observations",
      sql`
        select id, client_request_id, observation_type, value_primary,
               value_secondary, unit_primary, unit_secondary, note,
               observed_at_utc, observed_local_date, time_zone,
               source_category, source_provider, source_external_id,
               metadata_json, version, created_at_utc, updated_at_utc,
               case
                 when recorded_by_account_id is null then null
                 when ${accountId}::uuid is null then null
                 else recorded_by_account_id = ${accountId}::uuid
               end as recorded_by_self
        from lifemate.health_observations
        where person_id = ${personId}::uuid
        order by observed_at_utc, id
        limit ${portableExportRowLimit + 1}
      `,
    );

    const privacyConsents = await bounded(
      "privacy_consents",
      sql`
        select id, document_type, document_version, granted_at_utc,
               revoked_at_utc, created_at_utc
        from lifemate.privacy_consents
        where user_id = ${appUserId}
        order by created_at_utc, id
        limit ${portableExportRowLimit + 1}
      `,
    );

    const careRelationships = await bounded(
      "care_relationships",
      sql`
        select id,
               case when patient_person_id = ${personId}::uuid
                    then 'patient' else 'caregiver' end as self_role,
               status, patient_consent_version, patient_consented_at_utc,
               caregiver_consent_version, caregiver_consented_at_utc,
               can_view_women_calendar, can_manage_health_record,
               health_record_management_consent_version,
               health_record_management_consented_at_utc,
               health_record_management_revoked_at_utc,
               case when revoked_by_user_id is null then null
                    else revoked_by_user_id = ${appUserId} end as revoked_by_self,
               revoked_at_utc, created_at_utc, updated_at_utc
        from lifemate.care_relationships
        where patient_person_id = ${personId}::uuid
           or caregiver_person_id = ${personId}::uuid
        order by created_at_utc, id
        limit ${portableExportRowLimit + 1}
      `,
    );

    const careInvitations = await bounded(
      "care_invitations",
      sql`
        select id, contact_type, contact_hint, patient_consent_version,
               status, expires_at_utc, responded_at_utc, revoked_at_utc,
               created_at_utc
        from lifemate.care_invitations
        where inviter_user_id = ${appUserId}
        order by created_at_utc, id
        limit ${portableExportRowLimit + 1}
      `,
    );

    const womenCalendarProfiles = await bounded(
      "women_calendar_profiles",
      sql`
        select enabled, last_period_start, cycle_length, period_length,
               reminders_enabled, algorithm_version, version,
               daily_check_in_date, daily_mood, daily_energy, daily_symptoms,
               daily_support_need, daily_private_note, share_daily_summary,
               created_at_utc, updated_at_utc
        from lifemate.women_calendar_profiles
        where owner_person_id = ${personId}::uuid
        order by created_at_utc
        limit ${portableExportRowLimit + 1}
      `,
    );

    const womenCalendarEpisodes = await bounded(
      "women_calendar_episodes",
      sql`
        select id, started_on, ended_on, private_notes, version,
               provenance_source, provenance_restricted,
               created_at_utc, updated_at_utc
        from lifemate.women_calendar_episodes
        where owner_person_id = ${personId}::uuid
        order by started_on, id
        limit ${portableExportRowLimit + 1}
      `,
    );

    const womenCalendarDailyLogs = await bounded(
      "women_calendar_daily_logs",
      sql`
        select id, logged_on, mood, energy_level, pain_level, symptoms,
               private_notes, share_summary_with_companion, version,
               provenance_source, provenance_restricted,
               created_at_utc, updated_at_utc
        from lifemate.women_calendar_daily_logs
        where owner_person_id = ${personId}::uuid
        order by logged_on, id
        limit ${portableExportRowLimit + 1}
      `,
    );

    // A support action is meaningful to the patient, but the caregiver's raw
    // user/relationship identifiers belong to another person and are omitted.
    const womenCalendarSupportActionsReceived = await bounded(
      "women_calendar_support_actions_received",
      sql`
        select id, action_type, performed_at_utc, created_at_utc
        from lifemate.women_calendar_support_actions
        where patient_person_id = ${personId}::uuid
        order by performed_at_utc, id
        limit ${portableExportRowLimit + 1}
      `,
    );

    const payload: Row = {
      schemaVersion: portableExportSchemaVersion,
      generatedAtUtc: new Date().toISOString(),
      scope: "authenticated-self-service",
      account: portableRows(users)[0],
      identity: {
        account: accountRows[0] ? portableRow(accountRows[0]) : null,
        contactPoints: portableRows(contactPoints),
        externalIdentities: portableRows(externalIdentities),
        appEnrollments: portableRows(enrollments),
        deletionRequests: portableRows(deletionRequests),
      },
      profile: portableRows(profiles)[0] ?? null,
      healthcare: {
        medications: portableRows(medications),
        treatmentPlans: portableRows(treatmentPlans),
        treatmentSchedules: portableRows(treatmentSchedules),
        doseOccurrences: portableRows(doseOccurrences),
        doseAdherenceEvents: portableRows(adherenceEvents),
        careEvents: portableRows(careEvents),
        healthObservations: portableRows(healthObservations),
      },
      careAndConsent: {
        privacyConsents: portableRows(privacyConsents),
        relationships: portableRows(careRelationships),
        invitationsCreatedBySelf: portableRows(careInvitations),
      },
      womenCalendar: {
        profiles: portableRows(womenCalendarProfiles),
        episodes: portableRows(womenCalendarEpisodes),
        dailyLogs: portableRows(womenCalendarDailyLogs),
        supportActionsReceived: portableRows(
          womenCalendarSupportActionsReceived,
        ),
      },
      exclusions: [
        "raw authentication/provider subjects",
        "encrypted contact values and contact hashes",
        "invitation token/contact hashes",
        "raw identifiers belonging to linked people",
        "internal audit/security logs",
        "idempotency keys and outbox transport records",
      ],
    };
    assertPortableExportSize(payload);
    return payload;
  }

  return { exportAccountData };
}

async function bounded(
  label: string,
  rowsPromise: PromiseLike<Row[]>,
): Promise<Row[]> {
  const rows = await rowsPromise;
  if (rows.length > portableExportRowLimit) {
    throw new ApiError(
      413,
      "data_export_too_large",
      `The ${label} dataset is too large for the self-service export path.`,
    );
  }
  return rows;
}

export function assertPortableExportSize(payload: unknown): void {
  const size = new TextEncoder().encode(JSON.stringify(payload)).byteLength;
  if (size > portableExportMaximumBytes) {
    throw new ApiError(
      413,
      "data_export_too_large",
      "The account export is too large for the self-service export path.",
    );
  }
}

export function portableRows(rows: Row[]): Row[] {
  return rows.map(portableRow);
}

export function portableRow(row: Row): Row {
  return Object.fromEntries(
    Object.entries(row).map(([key, value]) => [camelCase(key), value]),
  );
}

function stringOrNull(value: unknown): string | null {
  return typeof value === "string" && value.length > 0 ? value : null;
}

function camelCase(value: string): string {
  return value.replace(
    /_([a-z])/g,
    (_, letter: string) => letter.toUpperCase(),
  );
}
