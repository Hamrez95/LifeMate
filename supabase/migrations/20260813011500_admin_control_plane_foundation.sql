-- LifeMate Command Center administrative control plane.
--
-- This migration is additive and intentionally separates internal staff authorization
-- from patient/caregiver access grants. Admin permissions never imply health-data
-- authorization. Elevated health capabilities are non-role-assignable and require a
-- separate time-bound access request.

create extension if not exists pgcrypto;
create schema if not exists admin;

create table if not exists admin.roles (
    id uuid primary key default gen_random_uuid(),
    code character varying(64) not null unique,
    display_name character varying(120) not null,
    rank smallint not null default 100 check (rank between 1 and 1000),
    status character varying(24) not null default 'Active'
        check (status in ('Active','Disabled')),
    is_system boolean not null default true,
    created_at_utc timestamp with time zone not null default now(),
    updated_at_utc timestamp with time zone not null default now()
);

create table if not exists admin.permissions (
    code character varying(128) primary key,
    domain character varying(48) not null,
    risk_level character varying(24) not null
        check (risk_level in ('STANDARD','SENSITIVE','HIGH_RISK','ELEVATED')),
    role_assignable boolean not null default true,
    description character varying(320) not null,
    created_at_utc timestamp with time zone not null default now(),
    updated_at_utc timestamp with time zone not null default now()
);

create table if not exists admin.role_permissions (
    role_id uuid not null references admin.roles(id) on delete cascade,
    permission_code character varying(128) not null
        references admin.permissions(code) on delete restrict,
    created_at_utc timestamp with time zone not null default now(),
    primary key (role_id, permission_code)
);
create index if not exists ix_admin_role_permissions_permission
    on admin.role_permissions(permission_code, role_id);

create table if not exists admin.members (
    account_id uuid primary key references identity.accounts(id) on delete restrict,
    status character varying(24) not null default 'Active'
        check (status in ('Active','Disabled','Revoked')),
    created_by_account_id uuid references identity.accounts(id) on delete restrict,
    created_at_utc timestamp with time zone not null default now(),
    updated_at_utc timestamp with time zone not null default now(),
    disabled_at_utc timestamp with time zone
);

create table if not exists admin.member_roles (
    id uuid primary key default gen_random_uuid(),
    account_id uuid not null references admin.members(account_id) on delete cascade,
    role_id uuid not null references admin.roles(id) on delete restrict,
    granted_by_account_id uuid references identity.accounts(id) on delete restrict,
    starts_at_utc timestamp with time zone not null default now(),
    expires_at_utc timestamp with time zone,
    revoked_at_utc timestamp with time zone,
    created_at_utc timestamp with time zone not null default now(),
    check (expires_at_utc is null or expires_at_utc > starts_at_utc)
);
create unique index if not exists uq_admin_member_roles_active
    on admin.member_roles(account_id, role_id)
    where revoked_at_utc is null;
create index if not exists ix_admin_member_roles_account_window
    on admin.member_roles(account_id, starts_at_utc, expires_at_utc)
    where revoked_at_utc is null;

-- Append-oriented administrative audit evidence. The application runtime receives
-- SELECT+INSERT only; UPDATE/DELETE/TRUNCATE are deliberately never granted.
create table if not exists admin.audit_events (
    id uuid primary key default gen_random_uuid(),
    actor_account_id uuid references identity.accounts(id) on delete set null,
    action character varying(160) not null,
    resource_type character varying(100) not null,
    resource_id character varying(180),
    result character varying(24) not null
        check (result in ('Allowed','Denied','Succeeded','Failed')),
    reason character varying(1000),
    correlation_id uuid not null,
    request_id character varying(180),
    elevated_access boolean not null default false,
    metadata_json jsonb not null default '{}'::jsonb
        check (jsonb_typeof(metadata_json) = 'object'),
    occurred_at_utc timestamp with time zone not null default now()
);
create index if not exists ix_admin_audit_events_occurred
    on admin.audit_events(occurred_at_utc desc);
create index if not exists ix_admin_audit_events_actor
    on admin.audit_events(actor_account_id, occurred_at_utc desc)
    where actor_account_id is not null;
create index if not exists ix_admin_audit_events_resource
    on admin.audit_events(resource_type, resource_id, occurred_at_utc desc);

