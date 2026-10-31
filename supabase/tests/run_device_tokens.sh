#!/usr/bin/env bash
# Device push tokens (migration 0073): one owner per token, several devices
# per account, and no direct table access from the app.
set -euo pipefail
suite_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
migration="$suite_dir/../migrations/0073_device_tokens.sql"
test_root="$(mktemp -d "${TMPDIR:-/tmp}/marugen-device-tokens.XXXXXX")"
cleanup() { pg_ctl -D "$test_root/data" -m immediate stop >/dev/null 2>&1 || true; rm -rf -- "$test_root"; }
trap cleanup EXIT
initdb -D "$test_root/data" -A trust -U postgres >"$test_root/init.log"
pg_ctl -D "$test_root/data" -l "$test_root/server.log" -o "-h '' -k '$test_root'" start >/dev/null
args=(-X -h "$test_root" -U postgres -d postgres -v ON_ERROR_STOP=1)
psql "${args[@]}" >"$test_root/bootstrap.log" <<'SQL'
create role anon nologin;
create role authenticated nologin;
create role service_role nologin bypassrls;
create schema auth;
create table auth.users(id uuid primary key, last_sign_in_at timestamptz);
create function auth.uid() returns uuid language sql stable as
$$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
grant usage on schema public, auth to anon, authenticated, service_role;
-- Supabase grants new tables and functions to the API roles by default.
alter default privileges in schema public grant all on tables to anon, authenticated, service_role;
alter default privileges in schema public grant all on functions to anon, authenticated, service_role;
create table public.profiles(
  id uuid primary key references auth.users(id) on delete cascade,
  fcm_token text,
  notifications_enabled boolean not null default true,
  created_at timestamptz not null default now()
);
insert into auth.users values
  ('00000000-0000-0000-0000-0000000000a1', now() - interval '2 days'),
  ('00000000-0000-0000-0000-0000000000b1', now() - interval '1 day'),
  ('00000000-0000-0000-0000-0000000000c1', null);
-- A's sign-out never reached the server before B used the same phone.
insert into public.profiles(id, fcm_token) values
  ('00000000-0000-0000-0000-0000000000a1', 'shared-phone'),
  ('00000000-0000-0000-0000-0000000000b1', 'shared-phone'),
  ('00000000-0000-0000-0000-0000000000c1', 'c-phone');
SQL
psql "${args[@]}" -f "$migration" >>"$test_root/bootstrap.log"
# Applying it again is harmless.
psql "${args[@]}" -f "$migration" >>"$test_root/bootstrap.log"
psql "${args[@]}" -f "$suite_dir/device_tokens.sql" >"$test_root/suite.log"
echo "device tokens: all checks passed"
