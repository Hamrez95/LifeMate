import postgres from "npm:postgres@3.4.7";

type Operation = "readiness" | "scrub" | "rehydrate";
type Mode = "dry-run" | "apply";
type Dataset = "treatment_plans" | "dose_occurrences";

type RetirementRow = {
  dataset: Dataset;
  id: string;
  patient_person_id: string;
  patient_user_id: string | null;
};

type MappingRow = {
  account_id: string;
  legacy_app_user_id: string;
};

export type TreatmentDoseOwnerReadiness = {
  treatmentPlans: number;
  doseOccurrences: number;
  totalRows: number;
  mappedRows: number;
  missingMappings: number;
  ambiguousMappings: number;
  linkedRows: number;
  retiredRows: number;
  mismatchedLegacyOwners: number;
  dosePlanPersonMismatches: number;
  ready: boolean;
};

export type TreatmentDoseOwnerRetirementSummary = {
  operation: Operation;
  mode: Mode;
  maxRows: number;
  readiness: TreatmentDoseOwnerReadiness;
  scannedRows: number;
  changedRows: number;
  hasMore: boolean;
};

const uuidPattern =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

function requireOperation(value: string): Operation {
  if (value === "readiness" || value === "scrub" || value === "rehydrate") {
    return value;
  }
  throw new Error(
    "Treatment/Dose owner operation must be readiness, scrub or rehydrate.",
  );
}

function requireMode(value: string): Mode {
  if (value === "dry-run" || value === "apply") return value;
  throw new Error("Treatment/Dose owner mode must be dry-run or apply.");
}

function requireMaxRows(value: number): number {
  if (!Number.isSafeInteger(value) || value < 1 || value > 2000) {
    throw new Error(
      "Treatment/Dose owner maxRows must be an integer from 1 to 2000.",
    );
  }
  return value;
}

function integer(value: unknown): number {
  const parsed = Number(value);
  if (!Number.isSafeInteger(parsed) || parsed < 0) {
    throw new Error("Treatment/Dose readiness returned an invalid count.");
  }
  return parsed;
}

function assertUuid(label: string, value: unknown): string {
  if (typeof value !== "string" || !uuidPattern.test(value)) {
    throw new Error(`Treatment/Dose ${label} is not a UUID.`);
  }
  return value.toLowerCase();
}

function dataset(value: unknown): Dataset {
  if (value === "treatment_plans" || value === "dose_occurrences") {
    return value;
  }
  throw new Error("Treatment/Dose retirement returned an unknown dataset.");
}

