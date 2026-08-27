begin;

insert into admin.permissions(code,domain,risk_level,role_assignable,description) values
('privacy.admin.read','privacy','SENSITIVE',true,'Read legal document versions, acceptance coverage and optional privacy purpose catalog'),
('privacy.admin.write','privacy','HIGH_RISK',true,'Publish or retire legal document versions and administer optional purpose catalog wording/status')
on conflict (code) do update set
  domain=excluded.domain,
  risk_level=excluded.risk_level,
  role_assignable=excluded.role_assignable,
  description=excluded.description,
  updated_at_utc=now();

insert into admin.role_permissions(role_id,permission_code)
select r.id,p.code
from admin.roles r
cross join (values('privacy.admin.read'),('privacy.admin.write')) p(code)
where r.code in ('founder','super_admin')
on conflict do nothing;

insert into admin.role_permissions(role_id,permission_code)
select r.id,'privacy.admin.read'
from admin.roles r
where r.code in ('legal','product','security','support')
on conflict do nothing;

insert into admin.role_permissions(role_id,permission_code)
select r.id,'privacy.admin.write'
from admin.roles r
where r.code in ('legal','product')
on conflict do nothing;

create or replace function admin.privacy_legal_snapshot(
  p_actor_account_id uuid,
  p_jurisdiction varchar default 'GLOBAL'
) returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog,admin,consent,identity
as $$
declare
  v_documents jsonb;
  v_purposes jsonb;
  v_required_accounts bigint;
  v_complete_accounts bigint;
begin
  if not admin.account_has_permission(p_actor_account_id,'privacy.admin.read') then
    raise exception using errcode='42501',message='permission_denied';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id',d.id,
    'purpose',d.purpose,
    'version',d.version,
    'jurisdiction',d.jurisdiction,
    'title',d.title,
    'documentHash',d.document_hash,
    'contentUri',d.content_uri,
    'status',d.status,
    'effectiveAtUtc',d.effective_at_utc,
    'createdAtUtc',d.created_at_utc,
    'acceptanceCount',coalesce(a.acceptance_count,0)
  ) order by d.created_at_utc desc,d.id desc),'[]'::jsonb)
  into v_documents
  from consent.consent_documents d
  left join lateral (
    select count(*)::bigint acceptance_count
    from consent.legal_acceptances la
    where la.document_id=d.id and la.document_hash=d.document_hash
  ) a on true
  where d.purpose in ('legal_terms','privacy_notice')
    and d.jurisdiction in (p_jurisdiction,'GLOBAL');

  select coalesce(jsonb_agg(jsonb_build_object(
    'purpose',p.purpose,
    'category',p.category,
    'channel',p.channel,
    'policyVersion',p.policy_version,
    'defaultEnabled',p.default_enabled,
    'userMutable',p.user_mutable,
    'status',p.status,
    'description',p.description,
    'updatedAtUtc',p.updated_at_utc,
    'optedInCount',coalesce(c.opted_in_count,0),
    'explicitOptOutCount',coalesce(c.opted_out_count,0)
  ) order by p.category,p.purpose),'[]'::jsonb)
  into v_purposes
  from consent.preference_purposes p
  left join lateral (
    select
      count(*) filter (where duc.status='OptedIn')::bigint opted_in_count,
      count(*) filter (where duc.status in ('OptedOut','Revoked'))::bigint opted_out_count
    from consent.data_use_consents duc
    where duc.purpose=p.purpose
      and duc.policy_version=p.policy_version
      and duc.jurisdiction=p_jurisdiction
  ) c on true;

  select count(*)::bigint into v_required_accounts
  from identity.accounts a
  where a.status='Active';

  select count(*)::bigint into v_complete_accounts
  from identity.accounts a
  where a.status='Active'
    and a.registration_completed_at_utc is not null;

  return jsonb_build_object(
    'jurisdiction',p_jurisdiction,
    'documents',v_documents,
    'purposes',v_purposes,
    'acceptanceCoverage',jsonb_build_object(
      'eligibleAccountCount',v_required_accounts,
      'registrationCompleteCount',v_complete_accounts
    ),
    'freshness',jsonb_build_object('status','fresh','asOfUtc',now())
  );
