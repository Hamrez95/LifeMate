begin;

alter table consent.consent_documents
  add column if not exists row_version bigint not null default 1,
  add column if not exists updated_at_utc timestamptz not null default now(),
  add column if not exists retired_at_utc timestamptz;

alter table consent.consent_documents
  drop constraint if exists ck_consent_documents_row_version;
alter table consent.consent_documents
  add constraint ck_consent_documents_row_version check (row_version >= 1);

alter table consent.preference_purposes
  add column if not exists version bigint not null default 1;
alter table consent.preference_purposes
  drop constraint if exists ck_preference_purposes_version;
alter table consent.preference_purposes
  add constraint ck_preference_purposes_version check (version >= 1);

insert into admin.permissions(code,domain,risk_level,role_assignable,description) values
  ('privacy.read','privacy','SENSITIVE',true,'Read legal-document versions, aggregate acceptance coverage and privacy preference metadata without raw health data'),
  ('privacy.write','privacy','HIGH_RISK',true,'Publish/retire legal-document versions and manage optional preference-purpose catalog metadata; never accept or opt in on behalf of users')
on conflict (code) do update set
  domain=excluded.domain,
  risk_level=excluded.risk_level,
  role_assignable=excluded.role_assignable,
  description=excluded.description,
  updated_at_utc=now();

insert into admin.role_permissions(role_id,permission_code)
select r.id,p.code
from admin.roles r
cross join admin.permissions p
where r.code='founder' and p.code in ('privacy.read','privacy.write')
on conflict do nothing;

insert into admin.role_permissions(role_id,permission_code)
select r.id,p.code
from admin.roles r
cross join admin.permissions p
where r.code='product' and p.code in ('privacy.read','privacy.write')
on conflict do nothing;

create or replace function admin.privacy_legal_documents(
  p_actor_account_id uuid,
  p_limit integer default 100
) returns table(
  id uuid,
  purpose varchar,
  version varchar,
  jurisdiction varchar,
  title varchar,
  document_hash varchar,
  content_uri text,
  status varchar,
  effective_at_utc timestamptz,
  row_version bigint,
  created_at_utc timestamptz,
  updated_at_utc timestamptz,
  retired_at_utc timestamptz
)
language plpgsql
stable
security definer
set search_path = pg_catalog, admin, consent
as $$
begin
  if not admin.account_has_permission(p_actor_account_id,'privacy.read') then
    raise exception 'privacy_permission_denied' using errcode='42501';
  end if;
  if p_limit is null or p_limit < 1 or p_limit > 200 then
    raise exception 'privacy_limit_invalid' using errcode='22023';
  end if;
  return query
  select d.id,d.purpose,d.version,d.jurisdiction,d.title,d.document_hash,d.content_uri,
         d.status,d.effective_at_utc,d.row_version,d.created_at_utc,d.updated_at_utc,d.retired_at_utc
  from consent.consent_documents d
  where d.purpose in ('legal_terms','privacy_notice')
  order by d.effective_at_utc desc nulls last,d.created_at_utc desc,d.id
  limit p_limit;
end;
$$;

create or replace function admin.privacy_preference_purposes(
  p_actor_account_id uuid
) returns table(
  purpose varchar,
  category varchar,
  channel varchar,
  policy_version varchar,
  default_enabled boolean,
  user_mutable boolean,
  status varchar,
  description varchar,
  version bigint,
  updated_at_utc timestamptz
)
language plpgsql
stable
security definer
set search_path = pg_catalog, admin, consent
as $$
begin
  if not admin.account_has_permission(p_actor_account_id,'privacy.read') then
    raise exception 'privacy_permission_denied' using errcode='42501';
  end if;
  return query
  select p.purpose,p.category,p.channel,p.policy_version,p.default_enabled,p.user_mutable,
         p.status,p.description,p.version,p.updated_at_utc
  from consent.preference_purposes p
  order by p.category,p.purpose;