async function inspectReadiness(
  sql: ReturnType<typeof postgres>,
): Promise<TreatmentDoseOwnerReadiness> {
  const rows = await sql`
    with active_self as (
      select
        l.person_id,
        count(distinct a.id)::integer as mapping_count,
        max(a.legacy_app_user_id::text)::uuid as mapped_app_user_id
      from core.account_person_links l
      join identity.accounts a
        on a.id=l.account_id
       and a.status='Active'
       and a.legacy_app_user_id is not null
      join lifemate.app_users u
        on u.id=a.legacy_app_user_id
       and u.status='Active'
      where l.link_type='Self'
        and l.status='Active'
      group by l.person_id
    ), healthcare_rows as (
      select
        'treatment_plans'::text as dataset,
        p.id,
        p.patient_person_id,
        p.patient_user_id
      from lifemate.treatment_plans p
      union all
      select
        'dose_occurrences'::text,
        d.id,
        d.patient_person_id,
        d.patient_user_id
      from lifemate.dose_occurrences d
    ), row_mapping as (
      select
        r.*,
        coalesce(s.mapping_count,0)::integer as mapping_count,
        s.mapped_app_user_id
      from healthcare_rows r
      left join active_self s on s.person_id=r.patient_person_id
    ), dose_plan_mismatch as (
      select count(*)::integer as count
      from lifemate.dose_occurrences d
      join lifemate.treatment_plans p on p.id=d.treatment_plan_id
      where d.patient_person_id is distinct from p.patient_person_id
    )
    select
      count(*) filter (where dataset='treatment_plans')::integer
        as treatment_plans,
      count(*) filter (where dataset='dose_occurrences')::integer
        as dose_occurrences,
      count(*)::integer as total_rows,
      count(*) filter (where mapping_count=1)::integer as mapped_rows,
      count(*) filter (where mapping_count=0)::integer as missing_mappings,
      count(*) filter (where mapping_count>1)::integer as ambiguous_mappings,
      count(*) filter (where patient_user_id is not null)::integer as linked_rows,
      count(*) filter (where patient_user_id is null)::integer as retired_rows,
      count(*) filter (
        where patient_user_id is not null
          and mapping_count=1
          and patient_user_id is distinct from mapped_app_user_id
      )::integer as mismatched_legacy_owners,
      (select count from dose_plan_mismatch)::integer
        as dose_plan_person_mismatches
    from row_mapping
  `;
  const row = rows[0] ?? {};
  const readiness: TreatmentDoseOwnerReadiness = {
    treatmentPlans: integer(row.treatment_plans ?? 0),
    doseOccurrences: integer(row.dose_occurrences ?? 0),
    totalRows: integer(row.total_rows ?? 0),
    mappedRows: integer(row.mapped_rows ?? 0),
    missingMappings: integer(row.missing_mappings ?? 0),
    ambiguousMappings: integer(row.ambiguous_mappings ?? 0),
    linkedRows: integer(row.linked_rows ?? 0),
    retiredRows: integer(row.retired_rows ?? 0),
    mismatchedLegacyOwners: integer(row.mismatched_legacy_owners ?? 0),
    dosePlanPersonMismatches: integer(row.dose_plan_person_mismatches ?? 0),
    ready: false,
  };
  readiness.ready = readiness.totalRows > 0 &&
    readiness.mappedRows === readiness.totalRows &&
    readiness.missingMappings === 0 &&
    readiness.ambiguousMappings === 0 &&
    readiness.mismatchedLegacyOwners === 0 &&
    readiness.dosePlanPersonMismatches === 0;
  return readiness;
}

function requireReady(readiness: TreatmentDoseOwnerReadiness): void {
  if (readiness.totalRows === 0) {
    throw new Error("treatment_dose_owner_retirement_readiness_vacuous");
  }
  if (readiness.missingMappings > 0) {
    throw new Error("treatment_dose_owner_retirement_mapping_missing");
  }
  if (readiness.ambiguousMappings > 0) {
    throw new Error("treatment_dose_owner_retirement_mapping_ambiguous");
  }
  if (readiness.mismatchedLegacyOwners > 0) {
    throw new Error("treatment_dose_owner_retirement_mapping_mismatch");
  }
  if (readiness.dosePlanPersonMismatches > 0) {
    throw new Error("treatment_dose_owner_retirement_dose_plan_mismatch");
  }
  if (!readiness.ready) {
    throw new Error("treatment_dose_owner_retirement_not_ready");
  }
}

async function uniqueActiveMapping(
  connection: any,
  personId: string,
): Promise<MappingRow> {
  const rows = await connection`
    select distinct
      a.id::text as account_id,
      a.legacy_app_user_id::text as legacy_app_user_id
    from core.account_person_links l
    join identity.accounts a
      on a.id=l.account_id
     and a.status='Active'
     and a.legacy_app_user_id is not null
    join lifemate.app_users u
      on u.id=a.legacy_app_user_id
     and u.status='Active'
    where l.person_id=${personId}::uuid
      and l.link_type='Self'
      and l.status='Active'
    order by account_id
  `;
  if (rows.length !== 1) {
    throw new Error("treatment_dose_owner_retirement_mapping_changed");
  }
  return {
    account_id: assertUuid("Account mapping", rows[0].account_id),
    legacy_app_user_id: assertUuid(
      "AppUser mapping",
      rows[0].legacy_app_user_id,
    ),
  };
}

