-- Disposable database only. Checks migration 0079 against the full schema.
-- All fixtures are synthetic and rolled back.
\set ON_ERROR_STOP on
begin;

create schema lease_test;
create function lease_test.fail_unless(ok boolean, message text) returns void
language plpgsql as $$
begin
  if ok is not true then raise exception 'FAILED: %', message; end if;
end $$;
create function lease_test.attempt(statement text) returns text
language plpgsql as $$
begin
  execute statement;
  return 'ok';
exception
  when insufficient_privilege then return 'denied';
  when others then return 'rejected: ' || sqlerrm;
end $$;
grant usage on schema lease_test to anon, authenticated, service_role;
create function lease_test.lease() returns timestamptz
language sql security definer as $$
  select refresh_started_at from public.easyparcel_connection where id = 1
$$;

insert into auth.users (id, email) values
  ('79000000-0000-0000-0000-000000000001', 'buyer@example.invalid'),
  ('79000000-0000-0000-0000-000000000002', 'staff@example.invalid'),
  ('79000000-0000-0000-0000-000000000004', 'owner@example.invalid');
update public.profiles set role = 'staff' where id = '79000000-0000-0000-0000-000000000002';
update public.profiles set role = 'owner' where id = '79000000-0000-0000-0000-000000000004';
insert into public.easyparcel_connection
  (id, access_token, refresh_token, access_token_expires_at, refresh_token_expires_at)
values (1, 'access-test', 'refresh-test', now() - interval '1 minute', now() + interval '30 days');

-- Server only, definer with a pinned search_path.
select lease_test.fail_unless(
  to_regprocedure('public.release_easyparcel_token_refresh(text)') is not null,
  'release_easyparcel_token_refresh(text) exists');
select lease_test.fail_unless(
  not has_function_privilege(r, 'public.release_easyparcel_token_refresh(text)', 'execute'),
  format('%s cannot execute release_easyparcel_token_refresh', r))
  from unnest(array['anon', 'authenticated']) r;
select lease_test.fail_unless(
  has_function_privilege('service_role', 'public.release_easyparcel_token_refresh(text)', 'execute'),
  'service_role can execute release_easyparcel_token_refresh');
select lease_test.fail_unless(
  (select p.prosecdef and p.proconfig @> array['search_path=public, pg_temp']
     from pg_proc p
    where p.oid = 'public.release_easyparcel_token_refresh(text)'::regprocedure),
  'release_easyparcel_token_refresh is SECURITY DEFINER with a pinned search_path');

set local role service_role;
-- Nothing held: nothing to release.
select lease_test.fail_unless(
  not public.release_easyparcel_token_refresh('refresh-test'),
  'releasing when no lease is held reports false');
-- Held lease, wrong token: refused, lease kept.
select lease_test.fail_unless(
  public.claim_easyparcel_token_refresh('refresh-test'),
  'the refresher takes the lease');
select lease_test.fail_unless(
  not public.release_easyparcel_token_refresh('some-other-token')
  and lease_test.lease() is not null,
  'a different refresh token cannot release the lease');
select lease_test.fail_unless(
  not public.claim_easyparcel_token_refresh('refresh-test'),
  'the lease is still held after the refused release');
-- The holder hands it back: the next refresher gets it at once.
select lease_test.fail_unless(
  public.release_easyparcel_token_refresh('refresh-test')
  and lease_test.lease() is null,
  'the holder releases its lease');
select lease_test.fail_unless(
  not public.release_easyparcel_token_refresh('refresh-test'),
  'a second release is a no-op');
select lease_test.fail_unless(
  public.claim_easyparcel_token_refresh('refresh-test'),
  'the next refresher takes the lease without waiting 60 seconds');
reset role;

-- The tokens were replaced (successful refresh or reconnect) while a lease
-- is running on the new ones: the old holder releases nothing.
update public.easyparcel_connection
   set refresh_token = 'refresh-rotated', refresh_started_at = now();
set local role service_role;
select lease_test.fail_unless(
  not public.release_easyparcel_token_refresh('refresh-test')
  and lease_test.lease() is not null,
  'a holder of the previous refresh token cannot release the new lease');
reset role;

-- An expired lease is not touched (it is free for the next claim anyway).
update public.easyparcel_connection set refresh_started_at = now() - interval '61 seconds';
set local role service_role;
select lease_test.fail_unless(
  not public.release_easyparcel_token_refresh('refresh-rotated')
  and lease_test.lease() is not null,
  'an expired lease is left alone');
select lease_test.fail_unless(
  public.claim_easyparcel_token_refresh('refresh-rotated'),
  'an expired lease can still be claimed');
reset role;

-- Forbidden callers, by real calls: anon, customer, staff and owner.
set local role anon;
select lease_test.fail_unless(
  lease_test.attempt('select public.release_easyparcel_token_refresh(''refresh-rotated'')') = 'denied',
  'anon cannot call release_easyparcel_token_refresh');
reset role;
select set_config('request.jwt.claim.sub', u, true),
       set_config('role', 'authenticated', true),
       lease_test.fail_unless(
         lease_test.attempt('select public.release_easyparcel_token_refresh(''refresh-rotated'')') = 'denied',
         format('signed-in user %s cannot call release_easyparcel_token_refresh', u))
  from unnest(array[
    '79000000-0000-0000-0000-000000000001',
    '79000000-0000-0000-0000-000000000002',
    '79000000-0000-0000-0000-000000000004']) u;
reset role;
select set_config('request.jwt.claim.sub', '', true);
select lease_test.fail_unless(
  lease_test.lease() is not null,
  'the lease survived every forbidden call');

rollback;
