begin;

-- Command Center may inspect Circle structure for support/operations, but never
-- raw planning events, audit metadata, contact hashes, or health content.
grant select on table network.circles to lifemate_admin_runtime;
grant select on table network.circle_members to lifemate_admin_runtime;
grant select on table network.circle_invitations to lifemate_admin_runtime;
grant select on table network.circle_member_sharing_policies to lifemate_admin_runtime;

drop policy if exists circles_admin_structure_read on network.circles;
create policy circles_admin_structure_read
  on network.circles
  for select
  to lifemate_admin_runtime
  using (true);

drop policy if exists circle_members_admin_structure_read on network.circle_members;
create policy circle_members_admin_structure_read
  on network.circle_members
  for select
  to lifemate_admin_runtime
  using (true);

drop policy if exists circle_invitations_admin_structure_read on network.circle_invitations;
create policy circle_invitations_admin_structure_read
  on network.circle_invitations
  for select
  to lifemate_admin_runtime
  using (true);

drop policy if exists circle_sharing_admin_structure_read on network.circle_member_sharing_policies;
create policy circle_sharing_admin_structure_read
  on network.circle_member_sharing_policies
  for select
  to lifemate_admin_runtime
  using (true);

comment on policy circles_admin_structure_read on network.circles is
  'Admin structural support read only. Circle membership is not authorization.';
comment on policy circle_members_admin_structure_read on network.circle_members is
  'Admin structural support read only; no health-data access is implied.';
comment on policy circle_invitations_admin_structure_read on network.circle_invitations is
  'Admin structural support read only. API must not expose invitee_contact_hash.';
comment on policy circle_sharing_admin_structure_read on network.circle_member_sharing_policies is
  'Admin may inspect sharing mode metadata only; protected Women Health content remains excluded.';

commit;
