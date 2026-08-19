-- Admin-only workforce profile foundation for Command Center staff.
--
-- Auth identity remains in Supabase Auth / identity.accounts. This table stores only
-- internal workforce presentation metadata and never consumer Person, health, password,
-- token or provider-secret data. Authorization remains admin.members + member_roles.

create table if not exists admin.staff_profiles (
    account_id uuid primary key references admin.members(account_id) on delete cascade,
    username character varying(32) not null unique,
    display_name character varying(120) not null,
    created_at_utc timestamp with time zone not null default now(),
    updated_at_utc timestamp with time zone not null default now(),
    username_changed_at_utc timestamp with time zone not null default now(),
    check (username = lower(username)),
    check (username ~ '^[a-z0-9][a-z0-9._-]{2,31}$'),
    check (length(trim(display_name)) between 2 and 120)
);

create index if not exists ix_admin_staff_profiles_display_name
    on admin.staff_profiles(lower(display_name), account_id);

alter table admin.staff_profiles enable row level security;
alter table admin.staff_profiles force row level security;

drop policy if exists lifemate_admin_runtime_select on admin.staff_profiles;
create policy lifemate_admin_runtime_select
on admin.staff_profiles for select to lifemate_admin_runtime
using (true);

drop policy if exists lifemate_admin_runtime_insert on admin.staff_profiles;
create policy lifemate_admin_runtime_insert
on admin.staff_profiles for insert to lifemate_admin_runtime
with check (true);

drop policy if exists lifemate_admin_runtime_update on admin.staff_profiles;
create policy lifemate_admin_runtime_update
on admin.staff_profiles for update to lifemate_admin_runtime
using (true)
with check (true);

revoke all on admin.staff_profiles from public;
do $$
declare v_role text;
begin
  foreach v_role in array array['anon','authenticated'] loop
    if exists (select 1 from pg_roles where rolname=v_role) then
      execute format('revoke all on admin.staff_profiles from %I', v_role);
    end if;
  end loop;
end
$$;

grant select, insert, update on admin.staff_profiles to lifemate_admin_runtime;

comment on table admin.staff_profiles is
  'Internal Command Center workforce aliases/display names. Contains no passwords, auth tokens, consumer profile or health data.';

insert into admin.permissions(code, domain, risk_level, role_assignable, description) values
('security.staff.manage','security','HIGH_RISK',true,'Invite, activate, disable and change ordinary Command Center staff role membership'),
('security.staff.audit.read','security','SENSITIVE',true,'Read privacy-minimized Command Center staff activity and access-change audit evidence')
on conflict (code) do update set
  domain=excluded.domain,
  risk_level=excluded.risk_level,
  role_assignable=excluded.role_assignable,
  description=excluded.description,
  updated_at_utc=now();

-- Founder-only in the first policy version. Super Admin does not inherit this merely
-- because it historically received all foundation permissions; any future delegation
-- requires an explicit reviewed migration.
insert into admin.role_permissions(role_id, permission_code)
select r.id, p.code
from admin.roles r
join admin.permissions p on p.code in ('security.staff.manage','security.staff.audit.read')
where r.code='founder' and r.status='Active'
on conflict do nothing;
