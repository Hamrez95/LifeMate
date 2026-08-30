begin;

create table if not exists lifemate.women_cycle_insight_preferences (
  owner_person_id uuid primary key references core.persons(id) on delete cascade,
  insights_enabled boolean not null default true,
  notifications_enabled boolean not null default false,
  expected_period_notifications boolean not null default true,
  logging_reminder_notifications boolean not null default true,
  frequency_mode character varying(16) not null default 'balanced',
  version integer not null default 1,
  created_at_utc timestamptz not null default now(),
  updated_at_utc timestamptz not null default now(),
  constraint ck_women_cycle_insight_frequency check (
    frequency_mode in ('low','balanced','high')
  ),
  constraint ck_women_cycle_insight_version check (version >= 1)
);

create table if not exists lifemate.women_cycle_insight_history (
  id uuid primary key default gen_random_uuid(),
  owner_person_id uuid not null references core.persons(id) on delete cascade,
  insight_id character varying(120) not null,
  insight_type character varying(40) not null,
  rule_version character varying(40) not null,
  surface character varying(24) not null,
  analytics_key character varying(80) not null,
  occurred_on date not null default current_date,
  occurred_at_utc timestamptz not null default now(),
  created_at_utc timestamptz not null default now(),
  constraint ck_women_cycle_insight_id check (length(trim(insight_id)) between 1 and 120),
  constraint ck_women_cycle_insight_type check (
    insight_type in (
      'expected_period_window',
      'recurring_symptom_pattern',
      'logging_reminder',
      'cycle_history_observation'
    )
  ),
  constraint ck_women_cycle_insight_surface check (
    surface in ('in_app','local_notification','remote_notification')
  ),
  constraint ck_women_cycle_insight_rule_version check (
    length(trim(rule_version)) between 1 and 40
  ),
  constraint ck_women_cycle_insight_analytics_key check (
    length(trim(analytics_key)) between 1 and 80
  )
);

create unique index if not exists ux_women_cycle_insight_daily_dedup
  on lifemate.women_cycle_insight_history(owner_person_id, insight_id, surface, occurred_on);
create index if not exists ix_women_cycle_insight_history_person_time
  on lifemate.women_cycle_insight_history(owner_person_id, occurred_at_utc desc);

alter table lifemate.women_cycle_insight_preferences enable row level security;
alter table lifemate.women_cycle_insight_preferences force row level security;
alter table lifemate.women_cycle_insight_history enable row level security;
alter table lifemate.women_cycle_insight_history force row level security;

revoke all on table lifemate.women_cycle_insight_preferences from public;
revoke all on table lifemate.women_cycle_insight_history from public;

do $$
declare v_role text;
begin
  foreach v_role in array array['anon','authenticated','service_role'] loop
    if exists(select 1 from pg_roles where rolname = v_role) then
      execute format('revoke all on table lifemate.women_cycle_insight_preferences from %I', v_role);
      execute format('revoke all on table lifemate.women_cycle_insight_history from %I', v_role);
    end if;
  end loop;
end $$;

comment on table lifemate.women_cycle_insight_preferences is
  'Self-owned Cycle Insight controls. Notification permission remains separate from in-app insight availability.';
comment on table lifemate.women_cycle_insight_history is
  'Privacy-safe Cycle Insight delivery/impression metadata only. Raw symptoms, pain, private notes, fertility details and rendered copy are forbidden.';

commit;