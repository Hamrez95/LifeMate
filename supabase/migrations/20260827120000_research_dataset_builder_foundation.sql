-- #497: Founder-only research dataset definitions, privacy transforms and export jobs.
-- Extends analytics export policy/audit instead of providing a raw export-all path.

create table if not exists analytics.dataset_definitions (
  id uuid primary key default gen_random_uuid(),
  name character varying(160) not null check (length(trim(name)) between 3 and 160),
  purpose character varying(64) not null references analytics.export_policies(purpose) on delete restrict,
  source_category character varying(80) not null references analytics.source_policies(source_category) on delete restrict,
  filter_json jsonb not null default '{}'::jsonb check (jsonb_typeof(filter_json)='object' and octet_length(filter_json::text)<=16000),
  version integer not null default 1 check (version >= 1),
  status character varying(20) not null default 'Draft' check (status in ('Draft','Active','Archived')),
  created_by_account_id uuid not null references admin.members(account_id) on delete restrict,
  created_at_utc timestamptz not null default now(),
  updated_at_utc timestamptz not null default now()
);

create table if not exists analytics.dataset_privacy_policies (
  dataset_id uuid primary key references analytics.dataset_definitions(id) on delete cascade,
  policy_version integer not null default 1 check (policy_version >= 1),
  direct_identifiers_removed boolean not null default true check (direct_identifiers_removed=true),
  age_bucket_years smallint check (age_bucket_years is null or age_bucket_years between 1 and 20),
  minimum_cohort_size integer not null check (minimum_cohort_size between 5 and 1000000),
  small_cell_threshold integer not null check (small_cell_threshold between 5 and 1000000),
  quasi_identifier_rules jsonb not null default '{}'::jsonb check (jsonb_typeof(quasi_identifier_rules)='object' and octet_length(quasi_identifier_rules::text)<=16000),
  row_mode character varying(20) not null default 'Aggregate' check (row_mode in ('Aggregate','Pseudonymous')),
  updated_by_account_id uuid not null references admin.members(account_id) on delete restrict,
  updated_at_utc timestamptz not null default now(),
  check (small_cell_threshold <= minimum_cohort_size)
);

create table if not exists analytics.dataset_export_jobs (
  id uuid primary key default gen_random_uuid(),
  dataset_id uuid not null references analytics.dataset_definitions(id) on delete restrict,
  dataset_version integer not null,
  privacy_policy_version integer not null,
  requested_by_account_id uuid not null references admin.members(account_id) on delete restrict,
  purpose character varying(64) not null,
  format character varying(12) not null check (format in ('CSV','XLSX')),
  status character varying(24) not null default 'Pending' check (status in ('Pending','Processing','Completed','Rejected','Failed','Expired')),
  cohort_size integer,
  artifact_storage_path character varying(500),
  artifact_sha256 character(64),
  artifact_expires_at_utc timestamptz,
  reason_code character varying(100),
  created_at_utc timestamptz not null default now(),
  updated_at_utc timestamptz not null default now(),
  check (artifact_sha256 is null or artifact_sha256 ~ '^[0-9a-f]{64}$'),
  check (artifact_storage_path is null or artifact_storage_path !~ '(\.\.|^/|://)'),
  check ((status='Completed') = (artifact_storage_path is not null and artifact_sha256 is not null and artifact_expires_at_utc is not null))
);
create index if not exists ix_analytics_dataset_export_jobs_status on analytics.dataset_export_jobs(status,created_at_utc,id);

create or replace function admin.account_is_active_founder(p_account_id uuid, p_at timestamptz default now()) returns boolean
language sql stable set search_path=admin,pg_temp as $$
  select exists(
    select 1 from admin.members m
    join admin.member_roles mr on mr.account_id=m.account_id
    join admin.roles r on r.id=mr.role_id
    where m.account_id=p_account_id and m.status='Active' and r.code='founder' and r.status='Active'
      and mr.revoked_at_utc is null and mr.starts_at_utc<=p_at
      and (mr.expires_at_utc is null or mr.expires_at_utc>p_at)
  )
$$;

