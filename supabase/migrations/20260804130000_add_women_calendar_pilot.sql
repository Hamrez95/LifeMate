alter table lifemate.care_relationships
    add column if not exists can_view_women_calendar boolean not null default false;

create table if not exists lifemate.women_calendar_profiles (
    owner_user_id uuid primary key references lifemate.app_users(id) on delete cascade,
    enabled boolean not null default false,
    last_period_start date,
    cycle_length integer not null default 28,
    period_length integer not null default 5,
    reminders_enabled boolean not null default true,
    algorithm_version character varying(32) not null default 'calendar-estimate-v1',
    version integer not null default 1,
    created_at_utc timestamp with time zone not null,
    updated_at_utc timestamp with time zone not null,
    constraint ck_women_calendar_cycle_length check (cycle_length between 21 and 45),
    constraint ck_women_calendar_period_length check (
        period_length between 1 and 10 and period_length < cycle_length
    ),
    constraint ck_women_calendar_profile_version check (version > 0),
    constraint ck_women_calendar_enabled_start check (
        enabled = false or last_period_start is not null
    )
);

create table if not exists lifemate.women_calendar_episodes (
    id uuid primary key,
    owner_user_id uuid not null references lifemate.app_users(id) on delete cascade,
    started_on date not null,
    ended_on date,
    private_notes character varying(500),
    version integer not null default 1,
    created_at_utc timestamp with time zone not null,
    updated_at_utc timestamp with time zone not null,
    constraint ck_women_calendar_episode_range check (
        ended_on is null or ended_on >= started_on
    ),
    constraint ck_women_calendar_episode_version check (version > 0),
    constraint uq_women_calendar_episode_start unique (owner_user_id, started_on)
);

create index if not exists ix_women_calendar_episodes_owner_start
    on lifemate.women_calendar_episodes(owner_user_id, started_on desc);

create table if not exists lifemate.women_calendar_support_actions (
    id uuid primary key,
    patient_user_id uuid not null references lifemate.app_users(id) on delete cascade,
    caregiver_user_id uuid not null references lifemate.app_users(id) on delete cascade,
    relationship_id uuid not null references lifemate.care_relationships(id) on delete cascade,
    action_type character varying(32) not null,
    performed_at_utc timestamp with time zone not null,
    created_at_utc timestamp with time zone not null,
    constraint ck_women_calendar_support_action_type check (
        action_type in ('Hydration', 'Rest', 'Warmth', 'Chores')
    )
);

create index if not exists ix_women_calendar_support_patient_time
    on lifemate.women_calendar_support_actions(patient_user_id, performed_at_utc desc);

do $migration$
begin
    if exists (select 1 from pg_roles where rolname = 'anon') then
        execute 'revoke all privileges on table lifemate.women_calendar_profiles from anon';
        execute 'revoke all privileges on table lifemate.women_calendar_episodes from anon';
        execute 'revoke all privileges on table lifemate.women_calendar_support_actions from anon';
    end if;
    if exists (select 1 from pg_roles where rolname = 'authenticated') then
        execute 'revoke all privileges on table lifemate.women_calendar_profiles from authenticated';
        execute 'revoke all privileges on table lifemate.women_calendar_episodes from authenticated';
        execute 'revoke all privileges on table lifemate.women_calendar_support_actions from authenticated';
    end if;
    if exists (select 1 from pg_roles where rolname = 'service_role') then
        execute 'revoke all privileges on table lifemate.women_calendar_profiles from service_role';
        execute 'revoke all privileges on table lifemate.women_calendar_episodes from service_role';
        execute 'revoke all privileges on table lifemate.women_calendar_support_actions from service_role';
    end if;
end
$migration$;

comment on column lifemate.care_relationships.can_view_women_calendar is
'Owner-controlled, independent consent scope for the women calendar summary.';
comment on table lifemate.women_calendar_profiles is
'Owner-only women calendar settings and deterministic estimate inputs.';
comment on column lifemate.women_calendar_episodes.private_notes is
'Never returned to caregivers.';
