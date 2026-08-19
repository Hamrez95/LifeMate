import postgres from "npm:postgres@3.4.7";

type Operation = "readiness" | "scrub" | "rehydrate";
type Mode = "dry-run" | "apply";

type MappingRow = {
  account_id: string;
  legacy_app_user_id: string;
};

type ProfileOwnerRow = {
  owner_person_id: string;
  owner_user_id: string;
};

export type WomenProfileOwnerReadiness = {
  totalProfiles: number;
  mappedProfiles: number;
  missingMappings: number;
  ambiguousMappings: number;
  linkedProfiles: number;
  retiredProfiles: number;
  mismatchedLegacyOwners: number;
  rehydrateConflicts: number;
  ready: boolean;
};

export type WomenProfileOwnerRetirementSummary = {
  operation: Operation;
  mode: Mode;
  maxProfiles: number;
  readiness: WomenProfileOwnerReadiness;
  scannedProfiles: number;
  changedProfiles: number;
  hasMore: boolean;
};

const uuidPattern =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

function requireOperation(value: string): Operation {
  if (value === "readiness" || value === "scrub" || value === "rehydrate") {
    return value;
  }
  throw new Error(
    "Women profile owner operation must be readiness, scrub or rehydrate.",
  );
}

function requireMode(value: string): Mode {
  if (value === "dry-run" || value === "apply") return value;
  throw new Error("Women profile owner mode must be dry-run or apply.");
}

function requireMaxProfiles(value: number): number {
  if (!Number.isSafeInteger(value) || value < 1 || value > 1000) {
    throw new Error(
      "Women profile owner maxProfiles must be an integer from 1 to 1000.",
    );
  }
  return value;
}

function integer(value: unknown): number {
  const parsed = Number(value);
  if (!Number.isSafeInteger(parsed) || parsed < 0) {
    throw new Error("Women profile owner readiness returned an invalid count.");
  }
  return parsed;
}

function assertUuid(label: string, value: unknown): string {
  if (typeof value !== "string" || !uuidPattern.test(value)) {
    throw new Error(`Women profile owner ${label} is not a UUID.`);
  }
  return value.toLowerCase();
}

async function inspectReadiness(
  sql: ReturnType<typeof postgres>,
): Promise<WomenProfileOwnerReadiness> {
  const rows = await sql`
    with active_self as (
      select
        l.person_id,
        a.id as account_id,
        a.legacy_app_user_id
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
    ), profile_mapping as (
      select
        p.owner_person_id,
        p.owner_user_id,
        count(distinct s.account_id)::integer as mapping_count,
        max(s.legacy_app_user_id::text)::uuid as mapped_app_user_id
      from lifemate.women_calendar_profiles p
      left join active_self s on s.person_id=p.owner_person_id
      group by p.owner_person_id,p.owner_user_id
    )
    select
      count(*)::integer as total_profiles,
      count(*) filter (where mapping_count=1)::integer as mapped_profiles,
      count(*) filter (where mapping_count=0)::integer as missing_mappings,
      count(*) filter (where mapping_count>1)::integer as ambiguous_mappings,
      count(*) filter (where owner_user_id is not null)::integer as linked_profiles,
      count(*) filter (where owner_user_id is null)::integer as retired_profiles,
      count(*) filter (
        where owner_user_id is not null
          and mapping_count=1
          and owner_user_id is distinct from mapped_app_user_id
      )::integer as mismatched_legacy_owners,
      count(*) filter (
        where owner_user_id is null
          and mapping_count=1
          and exists (
            select 1
            from lifemate.women_calendar_profiles other
            where other.owner_person_id <> profile_mapping.owner_person_id
              and other.owner_user_id=profile_mapping.mapped_app_user_id
          )
      )::integer as rehydrate_conflicts
    from profile_mapping
  `;
  const row = rows[0] ?? {};
  const readiness: WomenProfileOwnerReadiness = {
    totalProfiles: integer(row.total_profiles ?? 0),
    mappedProfiles: integer(row.mapped_profiles ?? 0),
    missingMappings: integer(row.missing_mappings ?? 0),
    ambiguousMappings: integer(row.ambiguous_mappings ?? 0),
    linkedProfiles: integer(row.linked_profiles ?? 0),
    retiredProfiles: integer(row.retired_profiles ?? 0),
    mismatchedLegacyOwners: integer(row.mismatched_legacy_owners ?? 0),
    rehydrateConflicts: integer(row.rehydrate_conflicts ?? 0),
    ready: false,
  };
  readiness.ready =
    readiness.totalProfiles > 0 &&
    readiness.mappedProfiles === readiness.totalProfiles &&
    readiness.missingMappings === 0 &&
    readiness.ambiguousMappings === 0 &&
    readiness.mismatchedLegacyOwners === 0 &&
    readiness.rehydrateConflicts === 0;
  return readiness;
}

