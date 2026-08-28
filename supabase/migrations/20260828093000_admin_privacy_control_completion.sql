begin;

-- Complete Core #565 on the existing consent model. This migration adds only
-- narrow Admin contracts; it never creates a second consent/preference store.

create or replace function consent.admin_acceptance_coverage(
  p_actor_account_id uuid,
  p_jurisdiction varchar default 'GLOBAL'
) returns jsonb
language plpgsql
stable
security definer
set search_path=pg_catalog,consent,identity,admin
as $$
declare
  v_result jsonb;
begin
  if not admin.account_has_permission(p_actor_account_id,'privacy.consent.read',now()) then
    raise exception 'privacy_coverage_forbidden' using errcode='42501';
  end if;

  with eligible as (
    select count(*)::integer as account_count
    from identity.accounts a
    where a.status='Active'
  ), required_docs as (
    select * from consent.current_registration_legal_documents(p_jurisdiction)
  ), coverage as (
    select
      d.id,
      d.purpose,
      d.version,
      d.jurisdiction,
      d.title,
      d.document_hash,
      d.effective_at_utc,
      count(distinct a.account_id)::integer as accepted_count
    from required_docs d
    left join consent.legal_acceptances a
      on a.document_id=d.id and a.document_hash=d.document_hash
    group by d.id,d.purpose,d.version,d.jurisdiction,d.title,d.document_hash,d.effective_at_utc
  )
  select jsonb_build_object(
    'jurisdiction',p_jurisdiction,
    'eligibleAccountCount',e.account_count,
    'requiredDocumentCount',(select count(*) from coverage),
    'items',coalesce((
      select jsonb_agg(jsonb_build_object(
        'documentId',c.id,
        'purpose',c.purpose,
        'version',c.version,
        'jurisdiction',c.jurisdiction,
        'title',c.title,
        'documentHash',c.document_hash,
        'effectiveAtUtc',c.effective_at_utc,
        'acceptedAccountCount',c.accepted_count,
        'coveragePercent',case when e.account_count=0 then 0
          else round((c.accepted_count::numeric/e.account_count::numeric)*100,2) end
      ) order by c.purpose,c.version)
      from coverage c
    ),'[]'::jsonb)
  ) into v_result
  from eligible e;

  return v_result;
end
$$;

create or replace function consent.admin_preference_purpose_catalog(
  p_actor_account_id uuid
) returns jsonb
language plpgsql
stable
security definer
set search_path=pg_catalog,consent,admin
as $$
declare v_result jsonb;
begin
  if not admin.account_has_permission(p_actor_account_id,'privacy.consent.read',now()) then
    raise exception 'privacy_purpose_catalog_forbidden' using errcode='42501';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'purpose',p.purpose,
    'category',p.category,
    'channel',p.channel,
    'policyVersion',p.policy_version,
    'defaultEnabled',p.default_enabled,
    'userMutable',p.user_mutable,
    'status',p.status,
    'description',p.description,
    'createdAtUtc',p.created_at_utc,
    'updatedAtUtc',p.updated_at_utc
  ) order by p.category,p.purpose),'[]'::jsonb)
  into v_result
  from consent.preference_purposes p;
  return jsonb_build_object('items',v_result);
end
$$;

create or replace function consent.admin_account_privacy_summary(
  p_actor_account_id uuid,
  p_account_id uuid,
  p_jurisdiction varchar default 'GLOBAL'
) returns jsonb
language plpgsql
stable
security definer
set search_path=pg_catalog,consent,identity,core,admin
as $$
declare
  v_person_id uuid;
  v_required integer:=0;
  v_accepted integer:=0;
  v_preferences jsonb:='[]'::jsonb;
