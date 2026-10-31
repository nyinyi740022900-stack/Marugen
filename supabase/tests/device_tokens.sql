-- Run with psql after migration 0073 (fixtures come from the runner).
-- A = 0…a1, B = 0…b1 (signed in on A's old phone later), C = 0…c1.

-- 1. The migration gives a shared token to whoever signed in last.
do $$ begin
  if (select user_id from public.device_tokens where token = 'shared-phone')
     <> '00000000-0000-0000-0000-0000000000b1' then
    raise exception 'Shared token not given to the latest sign-in';
  end if;
  if (select fcm_token from public.profiles
       where id = '00000000-0000-0000-0000-0000000000a1') is not null then
    raise exception 'Previous owner still holds the shared token';
  end if;
  if (select user_id from public.device_tokens where token = 'c-phone')
     <> '00000000-0000-0000-0000-0000000000c1' then
    raise exception 'Unshared token not copied';
  end if;
end $$;

-- 2. Nobody reads or writes the table directly.
set role anon;
do $$ begin
  begin
    perform 1 from public.device_tokens;
    raise exception 'Anonymous caller read device tokens';
  exception when insufficient_privilege then null;
  end;
  begin
    perform public.register_device_token('anon-token', 'android');
    raise exception 'Anonymous caller registered a token';
  exception when insufficient_privilege then null;
  end;
end $$;
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false);
do $$ begin
  begin
    perform 1 from public.device_tokens;
    raise exception 'Customer read device tokens directly';
  exception when insufficient_privilege then null;
  end;
end $$;

-- 3. Signing in on a phone takes it from the previous account.
select public.register_device_token('shared-phone', 'android');
select public.register_device_token('a-tablet', 'ios');
reset role;
do $$ begin
  if (select user_id from public.device_tokens where token = 'shared-phone')
     <> '00000000-0000-0000-0000-0000000000a1' then
    raise exception 'Re-registered phone not moved to the new account';
  end if;
  if (select fcm_token from public.profiles
       where id = '00000000-0000-0000-0000-0000000000b1') is not null then
    raise exception 'Previous account still targets the phone';
  end if;
  if (select count(*) from public.device_tokens
       where user_id = '00000000-0000-0000-0000-0000000000a1') <> 2 then
    raise exception 'One account cannot keep two devices';
  end if;
  if (select fcm_token from public.profiles
       where id = '00000000-0000-0000-0000-0000000000a1') <> 'a-tablet' then
    raise exception 'Legacy fcm_token not kept in step';
  end if;
end $$;

-- 4. Only the owner can unregister a token; blank tokens are refused.
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000b1', false);
select public.unregister_device_token('a-tablet');
do $$ begin
  begin
    perform public.register_device_token('  ', 'android');
    raise exception 'Blank token registered';
  exception when check_violation then null;
  end;
end $$;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false);
reset role;
do $$ begin
  if not exists (select 1 from public.device_tokens where token = 'a-tablet') then
    raise exception 'Another account unregistered a token it does not own';
  end if;
end $$;
set role authenticated;
select public.unregister_device_token('a-tablet');
reset role;
do $$ begin
  if exists (select 1 from public.device_tokens where token = 'a-tablet')
     or (select fcm_token from public.profiles
          where id = '00000000-0000-0000-0000-0000000000a1') is not null then
    raise exception 'Owner could not unregister the token';
  end if;
end $$;
