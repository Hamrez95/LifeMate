import fs from 'node:fs';

const migration = fs.readFileSync(
  'supabase/migrations/20260816045500_add_runtime_onboarding_control.sql',
  'utf8',
);
const database = fs.readFileSync(
  'supabase/functions/lifemate-api/database_legacy.ts',
  'utf8',
);
const databaseClient = fs.readFileSync(
  'supabase/functions/lifemate-api/database_client.ts',
  'utf8',
);
const runbook = fs.readFileSync(
  'docs/operations/beta-onboarding-control.md',
  'utf8',
);

function fail(message) {
  console.error(`Runtime onboarding control policy failure: ${message}`);
  process.exit(1);
}
function requireText(haystack, value, message) {
  if (!haystack.includes(value)) fail(message);
}
function forbidText(haystack, value, message) {
  if (haystack.toLowerCase().includes(value.toLowerCase())) fail(message);
}

for (const [value, message] of [
  ['create table if not exists security.runtime_controls', 'control must live in a LifeMate-owned PostgreSQL schema'],
  ["'new_user_onboarding'", 'migration must seed the new-user onboarding control'],
  ['alter table security.runtime_controls force row level security', 'control must force RLS'],
  ['grant select on table security.runtime_controls to lifemate_edge_runtime', 'Edge runtime must have read-only visibility'],
  ['revoke all on table security.runtime_controls from lifemate_edge_runtime', 'runtime privileges must be reset before the narrow SELECT grant'],
  ['create or replace function security.enforce_new_user_onboarding_control()', 'database boundary must enforce the control'],
  ['before insert on lifemate.app_users', 'new AppUser creation must be gated before INSERT'],
  ['where auth_subject = new.auth_subject', 'existing subjects must retain the idempotent conflict path'],
  ["errcode = '55P03'", 'paused onboarding must use the controlled temporary-unavailable SQLSTATE'],
]) requireText(migration, value, message);

requireText(
  database,
  'on conflict (auth_subject) do update',
  'bootstrap must remain idempotent so existing users can pass the INSERT trigger during a pause',
);
requireText(
  databaseClient,
  'code === "55P03"',
  'runtime must map the onboarding pause SQLSTATE to a controlled temporary-unavailable response',
);

for (const [value, message] of [
  ['application-bootstrap gate, not an identity-provider kill switch', 'runbook must state the provider-independent scope precisely'],
  ['Only an approved migration/operator database identity may mutate the control.', 'runbook must name the mutation boundary'],
  ['update security.runtime_controls', 'runbook must include a no-deploy pause/resume procedure'],
  ['Existing AppUsers continue normal authenticated flows', 'runbook must preserve existing-user continuity'],
]) requireText(runbook, value, message);

for (const [value, message] of [
  ['supabase db dump', 'onboarding control must not depend on Supabase CLI'],
  ['/auth/v1/admin', 'onboarding control must not depend on a provider-admin HTTP endpoint'],
]) forbidText(migration, value, message);

if (/grant\s+(insert|update|delete|all)[^;]*runtime_controls[^;]*lifemate_edge_runtime/i.test(migration)) {
  fail('Edge runtime must never receive mutation privileges on runtime_controls');
}

console.log('Runtime onboarding control is provider-independent, fail-closed, read-only to Edge, and no-deploy operable.');
