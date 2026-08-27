\set ON_ERROR_STOP on

do $$
declare
  v_upsert regprocedure := to_regprocedure('admin.upsert_growth_reward_rule(uuid,character varying,character varying,character varying,jsonb,integer,character varying,bigint,character varying,uuid,character varying,character varying)');
  v_create regprocedure := to_regprocedure('admin.create_growth_reward_event(uuid,uuid,character varying,uuid,character varying,character varying,uuid,character varying,character varying)');
  v_definition text;
begin
  if v_upsert is null or v_create is null then
    raise exception 'growth reward engine functions missing';
  end if;

  if not has_function_privilege('lifemate_admin_runtime',v_upsert,'EXECUTE')
     or not has_function_privilege('lifemate_admin_runtime',v_create,'EXECUTE') then
    raise exception 'admin runtime lacks reward management authority';
  end if;
  if has_function_privilege('lifemate_edge_runtime',v_upsert,'EXECUTE')
     or has_function_privilege('lifemate_edge_runtime',v_create,'EXECUTE') then
    raise exception 'consumer edge runtime unexpectedly owns reward management authority';
  end if;
  if has_function_privilege('lifemate_worker_runtime',v_upsert,'EXECUTE')
     or has_function_privilege('lifemate_worker_runtime',v_create,'EXECUTE') then
    raise exception 'worker runtime unexpectedly owns reviewed reward management authority';
  end if;

  if to_regrole('anon') is not null and has_table_privilege('anon','growth.reward_events','SELECT') then
    raise exception 'anon unexpectedly reads reward events';
  end if;
  if to_regrole('authenticated') is not null and has_table_privilege('authenticated','growth.reward_events','SELECT') then
    raise exception 'authenticated unexpectedly reads reward events directly';
  end if;

  v_definition:=lower(pg_get_functiondef(v_create));
  if position('''pending''' in v_definition)=0 then
    raise exception 'reward engine must create Pending evidence, not fabricate external issuance';
  end if;
  if position('for update' in v_definition)=0 then
    raise exception 'reward source/event lifecycle must use row locking';
  end if;
  if position('elevated_access' in v_definition)=0 or position('false' in v_definition)=0 then
    raise exception 'reward audit must remain distinct from elevated health access';
  end if;

  v_definition:=lower(pg_get_functiondef(v_upsert));
  if position('campaign_reward_source_unavailable' in v_definition)=0 then
    raise exception 'campaign reward activation must fail closed until canonical source semantics exist';
  end if;
  if position('reward_rule_version_conflict' in v_definition)=0 then
    raise exception 'reward rule mutation must preserve optimistic concurrency';
  end if;
end $$;
