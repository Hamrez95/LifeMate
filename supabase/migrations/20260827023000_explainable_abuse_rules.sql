begin;

insert into admin.permissions(code,domain,risk_level,role_assignable,description) values
('security.abuse.read','security','SENSITIVE',true,'Read explainable abuse rules and privacy-minimized decision history'),
('security.abuse.write','security','ELEVATED',false,'Create, update and retire explainable abuse rules')
on conflict (code) do update set
  domain=excluded.domain,
  risk_level=excluded.risk_level,
  role_assignable=excluded.role_assignable,
  description=excluded.description,
  updated_at_utc=now();

insert into admin.role_permissions(role_id,permission_code)
select r.id,'security.abuse.read'
from admin.roles r
where r.code in ('founder','super_admin','security','finance','marketing')
on conflict do nothing;

insert into admin.role_permissions(role_id,permission_code)
select r.id,'security.abuse.write'
from admin.roles r
where r.code in ('founder','super_admin','security')
on conflict do nothing;

create table if not exists security.abuse_rules (
  id uuid primary key default gen_random_uuid(),
  code character varying(80) not null unique check (code ~ '^[a-z][a-z0-9._-]{2,79}$'),
  context_code character varying(80) not null check (context_code ~ '^[a-z][a-z0-9._-]{2,79}$'),
  display_name character varying(160) not null,
  rule_kind character varying(32) not null check (rule_kind in ('VelocityLimit','UsageCap','Cooldown','DuplicateKey','EvidenceRequired')),
  subject_scope character varying(24) not null check (subject_scope in ('Account','VerifiedPhone')),
  enforcement_action character varying(24) not null check (enforcement_action in ('Allow','Deny','RequireApproval')),
  window_seconds integer check (window_seconds is null or window_seconds between 1 and 31536000),
  max_count integer check (max_count is null or max_count between 1 and 1000000),
  cooldown_seconds integer check (cooldown_seconds is null or cooldown_seconds between 1 and 31536000),
  evidence_code character varying(80) check (evidence_code is null or evidence_code ~ '^[a-z][a-z0-9._-]{2,79}$'),
  approval_request_type character varying(80) references admin.approval_policies(request_type) on delete restrict,
  priority integer not null default 100 check (priority between 1 and 10000),
  status character varying(16) not null default 'Active' check (status in ('Active','Disabled','Retired')),
  version bigint not null default 1 check (version >= 1),
  created_by_account_id uuid not null,
  created_at_utc timestamptz not null default now(),
  updated_at_utc timestamptz not null default now(),
  check (
    (rule_kind='VelocityLimit' and window_seconds is not null and max_count is not null and cooldown_seconds is null and evidence_code is null)
    or (rule_kind='UsageCap' and max_count is not null and window_seconds is null and cooldown_seconds is null and evidence_code is null)
    or (rule_kind='Cooldown' and cooldown_seconds is not null and window_seconds is null and max_count is null and evidence_code is null)
    or (rule_kind='DuplicateKey' and window_seconds is null and max_count is null and cooldown_seconds is null and evidence_code is null)
    or (rule_kind='EvidenceRequired' and evidence_code is not null and window_seconds is null and max_count is null and cooldown_seconds is null)
  ),
  check ((enforcement_action='RequireApproval') = (approval_request_type is not null))
);
create index if not exists ix_security_abuse_rules_context
  on security.abuse_rules(context_code,status,priority,id);

create table if not exists security.abuse_rule_versions (
  id uuid primary key default gen_random_uuid(),
  rule_id uuid not null references security.abuse_rules(id) on delete restrict,
  rule_version bigint not null check (rule_version >= 1),
  snapshot_json jsonb not null check (jsonb_typeof(snapshot_json)='object' and octet_length(snapshot_json::text)<=8192),
  changed_by_account_id uuid not null,
  change_reason character varying(1000) not null check (length(trim(change_reason)) between 10 and 1000),
  created_at_utc timestamptz not null default now(),
  unique(rule_id,rule_version)
);

create table if not exists security.abuse_events (
  id uuid primary key default gen_random_uuid(),
  context_code character varying(80) not null,
  subject_scope character varying(24) not null check (subject_scope in ('Account','VerifiedPhone')),
  subject_key_hash character varying(128) not null,
  operation_key_hash character varying(128) not null,
  event_code character varying(80) not null check (event_code ~ '^[a-z][a-z0-9._-]{2,79}$'),
  occurred_at_utc timestamptz not null default now(),
  recorded_at_utc timestamptz not null default now()
);
create index if not exists ix_security_abuse_events_velocity
  on security.abuse_events(context_code,subject_scope,subject_key_hash,occurred_at_utc desc);
create index if not exists ix_security_abuse_events_duplicate
  on security.abuse_events(context_code,subject_scope,subject_key_hash,operation_key_hash,occurred_at_utc desc);

