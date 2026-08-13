\set ON_ERROR_STOP on
begin;

insert into identity.accounts(id,status,created_at_utc,updated_at_utc) values
('91000000-0000-4000-8000-000000000001','Active',now(),now()),
('91000000-0000-4000-8000-000000000002','Active',now(),now());

insert into admin.members(account_id,status,created_by_account_id) values
('91000000-0000-4000-8000-000000000001','Active','91000000-0000-4000-8000-000000000001'),
('91000000-0000-4000-8000-000000000002','Active','91000000-0000-4000-8000-000000000002');

insert into admin.member_roles(account_id,role_id,granted_by_account_id)
select '91000000-0000-4000-8000-000000000001', id,
       '91000000-0000-4000-8000-000000000001'
from admin.roles where code='support';

insert into admin.member_roles(account_id,role_id,granted_by_account_id)
select '91000000-0000-4000-8000-000000000002', id,
       '91000000-0000-4000-8000-000000000002'
from admin.roles where code='founder';

do $$
begin
  if not admin.account_has_permission(
    '91000000-0000-4000-8000-000000000001','support.write'
  ) then raise exception 'Support lost support.write'; end if;

  if admin.account_has_permission(
    '91000000-0000-4000-8000-000000000001','finance.read'
  ) then raise exception 'Support obtained Finance access'; end if;

  if admin.account_has_permission(
    '91000000-0000-4000-8000-000000000001','security.roles.write'
  ) then raise exception 'Support obtained role administration'; end if;

  if admin.account_has_permission(
    '91000000-0000-4000-8000-000000000002','health.read.elevated'
  ) then raise exception 'Founder role bypassed break-glass health access'; end if;

  if admin.account_has_permission(
    '91000000-0000-4000-8000-000000000002','women_health.read.elevated'
  ) then raise exception 'Founder role bypassed highly-sensitive break-glass access'; end if;

  if (select rolbypassrls or rolsuper or rolcreaterole or rolcreatedb
      from pg_roles where rolname='lifemate_admin_runtime') then
    raise exception 'Admin runtime role regained privileged database attributes';
  end if;

  if has_schema_privilege('lifemate_admin_runtime','lifemate','USAGE') then
    raise exception 'Admin runtime obtained compatibility health schema access';
  end if;

  if has_table_privilege('lifemate_admin_runtime','lifemate.medications','SELECT') then
    raise exception 'Admin runtime can directly read medication rows';
  end if;

  if not has_table_privilege('lifemate_admin_runtime','admin.audit_events','SELECT')
     or not has_table_privilege('lifemate_admin_runtime','admin.audit_events','INSERT') then
    raise exception 'Admin runtime cannot append/read audit evidence';
  end if;

  if has_table_privilege('lifemate_admin_runtime','admin.audit_events','UPDATE')
     or has_table_privilege('lifemate_admin_runtime','admin.audit_events','DELETE')
     or has_table_privilege('lifemate_admin_runtime','admin.audit_events','TRUNCATE') then
    raise exception 'Admin runtime can mutate or erase audit history';
  end if;

  if not has_table_privilege('lifemate_admin_runtime','admin.user_directory_v1','SELECT') then
    raise exception 'Admin runtime cannot read approved user directory view';
  end if;

  if not exists (
    select 1 from pg_policies
    where schemaname='identity' and tablename='accounts'
      and policyname='lifemate_admin_runtime_select'
      and 'lifemate_admin_runtime'=any(roles)
  ) then raise exception 'Admin runtime lacks identity account RLS read path'; end if;

  if exists (
    select 1 from pg_policies
    where schemaname='identity' and tablename='contact_points'
      and 'lifemate_admin_runtime'=any(roles)
  ) then raise exception 'Admin runtime gained contact-point RLS access'; end if;

  if not (select relrowsecurity and relforcerowsecurity
          from pg_class c join pg_namespace n on n.oid=c.relnamespace
          where n.nspname='admin' and c.relname='audit_events') then
    raise exception 'Admin audit table is not FORCE RLS protected';
  end if;
end $$;

rollback;
