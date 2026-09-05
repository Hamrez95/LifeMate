begin;

create or replace function admin.enforce_custom_role_assignment_authority()
returns trigger
language plpgsql
security invoker
set search_path = admin, pg_temp
as $$
declare
  v_role admin.roles%rowtype;
begin
  if new.revoked_at_utc is not null then
    return new;
  end if;

  select * into v_role from admin.roles where id=new.role_id;
  if v_role.id is null or v_role.is_system then
    return new;
  end if;

  if new.granted_by_account_id is null then
    raise exception using errcode='42501', message='Custom role assignments require an explicit granting actor.';
  end if;
  if new.account_id=new.granted_by_account_id then
    raise exception using errcode='42501', message='Staff members cannot assign a custom role to themselves.';
  end if;
  if not admin.account_has_permission(new.granted_by_account_id,'security.staff.manage') then
    raise exception using errcode='42501', message='Granting actor cannot manage staff roles.';
  end if;
  if exists (
    select 1
    from admin.role_permissions rp
    join admin.permissions p on p.code=rp.permission_code
    where rp.role_id=v_role.id
      and (
        not p.role_assignable
        or p.risk_level='ELEVATED'
        or not admin.account_has_permission(new.granted_by_account_id,p.code)
      )
  ) then
    raise exception using errcode='42501', message='Granting actor cannot delegate every permission in this custom role.';
  end if;

  return new;
end;
$$;

drop trigger if exists trg_admin_member_roles_custom_authority on admin.member_roles;
create trigger trg_admin_member_roles_custom_authority
before insert or update of account_id,role_id,granted_by_account_id,revoked_at_utc on admin.member_roles
for each row execute function admin.enforce_custom_role_assignment_authority();

revoke all on function admin.enforce_custom_role_assignment_authority() from public;
do $$
declare
  role_name text;
begin
  foreach role_name in array array['anon','authenticated'] loop
    if exists (select 1 from pg_roles where rolname=role_name) then
      execute format(
        'revoke all on function admin.enforce_custom_role_assignment_authority() from %I',
        role_name
      );
    end if;
  end loop;
end;
$$;

comment on function admin.enforce_custom_role_assignment_authority() is
'Blocks custom-role self-assignment and delegation/reactivation of permissions the granting actor does not hold. Revocation remains allowed. System-role assignment keeps the existing ranked workflow.';

commit;