function requireReady(readiness: WomenProfileOwnerReadiness): void {
  if (readiness.totalProfiles === 0) {
    throw new Error("women_profile_owner_retirement_readiness_vacuous");
  }
  if (readiness.missingMappings > 0) {
    throw new Error("women_profile_owner_retirement_mapping_missing");
  }
  if (readiness.ambiguousMappings > 0) {
    throw new Error("women_profile_owner_retirement_mapping_ambiguous");
  }
  if (readiness.mismatchedLegacyOwners > 0) {
    throw new Error("women_profile_owner_retirement_mapping_mismatch");
  }
  if (readiness.rehydrateConflicts > 0) {
    throw new Error("women_profile_owner_retirement_rehydrate_conflict");
  }
  if (!readiness.ready) {
    throw new Error("women_profile_owner_retirement_not_ready");
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
    throw new Error("women_profile_owner_retirement_mapping_changed");
  }
  return {
    account_id: assertUuid("Account mapping", rows[0].account_id),
    legacy_app_user_id: assertUuid(
      "AppUser mapping",
      rows[0].legacy_app_user_id,
    ),
  };
}

async function scrubBatch(
  sql: ReturnType<typeof postgres>,
  mode: Mode,
  maxProfiles: number,
  confirmation: string | null | undefined,
): Promise<{ scanned: number; changed: number; hasMore: boolean }> {
  if (mode === "apply" && confirmation !== "SCRUB-WOMEN-PROFILE-OWNERS") {
    throw new Error(
      "Scrub apply mode requires confirmation SCRUB-WOMEN-PROFILE-OWNERS.",
    );
  }

  const rows = await sql<ProfileOwnerRow[]>`
    select
      owner_person_id::text as owner_person_id,
      owner_user_id::text as owner_user_id
    from lifemate.women_calendar_profiles
    where owner_user_id is not null
    order by owner_person_id
    limit ${maxProfiles + 1}
  `;
  const hasMore = rows.length > maxProfiles;
  const batch = rows.slice(0, maxProfiles).map((row) => ({
    owner_person_id: assertUuid("Person", row.owner_person_id),
    owner_user_id: assertUuid("legacy AppUser", row.owner_user_id),
  }));
  if (mode === "dry-run") {
    return { scanned: batch.length, changed: 0, hasMore };
  }

  let changed = 0;
  await sql.begin(async (transaction) => {
    for (const row of batch) {
      const mapping = await uniqueActiveMapping(
        transaction,
        row.owner_person_id,
      );
      if (mapping.legacy_app_user_id !== row.owner_user_id) {
        throw new Error("women_profile_owner_retirement_mapping_changed");
      }
      const updated = await transaction`
        update lifemate.women_calendar_profiles
        set owner_user_id=null
        where owner_person_id=${row.owner_person_id}::uuid
          and owner_user_id=${row.owner_user_id}::uuid
        returning owner_person_id::text as owner_person_id
      `;
      if (
        updated.length !== 1 ||
        updated[0]?.owner_person_id !== row.owner_person_id
      ) {
        throw new Error("women_profile_owner_retirement_scrub_conflict");
      }
      changed += 1;
    }
  });
  return { scanned: batch.length, changed, hasMore };
}

