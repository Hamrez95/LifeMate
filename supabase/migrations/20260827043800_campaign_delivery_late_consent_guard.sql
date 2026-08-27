begin;

create or replace function messaging.refresh_campaign_execution_terminal_state(
  p_execution_id uuid
) returns void
language plpgsql
security definer
set search_path=pg_catalog,messaging,pg_temp
as $$
begin
  update messaging.campaign_executions e
  set status=case
      when exists(
        select 1 from messaging.delivery_jobs j
        where j.execution_id=e.id
          and (
            j.status in ('Pending','InFlight')
            or (j.status='Failed' and j.attempt_count<5)
          )
      ) then e.status
      when exists(
        select 1 from messaging.delivery_jobs j
        where j.execution_id=e.id
          and j.status in ('Failed','PermanentFailed','OutcomeUnknown')
      ) then 'Failed'
      else 'Completed'
    end,
    updated_at_utc=now()
  where e.id=p_execution_id and e.status='Sending';
end $$;

revoke all on function messaging.refresh_campaign_execution_terminal_state(uuid)
  from public,anon,authenticated,lifemate_admin_runtime,lifemate_edge_runtime,lifemate_worker_runtime;

create or replace function messaging.resolve_campaign_delivery_job(p_job_id uuid)
returns table(
  job_id uuid,
  account_id uuid,
  channel varchar,
  provider varchar,
  product_code varchar,
  message_title varchar,
  message_body varchar,
  endpoint_hash varchar,
  endpoint_ciphertext_b64 text,
  endpoint_nonce_b64 varchar,
  endpoint_key_version smallint
)
language plpgsql
security definer
set search_path=pg_catalog,messaging,marketing,consent,identity,pg_temp
as $$
declare
  v_job messaging.delivery_jobs%rowtype;
  v_execution messaging.campaign_executions%rowtype;
  v_product varchar(64);
  v_title varchar(160);
  v_body varchar(2000);
  v_purpose varchar(80);
  v_has_endpoint boolean:=false;
