-- Keep canonical PostgreSQL migrations compatible with both Supabase's
-- `extensions` placement and portable installs where pgcrypto is in `public`.
create schema if not exists extensions;

do $$
begin
  if to_regprocedure('extensions.digest(text,text)') is null
     and to_regprocedure('public.digest(text,text)') is not null then
    execute $function$
      create function extensions.digest(input text, algorithm text)
      returns bytea
      language sql immutable strict parallel safe
      as 'select public.digest($1, $2)'
    $function$;
  end if;

  if to_regprocedure('extensions.digest(bytea,text)') is null
     and to_regprocedure('public.digest(bytea,text)') is not null then
    execute $function$
      create function extensions.digest(input bytea, algorithm text)
      returns bytea
      language sql immutable strict parallel safe
      as 'select public.digest($1, $2)'
    $function$;
  end if;

  if to_regprocedure('extensions.gen_random_bytes(integer)') is null
     and to_regprocedure('public.gen_random_bytes(integer)') is not null then
    execute $function$
      create function extensions.gen_random_bytes(byte_count integer)
      returns bytea
      language sql volatile strict parallel safe
      as 'select public.gen_random_bytes($1)'
    $function$;
  end if;
end
$$;

grant usage on schema extensions to lifemate_edge_runtime;
grant usage on schema extensions to lifemate_admin_runtime;

do $$
begin
  if to_regprocedure('extensions.digest(text,text)') is not null then
    execute 'grant execute on function extensions.digest(text,text) to lifemate_edge_runtime,lifemate_admin_runtime';
  end if;
  if to_regprocedure('extensions.digest(bytea,text)') is not null then
    execute 'grant execute on function extensions.digest(bytea,text) to lifemate_edge_runtime,lifemate_admin_runtime';
  end if;
  if to_regprocedure('extensions.gen_random_bytes(integer)') is not null then
    execute 'grant execute on function extensions.gen_random_bytes(integer) to lifemate_edge_runtime,lifemate_admin_runtime';
  end if;
end
$$;
