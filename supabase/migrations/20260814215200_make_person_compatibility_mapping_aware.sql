-- Provider-agnostic compatibility trigger functions.
-- Resolver helpers are created by the preceding 20260814215150 migration so a
-- fresh restore compiles these PL/pgSQL functions against existing dependencies.

-- User-profile compatibility projection must follow the mapped Self Person; a
-- provider-agnostic Account UUID is not required to equal either AppUser or Person.
create or replace function core.sync_legacy_user_profile()
returns trigger
language plpgsql
set search_path = pg_catalog, core, pg_temp
as $$
declare
  v_person_id uuid;
begin
  v_person_id := core.self_person_id_for_legacy_app_user(new.user_id);
  if v_person_id is null then
    raise exception 'legacy_profile_self_person_missing';
  end if;

  insert into core.person_profiles(
    person_id,display_name,locale,time_zone,avatar_key,profile_photo_path,
    created_at_utc,updated_at_utc
  )
  values(
    v_person_id,new.display_name,new.locale,new.time_zone,new.avatar_key,
    new.profile_photo_path,new.created_at_utc,new.updated_at_utc
  )
  on conflict(person_id) do update set
    display_name=excluded.display_name,
    locale=excluded.locale,
    time_zone=excluded.time_zone,
    avatar_key=excluded.avatar_key,
    profile_photo_path=excluded.profile_photo_path,
    updated_at_utc=excluded.updated_at_utc;
  return new;
end
$$;

-- Legacy healthcare writers may still send only *_user_id. Resolve Person via
-- the explicit bridge instead of copying the AppUser UUID into a Person FK.
--
-- Keep table dispatch separate from table-specific NEW field access. PostgreSQL
-- records are shaped by the trigger table, so a condition such as
-- `tg_table_name='medications' and new.owner_person_id is null` is unsafe when
-- this shared trigger executes for a table that has no owner_person_id field.
create or replace function core.sync_health_person_id()
returns trigger
language plpgsql
set search_path = pg_catalog, core, pg_temp
as $$
declare
  v_legacy_user_id uuid;
  v_person_id uuid;
begin
  if tg_table_name='medications' then
    if new.owner_person_id is not null then
      return new;
    end if;
    v_legacy_user_id := new.owner_user_id;
  elsif tg_table_name='treatment_plans' then
    if new.patient_person_id is not null then
      return new;
    end if;
    v_legacy_user_id := new.patient_user_id;
  elsif tg_table_name='dose_occurrences' then
    if new.patient_person_id is not null then
      return new;
    end if;
    v_legacy_user_id := new.patient_user_id;
  elsif tg_table_name='care_events' then
    if new.patient_person_id is not null then
      return new;
    end if;
    v_legacy_user_id := new.patient_user_id;
  elsif tg_table_name='women_calendar_profiles' then
    if new.owner_person_id is not null then
      return new;
    end if;
    v_legacy_user_id := new.owner_user_id;
  elsif tg_table_name='women_calendar_episodes' then
    if new.owner_person_id is not null then
      return new;
    end if;
    v_legacy_user_id := new.owner_user_id;
  elsif tg_table_name='women_calendar_daily_logs' then
    if new.owner_person_id is not null then
      return new;
    end if;
    v_legacy_user_id := new.owner_user_id;
  elsif tg_table_name='women_calendar_support_actions' then
    if new.patient_person_id is not null then
      return new;
    end if;
    v_legacy_user_id := new.patient_user_id;
  else
    return new;
  end if;

  if v_legacy_user_id is null then
    raise exception 'legacy_health_owner_user_missing';
  end if;

  v_person_id := core.self_person_id_for_legacy_app_user(v_legacy_user_id);
  if v_person_id is null then
    raise exception 'legacy_health_self_person_missing';
  end if;

  if tg_table_name='medications' then
    new.owner_person_id := v_person_id;
  elsif tg_table_name='treatment_plans' then
    new.patient_person_id := v_person_id;
  elsif tg_table_name='dose_occurrences' then
    new.patient_person_id := v_person_id;
  elsif tg_table_name='care_events' then
    new.patient_person_id := v_person_id;
  elsif tg_table_name='women_calendar_profiles' then
    new.owner_person_id := v_person_id;
  elsif tg_table_name='women_calendar_episodes' then
    new.owner_person_id := v_person_id;
  elsif tg_table_name='women_calendar_daily_logs' then
    new.owner_person_id := v_person_id;
  elsif tg_table_name='women_calendar_support_actions' then
    new.patient_person_id := v_person_id;
  end if;
  return new;
end
$$;

-- Care grants must authorize the mapped caregiver Account against the mapped
-- patient Person. Using legacy user UUIDs here would silently break isolation as
-- soon as provider identities are decoupled.
create or replace function security.sync_legacy_care_access()
returns trigger
language plpgsql
set search_path = pg_catalog, security, identity, core, lifemate, pg_temp
as $$
declare
  v_grant_id uuid;
  v_patient_person_id uuid;
  v_caregiver_account_id uuid;