begin
  if not admin.account_has_permission(p_actor_account_id,'privacy.consent.read',now()) then
    raise exception 'privacy_account_summary_forbidden' using errcode='42501';
  end if;
  if not exists(select 1 from identity.accounts where id=p_account_id) then
    raise exception 'privacy_account_not_found' using errcode='P0002';
  end if;

  select l.person_id into v_person_id
  from core.account_person_links l
  where l.account_id=p_account_id and l.link_type='Self' and l.status='Active'
  order by l.created_at_utc limit 1;

  with required_docs as (
    select * from consent.current_registration_legal_documents(p_jurisdiction)
  )
  select count(*)::integer,
         count(*) filter (where exists(
           select 1 from consent.legal_acceptances a
           where a.account_id=p_account_id
             and a.document_id=d.id
             and a.document_hash=d.document_hash
         ))::integer
  into v_required,v_accepted
  from required_docs d;

  if v_person_id is not null then
    select coalesce(jsonb_agg(jsonb_build_object(
      'purpose',p.purpose,
      'category',p.category,
      'channel',p.channel,
      'policyVersion',p.policy_version,
      'enabled',coalesce(c.status='OptedIn',p.default_enabled),
      'explicit',c.id is not null,
      'userMutable',p.user_mutable,
      'updatedAtUtc',c.updated_at_utc
    ) order by p.category,p.purpose),'[]'::jsonb)
    into v_preferences
    from consent.preference_purposes p
    left join consent.data_use_consents c
      on c.subject_person_id=v_person_id
     and c.purpose=p.purpose
     and c.jurisdiction=p_jurisdiction
     and c.policy_version=p.policy_version
    where p.status='Active';
  end if;

  return jsonb_build_object(
    'accountId',p_account_id,
    'jurisdiction',p_jurisdiction,
    'legal',jsonb_build_object(
      'requiredDocumentCount',v_required,
      'acceptedDocumentCount',v_accepted,
      'complete',v_required=0 or v_required=v_accepted
    ),
    'preferences',v_preferences
  );
end
$$;

create or replace function consent.admin_create_document(
  p_actor_account_id uuid,
  p_purpose varchar,
  p_version varchar,
  p_jurisdiction varchar,
  p_title varchar,
  p_document_hash varchar,
  p_content_uri text,
  p_effective_at_utc timestamptz,
  p_reason varchar,
  p_correlation_id uuid
) returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,consent,admin
as $$
declare v consent.consent_documents%rowtype;
begin
  if not admin.account_has_permission(p_actor_account_id,'privacy.consent.manage',now()) then
    raise exception 'privacy_document_create_forbidden' using errcode='42501';
  end if;
  if p_purpose not in ('legal_terms','privacy_notice')
     or p_version is null or length(btrim(p_version))<1 or length(p_version)>64
     or p_jurisdiction is null or p_jurisdiction !~ '^[A-Za-z0-9*_-]{1,16}$'
     or p_title is null or length(btrim(p_title))<3 or length(p_title)>200
     or p_document_hash is null or length(p_document_hash)<32 or length(p_document_hash)>128
     or p_content_uri is null or p_content_uri !~ '^https://'
     or p_reason is null or p_reason !~ '^[a-z0-9_.-]{3,80}$'
     or p_correlation_id is null then
    raise exception 'privacy_document_create_invalid' using errcode='22023';
  end if;

  insert into consent.consent_documents(
    purpose,version,jurisdiction,title,document_hash,content_uri,status,effective_at_utc,
    created_at_utc,updated_at_utc
  ) values(
    p_purpose,btrim(p_version),upper(p_jurisdiction),btrim(p_title),p_document_hash,p_content_uri,
    'Draft',p_effective_at_utc,now(),now()
  ) returning * into v;

  insert into admin.audit_events(
    actor_account_id,action,resource_type,resource_id,result,reason,
    correlation_id,request_id,elevated_access,metadata_json
  ) values(
    p_actor_account_id,'privacy.document.created','consent_document',v.id::text,'Succeeded',
    p_reason,p_correlation_id,null,false,
    jsonb_build_object('purpose',v.purpose,'version',v.version,'jurisdiction',v.jurisdiction,'status',v.status)
  );

  return jsonb_build_object('httpStatus',201,'documentId',v.id,'status',v.status,
    'updatedAtUtc',v.updated_at_utc,'effectiveAtUtc',v.effective_at_utc);
exception when unique_violation then
  return jsonb_build_object('httpStatus',409,'code','privacy_document_version_exists','message','Document version already exists.');
end
$$;

