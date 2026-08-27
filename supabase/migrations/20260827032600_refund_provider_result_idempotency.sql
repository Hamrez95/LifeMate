begin;

-- Provider result callbacks are evidence, not commands. Repeated delivery of the
-- same evidence is safe; contradictory terminal evidence must fail closed.
create or replace function commerce.record_refund_provider_result(
  p_refund_operation_id uuid,
  p_result character varying,
  p_provider_reference character varying,
  p_provider_error_code character varying
) returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,commerce,extensions,pg_temp
as $$
declare
  v_op commerce.refund_operations%rowtype;
  v_result character varying(16):=initcap(lower(trim(coalesce(p_result,''))));
  v_reference character varying:=nullif(trim(coalesce(p_provider_reference,'')),'');
  v_error character varying:=nullif(trim(coalesce(p_provider_error_code,'')),'');
  v_reference_hash character varying(64);
begin
  if v_result not in ('Succeeded','Failed') then
    return jsonb_build_object('httpStatus',400,'code','provider_result_invalid');
  end if;

  if v_result='Succeeded' then
    if v_reference is null or length(v_reference)>512 then
      return jsonb_build_object('httpStatus',400,'code','provider_reference_required');
    end if;
    v_reference_hash:=encode(extensions.digest(v_reference,'sha256'),'hex');
  else
    if v_error is null or length(v_error)>120 then
      return jsonb_build_object('httpStatus',400,'code','provider_error_code_required');
    end if;
  end if;

  select * into v_op
  from commerce.refund_operations
  where id=p_refund_operation_id
  for update;

  if not found then
    return jsonb_build_object('httpStatus',404,'code','refund_operation_not_found');
  end if;

  if v_op.status in ('Succeeded','Failed') then
    if v_op.status<>v_result then
      return jsonb_build_object(
        'httpStatus',409,
        'code','provider_result_conflict',
        'status',v_op.status
      );
    end if;
    if v_result='Succeeded' and v_op.provider_reference_hash is distinct from v_reference_hash then
      return jsonb_build_object(
        'httpStatus',409,
        'code','provider_evidence_conflict',
        'status',v_op.status
      );
    end if;
    if v_result='Failed' and v_op.provider_error_code is distinct from v_error then
      return jsonb_build_object(
        'httpStatus',409,
        'code','provider_evidence_conflict',
        'status',v_op.status
      );
    end if;
    return jsonb_build_object(
      'httpStatus',200,
      'code','ok',
      'status',v_op.status,
      'replayed',true
    );
  end if;

  if v_op.status not in ('PendingProvider','Submitted') then
    return jsonb_build_object(
      'httpStatus',409,
      'code','refund_operation_state_invalid',
      'status',v_op.status
    );
  end if;

  update commerce.refund_operations
  set status=v_result,
      provider_reference_hash=case when v_result='Succeeded' then v_reference_hash else null end,
      provider_error_code=case when v_result='Failed' then v_error else null end,
      submitted_at_utc=coalesce(submitted_at_utc,now()),
      settled_at_utc=now(),
      updated_at_utc=now()
  where id=v_op.id;

  update commerce.refund_requests
  set status=v_result,
      updated_at_utc=now(),
      version=version+1,
      resolution_reason=case
        when v_result='Failed' then 'Provider execution failed; see privacy-safe provider error code.'
        else resolution_reason
      end
  where id=v_op.refund_request_id;

  return jsonb_build_object(
    'httpStatus',200,
    'code','ok',
    'refundOperationId',v_op.id,
    'refundRequestId',v_op.refund_request_id,
    'status',v_result,
    'replayed',false
  );
end
$$;

revoke all on function commerce.record_refund_provider_result(uuid,character varying,character varying,character varying)
  from public;

do $$
begin
  if to_regrole('anon') is not null then
    revoke all on function commerce.record_refund_provider_result(uuid,character varying,character varying,character varying)
      from anon;
  end if;
  if to_regrole('authenticated') is not null then
    revoke all on function commerce.record_refund_provider_result(uuid,character varying,character varying,character varying)
      from authenticated;
  end if;
end
$$;

grant execute on function commerce.record_refund_provider_result(uuid,character varying,character varying,character varying)
  to lifemate_worker_runtime;

comment on function commerce.record_refund_provider_result(uuid,character varying,character varying,character varying) is
  'Records privacy-safe provider refund evidence idempotently and rejects blank or contradictory terminal evidence.';

commit;
