begin;

-- Command Center may inspect Circle structure for support/operations, but never
-- raw planning events, audit metadata, contact hashes, or health content.
-- Use column-level grants so the runtime role cannot read excluded fields even
-- if a future query accidentally references them.
grant select (
  id,
  owner_person_id,
  circle_kind,
  name,
  icon_key,
  status,
  version,
  created_at_utc,
  updated_at_utc,
  closed_at_utc
) on table network.circles to lifemate_admin_runtime;

grant select (
  id,
  circle_id,
  person_id,
  membership_role,
  membership_status,
  joined_at_utc,
  left_at_utc,
  removed_at_utc,
  created_at_utc,
  updated_at_utc
) on table network.circle_members to lifemate_admin_runtime;

grant select (
  id,
  circle_id,
  inviter_person_id,
  invitee_person_id,
  status,
  expires_at_utc,
  accepted_at_utc,
  declined_at_utc,
  revoked_at_utc,
  created_at_utc,
  updated_at_utc
) on table network.circle_invitations to lifemate_admin_runtime;

grant select (
  circle_id,
  person_id,
  sharing_mode,
  version,
  created_at_utc,
  updated_at_utc,
  revoked_at_utc
) on table network.circle_member_sharing_policies to lifemate_admin_runtime;

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
  'Admin structural support read only. invitee_contact_hash is not granted to the runtime role.';
comment on policy circle_sharing_admin_structure_read on network.circle_member_sharing_policies is
  'Admin may inspect sharing_mode lifecycle metadata only; protected Women Health content and sharing flags remain excluded.';

commit;
