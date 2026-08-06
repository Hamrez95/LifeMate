-- Care/coach-style capabilities can be account-level: the capability belongs to
-- the acting account, while authorization/consent decides which Person it may
-- access. Self-health capabilities remain Person-beneficiary entitlements.

create unique index if not exists uq_entitlements_account_level
  on commerce.entitlements(grantee_account_id,feature_id,source,source_key)
  where beneficiary_person_id is null and grantee_account_id is not null;

create unique index if not exists uq_entitlements_person_level
  on commerce.entitlements(beneficiary_person_id,feature_id,source,source_key,grantee_account_id)
  where beneficiary_person_id is not null;

-- Migrate the current FREE CareMate capability from self-beneficiary to
-- account-level without changing any paid-product policy.
insert into commerce.entitlements(
  grantee_account_id,beneficiary_person_id,feature_id,source,source_key,status,starts_at_utc)
select distinct e.grantee_account_id,null,e.feature_id,e.source,e.source_key,e.status,e.starts_at_utc
from commerce.entitlements e
join commerce.features f on f.id=e.feature_id
where e.source='FREE'
  and f.code='care.basic'
  and e.grantee_account_id is not null
  and not exists(
    select 1 from commerce.entitlements x
    where x.grantee_account_id=e.grantee_account_id
      and x.beneficiary_person_id is null
      and x.feature_id=e.feature_id
      and x.source=e.source
      and x.source_key=e.source_key
  );

delete from commerce.entitlements e
using commerce.features f
where e.feature_id=f.id
  and f.code='care.basic'
  and e.source='FREE'
  and e.beneficiary_person_id is not null;

create or replace function identity.sync_legacy_app_user_foundation()
returns trigger
language plpgsql
set search_path = identity, core, ecosystem, commerce, lifemate, pg_temp
as $$
declare feature_row record; care_feature_id uuid;
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

  -- Person-beneficiary free capabilities.
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

  -- Acting-account capability: whose health data is visible is decided later
  -- by scope + relationship/engagement + consent, never by this entitlement.
  select id into care_feature_id from commerce.features where code='care.basic';
  if care_feature_id is not null and not exists(
    select 1 from commerce.entitlements e
    where e.grantee_account_id=new.id
      and e.beneficiary_person_id is null
      and e.feature_id=care_feature_id
      and e.source='FREE'
      and e.source_key='free:v1:care.basic'
  ) then
    insert into commerce.entitlements(
      grantee_account_id,beneficiary_person_id,feature_id,source,source_key,status,starts_at_utc)
    values(new.id,null,care_feature_id,'FREE','free:v1:care.basic','Active',new.created_at_utc);
  end if;
  return new;
end
$$;

revoke execute on function identity.sync_legacy_app_user_foundation() from public;