async function rehydrateBatch(
  sql: ReturnType<typeof postgres>,
  mode: Mode,
  maxProfiles: number,
  confirmation: string | null | undefined,
): Promise<{ scanned: number; changed: number; hasMore: boolean }> {
  if (
    mode === "apply" &&
    confirmation !== "REHYDRATE-WOMEN-PROFILE-OWNERS"
  ) {
    throw new Error(
      "Rehydrate apply mode requires confirmation REHYDRATE-WOMEN-PROFILE-OWNERS.",
    );
  }

  const rows = await sql`
    with active_self as (
      select
        l.person_id,
        a.id as account_id,
        a.legacy_app_user_id
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
    )
    select
      p.owner_person_id::text as owner_person_id,
      max(s.legacy_app_user_id::text) as owner_user_id
    from lifemate.women_calendar_profiles p
    join active_self s on s.person_id=p.owner_person_id
    where p.owner_user_id is null
    group by p.owner_person_id
    having count(distinct s.account_id)=1
    order by p.owner_person_id
    limit ${maxProfiles + 1}
  `;
  const hasMore = rows.length > maxProfiles;
  const batch = rows.slice(0, maxProfiles).map((row) => ({
    owner_person_id: assertUuid("Person", row.owner_person_id),
    owner_user_id: assertUuid("rehydrated AppUser", row.owner_user_id),
  }));
  if (mode === "dry-run") {
    return { scanned: batch.length, changed: 0, hasMore };
  }

  let changed = 0;
  await sql.begin(async (transaction) => {
    for (const row of batch) {
      const mapping = await uniqueActiveMapping(
        transaction,
        row.owner_person_id,
      );
      if (mapping.legacy_app_user_id !== row.owner_user_id) {
        throw new Error("women_profile_owner_retirement_mapping_changed");
      }
      const conflicting = await transaction`
        select 1
        from lifemate.women_calendar_profiles
        where owner_user_id=${row.owner_user_id}::uuid
          and owner_person_id<>${row.owner_person_id}::uuid
        limit 1
      `;
      if (conflicting[0]) {
        throw new Error("women_profile_owner_retirement_rehydrate_conflict");
      }
      const updated = await transaction`
        update lifemate.women_calendar_profiles
        set owner_user_id=${row.owner_user_id}::uuid
        where owner_person_id=${row.owner_person_id}::uuid
          and owner_user_id is null
        returning owner_person_id::text as owner_person_id
      `;
      if (
        updated.length !== 1 ||
        updated[0]?.owner_person_id !== row.owner_person_id
      ) {
        throw new Error("women_profile_owner_retirement_rehydrate_conflict");
      }
      changed += 1;
    }
  });
  return { scanned: batch.length, changed, hasMore };
}

export async function runWomenProfileOwnerRetirement(options: {
  databaseUrl: string;
  operation: Operation;
  mode: Mode;
  maxProfiles: number;
  confirmation?: string | null;
}): Promise<WomenProfileOwnerRetirementSummary> {
  const databaseUrl = options.databaseUrl.trim();
  if (!databaseUrl) throw new Error("Database URL is required.");
  const operation = requireOperation(options.operation);
  const mode = requireMode(options.mode);
  const maxProfiles = requireMaxProfiles(options.maxProfiles);
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
        maxProfiles,
        readiness,
        scannedProfiles: 0,
        changedProfiles: 0,
        hasMore: false,
      };
    }
    const result = operation === "scrub"
      ? await scrubBatch(
        sql,
        mode,
        maxProfiles,
        options.confirmation,
      )
      : await rehydrateBatch(
        sql,
        mode,
        maxProfiles,
        options.confirmation,
      );
    return {
      operation,
      mode,
      maxProfiles,
      readiness,
      scannedProfiles: result.scanned,
      changedProfiles: result.changed,
      hasMore: result.hasMore,
    };
  } finally {
    await sql.end({ timeout: 2 });
  }
}

if (import.meta.main) {
  const operation = requireOperation(
    (Deno.env.get("LIFEMATE_WOMEN_PROFILE_OWNER_OPERATION") ?? "readiness")
      .trim()
      .toLowerCase(),
  );
  const mode = requireMode(
    (Deno.env.get("LIFEMATE_WOMEN_PROFILE_OWNER_MODE") ?? "dry-run")
      .trim()
      .toLowerCase(),
  );
  const summary = await runWomenProfileOwnerRetirement({
    databaseUrl: Deno.env.get("LIFEMATE_IDENTITY_MIGRATION_DATABASE_URL") ?? "",
    operation,
    mode,
    maxProfiles: Number(
      Deno.env.get("LIFEMATE_WOMEN_PROFILE_OWNER_MAX_PROFILES") ?? "100",
    ),
    confirmation: Deno.env.get("LIFEMATE_WOMEN_PROFILE_OWNER_CONFIRM"),
  });
  console.log(JSON.stringify(summary));
}
