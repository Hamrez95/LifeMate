\set ON_ERROR_STOP on

begin;

-- Seed through the canonical legacy write path as the migration owner. The
-- compatibility trigger creates Account, Self Person, enrollments and FREE
-- entitlements exactly as production bootstrap does.
insert into lifemate.app_users(id, auth_subject, status, created_at_utc, updated_at_utc)
values (
  '5b2500d0-2209-4b6f-9e41-1f9ff3a84c01'::uuid,
  'restricted-runtime-contract-subject',
  'Active',
  now(),
  now()
);
insert into lifemate.user_profiles(
  user_id, display_name, phone_number, email, locale, time_zone,
  avatar_key, version, created_at_utc, updated_at_utc
)
values (
  '5b2500d0-2209-4b6f-9e41-1f9ff3a84c01'::uuid,
  'Restricted Runtime Contract', null, 'runtime-contract@example.test',
  'fa', 'Asia/Tehran', 'person_blue', 1, now(), now()
);

set local role lifemate_edge_runtime;
select identity.request_account_deletion(
  '5b2500d0-2209-4b6f-9e41-1f9ff3a84c01'::uuid
) as request_id \gset

-- The API role must also be able to read its own deletion state through the
-- exact SECURITY INVOKER RPC used by the Edge route.
do $$
begin
  if not exists (
    select 1
    from identity.latest_account_deletion_request(
      '5b2500d0-2209-4b6f-9e41-1f9ff3a84c01'::uuid
    ) r
    where r.status='Requested'
  ) then
    raise exception 'restricted API role could not read deletion request';
  end if;
end
$$;

reset role;

-- The outbox worker finalizes the same request with its separate restricted
-- identity. This proves all WHERE-predicate read privileges required by the
-- SECURITY INVOKER finalizer are present, without granting schema-wide DML.
set local role lifemate_worker_runtime;
do $$
declare
  v_request_id uuid;
begin
  select id into v_request_id
  from identity.account_deletion_requests
  where account_id='5b2500d0-2209-4b6f-9e41-1f9ff3a84c01'::uuid
  order by requested_at_utc desc
  limit 1;
  if v_request_id is null then
    raise exception 'deletion request missing before worker finalization';
  end if;
  if identity.finalize_account_deletion(v_request_id) is not true then
    raise exception 'restricted worker failed to finalize account deletion';
  end if;
end
$$;
reset role;

do $$
begin
  if not exists (
    select 1 from identity.accounts
    where id='5b2500d0-2209-4b6f-9e41-1f9ff3a84c01'::uuid
      and status='Deleted'
  ) then
    raise exception 'account was not finalized as Deleted';
  end if;
  if not exists (
    select 1 from identity.account_deletion_requests
    where account_id='5b2500d0-2209-4b6f-9e41-1f9ff3a84c01'::uuid
      and status='Completed'
  ) then
    raise exception 'deletion request was not completed';
  end if;
end
$$;

rollback;
