begin;

create or replace function commerce.preview_entitlement_adjustment_v2(
  p_account_id uuid,
  p_target_type character varying,
  p_target_id uuid,
  p_action character varying,
  p_schedule_mode character varying,
  p_schedule_amount integer,
  p_exact_expires_at_utc timestamptz
) returns jsonb
language plpgsql
stable
security definer
set search_path=pg_catalog,commerce,pg_temp
as $$
declare
  v_result jsonb;
  v_has_indefinite boolean:=false;
begin
  v_result:=commerce.preview_entitlement_adjustment(
    p_account_id,p_target_type,p_target_id,p_action,p_schedule_mode,
    p_schedule_amount,p_exact_expires_at_utc
  );
  if coalesce((v_result->>'httpStatus')::integer,500)>=400 then return v_result; end if;
  if p_action='Extend' then
    select coalesce(bool_or((item->>'hasAdjustableIndefinite')::boolean),false)
      into v_has_indefinite
    from jsonb_array_elements(v_result->'before'->'features') item;
    if v_has_indefinite then
      return jsonb_build_object(
        'httpStatus',409,
        'code','entitlement_already_indefinite',
        'message','An indefinite paid/manual entitlement cannot be extended.'
      );
    end if;
  end if;
  return v_result;
end $$;

create or replace function commerce.execute_entitlement_adjustment_v2(
  p_actor_account_id uuid,
  p_account_id uuid,
  p_target_type character varying,
  p_target_id uuid,
  p_action character varying,
  p_schedule_mode character varying,
  p_schedule_amount integer,
  p_exact_expires_at_utc timestamptz,
  p_reason character varying,
  p_confirmed boolean,
  p_approval_request_id uuid,
  p_approval_expected_version bigint,
  p_correlation_id uuid,
  p_idempotency_key character varying,
  p_request_hash character varying
) returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,commerce,pg_temp
as $$
declare
  v_preview jsonb;
begin
  v_preview:=commerce.preview_entitlement_adjustment_v2(
    p_account_id,p_target_type,p_target_id,p_action,p_schedule_mode,
    p_schedule_amount,p_exact_expires_at_utc
  );
  if coalesce((v_preview->>'httpStatus')::integer,500)>=400 then return v_preview; end if;
  return commerce.execute_entitlement_adjustment(
    p_actor_account_id,p_account_id,p_target_type,p_target_id,p_action,p_schedule_mode,
    p_schedule_amount,p_exact_expires_at_utc,p_reason,p_confirmed,p_approval_request_id,
    p_approval_expected_version,p_correlation_id,p_idempotency_key,p_request_hash
  );
end $$;

revoke all on function commerce.preview_entitlement_adjustment(
  uuid,character varying,uuid,character varying,character varying,integer,timestamptz
) from lifemate_admin_runtime;
revoke all on function commerce.execute_entitlement_adjustment(
  uuid,uuid,character varying,uuid,character varying,character varying,integer,timestamptz,
  character varying,boolean,uuid,bigint,uuid,character varying,character varying
) from lifemate_admin_runtime;
revoke all on function commerce.preview_entitlement_adjustment_v2(
  uuid,character varying,uuid,character varying,character varying,integer,timestamptz
) from public,anon,authenticated;
revoke all on function commerce.execute_entitlement_adjustment_v2(
  uuid,uuid,character varying,uuid,character varying,character varying,integer,timestamptz,
  character varying,boolean,uuid,bigint,uuid,character varying,character varying
) from public,anon,authenticated;
grant execute on function commerce.preview_entitlement_adjustment_v2(
  uuid,character varying,uuid,character varying,character varying,integer,timestamptz
) to lifemate_admin_runtime;
grant execute on function commerce.execute_entitlement_adjustment_v2(
  uuid,uuid,character varying,uuid,character varying,character varying,integer,timestamptz,
  character varying,boolean,uuid,bigint,uuid,character varying,character varying
) to lifemate_admin_runtime;

commit;
