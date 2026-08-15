-- Move the short-lived healthcare idempotency ledger away from a raw Auth
-- subject linkage. New runtime rows use an externally keyed HMAC token while
-- existing raw-subject rows remain readable for their <=24h replay window.
--
-- The raw compatibility column is deliberately not dropped in this migration;
-- destructive retirement remains gated on protected token-only evidence.

alter table lifemate.idempotency_keys
    add column if not exists actor_subject_token character varying(64);

alter table lifemate.idempotency_keys
    drop constraint if exists ck_lifemate_idempotency_actor_subject_token;
alter table lifemate.idempotency_keys
    add constraint ck_lifemate_idempotency_actor_subject_token
    check (
      actor_subject_token is null
      or actor_subject_token ~ '^[0-9a-f]{64}$'
    );

-- A primary-key column is implicitly NOT NULL. Replace it with a nullable
-- UNIQUE constraint on the legacy key plus a token-only partial unique index.
-- Keeping a real UNIQUE constraint on the old columns is deliberate: the
-- currently deployed runtime's existing ON CONFLICT(column,...) statement
-- remains valid while this backwards-compatible schema migration rolls out.
alter table lifemate.idempotency_keys
    drop constraint if exists idempotency_keys_pkey;
alter table lifemate.idempotency_keys
    alter column actor_auth_subject drop not null;

alter table lifemate.idempotency_keys
    drop constraint if exists uq_lifemate_idempotency_legacy_actor_key;
alter table lifemate.idempotency_keys
    add constraint uq_lifemate_idempotency_legacy_actor_key
    unique (actor_auth_subject, operation, idempotency_key);

alter table lifemate.idempotency_keys
    drop constraint if exists ck_lifemate_idempotency_actor_identity_exactly_one;
alter table lifemate.idempotency_keys
    add constraint ck_lifemate_idempotency_actor_identity_exactly_one
    check (num_nonnulls(actor_auth_subject, actor_subject_token) = 1);

create unique index if not exists ux_lifemate_idempotency_token_actor_key
    on lifemate.idempotency_keys(actor_subject_token, operation, idempotency_key)
    where actor_subject_token is not null;

create index if not exists ix_lifemate_idempotency_actor_subject_token
    on lifemate.idempotency_keys(actor_subject_token)
    where actor_subject_token is not null;
