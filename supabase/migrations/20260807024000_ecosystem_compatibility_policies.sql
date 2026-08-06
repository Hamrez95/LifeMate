-- Compatibility and centralized policy helpers for the ecosystem foundation.
-- These triggers keep the current Edge API contract working while the mobile
-- clients and API migrate away from legacy AppUser/relationship permission fields.

create or replace function security.has_scope(
    p_grantee_account_id uuid,
    p_subject_person_id uuid,
    p_scope character varying,
    p_at_utc timestamp with time zone default now()
) returns boolean
language sql
stable
set search_path = security, pg_temp
as $$
  select exists (
    select 1
    from security.access_grants g
    join security.access_grant_scopes s on s.grant_id=g.id
    where g.grantee_account_id=p_grantee_account_id
      and g.subject_person_id=p_subject_person_id
      and g.status='Active'
      and g.starts_at_utc <= p_at_utc
      and (g.expires_at_utc is null or g.expires_at_utc > p_at_utc)
      and s.scope=p_scope
  )
$$;

create or replace function commerce.has_entitlement(
    p_grantee_account_id uuid,
    p_beneficiary_person_id uuid,
    p_feature_code character varying,
    p_at_utc timestamp with time zone default now()
) returns boolean
language sql
stable
set search_path = commerce, pg_temp
as $$
  select exists (
    select 1
    from commerce.entitlements e
    join commerce.features f on f.id=e.feature_id
    where f.code=p_feature_code
      and e.status='Active'
      and e.starts_at_utc <= p_at_utc
      and (e.expires_at_utc is null or e.expires_at_utc > p_at_utc)
      and (e.grantee_account_id is null or e.grantee_account_id=p_grantee_account_id)
      and (e.beneficiary_person_id is null or e.beneficiary_person_id=p_beneficiary_person_id)
  )
$$;

-- The four-argument helper remains deliberately fail-closed so future code
-- cannot accidentally enable commercial use without explicit review signals.
create or replace function analytics.commercial_export_allowed(
    p_source_category character varying,
    p_subject_category character varying,
    p_consent_active boolean,
    p_jurisdiction_approved boolean
) returns boolean
language sql
stable
set search_path = analytics, pg_temp
as $$ select false $$;

create or replace function analytics.commercial_export_allowed_reviewed(
    p_source_category character varying,
    p_subject_category character varying,
    p_consent_active boolean,
    p_jurisdiction_approved boolean,
    p_legal_review_approved boolean,
    p_platform_policy_review_approved boolean
) returns boolean
language sql
stable
set search_path = analytics, pg_temp
as $$
  select coalesce((
    select ep.enabled
       and p_consent_active
       and p_jurisdiction_approved
       and p_legal_review_approved
       and p_platform_policy_review_approved
       and coalesce(sp.commercial_allowed,false)
       and not coalesce(sp.restricted,true)
       and p_source_category <> 'HealthConnect'
       and p_subject_category not in ('Child','Dependent')
    from analytics.export_policies ep
    left join analytics.source_policies sp on sp.source_category=p_source_category
    where ep.purpose='commercial_aggregated_analytics'
  ), false)
$$;

-- Existing AppUser writes create/refresh Account + Self Person automatically.
create or replace function identity.sync_legacy_app_user_foundation()
returns trigger
language plpgsql
set search_path = identity, core, ecosystem, commerce, lifemate, pg_temp
as $$
declare app_id uuid; self_person_id uuid; feature_row record;
begin
  insert into identity.accounts(id, legacy_app_user_id, status, created_at_utc, updated_at_utc)
  values (
    new.id, new.id,
    case when new.status='Active' then 'Active' else 'Disabled' end,
    new.created_at_utc, new.updated_at_utc
  )
  on conflict (id) do update set
    legacy_app_user_id=excluded.legacy_app_user_id,
    status=case
      when identity.accounts.status='DeletionPending' then identity.accounts.status
      else excluded.status
    end,
    updated_at_utc=excluded.updated_at_utc;

  insert into identity.external_identities(account_id,provider,issuer,provider_subject,status,created_at_utc,last_authenticated_at_utc)
  values(new.id,'supabase_auth','supabase',new.auth_subject,'Active',new.created_at_utc,new.updated_at_utc)
  on conflict(provider,issuer,provider_subject) do update set
    account_id=excluded.account_id,
    status='Active',
    last_authenticated_at_utc=excluded.last_authenticated_at_utc;

  insert into core.persons(id,status,subject_category,created_at_utc,updated_at_utc)
  values(new.id,'Active','Unknown',new.created_at_utc,new.updated_at_utc)
  on conflict(id) do update set updated_at_utc=excluded.updated_at_utc;

  insert into core.account_person_links(account_id,person_id,link_type,status,created_at_utc)
  values(new.id,new.id,'Self','Active',new.created_at_utc)
  on conflict(account_id,person_id,link_type) do update set status='Active',revoked_at_utc=null;

  insert into ecosystem.app_enrollments(account_id,application_id,status,enrolled_at_utc)
  select new.id,a.id,'Active',new.created_at_utc
  from ecosystem.applications a where a.code in ('wellmate','caremate')
  on conflict(account_id,application_id) do nothing;

  for feature_row in
    select id,code from commerce.features
    where code in ('treatment.basic','care.basic','women_health.basic_tracking')
  loop
    insert into commerce.entitlements(
      grantee_account_id,beneficiary_person_id,feature_id,source,source_key,status,starts_at_utc)
    values(new.id,new.id,feature_row.id,'FREE','free:v1:'||feature_row.code,'Active',new.created_at_utc)
    on conflict(grantee_account_id,beneficiary_person_id,feature_id,source,source_key)
    do update set status='Active';
  end loop;
  return new;
