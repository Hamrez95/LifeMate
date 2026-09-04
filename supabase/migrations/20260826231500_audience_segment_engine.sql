begin;

create schema if not exists audience;

create table if not exists audience.segments (
  id uuid primary key default gen_random_uuid(),
  segment_key varchar(96) not null unique,
  name varchar(120) not null,
  description varchar(500),
  rule_version integer not null default 1 check (rule_version = 1),
  rule_json jsonb not null,
  rule_hash char(64) not null,
  status varchar(16) not null default 'Active' check (status in ('Active','Archived')),
  version bigint not null default 1 check (version >= 1),
  created_by_account_id uuid not null,
  updated_by_account_id uuid not null,
  created_at_utc timestamptz not null default now(),
  updated_at_utc timestamptz not null default now(),
  check (segment_key ~ '^[a-z][a-z0-9._-]{2,95}$'),
  check (length(trim(name)) between 2 and 120),
  check (rule_hash ~ '^[0-9a-f]{64}$')
);

create table if not exists audience.segment_history (
  segment_id uuid not null,
  version bigint not null,
  snapshot_json jsonb not null,
  archived_at_utc timestamptz not null default now(),
  primary key (segment_id, version)
);

create table if not exists audience.segment_snapshots (
  id uuid primary key default gen_random_uuid(),
  segment_id uuid not null references audience.segments(id),
  segment_version bigint not null check (segment_version >= 1),
  rule_hash char(64) not null,
  source_as_of_utc timestamptz not null,
  member_count integer not null check (member_count >= 0),
  created_by_account_id uuid not null,
  created_at_utc timestamptz not null default now(),
  check (rule_hash ~ '^[0-9a-f]{64}$')
);

create table if not exists audience.segment_snapshot_members (
  snapshot_id uuid not null references audience.segment_snapshots(id) on delete cascade,
  account_id uuid not null,
  person_id uuid,
  primary key (snapshot_id, account_id)
);

create or replace function audience.archive_segment_version()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, audience
as $$
begin
  insert into audience.segment_history(segment_id,version,snapshot_json)
  values (old.id,old.version,to_jsonb(old))
  on conflict (segment_id,version) do nothing;
  return new;
end;
$$;

drop trigger if exists trg_audience_segments_archive on audience.segments;
create trigger trg_audience_segments_archive
before update on audience.segments
for each row execute function audience.archive_segment_version();

create index if not exists ix_audience_segments_status_key
  on audience.segments(status,segment_key);
create index if not exists ix_audience_snapshots_segment_created
  on audience.segment_snapshots(segment_id,created_at_utc desc);
create index if not exists ix_audience_snapshot_members_account
  on audience.segment_snapshot_members(account_id,snapshot_id);

alter table audience.segments enable row level security;
alter table audience.segment_history enable row level security;
alter table audience.segment_snapshots enable row level security;
alter table audience.segment_snapshot_members enable row level security;
alter table audience.segments force row level security;
alter table audience.segment_history force row level security;
alter table audience.segment_snapshots force row level security;
alter table audience.segment_snapshot_members force row level security;

drop policy if exists lifemate_admin_runtime_rw on audience.segments;
create policy lifemate_admin_runtime_rw on audience.segments
for all to lifemate_admin_runtime using (true) with check (true);

drop policy if exists lifemate_admin_runtime_select on audience.segment_history;
create policy lifemate_admin_runtime_select on audience.segment_history
for select to lifemate_admin_runtime using (true);

drop policy if exists lifemate_admin_runtime_rw on audience.segment_snapshots;
create policy lifemate_admin_runtime_rw on audience.segment_snapshots
for all to lifemate_admin_runtime using (true) with check (true);

drop policy if exists lifemate_admin_runtime_rw on audience.segment_snapshot_members;
create policy lifemate_admin_runtime_rw on audience.segment_snapshot_members
for all to lifemate_admin_runtime using (true) with check (true);

revoke all on schema audience from public;
revoke all on all tables in schema audience from public;
revoke all on all functions in schema audience from public;
do $$
begin
  if to_regrole('anon') is not null then
    execute 'revoke all on schema audience from anon';
    execute 'revoke all on all tables in schema audience from anon';
    execute 'revoke all on all functions in schema audience from anon';
  end if;
  if to_regrole('authenticated') is not null then
    execute 'revoke all on schema audience from authenticated';
    execute 'revoke all on all tables in schema audience from authenticated';
    execute 'revoke all on all functions in schema audience from authenticated';
  end if;
end $$;
grant usage on schema audience to lifemate_admin_runtime;
grant select,insert,update on audience.segments to lifemate_admin_runtime;
grant select on audience.segment_history to lifemate_admin_runtime;
grant select,insert on audience.segment_snapshots,audience.segment_snapshot_members to lifemate_admin_runtime;

insert into admin.permissions(code,domain,risk_level,role_assignable,description) values
('marketing.segment.read','marketing','STANDARD',true,'Read reusable marketing audience segment definitions, previews and snapshots'),
('marketing.segment.write','marketing','HIGH_RISK',true,'Create, update, archive and snapshot reusable marketing audience segments')
on conflict (code) do update set
  domain=excluded.domain,
  risk_level=excluded.risk_level,
  role_assignable=excluded.role_assignable,
  description=excluded.description,
  updated_at_utc=now();

insert into admin.role_permissions(role_id,permission_code)
select r.id,p.code
from admin.roles r
join admin.permissions p on p.code in ('marketing.segment.read','marketing.segment.write')
where r.code in ('founder','super_admin','marketing')
on conflict do nothing;

insert into admin.role_permissions(role_id,permission_code)
select r.id,'marketing.segment.read'
from admin.roles r
where r.code in ('product','analyst')
on conflict do nothing;

comment on schema audience is 'Reusable non-clinical audience segmentation definitions and immutable execution snapshots.';
comment on table audience.segments is 'Versioned reusable segment rules. Actor UUID provenance is retained without identity foreign keys so later account deletion is not blocked. Raw health/medication/treatment/women-health attributes are forbidden by the API rule DSL.';
comment on table audience.segment_snapshots is 'Immutable execution snapshot metadata. Creator UUID is provenance only and deliberately not an identity foreign key.';
comment on table audience.segment_snapshot_members is 'Internal immutable execution membership. Account/person UUIDs are retained as opaque execution evidence without foreign keys so account deletion is never blocked. Not exposed to browser roles or general-purpose export APIs.';

commit;
