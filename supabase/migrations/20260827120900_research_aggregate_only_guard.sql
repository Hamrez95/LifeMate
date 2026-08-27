-- #497: Pseudonymous row-level export is intentionally unavailable until a
-- reviewed unlinkability/pseudonymization design is implemented. Keep the DB
-- fail-closed even if the Admin API boundary is bypassed.

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'ck_dataset_privacy_policies_aggregate_only'
      and conrelid = 'analytics.dataset_privacy_policies'::regclass
  ) then
    alter table analytics.dataset_privacy_policies
      add constraint ck_dataset_privacy_policies_aggregate_only
      check (row_mode = 'Aggregate');
  end if;
end $$;

-- Migration-chain contract assertions. These execute on the disposable
-- PostgreSQL schema gate as well as any reviewed apply, so a later migration
-- cannot silently reopen direct table access or identifier export.
do $$
declare
  v_claim oid := to_regprocedure(
    'analytics.claim_research_export_for_worker(uuid,character varying)'
  );
  v_complete oid := to_regprocedure(
    'analytics.complete_research_export_for_worker(uuid,character varying,character,timestamp with time zone)'
  );
  v_request oid := to_regprocedure(
    'analytics.request_research_export(uuid,uuid,character varying,uuid,character varying)'
  );
begin
  if to_regclass('analytics.dataset_definitions') is null
     or to_regclass('analytics.dataset_privacy_policies') is null
     or to_regclass('analytics.dataset_export_jobs') is null then
    raise exception 'research dataset tables missing';
  end if;

  if not exists (
    select 1 from pg_class c
    join pg_namespace n on n.oid=c.relnamespace
    where n.nspname='analytics'
      and c.relname in ('dataset_definitions','dataset_privacy_policies','dataset_export_jobs')
      and c.relrowsecurity=true
      and c.relforcerowsecurity=true
    group by n.nspname
    having count(*)=3
  ) then
    raise exception 'research dataset RLS/FORCE RLS boundary missing';
  end if;

  if analytics.research_json_contains_direct_identifier(
    '{"personId":"00000000-0000-4000-8000-000000000001"}'::jsonb
  ) is distinct from true then
    raise exception 'research direct-identifier guard failed';
  end if;
  if analytics.research_json_contains_direct_identifier(
    '{"ageBucket":"20-22","productCode":"wellmate"}'::jsonb
  ) is distinct from false then
    raise exception 'research identifier guard rejects reviewed aggregate fields';
  end if;

  if v_claim is null or v_complete is null or v_request is null then
    raise exception 'research export lifecycle functions missing';
  end if;

  if exists(select 1 from pg_roles where rolname='anon') then
    if has_table_privilege('anon','analytics.dataset_definitions','SELECT')
       or has_table_privilege('anon','analytics.dataset_privacy_policies','SELECT')
       or has_table_privilege('anon','analytics.dataset_export_jobs','SELECT')
       or has_function_privilege('anon',v_request,'EXECUTE') then
      raise exception 'anon research access must remain denied';
    end if;
  end if;

  if exists(select 1 from pg_roles where rolname='authenticated') then
    if has_table_privilege('authenticated','analytics.dataset_definitions','SELECT')
       or has_table_privilege('authenticated','analytics.dataset_privacy_policies','SELECT')
       or has_table_privilege('authenticated','analytics.dataset_export_jobs','SELECT')
       or has_function_privilege('authenticated',v_request,'EXECUTE') then
      raise exception 'authenticated research access must remain denied';
    end if;
  end if;

  if exists(select 1 from pg_roles where rolname='lifemate_admin_runtime') then
    if has_table_privilege('lifemate_admin_runtime','analytics.dataset_definitions','SELECT')
       or has_table_privilege('lifemate_admin_runtime','analytics.dataset_privacy_policies','SELECT')
       or has_table_privilege('lifemate_admin_runtime','analytics.dataset_export_jobs','SELECT') then
      raise exception 'admin runtime must use narrow research functions, not tables';
    end if;
    if not has_function_privilege('lifemate_admin_runtime',v_request,'EXECUTE') then
      raise exception 'admin runtime missing reviewed research request capability';
    end if;
    if has_function_privilege('lifemate_admin_runtime',v_claim,'EXECUTE')
       or has_function_privilege('lifemate_admin_runtime',v_complete,'EXECUTE') then
      raise exception 'admin runtime must not execute worker-only research lifecycle';
    end if;
  end if;

  if exists(select 1 from pg_roles where rolname='lifemate_worker_runtime') then
    if not has_function_privilege('lifemate_worker_runtime',v_claim,'EXECUTE')
       or not has_function_privilege('lifemate_worker_runtime',v_complete,'EXECUTE') then
      raise exception 'worker runtime missing research export lifecycle capability';
    end if;
    if has_table_privilege('lifemate_worker_runtime','analytics.dataset_definitions','SELECT')
       or has_table_privilege('lifemate_worker_runtime','analytics.dataset_privacy_policies','SELECT')
       or has_table_privilege('lifemate_worker_runtime','analytics.dataset_export_jobs','SELECT') then
      raise exception 'worker runtime must use narrow research functions, not tables';
    end if;
  end if;
end $$;
