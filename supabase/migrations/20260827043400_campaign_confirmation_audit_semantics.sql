begin;

-- Campaign second-confirmation is a high-risk commercial approval, not an
-- elevated/break-glass healthcare access. Keep the shared audit semantic clean
-- so Security/Access reports do not misclassify campaign approvals.
create or replace function messaging.confirm_campaign_execution(
  p_actor_account_id uuid,
  p_execution_id uuid,
  p_expected_version bigint,
  p_correlation_id uuid
) returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,messaging,admin,extensions,pg_temp
as $$
declare v_row messaging.campaign_executions%rowtype;
begin
  if not admin.account_has_permission(p_actor_account_id,'marketing.campaign.send') then
    return jsonb_build_object('httpStatus',403,'code','permission_denied','message','The required permission is not granted.');
  end if;
  select * into v_row from messaging.campaign_executions where id=p_execution_id for update;
  if not found then return jsonb_build_object('httpStatus',404,'code','campaign_execution_not_found','message','Campaign execution was not found.'); end if;
  if p_expected_version is null or p_expected_version<>v_row.version then
    return jsonb_build_object('httpStatus',409,'code','campaign_execution_version_conflict','message','Campaign execution changed.');
  end if;
  if not v_row.requires_second_confirmation or v_row.status<>'ApprovalPending' then
    return jsonb_build_object('httpStatus',409,'code','campaign_confirmation_not_required','message','This execution is not awaiting confirmation.');
  end if;
  if v_row.created_by_account_id=p_actor_account_id then
    return jsonb_build_object('httpStatus',409,'code','campaign_self_confirmation_denied','message','A second actor must confirm this execution.');
  end if;
  update messaging.campaign_executions
  set status='Prepared',confirmed_by_account_id=p_actor_account_id,confirmed_at_utc=now(),version=version+1,updated_at_utc=now()
  where id=p_execution_id returning * into v_row;
  insert into admin.audit_events(actor_account_id,action,resource_type,resource_id,result,correlation_id,elevated_access,metadata_json)
  values(p_actor_account_id,'marketing.campaign.confirm','campaign_execution',p_execution_id::text,'Succeeded',p_correlation_id,false,
    jsonb_build_object('version',v_row.version,'creatorAccountIdHash',encode(extensions.digest(v_row.created_by_account_id::text,'sha256'),'hex')));
  return jsonb_build_object('httpStatus',200,'code','ok','executionId',v_row.id,'status',v_row.status,'version',v_row.version);
end $$;

revoke all on function messaging.confirm_campaign_execution(uuid,uuid,bigint,uuid) from public;
grant execute on function messaging.confirm_campaign_execution(uuid,uuid,bigint,uuid) to lifemate_admin_runtime;

commit;
