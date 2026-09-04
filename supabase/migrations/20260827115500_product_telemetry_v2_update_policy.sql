begin;

create schema if not exists analytics;
create schema if not exists platform;

create table if not exists analytics.product_version_presence (
  account_id uuid not null references identity.accounts(id) on delete cascade,
  product varchar(16) not null check (product in ('wellmate','caremate')),
  platform varchar(16) not null check (platform in ('android','ios','web','windows','macos','linux','unknown')),
  app_version varchar(80) not null,
  build_number varchar(40) not null default 'unknown',
  rollout_cohort varchar(64),
  first_seen_at_utc timestamptz not null default now(),
  last_seen_at_utc timestamptz not null default now(),
  event_count bigint not null default 1 check (event_count >= 1),
  primary key (account_id, product, platform, app_version, build_number),
  check (app_version ~ '^[A-Za-z0-9][A-Za-z0-9._+-]{0,79}$'),
  check (build_number ~ '^[A-Za-z0-9][A-Za-z0-9._+-]{0,39}$'),
  check (rollout_cohort is null or rollout_cohort ~ '^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$')
);

create index if not exists ix_product_version_presence_latest
  on analytics.product_version_presence(account_id, product, platform, last_seen_at_utc desc);
create index if not exists ix_product_version_presence_adoption
  on analytics.product_version_presence(product, platform, app_version, last_seen_at_utc desc);

create or replace view analytics.account_product_version_v1 as
select distinct on (p.account_id, p.product, p.platform)
  p.account_id,
  p.product,
  p.platform,
  p.app_version,
  p.build_number,
  p.rollout_cohort,
  p.first_seen_at_utc,
  p.last_seen_at_utc
from analytics.product_version_presence p
order by p.account_id, p.product, p.platform, p.last_seen_at_utc desc,
         p.app_version desc, p.build_number desc;

create or replace view analytics.product_version_adoption_v1 as
select
  product,
  platform,
  app_version,
  build_number,
  count(*)::bigint as account_count,
  min(first_seen_at_utc) as first_seen_at_utc,
  max(last_seen_at_utc) as last_seen_at_utc,
  now() as freshness_at_utc
from analytics.account_product_version_v1
group by product, platform, app_version, build_number;

create table if not exists platform.product_update_policies (
  product varchar(16) not null check (product in ('wellmate','caremate')),
  platform varchar(16) not null check (platform in ('android','ios','web','windows','macos','linux')),
  minimum_supported_version varchar(80) not null,
  recommended_version varchar(80),
  mode varchar(16) not null default 'Soft' check (mode in ('Soft','Force')),
  reason_code varchar(32) not null default 'Routine'
    check (reason_code in ('Routine','Critical','Security','BreakingCompatibility')),
  message_key varchar(96),
  status varchar(16) not null default 'Active' check (status in ('Active','Disabled')),
  version bigint not null default 1 check (version >= 1),
  effective_at_utc timestamptz not null default now(),
  updated_at_utc timestamptz not null default now(),
  updated_by_account_id uuid references identity.accounts(id) on delete set null,
  primary key (product, platform),
  check (minimum_supported_version ~ '^[A-Za-z0-9][A-Za-z0-9._+-]{0,79}$'),
  check (recommended_version is null or recommended_version ~ '^[A-Za-z0-9][A-Za-z0-9._+-]{0,79}$'),
  check (message_key is null or message_key ~ '^[a-z][a-z0-9._-]{2,95}$'),
  check (mode <> 'Force' or reason_code in ('Critical','Security','BreakingCompatibility'))
);

create table if not exists platform.product_update_policy_history (
  product varchar(16) not null,
  platform varchar(16) not null,
  version bigint not null,
  snapshot_json jsonb not null,
  archived_at_utc timestamptz not null default now(),
  primary key (product, platform, version)
);

create or replace function platform.archive_product_update_policy()
returns trigger
language plpgsql
security invoker
set search_path = pg_catalog, platform
as $$
begin
  insert into platform.product_update_policy_history(
    product, platform, version, snapshot_json
  ) values (old.product, old.platform, old.version, to_jsonb(old))
  on conflict do nothing;
  new.version := old.version + 1;
  new.updated_at_utc := now();
  return new;
end;
$$;

drop trigger if exists trg_product_update_policy_archive on platform.product_update_policies;
create trigger trg_product_update_policy_archive
before update on platform.product_update_policies
for each row execute function platform.archive_product_update_policy();

create or replace function analytics.record_product_version_presence(
  p_app_user_id uuid,
  p_product varchar,
  p_platform varchar,
  p_app_version varchar,
  p_build_number varchar default 'unknown',
  p_rollout_cohort varchar default null
) returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, analytics, identity
as $$
declare
  v_account_id uuid;
  v_now timestamptz := now();