end
$$;

create or replace function admin.publish_legal_document_idempotent(
  p_actor_account_id uuid,
  p_purpose varchar,
  p_version varchar,
  p_jurisdiction varchar,
  p_title varchar,
  p_document_hash varchar,
  p_content_uri text,
  p_effective_at_utc timestamptz,
  p_correlation_id uuid,
  p_idempotency_key varchar,
  p_request_hash varchar
) returns jsonb
language plpgsql
security definer
set search_path = pg_catalog,admin,consent
as $$
declare
  v_inserted integer;
  v_existing admin.idempotency_keys%rowtype;
  v_document_id uuid;
  v_response jsonb;
begin
  if not admin.account_has_permission(p_actor_account_id,'privacy.admin.write') then
    raise exception using errcode='42501',message='permission_denied';
  end if;
  if p_purpose not in ('legal_terms','privacy_notice')
     or p_version is null or length(trim(p_version)) not between 1 and 64
     or p_jurisdiction is null or length(trim(p_jurisdiction)) not between 2 and 16
     or p_title is null or length(trim(p_title)) not between 3 and 200
     or p_document_hash is null or length(trim(p_document_hash)) not between 32 and 160
     or p_content_uri is null or p_content_uri !~ '^https://'
     or length(p_content_uri) > 2048
     or p_effective_at_utc is null then
    raise exception using errcode='22023',message='legal_document_invalid';
  end if;
  if p_idempotency_key is null or length(p_idempotency_key) not between 8 and 180
     or p_request_hash is null or length(p_request_hash) <> 64 then
    raise exception using errcode='22023',message='idempotency_invalid';
  end if;

  insert into admin.idempotency_keys(actor_account_id,operation,idempotency_key,request_hash,status)
  values(p_actor_account_id,'privacy.legal.publish',p_idempotency_key,p_request_hash,'Processing')
  on conflict do nothing;
  get diagnostics v_inserted=row_count;

  if v_inserted=0 then
    select * into v_existing from admin.idempotency_keys
    where actor_account_id=p_actor_account_id and operation='privacy.legal.publish'
      and idempotency_key=p_idempotency_key for update;
    if v_existing.request_hash<>p_request_hash then
      return jsonb_build_object('httpStatus',409,'code','idempotency_conflict');
    end if;
    if v_existing.status='Completed' and v_existing.response_json is not null then
      return v_existing.response_json || jsonb_build_object('replayed',true);
    end if;
    return jsonb_build_object('httpStatus',409,'code','operation_in_progress');
  end if;

  update consent.consent_documents
  set status='Retired'
  where purpose=p_purpose and jurisdiction=p_jurisdiction and status='Active';

  insert into consent.consent_documents(
    purpose,version,jurisdiction,title,document_hash,status,effective_at_utc,content_uri
  ) values(
    p_purpose,trim(p_version),trim(p_jurisdiction),trim(p_title),trim(p_document_hash),
    'Active',p_effective_at_utc,p_content_uri
  ) on conflict (purpose,version,jurisdiction) do update set
    title=excluded.title,
    document_hash=excluded.document_hash,
    status='Active',
    effective_at_utc=excluded.effective_at_utc,
    content_uri=excluded.content_uri
  returning id into v_document_id;

  insert into admin.audit_events(
    actor_account_id,action,resource_type,resource_id,result,correlation_id,metadata_json
  ) values(
    p_actor_account_id,'privacy.legal.publish','ConsentDocument',v_document_id::text,'Succeeded',
    p_correlation_id,
    jsonb_build_object('purpose',p_purpose,'version',p_version,'jurisdiction',p_jurisdiction)
  );

  v_response=jsonb_build_object(
    'httpStatus',200,'code','legal_document_published','documentId',v_document_id,'replayed',false
  );
  update admin.idempotency_keys set status='Completed',response_status=200,response_json=v_response,updated_at_utc=now()
  where actor_account_id=p_actor_account_id and operation='privacy.legal.publish'
    and idempotency_key=p_idempotency_key;
  return v_response;
