create index if not exists ix_pregnancy_dating_actor_account
  on pregnancy.dating_revisions(actor_account_id)
  where actor_account_id is not null;

create index if not exists ix_pregnancy_event_actor_account
  on pregnancy.episode_events(actor_account_id)
  where actor_account_id is not null;
