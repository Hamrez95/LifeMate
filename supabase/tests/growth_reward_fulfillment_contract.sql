\set ON_ERROR_STOP on

do $$
declare
  v_review regprocedure:=to_regprocedure('admin.review_growth_reward_source(uuid,character varying,uuid,bigint,character varying,character varying,uuid,character varying,character varying)');
  v_preview regprocedure:=to_regprocedure('admin.preview_growth_reward_fulfillment(uuid,bigint)');
  v_execute regprocedure:=to_regprocedure('admin.execute_growth_reward_fulfillment(uuid,uuid,bigint,uuid,bigint,character varying,uuid,character varying,character varying)');
  v_definition text;
  v_self boolean;
begin
  if v_review is null or v_preview is null or v_execute is null then
    raise exception 'reviewed reward fulfillment functions missing';
  end if;
  if not has_function_privilege('lifemate_admin_runtime',v_review,'EXECUTE')
     or not has_function_privilege('lifemate_admin_runtime',v_preview,'EXECUTE')
     or not has_function_privilege('lifemate_admin_runtime',v_execute,'EXECUTE') then
    raise exception 'admin runtime lacks reviewed reward fulfillment authority';
  end if;
  if has_function_privilege('lifemate_edge_runtime',v_review,'EXECUTE')
     or has_function_privilege('lifemate_edge_runtime',v_preview,'EXECUTE')
     or has_function_privilege('lifemate_edge_runtime',v_execute,'EXECUTE') then
    raise exception 'consumer edge runtime unexpectedly owns reward review/fulfillment authority';
  end if;
  if has_function_privilege('lifemate_worker_runtime',v_review,'EXECUTE')
     or has_function_privilege('lifemate_worker_runtime',v_execute,'EXECUTE') then
    raise exception 'worker runtime unexpectedly owns reviewed reward mutation authority';
  end if;

  select self_approval_allowed into v_self from admin.approval_policies where request_type='growth_reward_fulfillment' and status='Active';
  if v_self is distinct from false then
    raise exception 'reward fulfillment approval must prohibit self approval';
  end if;

  v_definition:=lower(pg_get_functiondef(v_execute));
  if position('admin.consume_approval_request' in v_definition)=0 then
    raise exception 'reward fulfillment must consume canonical approval transactionally';
  end if;
  if position('commerce.apply_manual_entitlement_grant_guarded' in v_definition)=0 then
    raise exception 'GiftEntitlement must reuse guarded entitlement authority';
  end if;
  if position('insert into commerce.entitlements' in v_definition)>0
     or position('update commerce.entitlements' in v_definition)>0 then
    raise exception 'reward fulfillment must not mutate entitlement tables directly';
  end if;
  if position('reward_fulfillment_adapter_unavailable' in v_definition)=0 then
    raise exception 'unsupported external reward adapters must fail closed';
  end if;
  if position('elevated_access' in v_definition)=0 or position('false' in v_definition)=0 then
    raise exception 'reward audit must remain non-elevated';
  end if;

  if not exists(
    select 1 from pg_trigger t join pg_class c on c.oid=t.tgrelid join pg_namespace n on n.oid=c.relnamespace
    where n.nspname='growth' and c.relname='reward_events' and t.tgname='trg_growth_reward_event_snapshot' and not t.tgisinternal
  ) then
    raise exception 'immutable reward config snapshot trigger missing';
  end if;
end $$;
