#!/usr/bin/env bash
# Home banners (migration 0076): customers see only active slides inside
# their window; admins see and manage every slide; the window check and
# text-length limits hold at the database.
set -euo pipefail
suite_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
test_root="$(mktemp -d "${TMPDIR:-/tmp}/marugen-banners.XXXXXX")"
cleanup() { pg_ctl -D "$test_root/data" -m immediate stop >/dev/null 2>&1 || true; rm -rf -- "$test_root"; }
trap cleanup EXIT
initdb -D "$test_root/data" -A trust -U postgres >"$test_root/init.log"
pg_ctl -D "$test_root/data" -l "$test_root/server.log" -o "-h '' -k '$test_root'" start >/dev/null
args=(-X -h "$test_root" -U postgres -d postgres -v ON_ERROR_STOP=1)
psql "${args[@]}" >"$test_root/bootstrap.log" <<'SQL'
create role anon nologin;
create role authenticated nologin;
create schema auth;
create function auth.uid() returns uuid language sql stable as
$$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
grant usage on schema public, auth to anon, authenticated;
create table public.profiles(id uuid primary key, role text not null);
create function public.is_admin() returns boolean language sql stable security definer as
$$ select exists (select 1 from public.profiles where id = auth.uid() and role in ('owner', 'staff')) $$;
insert into public.profiles values
  ('00000000-0000-0000-0000-0000000000c1', 'customer'),
  ('00000000-0000-0000-0000-0000000000a1', 'owner');
SQL
psql "${args[@]}" -f "$suite_dir/../migrations/0076_home_banners.sql" >>"$test_root/bootstrap.log"
psql "${args[@]}" >"$test_root/suite.log" <<'SQL'
insert into public.home_banners(id, image_url, title, sort_order, active, starts_at, ends_at) values
  ('00000000-0000-0000-0000-0000000000b1', 'u', 'live open',   2, true,  null, null),
  ('00000000-0000-0000-0000-0000000000b2', 'u', 'live window', 1, true,  now() - interval '1 hour', now() + interval '1 hour'),
  ('00000000-0000-0000-0000-0000000000b3', 'u', 'scheduled',   0, true,  now() + interval '1 day', null),
  ('00000000-0000-0000-0000-0000000000b4', 'u', 'ended',       0, true,  null, now() - interval '1 minute'),
  ('00000000-0000-0000-0000-0000000000b5', 'u', 'hidden',      0, false, null, null);

-- Window and length checks hold.
do $$
begin
  begin
    insert into public.home_banners(image_url, starts_at, ends_at)
    values ('u', now(), now() - interval '1 hour');
    raise exception 'ends_at before starts_at was accepted';
  exception when check_violation then null;
  end;
  begin
    insert into public.home_banners(image_url, title) values ('u', repeat('x', 81));
    raise exception 'an 81-character title was accepted';
  exception when check_violation then null;
  end;
  begin
    insert into public.home_banners(image_url) values ('   ');
    raise exception 'a blank image_url was accepted';
  exception when check_violation then null;
  end;
end $$;

-- Anonymous shoppers: only the two live slides, in sort order.
set role anon;
do $$
declare seen text;
begin
  select string_agg(title, ',' order by sort_order) into seen from public.home_banners;
  if seen is distinct from 'live window,live open' then
    raise exception 'anon sees: % (expected live window,live open)', seen;
  end if;
end $$;
reset role;

-- Signed-in customers: same two, and no writes.
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000c1', false);
do $$
declare n int;
begin
  select count(*) into n from public.home_banners;
  if n <> 2 then raise exception 'customer sees % slides (expected 2)', n; end if;
  begin
    update public.home_banners set active = false where id = '00000000-0000-0000-0000-0000000000b1';
    if found then raise exception 'customer could hide a banner'; end if;
  exception when insufficient_privilege then null;
  end;
  begin
    insert into public.home_banners(image_url) values ('x');
    raise exception 'customer could insert a banner';
  exception when insufficient_privilege then null;
  end;
end $$;

-- Admins: every slide, and writes land.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false);
do $$
declare n int; stamp timestamptz;
begin
  select count(*) into n from public.home_banners;
  if n <> 5 then raise exception 'admin sees % slides (expected 5)', n; end if;
  select updated_at into stamp from public.home_banners where id = '00000000-0000-0000-0000-0000000000b5';
  perform pg_sleep(0.01);
  update public.home_banners set active = true where id = '00000000-0000-0000-0000-0000000000b5';
  if not found then raise exception 'admin update did not apply'; end if;
  if (select updated_at from public.home_banners where id = '00000000-0000-0000-0000-0000000000b5') <= stamp then
    raise exception 'updated_at did not advance';
  end if;
  delete from public.home_banners where id = '00000000-0000-0000-0000-0000000000b4';
  if not found then raise exception 'admin delete did not apply'; end if;
end $$;
reset role;
select set_config('request.jwt.claim.sub', '', false);

-- The newly shown slide is now live for shoppers too.
set role anon;
do $$
declare n int;
begin
  select count(*) into n from public.home_banners;
  if n <> 3 then raise exception 'anon sees % slides after admin changes (expected 3)', n; end if;
end $$;
SQL
echo "home banners: all checks passed"
