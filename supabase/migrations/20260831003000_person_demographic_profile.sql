alter table core.person_profiles
  add column if not exists gender_identity character varying(32) not null default 'NotCollected',
  add column if not exists gender_self_description character varying(120),
  add column if not exists sex_assigned_at_birth character varying(32) not null default 'NotCollected',
  add column if not exists demographics_updated_at_utc timestamptz;

alter table core.person_profiles
  drop constraint if exists person_profiles_gender_identity_check,
  add constraint person_profiles_gender_identity_check check (
    gender_identity in (
      'NotCollected',
      'Woman',
      'Man',
      'NonBinary',
      'SelfDescribe',
      'PreferNotToSay'
    )
  ),
  drop constraint if exists person_profiles_sex_assigned_at_birth_check,
  add constraint person_profiles_sex_assigned_at_birth_check check (
    sex_assigned_at_birth in (
      'NotCollected',
      'Female',
      'Male',
      'Intersex',
      'PreferNotToSay'
    )
  ),
  drop constraint if exists person_profiles_gender_self_description_check,
  add constraint person_profiles_gender_self_description_check check (
    (gender_identity = 'SelfDescribe'
      and gender_self_description is not null
      and length(btrim(gender_self_description)) between 1 and 120)
    or
    (gender_identity <> 'SelfDescribe' and gender_self_description is null)
  );

comment on column core.person_profiles.gender_identity is
  'Self-described demographic gender identity. NotCollected preserves existing-user compatibility; PreferNotToSay is a valid explicit answer.';
comment on column core.person_profiles.sex_assigned_at_birth is
  'Purpose-limited health demographic. Must not be substituted for gender identity in audience messaging.';
comment on column core.person_profiles.gender_self_description is
  'Optional self-description used only when gender_identity=SelfDescribe.';
comment on column core.person_profiles.demographics_updated_at_utc is
  'Last explicit demographic update time; null means never collected.';
