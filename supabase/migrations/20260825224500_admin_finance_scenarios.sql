begin;

insert into admin.permissions(code, domain, description, risk_level)
values ('finance.scenario.write','finance','Create and version canonical finance scenarios','HIGH_RISK')
on conflict (code) do update
set description = excluded.description,
    risk_level = excluded.risk_level;

insert into admin.role_permissions(role_id, permission_code)
select roles.id, 'finance.scenario.write'
from admin.roles
where roles.code in ('Founder','SuperAdmin')
on conflict do nothing;

create table if not exists admin.finance_scenarios (
  scenario_id uuid primary key default gen_random_uuid(),
  scenario_kind character varying(16) not null check (scenario_kind in ('BASE','UPSIDE','DOWNSIDE')),
  name character varying(120) not null,
  currency character(3) not null check (currency ~ '^[A-Z]{3}$'),
  valid_from date not null,
  valid_to date not null,
  version integer not null default 1 check (version > 0),
  assumptions_json jsonb not null,
  created_by_account_id uuid references identity.accounts(id) on delete set null,
  updated_by_account_id uuid references identity.accounts(id) on delete set null,
  created_at_utc timestamptz not null default now(),
  updated_at_utc timestamptz not null default now(),
  check (valid_to >= valid_from),
  check (jsonb_typeof(assumptions_json) = 'array')
);

alter table admin.finance_scenarios enable row level security;
alter table admin.finance_scenarios force row level security;
drop policy if exists finance_scenarios_no_direct_access on admin.finance_scenarios;
create policy finance_scenarios_no_direct_access
  on admin.finance_scenarios for all using (false) with check (false);

create or replace function admin.get_finance_scenarios()
returns table(
  scenario_id uuid,
  scenario_kind character varying,
  name character varying,
  currency character,
  valid_from date,
  valid_to date,
  version integer,
  assumptions_json jsonb,
  created_at_utc timestamptz,
  updated_at_utc timestamptz
)
language sql
security definer
set search_path = admin, pg_temp
as $$
  select s.scenario_id, s.scenario_kind, s.name, s.currency, s.valid_from, s.valid_to,
         s.version, s.assumptions_json, s.created_at_utc, s.updated_at_utc
  from admin.finance_scenarios s
  order by s.updated_at_utc desc, s.scenario_id;
$$;

revoke all on function admin.get_finance_scenarios() from public;
grant execute on function admin.get_finance_scenarios() to lifemate_admin_runtime;

create or replace function admin.configure_finance_scenario(
  p_actor_account_id uuid,
  p_scenario_id uuid,
  p_scenario_kind character varying,
  p_name character varying,
  p_currency character,
  p_valid_from date,
  p_valid_to date,
  p_assumptions_json jsonb,
  p_expected_version integer,
  p_reason character varying,
  p_correlation_id uuid,
  p_idempotency_key character varying,
  p_request_hash character varying
) returns jsonb
language plpgsql
security definer
set search_path = admin, pg_catalog, pg_temp
as $$
declare
  v_operation constant character varying := 'finance.scenario.configure';
  v_existing admin.idempotency_keys%rowtype;
  v_scenario admin.finance_scenarios%rowtype;
  v_scenario_id uuid := coalesce(p_scenario_id, gen_random_uuid());
  v_response jsonb;
  v_assumption jsonb;