end
$$;

create or replace function admin.retire_legal_document_idempotent(
  p_actor_account_id uuid,
  p_document_id uuid,
  p_correlation_id uuid,
  p_idempotency_key varchar,
  p_request_hash varchar
) returns jsonb
language plpgsql
security definer
set search_path = pg_catalog,admin,consent
as $$
declare
  v_inserted integer;
  v_existing admin.idempotency_keys%rowtype;
  v_purpose varchar;
  v_status varchar;
  v_active_count integer;
  v_response jsonb;
begin
  if not admin.account_has_permission(p_actor_account_id,'privacy.admin.write') then
    raise exception using errcode='42501',message='permission_denied';
  end if;
  if p_idempotency_key is null or length(p_idempotency_key) not between 8 and 180
     or p_request_hash is null or length(p_request_hash)<>64 then
    raise exception using errcode='22023',message='idempotency_invalid';
  end if;

  insert into admin.idempotency_keys(actor_account_id,operation,idempotency_key,request_hash,status)
  values(p_actor_account_id,'privacy.legal.retire',p_idempotency_key,p_request_hash,'Processing')
  on conflict do nothing;
  get diagnostics v_inserted=row_count;
  if v_inserted=0 then
    select * into v_existing from admin.idempotency_keys
    where actor_account_id=p_actor_account_id and operation='privacy.legal.retire'
      and idempotency_key=p_idempotency_key for update;
    if v_existing.request_hash<>p_request_hash then
      return jsonb_build_object('httpStatus',409,'code','idempotency_conflict');
    end if;
    if v_existing.status='Completed' and v_existing.response_json is not null then
      return v_existing.response_json || jsonb_build_object('replayed',true);
    end if;
    return jsonb_build_object('httpStatus',409,'code','operation_in_progress');
  end if;

  select purpose,status into v_purpose,v_status
  from consent.consent_documents where id=p_document_id for update;
  if not found or v_purpose not in ('legal_terms','privacy_notice') then
    return jsonb_build_object('httpStatus',404,'code','legal_document_not_found');
  end if;
  if v_status='Active' then
    select count(*)::integer into v_active_count
    from consent.consent_documents
    where purpose=v_purpose and status='Active' and id<>p_document_id;
    if v_active_count=0 then
      return jsonb_build_object('httpStatus',409,'code','last_active_legal_document');
    end if;
  end if;

  update consent.consent_documents set status='Retired' where id=p_document_id;
  insert into admin.audit_events(actor_account_id,action,resource_type,resource_id,result,correlation_id,metadata_json)
  values(p_actor_account_id,'privacy.legal.retire','ConsentDocument',p_document_id::text,'Succeeded',p_correlation_id,
    jsonb_build_object('purpose',v_purpose));
  v_response=jsonb_build_object('httpStatus',200,'code','legal_document_retired','documentId',p_document_id,'replayed',false);
  update admin.idempotency_keys set status='Completed',response_status=200,response_json=v_response,updated_at_utc=now()
  where actor_account_id=p_actor_account_id and operation='privacy.legal.retire'
    and idempotency_key=p_idempotency_key;
  return v_response;
end
$$;

create or replace function admin.update_privacy_purpose_idempotent(
  p_actor_account_id uuid,
  p_purpose varchar,
  p_policy_version varchar,
  p_description varchar,
  p_status varchar,
  p_correlation_id uuid,
  p_idempotency_key varchar,
  p_request_hash varchar
) returns jsonb
language plpgsql
security definer
set search_path = pg_catalog,admin,consent
as $$
declare
  v_inserted integer;
  v_existing admin.idempotency_keys%rowtype;
  v_response jsonb;
