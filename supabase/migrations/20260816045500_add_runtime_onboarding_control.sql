-- Provider-independent operational control for pausing new LifeMate application
-- onboarding without redeploying the Edge runtime. Existing authenticated users
-- do not depend on this flag for normal healthcare operations.
create table if not exists security.runtime_controls (
  control_key text primary key,
  enabled boolean not null,
  updated_at_utc timestamptz not null default now(),
  note text null,
  constraint ck_runtime_controls_key
    check (control_key ~ '^[a-z][a-z0-9_]{2,63}$'),
  constraint ck_runtime_controls_note
    check (note is null or char_length(note) <= 240)
);

insert into security.runtime_controls(control_key, enabled, note)
values (
  'new_user_onboarding',
  true,
  'Operational beta onboarding gate; mutate only with an approved operator/admin database identity.'
)
on conflict (control_key) do nothing;

alter table security.runtime_controls enable row level security;
alter table security.runtime_controls force row level security;

drop policy if exists lifemate_edge_runtime_read_runtime_controls
  on security.runtime_controls;
create policy lifemate_edge_runtime_read_runtime_controls
  on security.runtime_controls
  for select
  to lifemate_edge_runtime
  using (control_key = 'new_user_onboarding');

revoke all on table security.runtime_controls from public;
revoke all on table security.runtime_controls from lifemate_edge_runtime;
grant select on table security.runtime_controls to lifemate_edge_runtime;

do $$
begin
  if exists (select 1 from pg_roles where rolname='anon') then
    execute 'revoke all on table security.runtime_controls from anon';
  end if;
  if exists (select 1 from pg_roles where rolname='authenticated') then
    execute 'revoke all on table security.runtime_controls from authenticated';
  end if;
end
$$;

create or replace function security.touch_runtime_control_updated_at()
returns trigger
language plpgsql
set search_path = pg_catalog, security
as $$
begin
  new.updated_at_utc := now();
  return new;
end;
$$;

revoke all on function security.touch_runtime_control_updated_at() from public;

drop trigger if exists trg_touch_runtime_control_updated_at
  on security.runtime_controls;
create trigger trg_touch_runtime_control_updated_at
before update on security.runtime_controls
for each row execute function security.touch_runtime_control_updated_at();

-- The application bootstrap already uses INSERT ... ON CONFLICT(auth_subject).
-- This trigger blocks only a genuinely new AppUser while permitting an existing
-- subject to take the idempotent conflict/update path during an onboarding pause.
-- SQLSTATE 55P03 is deliberately reused because the API already maps it to a
-- controlled temporary-unavailable 503 rather than leaking database details.
create or replace function security.enforce_new_user_onboarding_control()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, security, lifemate
as $$
declare
  onboarding_enabled boolean;
begin
  if exists (
    select 1
    from lifemate.app_users
    where auth_subject = new.auth_subject
  ) then
    return new;
  end if;

  select enabled
  into onboarding_enabled
  from security.runtime_controls
  where control_key = 'new_user_onboarding';

  if onboarding_enabled is distinct from true then
    raise exception 'new user onboarding is temporarily paused'
      using errcode = '55P03';
  end if;

  return new;
end;
$$;

revoke all on function security.enforce_new_user_onboarding_control()
  from public;

drop trigger if exists trg_enforce_new_user_onboarding_control
  on lifemate.app_users;
create trigger trg_enforce_new_user_onboarding_control
before insert on lifemate.app_users
for each row execute function security.enforce_new_user_onboarding_control();

comment on table security.runtime_controls is
  'LifeMate-owned provider-independent operational controls. Application runtime is read-only; operator/admin identity owns mutations.';
comment on column security.runtime_controls.enabled is
  'Current operational state. new_user_onboarding=false blocks new application bootstrap without affecting existing identities.';
comment on function security.enforce_new_user_onboarding_control() is
  'Fail-closed database boundary for new AppUser bootstrap; existing auth subjects retain the idempotent bootstrap path while onboarding is paused.';
