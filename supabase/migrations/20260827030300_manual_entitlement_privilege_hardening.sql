begin;

alter function commerce.preview_manual_entitlement_adjustment(
  uuid,character varying,uuid,uuid,bigint,character varying,character varying,integer,timestamptz,timestamptz
) security definer;

revoke all on function commerce.preview_manual_entitlement_adjustment(
  uuid,character varying,uuid,uuid,bigint,character varying,character varying,integer,timestamptz,timestamptz
) from public,anon,authenticated;
grant execute on function commerce.preview_manual_entitlement_adjustment(
  uuid,character varying,uuid,uuid,bigint,character varying,character varying,integer,timestamptz,timestamptz
) to lifemate_admin_runtime;

revoke all on function commerce.manual_adjustment_approval_valid(
  uuid,uuid,uuid,bigint,jsonb,jsonb,jsonb,uuid
) from public,anon,authenticated;
grant execute on function commerce.manual_adjustment_approval_valid(
  uuid,uuid,uuid,bigint,jsonb,jsonb,jsonb,uuid
) to lifemate_admin_runtime;

revoke all on function admin.account_has_active_role(uuid,character varying,timestamptz)
  from public,anon,authenticated;
revoke all on function commerce.manual_adjustment_target_features(character varying,uuid)
  from public,anon,authenticated;
revoke all on function commerce.manual_adjustment_self_person(uuid)
  from public,anon,authenticated;

comment on function commerce.preview_manual_entitlement_adjustment(
  uuid,character varying,uuid,uuid,bigint,character varying,character varying,integer,timestamptz,timestamptz
) is 'Narrow read-only preview entrypoint for #492. Uses canonical Product/Offer feature mapping and exact entitlement version for existing adjustments.';

commit;