create or replace function consent.admin_publish_document(
  p_actor_account_id uuid,
  p_document_id uuid,
  p_expected_updated_at timestamptz,
  p_effective_at_utc timestamptz,
  p_reason varchar,
  p_correlation_id uuid
) returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,consent,admin
as $$
declare v consent.consent_documents%rowtype;
begin
  if not admin.account_has_permission(p_actor_account_id,'privacy.consent.manage',now()) then
    raise exception 'privacy_document_publish_forbidden' using errcode='42501';
  end if;
  if p_document_id is null or p_expected_updated_at is null or p_effective_at_utc is null
     or p_reason is null or p_reason !~ '^[a-z0-9_.-]{3,80}$' or p_correlation_id is null then
    raise exception 'privacy_document_publish_invalid' using errcode='22023';
  end if;
  select * into v from consent.consent_documents where id=p_document_id for update;
  if not found then raise exception 'privacy_document_not_found' using errcode='P0002'; end if;
  if v.updated_at_utc is distinct from p_expected_updated_at then
    raise exception 'privacy_document_version_conflict' using errcode='40001';
  end if;
  if v.status<>'Draft' then raise exception 'privacy_document_publish_state_invalid' using errcode='55000'; end if;
  if v.purpose not in ('legal_terms','privacy_notice') or v.document_hash is null
     or length(v.document_hash)<32 or v.content_uri is null or v.content_uri !~ '^https://' then
    raise exception 'privacy_document_publish_contract_invalid' using errcode='22023';
  end if;

  -- Serialize publication within one purpose/jurisdiction. Future-effective versions may
  -- coexist with the currently-effective document; current_registration_legal_documents
  -- remains authoritative for which version is required at a point in time.
  perform pg_advisory_xact_lock(hashtextextended(v.purpose||':'||v.jurisdiction,0));
  update consent.consent_documents
  set status='Active',effective_at_utc=p_effective_at_utc,updated_at_utc=now()
  where id=v.id returning * into v;

  insert into admin.audit_events(
    actor_account_id,action,resource_type,resource_id,result,reason,
    correlation_id,request_id,elevated_access,metadata_json
  ) values(
    p_actor_account_id,'privacy.document.published','consent_document',v.id::text,'Succeeded',
    p_reason,p_correlation_id,null,false,
    jsonb_build_object('purpose',v.purpose,'version',v.version,'jurisdiction',v.jurisdiction,'effectiveAtUtc',v.effective_at_utc)
  );
  return jsonb_build_object('httpStatus',200,'documentId',v.id,'status',v.status,
    'updatedAtUtc',v.updated_at_utc,'effectiveAtUtc',v.effective_at_utc);
end
$$;

create or replace function consent.admin_update_preference_purpose(
  p_actor_account_id uuid,
  p_purpose varchar,
  p_expected_updated_at timestamptz,
  p_description varchar,
  p_policy_version varchar,
  p_status varchar,
  p_reason varchar,
  p_correlation_id uuid
) returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,consent,admin
as $$
declare v consent.preference_purposes%rowtype;
begin
  if not admin.account_has_permission(p_actor_account_id,'privacy.consent.manage',now()) then
    raise exception 'privacy_purpose_update_forbidden' using errcode='42501';
  end if;
  if p_purpose is null or p_expected_updated_at is null
     or p_description is null or length(btrim(p_description))<3 or length(p_description)>240
     or p_policy_version is null or p_policy_version !~ '^[A-Za-z0-9._-]{1,64}$'
     or p_status not in ('Active','Retired')
     or p_reason is null or p_reason !~ '^[a-z0-9_.-]{3,80}$' or p_correlation_id is null then
    raise exception 'privacy_purpose_update_invalid' using errcode='22023';
  end if;
  select * into v from consent.preference_purposes where purpose=p_purpose for update;
  if not found then raise exception 'privacy_purpose_not_found' using errcode='P0002'; end if;
  if v.updated_at_utc is distinct from p_expected_updated_at then
    raise exception 'privacy_purpose_version_conflict' using errcode='40001';
  end if;

  -- category/channel/default_enabled/user_mutable are deliberately immutable here.
  -- In particular, Admin cannot turn a catalog default on and thereby opt users in.
  update consent.preference_purposes
  set description=btrim(p_description),policy_version=p_policy_version,status=p_status,updated_at_utc=now()
  where purpose=v.purpose returning * into v;

  insert into admin.audit_events(
    actor_account_id,action,resource_type,resource_id,result,reason,
    correlation_id,request_id,elevated_access,metadata_json
  ) values(
    p_actor_account_id,'privacy.preference_purpose.updated','privacy_preference_purpose',v.purpose,
    'Succeeded',p_reason,p_correlation_id,null,false,
    jsonb_build_object('policyVersion',v.policy_version,'status',v.status)
  );
  return jsonb_build_object('httpStatus',200,'purpose',v.purpose,'policyVersion',v.policy_version,
    'status',v.status,'updatedAtUtc',v.updated_at_utc);
