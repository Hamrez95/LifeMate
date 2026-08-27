begin;

-- Keep the original purpose mutation internal and expose a concurrency-aware
-- wrapper to the restricted Admin runtime.
revoke execute on function commerce.execute_manual_entitlement_adjustment(
  uuid,uuid,uuid,uuid,uuid,character varying,timestamptz,integer,integer,
  character varying,boolean,uuid,bigint,uuid,uuid,character varying,character varying
) from lifemate_admin_runtime;

-- Entitlement event history gains a truthful generic adjustment event. Existing
-- event values remain valid and unchanged.
alter table commerce.entitlement_events
  drop constraint if exists entitlement_events_event_type_check;
alter table commerce.entitlement_events
  add constraint entitlement_events_event_type_check
  check (event_type in ('Granted','Renewed','Adjusted','Expired','Cancelled','Revoked','Refunded','Chargeback','TrialStarted','TrialConverted'));

create or replace function commerce.normalize_manual_adjustment_event()
returns trigger
language plpgsql
set search_path=pg_catalog,pg_temp
as $$
begin
  if new.event_type='Renewed'
     and lower(coalesce(new.metadata_json->>'operation',''))='reduce' then
    new.event_type:='Adjusted';
  end if;
  return new;
end $$;

drop trigger if exists trg_normalize_manual_adjustment_event on commerce.entitlement_events;
create trigger trg_normalize_manual_adjustment_event
before insert on commerce.entitlement_events
for each row execute function commerce.normalize_manual_adjustment_event();

create or replace function commerce.execute_manual_entitlement_adjustment_v2(
  p_actor_account_id uuid,
  p_subject_account_id uuid,
  p_entitlement_id uuid,
  p_expected_entitlement_version bigint,
  p_feature_id uuid,
  p_offer_id uuid,
  p_operation character varying,
  p_exact_expires_at_utc timestamptz,
  p_add_days integer,
  p_add_months integer,
  p_reason character varying,
  p_confirmed boolean,
  p_approval_request_id uuid,
  p_approval_expected_version bigint,
  p_abuse_decision_id uuid,
  p_correlation_id uuid,
  p_idempotency_key character varying,
  p_request_hash character varying
) returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,commerce,admin,security,pg_temp
as $$
declare
  v_operation character varying(16):=initcap(lower(trim(coalesce(p_operation,''))));
  v_current_version bigint;
  v_result jsonb;
begin
  if v_operation<>'Grant' then
    if p_entitlement_id is null or p_expected_entitlement_version is null or p_expected_entitlement_version<1 then
      return jsonb_build_object('httpStatus',400,'code','entitlement_adjust_version_required','message','Existing entitlement adjustments require expectedEntitlementVersion.','replayed',false);
    end if;
    select version into v_current_version
    from commerce.entitlements
    where id=p_entitlement_id
    for update;
    if not found then
      return jsonb_build_object('httpStatus',404,'code','entitlement_not_found','message','Entitlement was not found.','replayed',false);
    end if;
    if v_current_version<>p_expected_entitlement_version then
      return jsonb_build_object('httpStatus',409,'code','entitlement_version_conflict','message','Entitlement changed; refresh before adjusting.','currentVersion',v_current_version,'replayed',false);
    end if;
  elsif p_expected_entitlement_version is not null then
    return jsonb_build_object('httpStatus',400,'code','entitlement_grant_version_invalid','message','Grant must not include expectedEntitlementVersion.','replayed',false);
  end if;

  v_result:=commerce.execute_manual_entitlement_adjustment(
    p_actor_account_id,p_subject_account_id,p_entitlement_id,p_feature_id,p_offer_id,
    v_operation,p_exact_expires_at_utc,p_add_days,p_add_months,p_reason,p_confirmed,
    p_approval_request_id,p_approval_expected_version,p_abuse_decision_id,p_correlation_id,
    p_idempotency_key,p_request_hash
  );
  return v_result;
end $$;

revoke all on function commerce.normalize_manual_adjustment_event() from public,anon,authenticated;
revoke all on function commerce.execute_manual_entitlement_adjustment_v2(
  uuid,uuid,uuid,bigint,uuid,uuid,character varying,timestamptz,integer,integer,
  character varying,boolean,uuid,bigint,uuid,uuid,character varying,character varying
) from public,anon,authenticated;
grant execute on function commerce.execute_manual_entitlement_adjustment_v2(
  uuid,uuid,uuid,bigint,uuid,uuid,character varying,timestamptz,integer,integer,
  character varying,boolean,uuid,bigint,uuid,uuid,character varying,character varying
) to lifemate_admin_runtime;

comment on function commerce.execute_manual_entitlement_adjustment_v2(
  uuid,uuid,uuid,bigint,uuid,uuid,character varying,timestamptz,integer,integer,
  character varying,boolean,uuid,bigint,uuid,uuid,character varying,character varying
) is 'Concurrency-aware public Admin runtime entrypoint for #492 manual entitlement operations.';

commit;
