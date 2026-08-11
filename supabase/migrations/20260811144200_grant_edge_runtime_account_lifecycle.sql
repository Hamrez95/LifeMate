-- Account lifecycle endpoints call these RPCs directly. Keep EXECUTE explicit so
-- revoking the default function privileges cannot break self-service deletion.
grant execute on function identity.request_account_deletion(uuid)
  to lifemate_edge_runtime;
grant execute on function identity.latest_account_deletion_request(uuid)
  to lifemate_edge_runtime;