begin
  select * into v_job
  from messaging.delivery_jobs
  where id=p_job_id
  for update;
  if not found or v_job.status<>'InFlight' then return; end if;

  select * into v_execution
  from messaging.campaign_executions
  where id=v_job.execution_id
  for share;
  if not found or v_execution.status<>'Sending' then
    update messaging.delivery_jobs
    set status='Cancelled',next_attempt_at_utc=null,updated_at_utc=now()
    where id=v_job.id;
    perform messaging.refresh_campaign_execution_terminal_state(v_job.execution_id);
    return;
  end if;

  v_purpose:=case when v_job.channel='SMS' then 'promotional_sms' else 'promotional_push' end;
  if not consent.account_allows_optional_purpose(v_job.account_id,v_purpose,'GLOBAL') then
    update messaging.delivery_jobs
    set status='Suppressed',suppression_reason='OptedOut',next_attempt_at_utc=null,updated_at_utc=now()
    where id=v_job.id;
    insert into messaging.delivery_events(
      delivery_job_id,event_type,reason_code,occurred_at_utc
    ) values(v_job.id,'Suppressed','late_opt_out',now());
    perform messaging.refresh_campaign_execution_terminal_state(v_job.execution_id);
    return;
  end if;

  if not exists(
    select 1 from identity.accounts a
    where a.id=v_job.account_id and a.status='Active'
  ) then
    update messaging.delivery_jobs
    set status='Suppressed',suppression_reason='InactiveAccount',next_attempt_at_utc=null,updated_at_utc=now()
    where id=v_job.id;
    insert into messaging.delivery_events(
      delivery_job_id,event_type,reason_code,occurred_at_utc
    ) values(v_job.id,'Suppressed','inactive_account',now());
    perform messaging.refresh_campaign_execution_terminal_state(v_job.execution_id);
    return;
  end if;

  select c.product_code into v_product
  from marketing.campaigns c where c.id=v_execution.campaign_id;
  select m.title,m.body into v_title,v_body
  from messaging.campaign_messages m
  where m.id=v_job.message_id and m.status='Active';
  if v_product is null or v_body is null then
    update messaging.delivery_jobs
    set status='PermanentFailed',next_attempt_at_utc=null,updated_at_utc=now()
    where id=v_job.id;
    insert into messaging.delivery_events(
      delivery_job_id,event_type,reason_code,occurred_at_utc
    ) values(v_job.id,'PermanentFailed','message_unavailable',now());
    perform messaging.refresh_campaign_execution_terminal_state(v_job.execution_id);
    return;
  end if;

  if v_job.channel='SMS' then
    select exists(
      select 1 from identity.contact_points cp
      where cp.account_id=v_job.account_id
        and cp.kind='Phone'
        and cp.status='Verified'
        and cp.verified_at_utc is not null
        and cp.encrypted_value is not null
        and cp.encryption_nonce_b64 is not null
        and cp.encryption_key_version is not null
    ) into v_has_endpoint;
    if not v_has_endpoint then
      update messaging.delivery_jobs
      set status='Suppressed',suppression_reason='NoReachableAddress',next_attempt_at_utc=null,updated_at_utc=now()
      where id=v_job.id;
      insert into messaging.delivery_events(
        delivery_job_id,event_type,reason_code,occurred_at_utc
      ) values(v_job.id,'Suppressed','phone_unavailable',now());
      perform messaging.refresh_campaign_execution_terminal_state(v_job.execution_id);
      return;
    end if;

    return query
    select
      v_job.id,v_job.account_id,v_job.channel,v_execution.sms_provider,v_product,
      v_title,v_body,cp.normalized_value_hash,encode(cp.encrypted_value,'base64'),
      cp.encryption_nonce_b64,cp.encryption_key_version
    from identity.contact_points cp
    where cp.account_id=v_job.account_id
      and cp.kind='Phone'
      and cp.status='Verified'
      and cp.verified_at_utc is not null
      and cp.encrypted_value is not null
      and cp.encryption_nonce_b64 is not null
      and cp.encryption_key_version is not null
    order by cp.updated_at_utc desc,cp.id desc
    limit 1;
    return;
  end if;

  if v_job.channel='Push' then
    select exists(
      select 1 from messaging.push_registrations pr
      where pr.account_id=v_job.account_id
        and pr.product_code=v_product
        and pr.status='Active'
    ) into v_has_endpoint;
    if not v_has_endpoint then
      update messaging.delivery_jobs
      set status='Suppressed',suppression_reason='NoReachableAddress',next_attempt_at_utc=null,updated_at_utc=now()
      where id=v_job.id;
      insert into messaging.delivery_events(
        delivery_job_id,event_type,reason_code,occurred_at_utc
      ) values(v_job.id,'Suppressed','push_token_unavailable',now());
      perform messaging.refresh_campaign_execution_terminal_state(v_job.execution_id);
      return;
    end if;

    return query
    select
      v_job.id,v_job.account_id,v_job.channel,pr.provider,v_product,v_title,v_body,
      pr.token_hash,encode(pr.token_ciphertext,'base64'),pr.token_nonce_b64,
      pr.encryption_key_version
    from messaging.push_registrations pr
    where pr.account_id=v_job.account_id
      and pr.product_code=v_product
      and pr.status='Active'
    order by pr.last_seen_at_utc desc,pr.id desc
    limit 1;
    return;
  end if;

  update messaging.delivery_jobs
  set status='PermanentFailed',next_attempt_at_utc=null,updated_at_utc=now()
  where id=v_job.id;
  insert into messaging.delivery_events(
    delivery_job_id,event_type,reason_code,occurred_at_utc
  ) values(v_job.id,'PermanentFailed','channel_invalid',now());
  perform messaging.refresh_campaign_execution_terminal_state(v_job.execution_id);