end
$$;

-- Idempotent mutation wrappers share the existing Admin idempotency ledger.
create or replace function consent.admin_create_document_idempotent(
  p_actor_account_id uuid,p_purpose varchar,p_version varchar,p_jurisdiction varchar,p_title varchar,
  p_document_hash varchar,p_content_uri text,p_effective_at_utc timestamptz,p_reason varchar,
  p_correlation_id uuid,p_idempotency_key varchar,p_request_hash varchar
) returns jsonb language plpgsql security definer set search_path=pg_catalog,consent,admin as $$
declare v_operation constant varchar(120):='privacy.document.create'; v_existing admin.idempotency_keys%rowtype; v_response jsonb;
begin
  if p_idempotency_key is null or length(p_idempotency_key)<8 or length(p_idempotency_key)>180
     or p_request_hash is null or length(p_request_hash)<32 or length(p_request_hash)>128 then
    return jsonb_build_object('httpStatus',400,'code','idempotency_invalid','replayed',false);
  end if;
  perform pg_advisory_xact_lock(hashtextextended(p_actor_account_id::text||':'||v_operation||':'||p_idempotency_key,0));
  select * into v_existing from admin.idempotency_keys where actor_account_id=p_actor_account_id and operation=v_operation and idempotency_key=p_idempotency_key for update;
  if found then
    if v_existing.request_hash<>p_request_hash then return jsonb_build_object('httpStatus',409,'code','idempotency_conflict','replayed',false); end if;
    if v_existing.status='Completed' and v_existing.response_json is not null then return v_existing.response_json||jsonb_build_object('replayed',true); end if;
    return jsonb_build_object('httpStatus',409,'code','idempotency_in_progress','replayed',false);
  end if;
  insert into admin.idempotency_keys(actor_account_id,operation,idempotency_key,request_hash,status) values(p_actor_account_id,v_operation,p_idempotency_key,p_request_hash,'Processing');
  v_response:=consent.admin_create_document(p_actor_account_id,p_purpose,p_version,p_jurisdiction,p_title,p_document_hash,p_content_uri,p_effective_at_utc,p_reason,p_correlation_id)||jsonb_build_object('replayed',false);
  update admin.idempotency_keys set status='Completed',response_status=(v_response->>'httpStatus')::integer,response_json=v_response,updated_at_utc=now() where actor_account_id=p_actor_account_id and operation=v_operation and idempotency_key=p_idempotency_key;
  return v_response;
end $$;

create or replace function consent.admin_publish_document_idempotent(
  p_actor_account_id uuid,p_document_id uuid,p_expected_updated_at timestamptz,p_effective_at_utc timestamptz,
  p_reason varchar,p_correlation_id uuid,p_idempotency_key varchar,p_request_hash varchar
) returns jsonb language plpgsql security definer set search_path=pg_catalog,consent,admin as $$
declare v_operation constant varchar(120):='privacy.document.publish'; v_existing admin.idempotency_keys%rowtype; v_response jsonb;
begin
  if p_idempotency_key is null or length(p_idempotency_key)<8 or length(p_idempotency_key)>180 or p_request_hash is null or length(p_request_hash)<32 or length(p_request_hash)>128 then return jsonb_build_object('httpStatus',400,'code','idempotency_invalid','replayed',false); end if;
  perform pg_advisory_xact_lock(hashtextextended(p_actor_account_id::text||':'||v_operation||':'||p_idempotency_key,0));
  select * into v_existing from admin.idempotency_keys where actor_account_id=p_actor_account_id and operation=v_operation and idempotency_key=p_idempotency_key for update;
  if found then if v_existing.request_hash<>p_request_hash then return jsonb_build_object('httpStatus',409,'code','idempotency_conflict','replayed',false); end if; if v_existing.status='Completed' and v_existing.response_json is not null then return v_existing.response_json||jsonb_build_object('replayed',true); end if; return jsonb_build_object('httpStatus',409,'code','idempotency_in_progress','replayed',false); end if;
  insert into admin.idempotency_keys(actor_account_id,operation,idempotency_key,request_hash,status) values(p_actor_account_id,v_operation,p_idempotency_key,p_request_hash,'Processing');
  v_response:=consent.admin_publish_document(p_actor_account_id,p_document_id,p_expected_updated_at,p_effective_at_utc,p_reason,p_correlation_id)||jsonb_build_object('replayed',false);
  update admin.idempotency_keys set status='Completed',response_status=(v_response->>'httpStatus')::integer,response_json=v_response,updated_at_utc=now() where actor_account_id=p_actor_account_id and operation=v_operation and idempotency_key=p_idempotency_key; return v_response;
