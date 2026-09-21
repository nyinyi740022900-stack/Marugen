-- Security fix: "Users can update their own profile" (0001_init.sql) has no
-- WITH CHECK, so any authenticated user could call the REST/JS client
-- directly and set their own profiles.role to 'owner'/'staff', which
-- public.is_admin() then trusts everywhere — a full privilege-escalation
-- path to admin. A trigger (not just a policy) is used so it also covers
-- any future policy/table change, not only this one UPDATE policy.
--
-- auth.uid() is null for a service-role/SQL-editor session (no PostgREST
-- JWT), so legitimate role promotions done from the Supabase dashboard or
-- a backend job using the service key still work — only an authenticated
-- end-user session (auth.uid() present) changing their *own* role without
-- already being admin gets silently reverted.
create or replace function public.prevent_role_self_escalation()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  if new.role is distinct from old.role then
    if auth.uid() is not null and not public.is_admin() then
      new.role := old.role;
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_prevent_role_self_escalation on public.profiles;
create trigger trg_prevent_role_self_escalation
  before update on public.profiles
  for each row execute function public.prevent_role_self_escalation();
