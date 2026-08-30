begin;

create table if not exists lifemate.women_health_lifecycle (
  owner_person_id uuid primary key references core.persons(id) on delete cascade,
  lifecycle_state character varying(32) not null default 'active',
  pause_reason character varying(32),
  cocoon_activation_source character varying(32),
  paused_at_utc timestamptz,
  pregnancy_mode_activated_at_utc timestamptz,
  postpartum_at_utc timestamptz,
  resumable_at_utc timestamptz,
  resumed_at_utc timestamptz,
  version integer not null default 1,
  created_at_utc timestamptz not null default now(),
  updated_at_utc timestamptz not null default now(),
  constraint ck_women_health_lifecycle_state check (
    lifecycle_state in (
      'active',
      'paused_for_pregnancy',
      'postpartum_recovery',
      'resumable'
    )
  ),
  constraint ck_women_health_pause_reason check (
    pause_reason is null or pause_reason in ('pregnancy')
  ),
  constraint ck_women_health_lifecycle_version check (version >= 1),
  constraint ck_women_health_pregnancy_pause_consistency check (
    lifecycle_state <> 'paused_for_pregnancy'
    or (
      pause_reason = 'pregnancy'
      and paused_at_utc is not null
      and pregnancy_mode_activated_at_utc is not null
    )
  )
);

create table if not exists lifemate.women_health_lifecycle_events (
  id uuid primary key default gen_random_uuid(),
  owner_person_id uuid not null references core.persons(id) on delete cascade,
  from_state character varying(32),
  to_state character varying(32) not null,
  reason character varying(32),
  idempotency_key character varying(120) not null,
  actor_account_id uuid references identity.accounts(id) on delete set null,
  occurred_at_utc timestamptz not null default now(),
  created_at_utc timestamptz not null default now(),
  constraint ck_women_lifecycle_event_to_state check (
    to_state in ('active','paused_for_pregnancy','postpartum_recovery','resumable')
  ),
  constraint ck_women_lifecycle_event_from_state check (
    from_state is null or from_state in ('active','paused_for_pregnancy','postpartum_recovery','resumable')
  ),
  constraint ck_women_lifecycle_event_reason check (
    reason is null or reason in ('pregnancy','postpartum','explicit_resume')
  ),
  constraint ck_women_lifecycle_event_idempotency check (
    length(btrim(idempotency_key)) between 8 and 120
  )
);

create unique index if not exists ux_women_lifecycle_event_idempotency
  on lifemate.women_health_lifecycle_events(owner_person_id, idempotency_key);
create index if not exists ix_women_lifecycle_event_person_time
  on lifemate.women_health_lifecycle_events(owner_person_id, occurred_at_utc desc);

alter table lifemate.women_health_lifecycle enable row level security;
alter table lifemate.women_health_lifecycle force row level security;
alter table lifemate.women_health_lifecycle_events enable row level security;
alter table lifemate.women_health_lifecycle_events force row level security;

revoke all on table lifemate.women_health_lifecycle from public;
revoke all on table lifemate.women_health_lifecycle_events from public;

do $$
declare v_role text;
begin
  foreach v_role in array array['anon','authenticated','service_role'] loop
    if exists(select 1 from pg_roles where rolname=v_role) then
      execute format('revoke all on table lifemate.women_health_lifecycle from %I', v_role);
      execute format('revoke all on table lifemate.women_health_lifecycle_events from %I', v_role);
    end if;
  end loop;
end $$;

comment on table lifemate.women_health_lifecycle is
  'Person-scoped Women Health lifecycle. Pregnancy pauses predictions/reminders without deleting historical cycle data or changing consent.';
comment on column lifemate.women_health_lifecycle.cocoon_activation_source is
  'Commercial/product transition provenance only; never grants CocoonMate entitlement.';

commit;