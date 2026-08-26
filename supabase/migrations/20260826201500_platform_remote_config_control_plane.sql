begin;

create schema if not exists platform;

create table if not exists platform.controls (
  control_key varchar(96) primary key,
  control_kind varchar(24) not null check (control_kind in ('FeatureFlag','Config')),
  value_type varchar(16) not null check (value_type in ('Boolean','Integer','String','Json')),
  default_value jsonb not null,
  description varchar(240) not null,
  fail_closed boolean not null default false,
  status varchar(16) not null default 'Active' check (status in ('Active','Retired')),
  version bigint not null default 1 check (version >= 1),
  created_at_utc timestamptz not null default now(),
  updated_at_utc timestamptz not null default now(),
  check (control_key ~ '^[a-z][a-z0-9._-]{2,95}$')
);

create table if not exists platform.control_rules (
  id uuid primary key default gen_random_uuid(),
  control_key varchar(96) not null references platform.controls(control_key) on delete cascade,
  priority integer not null default 100 check (priority between 1 and 10000),
  target_type varchar(24) not null check (target_type in ('Global','Product','Segment','Percentage','Beta','Account')),
  target_key varchar(128),
  rollout_basis_points integer check (rollout_basis_points is null or rollout_basis_points between 0 and 10000),
  value jsonb not null,
  starts_at_utc timestamptz,
  ends_at_utc timestamptz,
  status varchar(16) not null default 'Active' check (status in ('Active','Disabled','Retired')),
  version bigint not null default 1 check (version >= 1),
  created_at_utc timestamptz not null default now(),
  updated_at_utc timestamptz not null default now(),
  check ((target_type='Global' and target_key is null) or (target_type<>'Global' and target_key is not null)),
  check ((target_type='Percentage' and rollout_basis_points is not null) or (target_type<>'Percentage' and rollout_basis_points is null)),
  check (ends_at_utc is null or starts_at_utc is null or ends_at_utc > starts_at_utc)
);

create index if not exists ix_platform_control_rules_lookup
  on platform.control_rules(control_key,status,priority,id);

alter table platform.controls enable row level security;
alter table platform.control_rules enable row level security;
alter table platform.controls force row level security;
alter table platform.control_rules force row level security;
revoke all on schema platform from public, anon, authenticated;
revoke all on all tables in schema platform from public, anon, authenticated;

insert into admin.permissions(code,domain,risk_level,role_assignable,description) values
('platform.config.read','platform','STANDARD',true,'Read canonical Remote Config and Feature Flag definitions and evaluation metadata'),
('platform.config.write','platform','HIGH_RISK',true,'Create or update versioned Remote Config and Feature Flag definitions and rollout rules')
on conflict (code) do update set
  domain=excluded.domain,
  risk_level=excluded.risk_level,
  role_assignable=excluded.role_assignable,
  description=excluded.description,
  updated_at_utc=now();

insert into admin.role_permissions(role_id,permission_code)
select r.id,p.code
from admin.roles r
join admin.permissions p on p.code in ('platform.config.read','platform.config.write')
where r.code in ('founder','super_admin')
on conflict do nothing;

insert into admin.role_permissions(role_id,permission_code)
select r.id,'platform.config.read'
from admin.roles r
where r.code in ('product','technical')
on conflict do nothing;

insert into admin.role_permissions(role_id,permission_code)
select r.id,'platform.config.write'
from admin.roles r
where r.code='technical'
on conflict do nothing;

comment on table platform.controls is 'Canonical typed Remote Config / Feature Flag definitions. No PII or health data is stored here.';
comment on table platform.control_rules is 'Versioned targeting rules for platform controls. target_key must be an opaque product/segment/account identifier, never raw PII.';

commit;
