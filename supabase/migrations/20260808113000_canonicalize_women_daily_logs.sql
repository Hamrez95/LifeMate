-- Preserve legacy profile-embedded daily state by copying it into the
-- canonical per-day log table. This is additive and idempotent; no legacy
-- column is removed in this release.
insert into lifemate.women_calendar_daily_logs (
    id, owner_user_id, logged_on, mood, energy_level, pain_level, symptoms,
    private_notes, share_summary_with_companion, version,
    created_at_utc, updated_at_utc
)
select
    gen_random_uuid(),
    p.owner_user_id,
    p.daily_check_in_date,
    coalesce(p.daily_mood, 'Neutral'),
    coalesce(p.daily_energy, 3),
    0,
    coalesce((
        select array_agg(mapped)::character varying(32)[]
        from (
            select distinct case lower(trim(value))
                when 'cramps' then 'Cramps'
                when 'headache' then 'Headache'
                when 'bloating' then 'Bloating'
                when 'fatigue' then 'Fatigue'
                when 'breast_tenderness' then 'BreastTenderness'
                when 'breasttenderness' then 'BreastTenderness'
                when 'back_pain' then 'BackPain'
                when 'backpain' then 'BackPain'
                when 'sleep_change' then 'SleepChange'
                when 'sleepchange' then 'SleepChange'
                when 'appetite_change' then 'AppetiteChange'
                when 'appetitechange' then 'AppetiteChange'
                when 'no_symptom' then 'NoSymptom'
                when 'nosymptom' then 'NoSymptom'
                else null
            end as mapped
            from unnest(p.daily_symptoms) value
        ) normalized
        where mapped is not null
    ), '{}'::character varying(32)[]),
    p.daily_private_note,
    p.share_daily_summary,
    1,
    coalesce(p.created_at_utc, now()),
    coalesce(p.updated_at_utc, now())
from lifemate.women_calendar_profiles p
where p.daily_check_in_date is not null
  and p.daily_mood is not null
on conflict (owner_user_id, logged_on) do nothing;

comment on column lifemate.women_calendar_profiles.daily_check_in_date is
'Legacy compatibility column. New daily wellbeing writes use women_calendar_daily_logs only.';
