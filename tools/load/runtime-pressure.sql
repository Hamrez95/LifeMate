select json_build_object(
  'sampledAtUtc', clock_timestamp(),
  'database', json_build_object(
    'maxConnections', current_setting('max_connections')::integer,
    'databaseConnections', (
      select count(*)
      from pg_stat_activity
      where datname=current_database()
    ),
    'lifeMateRuntimeConnections', (
      select count(*)
      from pg_stat_activity
      where datname=current_database()
        and usename in ('lifemate_edge_runtime','lifemate_worker_runtime')
    ),
    'waitingRuntimeConnections', (
      select count(*)
      from pg_stat_activity
      where datname=current_database()
        and usename in ('lifemate_edge_runtime','lifemate_worker_runtime')
        and wait_event_type is not null
    ),
    'runtimeQueriesOverOneSecond', (
      select count(*)
      from pg_stat_activity
      where datname=current_database()
        and usename in ('lifemate_edge_runtime','lifemate_worker_runtime')
        and state='active'
        and query_start is not null
        and clock_timestamp()-query_start > interval '1 second'
    )
  ),
  'outbox', (
    select row_to_json(metrics)
    from integration.outbox_queue_metrics(
      array[
        'care.adherence_projection_refresh_requested',
        'identity.session_revoke_requested',
        'identity.account_deletion_requested'
      ]::character varying[]
    ) metrics
  )
)::text;