async function selectRows(
  sql: ReturnType<typeof postgres>,
  linked: boolean,
  maxRows: number,
): Promise<{ batch: RetirementRow[]; hasMore: boolean }> {
  const rows = linked
    ? await sql`
      select dataset,id,patient_person_id,patient_user_id
      from (
        select 'treatment_plans'::text as dataset,id,patient_person_id,patient_user_id
        from lifemate.treatment_plans
        where patient_user_id is not null
        union all
        select 'dose_occurrences'::text,id,patient_person_id,patient_user_id
        from lifemate.dose_occurrences
        where patient_user_id is not null
      ) candidates
      order by dataset,id
      limit ${maxRows + 1}
    `
    : await sql`
      select dataset,id,patient_person_id,patient_user_id
      from (
        select 'treatment_plans'::text as dataset,id,patient_person_id,patient_user_id
        from lifemate.treatment_plans
        where patient_user_id is null
        union all
        select 'dose_occurrences'::text,id,patient_person_id,patient_user_id
        from lifemate.dose_occurrences
        where patient_user_id is null
      ) candidates
      order by dataset,id
      limit ${maxRows + 1}
    `;
  const hasMore = rows.length > maxRows;
  const batch = rows.slice(0, maxRows).map((row) => ({
    dataset: dataset(row.dataset),
    id: assertUuid("row id", row.id),
    patient_person_id: assertUuid("Person", row.patient_person_id),
    patient_user_id: row.patient_user_id == null
      ? null
      : assertUuid("legacy AppUser", row.patient_user_id),
  }));
  return { batch, hasMore };
}

async function scrubBatch(
  sql: ReturnType<typeof postgres>,
  mode: Mode,
  maxRows: number,
  confirmation: string | null | undefined,
): Promise<{ scanned: number; changed: number; hasMore: boolean }> {
  if (mode === "apply" && confirmation !== "SCRUB-TREATMENT-DOSE-OWNERS") {
    throw new Error(
      "Scrub apply mode requires confirmation SCRUB-TREATMENT-DOSE-OWNERS.",
    );
  }
  const selected = await selectRows(sql, true, maxRows);
  if (mode === "dry-run") {
    return {
      scanned: selected.batch.length,
      changed: 0,
      hasMore: selected.hasMore,
    };
  }

  let changed = 0;
  await sql.begin(async (transaction) => {
    for (const row of selected.batch) {
      if (!row.patient_user_id) {
        throw new Error("treatment_dose_owner_retirement_scrub_state_changed");
      }
      const mapping = await uniqueActiveMapping(
        transaction,
        row.patient_person_id,
      );
      if (mapping.legacy_app_user_id !== row.patient_user_id) {
        throw new Error("treatment_dose_owner_retirement_mapping_changed");
      }
      const updated = row.dataset === "treatment_plans"
        ? await transaction`
          update lifemate.treatment_plans
          set patient_user_id=null
          where id=${row.id}::uuid
            and patient_person_id=${row.patient_person_id}::uuid
            and patient_user_id=${row.patient_user_id}::uuid
          returning id::text as id
        `
        : await transaction`
          update lifemate.dose_occurrences
          set patient_user_id=null
          where id=${row.id}::uuid
            and patient_person_id=${row.patient_person_id}::uuid
            and patient_user_id=${row.patient_user_id}::uuid
          returning id::text as id
        `;
      if (updated.length !== 1 || updated[0]?.id !== row.id) {
        throw new Error("treatment_dose_owner_retirement_scrub_conflict");
      }
      changed += 1;
    }
  });
  return { scanned: selected.batch.length, changed, hasMore: selected.hasMore };
}

