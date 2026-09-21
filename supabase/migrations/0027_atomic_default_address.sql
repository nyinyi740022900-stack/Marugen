-- Fixes a race in "set default address": the app previously did this as
-- two separate statements (clear all defaults for the user, then set the
-- target insert/update's is_default) — see
-- lib/features/profile/data/address_repository.dart. A crash between the
-- two, or two concurrent "set default" taps, could leave a user with zero
-- default addresses or two rows both marked default, since nothing
-- enforced "at most one default per user" atomically.
--
-- This RPC does the clear-and-set as a single UPDATE statement, which
-- Postgres applies atomically across every row it touches — there is no
-- window where the write is half-done. `security definer` + pinned
-- `search_path` is standard practice for a function that needs to run as
-- table owner; the function stays safe to expose to any authenticated
-- user because it hardcodes `where user_id = auth.uid()` itself rather
-- than trusting a client-supplied user id.

create or replace function public.set_default_address(p_address_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.addresses
  set is_default = (id = p_address_id)
  where user_id = auth.uid();
end;
$$;

grant execute on function public.set_default_address(uuid) to authenticated;