end
$$;

drop trigger if exists trg_sync_legacy_app_user_foundation on lifemate.app_users;
create trigger trg_sync_legacy_app_user_foundation
after insert or update of auth_subject,status,updated_at_utc on lifemate.app_users
for each row execute function identity.sync_legacy_app_user_foundation();

create or replace function core.sync_legacy_user_profile()
returns trigger
language plpgsql
set search_path = core, pg_temp
as $$
begin
  insert into core.person_profiles(
    person_id,display_name,locale,time_zone,avatar_key,profile_photo_path,created_at_utc,updated_at_utc)
  values(
    new.user_id,new.display_name,new.locale,new.time_zone,new.avatar_key,new.profile_photo_path,new.created_at_utc,new.updated_at_utc)
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

drop trigger if exists trg_sync_legacy_user_profile on lifemate.user_profiles;
create trigger trg_sync_legacy_user_profile
after insert or update of display_name,locale,time_zone,avatar_key,profile_photo_path,updated_at_utc
on lifemate.user_profiles
for each row execute function core.sync_legacy_user_profile();

-- Current caregiver mutations dual-write relationship context into grants/scopes.
create or replace function security.sync_legacy_care_access()
returns trigger
language plpgsql
set search_path = security, lifemate, pg_temp
as $$
declare grant_id uuid;
begin
  insert into security.access_grants(
    subject_person_id,grantee_account_id,grantor_person_id,
    context_type,context_id,status,starts_at_utc,expires_at_utc,revoked_at_utc,created_at_utc,updated_at_utc)
  values(
    new.patient_user_id,new.caregiver_user_id,new.patient_user_id,
    'care_relationship',new.id,
    case when new.status='Active' then 'Active' else 'Revoked' end,
    new.created_at_utc,null,
    case when new.status='Active' then null else coalesce(new.revoked_at_utc,now()) end,
    new.created_at_utc,new.updated_at_utc)
  on conflict(subject_person_id,grantee_account_id,context_type,context_id)
  do update set
    status=excluded.status,
    revoked_at_utc=excluded.revoked_at_utc,
    updated_at_utc=excluded.updated_at_utc
  returning id into grant_id;

  if new.status='Active' then
    insert into security.access_grant_scopes(grant_id,scope)
    select grant_id,scope from (values
      ('treatment.medication.read'),('treatment.plan.read'),
      ('treatment.adherence.read'),('care.events.read')
    ) s(scope)
    on conflict do nothing;

    if coalesce(new.can_view_women_calendar,false) then
      insert into security.access_grant_scopes(grant_id,scope)
      values(grant_id,'women_health.summary.read'),(grant_id,'women_health.support.write')
      on conflict do nothing;
    else
      delete from security.access_grant_scopes
      where access_grant_scopes.grant_id=grant_id
        and scope in ('women_health.summary.read','women_health.support.write','women_health.daily.read');
    end if;
  else
    delete from security.access_grant_scopes where access_grant_scopes.grant_id=grant_id;
  end if;
  return new;
end
$$;

drop trigger if exists trg_sync_legacy_care_access on lifemate.care_relationships;
create trigger trg_sync_legacy_care_access
after insert or update of status,can_view_women_calendar,revoked_at_utc,updated_at_utc
on lifemate.care_relationships
for each row execute function security.sync_legacy_care_access();

