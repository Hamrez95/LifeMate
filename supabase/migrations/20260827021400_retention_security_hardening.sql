begin;

-- Retention administration is high-risk business/security policy, not elevated
-- health-data access. It must remain assignable through the ordinary allow-listed
-- RBAC catalog while AAL2 is enforced by the Admin API boundary.
update admin.permissions
set risk_level='HIGH_RISK',
    role_assignable=true,
    description='Change retention policies and preservation holds through audited high-risk server workflows',
    updated_at_utc=now()
where code='security.retention.write';

-- Narrow privileged entrypoints own the writes. The Admin runtime may read the
-- control-plane state but cannot directly mutate retention tables.
alter function security.retention_policy_for(character varying,character varying) security definer;
alter function security.activate_retention_policy(
  uuid,character varying,character varying,integer,integer,character varying,
  character varying,character varying,uuid
) security definer;
alter function security.create_retention_hold(
  uuid,uuid,character varying,character varying,character varying,character varying,
  timestamptz,uuid
) security definer;
alter function security.release_retention_hold(
  uuid,uuid,character varying,uuid
) security definer;

revoke insert,update on security.retention_policy_versions from lifemate_admin_runtime;
revoke insert,update on security.retention_holds from lifemate_admin_runtime;
revoke insert,update on security.retention_execution_runs from lifemate_admin_runtime;
grant select on security.retention_policy_versions,security.retention_holds,
  security.retention_execution_runs to lifemate_admin_runtime;

-- The worker resolves policy only through the function; no broad policy-table read
-- is required by the caller after SECURITY DEFINER hardening.
revoke all on security.retention_policy_versions from lifemate_worker_runtime;
grant execute on function security.retention_policy_for(character varying,character varying)
  to lifemate_worker_runtime;

comment on function security.activate_retention_policy(
  uuid,character varying,character varying,integer,integer,character varying,
  character varying,character varying,uuid
) is 'Audited high-risk retention policy mutation. SECURITY DEFINER is intentionally narrow; the Admin runtime has no direct write grant on retention policy tables.';

commit;
