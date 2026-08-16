begin;

create or replace function marketing.claim_campaign_publish_execution(p_execution_id uuid)
returns table(
  execution_id uuid,
  campaign_id uuid,
  provider_code varchar,
  publish_text varchar,
  asset_refs jsonb,
  credential_secret_name varchar
)
language plpgsql
security definer
set search_path = marketing, admin, pg_temp
as $$
declare
  v_execution marketing.campaign_publish_executions%rowtype;
  v_campaign marketing.campaigns%rowtype;
  v_content marketing.campaign_content%rowtype;
  v_secret_name varchar;
  v_failure varchar;
begin
  select * into v_execution
  from marketing.campaign_publish_executions
  where id=p_execution_id
  for update;

  if not found then return; end if;

  -- A second claim of an execution already marked Processing means the previous
  -- worker may have crossed the external side-effect boundary before crashing.
  -- Never call the provider again automatically. Preserve the ambiguity for a
  -- human operator instead of risking a duplicate social post.
  if v_execution.status = 'Processing' then
    update marketing.campaign_publish_executions
       set status='OutcomeUnknown',
           failure_code='previous_attempt_outcome_unknown',
           completed_at_utc=now()
     where id=p_execution_id;
    insert into marketing.campaign_publish_execution_events(execution_id,event_type,code)
    values(p_execution_id,'OutcomeUnknown','previous_attempt_outcome_unknown');
    return;
  end if;

  if v_execution.status <> 'Queued' then return; end if;

  select * into v_campaign
  from marketing.campaigns
  where id=v_execution.campaign_id;

  select * into v_content
  from marketing.campaign_content
  where campaign_id=v_execution.campaign_id;

  select credential_secret_name into v_secret_name
  from marketing.channel_connections
  where provider_code=v_execution.provider_code
    and operator_status='Enabled';

  if v_campaign.status not in ('Ready','Active') then
    v_failure := 'campaign_not_publishable';
  elsif v_content.approval_state <> 'Approved'
     or v_content.approved_revision is distinct from v_execution.content_revision
     or v_content.content_revision is distinct from v_execution.content_revision then
    v_failure := 'approval_changed';
  elsif v_secret_name is null
     or not admin.marketing_channel_credential_available(v_execution.provider_code) then
    v_failure := 'provider_not_configured';
  end if;

  if v_failure is not null then
    update marketing.campaign_publish_executions
       set status='Failed',completed_at_utc=now(),failure_code=v_failure
     where id=p_execution_id;
    insert into marketing.campaign_publish_execution_events(execution_id,event_type,code)
    values(p_execution_id,'Failed',v_failure);
    return;
  end if;

  update marketing.campaign_publish_executions
     set status='Processing',started_at_utc=now(),failure_code=null
   where id=p_execution_id;
  insert into marketing.campaign_publish_execution_events(execution_id,event_type)
  values(p_execution_id,'Processing');

  return query
  select v_execution.id,v_execution.campaign_id,v_execution.provider_code,
         v_content.publish_text,v_content.asset_refs,v_secret_name;
end
$$;

revoke all on function marketing.claim_campaign_publish_execution(uuid) from public;
grant execute on function marketing.claim_campaign_publish_execution(uuid) to lifemate_worker_runtime;

commit;
