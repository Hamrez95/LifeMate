import { getLifeMateSql } from "./database_client.ts";
import { ApiError } from "./validation.ts";

type Row = Record<string, unknown>;

const exportRowLimit = 5_000;

async function requireSelfPerson(
  connection: any,
  appUserId: string,
): Promise<string> {
  const rows = await connection`
    select core.self_person_id_for_legacy_app_user(${appUserId}::uuid)::text as person_id
  `;
  const personId = rows[0]?.person_id;
  if (typeof personId !== "string" || personId.length === 0) {
    throw new ApiError(
      409,
      "identity_person_mapping_missing",
      "Person mapping is unavailable.",
    );
  }
  return personId;
}

function boundedRows(rows: Row[], name: string): Row[] {
  if (rows.length > exportRowLimit) {
    throw new ApiError(
      413,
      "schedule_export_too_large",
      `${name} exceeds the medication schedule export limit.`,
    );
  }
  return rows;
}

export function createMedicationScheduleExportStore(databaseUrl: string) {
  const sql = getLifeMateSql(databaseUrl);

  async function exportOptimizationHistory(
    appUserId: string,
  ): Promise<Record<string, unknown>> {
    const ownerPersonId = await requireSelfPerson(sql, appUserId);

    const nearbyProposals = boundedRows(
      await sql`
        select id, algorithm_version, status,
               expected_notification_reduction,
               expires_at_utc, confirmed_at_utc, applied_at_utc,
               undone_at_utc, created_at_utc, updated_at_utc
        from lifemate.medication_schedule_optimization_proposals
        where owner_person_id=${ownerPersonId}::uuid
        order by created_at_utc,id
        limit ${exportRowLimit + 1}
      `,
      "nearby proposals",
    );

    const nearbyChanges = boundedRows(
      await sql`
        select proposal_id,treatment_plan_id,
               old_anchor_local_time,new_anchor_local_time,
               interval_hours,expected_treatment_plan_version,
               expected_timing_version,applied_treatment_plan_version,
               shift_minutes,created_at_utc
        from lifemate.medication_schedule_optimization_plan_changes
        where owner_person_id=${ownerPersonId}::uuid
        order by created_at_utc,proposal_id,treatment_plan_id
        limit ${exportRowLimit + 1}
      `,
      "nearby changes",
    );

    const optimizationRuns = boundedRows(
      await sql`
        select id,mode,algorithm_version,consent_text_version,
               schedule_preferences_version,sleep_window_enabled,
               max_variation_minutes,effective_from_local_date,
               effective_until_local_date,status,expires_at_utc,
               confirmed_at_utc,applied_at_utc,undone_at_utc,
               created_at_utc,updated_at_utc
        from lifemate.medication_schedule_optimization_runs
        where owner_person_id=${ownerPersonId}::uuid
        order by created_at_utc,id
        limit ${exportRowLimit + 1}
      `,
      "optimization runs",
    );

    const optimizationChanges = boundedRows(
      await sql`
        select id,run_id,treatment_plan_id,
               expected_treatment_plan_version,expected_timing_version,
               entered_interval_minutes,old_anchor_local_time,
               proposed_anchor_local_time,reason,created_at_utc
        from lifemate.medication_schedule_optimization_changes
        where owner_person_id=${ownerPersonId}::uuid
        order by created_at_utc,run_id,treatment_plan_id
        limit ${exportRowLimit + 1}
      `,
      "optimization changes",
    );

    const occurrenceOverrides = boundedRows(
      await sql`
        select id,run_id,change_id,treatment_plan_id,
               original_local_date,original_local_time,
               replacement_local_date,replacement_local_time,time_zone,
               entered_interval_minutes,actual_gap_minutes,variation_minutes,
               status,created_at_utc,updated_at_utc
        from lifemate.dose_occurrence_overrides
        where owner_person_id=${ownerPersonId}::uuid
        order by created_at_utc,run_id,treatment_plan_id,id
        limit ${exportRowLimit + 1}
      `,
      "occurrence overrides",
    );

    return {
      nearbyProposals,
      nearbyChanges,
      optimizationRuns,
      optimizationChanges,
      occurrenceOverrides,
      exclusions: [
        "sleep-window snapshot hashes",
        "idempotency hashes",
        "raw audit/security logs",
        "rendered notification copy",
      ],
    };
  }

  return { exportOptimizationHistory };
}