end;
$$;

create or replace function admin.privacy_acceptance_coverage(
  p_actor_account_id uuid,
  p_jurisdiction varchar default 'GLOBAL'
) returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, admin, consent, identity
as $$
declare
  v_result jsonb;
begin
  if not admin.account_has_permission(p_actor_account_id,'privacy.read') then
    raise exception 'privacy_permission_denied' using errcode='42501';
  end if;
  if p_jurisdiction is null or p_jurisdiction !~ '^[A-Z][A-Z0-9_-]{1,15}$' then
    raise exception 'privacy_jurisdiction_invalid' using errcode='22023';
  end if;

  with required as (
    select * from consent.current_registration_legal_documents(p_jurisdiction)
  ), active_accounts as (
    select a.id from identity.accounts a where a.status='Active'
  ), per_document as (
    select r.id,r.purpose,r.version,r.jurisdiction,r.title,r.document_hash,r.effective_at_utc,
           count(a.id)::bigint as eligible_accounts,
           count(la.account_id)::bigint as accepted_accounts
    from required r
    cross join active_accounts a
    left join consent.legal_acceptances la
      on la.account_id=a.id and la.document_id=r.id and la.document_hash=r.document_hash
    group by r.id,r.purpose,r.version,r.jurisdiction,r.title,r.document_hash,r.effective_at_utc
  )
  select jsonb_build_object(
    'jurisdiction',p_jurisdiction,
    'asOfUtc',now(),
    'documents',coalesce(jsonb_agg(jsonb_build_object(
      'id',d.id,
      'purpose',d.purpose,
      'version',d.version,
      'jurisdiction',d.jurisdiction,
      'title',d.title,
      'documentHash',d.document_hash,
      'effectiveAtUtc',d.effective_at_utc,
      'eligibleAccounts',d.eligible_accounts,
      'acceptedAccounts',d.accepted_accounts
    ) order by d.purpose),'[]'::jsonb)
  ) into v_result
  from per_document d;
  return coalesce(v_result,jsonb_build_object('jurisdiction',p_jurisdiction,'asOfUtc',now(),'documents','[]'::jsonb));
end;
$$;

create or replace function admin.user_privacy_summary(
  p_actor_account_id uuid,
  p_target_account_id uuid,
  p_jurisdiction varchar default 'GLOBAL'
) returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, admin, consent, identity, core
as $$
declare
  v_result jsonb;
begin
  if not admin.account_has_permission(p_actor_account_id,'privacy.read') then
    raise exception 'privacy_permission_denied' using errcode='42501';
  end if;
  if not exists(select 1 from identity.accounts where id=p_target_account_id) then
    raise exception 'privacy_account_not_found' using errcode='P0002';
  end if;

  with required as (
    select * from consent.current_registration_legal_documents(p_jurisdiction)
  ), person_row as (
    select l.person_id from core.account_person_links l
    where l.account_id=p_target_account_id and l.link_type='Self' and l.status='Active'
    order by l.created_at_utc limit 1
  )
  select jsonb_build_object(
    'accountId',p_target_account_id,
    'jurisdiction',p_jurisdiction,
    'legal',coalesce((select jsonb_agg(jsonb_build_object(
      'documentId',r.id,
      'purpose',r.purpose,
      'version',r.version,
      'accepted',exists(select 1 from consent.legal_acceptances la where la.account_id=p_target_account_id and la.document_id=r.id and la.document_hash=r.document_hash)
    ) order by r.purpose) from required r),'[]'::jsonb),
    'preferences',coalesce((select jsonb_agg(jsonb_build_object(
      'purpose',p.purpose,
      'category',p.category,
      'channel',p.channel,
      'policyVersion',p.policy_version,
      'status',c.status,
      'explicit',c.id is not null,
      'updatedAtUtc',c.updated_at_utc
    ) order by p.category,p.purpose)
      from consent.preference_purposes p
      left join person_row pr on true
      left join consent.data_use_consents c
        on c.subject_person_id=pr.person_id
       and c.purpose=p.purpose
       and c.jurisdiction=p_jurisdiction
       and c.policy_version=p.policy_version
      where p.status='Active'),'[]'::jsonb),
    'asOfUtc',now()
  ) into v_result;
  return v_result;
