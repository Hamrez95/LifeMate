begin;

create or replace function consent.admin_legal_acceptance_coverage(
  p_actor_account_id uuid,
  p_jurisdiction varchar default 'GLOBAL'
) returns jsonb
language plpgsql
stable
security definer
set search_path=pg_catalog,consent,identity,admin
as $$
declare v_items jsonb; v_active_accounts bigint;
begin
  if p_actor_account_id is null or not admin.account_has_permission(p_actor_account_id,'privacy.consent.read') then
    raise exception 'privacy_read_forbidden' using errcode='42501';
  end if;
  select count(*) into v_active_accounts from identity.accounts where status='Active';
  select coalesce(jsonb_agg(jsonb_build_object(
    'documentId',d.id,'purpose',d.purpose,'version',d.version,'jurisdiction',d.jurisdiction,
    'documentHash',d.document_hash,'effectiveAtUtc',d.effective_at_utc,
    'acceptedCount',d.accepted_count,'eligibleAccountCount',v_active_accounts,
    'coveragePercent',case when v_active_accounts=0 then 100 else round((d.accepted_count::numeric*100)/v_active_accounts,2) end
  ) order by d.purpose,d.jurisdiction,d.version),'[]'::jsonb) into v_items
  from (
    select r.id,r.purpose,r.version,r.jurisdiction,r.document_hash,r.effective_at_utc,
      count(la.account_id) filter(where la.document_hash=r.document_hash)::bigint as accepted_count
    from consent.current_registration_legal_documents(p_jurisdiction) r
    left join consent.legal_acceptances la on la.document_id=r.id
    group by r.id,r.purpose,r.version,r.jurisdiction,r.document_hash,r.effective_at_utc
  ) d;
  return jsonb_build_object(
    'items',v_items,'eligibleAccountCount',v_active_accounts,
    'source','consent.current_registration_legal_documents+consent.legal_acceptances',
    'asOfUtc',now()
  );
end $$;

create or replace function consent.admin_user_privacy_summary(
  p_actor_account_id uuid,
  p_target_account_id uuid
) returns jsonb
language plpgsql
stable
security definer
set search_path=pg_catalog,consent,core,admin
as $$
declare v_person_id uuid; v_acceptances jsonb; v_preferences jsonb; v_consents jsonb;
begin
  if p_actor_account_id is null or not admin.account_has_permission(p_actor_account_id,'privacy.consent.read') then
    raise exception 'privacy_read_forbidden' using errcode='42501';
  end if;
  select person_id into v_person_id from core.account_person_links
    where account_id=p_target_account_id and link_type='Self' and status='Active' limit 1;
  select coalesce(jsonb_agg(jsonb_build_object(
    'documentId',a.document_id,'purpose',d.purpose,'version',d.version,
    'jurisdiction',d.jurisdiction,'acceptedAtUtc',a.accepted_at_utc,'source',a.source
  ) order by a.accepted_at_utc desc),'[]'::jsonb)
  into v_acceptances
  from consent.legal_acceptances a join consent.consent_documents d on d.id=a.document_id
  where a.account_id=p_target_account_id;
  select coalesce(jsonb_agg(jsonb_build_object(
    'purpose',p.purpose,'category',p.category,'channel',p.channel,'policyVersion',p.policy_version,
    'enabled',coalesce(c.status='OptedIn',p.default_enabled),'explicit',c.id is not null,
    'status',coalesce(c.status,'Default')
  ) order by p.category,p.purpose),'[]'::jsonb)
  into v_preferences
  from consent.preference_purposes p
  left join consent.data_use_consents c
    on c.subject_person_id=v_person_id and c.purpose=p.purpose and c.policy_version=p.policy_version
  where p.status='Active';
  select coalesce(jsonb_agg(jsonb_build_object(
    'consentRecordId',r.id,'purpose',r.purpose,'scopeKey',r.scope_key,'status',r.status,
    'grantedAtUtc',r.granted_at_utc,'revokedAtUtc',r.revoked_at_utc,'expiresAtUtc',r.expires_at_utc
  ) order by r.updated_at_utc desc),'[]'::jsonb)
  into v_consents
  from consent.consent_records r where r.subject_person_id=v_person_id;
  return jsonb_build_object(
    'accountId',p_target_account_id,'subjectPersonId',v_person_id,
    'legalAcceptances',v_acceptances,'preferences',v_preferences,'consents',v_consents,
    'mutableFromAdmin',false,'asOfUtc',now()
  );
end $$;

