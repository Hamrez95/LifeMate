begin;

alter table lifemate.women_calendar_daily_logs
  add column if not exists period_flow character varying(16),
  add column if not exists blood_appearance character varying(24),
  add column if not exists blood_texture character varying(24),
  add column if not exists period_observation_schema_version smallint not null default 1;

alter table lifemate.women_calendar_daily_logs
  drop constraint if exists ck_women_daily_period_flow,
  add constraint ck_women_daily_period_flow check (
    period_flow is null or period_flow in ('light','medium','heavy')
  ),
  drop constraint if exists ck_women_daily_blood_appearance,
  add constraint ck_women_daily_blood_appearance check (
    blood_appearance is null or blood_appearance in (
      'bright_red','red','dark_red','brown'
    )
  ),
  drop constraint if exists ck_women_daily_blood_texture,
  add constraint ck_women_daily_blood_texture check (
    blood_texture is null or blood_texture in (
      'usual','watery','thick','clot_observed'
    )
  ),
  drop constraint if exists ck_women_daily_period_observation_schema_version,
  add constraint ck_women_daily_period_observation_schema_version check (
    period_observation_schema_version between 1 and 32
  );

comment on column lifemate.women_calendar_daily_logs.period_flow is
  'Optional user-recorded menstrual flow observation; structured, non-diagnostic canonical value.';
comment on column lifemate.women_calendar_daily_logs.blood_appearance is
  'Optional user-recorded blood appearance observation; structured, non-diagnostic canonical value.';
comment on column lifemate.women_calendar_daily_logs.blood_texture is
  'Optional user-recorded texture/consistency observation; structured, non-diagnostic canonical value.';
comment on column lifemate.women_calendar_daily_logs.period_observation_schema_version is
  'Version of the structured period-observation vocabulary. Existing rows default to v1.';

commit;
