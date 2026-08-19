import { readFileSync } from "node:fs";

const test = readFileSync(
  "supabase/functions/lifemate-api/database_only_breach_proof_integration_test.ts",
  "utf8",
);
const workflow = readFileSync(
  ".github/workflows/database-breach-proof-policy.yml",
  "utf8",
);
const threatModel = readFileSync(
  "docs/security/IDENTITY_MEDICAL_LINKAGE_THREAT_MODEL.md",
  "utf8",
);

for (const marker of [
  'new Deno.Command("pg_dump"',
  '"--data-only"',
  '"--schema=identity"',
  '"--schema=core"',
  '"--schema=lifemate"',
  "dump.includes(forbidden)",
  "LIFEMATE_IDENTITY_LINK_RAW_RETIREMENT",
  "LIFEMATE_IDENTITY_CONTACT_RAW_RETIREMENT",
  "external_identity_tokens",
  "provider_identity_handles",
  "contact_points",
  "directAuthJoin",
  "directProviderJoin",
  "pseudonymousGraph",
  'Deno.env.delete("LIFEMATE_IDENTITY_LINK_KEY")',
]) {
  if (!test.includes(marker)) {
    throw new Error(`Database-breach proof test is missing: ${marker}`);
  }
}

if (/--schema=(auth|storage|realtime)/i.test(test)) {
  throw new Error(
    "Synthetic proof dump must stay scoped to LifeMate-owned application schemas.",
  );
}
if (/writeTextFile|writeFile|Deno\.open|createWriteStream/i.test(test)) {
  throw new Error(
    "Database-breach proof must inspect the synthetic logical dump in memory only.",
  );
}

for (const marker of [
  "postgres:17.6-alpine",
  "--allow-run=pg_dump",
  "database_only_breach_proof_integration_test.ts",
  "verify-database-breach-proof.mjs",
]) {
  if (!workflow.includes(marker)) {
    throw new Error(`Database-breach proof workflow is missing: ${marker}`);
  }
}
if (/actions\/upload-artifact|artifact/i.test(workflow)) {
  throw new Error(
    "Database-breach proof workflow must not upload the synthetic logical dump or artifacts.",
  );
}
if (/\$\{\{\s*secrets\./i.test(workflow)) {
  throw new Error(
    "Synthetic database-breach proof must not depend on real environment secrets.",
  );
}

for (const marker of [
  "Live production evidence — 2026-08-19",
  "Source migrations/runtime have advanced substantially beyond this live schema",
  "Phase 5 — synthetic database-only breach proof",
  "reviewed source target state",
  "does not prove anonymity",
  "#217 remains OPEN",
]) {
  if (!threatModel.includes(marker)) {
    throw new Error(`Threat model source/live distinction is missing: ${marker}`);
  }
}

console.log("Synthetic database-only breach proof boundary verified.");