async function rehydrateBatch(
  sql: ReturnType<typeof postgres>,
  mode: Mode,
  maxRows: number,
  confirmation: string | null | undefined,
): Promise<{ scanned: number; changed: number; hasMore: boolean }> {
  if (
    mode === "apply" &&
    confirmation !== "REHYDRATE-TREATMENT-DOSE-OWNERS"
  ) {
    throw new Error(
      "Rehydrate apply mode requires confirmation REHYDRATE-TREATMENT-DOSE-OWNERS.",
    );
  }
  const selected = await selectRows(sql, false, maxRows);
  if (mode === "dry-run") {
    return {
      scanned: selected.batch.length,
      changed: 0,
      hasMore: selected.hasMore,
    };
  }

  let changed = 0;
  await sql.begin(async (transaction) => {
    for (const row of selected.batch) {
      const mapping = await uniqueActiveMapping(
        transaction,
        row.patient_person_id,
      );
      const updated = row.dataset === "treatment_plans"
        ? await transaction`
          update lifemate.treatment_plans
          set patient_user_id=${mapping.legacy_app_user_id}::uuid
          where id=${row.id}::uuid
            and patient_person_id=${row.patient_person_id}::uuid
            and patient_user_id is null
          returning id::text as id
        `
        : await transaction`
          update lifemate.dose_occurrences
          set patient_user_id=${mapping.legacy_app_user_id}::uuid
          where id=${row.id}::uuid
            and patient_person_id=${row.patient_person_id}::uuid
            and patient_user_id is null
          returning id::text as id
        `;
      if (updated.length !== 1 || updated[0]?.id !== row.id) {
        throw new Error("treatment_dose_owner_retirement_rehydrate_conflict");
      }
      changed += 1;
    }
  });
  return { scanned: selected.batch.length, changed, hasMore: selected.hasMore };
}

export async function runTreatmentDoseOwnerRetirement(options: {
  databaseUrl: string;
  operation: Operation;
  mode: Mode;
  maxRows: number;
  confirmation?: string | null;
}): Promise<TreatmentDoseOwnerRetirementSummary> {
  const databaseUrl = options.databaseUrl.trim();
  if (!databaseUrl) throw new Error("Database URL is required.");
  const operation = requireOperation(options.operation);
  const mode = requireMode(options.mode);
  const maxRows = requireMaxRows(options.maxRows);
  if (operation === "readiness" && mode !== "dry-run") {
    throw new Error("Readiness operation is dry-run only.");
  }

  const sql = postgres(databaseUrl, {
    max: 1,
    prepare: false,
    idle_timeout: 5,
    connect_timeout: 5,
  });
  try {
    const readiness = await inspectReadiness(sql);
    requireReady(readiness);
    if (operation === "readiness") {
      return {
        operation,
        mode,
        maxRows,
        readiness,
        scannedRows: 0,
        changedRows: 0,
        hasMore: false,
      };
    }
    const result = operation === "scrub"
      ? await scrubBatch(sql, mode, maxRows, options.confirmation)
      : await rehydrateBatch(sql, mode, maxRows, options.confirmation);
    return {
      operation,
      mode,
      maxRows,
      readiness,
      scannedRows: result.scanned,
      changedRows: result.changed,
      hasMore: result.hasMore,
    };
  } finally {
    await sql.end({ timeout: 2 });
  }
}

if (import.meta.main) {
  const operation = requireOperation(
    (Deno.env.get("LIFEMATE_TREATMENT_DOSE_OWNER_OPERATION") ?? "readiness")
      .trim()
      .toLowerCase(),
  );
  const mode = requireMode(
    (Deno.env.get("LIFEMATE_TREATMENT_DOSE_OWNER_MODE") ?? "dry-run")
      .trim()
      .toLowerCase(),
  );
  const summary = await runTreatmentDoseOwnerRetirement({
    databaseUrl: Deno.env.get("LIFEMATE_IDENTITY_MIGRATION_DATABASE_URL") ?? "",
    operation,
    mode,
    maxRows: Number(
      Deno.env.get("LIFEMATE_TREATMENT_DOSE_OWNER_MAX_ROWS") ?? "250",
    ),
    confirmation: Deno.env.get("LIFEMATE_TREATMENT_DOSE_OWNER_CONFIRM"),
  });
  console.log(JSON.stringify(summary));
}