end $$;

revoke all on function messaging.resolve_campaign_delivery_job(uuid)
  from public,anon,authenticated,lifemate_admin_runtime,lifemate_edge_runtime;
grant execute on function messaging.resolve_campaign_delivery_job(uuid)
  to lifemate_worker_runtime;

create or replace function messaging.schedule_campaign_execution(
  p_actor_account_id uuid,
  p_execution_id uuid,
  p_expected_version bigint,
  p_scheduled_at_utc timestamptz,
  p_correlation_id uuid
) returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,messaging,admin,pg_temp
as $$
declare v_row messaging.campaign_executions%rowtype;
begin
  if not admin.account_has_permission(p_actor_account_id,'marketing.campaign.send') then
    return jsonb_build_object('httpStatus',403,'code','permission_denied','message','The required permission is not granted.');
  end if;
  if p_scheduled_at_utc is null or p_scheduled_at_utc<now()-interval '1 minute'
     or p_scheduled_at_utc>now()+interval '30 days' then
    return jsonb_build_object('httpStatus',400,'code','campaign_schedule_invalid','message','Schedule time is outside the allowed window.');
  end if;
  select * into v_row from messaging.campaign_executions where id=p_execution_id for update;
  if not found then
    return jsonb_build_object('httpStatus',404,'code','campaign_execution_not_found','message','Campaign execution was not found.');
  end if;
  if p_expected_version is null or p_expected_version<>v_row.version then
    return jsonb_build_object('httpStatus',409,'code','campaign_execution_version_conflict','message','Campaign execution changed.');
  end if;
  if v_row.status<>'Prepared' then
    return jsonb_build_object('httpStatus',409,'code','campaign_execution_not_prepared','message','Campaign execution is not prepared for scheduling.');
  end if;
  if v_row.requires_second_confirmation and v_row.confirmed_at_utc is null then
    return jsonb_build_object('httpStatus',409,'code','campaign_confirmation_required','message','Second confirmation is required before scheduling.');
  end if;
  if not exists(
    select 1 from messaging.delivery_jobs j
    where j.execution_id=p_execution_id and j.status='Pending'
  ) then
    return jsonb_build_object('httpStatus',409,'code','campaign_no_eligible_recipients','message','No eligible recipients remain for this campaign.');
  end if;

  update messaging.campaign_executions
  set status='Scheduled',scheduled_at_utc=p_scheduled_at_utc,version=version+1,updated_at_utc=now()
  where id=p_execution_id returning * into v_row;
  insert into admin.audit_events(
    actor_account_id,action,resource_type,resource_id,result,correlation_id,elevated_access,metadata_json
  ) values(
    p_actor_account_id,'marketing.campaign.schedule','campaign_execution',p_execution_id::text,
    'Succeeded',p_correlation_id,false,
    jsonb_build_object('scheduledAtUtc',p_scheduled_at_utc,'version',v_row.version)
  );
  return jsonb_build_object(
    'httpStatus',200,'code','ok','executionId',v_row.id,'status',v_row.status,
    'scheduledAtUtc',v_row.scheduled_at_utc,'version',v_row.version
  );
end $$;

revoke all on function messaging.schedule_campaign_execution(uuid,uuid,bigint,timestamptz,uuid)
  from public,anon,authenticated,lifemate_edge_runtime,lifemate_worker_runtime;
grant execute on function messaging.schedule_campaign_execution(uuid,uuid,bigint,timestamptz,uuid)
  to lifemate_admin_runtime;

comment on function messaging.resolve_campaign_delivery_job(uuid)
is 'Worker-only send-time boundary. Re-checks promotional opt-in, active account and current encrypted endpoint immediately before provider delivery.';
comment on function messaging.refresh_campaign_execution_terminal_state(uuid)
is 'Completes or fails a Sending execution after delivery jobs become terminal, including late opt-out suppression.';

commit;
