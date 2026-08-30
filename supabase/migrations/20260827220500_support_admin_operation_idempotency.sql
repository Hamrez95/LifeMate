-- #569: expose support escalation/reference operations through the canonical Admin API
-- without allowing direct table/browser mutation. Existing #496 tables remain canonical.

create or replace function admin.create_support_escalation_idempotent(
  p_actor_account_id uuid,
  p_ticket_id uuid,
  p_target_role_code character varying,
  p_safe_reason character varying,
  p_correlation_id uuid,
  p_idempotency_key character varying,
  p_request_hash character varying
) returns jsonb
language plpgsql
security definer
set search_path = admin,support,pg_temp
as $$
declare
  v_inserted integer;
  v_existing admin.idempotency_keys%rowtype;
  v_escalation_id uuid;
  v_response jsonb;
begin
  if not admin.account_has_permission(p_actor_account_id,'support.write') then
    raise exception using errcode='42501',message='permission_denied';
  end if;
  if p_idempotency_key is null or length(p_idempotency_key) < 8 or length(p_idempotency_key) > 180
     or p_request_hash is null or length(p_request_hash) <> 64 then
    raise exception using errcode='22023',message='idempotency_invalid';
  end if;

  insert into admin.idempotency_keys(
    actor_account_id,operation,idempotency_key,request_hash,status
  ) values(
    p_actor_account_id,'support.escalation.create',p_idempotency_key,p_request_hash,'Processing'
  ) on conflict do nothing;
  get diagnostics v_inserted = row_count;

  if v_inserted = 0 then
    select * into v_existing
    from admin.idempotency_keys
    where actor_account_id=p_actor_account_id
      and operation='support.escalation.create'
      and idempotency_key=p_idempotency_key
    for update;
    if v_existing.request_hash <> p_request_hash then
      return jsonb_build_object('httpStatus',409,'code','idempotency_conflict');
    end if;
    if v_existing.status='Completed' and v_existing.response_json is not null then
      return v_existing.response_json || jsonb_build_object('replayed',true);
    end if;
    return jsonb_build_object('httpStatus',409,'code','operation_in_progress');
  end if;

  v_escalation_id := admin.create_support_escalation(
    p_actor_account_id,p_ticket_id,p_target_role_code,p_safe_reason,p_correlation_id
  );
  v_response := jsonb_build_object(
    'httpStatus',201,'code','support_escalation_created',
    'ticketId',p_ticket_id,'escalationId',v_escalation_id,'replayed',false
  );
  update admin.idempotency_keys
  set status='Completed',response_status=201,response_json=v_response,updated_at_utc=now()
  where actor_account_id=p_actor_account_id
    and operation='support.escalation.create'
    and idempotency_key=p_idempotency_key;
  return v_response;
end
$$;

create or replace function admin.link_support_ticket_reference_idempotent(
  p_actor_account_id uuid,
  p_ticket_id uuid,
  p_link_kind character varying,
  p_reference_code character varying,
  p_correlation_id uuid,
  p_idempotency_key character varying,
  p_request_hash character varying
) returns jsonb
language plpgsql
security definer
set search_path = admin,support,pg_temp
as $$
declare
  v_inserted integer;
  v_existing admin.idempotency_keys%rowtype;
  v_link_id uuid;
  v_response jsonb;
begin
  if not admin.account_has_permission(p_actor_account_id,'support.write') then
    raise exception using errcode='42501',message='permission_denied';
  end if;
  if p_idempotency_key is null or length(p_idempotency_key) < 8 or length(p_idempotency_key) > 180
     or p_request_hash is null or length(p_request_hash) <> 64 then
    raise exception using errcode='22023',message='idempotency_invalid';
  end if;

  insert into admin.idempotency_keys(
    actor_account_id,operation,idempotency_key,request_hash,status
  ) values(
    p_actor_account_id,'support.reference.link',p_idempotency_key,p_request_hash,'Processing'
  ) on conflict do nothing;
  get diagnostics v_inserted = row_count;

  if v_inserted = 0 then
    select * into v_existing
    from admin.idempotency_keys
    where actor_account_id=p_actor_account_id
      and operation='support.reference.link'
      and idempotency_key=p_idempotency_key
    for update;
    if v_existing.request_hash <> p_request_hash then
      return jsonb_build_object('httpStatus',409,'code','idempotency_conflict');
    end if;
    if v_existing.status='Completed' and v_existing.response_json is not null then
      return v_existing.response_json || jsonb_build_object('replayed',true);
    end if;
    return jsonb_build_object('httpStatus',409,'code','operation_in_progress');
  end if;

  v_link_id := admin.link_support_ticket_reference(
    p_actor_account_id,p_ticket_id,p_link_kind,p_reference_code,p_correlation_id
  );
  v_response := jsonb_build_object(
    'httpStatus',201,'code','support_reference_linked',
    'ticketId',p_ticket_id,'linkId',v_link_id,'replayed',false
  );
  update admin.idempotency_keys
  set status='Completed',response_status=201,response_json=v_response,updated_at_utc=now()
  where actor_account_id=p_actor_account_id
    and operation='support.reference.link'
    and idempotency_key=p_idempotency_key;
  return v_response;
end
$$;

revoke all on function admin.create_support_escalation_idempotent(uuid,uuid,character varying,character varying,uuid,character varying,character varying) from public;
revoke all on function admin.link_support_ticket_reference_idempotent(uuid,uuid,character varying,character varying,uuid,character varying,character varying) from public;

do $$
begin
  if exists(select 1 from pg_roles where rolname='lifemate_admin_runtime') then
    grant execute on function admin.create_support_escalation_idempotent(uuid,uuid,character varying,character varying,uuid,character varying,character varying)
      to lifemate_admin_runtime;
    grant execute on function admin.link_support_ticket_reference_idempotent(uuid,uuid,character varying,character varying,uuid,character varying,character varying)
      to lifemate_admin_runtime;
  end if;
end
$$;
