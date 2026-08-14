-- Durable, bounded idempotency ledger for healthcare API mutations.
--
-- This is deliberately separate from domain tables so retry safety can be
-- standardized across treatment, adherence, care, health-observation and
-- account-lifecycle mutations without coupling every aggregate to transport
-- metadata. The ledger stores only short-lived request hashes and response
-- envelopes. Direct mobile roles remain denied; only the reviewed Edge runtime
-- may use it.

create table if not exists lifemate.idempotency_keys (
    actor_auth_subject uuid not null,
    operation character varying(220) not null,
    idempotency_key character varying(180) not null,
    request_hash character varying(64) not null
        check (request_hash ~ '^[0-9a-f]{64}$'),
    status character varying(24) not null default 'Processing'
        check (status in ('Processing','Completed')),
    response_status integer
        check (response_status is null or response_status between 200 and 299),
    response_body text
        check (response_body is null or octet_length(response_body) <= 65536),
    created_at_utc timestamp with time zone not null default now(),
    updated_at_utc timestamp with time zone not null default now(),
    expires_at_utc timestamp with time zone not null
        default (now() + interval '24 hours'),
    primary key (actor_auth_subject, operation, idempotency_key)
);

create index if not exists ix_lifemate_idempotency_expiry
    on lifemate.idempotency_keys(expires_at_utc);

alter table lifemate.idempotency_keys enable row level security;
alter table lifemate.idempotency_keys force row level security;

drop policy if exists lifemate_edge_runtime_access
    on lifemate.idempotency_keys;
create policy lifemate_edge_runtime_access
    on lifemate.idempotency_keys
    for all
    to lifemate_edge_runtime
    using (true)
    with check (true);

grant select, insert, update, delete
    on lifemate.idempotency_keys
    to lifemate_edge_runtime;

-- Preserve the direct-client deny boundary even on Supabase installations where
-- these roles exist. Portable PostgreSQL CI does not create them, so keep this
-- conditional.
do $$
declare
  v_role text;
begin
  foreach v_role in array array['anon','authenticated'] loop
    if exists (select 1 from pg_roles where rolname = v_role) then
      execute format(
        'revoke all on table lifemate.idempotency_keys from %I',
        v_role
      );
    end if;
  end loop;
end
$$;
