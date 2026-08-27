\set ON_ERROR_STOP on

-- Campaign execution must stay behind the Admin/worker runtime boundaries,
-- preserve promotional opt-out by default, and serialize mutable lifecycle
-- operations before this feature is considered ready.
do $$
declare
  v_prepare regprocedure := to_regprocedure('messaging.prepare_campaign_execution(uuid,uuid,uuid,timestamptz,character varying[],character varying,character varying,uuid)');
  v_prepare_v2 regprocedure := to_regprocedure('messaging.prepare_campaign_execution_v2(uuid,uuid,uuid,timestamptz,character varying[],character varying,character varying,uuid)');
  v_confirm regprocedure := to_regprocedure('messaging.confirm_campaign_execution(uuid,uuid,bigint,uuid)');
  v_schedule regprocedure := to_regprocedure('messaging.schedule_campaign_execution(uuid,uuid,bigint,timestamptz,uuid)');
  v_claim regprocedure := to_regprocedure('messaging.claim_campaign_delivery_jobs(integer)');
  v_resolve regprocedure := to_regprocedure('messaging.resolve_campaign_delivery_job(uuid)');
  v_result_v2 regprocedure := to_regprocedure('messaging.record_campaign_delivery_result_v2(uuid,character varying,character varying,character varying,character varying,timestamptz)');
  v_definition text;
  v_unknown_account uuid := gen_random_uuid();
begin
  if v_prepare is null or v_prepare_v2 is null or v_confirm is null or v_schedule is null
     or v_claim is null or v_resolve is null or v_result_v2 is null then
    raise exception 'campaign orchestrator canonical functions missing';
  end if;

  if to_regrole('anon') is not null and has_schema_privilege('anon','messaging','USAGE') then
    raise exception 'anon unexpectedly has messaging schema usage';
  end if;
  if to_regrole('authenticated') is not null and has_schema_privilege('authenticated','messaging','USAGE') then
    raise exception 'authenticated unexpectedly has messaging schema usage';
  end if;
  if to_regrole('lifemate_edge_runtime') is not null and has_table_privilege('lifemate_edge_runtime','messaging.delivery_jobs','SELECT') then
    raise exception 'healthcare edge runtime unexpectedly reads campaign delivery jobs';
  end if;

  if not has_function_privilege('lifemate_admin_runtime', v_prepare_v2, 'EXECUTE')
     or not has_function_privilege('lifemate_admin_runtime', v_confirm, 'EXECUTE')
     or not has_function_privilege('lifemate_admin_runtime', v_schedule, 'EXECUTE') then
    raise exception 'admin runtime lacks canonical campaign execution functions';
  end if;
  if has_function_privilege('lifemate_admin_runtime', v_claim, 'EXECUTE')
     or has_function_privilege('lifemate_admin_runtime', v_resolve, 'EXECUTE')
     or has_function_privilege('lifemate_admin_runtime', v_result_v2, 'EXECUTE') then
    raise exception 'admin runtime unexpectedly owns provider worker authority';
  end if;
  if not has_function_privilege('lifemate_worker_runtime', v_claim, 'EXECUTE')
     or not has_function_privilege('lifemate_worker_runtime', v_resolve, 'EXECUTE')
     or not has_function_privilege('lifemate_worker_runtime', v_result_v2, 'EXECUTE') then
    raise exception 'worker runtime lacks bounded delivery authority';
  end if;
  if has_function_privilege('lifemate_worker_runtime', v_prepare_v2, 'EXECUTE')
     or has_function_privilege('lifemate_worker_runtime', v_confirm, 'EXECUTE') then
    raise exception 'worker runtime unexpectedly owns campaign approval authority';
  end if;

  if consent.account_allows_optional_purpose(v_unknown_account,'promotional_sms','GLOBAL') then
    raise exception 'promotional SMS must fail closed without explicit opt-in';
  end if;
  if consent.account_allows_optional_purpose(v_unknown_account,'promotional_push','GLOBAL') then
    raise exception 'promotional Push must fail closed without explicit opt-in';
  end if;

  v_definition := lower(pg_get_functiondef(v_prepare_v2));
  if position('campaign_sms_provider_required' in v_definition)=0
     or position('sms_provider' in v_definition)=0 then
    raise exception 'campaign preparation must persist explicit SMS provider selection';
  end if;

  v_definition := lower(pg_get_functiondef(v_confirm));
  if position('for update' in v_definition)=0 then
    raise exception 'campaign confirmation must lock the execution row';
  end if;
  if position('p_correlation_id,false' in replace(v_definition,' ',''))=0 then
    raise exception 'campaign confirmation must not masquerade as elevated health access';
  end if;

  v_definition := lower(pg_get_functiondef(v_schedule));
  if position('for update' in v_definition)=0 then
    raise exception 'campaign scheduling must lock the execution row';
  end if;

  v_definition := lower(pg_get_functiondef(v_claim));
  if position('skip locked' in v_definition)=0 then
    raise exception 'delivery claims must use skip locked for concurrent workers';
  end if;

  v_definition := lower(pg_get_functiondef(v_resolve));
  if position('encrypted_value' in v_definition)=0
     or position('token_ciphertext' in v_definition)=0 then
    raise exception 'worker delivery projection must resolve encrypted endpoint envelopes';
  end if;

  v_definition := lower(pg_get_functiondef(v_result_v2));
  if position('for update' in v_definition)=0 then
    raise exception 'delivery result recording must lock the delivery job';
  end if;
  if position('outcomeunknown' in replace(v_definition,' ',''))=0
     or position('permanentfailed' in replace(v_definition,' ',''))=0
     or position('neitherisautomaticallyretried' in replace(v_definition,' ',''))=0 then
    raise exception 'unknown and permanent provider outcomes must be terminal without automatic retry';
  end if;
end $$;
