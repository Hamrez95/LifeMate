create table if not exists lifemate.women_calendar_daily_logs (
    id uuid primary key,
    owner_user_id uuid not null references lifemate.app_users(id) on delete cascade,
    logged_on date not null,
    mood character varying(24) not null,
    energy_level smallint not null,
    pain_level smallint not null,
    symptoms character varying(32)[] not null default '{}',
    private_notes character varying(500),
    share_summary_with_companion boolean not null default false,
    version integer not null default 1,
    created_at_utc timestamp with time zone not null,
    updated_at_utc timestamp with time zone not null,
    constraint uq_women_calendar_daily_log unique (owner_user_id, logged_on),
    constraint ck_women_calendar_daily_log_mood check (
        mood in ('Great', 'Good', 'Neutral', 'Low', 'Overwhelmed')
    ),
    constraint ck_women_calendar_daily_log_energy check (energy_level between 1 and 5),
    constraint ck_women_calendar_daily_log_pain check (pain_level between 0 and 5),
    constraint ck_women_calendar_daily_log_symptoms check (
        cardinality(symptoms) <= 8 and symptoms <@ array[
            'Cramps', 'Headache', 'Bloating', 'Fatigue', 'BreastTenderness',
            'BackPain', 'SleepChange', 'AppetiteChange', 'NoSymptom'
        ]::character varying[]
    ),
    constraint ck_women_calendar_daily_log_version check (version > 0)
);

create index if not exists ix_women_calendar_daily_logs_owner_date
    on lifemate.women_calendar_daily_logs(owner_user_id, logged_on desc);

create index if not exists ix_women_calendar_daily_logs_shared_date
    on lifemate.women_calendar_daily_logs(owner_user_id, logged_on desc)
    where share_summary_with_companion = true;

alter table lifemate.women_calendar_support_actions
    drop constraint if exists ck_women_calendar_support_action_type;

alter table lifemate.women_calendar_support_actions
    add constraint ck_women_calendar_support_action_type check (
        action_type in (
            'Hydration', 'Rest', 'Warmth', 'Chores', 'Walk', 'CheckIn'
        )
    );

do $migration$
begin
    if exists (select 1 from pg_roles where rolname = 'anon') then
        execute 'revoke all privileges on table lifemate.women_calendar_daily_logs from anon';
    end if;
    if exists (select 1 from pg_roles where rolname = 'authenticated') then
        execute 'revoke all privileges on table lifemate.women_calendar_daily_logs from authenticated';
    end if;
    if exists (select 1 from pg_roles where rolname = 'service_role') then
        execute 'revoke all privileges on table lifemate.women_calendar_daily_logs from service_role';
    end if;
end
$migration$;

comment on table lifemate.women_calendar_daily_logs is
'Owner daily wellbeing log. Only explicitly shared summaries may be returned to an authorized companion.';
comment on column lifemate.women_calendar_daily_logs.private_notes is
'Owner-only text. It must never be returned in caregiver endpoints or audit metadata.';
comment on column lifemate.women_calendar_daily_logs.share_summary_with_companion is
'Per-entry owner consent for sharing mood, energy, pain and selected symptom codes only.';