end;
$$;

create or replace function admin.publish_legal_document(
  p_actor_account_id uuid,
  p_purpose varchar,
  p_version varchar,
  p_jurisdiction varchar,
  p_title varchar,
  p_document_hash varchar,
  p_content_uri text,
  p_effective_at_utc timestamptz,
  p_reason varchar,
  p_correlation_id uuid,
  p_idempotency_key varchar,
  p_request_hash varchar
) returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, admin, consent
as $$
declare
  v_existing admin.idempotency_keys%rowtype;
  v_document consent.consent_documents%rowtype;
  v_response jsonb;
  v_operation varchar(128) := 'privacy.legal_document.publish';
begin
  if not admin.account_has_permission(p_actor_account_id,'privacy.write') then
    return jsonb_build_object('httpStatus',403,'code','permission_denied','message','The required permission is not granted.','replayed',false);
  end if;
  if p_purpose not in ('legal_terms','privacy_notice')
     or p_version is null or length(trim(p_version))<1 or length(trim(p_version))>64
     or p_jurisdiction is null or p_jurisdiction !~ '^[A-Z][A-Z0-9_-]{1,15}$'
     or p_title is null or length(trim(p_title))<2 or length(trim(p_title))>160
     or p_document_hash is null or p_document_hash !~ '^[A-Za-z0-9:_-]{16,160}$'
     or p_content_uri is null or p_content_uri !~ '^https://'
     or p_effective_at_utc is null
     or p_reason is null or length(trim(p_reason))<10 or length(trim(p_reason))>1000
     or p_idempotency_key is null or length(p_idempotency_key)<8 or length(p_idempotency_key)>180
     or p_request_hash is null or length(p_request_hash)<32 or length(p_request_hash)>128 then
    return jsonb_build_object('httpStatus',400,'code','privacy_legal_document_invalid','message','Legal document payload is invalid.','replayed',false);
  end if;

  perform pg_advisory_xact_lock(hashtextextended(p_actor_account_id::text || ':' || v_operation || ':' || p_idempotency_key,0));
  select * into v_existing from admin.idempotency_keys
   where actor_account_id=p_actor_account_id and operation=v_operation and idempotency_key=p_idempotency_key for update;
  if found then
    if v_existing.request_hash<>p_request_hash then
      return jsonb_build_object('httpStatus',409,'code','idempotency_conflict','message','Idempotency-Key was already used for another request.','replayed',false);
    end if;
    if v_existing.status='Completed' and v_existing.response_json is not null then
      return v_existing.response_json || jsonb_build_object('replayed',true);
    end if;
    return jsonb_build_object('httpStatus',409,'code','idempotency_in_progress','message','Matching request is still processing.','replayed',false);
  end if;
  insert into admin.idempotency_keys(actor_account_id,operation,idempotency_key,request_hash,status)
  values(p_actor_account_id,v_operation,p_idempotency_key,p_request_hash,'Processing');

  if exists(select 1 from consent.consent_documents d where d.purpose=p_purpose and d.version=trim(p_version) and d.jurisdiction=p_jurisdiction) then
    v_response:=jsonb_build_object('httpStatus',409,'code','privacy_legal_document_exists','message','Document version already exists.','replayed',false);
  else
    insert into consent.consent_documents(purpose,version,jurisdiction,title,document_hash,status,effective_at_utc,content_uri,row_version,updated_at_utc)
    values(p_purpose,trim(p_version),p_jurisdiction,trim(p_title),p_document_hash,'Active',p_effective_at_utc,p_content_uri,1,now())
    returning * into v_document;
    v_response:=jsonb_build_object('httpStatus',201,'code','ok','documentId',v_document.id,'rowVersion',v_document.row_version,'replayed',false);
  end if;

  insert into admin.audit_events(actor_account_id,action,resource_type,resource_id,result,reason,correlation_id,request_id,elevated_access,metadata_json)
  values(p_actor_account_id,v_operation,'consent_document',coalesce(v_document.id::text,p_purpose || ':' || trim(p_version)),case when (v_response->>'httpStatus')::int<400 then 'Succeeded' else 'Denied' end,trim(p_reason),p_correlation_id,p_idempotency_key,false,
    jsonb_build_object('purpose',p_purpose,'version',trim(p_version),'jurisdiction',p_jurisdiction,'effectiveAtUtc',p_effective_at_utc,'code',v_response->>'code'));
  update admin.idempotency_keys set status='Completed',response_status=(v_response->>'httpStatus')::int,response_json=v_response,updated_at_utc=now()
  where actor_account_id=p_actor_account_id and operation=v_operation and idempotency_key=p_idempotency_key;
  return v_response;
