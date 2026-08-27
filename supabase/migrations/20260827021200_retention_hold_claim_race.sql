begin;

create or replace function security.create_retention_hold(
  p_actor_account_id uuid,
  p_account_id uuid,
  p_data_category character varying,
  p_purpose_code character varying,
  p_reason_code character varying,
  p_reason character varying,
  p_expires_at_utc timestamptz,
  p_correlation_id uuid
) returns jsonb
language plpgsql
set search_path=security,admin,identity,integration,pg_temp
as $$
declare
  v_id uuid;
  v_processing boolean;
begin
  if not admin.account_has_permission(p_actor_account_id,'security.retention.write') then
    return jsonb_build_object('httpStatus',403,'code','retention_permission_denied','message','Actor cannot create preservation holds.');
  end if;
  if p_reason is null or length(trim(p_reason))<10 or length(trim(p_reason))>1000
     or p_reason_code is null or p_reason_code !~ '^[a-z][a-z0-9._-]{2,79}$' then
    return jsonb_build_object('httpStatus',400,'code','retention_hold_reason_invalid','message','A valid reason code and bounded reason are required.');
  end if;
  if p_expires_at_utc is not null and p_expires_at_utc<=now() then
    return jsonb_build_object('httpStatus',400,'code','retention_hold_expiry_invalid','message','Hold expiry must be in the future.');
  end if;

  -- Serialize hold placement against account deletion state and unclaimed
  -- deletion messages. If a worker has already claimed the destructive message,
  -- fail instead of presenting a hold that cannot be guaranteed.
  perform 1 from identity.accounts where id=p_account_id for update;
  if not found then
    return jsonb_build_object('httpStatus',404,'code','retention_account_not_found','message','Account was not found.');
  end if;

  perform 1 from identity.account_deletion_requests
  where account_id=p_account_id and status in ('Requested','Processing')
  for update;

  perform 1 from integration.outbox_messages
  where aggregate_id=p_account_id
    and event_type='identity.account_deletion_requested'
    and status in ('Pending','Failed','Processing')
  for update;

  select exists(
    select 1 from integration.outbox_messages
    where aggregate_id=p_account_id
      and event_type='identity.account_deletion_requested'
      and status='Processing'
  ) into v_processing;
  if v_processing then
    return jsonb_build_object('httpStatus',409,'code','retention_deletion_in_progress','message','Deletion is already being processed; a preservation hold cannot be guaranteed.');
  end if;

  insert into security.retention_holds(
    account_id,data_category,purpose_code,reason_code,reason,status,expires_at_utc,created_by_account_id
  ) values(
    p_account_id,
    nullif(lower(trim(coalesce(p_data_category,''))),''),
    nullif(lower(trim(coalesce(p_purpose_code,''))),''),
    lower(trim(p_reason_code)),trim(p_reason),'Active',p_expires_at_utc,p_actor_account_id
  ) returning id into v_id;

  perform security.refresh_account_deletion_outbox(p_account_id);

  insert into admin.audit_events(actor_account_id,action,resource_type,resource_id,result,reason,correlation_id,elevated_access,metadata_json)
  values(
    p_actor_account_id,'security.retention.hold.create','retention_hold',v_id::text,'Succeeded',trim(p_reason),p_correlation_id,true,
    jsonb_build_object('accountId',p_account_id,'reasonCode',lower(trim(p_reason_code)))
  );
  return jsonb_build_object('httpStatus',201,'code','ok','id',v_id);
end $$;

revoke all on function security.create_retention_hold(uuid,uuid,character varying,character varying,character varying,character varying,timestamptz,uuid) from public;
grant execute on function security.create_retention_hold(uuid,uuid,character varying,character varying,character varying,character varying,timestamptz,uuid) to lifemate_admin_runtime;

commit;
