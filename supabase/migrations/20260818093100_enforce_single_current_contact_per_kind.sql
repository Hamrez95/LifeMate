-- #358 / #217: canonical Account contact state is singular per kind.
-- Keep historical Revoked rows, but never allow two current Email or Phone rows
-- for the same Account at the same time.

create unique index if not exists uq_contact_points_current_account_kind
  on identity.contact_points(account_id,kind)
  where status <> 'Revoked';

comment on index identity.uq_contact_points_current_account_kind is
  'At most one Pending/Verified ContactPoint of each kind may be current for an Account.';