end;
$$;

create or replace function admin.retire_legal_document(
  p_actor_account_id uuid,
  p_document_id uuid,
  p_expected_version bigint,
  p_reason varchar,
  p_correlation_id uuid,
  p_idempotency_key varchar,
  p_request_hash varchar
) returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, admin, consent
as $$
declare
  v_existing admin.idempotency_keys%rowtype;
  v_document consent.consent_documents%rowtype;
  v_response jsonb;
  v_operation varchar(128) := 'privacy.legal_document.retire';
begin
  if not admin.account_has_permission(p_actor_account_id,'privacy.write') then
    return jsonb_build_object('httpStatus',403,'code','permission_denied','message','The required permission is not granted.','replayed',false);
  end if;
  if p_expected_version is null or p_expected_version<1
     or p_reason is null or length(trim(p_reason))<10 or length(trim(p_reason))>1000
     or p_idempotency_key is null or length(p_idempotency_key)<8 or length(p_idempotency_key)>180
     or p_request_hash is null or length(p_request_hash)<32 or length(p_request_hash)>128 then
    return jsonb_build_object('httpStatus',400,'code','privacy_legal_retire_invalid','message','Retire request is invalid.','replayed',false);
  end if;
  perform pg_advisory_xact_lock(hashtextextended(p_actor_account_id::text || ':' || v_operation || ':' || p_idempotency_key,0));
  select * into v_existing from admin.idempotency_keys where actor_account_id=p_actor_account_id and operation=v_operation and idempotency_key=p_idempotency_key for update;
  if found then
    if v_existing.request_hash<>p_request_hash then return jsonb_build_object('httpStatus',409,'code','idempotency_conflict','message','Idempotency-Key conflict.','replayed',false); end if;
    if v_existing.status='Completed' and v_existing.response_json is not null then return v_existing.response_json || jsonb_build_object('replayed',true); end if;
    return jsonb_build_object('httpStatus',409,'code','idempotency_in_progress','message','Matching request is processing.','replayed',false);
  end if;
  insert into admin.idempotency_keys(actor_account_id,operation,idempotency_key,request_hash,status) values(p_actor_account_id,v_operation,p_idempotency_key,p_request_hash,'Processing');

  select * into v_document from consent.consent_documents where id=p_document_id and purpose in ('legal_terms','privacy_notice') for update;
  if not found then
    v_response:=jsonb_build_object('httpStatus',404,'code','privacy_legal_document_not_found','message','Legal document was not found.','replayed',false);
  elsif v_document.row_version<>p_expected_version then
    v_response:=jsonb_build_object('httpStatus',409,'code','privacy_legal_document_version_conflict','message','Document changed; refresh before retiring.','currentVersion',v_document.row_version,'replayed',false);
  elsif v_document.status='Retired' then
    v_response:=jsonb_build_object('httpStatus',200,'code','ok','documentId',v_document.id,'rowVersion',v_document.row_version,'noop',true,'replayed',false);
  else
    update consent.consent_documents set status='Retired',retired_at_utc=now(),updated_at_utc=now(),row_version=row_version+1 where id=v_document.id returning * into v_document;
    v_response:=jsonb_build_object('httpStatus',200,'code','ok','documentId',v_document.id,'rowVersion',v_document.row_version,'noop',false,'replayed',false);
  end if;
  insert into admin.audit_events(actor_account_id,action,resource_type,resource_id,result,reason,correlation_id,request_id,elevated_access,metadata_json)
  values(p_actor_account_id,v_operation,'consent_document',p_document_id::text,case when (v_response->>'httpStatus')::int<400 then 'Succeeded' else 'Denied' end,trim(p_reason),p_correlation_id,p_idempotency_key,false,jsonb_build_object('expectedVersion',p_expected_version,'code',v_response->>'code'));
  update admin.idempotency_keys set status='Completed',response_status=(v_response->>'httpStatus')::int,response_json=v_response,updated_at_utc=now() where actor_account_id=p_actor_account_id and operation=v_operation and idempotency_key=p_idempotency_key;
  return v_response;
