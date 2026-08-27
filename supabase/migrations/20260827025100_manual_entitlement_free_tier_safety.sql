begin;

create or replace function commerce.entitlement_adjustment_snapshot(
  p_account_id uuid,
  p_target_type character varying,
  p_target_id uuid
) returns jsonb
language sql
stable
set search_path=commerce,pg_temp
as $$
  with tf as (
    select feature_id from commerce.entitlement_adjustment_target_features(p_target_type,p_target_id)
  ), rows as (
    select f.id as feature_id,f.code,
      count(e.id) filter (
        where e.source<>'FREE' and e.status='Active' and e.starts_at_utc<=now()
          and (e.expires_at_utc is null or e.expires_at_utc>now())
      ) as active_count,
      count(e.id) filter (
        where e.source='FREE' and e.status='Active' and e.starts_at_utc<=now()
          and (e.expires_at_utc is null or e.expires_at_utc>now())
      ) as free_active_count,
      bool_or(e.expires_at_utc is null) filter (
        where e.source<>'FREE' and e.status='Active' and e.starts_at_utc<=now()
          and (e.expires_at_utc is null or e.expires_at_utc>now())
      ) as has_indefinite,
      max(e.expires_at_utc) filter (
        where e.source<>'FREE' and e.status='Active' and e.starts_at_utc<=now()
          and e.expires_at_utc>now()
      ) as max_expires_at_utc
    from tf
    join commerce.features f on f.id=tf.feature_id
    left join commerce.entitlements e on e.feature_id=f.id and e.grantee_account_id=p_account_id
    group by f.id,f.code
  )
  select jsonb_build_object(
    'targetType',p_target_type,'targetId',p_target_id,'accountId',p_account_id,
    'features',coalesce(jsonb_agg(jsonb_build_object(
      'featureId',feature_id,'featureCode',code,'activeCount',active_count,
      'freeActiveCount',free_active_count,'hasIndefinite',coalesce(has_indefinite,false),
      'maxExpiresAtUtc',max_expires_at_utc
    ) order by code),'[]'::jsonb)
  ) from rows
$$;

alter function commerce.execute_entitlement_adjustment(
  uuid,uuid,character varying,uuid,character varying,character varying,integer,timestamptz,
  character varying,uuid,bigint,uuid,character varying,character varying
) rename to execute_entitlement_adjustment_internal_v1;

create or replace function commerce.guard_free_entitlement_from_manual_adjustment()
returns trigger
language plpgsql
set search_path=commerce,pg_temp
as $$
begin
  if old.source='FREE' and current_setting('lifemate.manual_entitlement_adjustment',true)='on' then
    return null;
  end if;
  return new;
end $$;

drop trigger if exists trg_guard_free_entitlement_manual_adjustment on commerce.entitlements;
create trigger trg_guard_free_entitlement_manual_adjustment
before update on commerce.entitlements
for each row execute function commerce.guard_free_entitlement_from_manual_adjustment();

create or replace function commerce.execute_entitlement_adjustment(
  p_actor_account_id uuid,
  p_account_id uuid,
  p_target_type character varying,
  p_target_id uuid,
  p_action character varying,
  p_schedule_mode character varying,
  p_schedule_amount integer,
  p_exact_expires_at_utc timestamptz,
  p_reason character varying,
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
declare v_result jsonb;
begin
  perform set_config('lifemate.manual_entitlement_adjustment','on',true);
  v_result:=commerce.execute_entitlement_adjustment_internal_v1(
    p_actor_account_id,p_account_id,p_target_type,p_target_id,p_action,p_schedule_mode,p_schedule_amount,
    p_exact_expires_at_utc,p_reason,p_approval_request_id,p_approval_expected_version,p_correlation_id,
    p_idempotency_key,p_request_hash
  );
  return v_result;
end $$;

revoke all on function commerce.execute_entitlement_adjustment_internal_v1(
  uuid,uuid,character varying,uuid,character varying,character varying,integer,timestamptz,
  character varying,uuid,bigint,uuid,character varying,character varying
) from public,anon,authenticated,lifemate_admin_runtime;
revoke all on function commerce.execute_entitlement_adjustment(
  uuid,uuid,character varying,uuid,character varying,character varying,integer,timestamptz,
  character varying,uuid,bigint,uuid,character varying,character varying
) from public,anon,authenticated;
grant execute on function commerce.execute_entitlement_adjustment(
  uuid,uuid,character varying,uuid,character varying,character varying,integer,timestamptz,
  character varying,uuid,bigint,uuid,character varying,character varying
) to lifemate_admin_runtime;

comment on function commerce.execute_entitlement_adjustment(
  uuid,uuid,character varying,uuid,character varying,character varying,integer,timestamptz,
  character varying,uuid,bigint,uuid,character varying,character varying
) is 'Canonical audited manual entitlement workflow. FREE baseline entitlements are never reduced or revoked by this path.';

commit;
