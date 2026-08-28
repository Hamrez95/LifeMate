begin;

-- #487 established read-only canonical control-plane tables. #186 extends only
-- the Admin runtime authority required to manage those exact tables; browser
-- roles remain denied and protected capability evaluation stays server-side.
do $$
begin
  if exists(select 1 from pg_roles where rolname='lifemate_admin_runtime') then
    grant select,insert,update on platform.controls to lifemate_admin_runtime;
    grant select,insert,update on platform.control_rules to lifemate_admin_runtime;
    grant select,insert on platform.control_history to lifemate_admin_runtime;
    grant select,insert on platform.control_rule_history to lifemate_admin_runtime;
  end if;
end $$;

drop policy if exists platform_controls_admin_insert on platform.controls;
create policy platform_controls_admin_insert on platform.controls
  for insert to lifemate_admin_runtime with check (true);
drop policy if exists platform_controls_admin_update on platform.controls;
create policy platform_controls_admin_update on platform.controls
  for update to lifemate_admin_runtime using (true) with check (true);

drop policy if exists platform_control_rules_admin_insert on platform.control_rules;
create policy platform_control_rules_admin_insert on platform.control_rules
  for insert to lifemate_admin_runtime with check (true);
drop policy if exists platform_control_rules_admin_update on platform.control_rules;
create policy platform_control_rules_admin_update on platform.control_rules
  for update to lifemate_admin_runtime using (true) with check (true);

drop policy if exists platform_control_history_admin_select on platform.control_history;
create policy platform_control_history_admin_select on platform.control_history
  for select to lifemate_admin_runtime using (true);
drop policy if exists platform_control_history_admin_insert on platform.control_history;
create policy platform_control_history_admin_insert on platform.control_history
  for insert to lifemate_admin_runtime with check (true);

drop policy if exists platform_control_rule_history_admin_select on platform.control_rule_history;
create policy platform_control_rule_history_admin_select on platform.control_rule_history
  for select to lifemate_admin_runtime using (true);
drop policy if exists platform_control_rule_history_admin_insert on platform.control_rule_history;
create policy platform_control_rule_history_admin_insert on platform.control_rule_history
  for insert to lifemate_admin_runtime with check (true);

-- History is append-only to the Admin runtime.
revoke update,delete on platform.control_history from lifemate_admin_runtime;
revoke update,delete on platform.control_rule_history from lifemate_admin_runtime;
-- Control removal is represented by Retired status; physical DELETE is not an
-- Admin capability.
revoke delete on platform.controls from lifemate_admin_runtime;
revoke delete on platform.control_rules from lifemate_admin_runtime;

commit;
