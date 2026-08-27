begin;

-- v2 is the canonical correction executor because it binds the mutation to
-- an idempotency key + request hash before consuming the approval snapshot.
revoke all on function admin.apply_approved_transaction_correction(
  uuid,uuid,character varying,character varying,character varying,
  character varying,uuid,bigint,uuid
) from public,anon,authenticated,lifemate_admin_runtime;

revoke all on function admin.apply_approved_transaction_correction_v2(
  uuid,uuid,character varying,character varying,character varying,
  character varying,uuid,bigint,uuid,character varying,character varying
) from public,anon,authenticated;
grant execute on function admin.apply_approved_transaction_correction_v2(
  uuid,uuid,character varying,character varying,character varying,
  character varying,uuid,bigint,uuid,character varying,character varying
) to lifemate_admin_runtime;

comment on function admin.apply_approved_transaction_correction_v2(
  uuid,uuid,character varying,character varying,character varying,
  character varying,uuid,bigint,uuid,character varying,character varying
) is 'Canonical idempotent #493 reconciliation correction executor. Provider transaction facts remain immutable; only append-only classification correction is added.';

commit;
