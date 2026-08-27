begin;

create or replace function commerce.manual_adjustment_approval_valid(
  p_actor_account_id uuid,
  p_subject_account_id uuid,
  p_approval_request_id uuid,
  p_approval_expected_version bigint,
  p_before jsonb,
  p_delta jsonb,
  p_after jsonb,
  p_correlation_id uuid
) returns boolean
language plpgsql
security definer
set search_path=pg_catalog,admin,commerce,pg_temp
as $$
declare v_approval jsonb;
begin
  v_approval:=admin.consume_approval_request(
    p_actor_account_id,p_approval_request_id,p_approval_expected_version,
    'commerce.entitlement.adjust.execute',p_correlation_id
  );
  if v_approval->>'requestType'<>'manual_entitlement_adjustment'
     or v_approval->>'targetType'<>'account'
     or v_approval->>'targetId'<>p_subject_account_id::text
     or v_approval->'before'<>p_before
     or v_approval->'delta'<>p_delta
     or v_approval->'after'<>p_after then
    raise exception using errcode='22023',message='Approval snapshot no longer matches current entitlement state.';
  end if;
  return true;
end $$;

revoke all on function commerce.manual_adjustment_approval_valid(uuid,uuid,uuid,bigint,jsonb,jsonb,jsonb,uuid) from public,anon,authenticated;

create or replace function commerce.manual_adjustment_after_state(p_entitlement_id uuid)
returns jsonb
language sql stable
set search_path=commerce,pg_temp
as $$
  select jsonb_build_object(
    'entitlementId',e.id,'featureId',e.feature_id,'status',e.status,
    'expiresAtUtc',e.expires_at_utc,'version',e.version
  ) from commerce.entitlements e where e.id=p_entitlement_id
$$;

revoke all on function commerce.manual_adjustment_after_state(uuid) from public,anon,authenticated;
grant execute on function commerce.manual_adjustment_after_state(uuid) to lifemate_admin_runtime;

commit;
