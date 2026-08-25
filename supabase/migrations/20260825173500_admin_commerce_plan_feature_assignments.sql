begin;

create table if not exists commerce.plan_feature_assignments (
  plan_id uuid not null references commerce.plans(id) on delete restrict,
  feature_id uuid not null references commerce.features(id) on delete restrict,
  assigned boolean not null default false,
  version integer not null default 1 check (version > 0),
  created_at_utc timestamptz not null default now(),
  updated_at_utc timestamptz not null default now(),
  primary key (plan_id, feature_id)
);

alter table commerce.plan_feature_assignments enable row level security;
alter table commerce.plan_feature_assignments force row level security;
drop policy if exists plan_feature_assignments_no_direct_access on commerce.plan_feature_assignments;
create policy plan_feature_assignments_no_direct_access
  on commerce.plan_feature_assignments for all using (false) with check (false);

insert into admin.permissions(code, domain, risk_level, role_assignable, description)
values ('commerce.plan_feature.write','commerce','HIGH_RISK',true,
  'Configure explicit versioned plan-to-feature assignments through the audited server workflow')
on conflict (code) do update set
  domain = excluded.domain,
  risk_level = excluded.risk_level,
  role_assignable = excluded.role_assignable,
  description = excluded.description,
  updated_at_utc = now();

insert into admin.role_permissions(role_id, permission_code)
select r.id, 'commerce.plan_feature.write'
from admin.roles r
where r.code in ('founder','super_admin','product')
on conflict do nothing;

create or replace function admin.get_commerce_plan_features(p_plan_id uuid)
returns table(
  feature_id uuid,
  feature_code character varying,
  description character varying,
  assigned boolean,
  version integer,
  updated_at_utc timestamptz
)
language sql
security definer
set search_path = admin, commerce, pg_temp
as $$
  select f.id, f.code, f.description,
         coalesce(a.assigned, false),
         coalesce(a.version, 0),
         a.updated_at_utc
  from commerce.plans pl
  join commerce.product_features pf on pf.product_id = pl.product_id
  join commerce.features f on f.id = pf.feature_id
  left join commerce.plan_feature_assignments a
    on a.plan_id = pl.id and a.feature_id = f.id
  where pl.id = p_plan_id
  order by f.code asc;
$$;

revoke all on function admin.get_commerce_plan_features(uuid) from public;
grant execute on function admin.get_commerce_plan_features(uuid) to lifemate_admin_runtime;

create or replace function admin.configure_commerce_plan_feature(
  p_actor_account_id uuid,
  p_plan_id uuid,
  p_feature_id uuid,
  p_assigned boolean,
  p_expected_version integer,
  p_reason character varying,
  p_correlation_id uuid,
  p_idempotency_key character varying,
  p_request_hash character varying
) returns jsonb
language plpgsql
security definer
set search_path = admin, commerce, pg_temp
as $$
declare
  v_operation constant character varying := 'commerce.plan_feature.configure';
  v_existing admin.idempotency_keys%rowtype;
  v_assignment commerce.plan_feature_assignments%rowtype;
  v_response jsonb;
begin
  if not admin.account_has_permission(p_actor_account_id,'commerce.plan_feature.write') then
    return jsonb_build_object('httpStatus',403,'code','permission_denied','message','The required permission is not granted.','replayed',false);
  end if;
  if p_plan_id is null or p_feature_id is null or p_assigned is null or p_expected_version is null or p_expected_version < 0 then
    return jsonb_build_object('httpStatus',400,'code','plan_feature_invalid','message','Plan feature fields are invalid.','replayed',false);
  end if;
  if p_reason is null or length(trim(p_reason)) not between 10 and 1000
     or p_idempotency_key is null or length(p_idempotency_key) not between 8 and 180
     or p_request_hash is null or length(p_request_hash) not between 32 and 128 then
    return jsonb_build_object('httpStatus',400,'code','plan_feature_request_invalid','message','Plan feature request metadata is invalid.','replayed',false);
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

  perform pg_advisory_xact_lock(hashtextextended('commerce.plan_feature:' || p_plan_id::text || ':' || p_feature_id::text,0));

  if not exists (
    select 1
    from commerce.plans pl
    join commerce.products pr on pr.id = pl.product_id
    join commerce.product_features pf on pf.product_id = pl.product_id and pf.feature_id = p_feature_id
    where pl.id = p_plan_id and pl.status = 'Active' and pr.status = 'Active'
  ) then
    v_response := jsonb_build_object('httpStatus',409,'code','plan_feature_not_assignable','message','The feature is not assignable to this active plan.','replayed',false);
  else
    select * into v_assignment from commerce.plan_feature_assignments
    where plan_id = p_plan_id and feature_id = p_feature_id for update;

    if not found then
      if p_expected_version <> 0 then
        v_response := jsonb_build_object('httpStatus',409,'code','plan_feature_version_conflict','message','Plan feature version does not match.','replayed',false);
      else
        insert into commerce.plan_feature_assignments(plan_id,feature_id,assigned,version)
        values (p_plan_id,p_feature_id,p_assigned,1)
        returning * into v_assignment;
        v_response := jsonb_build_object('httpStatus',201,'code','ok','planId',p_plan_id,'featureId',p_feature_id,'assigned',v_assignment.assigned,'version',v_assignment.version,'replayed',false);
      end if;
    elsif v_assignment.version <> p_expected_version then
      v_response := jsonb_build_object('httpStatus',409,'code','plan_feature_version_conflict','message','Plan feature version does not match.','replayed',false);
    else
      update commerce.plan_feature_assignments
      set assigned = p_assigned, version = version + 1, updated_at_utc = now()
      where plan_id = p_plan_id and feature_id = p_feature_id
      returning * into v_assignment;
      v_response := jsonb_build_object('httpStatus',200,'code','ok','planId',p_plan_id,'featureId',p_feature_id,'assigned',v_assignment.assigned,'version',v_assignment.version,'replayed',false);
    end if;
  end if;

  insert into admin.audit_events(
    actor_account_id, action, resource_type, resource_id, result, reason,
    correlation_id, request_id, elevated_access, metadata_json
  ) values (
    p_actor_account_id, v_operation, 'commerce_plan_feature',
    p_plan_id::text || ':' || p_feature_id::text,
    case when (v_response->>'httpStatus')::integer < 400 then 'Succeeded' else 'Denied' end,
    trim(p_reason), p_correlation_id, p_idempotency_key, false,
    jsonb_build_object('code',v_response->>'code','featureId',p_feature_id,'assigned',p_assigned,'expectedVersion',p_expected_version)
  );

  update admin.idempotency_keys
  set status='Completed', response_status=(v_response->>'httpStatus')::integer,
      response_json=v_response, updated_at_utc=now()
  where actor_account_id=p_actor_account_id and operation=v_operation and idempotency_key=p_idempotency_key;

  return v_response;
end $$;

revoke all on function admin.configure_commerce_plan_feature(
  uuid,uuid,uuid,boolean,integer,character varying,uuid,character varying,character varying
) from public;
grant execute on function admin.configure_commerce_plan_feature(
  uuid,uuid,uuid,boolean,integer,character varying,uuid,character varying,character varying
) to lifemate_admin_runtime;

commit;
