begin;

create or replace function security.evaluate_abuse_rules(
  p_actor_account_id uuid,
  p_context_code character varying,
  p_operation_key character varying,
  p_evidence_codes character varying[],
  p_idempotency_key character varying,
  p_request_hash character varying
) returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,security,identity,extensions,pg_temp
as $$
declare
  v_context character varying(80):=lower(trim(coalesce(p_context_code,'')));
  v_operation_hash character varying(128);
  v_existing security.abuse_decisions%rowtype;
  v_rule security.abuse_rules%rowtype;
  v_subject_hash character varying(128);
  v_count bigint;
  v_last timestamptz;
  v_triggered boolean;
  v_final character varying(24):='Allow';
  v_rule_ids uuid[]:='{}'::uuid[];
  v_reasons character varying(160)[]:='{}'::character varying[];
  v_approval character varying(80);
  v_rule_set_hash character varying(128);
  v_decision_id uuid;
  v_evidence character varying[]:=coalesce(p_evidence_codes,'{}'::character varying[]);
begin
  if v_context !~ '^[a-z][a-z0-9._-]{2,79}$' then
    return jsonb_build_object('httpStatus',400,'code','abuse_context_invalid','message','Context code is invalid.');
  end if;
  if p_operation_key is null or length(p_operation_key)<1 or length(p_operation_key)>180
     or p_idempotency_key is null or length(p_idempotency_key)<8 or length(p_idempotency_key)>180
     or p_request_hash is null or p_request_hash !~ '^[0-9a-f]{64,128}$' then
    return jsonb_build_object('httpStatus',400,'code','abuse_evaluation_metadata_invalid','message','Evaluation metadata is invalid.');
  end if;
  if exists(select 1 from unnest(v_evidence) e where e !~ '^[a-z][a-z0-9._-]{2,79}$') or cardinality(v_evidence)>32 then
    return jsonb_build_object('httpStatus',400,'code','abuse_evidence_codes_invalid','message','Evidence codes are invalid.');
  end if;

  v_operation_hash:=encode(extensions.digest(p_operation_key,'sha256'),'hex');
  perform pg_advisory_xact_lock(hashtextextended(p_actor_account_id::text||':'||v_context||':'||p_idempotency_key,0));
  select * into v_existing from security.abuse_decisions
  where actor_account_id=p_actor_account_id and context_code=v_context and idempotency_key=p_idempotency_key;
  if found then
    if v_existing.request_hash<>p_request_hash then
      return jsonb_build_object('httpStatus',409,'code','idempotency_conflict','message','This Idempotency-Key was already used for a different evaluation.');
    end if;
    return jsonb_build_object(
      'httpStatus',200,'code','ok','decisionId',v_existing.id,'action',v_existing.final_action,
      'matchedRuleIds',v_existing.matched_rule_ids,'reasonCodes',v_existing.reason_codes,
      'approvalRequestType',v_existing.approval_request_type,'replayed',true
    );
  end if;

  select encode(extensions.digest(coalesce(string_agg(code||':'||version::text||':'||status,',' order by priority,id),''),'sha256'),'hex')
  into v_rule_set_hash
  from security.abuse_rules where context_code=v_context and status='Active';

  for v_rule in
    select * from security.abuse_rules
    where context_code=v_context and status='Active'
    order by priority,id
  loop
    v_subject_hash:=security.abuse_subject_key_hash(p_actor_account_id,v_rule.subject_scope);
    v_triggered:=false;
    if v_subject_hash is null then
      if v_rule.subject_scope='VerifiedPhone' then
        v_triggered:=true;
        v_reasons:=array_append(v_reasons,'verified_phone_unavailable');
      end if;
    elsif v_rule.rule_kind='VelocityLimit' then
      select count(*) into v_count from security.abuse_events
      where context_code=v_context and subject_scope=v_rule.subject_scope and subject_key_hash=v_subject_hash
        and occurred_at_utc>=now()-make_interval(secs=>v_rule.window_seconds);
      v_triggered:=v_count>=v_rule.max_count;
    elsif v_rule.rule_kind='UsageCap' then
      select count(*) into v_count from security.abuse_events
      where context_code=v_context and subject_scope=v_rule.subject_scope and subject_key_hash=v_subject_hash;
      v_triggered:=v_count>=v_rule.max_count;
    elsif v_rule.rule_kind='Cooldown' then
      select max(occurred_at_utc) into v_last from security.abuse_events
      where context_code=v_context and subject_scope=v_rule.subject_scope and subject_key_hash=v_subject_hash;
      v_triggered:=v_last is not null and v_last>now()-make_interval(secs=>v_rule.cooldown_seconds);
    elsif v_rule.rule_kind='DuplicateKey' then
      v_triggered:=exists(
        select 1 from security.abuse_events
        where context_code=v_context and subject_scope=v_rule.subject_scope and subject_key_hash=v_subject_hash
          and operation_key_hash=v_operation_hash
      );
    elsif v_rule.rule_kind='EvidenceRequired' then
      v_triggered:=not (v_rule.evidence_code=any(v_evidence));
    end if;

    if v_triggered then
      v_rule_ids:=array_append(v_rule_ids,v_rule.id);
      v_reasons:=array_append(v_reasons,v_rule.code);
      if v_rule.enforcement_action='Deny' then
        v_final:='Deny';
        v_approval:=null;
      elsif v_rule.enforcement_action='RequireApproval' and v_final='Allow' then
        v_final:='RequireApproval';
        v_approval:=v_rule.approval_request_type;
      end if;
    end if;
  end loop;

  insert into security.abuse_decisions(
    actor_account_id,context_code,operation_key_hash,final_action,matched_rule_ids,reason_codes,
    approval_request_type,rule_set_hash,idempotency_key,request_hash
  ) values(
    p_actor_account_id,v_context,v_operation_hash,v_final,v_rule_ids,v_reasons,v_approval,
    coalesce(v_rule_set_hash,encode(extensions.digest('','sha256'),'hex')),p_idempotency_key,p_request_hash
  ) returning id into v_decision_id;

  return jsonb_build_object(
    'httpStatus',200,'code','ok','decisionId',v_decision_id,'action',v_final,
    'matchedRuleIds',v_rule_ids,'reasonCodes',v_reasons,'approvalRequestType',v_approval,'replayed',false
  );
end $$;

revoke all on function security.evaluate_abuse_rules(uuid,character varying,character varying,character varying[],character varying,character varying) from public;
grant execute on function security.evaluate_abuse_rules(uuid,character varying,character varying,character varying[],character varying,character varying) to lifemate_edge_runtime,lifemate_admin_runtime;

commit;
