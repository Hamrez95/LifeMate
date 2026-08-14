-- FK support index for app-user deletion/revocation paths. The primary read
-- queries are already covered by person/date/type indexes, but owner_user_id is
-- also a cascading foreign key and should not require a table scan when the
-- parent app user is deleted.
create index if not exists ix_health_observations_owner_user_id
  on lifemate.health_observations(owner_user_id);
