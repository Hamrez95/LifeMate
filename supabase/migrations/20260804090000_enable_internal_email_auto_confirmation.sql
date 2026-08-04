-- Internal testing phase only.
-- Keep normal Supabase rate-limited email/password signup, but mark newly
-- inserted email users as confirmed so the apps receive a session immediately
-- and do not require an email-confirmation round trip.
-- Remove this trigger before public launch or when authentication is migrated.
create or replace function public.lifemate_internal_auto_confirm_email()
returns trigger
language plpgsql
security definer
set search_path = auth, pg_temp
as $$
begin
  if new.email is not null and new.email_confirmed_at is null then
    new.email_confirmed_at := now();
  end if;
  return new;
end;
$$;

revoke all on function public.lifemate_internal_auto_confirm_email()
from public, anon, authenticated;

drop trigger if exists lifemate_internal_auto_confirm_email on auth.users;
create trigger lifemate_internal_auto_confirm_email
before insert on auth.users
for each row
execute function public.lifemate_internal_auto_confirm_email();