-- Mutation idempotency contains only administrative request/response metadata. API
-- code must never persist raw health payloads in this table.
create table if not exists admin.idempotency_keys (
    actor_account_id uuid not null references identity.accounts(id) on delete cascade,
    operation character varying(120) not null,
    idempotency_key character varying(180) not null,
    request_hash character varying(128) not null,
    status character varying(24) not null default 'Processing'
        check (status in ('Processing','Completed','Failed')),
    response_status integer check (response_status is null or response_status between 100 and 599),
    response_json jsonb,
    created_at_utc timestamp with time zone not null default now(),
    updated_at_utc timestamp with time zone not null default now(),
    expires_at_utc timestamp with time zone not null default (now() + interval '24 hours'),
    primary key (actor_account_id, operation, idempotency_key)
);
create index if not exists ix_admin_idempotency_expiry
    on admin.idempotency_keys(expires_at_utc);

-- Break-glass foundation. Approval does not itself expose data; later User 360 APIs
-- must additionally call admin.account_has_elevated_access for the exact subject and
-- capability. These capabilities cannot be granted through ordinary roles.
create table if not exists admin.elevated_access_requests (
    id uuid primary key default gen_random_uuid(),
    requester_account_id uuid not null references admin.members(account_id) on delete restrict,
    subject_person_id uuid not null references core.persons(id) on delete restrict,
    capability character varying(128) not null
        check (capability in ('health.read.elevated','women_health.read.elevated')),
    reason character varying(1000) not null check (length(trim(reason)) >= 10),
    status character varying(24) not null default 'Pending'
        check (status in ('Pending','Approved','Denied','Expired','Revoked')),
    requested_at_utc timestamp with time zone not null default now(),
    reviewed_by_account_id uuid references admin.members(account_id) on delete restrict,
    reviewed_at_utc timestamp with time zone,
    expires_at_utc timestamp with time zone,
    revoked_at_utc timestamp with time zone,
    review_reason character varying(1000),
    check (
      (status = 'Pending' and reviewed_at_utc is null and expires_at_utc is null)
      or status <> 'Pending'
    )
);
create index if not exists ix_admin_elevated_requests_requester
    on admin.elevated_access_requests(requester_account_id, requested_at_utc desc);
create index if not exists ix_admin_elevated_requests_subject_active
    on admin.elevated_access_requests(subject_person_id, capability, expires_at_utc)
    where status = 'Approved';

-- Capability checks are centralized and fail closed. A permission marked
-- role_assignable=false can never become effective through role membership even if a
-- row is inserted into role_permissions by a privileged DBA.
create or replace function admin.account_has_permission(
    p_account_id uuid,
    p_permission character varying,
    p_at timestamp with time zone default now()
) returns boolean
language sql
stable
set search_path = admin, pg_temp
as $$
    select exists (
      select 1
      from admin.members m
      join admin.member_roles mr on mr.account_id = m.account_id
      join admin.roles r on r.id = mr.role_id
      join admin.role_permissions rp on rp.role_id = r.id
      join admin.permissions p on p.code = rp.permission_code
      where m.account_id = p_account_id
        and m.status = 'Active'
        and r.status = 'Active'
        and mr.revoked_at_utc is null
        and mr.starts_at_utc <= p_at
        and (mr.expires_at_utc is null or mr.expires_at_utc > p_at)
        and p.code = p_permission
        and p.role_assignable = true
    )
$$;

create or replace function admin.account_has_elevated_access(
    p_account_id uuid,
    p_subject_person_id uuid,
    p_capability character varying,
    p_at timestamp with time zone default now()
) returns boolean
language sql
stable
set search_path = admin, pg_temp
as $$
    select exists (
      select 1
      from admin.members m
      join admin.elevated_access_requests e
        on e.requester_account_id = m.account_id
      where m.account_id = p_account_id
        and m.status = 'Active'
        and e.subject_person_id = p_subject_person_id
        and e.capability = p_capability
        and e.status = 'Approved'
        and e.reviewed_at_utc is not null
        and e.expires_at_utc is not null
        and e.expires_at_utc > p_at
        and e.revoked_at_utc is null
    )
$$;

