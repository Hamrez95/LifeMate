\set ON_ERROR_STOP on
begin;

insert into lifemate.app_users(id,auth_subject,status,created_at_utc,updated_at_utc)
values(
  '51000000-0000-0000-0000-000000000001',
  'runtime-contract-subject',
  'Active',now(),now()
);

insert into lifemate.user_profiles(
  id,user_id,display_name,phone_number,email,locale,time_zone,created_at_utc,updated_at_utc)
values(
  '51100000-0000-0000-0000-000000000001',
  '51000000-0000-0000-0000-000000000001',
  'Runtime Contract','+989121234567','runtime@example.invalid','fa','Asia/Tehran',now(),now()
);

select care.rebuild_daily_adherence_summary(
  '51000000-0000-0000-0000-000000000001',current_date
);

do $$
begin
  if not exists(
    select 1 from care.daily_adherence_summary
    where person_id='51000000-0000-0000-0000-000000000001'
      and summary_date=current_date
      and scheduled_count=0
      and taken_count=0
      and missed_count=0
      and late_count=0
  ) then
    raise exception 'empty adherence projection was not rebuilt';
  end if;
end $$;

insert into integration.outbox_messages(
  id,aggregate_type,aggregate_id,event_type,idempotency_key,payload_json,status,available_at_utc
) values(
  '52000000-0000-0000-0000-000000000001',
  'contract','51000000-0000-0000-0000-000000000001','contract.runtime',
  'contract-runtime-outbox','{}'::jsonb,'Pending',now()
);

select * from integration.claim_outbox_messages_for_events(
  'runtime-contract-worker',10,array['contract.runtime']::character varying[]
);

do $$
begin
  if not exists(
    select 1 from integration.outbox_messages
    where id='52000000-0000-0000-0000-000000000001'
      and status='Processing'
      and locked_by='runtime-contract-worker'
      and attempt_count=1
  ) then
    raise exception 'outbox claim failed';
  end if;
end $$;

select integration.complete_outbox_message(
  '52000000-0000-0000-0000-000000000001','runtime-contract-worker'
);

do $$
begin
  if not exists(
    select 1 from integration.outbox_messages
    where id='52000000-0000-0000-0000-000000000001'
      and status='Processed'
      and processed_at_utc is not null
      and locked_by is null
  ) then
    raise exception 'outbox completion failed';
  end if;
end $$;

select identity.request_account_deletion(
  '51000000-0000-0000-0000-000000000001'
) as deletion_request_id \gset

select identity.finalize_account_deletion(:'deletion_request_id'::uuid);

do $$
begin
  if not exists(
    select 1 from identity.accounts
    where id='51000000-0000-0000-0000-000000000001' and status='Deleted'
  ) then
    raise exception 'account deletion finalization failed';
  end if;

  if exists(
    select 1 from lifemate.user_profiles
    where user_id='51000000-0000-0000-0000-000000000001'
      and (phone_number is not null or email is not null or profile_photo_path is not null)
  ) then
    raise exception 'legacy contact/profile identifiers survived deletion finalization';
  end if;

  if exists(
    select 1 from identity.external_identities
    where account_id='51000000-0000-0000-0000-000000000001'
  ) then
    raise exception 'external identities survived deletion finalization';
  end if;
end $$;

rollback;
