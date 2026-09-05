begin;

-- Custom-role mutations need privileged table access, but the Admin runtime receives
-- only EXECUTE on these narrow functions. Keep authorization inside the routines and
-- preserve the browser/runtime least-privilege boundary.
alter function admin.mutate_custom_role(
  uuid, character varying, character varying, character varying, smallint, bigint,
  character varying, uuid, character varying, character varying
) security definer;

alter function admin.mutate_custom_role_permission(
  uuid, character varying, character varying, character varying, bigint,
  character varying, uuid, character varying, character varying
) security definer;

-- Defense in depth for any runtime code path that inserts/reactivates member_roles.
-- The canonical staff mutation already enforces rank; the trigger repeats the same
-- authority boundary so a future server bug cannot bypass it with a direct INSERT.
create or replace function admin.enforce_custom_role_assignment_authority()
returns trigger
language plpgsql
security invoker
set search_path = admin, pg_temp
as $$
declare
  v_role admin.roles%rowtype;
  v_actor_rank smallint;
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
  if not exists (
    select 1 from admin.members m
    where m.account_id=new.account_id and m.status='Active'
  ) then
    raise exception using errcode='42501', message='Target staff membership must be active before assigning a custom role.';
  end if;
  if not admin.account_has_permission(new.granted_by_account_id,'security.staff.manage') then
    raise exception using errcode='42501', message='Granting actor cannot manage staff roles.';
  end if;

  select min(r.rank) into v_actor_rank
  from admin.member_roles mr
  join admin.roles r on r.id=mr.role_id
  where mr.account_id=new.granted_by_account_id
    and r.status='Active'
    and mr.revoked_at_utc is null
    and mr.starts_at_utc<=now()
    and (mr.expires_at_utc is null or mr.expires_at_utc>now());

  if v_actor_rank is null or v_role.rank<=v_actor_rank then
    raise exception using errcode='42501', message='Granting actor cannot assign a custom role at or above their authority.';
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

revoke all on function admin.enforce_custom_role_assignment_authority() from public;
do $$
begin
  if exists (select 1 from pg_roles where rolname='anon') then
    revoke all on function admin.enforce_custom_role_assignment_authority() from anon;
  end if;
  if exists (select 1 from pg_roles where rolname='authenticated') then
    revoke all on function admin.enforce_custom_role_assignment_authority() from authenticated;
  end if;
end;
$$;

comment on function admin.enforce_custom_role_assignment_authority() is
'Blocks custom-role self-assignment, inactive-target assignment, rank escalation, elevated/non-role permission delegation, and delegation beyond the granting actor authority. Revocation remains allowed.';

commit;
