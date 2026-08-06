-- Account lifecycle hardening. A deletion/disable operation must never be
-- undone by the legacy bootstrap compatibility trigger, and current Edge API
-- relationship checks must lose access immediately even before the future
-- background erasure worker finishes.

create or replace function identity.sync_legacy_app_user_foundation()
returns trigger
language plpgsql
set search_path = identity, core, ecosystem, commerce, lifemate, pg_temp
as $$
declare feature_row record; care_feature_id uuid; v_account_status character varying(32);
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
      when identity.accounts.status in ('DeletionPending','Deleted') then identity.accounts.status
      else excluded.status
    end,
    updated_at_utc=excluded.updated_at_utc;

  select status into v_account_status from identity.accounts where id=new.id;

  insert into identity.external_identities(account_id,provider,issuer,provider_subject,status,created_at_utc,last_authenticated_at_utc)
  values(
    new.id,'supabase_auth','supabase',new.auth_subject,
    case when v_account_status='Active' then 'Active' else 'Disabled' end,
    new.created_at_utc,new.updated_at_utc)
  on conflict(provider,issuer,provider_subject) do update set
    account_id=excluded.account_id,
    status=excluded.status,
    last_authenticated_at_utc=excluded.last_authenticated_at_utc;

  insert into core.persons(id,status,subject_category,created_at_utc,updated_at_utc)
  values(new.id,'Active','Unknown',new.created_at_utc,new.updated_at_utc)
  on conflict(id) do update set updated_at_utc=excluded.updated_at_utc;

  insert into core.account_person_links(account_id,person_id,link_type,status,created_at_utc)
  values(new.id,new.id,'Self','Active',new.created_at_utc)
  on conflict(account_id,person_id,link_type) do update set status='Active',revoked_at_utc=null;

  insert into ecosystem.app_enrollments(account_id,application_id,status,enrolled_at_utc)
  select new.id,a.id,
         case when v_account_status='Active' then 'Active' else 'Suspended' end,
         new.created_at_utc
  from ecosystem.applications a where a.code in ('wellmate','caremate')
  on conflict(account_id,application_id) do update set
    status=excluded.status,
    last_active_at_utc=case when excluded.status='Active' then now() else ecosystem.app_enrollments.last_active_at_utc end;

  -- A disabled/deleting account must not regain capabilities through bootstrap.
  if v_account_status <> 'Active' then
    return new;
  end if;

  for feature_row in
    select id,code from commerce.features
    where code in ('treatment.basic','women_health.basic_tracking')
  loop
    insert into commerce.entitlements(
      grantee_account_id,beneficiary_person_id,feature_id,source,source_key,status,starts_at_utc)
    values(new.id,new.id,feature_row.id,'FREE','free:v1:'||feature_row.code,'Active',new.created_at_utc)
    on conflict(grantee_account_id,beneficiary_person_id,feature_id,source,source_key)
    do update set status='Active';
  end loop;

  select id into care_feature_id from commerce.features where code='care.basic';
  if care_feature_id is not null and not exists(
    select 1 from commerce.entitlements e
    where e.grantee_account_id=new.id
      and e.beneficiary_person_id is null
      and e.feature_id=care_feature_id
      and e.source='FREE'
      and e.source_key='free:v1:care.basic'
      and e.status='Active'
  ) then
    insert into commerce.entitlements(
      grantee_account_id,beneficiary_person_id,feature_id,source,source_key,status,starts_at_utc)
    values(new.id,null,care_feature_id,'FREE','free:v1:care.basic','Active',new.created_at_utc)
    on conflict do nothing;
  end if;
  return new;
end
$$;

create or replace function identity.request_account_deletion(p_account_id uuid)
returns uuid
language plpgsql
set search_path = identity, core, ecosystem, security, commerce, integration, lifemate, pg_temp
as $$
declare request_id uuid; v_self_person_id uuid;
begin
  select person_id into v_self_person_id
  from core.account_person_links
  where account_id=p_account_id and link_type='Self' and status='Active'
  limit 1;

  if not exists(select 1 from identity.accounts where id=p_account_id and status <> 'Deleted') then
    raise exception 'account_not_found';
  end if;

  insert into identity.account_deletion_requests(account_id,status,requested_at_utc,retention_policy_version)
  values(p_account_id,'Requested',now(),'retention-v1')
  on conflict(account_id,status) do update set requested_at_utc=excluded.requested_at_utc
  returning id into request_id;

  update identity.accounts
     set status='DeletionPending',updated_at_utc=now()
   where id=p_account_id;

  -- Current Edge authentication gate checks this legacy status.
  update lifemate.app_users
     set status='Disabled',updated_at_utc=now()
   where id=p_account_id;

  update identity.external_identities
     set status='Disabled'
   where account_id=p_account_id and status='Active';

  update ecosystem.app_enrollments
     set status='Suspended'
   where account_id=p_account_id and status='Active';

  -- Current Edge caregiver authorization still reads care_relationships.
  -- Revoke both directions now; compatibility triggers revoke scopes/consent.
  update lifemate.care_relationships
     set status='Revoked',
         revoked_by_user_id=p_account_id,
         revoked_at_utc=coalesce(revoked_at_utc,now()),
         updated_at_utc=now()
   where status='Active'
     and (patient_user_id=p_account_id or caregiver_user_id=p_account_id);

  update security.access_grants
     set status='Revoked',revoked_at_utc=coalesce(revoked_at_utc,now()),updated_at_utc=now()
   where status='Active'
     and (grantee_account_id=p_account_id
          or (v_self_person_id is not null and subject_person_id=v_self_person_id));

  update commerce.entitlements
     set status='Revoked',updated_at_utc=now()
   where status='Active'
     and (grantee_account_id=p_account_id
          or (v_self_person_id is not null and beneficiary_person_id=v_self_person_id));

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

revoke execute on function identity.sync_legacy_app_user_foundation() from public;
revoke execute on function identity.request_account_deletion(uuid) from public;