insert into admin.permissions(code, domain, risk_level, role_assignable, description) values
('users.read.basic','users','STANDARD',true,'Read non-health User 360 identity/application/system summary'),
('users.read.sensitive','users','SENSITIVE',true,'Read separately permitted sensitive identity/contact details; never raw health records'),
('users.suspend','users','HIGH_RISK',true,'Suspend an end-user account through an audited workflow'),
('relationships.read','relationships','SENSITIVE',true,'Read relationship, access-grant and consent state without raw health payloads'),
('support.read','support','STANDARD',true,'Read LifeMate support workflow data'),
('support.write','support','SENSITIVE',true,'Create and update LifeMate support workflow data'),
('commerce.read','commerce','STANDARD',true,'Read subscriptions, plans, entitlements and promotions'),
('commerce.refund','commerce','HIGH_RISK',true,'Initiate a human-approved refund workflow'),
('commerce.promo.write','commerce','SENSITIVE',true,'Create or update promotion rules and codes'),
('marketing.read','marketing','STANDARD',true,'Read campaigns, attribution and content workflow data'),
('marketing.campaign.write','marketing','SENSITIVE',true,'Create and edit campaigns and content plans'),
('marketing.social.publish','marketing','HIGH_RISK',true,'Approve publication through a configured social adapter'),
('finance.read','finance','SENSITIVE',true,'Read management finance summaries and source records'),
('finance.write','finance','HIGH_RISK',true,'Create or amend management finance records through audited workflows'),
('analytics.read','analytics','STANDARD',true,'Read approved aggregate product/business analytics'),
('operations.read','operations','SENSITIVE',true,'Read service health, release, integration and incident summaries'),
('security.audit.read','security','SENSITIVE',true,'Read administrative security audit evidence'),
('security.roles.write','security','HIGH_RISK',true,'Manage administrative role membership and permissions'),
('security.break_glass.request','security','HIGH_RISK',true,'Request temporary subject-scoped access to sensitive health data'),
('security.break_glass.approve','security','HIGH_RISK',true,'Approve or deny a temporary sensitive-data access request'),
('ai.business.read','ai','STANDARD',true,'Use read-only AI business tools allowed by current permissions'),
('ai.marketing.use','ai','STANDARD',true,'Use AI marketing drafting tools without autonomous publishing'),
('settings.read','settings','STANDARD',true,'Read Command Center configuration'),
('settings.write','settings','HIGH_RISK',true,'Change reviewed Command Center configuration'),
('health.read.elevated','health','ELEVATED',false,'Temporary subject-scoped raw health access; never role assignable'),
('women_health.read.elevated','women_health','ELEVATED',false,'Temporary highly-sensitive women-health access; never role assignable')
on conflict (code) do update set
  domain=excluded.domain,
  risk_level=excluded.risk_level,
  role_assignable=excluded.role_assignable,
  description=excluded.description,
  updated_at_utc=now();

insert into admin.roles(code, display_name, rank, status, is_system) values
('founder','Founder',10,'Active',true),
('super_admin','Super Admin',20,'Active',true),
('product','Product',100,'Active',true),
('support','Support',110,'Active',true),
('marketing','Marketing',120,'Active',true),
('finance','Finance',130,'Active',true),
('technical','Technical',140,'Active',true),
('security','Security',150,'Active',true)
on conflict (code) do update set
  display_name=excluded.display_name,
  rank=excluded.rank,
  status=excluded.status,
  is_system=excluded.is_system,
  updated_at_utc=now();

-- Founder and Super Admin receive all ordinary role-assignable permissions. Elevated
-- health access remains impossible through role membership.
insert into admin.role_permissions(role_id, permission_code)
select r.id, p.code
from admin.roles r
cross join admin.permissions p
where r.code in ('founder','super_admin') and p.role_assignable = true
on conflict do nothing;

-- Product.
insert into admin.role_permissions(role_id, permission_code)
select r.id, v.permission_code
from admin.roles r
cross join (values
 ('users.read.basic'),('relationships.read'),('commerce.read'),('analytics.read'),
 ('operations.read'),('ai.business.read'),('settings.read')
) v(permission_code)
where r.code='product'
on conflict do nothing;

