\set ON_ERROR_STOP on
begin;

insert into identity.accounts(id,status,created_at_utc,updated_at_utc) values
('91000000-0000-4000-8000-000000000001','Active',now(),now()),
('91000000-0000-4000-8000-000000000002','Active',now(),now()),
('91000000-0000-4000-8000-000000000003','Active',now(),now());

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

  if not has_schema_privilege('lifemate_admin_runtime','support','USAGE') then
    raise exception 'Admin runtime cannot resolve the support metadata schema';
  end if;

  if not has_table_privilege('lifemate_admin_runtime','support.tickets','SELECT')
     or not has_table_privilege('lifemate_admin_runtime','admin.support_ticket_queue_v1','SELECT') then
    raise exception 'Admin runtime cannot read the approved support queue boundary';
  end if;

  if has_table_privilege('lifemate_admin_runtime','support.tickets','INSERT')
     or has_table_privilege('lifemate_admin_runtime','support.tickets','UPDATE')
     or has_table_privilege('lifemate_admin_runtime','support.tickets','DELETE')
     or has_table_privilege('lifemate_admin_runtime','support.tickets','TRUNCATE') then
    raise exception 'Admin runtime can mutate support queue metadata directly';
  end if;

  if exists (select 1 from pg_roles where rolname='authenticated') and has_table_privilege(
    'authenticated','admin.support_ticket_queue_v1','SELECT'
  ) then raise exception 'Browser authenticated role can read the support queue'; end if;

  if has_table_privilege('lifemate_admin_runtime','identity.accounts','UPDATE') then
    raise exception 'Admin runtime gained direct identity account UPDATE privilege';
  end if;

  if not has_table_privilege(
    'lifemate_admin_runtime','identity.external_identity_tokens','SELECT'
  ) then raise exception 'Admin runtime cannot read canonical identity tokens'; end if;

  if has_table_privilege('lifemate_admin_runtime','identity.external_identity_tokens','INSERT')
     or has_table_privilege('lifemate_admin_runtime','identity.external_identity_tokens','UPDATE')
     or has_table_privilege('lifemate_admin_runtime','identity.external_identity_tokens','DELETE')
     or has_table_privilege('lifemate_admin_runtime','identity.external_identity_tokens','TRUNCATE') then
    raise exception 'Admin runtime can mutate canonical identity tokens';
  end if;

  if not exists (
    select 1 from pg_policies
    where schemaname='identity' and tablename='external_identity_tokens'
      and policyname='lifemate_admin_runtime_select'
      and 'lifemate_admin_runtime'=any(roles)
  ) then raise exception 'Admin runtime lacks token RLS read path'; end if;

  if exists (select 1 from pg_roles where rolname='authenticated')
     and has_table_privilege(
       'authenticated','identity.external_identity_tokens','SELECT'
     ) then raise exception 'Browser authenticated role can read identity tokens'; end if;

  if not has_function_privilege(
    'lifemate_admin_runtime',
    'admin.execute_user_account_action(uuid,uuid,character varying,character varying,uuid,character varying,character varying)',
    'EXECUTE'
  ) then raise exception 'Admin runtime cannot execute the narrow user action boundary'; end if;

  if exists (select 1 from pg_roles where rolname='authenticated') and has_function_privilege(
    'authenticated',
    'admin.execute_user_account_action(uuid,uuid,character varying,character varying,uuid,character varying,character varying)',
    'EXECUTE'
  ) then raise exception 'Browser authenticated role can execute admin user actions'; end if;

  if not exists (
    select 1 from pg_policies
    where schemaname='identity' and tablename='accounts'
      and policyname='lifemate_admin_runtime_select'
      and 'lifemate_admin_runtime'=any(roles)
  ) then raise exception 'Admin runtime lacks identity account RLS read path'; end if;

  if not exists (
    select 1 from pg_policies
    where schemaname='support' and tablename='tickets'
      and policyname='lifemate_admin_runtime_select'
      and 'lifemate_admin_runtime'=any(roles)
  ) then raise exception 'Admin runtime lacks support ticket RLS read path'; end if;

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

  if not (select relrowsecurity and relforcerowsecurity
          from pg_class c join pg_namespace n on n.oid=c.relnamespace
          where n.nspname='support' and c.relname='tickets') then
    raise exception 'Support ticket metadata is not FORCE RLS protected';
  end if;

  if not has_function_privilege(
    'lifemate_admin_runtime',
    'admin.mutate_staff_membership(uuid,uuid,character varying,character varying,uuid,character varying,character varying)',
    'EXECUTE'
  ) or not has_function_privilege(
    'lifemate_admin_runtime',
    'admin.mutate_staff_role(uuid,uuid,character varying,character varying,character varying,uuid,character varying,character varying)',
    'EXECUTE'
  ) then raise exception 'Admin runtime cannot use the narrow staff mutation boundary'; end if;

  if exists (select 1 from pg_roles where rolname='authenticated') and (
    has_function_privilege(
      'authenticated',
      'admin.mutate_staff_membership(uuid,uuid,character varying,character varying,uuid,character varying,character varying)',
      'EXECUTE'
    ) or has_function_privilege(
      'authenticated',
      'admin.mutate_staff_role(uuid,uuid,character varying,character varying,character varying,uuid,character varying,character varying)',
      'EXECUTE'
    )
  ) then raise exception 'Browser authenticated role can execute staff mutations'; end if;

  if has_table_privilege('lifemate_admin_runtime','commerce.trial_policies','SELECT')
     or has_table_privilege('lifemate_admin_runtime','commerce.trial_policies','INSERT')
     or has_table_privilege('lifemate_admin_runtime','commerce.trial_policies','UPDATE') then
    raise exception 'Admin runtime can directly access trial policy storage';
  end if;

  if not has_function_privilege(
    'lifemate_admin_runtime',
    'admin.configure_commerce_trial_policy(uuid,uuid,smallint,character varying,character varying,integer,character varying,uuid,character varying,character varying)',
    'EXECUTE'
  ) then raise exception 'Admin runtime cannot execute the narrow trial policy boundary'; end if;

  if exists (select 1 from pg_roles where rolname='authenticated') and has_function_privilege(
    'authenticated',
    'admin.configure_commerce_trial_policy(uuid,uuid,smallint,character varying,character varying,integer,character varying,uuid,character varying,character varying)',
    'EXECUTE'
  ) then raise exception 'Browser authenticated role can execute trial policy mutation'; end if;

  if (admin.mutate_staff_membership(
    '91000000-0000-4000-8000-000000000002',
    '91000000-0000-4000-8000-000000000003',
    'activate','Founder approved staff onboarding.','91000000-0000-4000-8000-000000000003',
    'staff-contract-activation-001','aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
  )->>'httpStatus')::integer <> 201 then raise exception 'Founder cannot activate staff through canonical mutation'; end if;

  if (admin.mutate_staff_role(
    '91000000-0000-4000-8000-000000000002',
    '91000000-0000-4000-8000-000000000003','support','assign',
    'Founder approved role assignment.','91000000-0000-4000-8000-000000000003',
    'staff-contract-role-001','bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'
  )->>'httpStatus')::integer <> 200 then raise exception 'Founder cannot assign ordinary role through canonical mutation'; end if;

  if (admin.mutate_staff_role(
    '91000000-0000-4000-8000-000000000002',
    '91000000-0000-4000-8000-000000000003','founder','assign',
    'Attempt to mutate protected Founder role.','91000000-0000-4000-8000-000000000003',
    'staff-contract-founder-001','cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc'
  )->>'code') <> 'privileged_role_immutable' then raise exception 'Founder role mutation did not fail closed'; end if;

  if (admin.mutate_staff_role(
    '91000000-0000-4000-8000-000000000002',
    '91000000-0000-4000-8000-000000000003','support','assign',
    'Founder approved role assignment.','91000000-0000-4000-8000-000000000003',
    'staff-contract-role-001','bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'
  )->>'replayed')::boolean is not true then raise exception 'Staff mutation replay was not deterministic'; end if;

  if (admin.mutate_staff_role(
    '91000000-0000-4000-8000-000000000002',
    '91000000-0000-4000-8000-000000000003','support','assign',
    'A different reason must conflict.','91000000-0000-4000-8000-000000000003',
    'staff-contract-role-001','dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd'
  )->>'code') <> 'idempotency_conflict' then raise exception 'Staff mutation idempotency mismatch did not conflict'; end if;
end $$;

rollback;