begin
  if p_product not in ('wellmate','caremate') then
    raise exception 'product_invalid' using errcode='22023';
  end if;
  if p_platform not in ('android','ios','web','windows','macos','linux','unknown') then
    raise exception 'platform_invalid' using errcode='22023';
  end if;
  if p_app_version is null or p_app_version !~ '^[A-Za-z0-9][A-Za-z0-9._+-]{0,79}$' then
    raise exception 'app_version_invalid' using errcode='22023';
  end if;
  if p_build_number is null or p_build_number !~ '^[A-Za-z0-9][A-Za-z0-9._+-]{0,39}$' then
    raise exception 'build_number_invalid' using errcode='22023';
  end if;
  if p_rollout_cohort is not null and p_rollout_cohort !~ '^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$' then
    raise exception 'rollout_cohort_invalid' using errcode='22023';
  end if;

  select identity.account_id_for_legacy_app_user(p_app_user_id) into v_account_id;
  if v_account_id is null then
    raise exception 'account_not_found' using errcode='P0002';
  end if;

  insert into analytics.product_version_presence(
    account_id, product, platform, app_version, build_number, rollout_cohort,
    first_seen_at_utc, last_seen_at_utc, event_count
  ) values (
    v_account_id, p_product, p_platform, p_app_version, p_build_number,
    p_rollout_cohort, v_now, v_now, 1
  )
  on conflict (account_id, product, platform, app_version, build_number)
  do update set
    rollout_cohort=coalesce(excluded.rollout_cohort, analytics.product_version_presence.rollout_cohort),
    last_seen_at_utc=v_now,
    event_count=analytics.product_version_presence.event_count+1;

  -- Retention is bounded without collecting a device identifier. Historical
  -- version-presence facts older than 400 days are not needed for operations.
  delete from analytics.product_version_presence
  where account_id=v_account_id and last_seen_at_utc < v_now - interval '400 days';

  return jsonb_build_object(
    'product', p_product,
    'platform', p_platform,
    'appVersion', p_app_version,
    'buildNumber', p_build_number,
    'lastSeenAtUtc', v_now
  );
end;
$$;

create or replace function platform.current_product_update_policy(
  p_product varchar,
  p_platform varchar
) returns jsonb
language sql
stable
security definer
set search_path = pg_catalog, platform
as $$
  select coalesce((
    select jsonb_build_object(
      'product', product,
      'platform', platform,
      'minimumSupportedVersion', minimum_supported_version,
      'recommendedVersion', recommended_version,
      'mode', mode,
      'reasonCode', reason_code,
      'messageKey', message_key,
      'policyVersion', version,
      'effectiveAtUtc', effective_at_utc,
      'updatedAtUtc', updated_at_utc
    )
    from platform.product_update_policies
    where product=p_product and platform=p_platform
      and status='Active' and effective_at_utc <= now()
    limit 1
  ), jsonb_build_object(
    'product', p_product,
    'platform', p_platform,
    'minimumSupportedVersion', null,
    'recommendedVersion', null,
    'mode', 'Soft',
    'reasonCode', 'Routine',
    'messageKey', null,
    'policyVersion', 0
  ))
$$;

alter table analytics.product_version_presence enable row level security;
alter table analytics.product_version_presence force row level security;
alter table platform.product_update_policies enable row level security;
alter table platform.product_update_policies force row level security;
alter table platform.product_update_policy_history enable row level security;
alter table platform.product_update_policy_history force row level security;

revoke all on analytics.product_version_presence from public;
revoke all on platform.product_update_policies from public;
revoke all on platform.product_update_policy_history from public;
revoke all on function analytics.record_product_version_presence(uuid,varchar,varchar,varchar,varchar,varchar) from public;
revoke all on function platform.current_product_update_policy(varchar,varchar) from public;
do $$
begin
  if to_regrole('anon') is not null then
    execute 'revoke all on analytics.product_version_presence from anon';
    execute 'revoke all on platform.product_update_policies from anon';
    execute 'revoke all on platform.product_update_policy_history from anon';
    execute 'revoke all on function analytics.record_product_version_presence(uuid,varchar,varchar,varchar,varchar,varchar) from anon';
    execute 'revoke all on function platform.current_product_update_policy(varchar,varchar) from anon';
  end if;
  if to_regrole('authenticated') is not null then
    execute 'revoke all on analytics.product_version_presence from authenticated';
    execute 'revoke all on platform.product_update_policies from authenticated';
    execute 'revoke all on platform.product_update_policy_history from authenticated';
    execute 'revoke all on function analytics.record_product_version_presence(uuid,varchar,varchar,varchar,varchar,varchar) from authenticated';
    execute 'revoke all on function platform.current_product_update_policy(varchar,varchar) from authenticated';
  end if;
end $$;

do $$
begin
  if exists (select 1 from pg_roles where rolname='lifemate_edge_runtime') then
    grant usage on schema analytics, platform to lifemate_edge_runtime;
    grant execute on function analytics.record_product_version_presence(uuid,varchar,varchar,varchar,varchar,varchar) to lifemate_edge_runtime;
    grant execute on function platform.current_product_update_policy(varchar,varchar) to lifemate_edge_runtime;
  end if;
  if exists (select 1 from pg_roles where rolname='lifemate_admin_runtime') then
    grant usage on schema analytics, platform to lifemate_admin_runtime;
    grant select on analytics.account_product_version_v1, analytics.product_version_adoption_v1 to lifemate_admin_runtime;
    grant select on platform.product_update_policies to lifemate_admin_runtime;
  end if;
end
$$;

insert into admin.permissions(code,domain,risk_level,role_assignable,description) values
('analytics.product_versions.read','analytics','STANDARD',true,'Read product app-version adoption and per-user current version metadata')
on conflict (code) do update set
  domain=excluded.domain,
  risk_level=excluded.risk_level,
  role_assignable=excluded.role_assignable,
  description=excluded.description,
  updated_at_utc=now();

insert into admin.role_permissions(role_id,permission_code)
select r.id,'analytics.product_versions.read'
from admin.roles r
where r.code in ('founder','super_admin','product','technical')
on conflict do nothing;

comment on table analytics.product_version_presence is
  'Account-scoped product/version presence facts. No device fingerprint, raw health data, contact value or arbitrary client metadata is accepted.';
comment on view analytics.account_product_version_v1 is
  'Current/last-seen product version per Account, Product and Platform for User 360 operational context.';
comment on view analytics.product_version_adoption_v1 is
  'Aggregate current app-version adoption counts with source freshness.';
comment on table platform.product_update_policies is
  'Server-managed update policy. Soft is default; Force is structurally restricted to Critical/Security/BreakingCompatibility reasons.';

commit;
