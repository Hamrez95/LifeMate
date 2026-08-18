\set ON_ERROR_STOP on
begin;

do $$
begin
  if not exists(
    select 1 from information_schema.columns
    where table_schema='identity' and table_name='contact_points'
      and column_name='encryption_nonce_b64'
  ) then raise exception 'ContactPoint envelope nonce column missing'; end if;

  if not exists(
    select 1 from information_schema.columns
    where table_schema='identity' and table_name='contact_points'
      and column_name='encryption_key_version'
  ) then raise exception 'ContactPoint envelope key-version column missing'; end if;

  if exists(
    select 1 from information_schema.columns
    where table_schema='identity' and table_name='contact_points'
      and column_name in (
        'email','phone','normalized_value','plaintext_value','encryption_key'
      )
  ) then raise exception 'ContactPoint table gained plaintext contact storage'; end if;

  if not (select c.relrowsecurity and c.relforcerowsecurity
          from pg_class c join pg_namespace n on n.oid=c.relnamespace
          where n.nspname='identity' and c.relname='contact_points') then
    raise exception 'ContactPoint table is not FORCE RLS protected';
  end if;

  if not has_table_privilege(
    'lifemate_edge_runtime','identity.contact_points','SELECT'
  ) or not has_table_privilege(
    'lifemate_edge_runtime','identity.contact_points','INSERT'
  ) or not has_table_privilege(
    'lifemate_edge_runtime','identity.contact_points','UPDATE'
  ) then raise exception 'Edge runtime lacks ContactPoint dual-write boundary'; end if;

  if has_table_privilege(
    'lifemate_edge_runtime','identity.contact_points','DELETE'
  ) or has_table_privilege(
    'lifemate_edge_runtime','identity.contact_points','TRUNCATE'
  ) then raise exception 'Edge runtime can destructively erase ContactPoints'; end if;

  if has_table_privilege(
    'lifemate_worker_runtime','identity.contact_points','SELECT'
  ) or has_table_privilege(
    'lifemate_worker_runtime','identity.contact_points','INSERT'
  ) or has_table_privilege(
    'lifemate_worker_runtime','identity.contact_points','UPDATE'
  ) or has_table_privilege(
    'lifemate_worker_runtime','identity.contact_points','DELETE'
  ) or has_table_privilege(
    'lifemate_worker_runtime','identity.contact_points','TRUNCATE'
  ) then raise exception 'Worker gained direct ContactPoint table access'; end if;

  if not has_function_privilege(
    'lifemate_worker_runtime','identity.finalize_account_deletion(uuid)','EXECUTE'
  ) then raise exception 'Worker lost SECURITY DEFINER account-deletion cleanup'; end if;

  if exists(select 1 from pg_roles where rolname='authenticated') and
     has_table_privilege('authenticated','identity.contact_points','SELECT') then
    raise exception 'Authenticated browser can read ContactPoints';
  end if;
  if exists(select 1 from pg_roles where rolname='anon') and
     has_table_privilege('anon','identity.contact_points','SELECT') then
    raise exception 'Anon browser can read ContactPoints';
  end if;
  if exists(select 1 from pg_roles where rolname='service_role') and
     has_table_privilege('service_role','identity.contact_points','SELECT') then
    raise exception 'Supabase service_role can directly read ContactPoints';
  end if;

  if not exists(
    select 1 from pg_indexes
    where schemaname='identity'
      and tablename='contact_points'
      and indexname='uq_contact_points_current_kind_hash'
      and indexdef ilike '%where%status%Revoked%'
  ) then raise exception 'Current-contact global partial uniqueness index missing'; end if;

  if not exists(
    select 1 from pg_indexes
    where schemaname='identity'
      and tablename='contact_points'
      and indexname='uq_contact_points_current_account_kind'
      and indexdef ilike '%where%status%Revoked%'
  ) then raise exception 'Single current ContactPoint per Account/kind index missing'; end if;
end $$;

-- A revoked historical hash must not permanently lock a legitimately moved
-- email/phone to the previous Account.
insert into identity.accounts(id,status,created_at_utc,updated_at_utc) values
('93000000-0000-4000-8000-000000000001','Active',now(),now()),
('93000000-0000-4000-8000-000000000002','Active',now(),now());

insert into identity.contact_points(
  account_id,kind,normalized_value_hash,status,created_at_utc,updated_at_utc
) values(
  '93000000-0000-4000-8000-000000000001','Phone',
  repeat('a',64),'Pending',now(),now()
);

update identity.contact_points
set status='Revoked',updated_at_utc=now()
where account_id='93000000-0000-4000-8000-000000000001'
  and kind='Phone';

insert into identity.contact_points(
  account_id,kind,normalized_value_hash,status,created_at_utc,updated_at_utc
) values(
  '93000000-0000-4000-8000-000000000002','Phone',
  repeat('a',64),'Pending',now(),now()
);

do $$
begin
  if (select count(*) from identity.contact_points
      where kind='Phone' and normalized_value_hash=repeat('a',64)) <> 2 then
    raise exception 'Revoked ContactPoint hash could not be safely reused';
  end if;
  if (select count(*) from identity.contact_points
      where kind='Phone' and normalized_value_hash=repeat('a',64)
        and status <> 'Revoked') <> 1 then
    raise exception 'Current ContactPoint global uniqueness is not enforced';
  end if;
end $$;

rollback;
