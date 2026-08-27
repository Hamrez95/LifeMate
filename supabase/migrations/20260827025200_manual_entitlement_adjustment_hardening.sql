begin;

-- #492 hardening: these permissions are business-authority permissions, not
-- break-glass health permissions. They must be assignable to the explicit Sales
-- and Founder roles or admin.account_has_permission() will always fail closed.
update admin.permissions
set risk_level='HIGH_RISK',role_assignable=true,updated_at_utc=now()
where code in ('commerce.entitlement.adjust.approve','commerce.entitlement.adjust.execute');

-- Preserve the generic entitlement event timeline without mislabelling a shorter
-- expiry as a cancellation.
alter table commerce.entitlement_events
  drop constraint if exists entitlement_events_event_type_check;
alter table commerce.entitlement_events
  add constraint entitlement_events_event_type_check
  check (event_type in ('Granted','Renewed','Adjusted','Expired','Cancelled','Revoked','Refunded','Chargeback','TrialStarted','TrialConverted'));

create or replace function commerce.normalize_manual_entitlement_adjustment_event()
returns trigger
language plpgsql
set search_path=pg_catalog,pg_temp
as $$
begin
  if new.event_type='Cancelled'
     and lower(coalesce(new.metadata_json->>'adminAction',''))='reduce' then
    new.event_type:='Adjusted';
  end if;
  return new;
end $$;

drop trigger if exists trg_normalize_manual_entitlement_adjustment_event on commerce.entitlement_events;
create trigger trg_normalize_manual_entitlement_adjustment_event
before insert on commerce.entitlement_events
for each row execute function commerce.normalize_manual_entitlement_adjustment_event();

-- Keep the existing mutation as the implementation primitive, but remove runtime
-- access to it. The public Admin entry point below adds the explicit confirmation
-- contract required for destructive Reduce/Revoke actions.
revoke execute on function commerce.execute_entitlement_adjustment(
  uuid,uuid,character varying,uuid,character varying,character varying,integer,timestamptz,
  character varying,uuid,bigint,uuid,character varying,character varying
) from lifemate_admin_runtime;

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
set search_path=pg_catalog,commerce,admin,security,pg_temp
as $$
declare
  v_action character varying(16):=initcap(lower(trim(coalesce(p_action,''))));
begin
  if v_action in ('Reduce','Revoke') and coalesce(p_confirmed,false)=false then
    return jsonb_build_object(
      'httpStatus',400,
      'code','entitlement_adjustment_confirmation_required',
      'message','Reduce and Revoke require explicit confirmation.',
      'replayed',false
    );
  end if;
  return commerce.execute_entitlement_adjustment(
    p_actor_account_id,p_account_id,p_target_type,p_target_id,p_action,p_schedule_mode,
    p_schedule_amount,p_exact_expires_at_utc,p_reason,p_approval_request_id,
    p_approval_expected_version,p_correlation_id,p_idempotency_key,p_request_hash
  );
end $$;

revoke all on function commerce.normalize_manual_entitlement_adjustment_event() from public,anon,authenticated;
revoke all on function commerce.execute_entitlement_adjustment_v2(
  uuid,uuid,character varying,uuid,character varying,character varying,integer,timestamptz,
  character varying,boolean,uuid,bigint,uuid,character varying,character varying
) from public,anon,authenticated;
grant execute on function commerce.execute_entitlement_adjustment_v2(
  uuid,uuid,character varying,uuid,character varying,character varying,integer,timestamptz,
  character varying,boolean,uuid,bigint,uuid,character varying,character varying
) to lifemate_admin_runtime;

comment on function commerce.execute_entitlement_adjustment_v2(
  uuid,uuid,character varying,uuid,character varying,character varying,integer,timestamptz,
  character varying,boolean,uuid,bigint,uuid,character varying,character varying
) is 'Canonical #492 Admin runtime entrypoint. Reduce/Revoke require explicit confirmation; purpose approval and abuse checks remain transactional in the underlying mutation.';

commit;