-- Person-ownership compatibility triggers for current writers.
create or replace function core.sync_health_person_id()
returns trigger
language plpgsql
set search_path = core, pg_temp
as $$
begin
  if tg_table_name='medications' then new.owner_person_id := new.owner_user_id;
  elsif tg_table_name='treatment_plans' then new.patient_person_id := new.patient_user_id;
  elsif tg_table_name='dose_occurrences' then new.patient_person_id := new.patient_user_id;
  elsif tg_table_name='care_events' then new.patient_person_id := new.patient_user_id;
  elsif tg_table_name in ('women_calendar_profiles','women_calendar_episodes','women_calendar_daily_logs') then new.owner_person_id := new.owner_user_id;
  elsif tg_table_name='women_calendar_support_actions' then new.patient_person_id := new.patient_user_id;
  end if;
  return new;
end
$$;

do $migration$
declare t text;
begin
  foreach t in array array[
    'medications','treatment_plans','dose_occurrences','care_events',
    'women_calendar_profiles','women_calendar_episodes','women_calendar_daily_logs',
    'women_calendar_support_actions'
  ] loop
    execute format('drop trigger if exists trg_sync_health_person_id on lifemate.%I',t);
    execute format(
      'create trigger trg_sync_health_person_id before insert or update on lifemate.%I for each row execute function core.sync_health_person_id()',t
    );
  end loop;
end
$migration$;

-- Requesting deletion immediately disables current healthcare API access,
-- revokes cross-person grants/entitlements and queues asynchronous session/data work.
create or replace function identity.request_account_deletion(p_account_id uuid)
returns uuid
language plpgsql
set search_path = identity, security, commerce, integration, lifemate, pg_temp
as $$
declare request_id uuid;
begin
  if not exists(select 1 from identity.accounts where id=p_account_id and status <> 'Deleted') then
    raise exception 'account_not_found';
  end if;

  insert into identity.account_deletion_requests(account_id,status,requested_at_utc,retention_policy_version)
  values(p_account_id,'Requested',now(),'retention-v1')
  on conflict(account_id,status) do update set requested_at_utc=excluded.requested_at_utc
  returning id into request_id;

  update identity.accounts set status='DeletionPending',updated_at_utc=now() where id=p_account_id;
  update lifemate.app_users set status='Disabled',updated_at_utc=now() where id=p_account_id;
  update security.access_grants
     set status='Revoked',revoked_at_utc=coalesce(revoked_at_utc,now()),updated_at_utc=now()
   where grantee_account_id=p_account_id and status='Active';
  update commerce.entitlements
     set status='Revoked',updated_at_utc=now()
   where grantee_account_id=p_account_id and status='Active';

  insert into integration.outbox_messages(
    aggregate_type,aggregate_id,event_type,idempotency_key,payload_json,status,available_at_utc)
  values
    ('account',p_account_id,'identity.session_revoke_requested',
     'account-deletion:session-revoke:'||request_id::text,
     jsonb_build_object('accountId',p_account_id,'requestId',request_id),'Pending',now()),
    ('account',p_account_id,'identity.account_deletion_requested',
     'account-deletion:process:'||request_id::text,
     jsonb_build_object('accountId',p_account_id,'requestId',request_id),'Pending',now())
  on conflict(idempotency_key) do nothing;

  return request_id;
end
$$;

-- Add a second restricted-source check at write time for all compatibility health tables.
do $migration$
declare t text;
begin
  foreach t in array array['medications','treatment_plans','dose_occurrences','dose_adherence_events','care_events','women_calendar_episodes','women_calendar_daily_logs'] loop
    execute format('comment on column lifemate.%I.provenance_source is %L',t,
      'Immutable source category used by privacy/secondary-use policy. HealthConnect must be restricted.');
  end loop;
end
$migration$;

-- No client/Data API role can invoke policy or deletion functions directly.
do $migration$
declare fn text; role_name text;
begin
  foreach role_name in array array['anon','authenticated','service_role'] loop
    if exists(select 1 from pg_roles where rolname=role_name) then
      execute format('revoke execute on all functions in schema identity from %I',role_name);
      execute format('revoke execute on all functions in schema security from %I',role_name);
      execute format('revoke execute on all functions in schema commerce from %I',role_name);
      execute format('revoke execute on all functions in schema analytics from %I',role_name);
    end if;
  end loop;
end
$migration$;
