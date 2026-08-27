begin;

-- Abuse-rule administration is a high-risk security policy mutation, not the
-- separate elevated-health-data capability. Keep it in the ordinary allow-listed
-- RBAC catalog; the Admin API already enforces AAL2.
update admin.permissions
set risk_level='HIGH_RISK',
    role_assignable=true,
    description='Create, update and retire explainable abuse rules through audited high-risk server workflows',
    updated_at_utc=now()
where code='security.abuse.write';

-- Rule writes are available only through narrow privileged entrypoints. The Admin
-- runtime retains read access for the console but does not receive direct mutation
-- authority over the security tables.
alter function security.upsert_abuse_rule(
  uuid,character varying,character varying,character varying,character varying,
  character varying,character varying,integer,integer,integer,character varying,
  character varying,integer,bigint,character varying,uuid
) security definer;
alter function security.retire_abuse_rule(
  uuid,uuid,bigint,character varying,uuid
) security definer;
alter function security.upsert_abuse_rule_idempotent(
  uuid,character varying,character varying,character varying,character varying,
  character varying,character varying,integer,integer,integer,character varying,
  character varying,integer,bigint,character varying,uuid,character varying,character varying
) security definer;
alter function security.retire_abuse_rule_idempotent(
  uuid,uuid,bigint,character varying,uuid,character varying,character varying
) security definer;

revoke insert,update on security.abuse_rules from lifemate_admin_runtime;
revoke insert on security.abuse_rule_versions from lifemate_admin_runtime;
grant select on security.abuse_rules,security.abuse_rule_versions,
  security.abuse_events,security.abuse_decisions to lifemate_admin_runtime;

-- Generic Edge callers must not be able to submit arbitrary actor/subject UUIDs
-- to the privileged evaluator or poison usage history. Child-domain SECURITY
-- DEFINER functions (#492+) invoke these helpers internally after their own
-- account/person authorization checks.
revoke execute on function security.evaluate_abuse_rules(
  uuid,uuid,character varying,character varying,character varying[],character varying,character varying
) from lifemate_edge_runtime;
revoke execute on function security.record_abuse_event(
  uuid,character varying,character varying,character varying
) from lifemate_edge_runtime;

comment on function security.evaluate_abuse_rules(
  uuid,uuid,character varying,character varying,character varying[],character varying,character varying
) is 'Internal explainable abuse evaluator. Not directly executable by the generic Edge DB role; purpose-specific authorized server mutations call it inside their transaction.';
comment on function security.record_abuse_event(
  uuid,character varying,character varying,character varying
) is 'Internal idempotent usage-event recorder. Purpose-specific authorized server mutations call it only after successful business execution.';

commit;
