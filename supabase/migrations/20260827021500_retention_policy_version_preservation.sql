begin;

-- The existing retention-v2 finalizer intentionally records its own policy
-- version. Once a deletion request has been upgraded to retention-v3, however,
-- that legacy assignment must not erase the exact policy version that governed
-- eligibility/holds. Preserve the current v3 evidence across later status
-- transitions while leaving pre-v3 requests unchanged.
create or replace function identity.preserve_account_deletion_retention_policy_version()
returns trigger
language plpgsql
set search_path=pg_catalog,identity,pg_temp
as $$
begin
  if old.retention_policy_version like 'retention-v3.%'
     and new.retention_policy_version in ('retention-v1','retention-v2') then
    new.retention_policy_version:=old.retention_policy_version;
  end if;
  return new;
end $$;

drop trigger if exists trg_preserve_account_deletion_retention_policy_version
  on identity.account_deletion_requests;
create trigger trg_preserve_account_deletion_retention_policy_version
before update of retention_policy_version on identity.account_deletion_requests
for each row execute function identity.preserve_account_deletion_retention_policy_version();

revoke all on function identity.preserve_account_deletion_retention_policy_version() from public;

comment on function identity.preserve_account_deletion_retention_policy_version()
is 'Prevents the legacy retention-v2 finalizer from downgrading exact retention-v3 policy evidence after a request has been upgraded.';

commit;
