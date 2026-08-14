-- The compatibility trigger predates provider-agnostic Account/AppUser IDs.
-- Make it follow identity.accounts.legacy_app_user_id after the first bootstrap
-- and never reactivate provider identity/enrollment data during deletion.
create or replace function identity.sync_legacy_app_user_foundation()
returns trigger
language plpgsql
set search_path = pg_catalog, identity, core, ecosystem, commerce, lifemate, pg_temp
as $$
declare
  v_account_id uuid;
  v_self_person_id uuid;
  feature_row record;
begin
  select id
    into v_account_id
    from identity.accounts
   where legacy_app_user_id = new.id
   order by created_at_utc, id
   limit 1;

  if v_account_id is null then
    -- New legacy rows keep the old one-to-one bootstrap shape initially. Once
    -- an Account is explicitly remapped, later AppUser updates follow the
    -- bridge instead of recreating an account with AppUser.id.
    v_account_id := new.id;
    insert into identity.accounts(
      id,legacy_app_user_id,status,created_at_utc,updated_at_utc
    )
    values(
      v_account_id,new.id,
      case when new.status='Active' then 'Active' else 'Disabled' end,
      new.created_at_utc,new.updated_at_utc
    )
    on conflict(id) do update set
      legacy_app_user_id=excluded.legacy_app_user_id,
      status=case
        when identity.accounts.status in ('DeletionPending','Deleted')
          then identity.accounts.status
        else excluded.status
      end,
      updated_at_utc=excluded.updated_at_utc;
  else
    update identity.accounts
       set status=case
         when identity.accounts.status in ('DeletionPending','Deleted')
           then identity.accounts.status
         when new.status='Active' then 'Active'
         else 'Disabled'
       end,
       updated_at_utc=new.updated_at_utc
     where id=v_account_id;
  end if;

  if new.status <> 'Active' then
    update identity.external_identities
       set status='Disabled',
           last_authenticated_at_utc=case
             when new.status='Deleted' then null
             else last_authenticated_at_utc
           end
     where account_id=v_account_id
       and provider='supabase_auth'
       and issuer='supabase';

    update ecosystem.app_enrollments
       set status=case when new.status='Deleted' then 'Left' else 'Suspended' end,
           last_active_at_utc=case when new.status='Deleted' then null else last_active_at_utc end
     where account_id=v_account_id;

    return new;
  end if;

  insert into identity.external_identities(
    account_id,provider,issuer,provider_subject,status,
    created_at_utc,last_authenticated_at_utc
  )
  values(
    v_account_id,'supabase_auth','supabase',new.auth_subject,'Active',
    new.created_at_utc,new.updated_at_utc
  )
  on conflict(provider,issuer,provider_subject) do update set
    account_id=excluded.account_id,
    status='Active',
    last_authenticated_at_utc=excluded.last_authenticated_at_utc;

  select person_id
    into v_self_person_id
    from core.account_person_links
   where account_id=v_account_id
     and link_type='Self'
   order by case when status='Active' then 0 else 1 end,created_at_utc
   limit 1;

  if v_self_person_id is null then
    -- Preserve the historical person-id shape only for a brand-new legacy
    -- bootstrap. A remapped account keeps its existing explicit Self Person.
    v_self_person_id := new.id;
    insert into core.persons(id,status,subject_category,created_at_utc,updated_at_utc)
    values(v_self_person_id,'Active','Unknown',new.created_at_utc,new.updated_at_utc)
    on conflict(id) do update set updated_at_utc=excluded.updated_at_utc;

    insert into core.account_person_links(
      account_id,person_id,link_type,status,created_at_utc
    )
    values(v_account_id,v_self_person_id,'Self','Active',new.created_at_utc)
    on conflict(account_id,person_id,link_type) do update set
      status='Active',revoked_at_utc=null;
  else
    update core.persons
       set updated_at_utc=new.updated_at_utc
     where id=v_self_person_id
       and status <> 'Deleted';
  end if;

  insert into ecosystem.app_enrollments(
    account_id,application_id,status,enrolled_at_utc,last_active_at_utc
  )
  select v_account_id,a.id,'Active',new.created_at_utc,new.updated_at_utc
  from ecosystem.applications a
  where a.code in ('wellmate','caremate')
  on conflict(account_id,application_id) do update set
    status='Active',last_active_at_utc=excluded.last_active_at_utc;

  for feature_row in
    select id,code from commerce.features
    where code in ('treatment.basic','care.basic','women_health.basic_tracking')
  loop
    insert into commerce.entitlements(
      grantee_account_id,beneficiary_person_id,feature_id,
      source,source_key,status,starts_at_utc
    )
    values(
      v_account_id,v_self_person_id,feature_row.id,
      'FREE','free:v1:'||feature_row.code,'Active',new.created_at_utc
    )
    on conflict(
      grantee_account_id,beneficiary_person_id,feature_id,source,source_key
    ) do update set status='Active';
  end loop;

  return new;
end
$$;
