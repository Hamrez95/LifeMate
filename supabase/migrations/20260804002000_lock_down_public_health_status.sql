-- Security hardening for a legacy/public diagnostic table reported by the
-- Supabase security advisor. LifeMate runtime code does not read this table.
-- Keep it fail-closed for client roles without coupling the migration to
-- environments where the table was never created.

do $$
begin
  if to_regclass('public.health_status') is not null then
    execute 'alter table public.health_status enable row level security';
    execute 'revoke all privileges on table public.health_status from anon, authenticated';
    execute 'drop policy if exists health_status_deny_client_access on public.health_status';
    execute $policy$
      create policy health_status_deny_client_access
      on public.health_status
      as restrictive
      for all
      to anon, authenticated
      using (false)
      with check (false)
    $policy$;
    execute $comment$
      comment on policy health_status_deny_client_access on public.health_status is
      'LifeMate client roles must never access legacy diagnostic state.'
    $comment$;
  end if;
end
$$;

-- Rollback plan (manual and reviewed; do not apply automatically):
-- drop policy if exists health_status_deny_client_access on public.health_status;
-- Restore only the minimum grants required by an explicitly documented owner.
