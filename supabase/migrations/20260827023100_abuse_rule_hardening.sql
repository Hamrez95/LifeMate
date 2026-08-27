begin;

revoke all on table security.abuse_events from lifemate_edge_runtime;
revoke all on table security.abuse_decisions from lifemate_edge_runtime;

create unique index if not exists ux_security_abuse_events_operation
  on security.abuse_events(context_code,subject_scope,subject_key_hash,operation_key_hash,event_code);

create or replace function security.record_abuse_event(
  p_account_id uuid,
  p_context_code character varying,
  p_operation_key character varying,
  p_event_code character varying
) returns boolean
language plpgsql
security definer
set search_path=pg_catalog,security,extensions,pg_temp
as $$
declare
  v_context character varying(80):=lower(trim(coalesce(p_context_code,'')));
  v_event character varying(80):=lower(trim(coalesce(p_event_code,'')));
  v_scope character varying(24);
  v_hash character varying(128);
  v_operation_hash character varying(128);
begin
  if v_context !~ '^[a-z][a-z0-9._-]{2,79}$' or v_event !~ '^[a-z][a-z0-9._-]{2,79}$'
     or p_operation_key is null or length(p_operation_key)<1 or length(p_operation_key)>180 then
    raise exception 'abuse_event_invalid';
  end if;
  v_operation_hash:=encode(extensions.digest(p_operation_key,'sha256'),'hex');
  for v_scope in
    select distinct subject_scope from security.abuse_rules
    where context_code=v_context and status='Active'
  loop
    v_hash:=security.abuse_subject_key_hash(p_account_id,v_scope);
    if v_hash is not null then
      insert into security.abuse_events(context_code,subject_scope,subject_key_hash,operation_key_hash,event_code)
      values(v_context,v_scope,v_hash,v_operation_hash,v_event)
      on conflict(context_code,subject_scope,subject_key_hash,operation_key_hash,event_code) do nothing;
    end if;
  end loop;
  return true;
end $$;

create or replace function security.retire_abuse_rule(
  p_actor_account_id uuid,
  p_rule_id uuid,
  p_expected_version bigint,
  p_reason character varying,
  p_correlation_id uuid
) returns jsonb
language plpgsql
set search_path=security,admin,pg_temp
as $$
declare
  v_rule security.abuse_rules%rowtype;
  v_new_version bigint;
  v_snapshot jsonb;
begin
  if not admin.account_has_permission(p_actor_account_id,'security.abuse.write') then
    return jsonb_build_object('httpStatus',403,'code','abuse_rule_permission_denied','message','Actor cannot retire abuse rules.');
  end if;
  if p_expected_version is null or p_expected_version<1
     or p_reason is null or length(trim(p_reason))<10 or length(trim(p_reason))>1000 then
    return jsonb_build_object('httpStatus',400,'code','abuse_rule_retire_invalid','message','Expected version and bounded reason are required.');
  end if;
  select * into v_rule from security.abuse_rules where id=p_rule_id for update;
  if not found then
    return jsonb_build_object('httpStatus',404,'code','abuse_rule_not_found','message','Rule was not found.');
  end if;
  if v_rule.version<>p_expected_version then
    return jsonb_build_object('httpStatus',409,'code','abuse_rule_version_conflict','message','Rule version changed.');
  end if;
  if v_rule.status='Retired' then
    return jsonb_build_object('httpStatus',409,'code','abuse_rule_already_retired','message','Rule is already retired.');
  end if;

  v_new_version:=v_rule.version+1;
  update security.abuse_rules
  set status='Retired',version=v_new_version,updated_at_utc=now()
  where id=p_rule_id
  returning * into v_rule;

  v_snapshot:=jsonb_build_object(
    'code',v_rule.code,'contextCode',v_rule.context_code,'displayName',v_rule.display_name,
    'ruleKind',v_rule.rule_kind,'subjectScope',v_rule.subject_scope,
    'enforcementAction',v_rule.enforcement_action,'windowSeconds',v_rule.window_seconds,
    'maxCount',v_rule.max_count,'cooldownSeconds',v_rule.cooldown_seconds,
    'evidenceCode',v_rule.evidence_code,'approvalRequestType',v_rule.approval_request_type,
    'priority',v_rule.priority,'status',v_rule.status
  );
  insert into security.abuse_rule_versions(rule_id,rule_version,snapshot_json,changed_by_account_id,change_reason)
  values(v_rule.id,v_new_version,v_snapshot,p_actor_account_id,trim(p_reason));

  insert into admin.audit_events(actor_account_id,action,resource_type,resource_id,result,reason,correlation_id,elevated_access,metadata_json)
  values(p_actor_account_id,'security.abuse.rule.retire','abuse_rule',v_rule.id::text,'Succeeded',trim(p_reason),p_correlation_id,true,
    jsonb_build_object('code',v_rule.code,'contextCode',v_rule.context_code,'version',v_new_version));

  return jsonb_build_object('httpStatus',200,'code','ok','id',v_rule.id,'version',v_new_version,'status','Retired');
end $$;

revoke all on function security.record_abuse_event(uuid,character varying,character varying,character varying) from public;
revoke all on function security.retire_abuse_rule(uuid,uuid,bigint,character varying,uuid) from public;
grant execute on function security.record_abuse_event(uuid,character varying,character varying,character varying) to lifemate_edge_runtime,lifemate_admin_runtime;
grant execute on function security.retire_abuse_rule(uuid,uuid,bigint,character varying,uuid) to lifemate_admin_runtime;

commit;