begin
  if not admin.account_has_permission(p_actor_account_id,'finance.scenario.write') then
    return jsonb_build_object('httpStatus',403,'code','permission_denied','message','The required permission is not granted.','replayed',false);
  end if;

  if p_scenario_kind not in ('BASE','UPSIDE','DOWNSIDE')
     or p_name is null or length(trim(p_name)) not between 1 and 120
     or p_currency is null or p_currency !~ '^[A-Z]{3}$'
     or p_valid_from is null or p_valid_to is null or p_valid_to < p_valid_from
     or p_assumptions_json is null or jsonb_typeof(p_assumptions_json) <> 'array'
     or jsonb_array_length(p_assumptions_json) not between 1 and 100 then
    return jsonb_build_object('httpStatus',400,'code','finance_scenario_invalid','message','Scenario values are invalid.','replayed',false);
  end if;

  for v_assumption in select value from jsonb_array_elements(p_assumptions_json)
  loop
    if jsonb_typeof(v_assumption) <> 'object'
       or (v_assumption->>'classification') not in ('BUDGET','FORECAST')
       or coalesce(v_assumption->>'code','') !~ '^[A-Z0-9_.-]{1,64}$'
       or coalesce(v_assumption->>'amountMinor','') !~ '^-?[0-9]+$' then
      return jsonb_build_object('httpStatus',400,'code','finance_scenario_assumption_invalid','message','Scenario assumption is invalid.','replayed',false);
    end if;
  end loop;

  if p_reason is null or length(trim(p_reason)) not between 10 and 1000
     or p_idempotency_key is null or length(p_idempotency_key) not between 8 and 180
     or p_request_hash is null or length(p_request_hash) not between 32 and 128 then
    return jsonb_build_object('httpStatus',400,'code','finance_scenario_request_invalid','message','Scenario request metadata is invalid.','replayed',false);
  end if;

  perform pg_advisory_xact_lock(hashtextextended(p_actor_account_id::text || ':' || v_operation || ':' || p_idempotency_key,0));
  select * into v_existing from admin.idempotency_keys
  where actor_account_id = p_actor_account_id and operation = v_operation and idempotency_key = p_idempotency_key
  for update;

  if found then
    if v_existing.request_hash <> p_request_hash then
      return jsonb_build_object('httpStatus',409,'code','idempotency_conflict','message','This Idempotency-Key was already used for a different request.','replayed',false);
    end if;
    if v_existing.status = 'Completed' and v_existing.response_json is not null then
      return v_existing.response_json || jsonb_build_object('replayed',true);
    end if;
    return jsonb_build_object('httpStatus',409,'code','idempotency_in_progress','message','The matching request is still being processed.','replayed',false);
  end if;

  insert into admin.idempotency_keys(actor_account_id,operation,idempotency_key,request_hash,status)
  values (p_actor_account_id,v_operation,p_idempotency_key,p_request_hash,'Processing');

  perform pg_advisory_xact_lock(hashtextextended('admin.finance_scenario:' || v_scenario_id::text,0));
  select * into v_scenario from admin.finance_scenarios where scenario_id = v_scenario_id for update;

  if found then
    if p_expected_version is null or v_scenario.version <> p_expected_version then
      v_response := jsonb_build_object('httpStatus',409,'code','finance_scenario_version_conflict','message','Scenario version does not match.','replayed',false);
    elsif v_scenario.currency <> p_currency then
      v_response := jsonb_build_object('httpStatus',409,'code','finance_scenario_currency_immutable','message','Scenario currency cannot be changed implicitly. Create a new scenario instead.','replayed',false);
    else
      update admin.finance_scenarios
      set scenario_kind=p_scenario_kind, name=trim(p_name), valid_from=p_valid_from, valid_to=p_valid_to,
          assumptions_json=p_assumptions_json, version=version+1, updated_by_account_id=p_actor_account_id, updated_at_utc=now()
      where scenario_id=v_scenario_id returning * into v_scenario;
      v_response := jsonb_build_object('httpStatus',200,'code','ok','scenarioId',v_scenario.scenario_id,'version',v_scenario.version,'updatedAtUtc',v_scenario.updated_at_utc,'replayed',false);
    end if;
  else
    if p_scenario_id is not null or p_expected_version is not null then
      v_response := jsonb_build_object('httpStatus',404,'code','finance_scenario_not_found','message','Scenario was not found.','replayed',false);
    else
      insert into admin.finance_scenarios(
        scenario_id,scenario_kind,name,currency,valid_from,valid_to,assumptions_json,created_by_account_id,updated_by_account_id
      ) values (
        v_scenario_id,p_scenario_kind,trim(p_name),p_currency,p_valid_from,p_valid_to,p_assumptions_json,p_actor_account_id,p_actor_account_id
      ) returning * into v_scenario;
      v_response := jsonb_build_object('httpStatus',201,'code','created','scenarioId',v_scenario.scenario_id,'version',v_scenario.version,'updatedAtUtc',v_scenario.updated_at_utc,'replayed',false);
    end if;
  end if;

  insert into admin.audit_events(
    actor_account_id, action, resource_type, resource_id, result, reason,
    correlation_id, request_id, elevated_access, metadata_json
  ) values (
    p_actor_account_id, v_operation, 'finance_scenario', v_scenario_id::text,
    case when (v_response->>'httpStatus')::integer < 400 then 'Succeeded' else 'Denied' end,
    trim(p_reason), p_correlation_id, p_idempotency_key, false,
    jsonb_build_object(
      'code',v_response->>'code','scenarioKind',p_scenario_kind,'currency',p_currency,
      'expectedVersion',p_expected_version,'classificationPolicy','BUDGET_OR_FORECAST_ONLY','implicitFx',false
    )
  );

  update admin.idempotency_keys
  set status='Completed', response_status=(v_response->>'httpStatus')::integer,
      response_json=v_response, updated_at_utc=now()
  where actor_account_id=p_actor_account_id and operation=v_operation and idempotency_key=p_idempotency_key;

  return v_response;
end $$;

revoke all on function admin.configure_finance_scenario(
  uuid,uuid,character varying,character varying,character,date,date,jsonb,integer,character varying,uuid,character varying,character varying
) from public;
grant execute on function admin.configure_finance_scenario(
  uuid,uuid,character varying,character varying,character,date,date,jsonb,integer,character varying,uuid,character varying,character varying
) to lifemate_admin_runtime;

commit;
