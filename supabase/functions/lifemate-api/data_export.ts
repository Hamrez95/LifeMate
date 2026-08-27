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
               presentation_intent, onboarding_completed_at_utc,
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
        select o.id, o.treatment_plan_id, o.scheduled_at_utc, o.status,
               o.occurred_at_utc, o.version, o.created_at_utc, o.updated_at_utc
        from lifemate.dose_occurrences o
        join lifemate.treatment_plans p on p.id = o.treatment_plan_id
        where p.patient_person_id = ${personId}::uuid
        order by o.scheduled_at_utc, o.id
        limit ${portableExportRowLimit + 1}
      `,
    );

    const careEvents = await bounded(
      "care_events",
      sql`
        select id, event_type, title, provider_name, specialty,
               medication_name, dose_text, administration_route, reason,
               instructions, center_name, address_line, phone_number,
               scheduled_local_date, scheduled_local_time, time_zone, status,
               patient_reminder_minutes_before,
               caregiver_reminder_minutes_before, version,
               provenance_source, provenance_restricted,
               created_at_utc, updated_at_utc
        from lifemate.care_events
        where owner_person_id = ${personId}::uuid
        order by scheduled_local_date, scheduled_local_time, id
        limit ${portableExportRowLimit + 1}
      `,
    );

    const careRelationships = await bounded(
      "care_relationships",
      sql`
        select relationship_type, status, consent_version, created_at_utc,
               updated_at_utc, revoked_at_utc
        from lifemate.care_relationships
        where patient_person_id = ${personId}::uuid
           or caregiver_person_id = ${personId}::uuid
        order by created_at_utc, id
        limit ${portableExportRowLimit + 1}
      `,
    );

    const womenCycles = await bounded(
      "women_cycles",
      sql`
        select id, cycle_start_date, cycle_length_days, period_length_days,
               created_at_utc, updated_at_utc
        from lifemate.women_cycles
        where owner_person_id = ${personId}::uuid
        order by cycle_start_date, id
        limit ${portableExportRowLimit + 1}
      `,
    );

    const womenDailyLogs = await bounded(
      "women_daily_logs",
      sql`
        select id, local_date, flow_level, symptoms, mood, notes,
               share_summary_with_companion, created_at_utc, updated_at_utc
        from lifemate.women_daily_logs
        where owner_person_id = ${personId}::uuid
        order by local_date, id
        limit ${portableExportRowLimit + 1}
      `,
    );

    const exportData: Row = {
      schemaVersion: portableExportSchemaVersion,
      exportedAtUtc: new Date().toISOString(),
      account: users[0],
      profile: profiles[0] ?? null,
      contactPoints,
      externalIdentities,
      appEnrollments: enrollments,
      accountDeletionRequests: deletionRequests,
      medications,
      treatmentPlans,
      treatmentSchedules,
      doseOccurrences,
      careEvents,
      careRelationships,
      womenCycles,
      womenDailyLogs,
    };

    const encoded = new TextEncoder().encode(JSON.stringify(exportData));
    if (encoded.byteLength > portableExportMaximumBytes) {
      throw new ApiError(
        413,
        "data_export_too_large",
        "Account data export exceeds the portable export size limit.",
      );
    }
    return exportData;
  }

  return { exportAccountData };
}

async function bounded(
  label: string,
  promise: Promise<Row[]>,
): Promise<Row[]> {
  const rows = await promise;
  if (rows.length > portableExportRowLimit) {
    throw new ApiError(
      413,
      "data_export_too_large",
      `${label} exceeds the portable export row limit.`,
    );
  }
  return rows;
}

function stringOrNull(value: unknown): string | null {
  return typeof value === "string" && value.length > 0 ? value : null;
}
