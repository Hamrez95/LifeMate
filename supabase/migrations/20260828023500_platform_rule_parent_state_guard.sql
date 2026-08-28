begin;

-- Keep control/rule lifecycle coherent under concurrent Admin mutations.
-- A rule may be disabled/retired after its parent is retired, but a new or
-- re-activated rule must never become Active beneath a retired control.
create or replace function platform.enforce_active_rule_parent()
returns trigger
language plpgsql
security invoker
set search_path = pg_catalog, platform
as $$
declare
  v_parent_status varchar(16);
begin
  if new.status <> 'Active' then
    return new;
  end if;

  select c.status
  into v_parent_status
  from platform.controls c
  where c.control_key = new.control_key
  for update;

  if v_parent_status is null then
    raise exception 'platform_control_not_found' using errcode='P0002';
  end if;

  if v_parent_status <> 'Active' then
    raise exception 'platform_control_inactive' using errcode='23514';
  end if;

  return new;
end;
$$;

drop trigger if exists trg_platform_control_rules_active_parent on platform.control_rules;
create trigger trg_platform_control_rules_active_parent
before insert or update of status, control_key
on platform.control_rules
for each row
execute function platform.enforce_active_rule_parent();

commit;
