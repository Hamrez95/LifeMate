alter table lifemate.women_calendar_profiles
    add column if not exists daily_check_in_date date,
    add column if not exists daily_mood character varying(24),
    add column if not exists daily_energy integer,
    add column if not exists daily_symptoms text[] not null default '{}',
    add column if not exists daily_support_need character varying(24),
    add column if not exists daily_private_note character varying(500),
    add column if not exists share_daily_summary boolean not null default false;

alter table lifemate.women_calendar_profiles
    drop constraint if exists ck_women_calendar_daily_mood,
    add constraint ck_women_calendar_daily_mood check (
        daily_mood is null or daily_mood in (
            'Great', 'Good', 'Neutral', 'Low', 'Overwhelmed'
        )
    ),
    drop constraint if exists ck_women_calendar_daily_energy,
    add constraint ck_women_calendar_daily_energy check (
        daily_energy is null or daily_energy between 1 and 5
    ),
    drop constraint if exists ck_women_calendar_daily_support_need,
    add constraint ck_women_calendar_daily_support_need check (
        daily_support_need is null or daily_support_need in (
            'None', 'Rest', 'Talk', 'Space', 'Warmth', 'Walk', 'Hug'
        )
    ),
    drop constraint if exists ck_women_calendar_daily_symptoms_count,
    add constraint ck_women_calendar_daily_symptoms_count check (
        coalesce(array_length(daily_symptoms, 1), 0) <= 8
    );

alter table lifemate.women_calendar_support_actions
    drop constraint if exists ck_women_calendar_support_action_type,
    add constraint ck_women_calendar_support_action_type check (
        action_type in (
            'Hydration', 'Rest', 'Warmth', 'Chores',
            'Message', 'Hug', 'Walk', 'Tea'
        )
    );

comment on column lifemate.women_calendar_profiles.daily_check_in_date is
'Owner local date for the current private daily cycle check-in.';
comment on column lifemate.women_calendar_profiles.daily_symptoms is
'Owner-only symptom codes. Never exposed to caregivers by the API.';
comment on column lifemate.women_calendar_profiles.daily_private_note is
'Owner-only note. Never exposed to caregivers by the API.';
comment on column lifemate.women_calendar_profiles.share_daily_summary is
'Explicit owner consent to share only mood, energy and support need with authorized caregivers.';
