import { readFileSync } from "node:fs";

const migrationPath =
  "supabase/migrations/20260819161000_retire_women_profile_owner_user_storage.sql";
const runtimePath =
  "supabase/functions/lifemate-api/person_women_calendar.ts";
const toolPath = "tools/security/women-profile-owner-retirement.ts";
const workflowPath = ".github/workflows/women-profile-owner-retirement.yml";
const runbookPath = "docs/security/WOMEN_PROFILE_OWNER_RETIREMENT_RUNBOOK.md";

const migration = readFileSync(migrationPath, "utf8");
const runtime = readFileSync(runtimePath, "utf8");
const tool = readFileSync(toolPath, "utf8");
const workflow = readFileSync(workflowPath, "utf8");
const runbook = readFileSync(runbookPath, "utf8");

for (const marker of [
  "retire_canonical_women_profile_owner_user",
  "before insert on lifemate.women_calendar_profiles",
  "if new.owner_person_id is not null then",
  "new.owner_user_id := null",
  "trg_00_retire_canonical_women_profile_owner_user",
]) {
  if (!migration.includes(marker)) {
    throw new Error(`Women profile retirement migration missing: ${marker}`);
  }
}
if (/before\s+update[^;]*retire_canonical_women_profile_owner_user/i.test(migration)) {
  throw new Error(
    "Women profile retirement trigger must stay INSERT-only; ordinary updates cannot scrub historical linkage.",
  );
}
if (/\b(delete\s+from|truncate|update)\s+lifemate\.women_calendar_profiles/i.test(migration)) {
  throw new Error(
    "Women profile retirement migration must not rewrite/delete historical profile rows.",
  );
}
if (/drop\s+(index|constraint)[^;]*uq_women_calendar_profile_owner_user/i.test(migration)) {
  throw new Error(
    "Women profile retirement must preserve the legacy rollback uniqueness boundary.",
  );
}

const profileRuntime = runtime.slice(
  runtime.indexOf("async function updateOwnerProfile"),
  runtime.indexOf("async function listOwnerEpisodes"),
);
if (!profileRuntime.includes("owner_person_id")) {
  throw new Error("Canonical Women profile runtime must write owner_person_id.");
}
if (/insert into lifemate\.women_calendar_profiles[\s\S]*?\(owner_user_id,/i.test(profileRuntime)) {
  throw new Error(
    "Canonical Women profile runtime must not persist owner_user_id.",
  );
}
if (profileRuntime.includes("String(row.owner_user_id)")) {
  throw new Error(
    "Canonical Women profile audit cannot depend on retired owner_user_id.",
  );
}
if (!profileRuntime.includes('"women_calendar_profile",\n          personId')) {
  throw new Error("Canonical Women profile audit resource must be Person.");
}

for (const marker of [
  "women_profile_owner_retirement_readiness_vacuous",
  "women_profile_owner_retirement_mapping_missing",
  "women_profile_owner_retirement_mapping_ambiguous",
  "women_profile_owner_retirement_mapping_mismatch",
  "SCRUB-WOMEN-PROFILE-OWNERS",
  "REHYDRATE-WOMEN-PROFILE-OWNERS",
  "maxProfiles must be an integer from 1 to 1000",
  "set owner_user_id=null",
  "owner_user_id is null",
  "and owner_user_id=${row.owner_user_id}::uuid",
  "and owner_user_id is null",
]) {
  if (!tool.includes(marker)) {
    throw new Error(`Women profile retirement tool missing: ${marker}`);
  }
}
if (/console\.log\([^\n]*(owner_person_id|owner_user_id|account_id)/i.test(tool)) {
  throw new Error("Women profile retirement output must remain count-only.");
}

for (const marker of [
  "workflow_dispatch:",
  "environment: beta",
  "github.ref_protected",
  "github.event.repository.private",
  "refs/heads/main",
  "SCRUB-WOMEN-PROFILE-OWNERS",
  "REHYDRATE-WOMEN-PROFILE-OWNERS",
  "LIFEMATE_IDENTITY_BACKFILL_DATABASE_URL",
]) {
  if (!workflow.includes(marker)) {
    throw new Error(`Protected Women profile workflow missing: ${marker}`);
  }
}

for (const marker of [
  "deploy the Person-only runtime first",
  "readiness",
  "scrub",
  "rehydrate",
  "before deploying an older backend",
  "#210",
]) {
  if (!runbook.includes(marker)) {
    throw new Error(`Women profile retirement runbook missing: ${marker}`);
  }
}

console.log("Women Calendar profile owner retirement policy verified.");