create table if not exists security.abuse_decisions (
  id uuid primary key default gen_random_uuid(),
  actor_account_id uuid not null,
  context_code character varying(80) not null,
  operation_key_hash character varying(128) not null,
  final_action character varying(24) not null check (final_action in ('Allow','Deny','RequireApproval')),
  matched_rule_ids uuid[] not null default '{}'::uuid[],
  reason_codes character varying(160)[] not null default '{}'::character varying[],
  approval_request_type character varying(80),
  rule_set_hash character varying(128) not null,
  idempotency_key character varying(180) not null,
  request_hash character varying(128) not null,
  evaluated_at_utc timestamptz not null default now(),
  unique(actor_account_id,context_code,idempotency_key)
);
create index if not exists ix_security_abuse_decisions_context
  on security.abuse_decisions(context_code,evaluated_at_utc desc);

alter table security.abuse_rules enable row level security;
alter table security.abuse_rules force row level security;
alter table security.abuse_rule_versions enable row level security;
alter table security.abuse_rule_versions force row level security;
alter table security.abuse_events enable row level security;
alter table security.abuse_events force row level security;
alter table security.abuse_decisions enable row level security;
alter table security.abuse_decisions force row level security;

revoke all on table security.abuse_rules from public,anon,authenticated;
revoke all on table security.abuse_rule_versions from public,anon,authenticated;
revoke all on table security.abuse_events from public,anon,authenticated;
revoke all on table security.abuse_decisions from public,anon,authenticated;

grant select,insert,update on security.abuse_rules to lifemate_admin_runtime;
grant select,insert on security.abuse_rule_versions to lifemate_admin_runtime;
grant select on security.abuse_events,security.abuse_decisions to lifemate_admin_runtime;
grant select,insert on security.abuse_events,security.abuse_decisions to lifemate_edge_runtime,lifemate_admin_runtime;

create policy abuse_rules_admin_runtime on security.abuse_rules
  for all to lifemate_admin_runtime using (true) with check (true);
create policy abuse_rule_versions_admin_runtime on security.abuse_rule_versions
  for select to lifemate_admin_runtime using (true);
create policy abuse_rule_versions_admin_insert on security.abuse_rule_versions
  for insert to lifemate_admin_runtime with check (true);
create policy abuse_events_admin_runtime on security.abuse_events
  for select to lifemate_admin_runtime using (true);
create policy abuse_events_edge_insert on security.abuse_events
  for insert to lifemate_edge_runtime with check (true);
create policy abuse_events_admin_insert on security.abuse_events
  for insert to lifemate_admin_runtime with check (true);
create policy abuse_decisions_admin_runtime on security.abuse_decisions
  for select to lifemate_admin_runtime using (true);
create policy abuse_decisions_edge_insert on security.abuse_decisions
  for insert to lifemate_edge_runtime with check (true);
create policy abuse_decisions_admin_insert on security.abuse_decisions
  for insert to lifemate_admin_runtime with check (true);

create or replace function security.abuse_subject_key_hash(
  p_account_id uuid,
  p_subject_scope character varying
) returns character varying
language plpgsql
stable
security definer
set search_path=pg_catalog,identity,extensions,pg_temp
as $$
declare v_phone_hash character varying;
begin
  if p_subject_scope='Account' then
    return encode(extensions.digest(p_account_id::text,'sha256'),'hex');
  end if;
  if p_subject_scope='VerifiedPhone' then
    select normalized_value_hash into v_phone_hash
    from identity.contact_points
    where account_id=p_account_id and kind='Phone' and status='Verified' and verified_at_utc is not null
    order by verified_at_utc desc,id
    limit 1;
    if v_phone_hash is null then return null; end if;
    return encode(extensions.digest('verified-phone:'||v_phone_hash,'sha256'),'hex');
  end if;
  return null;
end $$;

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
      elsif v_rule.enforcement_action='RequireApproval' and v_final<>'Deny' then
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
declare v_scope character varying(24); v_hash character varying(128); v_operation_hash character varying(128);
begin
  if p_context_code !~ '^[a-z][a-z0-9._-]{2,79}$' or p_event_code !~ '^[a-z][a-z0-9._-]{2,79}$'
     or p_operation_key is null or length(p_operation_key)<1 or length(p_operation_key)>180 then
    raise exception 'abuse_event_invalid';
  end if;
  v_operation_hash:=encode(extensions.digest(p_operation_key,'sha256'),'hex');
  for v_scope in select distinct subject_scope from security.abuse_rules where context_code=p_context_code and status='Active' loop
    v_hash:=security.abuse_subject_key_hash(p_account_id,v_scope);
    if v_hash is not null then
      insert into security.abuse_events(context_code,subject_scope,subject_key_hash,operation_key_hash,event_code)
      values(p_context_code,v_scope,v_hash,v_operation_hash,p_event_code);
    end if;
  end loop;
  return true;
end $$;