create or replace function analytics.create_research_dataset(
  p_actor uuid,p_name varchar,p_purpose varchar,p_source_category varchar,p_filter jsonb,
  p_age_bucket_years smallint,p_minimum_cohort_size integer,p_small_cell_threshold integer,
  p_quasi_identifier_rules jsonb,p_row_mode varchar
) returns uuid
language plpgsql security definer set search_path=analytics,admin,pg_temp as $$
declare v_id uuid; v_policy_min integer; v_research_allowed boolean;
begin
  if not admin.account_is_active_founder(p_actor) then raise exception using errcode='42501',message='research_founder_required'; end if;
  select minimum_cohort_size into v_policy_min from analytics.export_policies where purpose=p_purpose and enabled=true;
  if v_policy_min is null then raise exception using errcode='42501',message='research_export_policy_unavailable'; end if;
  select research_allowed into v_research_allowed from analytics.source_policies where source_category=p_source_category;
  if v_research_allowed is distinct from true then raise exception using errcode='42501',message='research_source_not_allowed'; end if;
  if p_minimum_cohort_size < greatest(v_policy_min,5) or p_small_cell_threshold < 5 or p_small_cell_threshold > p_minimum_cohort_size then
    raise exception using errcode='22023',message='research_privacy_threshold_invalid';
  end if;
  if p_row_mode not in ('Aggregate','Pseudonymous') then raise exception using errcode='22023',message='research_row_mode_invalid'; end if;
  if jsonb_typeof(coalesce(p_filter,'{}'::jsonb)) <> 'object' or octet_length(coalesce(p_filter,'{}'::jsonb)::text)>16000 then raise exception using errcode='22023',message='research_filter_invalid'; end if;
  if jsonb_typeof(coalesce(p_quasi_identifier_rules,'{}'::jsonb)) <> 'object' or octet_length(coalesce(p_quasi_identifier_rules,'{}'::jsonb)::text)>16000 then raise exception using errcode='22023',message='research_transform_invalid'; end if;
  insert into analytics.dataset_definitions(name,purpose,source_category,filter_json,created_by_account_id)
  values(trim(p_name),p_purpose,p_source_category,coalesce(p_filter,'{}'::jsonb),p_actor) returning id into v_id;
  insert into analytics.dataset_privacy_policies(dataset_id,age_bucket_years,minimum_cohort_size,small_cell_threshold,quasi_identifier_rules,row_mode,updated_by_account_id)
  values(v_id,p_age_bucket_years,p_minimum_cohort_size,p_small_cell_threshold,coalesce(p_quasi_identifier_rules,'{}'::jsonb),p_row_mode,p_actor);
  insert into admin.audit_events(actor_account_id,action,resource_type,resource_id,result,correlation_id,metadata_json)
  values(p_actor,'research.dataset.created','research_dataset',v_id::text,'Succeeded',gen_random_uuid(),jsonb_build_object('purpose',p_purpose,'sourceCategory',p_source_category,'rowMode',p_row_mode,'minimumCohortSize',p_minimum_cohort_size,'smallCellThreshold',p_small_cell_threshold));
  return v_id;
end $$;

alter table analytics.dataset_definitions enable row level security;
alter table analytics.dataset_definitions force row level security;
alter table analytics.dataset_privacy_policies enable row level security;
alter table analytics.dataset_privacy_policies force row level security;
alter table analytics.dataset_export_jobs enable row level security;
alter table analytics.dataset_export_jobs force row level security;

-- No table policy/grant is created for the Admin runtime. Founder identity is an
-- application fact, so all access stays behind purpose-specific SECURITY DEFINER
-- functions that receive and verify the exact authenticated actor account.
revoke all on analytics.dataset_definitions,analytics.dataset_privacy_policies,analytics.dataset_export_jobs from public;
revoke all on function analytics.create_research_dataset(uuid,varchar,varchar,varchar,jsonb,smallint,integer,integer,jsonb,varchar) from public;
do $$ begin
  if exists(select 1 from pg_roles where rolname='anon') then revoke all on analytics.dataset_definitions,analytics.dataset_privacy_policies,analytics.dataset_export_jobs from anon; end if;
  if exists(select 1 from pg_roles where rolname='authenticated') then revoke all on analytics.dataset_definitions,analytics.dataset_privacy_policies,analytics.dataset_export_jobs from authenticated; end if;
  if exists(select 1 from pg_roles where rolname='lifemate_admin_runtime') then
    grant usage on schema analytics to lifemate_admin_runtime;
    revoke all on analytics.dataset_definitions,analytics.dataset_privacy_policies,analytics.dataset_export_jobs from lifemate_admin_runtime;
    grant execute on function analytics.create_research_dataset(uuid,varchar,varchar,varchar,jsonb,smallint,integer,integer,jsonb,varchar) to lifemate_admin_runtime;
  end if;
end $$;