begin
  if not admin.account_has_permission(p_actor_account_id,'privacy.admin.write') then
    raise exception using errcode='42501',message='permission_denied';
  end if;
  if p_purpose is null or p_purpose !~ '^[a-z][a-z0-9._-]{2,79}$'
     or p_policy_version is null or length(trim(p_policy_version)) not between 1 and 64
     or p_description is null or length(trim(p_description)) not between 5 and 240
     or p_status not in ('Active','Retired') then
    raise exception using errcode='22023',message='privacy_purpose_invalid';
  end if;
  if p_idempotency_key is null or length(p_idempotency_key) not between 8 and 180
     or p_request_hash is null or length(p_request_hash)<>64 then
    raise exception using errcode='22023',message='idempotency_invalid';
  end if;

  insert into admin.idempotency_keys(actor_account_id,operation,idempotency_key,request_hash,status)
  values(p_actor_account_id,'privacy.purpose.update',p_idempotency_key,p_request_hash,'Processing')
  on conflict do nothing;
  get diagnostics v_inserted=row_count;
  if v_inserted=0 then
    select * into v_existing from admin.idempotency_keys
    where actor_account_id=p_actor_account_id and operation='privacy.purpose.update'
      and idempotency_key=p_idempotency_key for update;
    if v_existing.request_hash<>p_request_hash then
      return jsonb_build_object('httpStatus',409,'code','idempotency_conflict');
    end if;
    if v_existing.status='Completed' and v_existing.response_json is not null then
      return v_existing.response_json || jsonb_build_object('replayed',true);
    end if;
    return jsonb_build_object('httpStatus',409,'code','operation_in_progress');
  end if;

  update consent.preference_purposes
  set policy_version=trim(p_policy_version),description=trim(p_description),status=p_status,updated_at_utc=now()
  where purpose=p_purpose;
  if not found then
    return jsonb_build_object('httpStatus',404,'code','privacy_purpose_not_found');
  end if;

  insert into admin.audit_events(actor_account_id,action,resource_type,resource_id,result,correlation_id,metadata_json)
  values(p_actor_account_id,'privacy.purpose.update','PrivacyPurpose',p_purpose,'Succeeded',p_correlation_id,
    jsonb_build_object('policyVersion',p_policy_version,'status',p_status));
  v_response=jsonb_build_object('httpStatus',200,'code','privacy_purpose_updated','purpose',p_purpose,'replayed',false);
  update admin.idempotency_keys set status='Completed',response_status=200,response_json=v_response,updated_at_utc=now()
  where actor_account_id=p_actor_account_id and operation='privacy.purpose.update'
    and idempotency_key=p_idempotency_key;
  return v_response;
end
$$;

revoke all on function admin.privacy_legal_snapshot(uuid,varchar) from public;
revoke all on function admin.publish_legal_document_idempotent(uuid,varchar,varchar,varchar,varchar,varchar,text,timestamptz,uuid,varchar,varchar) from public;
revoke all on function admin.retire_legal_document_idempotent(uuid,uuid,uuid,varchar,varchar) from public;
revoke all on function admin.update_privacy_purpose_idempotent(uuid,varchar,varchar,varchar,varchar,uuid,varchar,varchar) from public;

do $$
begin
  if exists(select 1 from pg_roles where rolname='lifemate_admin_runtime') then
    grant execute on function admin.privacy_legal_snapshot(uuid,varchar) to lifemate_admin_runtime;
    grant execute on function admin.publish_legal_document_idempotent(uuid,varchar,varchar,varchar,varchar,varchar,text,timestamptz,uuid,varchar,varchar) to lifemate_admin_runtime;
    grant execute on function admin.retire_legal_document_idempotent(uuid,uuid,uuid,varchar,varchar) to lifemate_admin_runtime;
    grant execute on function admin.update_privacy_purpose_idempotent(uuid,varchar,varchar,varchar,varchar,uuid,varchar,varchar) to lifemate_admin_runtime;
  end if;
end
$$;

commit;