end;
$$;

create or replace function admin.update_preference_purpose(
  p_actor_account_id uuid,
  p_purpose varchar,
  p_description varchar,
  p_policy_version varchar,
  p_status varchar,
  p_expected_version bigint,
  p_reason varchar,
  p_correlation_id uuid,
  p_idempotency_key varchar,
  p_request_hash varchar
) returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, admin, consent
as $$
declare
  v_existing admin.idempotency_keys%rowtype;
  v_purpose consent.preference_purposes%rowtype;
  v_response jsonb;
  v_operation varchar(128) := 'privacy.preference_purpose.update';
begin
  if not admin.account_has_permission(p_actor_account_id,'privacy.write') then
    return jsonb_build_object('httpStatus',403,'code','permission_denied','message','The required permission is not granted.','replayed',false);
  end if;
  if p_purpose is null or p_purpose !~ '^[a-z][a-z0-9._-]{2,79}$'
     or p_description is null or length(trim(p_description))<3 or length(trim(p_description))>240
     or p_policy_version is null or length(trim(p_policy_version))<1 or length(trim(p_policy_version))>64
     or p_status not in ('Active','Retired')
     or p_expected_version is null or p_expected_version<1
     or p_reason is null or length(trim(p_reason))<10 or length(trim(p_reason))>1000
     or p_idempotency_key is null or length(p_idempotency_key)<8 or length(p_idempotency_key)>180
     or p_request_hash is null or length(p_request_hash)<32 or length(p_request_hash)>128 then
    return jsonb_build_object('httpStatus',400,'code','privacy_preference_purpose_invalid','message','Preference-purpose update is invalid.','replayed',false);
  end if;
  perform pg_advisory_xact_lock(hashtextextended(p_actor_account_id::text || ':' || v_operation || ':' || p_idempotency_key,0));
  select * into v_existing from admin.idempotency_keys where actor_account_id=p_actor_account_id and operation=v_operation and idempotency_key=p_idempotency_key for update;
  if found then
    if v_existing.request_hash<>p_request_hash then return jsonb_build_object('httpStatus',409,'code','idempotency_conflict','message','Idempotency-Key conflict.','replayed',false); end if;
    if v_existing.status='Completed' and v_existing.response_json is not null then return v_existing.response_json || jsonb_build_object('replayed',true); end if;
    return jsonb_build_object('httpStatus',409,'code','idempotency_in_progress','message','Matching request is processing.','replayed',false);
  end if;
  insert into admin.idempotency_keys(actor_account_id,operation,idempotency_key,request_hash,status) values(p_actor_account_id,v_operation,p_idempotency_key,p_request_hash,'Processing');

  select * into v_purpose from consent.preference_purposes where purpose=p_purpose for update;
  if not found then
    v_response:=jsonb_build_object('httpStatus',404,'code','privacy_preference_purpose_not_found','message','Preference purpose was not found.','replayed',false);
  elsif v_purpose.version<>p_expected_version then
    v_response:=jsonb_build_object('httpStatus',409,'code','privacy_preference_purpose_version_conflict','message','Preference purpose changed; refresh before updating.','currentVersion',v_purpose.version,'replayed',false);
  else
    update consent.preference_purposes set description=trim(p_description),policy_version=trim(p_policy_version),status=p_status,version=version+1,updated_at_utc=now() where purpose=p_purpose returning * into v_purpose;
    v_response:=jsonb_build_object('httpStatus',200,'code','ok','purpose',v_purpose.purpose,'version',v_purpose.version,'replayed',false);
  end if;
  insert into admin.audit_events(actor_account_id,action,resource_type,resource_id,result,reason,correlation_id,request_id,elevated_access,metadata_json)
  values(p_actor_account_id,v_operation,'preference_purpose',p_purpose,case when (v_response->>'httpStatus')::int<400 then 'Succeeded' else 'Denied' end,trim(p_reason),p_correlation_id,p_idempotency_key,false,jsonb_build_object('policyVersion',p_policy_version,'status',p_status,'expectedVersion',p_expected_version,'code',v_response->>'code'));
  update admin.idempotency_keys set status='Completed',response_status=(v_response->>'httpStatus')::int,response_json=v_response,updated_at_utc=now() where actor_account_id=p_actor_account_id and operation=v_operation and idempotency_key=p_idempotency_key;
  return v_response;
