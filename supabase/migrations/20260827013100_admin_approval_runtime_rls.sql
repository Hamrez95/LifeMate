begin;

drop policy if exists lifemate_admin_runtime_select on admin.approval_policies;
create policy lifemate_admin_runtime_select on admin.approval_policies
for select to lifemate_admin_runtime using (true);

drop policy if exists lifemate_admin_runtime_select on admin.approval_policy_approver_roles;
create policy lifemate_admin_runtime_select on admin.approval_policy_approver_roles
for select to lifemate_admin_runtime using (true);

drop policy if exists lifemate_admin_runtime_rw on admin.approval_requests;
create policy lifemate_admin_runtime_rw on admin.approval_requests
for all to lifemate_admin_runtime using (true) with check (true);

drop policy if exists lifemate_admin_runtime_select on admin.approval_events;
create policy lifemate_admin_runtime_select on admin.approval_events
for select to lifemate_admin_runtime using (true);

drop policy if exists lifemate_admin_runtime_insert on admin.approval_events;
create policy lifemate_admin_runtime_insert on admin.approval_events
for insert to lifemate_admin_runtime with check (true);

comment on policy lifemate_admin_runtime_rw on admin.approval_requests is
'Only the restricted server-side Admin API database role can read/write approval workflow state. Browser roles receive no table grants.';

commit;
