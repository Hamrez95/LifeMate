begin;

create or replace function admin.approval_state_has_forbidden_keys(p_value jsonb)
returns boolean
language plpgsql
immutable
security invoker
set search_path = pg_catalog, admin
as $$
declare
  v_key text;
  v_entry jsonb;
begin
  if p_value is null then
    return false;
  end if;

  if jsonb_typeof(p_value)='object' then
    for v_key,v_entry in select key,value from jsonb_each(p_value)
    loop
      if v_key !~ '^[A-Za-z][A-Za-z0-9_]{0,63}$'
         or v_key ~* '(health|medical|medication|treatment|diagnosis|symptom|journal|note|message|content|body|phone|email|address|password|secret|token)'
         or admin.approval_state_has_forbidden_keys(v_entry) then
        return true;
      end if;
    end loop;
    return false;
  end if;

  if jsonb_typeof(p_value)='array' then
    for v_entry in select value from jsonb_array_elements(p_value)
    loop
      if admin.approval_state_has_forbidden_keys(v_entry) then
        return true;
      end if;
    end loop;
  end if;

  return false;
end;
$$;

revoke all on function admin.approval_state_has_forbidden_keys(jsonb) from public,anon,authenticated;
grant execute on function admin.approval_state_has_forbidden_keys(jsonb) to lifemate_admin_runtime;

alter table admin.approval_requests drop constraint if exists ck_admin_approval_before_safe_keys;
alter table admin.approval_requests add constraint ck_admin_approval_before_safe_keys
  check (not admin.approval_state_has_forbidden_keys(before_json));
alter table admin.approval_requests drop constraint if exists ck_admin_approval_delta_safe_keys;
alter table admin.approval_requests add constraint ck_admin_approval_delta_safe_keys
  check (not admin.approval_state_has_forbidden_keys(requested_delta_json));
alter table admin.approval_requests drop constraint if exists ck_admin_approval_after_safe_keys;
alter table admin.approval_requests add constraint ck_admin_approval_after_safe_keys
  check (not admin.approval_state_has_forbidden_keys(after_json));

comment on function admin.approval_state_has_forbidden_keys(jsonb) is
'Database-level defense in depth for the generic approval ledger. Rejects sensitive/free-text/contact/secret-style state keys recursively even when a child-domain server path bypasses the HTTP parser.';

commit;