-- Support.
insert into admin.role_permissions(role_id, permission_code)
select r.id, v.permission_code
from admin.roles r
cross join (values
 ('users.read.basic'),('relationships.read'),('support.read'),('support.write'),('settings.read')
) v(permission_code)
where r.code='support'
on conflict do nothing;

-- Marketing.
insert into admin.role_permissions(role_id, permission_code)
select r.id, v.permission_code
from admin.roles r
cross join (values
 ('marketing.read'),('marketing.campaign.write'),('marketing.social.publish'),
 ('commerce.read'),('commerce.promo.write'),('analytics.read'),('ai.marketing.use'),('settings.read')
) v(permission_code)
where r.code='marketing'
on conflict do nothing;

-- Finance.
insert into admin.role_permissions(role_id, permission_code)
select r.id, v.permission_code
from admin.roles r
cross join (values
 ('finance.read'),('finance.write'),('commerce.read'),('commerce.refund'),('analytics.read'),('settings.read')
) v(permission_code)
where r.code='finance'
on conflict do nothing;

-- Technical.
insert into admin.role_permissions(role_id, permission_code)
select r.id, v.permission_code
from admin.roles r
cross join (values
 ('users.read.basic'),('analytics.read'),('operations.read'),('ai.business.read'),('settings.read')
) v(permission_code)
where r.code='technical'
on conflict do nothing;

-- Security. Even Security does not receive raw health access by role.
insert into admin.role_permissions(role_id, permission_code)
select r.id, v.permission_code
from admin.roles r
cross join (values
 ('users.read.basic'),('operations.read'),('security.audit.read'),('security.roles.write'),
 ('security.break_glass.request'),('security.break_glass.approve'),('settings.read')
) v(permission_code)
where r.code='security'
on conflict do nothing;

-- Dedicated least-privilege database identity for the Admin API. The portable SQL
-- chain must also run on ordinary PostgreSQL, so Vault references remain dynamic.
do $$
declare
  v_password text;
  v_secret_id uuid;
begin
  if not exists (select 1 from pg_roles where rolname='lifemate_admin_runtime') then
    v_password := encode(gen_random_bytes(32),'hex');
    execute format(
      'create role lifemate_admin_runtime with login password %L nosuperuser nocreatedb nocreaterole noinherit noreplication nobypassrls connection limit 10',
      v_password
    );
  else
    alter role lifemate_admin_runtime with login nosuperuser nocreatedb nocreaterole noinherit noreplication nobypassrls connection limit 10;
  end if;

  if to_regnamespace('vault') is not null then
    execute 'select id from vault.secrets where name=''lifemate_admin_runtime_password'' limit 1'
      into v_secret_id;
    if v_secret_id is null then
      if v_password is null then
        v_password := encode(gen_random_bytes(32),'hex');
        execute format('alter role lifemate_admin_runtime password %L', v_password);
      end if;
      execute format(
        'select vault.create_secret(%L,%L,%L)',
        v_password,
        'lifemate_admin_runtime_password',
        'Password for the least-privilege LifeMate Command Center Admin API database role'
      );
    end if;
  end if;
end
$$;

do $$
begin
  execute format('revoke all on database %I from lifemate_admin_runtime', current_database());
  execute format('grant connect on database %I to lifemate_admin_runtime', current_database());
end
$$;

-- Start from explicit deny. In particular, the Admin API receives no schema/table
-- access to the compatibility health schema (`lifemate`) or care read model schema.
do $$
declare
  v_schema text;
begin
  foreach v_schema in array array[
    'lifemate','care','identity','core','ecosystem','network','security','consent',
    'commerce','integration','analytics','admin'
  ] loop
    if to_regnamespace(v_schema) is not null then
      execute format('revoke all on schema %I from lifemate_admin_runtime', v_schema);
      execute format('revoke all on all tables in schema %I from lifemate_admin_runtime', v_schema);
      execute format('revoke all on all sequences in schema %I from lifemate_admin_runtime', v_schema);
      execute format('revoke all on all functions in schema %I from lifemate_admin_runtime', v_schema);
    end if;
  end loop;
end
$$;

grant usage on schema admin, identity, core, ecosystem, network, security, consent, commerce, analytics to lifemate_admin_runtime;

