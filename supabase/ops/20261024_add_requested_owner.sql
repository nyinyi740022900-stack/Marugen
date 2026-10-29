-- Prepared for explicit action-time confirmation of full Owner access.
-- App-level role only; does not grant Supabase project/team membership.
begin;
do $$
declare target public.profiles; updated public.profiles;
begin
 select p.* into strict target from public.profiles p
 join auth.users u on u.id=p.id
 where p.id='81b5a785-7aac-4925-b98e-927932790690'
 and lower(u.email)='marugenfishfarmaiagent@gmail.com'
 and u.email_confirmed_at is not null for update of p;
 if target.role is distinct from 'customer' then
  raise exception 'Account role changed; inspect again';
 end if;
 update public.profiles set role='owner' where id=target.id
 returning * into strict updated;
 if updated.role is distinct from 'owner' or
    (to_jsonb(target)-'role') is distinct from (to_jsonb(updated)-'role') then
  raise exception 'Unexpected account mutation; rolled back';
 end if;
end $$;
select email,role from public.profiles
where id='81b5a785-7aac-4925-b98e-927932790690';
commit;