create or replace function security.upsert_abuse_rule(
  p_actor_account_id uuid,
  p_code character varying,
  p_context_code character varying,
  p_display_name character varying,
  p_rule_kind character varying,
  p_subject_scope character varying,
  p_enforcement_action character varying,
  p_window_seconds integer,
  p_max_count integer,
  p_cooldown_seconds integer,
  p_evidence_code character varying,
  p_approval_request_type character varying,
  p_priority integer,
  p_expected_version bigint,
  p_reason character varying,
  p_correlation_id uuid
) returns jsonb
language plpgsql
set search_path=security,admin,pg_temp
as $$
declare v_rule security.abuse_rules%rowtype; v_snapshot jsonb; v_new_version bigint;
begin
  if not admin.account_has_permission(p_actor_account_id,'security.abuse.write') then
    return jsonb_build_object('httpStatus',403,'code','abuse_rule_permission_denied','message','Actor cannot change abuse rules.');
  end if;
  if p_code !~ '^[a-z][a-z0-9._-]{2,79}$' or p_context_code !~ '^[a-z][a-z0-9._-]{2,79}$'
     or p_reason is null or length(trim(p_reason))<10 or length(trim(p_reason))>1000 then
    return jsonb_build_object('httpStatus',400,'code','abuse_rule_invalid','message','Rule metadata is invalid.');
  end if;
  select * into v_rule from security.abuse_rules where code=p_code for update;
  if found then
    if p_expected_version is null or p_expected_version<>v_rule.version then
      return jsonb_build_object('httpStatus',409,'code','abuse_rule_version_conflict','message','Rule version changed.');
    end if;
    v_new_version:=v_rule.version+1;
    update security.abuse_rules set
      context_code=p_context_code,display_name=p_display_name,rule_kind=p_rule_kind,subject_scope=p_subject_scope,
      enforcement_action=p_enforcement_action,window_seconds=p_window_seconds,max_count=p_max_count,
      cooldown_seconds=p_cooldown_seconds,evidence_code=p_evidence_code,approval_request_type=p_approval_request_type,
      priority=p_priority,version=v_new_version,updated_at_utc=now()
    where id=v_rule.id returning * into v_rule;
  else
    if p_expected_version is not null then
      return jsonb_build_object('httpStatus',404,'code','abuse_rule_not_found','message','Rule was not found.');
    end if;
    insert into security.abuse_rules(
      code,context_code,display_name,rule_kind,subject_scope,enforcement_action,window_seconds,max_count,
      cooldown_seconds,evidence_code,approval_request_type,priority,created_by_account_id
    ) values(
      p_code,p_context_code,p_display_name,p_rule_kind,p_subject_scope,p_enforcement_action,p_window_seconds,p_max_count,
      p_cooldown_seconds,p_evidence_code,p_approval_request_type,p_priority,p_actor_account_id
    ) returning * into v_rule;
    v_new_version:=1;
  end if;

  v_snapshot:=jsonb_build_object(
    'code',v_rule.code,'contextCode',v_rule.context_code,'displayName',v_rule.display_name,'ruleKind',v_rule.rule_kind,
    'subjectScope',v_rule.subject_scope,'enforcementAction',v_rule.enforcement_action,'windowSeconds',v_rule.window_seconds,
    'maxCount',v_rule.max_count,'cooldownSeconds',v_rule.cooldown_seconds,'evidenceCode',v_rule.evidence_code,
    'approvalRequestType',v_rule.approval_request_type,'priority',v_rule.priority,'status',v_rule.status
  );
  insert into security.abuse_rule_versions(rule_id,rule_version,snapshot_json,changed_by_account_id,change_reason)
  values(v_rule.id,v_new_version,v_snapshot,p_actor_account_id,trim(p_reason));
  insert into admin.audit_events(actor_account_id,action,resource_type,resource_id,result,reason,correlation_id,elevated_access,metadata_json)
  values(p_actor_account_id,'security.abuse.rule.upsert','abuse_rule',v_rule.id::text,'Succeeded',trim(p_reason),p_correlation_id,true,
    jsonb_build_object('code',v_rule.code,'contextCode',v_rule.context_code,'version',v_new_version));
  return jsonb_build_object('httpStatus',200,'code','ok','id',v_rule.id,'version',v_new_version);
exception when check_violation or foreign_key_violation then
  return jsonb_build_object('httpStatus',400,'code','abuse_rule_configuration_invalid','message','Rule configuration is invalid.');
end $$;

revoke all on function security.abuse_subject_key_hash(uuid,character varying) from public;
revoke all on function security.evaluate_abuse_rules(uuid,character varying,character varying,character varying[],character varying,character varying) from public;
revoke all on function security.record_abuse_event(uuid,character varying,character varying,character varying) from public;
revoke all on function security.upsert_abuse_rule(uuid,character varying,character varying,character varying,character varying,character varying,character varying,integer,integer,integer,character varying,character varying,integer,bigint,character varying,uuid) from public;
grant execute on function security.evaluate_abuse_rules(uuid,character varying,character varying,character varying[],character varying,character varying) to lifemate_edge_runtime,lifemate_admin_runtime;
grant execute on function security.record_abuse_event(uuid,character varying,character varying,character varying) to lifemate_edge_runtime,lifemate_admin_runtime;
grant execute on function security.upsert_abuse_rule(uuid,character varying,character varying,character varying,character varying,character varying,character varying,integer,integer,integer,character varying,character varying,integer,bigint,character varying,uuid) to lifemate_admin_runtime;

commit;