-- Admin control-plane access. No runtime DELETE/TRUNCATE privilege is granted.
grant select on admin.roles, admin.permissions, admin.role_permissions, admin.members,
  admin.member_roles, admin.audit_events, admin.idempotency_keys,
  admin.elevated_access_requests to lifemate_admin_runtime;
grant insert, update on admin.members, admin.member_roles, admin.idempotency_keys,
  admin.elevated_access_requests to lifemate_admin_runtime;
grant insert on admin.audit_events to lifemate_admin_runtime;
grant usage, select on all sequences in schema admin to lifemate_admin_runtime;
grant execute on function admin.account_has_permission(uuid, character varying, timestamp with time zone)
  to lifemate_admin_runtime;
grant execute on function admin.account_has_elevated_access(uuid, uuid, character varying, timestamp with time zone)
  to lifemate_admin_runtime;

-- Non-health read surfaces required for admin identity resolution and future safe User
-- 360. Explicit table grants prevent accidental expansion when new tables are added.
grant select on identity.accounts, identity.external_identities, identity.contact_points,
  identity.account_deletion_requests to lifemate_admin_runtime;
grant select on core.persons, core.person_profiles, core.account_person_links to lifemate_admin_runtime;
grant select on ecosystem.applications, ecosystem.app_enrollments to lifemate_admin_runtime;
grant select on network.person_relationships to lifemate_admin_runtime;
grant select on security.access_grants, security.access_grant_scopes, security.scope_catalog to lifemate_admin_runtime;
grant select on consent.consent_records, consent.consent_events, consent.data_use_consents to lifemate_admin_runtime;
grant select on commerce.products, commerce.plans, commerce.features, commerce.product_features,
  commerce.prices, commerce.subscriptions, commerce.entitlements, commerce.entitlement_events
  to lifemate_admin_runtime;
grant select on analytics.source_policies, analytics.export_policies, analytics.export_audit
  to lifemate_admin_runtime;

-- RLS on admin control-plane tables. Table privileges remain the first command gate;
-- RLS is an additional fail-closed boundary because the runtime cannot bypass RLS.
do $$
declare
  v_table text;
begin
  foreach v_table in array array[
    'roles','permissions','role_permissions','members','member_roles','audit_events',
    'idempotency_keys','elevated_access_requests'
  ] loop
    execute format('alter table admin.%I enable row level security', v_table);
    execute format('alter table admin.%I force row level security', v_table);
    execute format('drop policy if exists lifemate_admin_runtime_select on admin.%I', v_table);
    execute format(
      'create policy lifemate_admin_runtime_select on admin.%I for select to lifemate_admin_runtime using (true)',
      v_table
    );
  end loop;
end
$$;

do $$
declare
  v_table text;
begin
  foreach v_table in array array['members','member_roles','idempotency_keys','elevated_access_requests'] loop
    execute format('drop policy if exists lifemate_admin_runtime_insert on admin.%I', v_table);
    execute format('drop policy if exists lifemate_admin_runtime_update on admin.%I', v_table);
    execute format(
      'create policy lifemate_admin_runtime_insert on admin.%I for insert to lifemate_admin_runtime with check (true)',
      v_table
    );
    execute format(
      'create policy lifemate_admin_runtime_update on admin.%I for update to lifemate_admin_runtime using (true) with check (true)',
      v_table
    );
  end loop;
end
$$;

drop policy if exists lifemate_admin_runtime_insert on admin.audit_events;
create policy lifemate_admin_runtime_insert on admin.audit_events
  for insert to lifemate_admin_runtime with check (true);

-- Direct Supabase browser roles receive no Admin schema access.
do $$
declare
  v_role text;
begin
  foreach v_role in array array['anon','authenticated'] loop
    if exists (select 1 from pg_roles where rolname=v_role) then
      execute format('revoke all on schema admin from %I', v_role);
      execute format('revoke all on all tables in schema admin from %I', v_role);
      execute format('revoke all on all sequences in schema admin from %I', v_role);
      execute format('revoke all on all functions in schema admin from %I', v_role);
    end if;
  end loop;
end
$$;

revoke all on schema admin from public;
revoke all on all tables in schema admin from public;
revoke all on all sequences in schema admin from public;
