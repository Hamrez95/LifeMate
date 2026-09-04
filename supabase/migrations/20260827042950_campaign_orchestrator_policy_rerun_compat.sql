-- Compatibility guard for the historical campaign orchestrator foundation migration.
-- Fresh databases reach this before the messaging tables exist, so it is a no-op.
-- During canonical reruns, remove only policies recreated by the following migration.

do $$
begin
  if to_regclass('messaging.push_registrations') is not null then
    execute 'drop policy if exists messaging_admin_read_push on messaging.push_registrations';
    execute 'drop policy if exists messaging_worker_rw_push on messaging.push_registrations';
  end if;

  if to_regclass('messaging.provider_pricing') is not null then
    execute 'drop policy if exists messaging_admin_rw_pricing on messaging.provider_pricing';
  end if;

  if to_regclass('messaging.campaign_messages') is not null then
    execute 'drop policy if exists messaging_admin_rw_messages on messaging.campaign_messages';
  end if;

  if to_regclass('messaging.campaign_policies') is not null then
    execute 'drop policy if exists messaging_admin_rw_policies on messaging.campaign_policies';
  end if;

  if to_regclass('messaging.campaign_executions') is not null then
    execute 'drop policy if exists messaging_admin_rw_executions on messaging.campaign_executions';
  end if;

  if to_regclass('messaging.delivery_jobs') is not null then
    execute 'drop policy if exists messaging_admin_read_jobs on messaging.delivery_jobs';
    execute 'drop policy if exists messaging_worker_rw_jobs on messaging.delivery_jobs';
  end if;

  if to_regclass('messaging.delivery_events') is not null then
    execute 'drop policy if exists messaging_admin_read_events on messaging.delivery_events';
    execute 'drop policy if exists messaging_worker_insert_events on messaging.delivery_events';
  end if;
end
$$;
