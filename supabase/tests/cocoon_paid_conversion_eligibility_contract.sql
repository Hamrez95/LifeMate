do $$
begin
  if commerce.cocoon_period_conversion_eligible(
    '00000000-0000-0000-0000-000000000000'::uuid,
    '00000000-0000-0000-0000-000000000000'::uuid
  ) then
    raise exception 'unknown account/person must not be conversion eligible';
  end if;

  if not has_function_privilege(
    'lifemate_edge_runtime',
    'commerce.cocoon_period_conversion_eligible(uuid,uuid)',
    'EXECUTE'
  ) then
    raise exception 'healthcare edge runtime must be able to evaluate Cocoon conversion eligibility';
  end if;

  if has_function_privilege(
    'authenticated',
    'commerce.cocoon_period_conversion_eligible(uuid,uuid)',
    'EXECUTE'
  ) then
    raise exception 'authenticated clients must not call the privileged eligibility function';
  end if;

  if has_table_privilege(
    'lifemate_edge_runtime',
    'commerce.transaction_effective_state_v1',
    'SELECT'
  ) then
    raise exception 'healthcare edge runtime must not read the protected transaction view directly';
  end if;
end
$$;
