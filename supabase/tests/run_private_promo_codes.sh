#!/usr/bin/env bash
# Private promo code regression (migration 0071). `--baseline` skips 0071
# and should fail, reproducing the public promo code listing.
set -euo pipefail
suite_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
test_root="$(mktemp -d "${TMPDIR:-/tmp}/marugen-private-promo.XXXXXX")"
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
create function auth.uid() returns uuid language sql stable as
$$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
grant usage on schema public, auth to anon, authenticated, service_role;
-- Supabase grants new tables and functions to the API roles by default;
-- RLS policies and explicit revokes are what actually restrict them.
alter default privileges in schema public grant all on tables to anon, authenticated, service_role;
alter default privileges in schema public grant all on functions to anon, authenticated, service_role;
create table public.profiles(id uuid primary key, role text not null default 'customer');
create table public.orders(id uuid primary key, user_id uuid, status text not null default 'pending');
create function public.is_admin() returns boolean language sql security definer
set search_path = public stable as $$
  select exists (select 1 from public.profiles where id = auth.uid() and role in ('staff', 'owner'));
$$;
SQL
psql "${args[@]}" -f "$suite_dir/../migrations/0006_promo_codes.sql" >>"$test_root/bootstrap.log"
psql "${args[@]}" -f "$suite_dir/../migrations/0015_promo_code_limits.sql" >>"$test_root/bootstrap.log"
if [[ "${1:-}" != '--baseline' ]]; then
  psql "${args[@]}" -f "$suite_dir/../migrations/0071_private_promo_codes.sql" >>"$test_root/bootstrap.log"
fi
psql "${args[@]}" -f "$suite_dir/private_promo_codes.sql"
echo "private promo codes: all checks passed"