end $$;

create or replace function consent.admin_retire_document_idempotent(
  p_actor_account_id uuid,p_document_id uuid,p_expected_updated_at timestamptz,p_reason varchar,
  p_correlation_id uuid,p_idempotency_key varchar,p_request_hash varchar
) returns jsonb language plpgsql security definer set search_path=pg_catalog,consent,admin as $$
declare v_operation constant varchar(120):='privacy.document.retire'; v_existing admin.idempotency_keys%rowtype; v_response jsonb;
begin
  if p_idempotency_key is null or length(p_idempotency_key)<8 or length(p_idempotency_key)>180 or p_request_hash is null or length(p_request_hash)<32 or length(p_request_hash)>128 then return jsonb_build_object('httpStatus',400,'code','idempotency_invalid','replayed',false); end if;
  perform pg_advisory_xact_lock(hashtextextended(p_actor_account_id::text||':'||v_operation||':'||p_idempotency_key,0));
  select * into v_existing from admin.idempotency_keys where actor_account_id=p_actor_account_id and operation=v_operation and idempotency_key=p_idempotency_key for update;
  if found then if v_existing.request_hash<>p_request_hash then return jsonb_build_object('httpStatus',409,'code','idempotency_conflict','replayed',false); end if; if v_existing.status='Completed' and v_existing.response_json is not null then return v_existing.response_json||jsonb_build_object('replayed',true); end if; return jsonb_build_object('httpStatus',409,'code','idempotency_in_progress','replayed',false); end if;
  insert into admin.idempotency_keys(actor_account_id,operation,idempotency_key,request_hash,status) values(p_actor_account_id,v_operation,p_idempotency_key,p_request_hash,'Processing');
  v_response:=consent.admin_retire_document(p_actor_account_id,p_document_id,p_expected_updated_at,p_reason,p_correlation_id)||jsonb_build_object('httpStatus',200,'replayed',false);
  update admin.idempotency_keys set status='Completed',response_status=200,response_json=v_response,updated_at_utc=now() where actor_account_id=p_actor_account_id and operation=v_operation and idempotency_key=p_idempotency_key; return v_response;
end $$;

create or replace function consent.admin_update_preference_purpose_idempotent(
  p_actor_account_id uuid,p_purpose varchar,p_expected_updated_at timestamptz,p_description varchar,
  p_policy_version varchar,p_status varchar,p_reason varchar,p_correlation_id uuid,
  p_idempotency_key varchar,p_request_hash varchar
) returns jsonb language plpgsql security definer set search_path=pg_catalog,consent,admin as $$
declare v_operation constant varchar(120):='privacy.preference_purpose.update'; v_existing admin.idempotency_keys%rowtype; v_response jsonb;
begin
  if p_idempotency_key is null or length(p_idempotency_key)<8 or length(p_idempotency_key)>180 or p_request_hash is null or length(p_request_hash)<32 or length(p_request_hash)>128 then return jsonb_build_object('httpStatus',400,'code','idempotency_invalid','replayed',false); end if;
  perform pg_advisory_xact_lock(hashtextextended(p_actor_account_id::text||':'||v_operation||':'||p_idempotency_key,0));
  select * into v_existing from admin.idempotency_keys where actor_account_id=p_actor_account_id and operation=v_operation and idempotency_key=p_idempotency_key for update;
  if found then if v_existing.request_hash<>p_request_hash then return jsonb_build_object('httpStatus',409,'code','idempotency_conflict','replayed',false); end if; if v_existing.status='Completed' and v_existing.response_json is not null then return v_existing.response_json||jsonb_build_object('replayed',true); end if; return jsonb_build_object('httpStatus',409,'code','idempotency_in_progress','replayed',false); end if;
  insert into admin.idempotency_keys(actor_account_id,operation,idempotency_key,request_hash,status) values(p_actor_account_id,v_operation,p_idempotency_key,p_request_hash,'Processing');
  v_response:=consent.admin_update_preference_purpose(p_actor_account_id,p_purpose,p_expected_updated_at,p_description,p_policy_version,p_status,p_reason,p_correlation_id)||jsonb_build_object('replayed',false);
  update admin.idempotency_keys set status='Completed',response_status=(v_response->>'httpStatus')::integer,response_json=v_response,updated_at_utc=now() where actor_account_id=p_actor_account_id and operation=v_operation and idempotency_key=p_idempotency_key; return v_response;
