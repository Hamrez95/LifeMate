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

comment on table security.runtime_controls is
  'LifeMate-owned provider-independent operational controls. Application runtime is read-only; operator/admin identity owns mutations.';
comment on column security.runtime_controls.enabled is
  'Current operational state. new_user_onboarding=false blocks new application bootstrap without affecting existing identities.';
