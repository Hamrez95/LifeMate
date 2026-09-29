do $$
begin
  if commerce.cocoon_product_offer_available() is null then
    raise exception 'Cocoon offer availability must return an explicit boolean';
  end if;

  if not has_function_privilege(
    'lifemate_edge_runtime',
    'commerce.cocoon_product_offer_available()',
    'EXECUTE'
  ) then
    raise exception 'healthcare edge runtime must be able to evaluate Cocoon offer availability';
  end if;

  if has_function_privilege(
    'authenticated',
    'commerce.cocoon_product_offer_available()',
    'EXECUTE'
  ) then
    raise exception 'authenticated clients must not call the privileged offer function';
  end if;

  if has_table_privilege('lifemate_edge_runtime','commerce.offers','SELECT') then
    raise exception 'healthcare edge runtime must not read the commerce offers catalog directly';
  end if;
end
$$;