end;
$$;

revoke all on function admin.privacy_legal_documents(uuid,integer) from public;
revoke all on function admin.privacy_preference_purposes(uuid) from public;
revoke all on function admin.privacy_acceptance_coverage(uuid,varchar) from public;
revoke all on function admin.user_privacy_summary(uuid,uuid,varchar) from public;
revoke all on function admin.publish_legal_document(uuid,varchar,varchar,varchar,varchar,varchar,text,timestamptz,varchar,uuid,varchar,varchar) from public;
revoke all on function admin.retire_legal_document(uuid,uuid,bigint,varchar,uuid,varchar,varchar) from public;
revoke all on function admin.update_preference_purpose(uuid,varchar,varchar,varchar,varchar,bigint,varchar,uuid,varchar,varchar) from public;

do $$
begin
  if exists(select 1 from pg_roles where rolname='lifemate_admin_runtime') then
    grant execute on function admin.privacy_legal_documents(uuid,integer) to lifemate_admin_runtime;
    grant execute on function admin.privacy_preference_purposes(uuid) to lifemate_admin_runtime;
    grant execute on function admin.privacy_acceptance_coverage(uuid,varchar) to lifemate_admin_runtime;
    grant execute on function admin.user_privacy_summary(uuid,uuid,varchar) to lifemate_admin_runtime;
    grant execute on function admin.publish_legal_document(uuid,varchar,varchar,varchar,varchar,varchar,text,timestamptz,varchar,uuid,varchar,varchar) to lifemate_admin_runtime;
    grant execute on function admin.retire_legal_document(uuid,uuid,bigint,varchar,uuid,varchar,varchar) to lifemate_admin_runtime;
    grant execute on function admin.update_preference_purpose(uuid,varchar,varchar,varchar,varchar,bigint,varchar,uuid,varchar,varchar) to lifemate_admin_runtime;
  end if;
end
$$;

comment on function admin.publish_legal_document is 'Admin may publish legal document metadata/version only; it cannot create user acceptance evidence.';
comment on function admin.update_preference_purpose is 'Admin may manage optional purpose catalog metadata only; it cannot change any account opt-in/out state.';

commit;