create or replace function consent.admin_create_document_draft_idempotent(
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
set search_path=pg_catalog,consent,admin
as $$
declare v_inserted integer; v_key admin.idempotency_keys%rowtype; v_doc consent.consent_documents%rowtype; v_response jsonb;
begin
  if p_actor_account_id is null or not admin.account_has_permission(p_actor_account_id,'privacy.consent.manage') then
    raise exception 'privacy_manage_forbidden' using errcode='42501';
  end if;
  if p_purpose not in ('legal_terms','privacy_notice') or p_version !~ '^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$'
     or p_jurisdiction !~ '^[A-Za-z0-9*-]{1,16}$' or char_length(btrim(p_title)) not between 3 and 200
     or p_document_hash !~ '^[0-9a-fA-F]{32,128}$' or p_content_uri !~ '^https://'
     or p_effective_at_utc is null or char_length(btrim(coalesce(p_reason,''))) not between 3 and 500
     or p_correlation_id is null or char_length(p_idempotency_key) not between 8 and 180
     or p_request_hash !~ '^[0-9a-f]{64}$' then
    raise exception 'privacy_document_payload_invalid' using errcode='22023';
  end if;
  insert into admin.idempotency_keys(actor_account_id,operation,idempotency_key,request_hash,status)
  values(p_actor_account_id,'privacy.document.create',p_idempotency_key,p_request_hash,'Processing')
  on conflict do nothing; get diagnostics v_inserted=row_count;
  if v_inserted=0 then
    select * into v_key from admin.idempotency_keys
      where actor_account_id=p_actor_account_id and operation='privacy.document.create' and idempotency_key=p_idempotency_key for update;
    if v_key.request_hash<>p_request_hash then return jsonb_build_object('httpStatus',409,'code','idempotency_conflict'); end if;
    if v_key.status='Completed' and v_key.response_json is not null then return v_key.response_json||jsonb_build_object('replayed',true); end if;
    return jsonb_build_object('httpStatus',409,'code','operation_in_progress');
  end if;
  insert into consent.consent_documents(purpose,version,jurisdiction,title,document_hash,status,effective_at_utc,content_uri,updated_at_utc)
  values(p_purpose,p_version,upper(p_jurisdiction),btrim(p_title),lower(p_document_hash),'Draft',p_effective_at_utc,p_content_uri,now())
  returning * into v_doc;
  insert into admin.audit_events(actor_account_id,action,resource_type,resource_id,result,reason,correlation_id,elevated_access,metadata_json)
  values(p_actor_account_id,'privacy.document.created','consent_document',v_doc.id::text,'Succeeded',btrim(p_reason),p_correlation_id,false,
    jsonb_build_object('purpose',v_doc.purpose,'version',v_doc.version,'jurisdiction',v_doc.jurisdiction));
  v_response:=jsonb_build_object('httpStatus',201,'code','ok','documentId',v_doc.id,'status',v_doc.status,'updatedAtUtc',v_doc.updated_at_utc,'replayed',false);
  update admin.idempotency_keys set status='Completed',response_status=201,response_json=v_response,updated_at_utc=now()
    where actor_account_id=p_actor_account_id and operation='privacy.document.create' and idempotency_key=p_idempotency_key;
  return v_response;
exception when unique_violation then
  raise exception 'privacy_document_version_exists' using errcode='23505';
end $$;

create or replace function consent.admin_publish_document_idempotent(
  p_actor_account_id uuid,
  p_document_id uuid,
  p_expected_updated_at timestamptz,
  p_reason varchar,
  p_correlation_id uuid,
  p_idempotency_key varchar,
  p_request_hash varchar
) returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,consent,admin
as $$
declare v_inserted integer; v_key admin.idempotency_keys%rowtype; v_doc consent.consent_documents%rowtype; v_response jsonb;
begin
  if p_actor_account_id is null or not admin.account_has_permission(p_actor_account_id,'privacy.consent.manage') then raise exception 'privacy_manage_forbidden' using errcode='42501'; end if;
  if p_document_id is null or p_expected_updated_at is null or p_correlation_id is null
     or char_length(btrim(coalesce(p_reason,''))) not between 3 and 500
     or char_length(p_idempotency_key) not between 8 and 180 or p_request_hash !~ '^[0-9a-f]{64}$' then
    raise exception 'privacy_publish_payload_invalid' using errcode='22023';
  end if;
  insert into admin.idempotency_keys(actor_account_id,operation,idempotency_key,request_hash,status)
  values(p_actor_account_id,'privacy.document.publish',p_idempotency_key,p_request_hash,'Processing') on conflict do nothing;
  get diagnostics v_inserted=row_count;
  if v_inserted=0 then
    select * into v_key from admin.idempotency_keys where actor_account_id=p_actor_account_id and operation='privacy.document.publish' and idempotency_key=p_idempotency_key for update;
    if v_key.request_hash<>p_request_hash then return jsonb_build_object('httpStatus',409,'code','idempotency_conflict'); end if;
    if v_key.status='Completed' and v_key.response_json is not null then return v_key.response_json||jsonb_build_object('replayed',true); end if;
    return jsonb_build_object('httpStatus',409,'code','operation_in_progress');
  end if;
  select * into v_doc from consent.consent_documents where id=p_document_id for update;
  if not found then raise exception 'privacy_document_not_found' using errcode='P0002'; end if;
  if v_doc.updated_at_utc is distinct from p_expected_updated_at then raise exception 'privacy_document_version_conflict' using errcode='40001'; end if;
  if v_doc.status<>'Draft' or v_doc.content_uri !~ '^https://' or v_doc.document_hash !~ '^[0-9a-fA-F]{32,128}$' or v_doc.effective_at_utc is null then
    raise exception 'privacy_document_publish_invalid' using errcode='55000';
  end if;
  update consent.consent_documents set status='Active',updated_at_utc=now() where id=v_doc.id returning * into v_doc;
  insert into admin.audit_events(actor_account_id,action,resource_type,resource_id,result,reason,correlation_id,elevated_access,metadata_json)
  values(p_actor_account_id,'privacy.document.published','consent_document',v_doc.id::text,'Succeeded',btrim(p_reason),p_correlation_id,false,
    jsonb_build_object('purpose',v_doc.purpose,'version',v_doc.version,'jurisdiction',v_doc.jurisdiction,'effectiveAtUtc',v_doc.effective_at_utc));
  v_response:=jsonb_build_object('httpStatus',200,'code','ok','documentId',v_doc.id,'status',v_doc.status,'updatedAtUtc',v_doc.updated_at_utc,'replayed',false);
  update admin.idempotency_keys set status='Completed',response_status=200,response_json=v_response,updated_at_utc=now()
    where actor_account_id=p_actor_account_id and operation='privacy.document.publish' and idempotency_key=p_idempotency_key;
  return v_response;
end $$;

create or replace function consent.admin_retire_document_idempotent(
  p_actor_account_id uuid,p_document_id uuid,p_expected_updated_at timestamptz,p_reason varchar,p_correlation_id uuid,
  p_idempotency_key varchar,p_request_hash varchar
) returns jsonb
language plpgsql security definer set search_path=pg_catalog,consent,admin as $$
declare v_inserted integer; v_key admin.idempotency_keys%rowtype; v_response jsonb;
begin
  if char_length(p_idempotency_key) not between 8 and 180 or p_request_hash !~ '^[0-9a-f]{64}$' then raise exception 'privacy_idempotency_invalid' using errcode='22023'; end if;
  insert into admin.idempotency_keys(actor_account_id,operation,idempotency_key,request_hash,status)
  values(p_actor_account_id,'privacy.document.retire',p_idempotency_key,p_request_hash,'Processing') on conflict do nothing;
  get diagnostics v_inserted=row_count;
  if v_inserted=0 then
    select * into v_key from admin.idempotency_keys where actor_account_id=p_actor_account_id and operation='privacy.document.retire' and idempotency_key=p_idempotency_key for update;
    if v_key.request_hash<>p_request_hash then return jsonb_build_object('httpStatus',409,'code','idempotency_conflict'); end if;
    if v_key.status='Completed' and v_key.response_json is not null then return v_key.response_json||jsonb_build_object('replayed',true); end if;
    return jsonb_build_object('httpStatus',409,'code','operation_in_progress');
  end if;
  v_response:=consent.admin_retire_document(p_actor_account_id,p_document_id,p_expected_updated_at,p_reason,p_correlation_id)||jsonb_build_object('httpStatus',200,'code','ok','replayed',false);
  update admin.idempotency_keys set status='Completed',response_status=200,response_json=v_response,updated_at_utc=now()
    where actor_account_id=p_actor_account_id and operation='privacy.document.retire' and idempotency_key=p_idempotency_key;
  return v_response;
end $$;

create or replace function consent.admin_update_preference_purpose_idempotent(
  p_actor_account_id uuid,p_purpose varchar,p_expected_updated_at timestamptz,p_description varchar,p_policy_version varchar,p_status varchar,
  p_reason varchar,p_correlation_id uuid,p_idempotency_key varchar,p_request_hash varchar
) returns jsonb
language plpgsql security definer set search_path=pg_catalog,consent,admin as $$
declare v_inserted integer; v_key admin.idempotency_keys%rowtype; v_pref consent.preference_purposes%rowtype; v_response jsonb;
begin
  if p_actor_account_id is null or not admin.account_has_permission(p_actor_account_id,'privacy.consent.manage') then raise exception 'privacy_manage_forbidden' using errcode='42501'; end if;
  if p_expected_updated_at is null or char_length(btrim(coalesce(p_description,''))) not between 3 and 240
     or p_policy_version !~ '^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$' or p_status not in ('Active','Retired')
     or char_length(btrim(coalesce(p_reason,''))) not between 3 and 500 or p_correlation_id is null
     or char_length(p_idempotency_key) not between 8 and 180 or p_request_hash !~ '^[0-9a-f]{64}$' then
    raise exception 'privacy_preference_payload_invalid' using errcode='22023';
  end if;
  insert into admin.idempotency_keys(actor_account_id,operation,idempotency_key,request_hash,status)
  values(p_actor_account_id,'privacy.preference.update',p_idempotency_key,p_request_hash,'Processing') on conflict do nothing;
  get diagnostics v_inserted=row_count;
  if v_inserted=0 then
    select * into v_key from admin.idempotency_keys where actor_account_id=p_actor_account_id and operation='privacy.preference.update' and idempotency_key=p_idempotency_key for update;
    if v_key.request_hash<>p_request_hash then return jsonb_build_object('httpStatus',409,'code','idempotency_conflict'); end if;
    if v_key.status='Completed' and v_key.response_json is not null then return v_key.response_json||jsonb_build_object('replayed',true); end if;
    return jsonb_build_object('httpStatus',409,'code','operation_in_progress');
  end if;
  select * into v_pref from consent.preference_purposes where purpose=p_purpose for update;
  if not found then raise exception 'privacy_preference_not_found' using errcode='P0002'; end if;
  if v_pref.updated_at_utc is distinct from p_expected_updated_at then raise exception 'privacy_preference_version_conflict' using errcode='40001'; end if;
  update consent.preference_purposes set description=btrim(p_description),policy_version=p_policy_version,status=p_status,updated_at_utc=now()
    where purpose=p_purpose returning * into v_pref;
  insert into admin.audit_events(actor_account_id,action,resource_type,resource_id,result,reason,correlation_id,elevated_access,metadata_json)
  values(p_actor_account_id,'privacy.preference.updated','preference_purpose',v_pref.purpose,'Succeeded',btrim(p_reason),p_correlation_id,false,
    jsonb_build_object('policyVersion',v_pref.policy_version,'status',v_pref.status));
  v_response:=jsonb_build_object('httpStatus',200,'code','ok','purpose',v_pref.purpose,'policyVersion',v_pref.policy_version,'status',v_pref.status,'updatedAtUtc',v_pref.updated_at_utc,'replayed',false);
  update admin.idempotency_keys set status='Completed',response_status=200,response_json=v_response,updated_at_utc=now()
    where actor_account_id=p_actor_account_id and operation='privacy.preference.update' and idempotency_key=p_idempotency_key;
  return v_response;
end $$;

revoke all on function consent.admin_legal_acceptance_coverage(uuid,varchar) from public,anon,authenticated;
revoke all on function consent.admin_user_privacy_summary(uuid,uuid) from public,anon,authenticated;
revoke all on function consent.admin_create_document_draft_idempotent(uuid,varchar,varchar,varchar,varchar,varchar,text,timestamptz,varchar,uuid,varchar,varchar) from public,anon,authenticated;
revoke all on function consent.admin_publish_document_idempotent(uuid,uuid,timestamptz,varchar,uuid,varchar,varchar) from public,anon,authenticated;
revoke all on function consent.admin_retire_document_idempotent(uuid,uuid,timestamptz,varchar,uuid,varchar,varchar) from public,anon,authenticated;
revoke all on function consent.admin_update_preference_purpose_idempotent(uuid,varchar,timestamptz,varchar,varchar,varchar,varchar,uuid,varchar,varchar) from public,anon,authenticated;
grant execute on function consent.admin_legal_acceptance_coverage(uuid,varchar) to lifemate_admin_runtime;
grant execute on function consent.admin_user_privacy_summary(uuid,uuid) to lifemate_admin_runtime;
grant execute on function consent.admin_create_document_draft_idempotent(uuid,varchar,varchar,varchar,varchar,varchar,text,timestamptz,varchar,uuid,varchar,varchar) to lifemate_admin_runtime;
grant execute on function consent.admin_publish_document_idempotent(uuid,uuid,timestamptz,varchar,uuid,varchar,varchar) to lifemate_admin_runtime;
grant execute on function consent.admin_retire_document_idempotent(uuid,uuid,timestamptz,varchar,uuid,varchar,varchar) to lifemate_admin_runtime;
grant execute on function consent.admin_update_preference_purpose_idempotent(uuid,varchar,timestamptz,varchar,varchar,varchar,varchar,uuid,varchar,varchar) to lifemate_admin_runtime;

commit;
