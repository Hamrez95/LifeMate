import assert from 'node:assert/strict';

const projectRef = process.env.SUPABASE_PROJECT_REF?.trim();
const accessToken = process.env.SUPABASE_ACCESS_TOKEN?.trim();

assert.match(
  projectRef ?? '',
  /^[a-z]{20}$/,
  'SUPABASE_PROJECT_REF must be an exact Supabase project ref',
);
assert.ok(accessToken, 'SUPABASE_ACCESS_TOKEN is required for DB preflight');

const query = `
select
  '20260902_runtime_v2'::text as contract_version,
  (
    to_regprocedure('consent.current_registration_legal_documents(character varying)') is not null
    and to_regprocedure('consent.registration_status_for_app_user(uuid,character varying)') is not null
    and to_regprocedure('public.get_my_demographics()') is not null
    and to_regclass('consent.legal_acceptances') is not null
    and exists (
      select 1
      from information_schema.columns
      where table_schema='identity'
        and table_name='accounts'
        and column_name='registration_completed_at_utc'
    )
    and exists (
      select 1
      from information_schema.columns
      where table_schema='consent'
        and table_name='consent_documents'
        and column_name='content_uri'
    )
    and to_regnamespace('platform') is not null
    and to_regprocedure('platform.client_control_evaluations(uuid,character varying,boolean)') is not null
    and to_regprocedure('platform.current_product_update_policy(character varying,character varying)') is not null
    and to_regclass('analytics.product_version_presence') is not null
    and has_schema_privilege('lifemate_edge_runtime','platform','USAGE')
    and has_function_privilege(
      'lifemate_edge_runtime',
      'platform.client_control_evaluations(uuid,character varying,boolean)',
      'EXECUTE'
    )
    and has_function_privilege(
      'lifemate_edge_runtime',
      'platform.current_product_update_policy(character varying,character varying)',
      'EXECUTE'
    )
    and exists (
      select 1
      from information_schema.columns
      where table_schema='lifemate'
        and table_name='treatment_plans'
        and column_name='recurrence_rule'
    )
    and exists (
      select 1
      from information_schema.columns
      where table_schema='lifemate'
        and table_name='care_events'
        and column_name='recurrence_rule'
    )
    and has_table_privilege('lifemate_edge_runtime','network.circles','SELECT')
    and has_table_privilege('lifemate_edge_runtime','network.circle_members','SELECT')
    and has_table_privilege('lifemate_edge_runtime','network.circle_invitations','SELECT')
    and has_table_privilege('lifemate_edge_runtime','network.circle_member_sharing_policies','SELECT')
    and exists (
      select 1
      from pg_policies
      where schemaname='network'
        and tablename='circles'
        and policyname='lifemate_edge_runtime_access'
        and 'lifemate_edge_runtime'=any(roles)
        and cmd='ALL'
        and coalesce(qual,'')='true'
        and coalesce(with_check,'')='true'
    )
  ) as ready
`;

const response = await fetch(
  `https://api.supabase.com/v1/projects/${encodeURIComponent(projectRef)}/database/query/read-only`,
  {
    method: 'POST',
    headers: {
      authorization: `Bearer ${accessToken}`,
      'content-type': 'application/json',
    },
    body: JSON.stringify({ query, parameters: [] }),
  },
);

if (!response.ok) {
  throw new Error(
    `Production DB contract preflight request failed with HTTP ${response.status}`,
  );
}

const payload = await response.json();

function findContract(value) {
  if (Array.isArray(value)) {
    for (const entry of value) {
      const found = findContract(entry);
      if (found) return found;
    }
    return null;
  }
  if (!value || typeof value !== 'object') return null;
  if (value.contract_version === '20260902_runtime_v2') return value;
  for (const entry of Object.values(value)) {
    const found = findContract(entry);
    if (found) return found;
  }
  return null;
}

const contract = findContract(payload);
assert.ok(contract, 'Production DB preflight returned no recognized contract row');
assert.equal(
  contract.ready,
  true,
  'Production DB is missing a required exact-main runtime contract; refusing API deploy',
);

console.log('PASS: production DB satisfies LifeMate post-login runtime contract');