begin
  v_patient_person_id := core.self_person_id_for_legacy_app_user(new.patient_user_id);
  v_caregiver_account_id := identity.account_id_for_legacy_app_user(new.caregiver_user_id);

  if v_patient_person_id is null or v_caregiver_account_id is null then
    raise exception 'legacy_care_bridge_missing';
  end if;

  insert into security.access_grants(
    subject_person_id,grantee_account_id,grantor_person_id,
    context_type,context_id,status,starts_at_utc,expires_at_utc,
    revoked_at_utc,created_at_utc,updated_at_utc
  )
  values(
    v_patient_person_id,v_caregiver_account_id,v_patient_person_id,
    'care_relationship',new.id,
    case when new.status='Active' then 'Active' else 'Revoked' end,
    new.created_at_utc,null,
    case when new.status='Active' then null else coalesce(new.revoked_at_utc,now()) end,
    new.created_at_utc,new.updated_at_utc
  )
  on conflict(subject_person_id,grantee_account_id,context_type,context_id)
  do update set
    status=excluded.status,
    revoked_at_utc=excluded.revoked_at_utc,
    updated_at_utc=excluded.updated_at_utc
  returning id into v_grant_id;

  if new.status='Active' then
    insert into security.access_grant_scopes(grant_id,scope)
    select v_grant_id,scope from (values
      ('treatment.medication.read'),('treatment.plan.read'),
      ('treatment.adherence.read'),('care.events.read')
    ) s(scope)
    on conflict do nothing;

    if coalesce(new.can_view_women_calendar,false) then
      insert into security.access_grant_scopes(grant_id,scope)
      values
        (v_grant_id,'women_health.summary.read'),
        (v_grant_id,'women_health.support.write')
      on conflict do nothing;
    else
      delete from security.access_grant_scopes s
      where s.grant_id=v_grant_id
        and s.scope in (
          'women_health.summary.read',
          'women_health.support.write',
          'women_health.daily.read'
        );
    end if;
  else
    delete from security.access_grant_scopes s where s.grant_id=v_grant_id;
  end if;
  return new;
end
$$;

-- The legacy care relationship remains the compatibility write model for
-- consent, but consent authority belongs to provider-agnostic Account/Person
-- identities. A patient AppUser resolves to the patient's Account and active
-- Self Person. A revoker AppUser resolves independently to the Account that
-- performed the revocation; raw AppUser UUIDs are never written into Account or
-- Person foreign keys.
create or replace function consent.sync_legacy_care_consent()
returns trigger
language plpgsql
set search_path = pg_catalog, consent, identity, core, lifemate, pg_temp
as $$
declare
  v_document_id uuid;
  v_record_id uuid;
  v_status character varying(24);
  v_patient_account_id uuid;
  v_patient_person_id uuid;
  v_event_actor_account_id uuid;
begin
  v_patient_account_id := identity.account_id_for_legacy_app_user(new.patient_user_id);
  v_patient_person_id := core.self_person_id_for_legacy_app_user(new.patient_user_id);

  if v_patient_account_id is null or v_patient_person_id is null then
    raise exception 'legacy_care_patient_bridge_missing';
  end if;

  v_status := case when new.status='Active' then 'Granted' else 'Revoked' end;
  v_event_actor_account_id := v_patient_account_id;

  if v_status='Revoked' and new.revoked_by_user_id is not null then
    v_event_actor_account_id := identity.account_id_for_legacy_app_user(new.revoked_by_user_id);
    if v_event_actor_account_id is null then
      raise exception 'legacy_care_revoker_bridge_missing';
    end if;
  end if;

  insert into consent.consent_documents(
    purpose,version,jurisdiction,title,status,effective_at_utc
  )
  values(
    'care_sharing',new.patient_consent_version,'*',
    'Care sharing consent','Active',new.patient_consented_at_utc
  )
  on conflict(purpose,version,jurisdiction) do update set status='Active'
  returning id into v_document_id;

  select id into v_record_id
  from consent.consent_records
  where subject_person_id=v_patient_person_id
    and purpose='care_sharing'
    and scope_key='care_relationship:'||new.id::text
  order by created_at_utc desc
  limit 1;

  if v_record_id is null then
    insert into consent.consent_records(
      subject_person_id,actor_account_id,document_id,purpose,scope_key,
      data_categories,jurisdiction,source,status,granted_at_utc,revoked_at_utc,
      created_at_utc,updated_at_utc
    )
    values(
      v_patient_person_id,v_patient_account_id,v_document_id,'care_sharing',
      'care_relationship:'||new.id::text,
      array['treatment','care_events','women_health_summary']::character varying[],
      '*','legacy_care_relationship',v_status,new.patient_consented_at_utc,
      case when v_status='Revoked' then coalesce(new.revoked_at_utc,now()) else null end,
      new.created_at_utc,new.updated_at_utc
    )
    returning id into v_record_id;

    insert into consent.consent_events(
      consent_record_id,actor_account_id,event_type,occurred_at_utc
    )
    values(
      v_record_id,v_event_actor_account_id,v_status,
      case when v_status='Granted'
        then new.patient_consented_at_utc
        else coalesce(new.revoked_at_utc,now())
      end
    );
  else
    update consent.consent_records
       set document_id=v_document_id,
           status=v_status,
           revoked_at_utc=case
             when v_status='Revoked' then coalesce(new.revoked_at_utc,now())
             else null
           end,
           updated_at_utc=new.updated_at_utc
     where id=v_record_id
       and status is distinct from v_status;

    if found then
      insert into consent.consent_events(
        consent_record_id,actor_account_id,event_type,occurred_at_utc
      )
      values(
        v_record_id,v_event_actor_account_id,v_status,
        case when v_status='Granted'
          then new.patient_consented_at_utc
          else coalesce(new.revoked_at_utc,now())
        end
      );
    end if;
  end if;
  return new;
end
$$;

revoke execute on function consent.sync_legacy_care_consent() from public;
