begin;

alter table lifemate.women_calendar_daily_logs
  add column if not exists symptom_observations jsonb not null default '[]'::jsonb,
  add column if not exists symptom_schema_version smallint not null default 1;

alter table lifemate.women_calendar_daily_logs
  drop constraint if exists ck_women_daily_symptom_observations_array,
  add constraint ck_women_daily_symptom_observations_array check (
    jsonb_typeof(symptom_observations) = 'array'
    and jsonb_array_length(symptom_observations) <= 16
  ),
  drop constraint if exists ck_women_daily_symptom_schema_version,
  add constraint ck_women_daily_symptom_schema_version check (
    symptom_schema_version between 1 and 32
  );

comment on column lifemate.women_calendar_daily_logs.symptom_observations is
  'Structured canonical Women Health symptom observations. Each item uses a language-neutral catalog id and optional 1..5 severity. Existing symptoms[] remains compatibility input during migration.';
comment on column lifemate.women_calendar_daily_logs.symptom_schema_version is
  'Version of the canonical Women Health symptom vocabulary/observation schema.';

commit;