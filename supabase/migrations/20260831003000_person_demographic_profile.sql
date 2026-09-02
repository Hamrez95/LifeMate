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

create or replace function public.get_my_demographics()
returns table (
  gender_identity character varying,
  gender_self_description character varying,
  sex_assigned_at_birth character varying,
  demographics_updated_at_utc timestamptz
)
language plpgsql
security definer
set search_path = pg_catalog, public, lifemate, core
as $$
declare
  v_auth_subject uuid;
  v_app_user_id uuid;
  v_person_id uuid;
begin
  v_auth_subject := nullif(current_setting('request.jwt.claim.sub', true), '')::uuid;

  select u.id into v_app_user_id
  from lifemate.app_users u
  where u.auth_subject = v_auth_subject
    and u.status = 'Active'
  limit 1;

  if v_app_user_id is null then
    raise exception 'not_onboarded' using errcode = 'P0001';
  end if;

  select core.self_person_id_for_legacy_app_user(v_app_user_id)
    into v_person_id;

  if v_person_id is null then
    raise exception 'identity_person_mapping_missing' using errcode = 'P0001';
  end if;

  return query
  select p.gender_identity,
         p.gender_self_description,
         p.sex_assigned_at_birth,
         p.demographics_updated_at_utc
  from core.person_profiles p
  where p.person_id = v_person_id;
end;
$$;

create or replace function public.set_my_demographics(
  p_gender_identity character varying,
  p_gender_self_description character varying default null,
  p_sex_assigned_at_birth character varying default 'PreferNotToSay'
)
returns table (
  gender_identity character varying,
  gender_self_description character varying,
  sex_assigned_at_birth character varying,
  demographics_updated_at_utc timestamptz
)
language plpgsql
security definer
set search_path = pg_catalog, public, lifemate, core
as $$
declare
  v_auth_subject uuid;
  v_app_user_id uuid;
  v_person_id uuid;
  v_gender_identity character varying(32);
  v_gender_self_description character varying(120);
  v_sex_assigned_at_birth character varying(32);
begin
  v_gender_identity := btrim(coalesce(p_gender_identity, ''));
  v_sex_assigned_at_birth := btrim(coalesce(p_sex_assigned_at_birth, ''));
  v_gender_self_description := nullif(btrim(coalesce(p_gender_self_description, '')), '');

  if v_gender_identity not in ('Woman','Man','NonBinary','SelfDescribe','PreferNotToSay') then
    raise exception 'invalid_gender_identity' using errcode = '22023';
  end if;
  if v_sex_assigned_at_birth not in ('Female','Male','Intersex','PreferNotToSay') then
    raise exception 'invalid_sex_assigned_at_birth' using errcode = '22023';
  end if;
  if v_gender_identity = 'SelfDescribe' then
    if v_gender_self_description is null or length(v_gender_self_description) > 120 then
      raise exception 'invalid_gender_self_description' using errcode = '22023';
    end if;
  else
    v_gender_self_description := null;
  end if;

  v_auth_subject := nullif(current_setting('request.jwt.claim.sub', true), '')::uuid;

  select u.id into v_app_user_id
  from lifemate.app_users u
  where u.auth_subject = v_auth_subject
    and u.status = 'Active'
  limit 1;

  if v_app_user_id is null then
    raise exception 'not_onboarded' using errcode = 'P0001';
  end if;

  select core.self_person_id_for_legacy_app_user(v_app_user_id)
    into v_person_id;

  if v_person_id is null then
    raise exception 'identity_person_mapping_missing' using errcode = 'P0001';
  end if;

  update core.person_profiles p
  set gender_identity = v_gender_identity,
      gender_self_description = v_gender_self_description,
      sex_assigned_at_birth = v_sex_assigned_at_birth,
      demographics_updated_at_utc = now(),
      updated_at_utc = now()
  where p.person_id = v_person_id;

  insert into lifemate.audit_logs(
    id, actor_user_id, action, resource_type, resource_id,
    metadata_json, created_at_utc
  ) values (
    gen_random_uuid(), v_app_user_id, 'profile.demographics_updated',
    'person_profile', v_person_id, null, now()
  );

  return query
  select p.gender_identity,
         p.gender_self_description,
         p.sex_assigned_at_birth,
         p.demographics_updated_at_utc
  from core.person_profiles p
  where p.person_id = v_person_id;
end;
$$;

revoke all on function public.get_my_demographics() from public, anon;
revoke all on function public.set_my_demographics(character varying, character varying, character varying) from public, anon;
grant execute on function public.get_my_demographics() to authenticated;
grant execute on function public.set_my_demographics(character varying, character varying, character varying) to authenticated;
