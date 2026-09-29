do $$
begin
  begin
    perform platform.client_control_evaluations(
      '00000000-0000-0000-0000-000000000000'::uuid,
      'cocoonmate',
      false
    );
    raise exception 'expected account_not_found for the unknown account';
  exception
    when sqlstate 'P0002' then
      null;
    when sqlstate '22023' then
      raise exception 'CocoonMate was rejected by the runtime-control product allow-list';
  end;
end
$$;
