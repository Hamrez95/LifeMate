-- Supabase-specific production worker scheduler.
--
-- This is intentionally outside the portable business-schema migration chain:
-- it depends on hosted Supabase pg_cron, pg_net, Vault, and the production Edge
-- Function URL. The scheduler credential is generated inside PostgreSQL, stored
-- only in Vault, and verified by a narrow SECURITY DEFINER function; plaintext
-- credentials are never committed to source or returned to the Edge runtime.

create extension if not exists pg_net;
create extension if not exists pg_cron with schema pg_catalog;

do $infrastructure$
begin
  if not exists (
    select 1 from vault.secrets
    where name = 'lifemate_worker_scheduler_token'
  ) then
    perform vault.create_secret(
      encode(extensions.gen_random_bytes(32), 'hex'),
      'lifemate_worker_scheduler_token',
      'LifeMate pg_cron to lifemate-worker credential',
      null
    );
  end if;
end
$infrastructure$;

create or replace function integration.verify_worker_scheduler_token(
  p_candidate text
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, vault, extensions, pg_temp
as $function$
  select coalesce(
    length(p_candidate) between 32 and 256
    and extensions.digest(p_candidate, 'sha256') = extensions.digest(
      (
        select decrypted_secret
        from vault.decrypted_secrets
        where name = 'lifemate_worker_scheduler_token'
        limit 1
      ),
      'sha256'
    ),
    false
  )
$function$;

revoke all on function integration.verify_worker_scheduler_token(text) from public;
revoke all on function integration.verify_worker_scheduler_token(text) from anon, authenticated;
grant execute on function integration.verify_worker_scheduler_token(text)
  to lifemate_worker_runtime;

-- One-minute cadence keeps healthy queue lag below the existing 120-second
-- warning threshold. Reusing the same job name makes this infrastructure script
-- idempotent: pg_cron replaces the existing definition rather than duplicating
-- worker invocations.
select cron.schedule(
  'lifemate-outbox-worker',
  '* * * * *',
  $cron$
    select net.http_post(
      url := 'https://bwdvmniywyyijjauipnh.supabase.co/functions/v1/lifemate-worker',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'x-lifemate-worker-token',
        (
          select decrypted_secret
          from vault.decrypted_secrets
          where name = 'lifemate_worker_scheduler_token'
          limit 1
        )
      ),
      body := '{}'::jsonb,
      timeout_milliseconds := 20000
    ) as request_id;
  $cron$
);
