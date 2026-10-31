-- Push tokens per device (whole-app audit P1-7).
--
-- An account held one FCM token (profiles.fcm_token) and nothing took a
-- token away from the account that used a phone before. If someone's
-- sign-out never reached the server and another person then signed in on
-- that phone, both accounts pointed at it and the first one's order pushes
-- kept arriving there.
--
-- device_tokens keeps one row per token, owned by the account that last
-- registered it, which also lets one account get pushes on several
-- devices. profiles.fcm_token stays in step for app builds and functions
-- that still read it.

create table if not exists public.device_tokens (
  token text primary key check (btrim(token) <> '' and length(token) <= 4096),
  user_id uuid not null references public.profiles(id) on delete cascade,
  platform text check (platform in ('android', 'ios')),
  updated_at timestamptz not null default now()
);
create index if not exists device_tokens_user_id_idx
  on public.device_tokens(user_id);
alter table public.device_tokens enable row level security;
-- No policies: the app goes through the two functions below and Edge
-- Functions use the service role.
revoke all on public.device_tokens from anon, authenticated;

-- A token shared by several accounts belongs to whoever signed in last.
with ranked as (
  select p.id, p.fcm_token,
         row_number() over (
           partition by p.fcm_token
           order by u.last_sign_in_at desc nulls last, p.created_at desc
         ) as rank
    from public.profiles p
    join auth.users u on u.id = p.id
   where p.fcm_token is not null and btrim(p.fcm_token) <> ''
)
insert into public.device_tokens(token, user_id)
select fcm_token, id from ranked where rank = 1
on conflict (token) do nothing;
update public.profiles p
   set fcm_token = null
  from public.device_tokens d
 where d.token = p.fcm_token
   and d.user_id <> p.id;

create or replace function public.register_device_token(
  p_token text,
  p_platform text default null
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  me uuid := auth.uid();
begin
  if me is null then
    raise exception 'Sign in to register this device' using errcode = '42501';
  end if;
  insert into public.device_tokens(token, user_id, platform, updated_at)
  values (p_token, me, p_platform, now())
  on conflict (token) do update
    set user_id = excluded.user_id,
        platform = excluded.platform,
        updated_at = now();
  update public.profiles set fcm_token = null
   where fcm_token = p_token and id <> me;
  update public.profiles set fcm_token = p_token
   where id = me and fcm_token is distinct from p_token;
end;
$$;

create or replace function public.unregister_device_token(p_token text)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  delete from public.device_tokens
   where token = p_token and user_id = auth.uid();
  update public.profiles set fcm_token = null
   where id = auth.uid() and fcm_token = p_token;
end;
$$;

revoke all on function public.register_device_token(text, text)
  from public, anon;
grant execute on function public.register_device_token(text, text)
  to authenticated;
revoke all on function public.unregister_device_token(text) from public, anon;
grant execute on function public.unregister_device_token(text)
  to authenticated;