end $$;

revoke all on function consent.admin_acceptance_coverage(uuid,varchar) from public;
revoke all on function consent.admin_preference_purpose_catalog(uuid) from public;
revoke all on function consent.admin_account_privacy_summary(uuid,uuid,varchar) from public;
revoke all on function consent.admin_create_document(uuid,varchar,varchar,varchar,varchar,varchar,text,timestamptz,varchar,uuid) from public;
revoke all on function consent.admin_publish_document(uuid,uuid,timestamptz,timestamptz,varchar,uuid) from public;
revoke all on function consent.admin_update_preference_purpose(uuid,varchar,timestamptz,varchar,varchar,varchar,varchar,uuid) from public;
revoke all on function consent.admin_create_document_idempotent(uuid,varchar,varchar,varchar,varchar,varchar,text,timestamptz,varchar,uuid,varchar,varchar) from public;
revoke all on function consent.admin_publish_document_idempotent(uuid,uuid,timestamptz,timestamptz,varchar,uuid,varchar,varchar) from public;
revoke all on function consent.admin_retire_document_idempotent(uuid,uuid,timestamptz,varchar,uuid,varchar,varchar) from public;
revoke all on function consent.admin_update_preference_purpose_idempotent(uuid,varchar,timestamptz,varchar,varchar,varchar,varchar,uuid,varchar,varchar) from public;

do $$ declare v_role text; begin
  foreach v_role in array array['anon','authenticated'] loop
    if exists(select 1 from pg_roles where rolname=v_role) then
      execute format('revoke all on function consent.admin_acceptance_coverage(uuid,varchar) from %I',v_role);
      execute format('revoke all on function consent.admin_preference_purpose_catalog(uuid) from %I',v_role);
      execute format('revoke all on function consent.admin_account_privacy_summary(uuid,uuid,varchar) from %I',v_role);
      execute format('revoke all on function consent.admin_create_document_idempotent(uuid,varchar,varchar,varchar,varchar,varchar,text,timestamptz,varchar,uuid,varchar,varchar) from %I',v_role);
      execute format('revoke all on function consent.admin_publish_document_idempotent(uuid,uuid,timestamptz,timestamptz,varchar,uuid,varchar,varchar) from %I',v_role);
      execute format('revoke all on function consent.admin_retire_document_idempotent(uuid,uuid,timestamptz,varchar,uuid,varchar,varchar) from %I',v_role);
      execute format('revoke all on function consent.admin_update_preference_purpose_idempotent(uuid,varchar,timestamptz,varchar,varchar,varchar,varchar,uuid,varchar,varchar) from %I',v_role);
    end if;
  end loop;
end $$;

grant execute on function consent.admin_acceptance_coverage(uuid,varchar) to lifemate_admin_runtime;
grant execute on function consent.admin_preference_purpose_catalog(uuid) to lifemate_admin_runtime;
grant execute on function consent.admin_account_privacy_summary(uuid,uuid,varchar) to lifemate_admin_runtime;
grant execute on function consent.admin_create_document_idempotent(uuid,varchar,varchar,varchar,varchar,varchar,text,timestamptz,varchar,uuid,varchar,varchar) to lifemate_admin_runtime;
grant execute on function consent.admin_publish_document_idempotent(uuid,uuid,timestamptz,timestamptz,varchar,uuid,varchar,varchar) to lifemate_admin_runtime;
grant execute on function consent.admin_retire_document_idempotent(uuid,uuid,timestamptz,varchar,uuid,varchar,varchar) to lifemate_admin_runtime;
grant execute on function consent.admin_update_preference_purpose_idempotent(uuid,varchar,timestamptz,varchar,varchar,varchar,varchar,uuid,varchar,varchar) to lifemate_admin_runtime;

commit;
