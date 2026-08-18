-- #358 / #217: complete the existing canonical ContactPoint model with the
-- envelope metadata required for externally keyed authenticated encryption.
-- Existing Profile email/phone columns remain the compatibility read/write model
-- until a later protected readiness/backfill cutover.

alter table identity.contact_points
  add column if not exists encryption_nonce_b64 character varying(64),
  add column if not exists encryption_key_version smallint;

alter table identity.contact_points
  drop constraint if exists ck_contact_points_nonce_b64;
alter table identity.contact_points
  add constraint ck_contact_points_nonce_b64
  check (
    encryption_nonce_b64 is null or
    length(encryption_nonce_b64) between 16 and 32
  );

alter table identity.contact_points
  drop constraint if exists ck_contact_points_encryption_key_version;
alter table identity.contact_points
  add constraint ck_contact_points_encryption_key_version
  check (
    encryption_key_version is null or
    encryption_key_version between 1 and 32767
  );

-- The original unconditional UNIQUE(kind,hash) prevented a legitimately
-- transferred phone/email from ever being attached to a new Account after the
-- old ContactPoint had been revoked. Keep global uniqueness only for current
-- (Pending/Verified) contacts; historical revoked hashes remain audit-safe.
alter table identity.contact_points
  drop constraint if exists contact_points_kind_normalized_value_hash_key;
create unique index if not exists uq_contact_points_current_kind_hash
  on identity.contact_points(kind,normalized_value_hash)
  where status <> 'Revoked';

comment on column identity.contact_points.normalized_value_hash is
  'Domain-separated HMAC-SHA256 lookup hash of normalized contact data using a dedicated external LifeMate hashing secret.';
comment on column identity.contact_points.encrypted_value is
  'AES-GCM ciphertext including authentication tag. Plaintext email/phone must never be persisted here.';
comment on column identity.contact_points.encryption_nonce_b64 is
  'Per-envelope 96-bit AES-GCM nonce encoded as base64; not secret.';
comment on column identity.contact_points.encryption_key_version is
  'External ContactPoint envelope key version. Encryption key material is never stored in PostgreSQL.';

alter table identity.contact_points enable row level security;
alter table identity.contact_points force row level security;
revoke all on identity.contact_points from public;

do $$
declare
  v_role text;
begin
  foreach v_role in array array['anon','authenticated','service_role'] loop
    if exists(select 1 from pg_roles where rolname=v_role) then
      execute format('revoke all on identity.contact_points from %I',v_role);
    end if;
  end loop;

  if exists(select 1 from pg_roles where rolname='lifemate_edge_runtime') then
    grant select,insert,update on identity.contact_points to lifemate_edge_runtime;
    revoke delete,truncate on identity.contact_points from lifemate_edge_runtime;
  end if;

  -- Account-deletion finalization already owns the only Worker mutation path.
  -- Keep the historical DELETE privilege but do not expand it to contact reads.
  if exists(select 1 from pg_roles where rolname='lifemate_worker_runtime') then
    revoke select,insert,update,truncate on identity.contact_points
      from lifemate_worker_runtime;
    grant delete on identity.contact_points to lifemate_worker_runtime;
  end if;
end
$$;
