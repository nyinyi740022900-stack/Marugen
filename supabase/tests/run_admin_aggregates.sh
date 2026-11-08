#!/usr/bin/env bash
# Admin dashboard and analytics totals (migration 0074): admin-only, past
# PostgREST's 1000-row limit, refunds netted out, Singapore days.
set -euo pipefail
suite_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
test_root="$(mktemp -d "${TMPDIR:-/tmp}/marugen-admin-aggregates.XXXXXX")"
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
alter default privileges in schema public grant all on functions to anon, authenticated, service_role;
create table public.profiles(id uuid primary key, role text not null default 'customer');
create function public.is_admin() returns boolean language sql security definer
set search_path = public stable as $$
  select exists (select 1 from public.profiles where id = auth.uid() and role in ('staff', 'owner'));
$$;
create table public.orders(
  id uuid primary key default gen_random_uuid(),
  status text not null,
  total numeric not null,
  refund_amount numeric,
  created_at timestamptz not null default now()
);
create table public.products(id uuid primary key, name text not null);
create table public.app_visits(
  id uuid primary key default gen_random_uuid(),
  visited_at timestamptz not null default now()
);
create table public.product_views(
  id uuid primary key default gen_random_uuid(),
  product_id uuid references public.products(id) on delete set null,
  viewed_at timestamptz not null default now()
);
SQL
psql "${args[@]}" -f "$suite_dir/../migrations/0074_admin_aggregates.sql" >>"$test_root/bootstrap.log"
psql "${args[@]}" -f "$suite_dir/admin_aggregates.sql" >"$test_root/suite.log"
echo "admin aggregates: all checks passed"
