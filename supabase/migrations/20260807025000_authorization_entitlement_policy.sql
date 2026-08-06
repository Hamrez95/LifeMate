-- Central policy composition and consent compatibility for current care writes.

create or replace function consent.sync_legacy_care_consent()
returns trigger
language plpgsql
set search_path = consent, lifemate, pg_temp
as $$
declare v_document_id uuid; v_record_id uuid; v_status character varying(24);
begin
  insert into consent.consent_documents(
    purpose,version,jurisdiction,title,status,effective_at_utc)
  values(
    'care_sharing',new.patient_consent_version,'*',
    'Care sharing consent','Active',new.patient_consented_at_utc)
  on conflict(purpose,version,jurisdiction) do update set status='Active'
  returning id into v_document_id;

  v_status := case when new.status='Active' then 'Granted' else 'Revoked' end;

  select id into v_record_id
  from consent.consent_records
  where subject_person_id=new.patient_user_id
    and purpose='care_sharing'
    and scope_key='care_relationship:'||new.id::text
  order by created_at_utc desc
  limit 1;

  if v_record_id is null then
    insert into consent.consent_records(
      subject_person_id,actor_account_id,document_id,purpose,scope_key,
      data_categories,jurisdiction,source,status,granted_at_utc,revoked_at_utc,
      created_at_utc,updated_at_utc)
    values(
      new.patient_user_id,new.patient_user_id,v_document_id,'care_sharing',
      'care_relationship:'||new.id::text,
      array['treatment','care_events','women_health_summary']::character varying[],
      '*','legacy_care_relationship',v_status,new.patient_consented_at_utc,
      case when v_status='Revoked' then coalesce(new.revoked_at_utc,now()) else null end,
      new.created_at_utc,new.updated_at_utc)
    returning id into v_record_id;

    insert into consent.consent_events(
      consent_record_id,actor_account_id,event_type,occurred_at_utc)
    values(
      v_record_id,new.patient_user_id,v_status,
      case when v_status='Granted' then new.patient_consented_at_utc else coalesce(new.revoked_at_utc,now()) end);
  else
    update consent.consent_records
       set document_id=v_document_id,
           status=v_status,
           revoked_at_utc=case when v_status='Revoked' then coalesce(new.revoked_at_utc,now()) else null end,
           updated_at_utc=new.updated_at_utc
     where id=v_record_id
       and status is distinct from v_status;

    if found then
      insert into consent.consent_events(
        consent_record_id,actor_account_id,event_type,occurred_at_utc)
      values(
        v_record_id,coalesce(new.revoked_by_user_id,new.patient_user_id),v_status,
        case when v_status='Granted' then new.patient_consented_at_utc else coalesce(new.revoked_at_utc,now()) end);
    end if;
  end if;
  return new;
end
$$;

drop trigger if exists trg_sync_legacy_care_consent on lifemate.care_relationships;
create trigger trg_sync_legacy_care_consent
after insert or update of status,patient_consent_version,patient_consented_at_utc,revoked_at_utc,updated_at_utc
on lifemate.care_relationships
for each row execute function consent.sync_legacy_care_consent();

create or replace function security.can_access_person_feature(
    p_grantee_account_id uuid,
    p_subject_person_id uuid,
    p_scope character varying,
    p_feature_code character varying,
    p_consent_purpose character varying default 'care_sharing',
    p_at_utc timestamp with time zone default now()
) returns boolean
language sql
stable
set search_path = security, core, consent, commerce, pg_temp
as $$
  select commerce.has_entitlement(
           p_grantee_account_id,p_subject_person_id,p_feature_code,p_at_utc)
     and (
       exists(
         select 1 from core.account_person_links l
         where l.account_id=p_grantee_account_id
           and l.person_id=p_subject_person_id
           and l.link_type='Self'
           and l.status='Active'
       )
       or (
         security.has_scope(
           p_grantee_account_id,p_subject_person_id,p_scope,p_at_utc)
         and exists(
           select 1 from consent.consent_records c
           where c.subject_person_id=p_subject_person_id
             and c.purpose=p_consent_purpose
             and c.status='Granted'
             and c.granted_at_utc <= p_at_utc
             and (c.expires_at_utc is null or c.expires_at_utc > p_at_utc)
         )
       )
     )
$$;

-- Provenance values are typed policy inputs rather than free-form labels.
do $migration$
declare t text; constraint_name text;
begin
  foreach t in array array[
    'medications','treatment_plans','dose_occurrences','dose_adherence_events',
    'care_events','women_calendar_episodes','women_calendar_daily_logs'
  ] loop
    constraint_name := 'ck_'||t||'_provenance_source';
    if not exists(
      select 1 from pg_constraint c
      join pg_class r on r.oid=c.conrelid
      join pg_namespace n on n.oid=r.relnamespace
      where c.conname=constraint_name and n.nspname='lifemate' and r.relname=t
    ) then
      execute format(
        'alter table lifemate.%I add constraint %I check (provenance_source in (%L,%L,%L,%L,%L,%L,%L,%L))',
        t,constraint_name,
        'FirstPartyUserInput','CaregiverInput','ClinicianInput','DeviceSensor',
        'HealthConnect','ImportedProvider','PartnerIntegration','SystemGenerated'
      );
    end if;
  end loop;
end
$migration$;

revoke execute on function security.can_access_person_feature(uuid,uuid,character varying,character varying,character varying,timestamp with time zone) from public;
revoke execute on function consent.sync_legacy_care_consent() from public;
