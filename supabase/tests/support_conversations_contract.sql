\set ON_ERROR_STOP on

-- #496 contract: conversation storage extends canonical support.tickets and remains
-- unavailable to browser roles. Runtime access is function-scoped for users and
-- Admin writes go through the existing support.write authority.

do $$
begin
  if to_regclass('support.conversation_messages') is null
     or to_regclass('support.conversation_reads') is null
     or to_regclass('support.message_attachments') is null then
    raise exception 'support conversation tables are missing';
  end if;

  if not exists (
    select 1 from pg_constraint c
    join pg_class t on t.oid=c.conrelid
    join pg_namespace n on n.oid=t.relnamespace
    where n.nspname='support' and t.relname='conversation_messages'
      and c.contype='f' and pg_get_constraintdef(c.oid) like '%support.tickets%'
  ) then
    raise exception 'conversation messages must extend support.tickets';
  end if;

  if not exists (
    select 1 from pg_class c join pg_namespace n on n.oid=c.relnamespace
    where n.nspname='support' and c.relname='conversation_messages'
      and c.relrowsecurity and c.relforcerowsecurity
  ) then
    raise exception 'conversation messages must FORCE RLS';
  end if;
end
$$;

do $$
declare v_role text;
begin
  foreach v_role in array array['anon','authenticated'] loop
    if exists(select 1 from pg_roles where rolname=v_role) then
      if has_table_privilege(v_role,'support.conversation_messages','SELECT,INSERT,UPDATE,DELETE')
         or has_table_privilege(v_role,'support.conversation_reads','SELECT,INSERT,UPDATE,DELETE')
         or has_table_privilege(v_role,'support.message_attachments','SELECT,INSERT,UPDATE,DELETE') then
        raise exception 'browser role % must not have direct support conversation table privileges',v_role;
      end if;
    end if;
  end loop;
end
$$;

do $$
begin
  if exists(select 1 from pg_roles where rolname='lifemate_edge_runtime') then
    if has_table_privilege('lifemate_edge_runtime','support.conversation_messages','SELECT,INSERT,UPDATE,DELETE') then
      raise exception 'edge runtime must not mutate/read conversation tables directly';
    end if;
    if not has_function_privilege(
      'lifemate_edge_runtime',
      'support.open_support_conversation(uuid,character varying,character varying,text,uuid)',
      'EXECUTE'
    ) then
      raise exception 'edge runtime requires narrow open conversation function';
    end if;
  end if;

  if exists(select 1 from pg_roles where rolname='lifemate_admin_runtime') then
    if not has_table_privilege('lifemate_admin_runtime','support.conversation_messages','SELECT') then
      raise exception 'admin runtime requires read-only visible-message access';
    end if;
    if has_table_privilege('lifemate_admin_runtime','support.conversation_messages','INSERT,UPDATE,DELETE') then
      raise exception 'admin runtime must not directly mutate visible messages';
    end if;
    if not has_function_privilege(
      'lifemate_admin_runtime',
      'admin.send_support_conversation_message(uuid,uuid,text,uuid,uuid,character varying,character varying)',
      'EXECUTE'
    ) then
      raise exception 'admin runtime requires purpose-specific visible reply function';
    end if;
  end if;
end
$$;

-- Security-definer functions must not be executable by PUBLIC (ACL grantee oid 0).
do $$
declare
  sig regprocedure;
  public_has_execute boolean;
begin
  foreach sig in array array[
    'support.open_support_conversation(uuid,character varying,character varying,text,uuid)'::regprocedure,
    'support.send_user_support_message(uuid,uuid,text,uuid)'::regprocedure,
    'support.list_user_support_messages(uuid,uuid,timestamp with time zone,integer)'::regprocedure,
    'support.mark_user_support_read(uuid,uuid,uuid)'::regprocedure,
    'admin.send_support_conversation_message(uuid,uuid,text,uuid,uuid,character varying,character varying)'::regprocedure
  ] loop
    select exists (
      select 1
      from pg_proc p,
           lateral aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) acl
      where p.oid=sig::oid
        and acl.grantee=0
        and acl.privilege_type='EXECUTE'
    ) into public_has_execute;
    if public_has_execute then
      raise exception 'PUBLIC execute must be revoked from %',sig;
    end if;
  end loop;
end
$$;
